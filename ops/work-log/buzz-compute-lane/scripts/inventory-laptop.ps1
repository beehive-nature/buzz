# Read-only C1+C2 capture for the Windows laptop. Changes nothing; never prints key contents.
# Usage: powershell -ExecutionPolicy Bypass -File inventory-laptop.ps1 [-BuzzRepo C:\path\to\buzz]
param([string]$BuzzRepo = "")
$E = "$HOME\buzz-lane-evidence\$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"; New-Item -ItemType Directory -Force $E | Out-Null
function Run($n, [scriptblock]$b) { "### $n" | Out-File -Append "$E\all.txt"; try { & $b 2>&1 | Out-String -Width 250 | Out-File -Append "$E\all.txt" } catch { $_ | Out-File -Append "$E\all.txt" } }
Run hw      { Get-CimInstance Win32_ComputerSystem | Select Name,TotalPhysicalMemory; Get-CimInstance Win32_Processor | Select Name,NumberOfCores,NumberOfLogicalProcessors; Get-CimInstance Win32_VideoController | Select Name,DriverVersion; Get-PSDrive C | Select Used,Free }
Run procs   { Get-Process | ? { $_.Name -match 'buzz|mesh|llama|x0x|claude' } | Select Name,Id,Path,@{n='WS_MB';e={[int]($_.WS/1MB)}} }
Run listen  { Get-NetTCPConnection -State Listen | ? { $_.LocalPort -in 3131,9337,12700,18080 -or $_.LocalAddress -ne '::' } | Select LocalAddress,LocalPort,OwningProcess | Sort LocalPort }
Run mesh    { $s = curl.exe -s -m 5 http://127.0.0.1:3131/api/status | ConvertFrom-Json; $s.PSObject.Properties.Remove('token'); $s | Select version,node_state,model_name,peers,gpus,routing_metrics | ConvertTo-Json -Depth 6 }
Run apikey  { "ANTHROPIC_API_KEY set (process/user/machine): " + [bool]$env:ANTHROPIC_API_KEY + "/" + [bool][Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY','User') + "/" + [bool][Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY','Machine') }
Run sshkeys { Get-ChildItem $HOME\.ssh\*.pub -EA SilentlyContinue | % { ssh-keygen -lf $_.FullName }; wsl bash -c 'for f in ~/.ssh/*.pub; do ssh-keygen -lf "$f"; done' }
$B = Get-ChildItem $env:APPDATA,$env:LOCALAPPDATA -Recurse -Depth 3 -Filter personas.json -EA SilentlyContinue | Select -First 1 | % DirectoryName
Run roster  { "store: $B"; foreach ($f in 'personas.json','managed-agents.json','teams.json','retention.db') { if (Test-Path "$B\$f") { Copy-Item "$B\$f" "$E\roster-$f"; Get-FileHash "$B\$f" | Select Hash,Path } } }
if ($BuzzRepo) {
  Run git { git -C $BuzzRepo status --porcelain=v2 --branch; git -C $BuzzRepo branch -vv --all; git -C $BuzzRepo stash list; git -C $BuzzRepo reflog -n 40 --date=iso; git -C $BuzzRepo diff --stat HEAD }
  git -C $BuzzRepo diff --binary HEAD > "$E\tracked.diff"; git -C $BuzzRepo ls-files --others --exclude-standard > "$E\untracked.txt"
}
Get-ChildItem $E -File | Get-FileHash | Format-Table -Auto | Out-File "$E\MANIFEST.sha256"
"EVIDENCE: $E"; Get-Content "$E\all.txt"
