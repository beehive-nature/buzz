# Buzz shared-compute lane — live-access runbook

Execute in order. Every step before §5 is **read-only**. Save every output under an
evidence dir per node (`evidence/<node>/<UTC-stamp>/`) and `sha256sum` it into `MANIFEST.sha256`.
Never print tokens/keys: when a command needs `api-token`, read it into a variable, never echo.
Label every recorded fact LIVE / REPO / RUNBOOK-CLAIM.

## 1. C1 — recover Astra (laptop, PowerShell). READ-ONLY. Do this first.

Forbidden: `reset`, `checkout`, `clean`, `stash push/pop`, `pull`, `rebase`, IDE "discard".

```powershell
$E = "$HOME\buzz-lane-evidence\$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"; mkdir $E | Out-Null
# find candidate Buzz trees (also check WSL: \\wsl$\<distro>\home\...)
Get-ChildItem $HOME -Directory -Recurse -Depth 4 -Filter .git -ErrorAction SilentlyContinue |
  ForEach-Object { $_.Parent.FullName } | Tee-Object "$E\git-roots.txt"
$R = "<chosen buzz root>"
git -C $R remote -v                         > "$E\remotes.txt"
git -C $R status --porcelain=v2 --branch    > "$E\status.txt"
git -C $R branch -vv --all                  > "$E\branches.txt"
git -C $R worktree list                     > "$E\worktrees.txt"
git -C $R stash list                        > "$E\stashes.txt"
git -C $R reflog -n 100 --date=iso          > "$E\reflog.txt"
git -C $R log --oneline -30 --all --date-order > "$E\log-all.txt"
git -C $R diff --binary HEAD                > "$E\tracked.diff"      # staged + unstaged
git -C $R ls-files --others --exclude-standard > "$E\untracked.txt"
# copy untracked files verbatim (no git state change)
Get-Content "$E\untracked.txt" | ForEach-Object { $d = Join-Path "$E\untracked" $_;
  New-Item -ItemType Directory -Force (Split-Path $d) | Out-Null; Copy-Item (Join-Path $R $_) $d }
# stashes as patches, if any
git -C $R stash list --format=%gd | ForEach-Object { git -C $R stash show -p --binary $_ > "$E\$($_ -replace '[{}@]','_').patch" }
Get-ChildItem $E -Recurse -File | Get-FileHash -Algorithm SHA256 | Format-Table -Auto | Out-File "$E\MANIFEST.sha256"
```

Then locate the work: `Select-String -Path "$E\tracked.diff","$E\untracked.txt" -Pattern 'mesh|meter|usage|settings|compute|receipt'`.
Record: files touched, what Settings shows, where its numbers come from (which of
`MeshServingUsage` / `buzz-meter` / new store). Only after the evidence dir is hashed may
anyone modify that tree — and preferably on a new branch in a separate worktree.

## 2. C2 — inventory. Linux nodes (Oracle, new VPS)

```bash
E=~/buzz-lane-evidence/$(date -u +%Y%m%dT%H%M%SZ); mkdir -p $E; cd $E
{ hostnamectl; uname -a; cat /etc/os-release; } > os.txt
lscpu > cpu.txt; free -b > mem.txt; df -h / /opt /var/lib 2>/dev/null > disk.txt
{ nvidia-smi 2>&1; lspci 2>/dev/null | grep -iE 'vga|3d|display'; } > gpu.txt
systemctl list-units --type=service --state=running --no-pager > services.txt
systemctl list-units --no-pager 'buzz-*' 'x0x*' 'mesh*' 'llama*' > lane-units.txt
for u in buzz-compute buzz-meter buzz-meter-gate x0x; do systemctl cat $u > unit-$u.txt 2>&1; done
sudo ss -ltnup > listen.txt                  # bind addresses + ports
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}' > docker.txt 2>&1
for b in /usr/local/bin/x0xd /usr/local/bin/x0x /opt/buzz-compute/src/build/bin/llama-server $(command -v mesh-llm); do
  [ -x "$b" ] && { echo "$b"; "$b" --version 2>&1 | head -2; sha256sum "$b"; }; done > binaries.txt
ls -l /opt/buzz-compute/models/ > models.txt; sha256sum /opt/buzz-compute/models/*.gguf >> models.txt
curl -s -m5 http://172.18.0.1:8090/health > llama-health.json; curl -s -m5 http://172.18.0.1:8090/v1/models > llama-models.json
curl -s -m5 http://127.0.0.1:3131/api/status > mesh-status.json   # mesh-llm, if present
T=$(sudo cat /var/lib/x0x/data/api-token); curl -s -m5 -H "Authorization: Bearer $T" http://127.0.0.1:12700/health > x0x-health.json; unset T
ls /opt/buzz-meter/receipts | wc -l > meter-count.txt; sudo cat /opt/buzz-meter/state/offset /opt/buzz-meter/state/receipt-chain-tip >> meter-count.txt
sha256sum * > MANIFEST.sha256
```
Local inference smoke (synthetic prompt, `max_tokens` 16) against whatever serves; record
`usage` and `timings` fields only.

## 2b. C2 — laptop (PowerShell)

```powershell
Get-CimInstance Win32_ComputerSystem | Select Name,TotalPhysicalMemory
Get-CimInstance Win32_Processor | Select Name,NumberOfCores,NumberOfLogicalProcessors
Get-CimInstance Win32_VideoController | Select Name,AdapterRAM,DriverVersion   # AdapterRAM caps at 4 GB; confirm in dxdiag /t
Get-PSDrive C; Get-NetTCPConnection -State Listen | Sort LocalPort | Select LocalAddress,LocalPort,OwningProcess
Get-Process | ? { $_.Name -match 'buzz|mesh|llama|x0x' } | Select Name,Id,Path,WS
curl.exe -s -m5 http://127.0.0.1:3131/api/status   # mesh-llm status (serve mode, model, peers, routing metrics)
curl.exe -s -m5 http://127.0.0.1:9337/v1/models
```
Plus Buzz app version (About), installed Qwen file + hash, backend (CPU/Vulkan/CUDA) from the
mesh-llm status or logs. **No x0x daemon is started on the laptop** (shared-network law).

## 3. C3 — one cross-machine Qwen job over the EXISTING route

1. Snapshot `:3131/api/status` on requester AND server (before).
2. From requester: `POST 127.0.0.1:9337/v1/chat/completions` with the served model id,
   `stream: true`, synthetic prompt containing a unique nonce, header `X-Request-Id: c3-<uuid>`,
   `max_tokens` 64. Record wall-clock start, first-byte time, end, response `usage`.
3. Snapshot status again (after). Proof of serving node = the SERVER's
   `remote_attempts`/`requests_served`/`tokens_served` delta matches this job's tokens,
   plus the server's inference log timing line at that timestamp, plus the endpoint_id that
   answered. One job at a time; nothing else in flight.
4. Repeat with the laptop as server (requester = a VPS) — the laptop-serves case is required.
5. Measure on the server: TTFT, decode tok/s, peak RSS/VRAM, CPU; laptop desktop stays usable.
6. Failure tests (synthetic only): server offline mid-request, client cancel, timeout. Confirm
   **no paid fallback** and no second execution.

## 4. C4 — reconcile meters before building

Answer from evidence: did the C3 job produce a buzz-meter receipt? (Only if it ran on
`buzz-compute`'s llama-server.) What did Astra's Settings show? Map each surface to exactly one
role: TELEMETRY (`MeshServingUsage`), ACCOUNTING+RECEIPT (candidate: buzz-meter/SPEC-SPEND-RECEIPT-1),
Astra's (TBD). Known buzz-meter gaps to decide on: non-durable `task_id`, in-memory dedupe,
constant `key_ref`, no node/model/request/attempt/outcome fields. Receipt target shape:
`JOB(request_id) → ATTEMPT(attempt_id) → EXECUTION(node, model) → USAGE(in/out tokens, timing, outcome) → RECEIPT(hash, prior, meter version)`;
billable identity = `request_id`, not attempt; settlement stays out.

## 5. C5 — x0x forward canary, VPS A → VPS B (disabled by default, reversible)

Prereq: both VPSs run x0xd ≥0.45.0 with trust set both ways and connect ACL on both ends.
1. On B: a loopback-bound inference endpoint (e.g. a second llama-server or socat relay on
   `127.0.0.1:18090` → the real server). Do **not** rebind production.
2. On B ACL: allow exactly A's `(agent_id, machine_id)` → `127.0.0.1:18090`. Keep a copy of the
   previous ACL for rollback.
3. On A: `x0x forward add` (`POST /forwards`) local `127.0.0.1:28090` → peer B, target port 18090.
4. Run the same workload through `127.0.0.1:28090` and through the existing route: N=20 jobs,
   latency, TTFT, tok/s, CPU/RAM of x0xd, IP accounting bytes (`systemctl show x0x -p IPIngressBytes,IPEgressBytes`).
5. Tests: wrong-agent denied; stream intact; kill B's x0xd mid-stream (behavior + reconnect);
   replay a captured ForwardV2 header after 60 s (expect reject); downgrade (V1 peer) behavior.
Rollback: `x0x forward remove`, restore ACL, stop relay. Nothing else changes.

## 6. C6 — PQ hop map (fill with evidence type per row)

`hop | transport | authentication | key establishment | PQ algorithm | observed/configured/inferred | evidence`
Hops: laptop↔box SSH (`ssh -vv` shows `kex:` algorithm — sntrup/mlkem hybrid or classical);
mesh-llm iroh QUIC (check iroh/rustls version for hybrid KEX); x0x ant-quic (need handshake log
or capture — no x0x diagnostic exposes it); HTTP inside hosts (plaintext, local); Caddy public door.
