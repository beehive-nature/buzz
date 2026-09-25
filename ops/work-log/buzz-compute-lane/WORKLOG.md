# Buzz shared-compute lane — work log (recovery point)

Lane owner: Claude Code seat (this lane only; not bGenealogy).
Companion: `RUNBOOK-LIVE.md` (execute when access arrives; do not rediscover).

Evidence classes used below:
- **REPO** = read from a checked-in file at the named commit. Says nothing about deployment.
- **RUNBOOK-CLAIM** = a historical statement in an ops doc. Unverified today.
- **LIVE** = observed on a machine by this lane. **There are none yet.**

## Gate status (2026-09-25)

| Gate | Status | Why |
|---|---|---|
| C0 recovery banked | DONE (this file) | local only, see "Persistence" |
| C1 Astra recovered | BLOCKED | laptop unreachable; her diff not in any reachable repo |
| C2 three nodes observed | BLOCKED | no SSH key/runner for any node; new VPS unidentified |
| C3 compute proven | BLOCKED on C2 | |
| C4 accounting proven | BLOCKED on C3 | |
| C5 x0x canary | BLOCKED on C2 + C3 baseline | |
| C6 PQ map | PARTIAL (source only) | no live handshake evidence |
| C7 architecture ruling | NOT STARTED | needs C3–C5 measurements |

## Sources read (commits)

- `skaists/buzz` main @ `e3a781b` (shallow + 200 depth fetch)
- `beehive-nature/beehive-nature` main @ `b517ddec`
- `saorsa-labs/x0x` checkout @ `e0af580` (Cargo version 0.45.0)

## Findings

1. **Buzz compute transport is mesh-llm over iroh.** REPO: `desktop/src-tauri/Cargo.toml:113-120`
   pins `Mesh-LLM/mesh-llm` tag `v0.75.1` (sdk, host-runtime, client, node, system, events),
   feature-gated `mesh-llm`. Local ports: OpenAI-style ingress `127.0.0.1:9337/v1`,
   management/status `:3131/api/status` (`mesh_llm/mod.rs:45-46,451`).
2. **No checked-in evidence puts x0x in Buzz's inference path.** REPO: no x0x reference in
   `desktop/src-tauri/src` (only base64 noise). x0x in ops appears only as a daemon on the
   Oracle box whose API is reached over SSH (`ops/x0x/LAPTOP-NETWORK.md`, `box-tunnel.sh`).
3. **`MeshServingUsage` is telemetry, not accounting.** REPO: `mesh_llm/usage.rs` projects the
   node's live status payload (inflight, requests, tokens, tok/s, local/remote/endpoint
   attempts, peers). No request/attempt IDs, no requester identity, no persistence, no
   dedupe. UI: `desktop/src/features/mesh-compute/{servingUsage.ts,hooks/useMeshServingUsage.ts,ui/MeshComputeSettingsCard.tsx}`.
   Last upstream touches 2026-08-01..08-11 (#3909, #3735, #5478) — none by Astra.
4. **Oracle's recorded architecture** (RUNBOOK-CLAIM, `ops/bmeshllm/README.md`, 2026-09-15/16):
   `buzz-compute.service` = llama-server @ `172.18.0.1:8090` (bridge only), model
   `qwen2.5-3b-instruct-q4_k_m.gguf`, `--threads 3 --parallel 1`; `buzz-meter-gate.service`
   (per-key bearer gate, `scripts/buzz-meter/gate.js`); `buzz-meter.service` (receipts
   sidecar, `scripts/buzz-meter/meter.py`). Qwen3.5-4B MTP swap attempted and rolled back.
   Box: Ubuntu 24.04 ARM64, host `bnr`, `129.153.202.144` (`ops/x0x/CSPU-2026-09.md`).
5. **buzz-meter is the existing ACCOUNTING/RECEIPT candidate — not a blank slate.** REPO
   (`scripts/buzz-meter/meter.py`): tails llama-server `usage.log` timing lines, emits
   SPEC-SPEND-RECEIPT-1 receipts (`docs/SPEC-SPEND-RECEIPT-1.md`), content-hash
   `receipt_id`, hash-chained via `provenance.prior_receipt_id`, private 0600, free tier
   charges 0 A, hash-chained escrow ledger (`voucher_escrow.py`). Gaps observed in code:
   - `operation.task_id` is the llama-server slot task id → **resets on service restart**;
     it is not a durable job ID.
   - dedupe `seen_tasks` is in-memory only; file offset is persisted (`state/offset`).
   - attribution is the constant `key_ref() = "estate-compute-key-1"` in the P1 path;
     P2 per-key gate exists in `gate.js` — how gate keys reach receipts: **unverified**.
   - receipt carries no serving node, model, request ID, attempt ID, transport, or outcome.
   - it only sees jobs executed by `buzz-compute`'s llama-server. **Jobs served by a mesh-llm
     node (e.g. the laptop) produce no buzz-meter receipt** unless something else feeds it.
6. **Three metering surfaces exist or are suspected:** `MeshServingUsage` (telemetry),
   `buzz-meter` (accounting+receipts, Oracle-only), Astra's Settings work (unknown).
   Rule: no fourth meter; reconcile after C1.
7. **x0x v0.45.0 has a real forward transport.** REPO: `POST/GET/DELETE /forwards`
   (`src/api/mod.rs:1703-1722`, CLI `x0x forward add|list|remove`), per-flow TCP over a QUIC
   peer stream, loopback targets only, gated by connect ACL on both ends
   (`docs/connect-acl.md`); ForwardV2 signs `(target, opener agent, recipient machine,
   issued_at)` with ML-DSA-65, 60 s replay window. Oracle ran 0.41.2→0.45.0 (RUNBOOK-CLAIM).
   Note: llama-server binds the docker bridge, not loopback — a forward target needs a
   loopback bind or relay (config change, canary only).
8. **PQ: capability in source, no live evidence.** ant-quic advertises ML-KEM-768/ML-DSA-65.
   x0x source exposes **no negotiated-KEX diagnostic** (grep for kex/negotiated found none);
   live proof needs ant-quic handshake logging, qlog, or a capture of the handshake flights.
   Other hops (SSH laptop→box, iroh in mesh-llm, HTTP inside hosts) are unclassified.
9. **Astra's newest work is not in reachable repos.** `skaists/buzz` has 19 branches, none
   compute/metering. `beehive-nature` Astra branches: `codex/astra-audit-2026-09-06`,
   `codex/astra-ux-arrival-2026-09-19` (not compute). Assume it lives uncommitted on the
   Windows laptop until shown otherwise.
10. **All deployed-state statements are unverified.** The "new VPS" is not named in anything read.

## Missing access (smallest unlock per node)

| Node | Needed | Why not available |
|---|---|---|
| Windows laptop | an operator session (or a self-hosted runner / Remote Control) able to run the PowerShell block in `RUNBOOK-LIVE.md` §1–2 and paste back outputs | cloud container cannot route to a home LAN; SSH key "stays in WSL" by design |
| Oracle VPS | SSH as `ubuntu@129.153.202.144` from this environment: a deploy key added as an environment secret + network policy allowing TCP 22 to that host — **or** a self-hosted runner on the box | `~/.ssh` empty; no key in env |
| New VPS | its identity (host/IP, provider, user) + the same key/runner mechanism | not named anywhere read |

## Persistence

This file lives in an ephemeral cloud container. It is **not pushed**. If it must survive
this container, a push target needs authorizing (candidate: branch
`claude-lovis/sweet-planck-cx1pq4` on `beehive-nature/buzz`, which is empty), or copy it out.

## Evidence 1 — first live signal (user screenshot, laptop Buzz desktop, 2026-09-24 20:18–20:35 local)

Class: **USER-SUPPLIED SCREENSHOT** (not observed by this lane directly).

- Agent `bQunsloth3.6MAX`, added by LoVis as "local shared compute agent", in #NOMAD ALLIANCE.
- Model string: `unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_XL` (35B MoE, ~3B active). This is
  NOT the qwen2.5-3b recorded on Oracle; which node served it is **not shown**.
- Turn error 20:32: `-32000 llm: … exhausted retries: 504 Gateway Timeout:
  {"error":{"message":"chat_completion timed out after 300000 ms",…,"code":"timeout"}}
  (cumulative 872.6369124s, 3 attempts)`. Message was re-posted 20:33 (second full job likely started).

Source trace (REPO, exact):
- The 504 body is produced by mesh-llm's OpenAI frontend: `crates/openai-frontend/src/router.rs:98`
  `DEFAULT_BACKEND_TIMEOUT = 300 s`, wrapped around the whole **non-streaming** `chat_completion`
  (`router.rs:226-228`, `598`); on timeout it calls `context.cancel()` and returns 504 `timeout`.
  (mesh-llm tag v0.75.1, the Buzz pin.)
- The retry is Buzz's: `crates/buzz-agent/src/llm.rs:1610` `MAX_RETRIES = 3`; `:1902-1920` retries
  **every** 5xx including this deterministic 504, then emits "exhausted retries".
  buzz-agent sends `"stream": false` (`llm.rs:769`, `:2132`).

Consequences:
1. A job that needs >300 s of non-streaming inference can never succeed; it's re-run identically
   3× → ~15 min wall, ~3× compute burned, same failure. (The frontend cancels each attempt on
   timeout, so attempts should not overlap — **unverified** whether the backend actually stops.)
2. This is precisely the JOB→ATTEMPT case for C4: 1 job, 3 attempts, outcome=timeout, billable=0,
   compute consumed ≈ 3×300 s. No current meter records it (`MeshServingUsage` is counters only;
   buzz-meter only sees Oracle's llama-server).
3. Unknown, needed before any fix: prompt tokens (agent system prompt + tools), serving node,
   backend device (CPU vs GPU/shared memory), prefill vs decode rate. Probe on laptop:
   `curl.exe -s http://127.0.0.1:3131/api/status` right after a failure, plus the mesh-llm log lines
   for that request.

Candidate fixes (NOT implemented — decide after the probe):
- buzz-agent: do not retry a 504 whose body `code` is `timeout` (surface immediately; one attempt of
  compute instead of three). Small, local, testable.
- Use streaming for agent turns so the 300 s cap applies to time-to-stream rather than full
  generation — larger change, touches response parsing.
- Model choice for this agent from measured tok/s, not size.

## Accounting invariant (ruled 2026-09-25) — logical job != attempt

Evidence 1 falsified `one request = one receipt = one billable execution`.
Required model for the eventual meter (NOT implemented; recover Astra first):
`JOB → ATTEMPT 1 → (ATTEMPT 2..n) → OUTCOME → USAGE → RECEIPT`.
A failed attempt can consume compute without becoming a payable job; usage is recorded
per attempt, billability is decided per job, and a retry never creates a second payable job.

## Holds (ruled 2026-09-25)
Streaming conversion, model-routing changes, raising the 300 s timeout, meter implementation,
x0x changes — all HOLD pending live evidence / C1. Authorized: buzz-agent fix 1 only
(mesh-llm `504` + `error.code == "timeout"` → terminal after attempt 1).

## Final state (ruled ACCEPTED / STOP, 2026-09-25)

- C0 recovery packet: `d2f6da125981f3441e06070c50e0ccdf21c781fa`
- Escrow commit (patch): `fdb1774dc8a1ae78a3dd467aad93a49e20f80380`
- Source base: `skaists/buzz@e3a781b653f9031634ae905a5cfc5198e201683e`
- Original local implementation commit: `69807f1ac8a5f067469db700fe0728c761f43fab`
- Patch: `patches/0001-fix-buzz-agent-don-t-retry-a-backend-s-terminal-504-.patch`
  sha256 `351f62921e240b368b586f141926b91d415ff57a05c8cc5e6478fc14d6094247`
- buzz-agent 596/596 PASS; targeted timeout regression PASS; negative control (fix disabled) FAIL as
  expected; fmt PASS; clippy `-D warnings` PASS. Full `just ci` not run (next owner).

Next owner — fresh session sourced on `skaists/buzz`:
1. verify patch sha256 and base `e3a781b`; 2. `git am` the exact patch; 3. confirm the diff matches
(one file, `crates/buzz-agent/src/llm.rs`, +132/-0); 4. run repo-required CI (`just ci`);
5. push + open the normal review path; 6. send to bFUzZ. Do not rewrite unless apply fails or review
finds a defect.

Gates: C1/C2 BLOCKED (live access). C3–C5 unopened. C6 source-level only. All HOLDs remain.

## Evidence 2 — laptop mesh-llm status (operator paste, 2026-09-24 ~22:47 local)

Class: **LIVE via operator paste** of `curl.exe -s http://127.0.0.1:3131/api/status` (invite `token` field
omitted here). Taken while the "?" test turn was in flight.

- mesh-llm `0.75.1` (latest `0.76.2`); `release_attestation: missing`; owner verified, hostname `loVis`.
- Node: `serving`, `is_host: true`, `is_client: false`, backend `skippy`, `llama_ready: true`.
- Model: `unsloth/Qwen3.6-35B-A3B-MTP-GGUF@main:UD-Q4_K_XL`, `context_length: 131072`, instance port 59589.
  Also available: `unsloth/gemma-4-26B-A4B-it-GGUF:UD-Q4_K_M`.
- GPU: **Intel Iris Xe (integrated), `my_is_soc: true`, 34.0 GB "VRAM" = shared system memory.**
- **`peers: []`** — the laptop's mesh has no other nodes. mesh `buzz-community-25c0…`,
  `publication_state: private`, `nostr_discovery: false`. So no cross-machine path exists in this mesh now;
  the VPSs are not peers of the laptop here.
- `inflight_requests: 1`; `routing_metrics` all zero (request_count 0, completion_tokens 0,
  attempt_timeout_count 0) → completed/failed/in-flight work is not reflected yet; the Settings
  telemetry would show zero for the failing jobs.
- `openai_guardrails.mode: disabled`.

Inference (unverified): the agent turn is served locally on an iGPU with shared memory; the ~300 s
timeouts are most plausibly prompt prefill of a large agent prompt on this device. Needs: prompt size
(ACP event #42) and a post-turn status snapshot (avg_attempt_ms, completion_tokens_observed).

## Evidence 3 — agent log + Share compute switch (operator paste, 2026-09-24 ~23:05 local, UTC-6)

- Buzz desktop `v0.5.21`. Share compute: laptop switched to `unsloth/gemma-4-E4B-it-GGUF:Q4_K_M` (4.6 GB,
  app-"Recommended" for Iris Xe / 32 GB AI memory); status `Starting…`; Max VRAM no limit.
- buzz-acp start line (04:43:22Z): `agents=10`, `respond_to=anyone`, `permission_mode=bypassPermissions`,
  `max_turn=7200s`, `idle_timeout=900s`, `subscribe=Mentions`, model still
  `unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_XL`, relay `wss://relay2.skaists.dev`. `discovered 0 channel(s)`
  WARN at start (mentions still delivered). Stopped 05:07:26Z (model switch).
- Last error: 503 `model 'unsloth/gemma-4-E4B-it-GGUF:Q4_K_M' is unavailable locally (loading or draining)`,
  surfaced by Buzz as a "network path problem between this machine and the host" — **misleading copy**:
  the cause is local model load, not the network. (Bug candidate, not in this lane's scope.)
- Outcome of the 22:45 "?" test turn: not reported.
