#!/usr/bin/env bash
# Read-only C2 inventory for a Linux node (Oracle / Hostinger). Changes nothing; prints no secrets.
# Usage: bash inventory-linux.sh   -> writes ~/buzz-lane-evidence/<UTC>/ and prints SUMMARY
set -u
E=~/buzz-lane-evidence/$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$E"; cd "$E"
run() { echo "### $1" >> all.txt; bash -c "$2" >> all.txt 2>&1; echo >> all.txt; }
run os        'cat /etc/os-release | grep -E "^(NAME|VERSION)="; uname -srm; hostname'
run cpu_mem   'nproc; free -h | head -2; df -h / | tail -1'
run gpu       'lspci 2>/dev/null | grep -iE "vga|3d|nvidia" || echo none'
run services  'systemctl list-units --type=service --state=running --no-pager | grep -iE "buzz|x0x|mesh|llama|meter|caddy|docker" || true'
run units     'for u in buzz-compute buzz-meter buzz-meter-gate buzz-compute-firewall x0x; do systemctl cat $u 2>/dev/null | grep -vE "(TOKEN|KEY|SECRET|PASSWORD)=" ; done'
run docker    'docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null'
run listen    'ss -ltnup 2>/dev/null | awk "NR==1||/LISTEN|UNCONN/{print \$1,\$5,\$7}"'
run binaries  'for b in x0xd x0x mesh-llm /opt/buzz-compute/src/build-new/bin/llama-server /opt/buzz-compute/src/build/bin/llama-server; do p=$(command -v $b 2>/dev/null || ls $b 2>/dev/null) && { echo "$p"; $p --version 2>&1 | head -2; sha256sum "$p"; }; done'
run models    'ls -l /opt/buzz-compute/models/ 2>/dev/null'
run llama     'curl -s -m5 http://172.18.0.1:8090/health; echo; curl -s -m5 http://172.18.0.1:8090/v1/models; echo'
run meter     'ls /opt/buzz-meter/receipts 2>/dev/null | wc -l; cat /opt/buzz-meter/state/receipt-chain-tip 2>/dev/null; echo; cat /opt/buzz-meter/state/offset 2>/dev/null'
run x0x       'T=$(sudo cat /var/lib/x0x/data/api-token 2>/dev/null); [ -n "$T" ] && curl -s -m5 -H "Authorization: Bearer $T" http://127.0.0.1:12700/health; unset T; echo'
run mesh      'curl -s -m5 http://127.0.0.1:3131/api/status | python3 -c "import sys,json;d=json.load(sys.stdin);d.pop(\"token\",None);print(json.dumps({k:d.get(k) for k in [\"version\",\"node_state\",\"model_name\",\"peers\",\"gpus\",\"routing_metrics\"]},indent=1))" 2>/dev/null || echo "no mesh-llm"'
sha256sum all.txt > MANIFEST.sha256
echo "EVIDENCE: $E"; cat all.txt
