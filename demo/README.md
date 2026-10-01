# Shared project memory: three people, two machines

A scripted demo on top of [`aws-local/`](../aws-local): a decision one person
makes in a Claude Code session reaches the next person's session on another
machine, and a newcomer gets every decision when onboarding.

| Who | Machine | What they do |
|---|---|---|
| **alice** | laptop (this Mac, isolated Claude profile) | Starts the cart total; settles how money is represented |
| **bob** | EC2 host (the floci guest) | Implements refunds, without Alice's code; follows her decision |
| **carol** | laptop (second profile) | Joins later, knows nothing, asks to be onboarded |

```
alice (Mac) ──hooks + MCP──► relay :14375 ─┐
carol (Mac) ──hooks + MCP──► relay :14375 ─┼─► NodePort 30374 ─► Service ─► ai-memory-0 ─► SQLite on PVC
bob  (EC2)  ──hooks + MCP──────────────────┘     (ALB stand-in)   (NetworkPolicy: VPC range only)
```

All three use the same project, `poc/tiny-shop`: the checkout's
[`.ai-memory.toml`](seed/tiny-shop/.ai-memory.toml) says so, wherever it
lives. Each person has their own `aim_` key (in Secrets Manager), so every
page is attributed.

**Inference is each user's own Claude login.** Bedrock in aws-local only
returns a stub, so the demo skips the gateway for inference. The EC2 host's
managed settings are switched to that mode by `setup.sh` (the gateway version
is kept at `/etc/claude-code/managed-settings.json.gateway`). The memory plane
is the real architecture.

## Run it

Needs the aws-local stack and a Claude subscription (Pro/Max) or Console account.

```bash
aws-local/up.sh      # skip if it is already up
demo/setup.sh        # identities, laptop profiles, bob's account on the EC2 host
```

`setup.sh` is idempotent. It creates `~/ai-memory-demo/` (one folder per laptop
user, plus a checksum-verified native `ai-memory` 2.2.1), a relay container
`aimem-laptop-lb`, and a `bob` account on the EC2 guest with Claude Code
installed. Your own `~/.claude` and ai-memory setup are not touched.

### Act 1: Alice makes a decision (laptop)

```bash
demo/laptop.sh alice
```

First run only: pick a theme, log in (`/login`), trust the folder. Then:

> Let's do backlog item 1, cart total and the SAVE10 code. Before any code, a
> team-wide decision: money is integer cents everywhere. Parse the catalog's
> price strings with Decimal once, at load time, never use float, and round
> percentage discounts with ROUND_HALF_EVEN. Record that decision for the
> team, then implement it with tests.

Approve the `memory_write_page` call when Claude asks. The repo's
[`CLAUDE.md`](seed/tiny-shop/CLAUDE.md) tells it to file settled decisions as
pinned pages under `decisions/`. Exit, then look at what memory holds:

```bash
demo/decisions.sh
```

### Act 2: Bob benefits from it (EC2 host)

```bash
demo/ec2.sh bob
```

First run only: log in by opening the printed URL and pasting the code back. Then:

> Implement backlog item 2: partial refunds.

No hint about money. Bob's checkout does not have Alice's code (it is the
seed, as if her branch were not merged yet). His session starts with the
project brief injected by the SessionStart hook, which carries Alice's
pinned decision, so refunds come out in integer cents with HALF_EVEN
rounding. Ask him "why cents?" and he will point at Alice's decision.

To see for yourself that the code did not travel:

```bash
demo/ec2.sh bob 'git log --oneline; ls shop'
```

Optional: have Bob settle something of his own ("refunds are separate records;
never mutate a paid order; record that"), so the next act has two authors.

### Act 3: Carol onboards (laptop, later)

```bash
demo/laptop.sh carol
```

> I just joined this project. Before I touch anything: what key decisions has
> the team made, who made them, and why?

Then give her real work, e.g. "Implement backlog item 3, receipts", and watch
the amounts render from cents.

## How the decision travels

1. Alice's Claude calls `memory_write_page` (MCP) with `pinned: true` under
   `decisions/`. The server attributes it to the owner of Alice's key.
2. When Bob's or Carol's session starts, the `SessionStart` hook sends the
   repository's marker (`workspace`, `project`, `[briefing]`) to the server and
   prints the returned brief. Claude Code adds that text to the session:
   pinned pages in full, `_rules/`, and recent page titles.
3. `CLAUDE.md` also tells the agent to call `memory_briefing` with
   `settled_first` before changing code, and `memory_query` for details.

Every session also leaves a summary page (`sessions/<id>.md`, built without an
LLM), so later briefs list what others worked on.

## Limits

- **Recording is up to the agent.** Decisions are saved because `CLAUDE.md`
  asks for it. If one is missed, say "record that decision".
- **No LLM consolidation here.** Turning whole transcripts into pages goes
  through LiteLLM, whose Bedrock is a stub in aws-local. Don't call
  `memory_consolidate` in the demo: it would store the stub reply.
- **Retrieved memory is untrusted data.** The brief says so to the agent. A
  wrong decision page spreads just as well as a right one; fix it at the source
  (edit or delete the page).
- **One instance, one trust boundary.** Everyone with a key to `team-a` can
  read `tiny-shop`. See `docs/architecture.md` section 3.

## Reset and teardown

```bash
demo/reset.sh        # forget poc/tiny-shop, fresh checkouts; logins stay
aws-local/down.sh    # everything, including the relay
rm -rf ~/ai-memory-demo
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `aws-local/up.sh` stalls at "Cluster status is CREATING" after a Docker or Mac restart | The k3s node's IP changed and it will not start. `aws-local/down.sh && aws-local/up.sh`. |
| No "ai-memory: project brief" at the start of a laptop session | Check the relay: `docker ps --filter name=aimem-laptop-lb`. `demo/laptop.sh` restarts it. |
| The brief is missing a decision | It is not pinned, or not under `decisions/`. `demo/decisions.sh` lists what exists. |
| Hooks on a Mac send nothing | They must run the native binary in `~/ai-memory-demo/.ai-memory-*`. The upstream `ai-memory` Docker wrapper runs the CLI in a container, where `127.0.0.1` is not your Mac. |
