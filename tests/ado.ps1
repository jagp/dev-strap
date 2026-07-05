# TEST (unit + e2e): ado mirrors Task*/todo state into task.ado as chronological
# blocks (one per agent/source), items updated in place. Observe-only: the hook
# never throws and always exits 0. ASCII-only enforced via omnilog-lib.
# Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$hooks = Join-Path $root '.claude\hooks'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
. (Join-Path $hooks 'ado-lib.ps1')

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}
function Obj($json) { $json | ConvertFrom-Json }

# --- Get-AdoBlockId: cobble a stable identifier from the event ------------------
Check 'blockId main' ((Get-AdoBlockId (Obj '{"tool_name":"TaskCreate"}')) -eq 'main')
$sub = Obj '{"tool_name":"TaskCreate","agent_id":"a4864e002ce7efac2","agent_type":"Explore"}'
Check 'blockId subagent => type + short id' ((Get-AdoBlockId $sub) -eq 'Explore #a4864e00')

# --- Get-AdoUpdatedContent: TaskCreate appends an item under its block ----------
$c = Get-AdoUpdatedContent '' (Obj '{"tool_name":"TaskCreate","tool_input":{"subject":"first task"},"tool_response":"Task #1 created successfully: first task"}')
Check 'create: has title'      ($c -match '(?m)^# ado')
Check 'create: main header'    ($c -match '(?m)^### main\b')
Check 'create: pending item'   ($c -match '(?m)^- \[ \] #1 first task$')

# second create in same (main) block -> one header, two items
$c = Get-AdoUpdatedContent $c (Obj '{"tool_name":"TaskCreate","tool_input":{"subject":"second task"},"tool_response":"Task #2 created successfully: second task"}')
Check 'create2: single main header' (([regex]::Matches($c, '(?m)^### main\b')).Count -eq 1)
Check 'create2: item #2 present'    ($c -match '(?m)^- \[ \] #2 second task$')

# --- TaskUpdate: flip an item's checkbox in place, found by #id anywhere --------
$c = Get-AdoUpdatedContent $c (Obj '{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"in_progress"}}')
Check 'update: #1 in_progress => [~]' ($c -match '(?m)^- \[~\] #1 first task$')
$c = Get-AdoUpdatedContent $c (Obj '{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}')
Check 'update: #1 completed => [x]'   ($c -match '(?m)^- \[x\] #1 first task$')
Check 'update: #2 untouched'          ($c -match '(?m)^- \[ \] #2 second task$')
$c = Get-AdoUpdatedContent $c (Obj '{"tool_name":"TaskUpdate","tool_input":{"taskId":"2","status":"deleted"}}')
Check 'update: #2 deleted => gone'    (-not ($c -match '#2 second task'))

# --- subagent TaskCreate opens a new block below main --------------------------
$c = Get-AdoUpdatedContent $c (Obj '{"tool_name":"TaskCreate","agent_id":"a4864e002ce7efac2","agent_type":"Explore","tool_input":{"subject":"sub work"},"tool_response":"Task #7 created successfully: sub work"}')
Check 'subagent: own block' ($c -match '(?m)^### Explore #a4864e00\b')
Check 'subagent: item #7'    ($c -match '(?m)^- \[ \] #7 sub work$')

# --- ASCII safety: unicode subject is transliterated, no non-ASCII survives ----
$c = Get-AdoUpdatedContent '' (Obj ('{"tool_name":"TaskCreate","tool_input":{"subject":"café — “x”"},"tool_response":"Task #9 created successfully"}'))
Check 'ascii: no non-ASCII bytes' (-not ($c -match '[^\x00-\x7F]'))

# --- e2e: fire the hook, target via $env:ADO_FILE, prove file write + exit 0 ----
$ado = Join-Path $env:TEMP ("ado-e2e-{0}.ado" -f ([guid]::NewGuid().ToString('N')))
Remove-Item -LiteralPath $ado -ErrorAction SilentlyContinue
$env:ADO_FILE = $ado
function Fire($j) { $j | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks 'ado-tool.ps1'); return $LASTEXITCODE }
$rc = Fire '{"tool_name":"TaskCreate","tool_input":{"subject":"live one"},"tool_response":"Task #1 created successfully: live one"}'
Check 'e2e: exit 0'        ($rc -eq 0)
Check 'e2e: file written'  ((Test-Path -LiteralPath $ado) -and ((Get-Content -Raw -LiteralPath $ado) -match '(?m)^- \[ \] #1 live one$'))
$rc = Fire '{"tool_name":"TaskUpdate","tool_input":{"taskId":"1","status":"completed"}}'
Check 'e2e: update in place' ((Get-Content -Raw -LiteralPath $ado) -match '(?m)^- \[x\] #1 live one$')

# non-Task tool is ignored (no spurious writes)
$before = Get-Content -Raw -LiteralPath $ado
$null = Fire '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
Check 'e2e: non-Task ignored' ((Get-Content -Raw -LiteralPath $ado) -eq $before)

# malformed stdin never throws, always exit 0
$rc = Fire 'not json at all'
Check 'e2e: malformed => exit 0' ($rc -eq 0)
$rc = '' | & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hooks 'ado-tool.ps1'); $rc = $LASTEXITCODE
Check 'e2e: empty => exit 0' ($rc -eq 0)

# scope off => hook writes nothing
$ado2 = Join-Path $env:TEMP ("ado-off-{0}.ado" -f ([guid]::NewGuid().ToString('N')))
$env:ADO_FILE = $ado2; $env:ADO_SCOPE = 'off'
$null = Fire '{"tool_name":"TaskCreate","tool_input":{"subject":"nope"},"tool_response":"Task #1 created successfully"}'
Check 'e2e: scope off => no file' (-not (Test-Path -LiteralPath $ado2))
Remove-Item Env:\ADO_SCOPE -ErrorAction SilentlyContinue

Remove-Item Env:\ADO_FILE -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ado  -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ado2 -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  ado'; exit 0 }
Write-Output ("FAIL  ado ({0} case(s))" -f $fail); exit 1
