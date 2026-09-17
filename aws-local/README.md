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

Needs Docker (≈6 GB free memory), `aws`, `kubectl`, `helm`, `jq`.

```bash
aws-local/up.sh        # 10-iam … 80-ec2, idempotent; first run pulls several GB
aws-local/90-verify.sh # evidence report -> aws-local/evidence/
aws-local/down.sh      # removes everything, including floci data
```

Individual steps can be re-run on their own (`aws-local/60-memory.sh`, …).
Credentials and the kubeconfig live in `aws-local/.state/` (git-ignored).

To poke around:

```bash
export KUBECONFIG=aws-local/.state/kubeconfig
kubectl get pods -A
open http://127.0.0.1:4566/_floci/ui          # floci console
```

## Steps

| Script | Does |
|---|---|
| `10-iam.sh` | Admin IAM user (EKS auth), cluster role, `ai-host` role + instance profile |
| `20-eks.sh` | `aws eks create-cluster`, kubeconfig via `aws eks update-kubeconfig` |
| `30-seed.sh` | Secrets, versioned backup bucket, ECR mirror push, image load into the node |
| `40-platform.sh` | In-cluster Service for the AWS endpoint, ESO + `ClusterSecretStore` |
| `50-gateway.sh` | LiteLLM + Postgres, config from ESO, Bedrock endpoint = floci |
| `60-memory.sh` | ai-memory tenant `team-a` from the production base |
| `70-keys.sh` | Service key for ai-memory, developer and EC2-host identities, all stored in Secrets Manager |
| `80-ec2.sh` | EC2 host: instance profile → secrets → managed settings → hooks → gateway call → shared note |
| `90-verify.sh` | End-to-end checks and the evidence report |

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
- First run pulls several GB of images; the LiteLLM image alone took ~20
  minutes on a home connection.
