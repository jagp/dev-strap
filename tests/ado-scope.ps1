# TEST (unit): Resolve-AdoTarget follows the shared omnilog scope config with an
# independent 'ado:' key. Fail-closed: an installed plugin must not write task.ado
# into projects that never opted in. $env:ADO_SCOPE=off beats $env:ADO_FILE beats
# config (pinned by tests/ado.ps1 e2e).
# Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
$hooks = Join-Path (Split-Path $PSScriptRoot -Parent) 'hooks\scripts'
. (Join-Path $hooks 'ado-lib.ps1')

$fail = 0
function Check($name, $cond) {
  if ($cond) { Write-Output "  ok   $name" } else { Write-Output "  FAIL $name"; $script:fail++ }
}

Remove-Item Env:\ADO_FILE -ErrorAction SilentlyContinue
Remove-Item Env:\ADO_SCOPE -ErrorAction SilentlyContinue
Remove-Item Env:\OMNILOG_FILE -ErrorAction SilentlyContinue
$proj = Join-Path $env:TEMP ("ado-scope-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
$env:CLAUDE_PROJECT_DIR = $proj
$cfg = Join-Path $proj '.claude\omnilog.local.md'
$marker = Join-Path $proj 'omnilog.md'
$board = Join-Path $proj '.claude\task.ado'

# 1) foreign project, no config, no marker -> null (fail-closed)
Check 'no-config/no-marker => null' ($null -eq (Resolve-AdoTarget))

# 2) omnilog per-project opt-in marker present -> the project board
Set-Content -LiteralPath $marker -Value '' -Encoding ASCII
Check 'marker => project board' ((Resolve-AdoTarget) -eq $board)

# 3) 'ado: off' disables independently, even with the marker
Set-Content -LiteralPath $cfg -Value "---`nado: off`n---" -Encoding ASCII
Check 'ado:off => null' ($null -eq (Resolve-AdoTarget))

# 4) 'scope: off' kills ado too
Set-Content -LiteralPath $cfg -Value "---`nscope: off`n---" -Encoding ASCII
Check 'scope:off => null' ($null -eq (Resolve-AdoTarget))

# 5) global omnilog scope alone does NOT enable ado (no implicit board litter)
Remove-Item -LiteralPath $marker -Force
Set-Content -LiteralPath $cfg -Value "---`nscope: global`n---" -Encoding ASCII
Check 'global/no-ado-key => null' ($null -eq (Resolve-AdoTarget))

# 6) 'ado: on' forces the board on without the marker
Set-Content -LiteralPath $cfg -Value "---`nado: on`n---" -Encoding ASCII
Check 'ado:on/no-marker => project board' ((Resolve-AdoTarget) -eq $board)

# 7) $env:ADO_FILE overrides config
$env:ADO_FILE = 'X:\board.ado'
Set-Content -LiteralPath $cfg -Value "---`nado: off`n---" -Encoding ASCII
Check 'ADO_FILE overrides config' ((Resolve-AdoTarget) -eq 'X:\board.ado')

# 8) $env:ADO_SCOPE=off beats even ADO_FILE
$env:ADO_SCOPE = 'off'
Check 'ADO_SCOPE=off beats ADO_FILE' ($null -eq (Resolve-AdoTarget))
Remove-Item Env:\ADO_SCOPE
Remove-Item Env:\ADO_FILE

Remove-Item Env:\CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $proj -Recurse -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'PASS  ado-scope'; exit 0 }
Write-Output ("FAIL  ado-scope ({0} case(s))" -f $fail); exit 1
