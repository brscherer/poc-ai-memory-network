# aws-local: the reference architecture on emulated AWS

Runs the architecture from [../docs/architecture.md](../docs/architecture.md) on a
laptop, using [floci](https://github.com/floci-io/floci) as the AWS emulator. The
goal is **evidence**: the production manifests in `deploy/eks/base` are applied
unchanged to a real Kubernetes cluster, and every hop is tested by
`90-verify.sh`, which writes a report to `evidence/`.

## What runs where

| Production | Here | Fidelity |
|---|---|---|
| EKS cluster | floci EKS "real mode" → k3s in Docker; `kubectl` authenticates with `aws eks get-token` | Real Kubernetes API, NetworkPolicy, PVCs |
| EC2 dev/agent host | floci EC2 → Ubuntu 24.04 container, instance profile, user-data | Real guest + IMDS; see limitations |
| ECR mirror | floci ECR → real `registry:2`; immutable tag | Real push and digest |
| Secrets Manager + External Secrets Operator | floci Secrets Manager + ESO (Helm) with custom endpoint | Real ESO sync |
| S3 backups | floci S3 (versioned bucket) | Real objects |
| LiteLLM gateway | LiteLLM + Postgres in namespace `ai-gateway` | Real LiteLLM, virtual keys, teams |
| Amazon Bedrock | floci Bedrock Runtime (Converse) | **Stub reply** by default; `BEDROCK_BACKEND=proxy` forwards to an OpenAI-compatible server (e.g. Ollama) |
| ai-memory tenant | `deploy/eks/base` + `k8s/ai-memory` overlay | Same manifests as production |
| Internal ALB | NodePort (`30374` memory, `30400` gateway) on the k3s node | Stand-in |
| Pod Identity / IRSA | Static IAM keys from Secrets Manager | Stand-in |

## Run it

Needs Docker (≈6 GB free memory), `tofu`, `aws`, `kubectl`, `helm`, `jq`.

```bash
aws-local/up.sh        # tofu stacks + glue scripts, idempotent
aws-local/90-verify.sh # evidence report -> aws-local/evidence/
aws-local/down.sh      # destroys the stacks, then floci and its data
```

Credentials, the kubeconfig and Tofu state live in `aws-local/.state/` and
`aws-local/tofu/*/terraform.tfstate` (both git-ignored).

To poke around:

```bash
export KUBECONFIG=aws-local/.state/kubeconfig
kubectl get pods -A
open http://127.0.0.1:4566/_floci/ui          # floci console
```

## Infrastructure as code

AWS resources are OpenTofu; the scripts cover only what is not an AWS API
call. Three stacks, because a provider cannot be configured from a cluster
that the same apply is still creating:

| Stack | Contains | Applied |
|---|---|---|
| `tofu/aws` | IAM (admin user, roles, instance profile), generated secrets, S3 buckets + release objects, ECR repository, VPC/subnets, EKS cluster | first |
| `tofu/cluster` | In-cluster Service for the AWS endpoint, External Secrets (Helm) wired to floci, `ClusterSecretStore`, the namespaces the policy checks use | after the cluster answers |
| `tofu/host` | The EC2 developer/agent host and its user-data | last: the guest calls the gateway and ai-memory while booting |

Against real AWS the only differences are the provider `endpoints` block, the
Pod Identity stand-in, and the AMI/instance type.

| Script | Why it is not Tofu |
|---|---|
| `10-artifacts.sh` | Downloads and checksums upstream release tarballs |
| `20-kubeconfig.sh` | Turns stack outputs into a kubeconfig (`aws eks update-kubeconfig`) |
| `30-images.sh` | Drives the local Docker daemon: ECR push, image load into the node |
| `40-platform.sh` | Helm installs that wait for rollout: floci expires an EKS token after 60 s, and a Tofu provider resolves its token once per apply |
| `50-gateway.sh`, `60-memory.sh` | `kubectl apply -k` of the kustomize overlays |
| `70-keys.sh` | Credentials only the running services can issue (LiteLLM keys, ai-memory users) |
| `85-ec2-wait.sh` | Waits for the guest's user-data to finish |
| `90-verify.sh` | The evidence run |

## Emulation caveats

These are properties of the emulator, not of the design:

- **Bedrock replies are stubbed.** `Converse` returns a fixed string, so it
  proves routing and auth, not model behaviour. For real answers set
  `BEDROCK_BACKEND=proxy` + `BEDROCK_PROXY_URL` (e.g. Ollama) in `.env`;
  `InvokeModel` is never proxied.
- **IMDS hands out floci's static keys.** The guest correctly uses the
  instance-role credential chain and the role is visible in IMDS, but STS
  reports `root`, so IAM policy is not actually enforced on it.
- **No ALB and no Pod Identity**: NodePort and static keys stand in.
- **NetworkPolicy is enforced but syncs on a delay.** k3s programs policies
  from pod-IP sets, so a pod created seconds earlier is not yet covered;
  `90-verify.sh` retries its network checks for this reason.
- **k3s ships no ingress controller here** (floci starts it with
  `--disable=traefik`).
- **Debug pods must not wear the app's Service labels.** The NetworkPolicy
  selects `app.kubernetes.io/name=ai-memory`, so a probe pod needs that label
  — which also made it a Service endpoint until the Service selector was
  narrowed with `app.kubernetes.io/component=server`.
- First run pulls several GB of images; the LiteLLM image alone took ~20
  minutes on a home connection.
