# ai-memory + LiteLLM (Bedrock) reference setup

Proof of concept for shared, per-repository AI memory
([ai-memory](https://github.com/akitaonrails/ai-memory) v2.2.1), where every
model call, from Claude Code and from ai-memory itself, goes through the
shared **LiteLLM** gateway to **Claude on Amazon Bedrock**.

Design, security controls, tenancy and rollout: [docs/architecture.md](docs/architecture.md).

## Layout

| Path | Purpose |
|---|---|
| `.ai-memory.toml` | This repo's memory scope marker (what every repo commits) |
| `templates/ai-memory.toml.example` | Marker template for other repos |
| `local/` | Docker Compose replica: LiteLLM (+Postgres) → Bedrock, ai-memory → LiteLLM |
| `scripts/bootstrap-keys.sh` | Issues LiteLLM + ai-memory keys (user provisioning flow) |
| `scripts/verify.sh` | End-to-end checks: gateway, auth, persistence, project isolation |
| `clients/managed-settings*.json` | Claude Code managed settings (Anthropic-format or Bedrock pass-through) |
| `clients/claude-gateway-key.sh` | `apiKeyHelper` reading the LiteLLM key from Secrets Manager |
| `clients/setup-developer.sh` | Wires hooks + session-aware MCP to the team's memory server |
| `deploy/eks/` | Kustomize base + per-tenant overlay (StatefulSet, internal ALB, NetworkPolicy, External Secrets, S3 backups) |
| `deploy/eks/agent-job-example.yaml` | Headless Claude Code job in EKS using gateway + shared memory |
| `deploy/ec2/user-data.sh` | EC2 dev/agent host bootstrap |
| `aws-local/` | The same architecture on emulated AWS (floci), with the AWS layer in OpenTofu: EKS, EC2, ECR, Secrets Manager, S3, Bedrock. Produces an evidence report |
| `scripts/mcp-call.sh` | Call one ai-memory MCP tool (what users and agents use; CLI page commands are root-only) |

## Local quickstart

Needs Docker and an AWS profile with Bedrock access to the Claude models.

```bash
cd local
cp .env.example .env            # fill secrets + Bedrock inference-profile IDs
./render-litellm-config.sh
docker compose up -d
../scripts/bootstrap-keys.sh jdoe jdoe@example.com team-a
export GATEWAY_KEY=... MEMORY_KEY=...   # printed by bootstrap
../scripts/verify.sh
```

Point your own Claude Code at the local stack:

```bash
export ANTHROPIC_BASE_URL=http://127.0.0.1:4000
export ANTHROPIC_AUTH_TOKEN=$GATEWAY_KEY
AI_MEMORY_SERVER_URL=http://127.0.0.1:49375 AI_MEMORY_USER=jdoe \
  clients/setup-developer.sh      # or pass the key directly for the POC
```

Then in Claude Code, `/status` should show the gateway base URL and the
`ANTHROPIC_AUTH_TOKEN` credential.

## Checking that memory persists and is shared per project

| Question | Check |
|---|---|
| Server up, counts growing? | `ai-memory status` (sessions / observations increase while you work) |
| Which projects exist? | `curl -H "Authorization: Bearer $KEY" $SERVER/api/v1/projects` |
| Is a note recallable? | `ai-memory search <term> --workspace <ws> --project <repo>` or the `memory_query` MCP tool |
| Shared between people? | Write a page as user A, search as user B in the same project |
| Isolated between repos? | Same search with another `--project` returns nothing |
| Survives restarts? | `docker compose restart ai-memory`, search again (`verify.sh` step 7) |
| Consolidation via gateway? | `ai-memory llm-test --provider openai-compat --model "$AI_MEMORY_LLM_MODEL" --prompt ping` in the server, then LiteLLM spend for the ai-memory service key |
| Capture policy? | `printf '{"cwd":"%s"}' "$PWD" \| ai-memory hook --event user-prompt-submit --agent claude-code --server-url "$AI_MEMORY_SERVER_URL" --check-capture` |

## Status

- The architecture has been run end to end on **emulated AWS** (`aws-local/`,
  powered by [floci](https://github.com/floci-io/floci)): a real k3s cluster,
  real EC2 guests with IMDS, ECR, Secrets Manager, S3 and External Secrets.
  The latest run passes 32/32 checks — see `aws-local/evidence/`. The AWS
  resources there are OpenTofu, so the same stacks describe real AWS.
  What the manifests in `deploy/eks/base` apply there is what they apply in EKS.
- Not yet run against a real AWS account: Bedrock answers are emulated (stubbed
  or proxied), and the ALB and Pod Identity have local stand-ins.
  Placeholders are in `UPPER_CASE`.
- Operational findings from those runs are in
  [docs/architecture.md](docs/architecture.md) section 10.
- Bedrock model IDs are deliberately not hard-coded: copy the inference
  profile IDs from `aws bedrock list-inference-profiles`.
