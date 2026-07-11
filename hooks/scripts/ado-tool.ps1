# PostToolUse hook: mirror task state into the ado board. OBSERVE-ONLY - reads the
# tool call and writes ado's own copy; never mutates the real task system, never
# blocks (exit 0 always). Fires on EVERY tool call, so filter to Task* FIRST and
# early-exit before touching (locking) the board file. ASCII + concurrency safety
# live in ado-lib.ps1. Field schemas pinned by probe (2026-07-05):
#   TaskCreate  tool_input {subject,...}  tool_response "Task #<id> created ..."
#   TaskUpdate  tool_input {taskId,status,...}
$ErrorActionPreference = 'Stop'
try {
  . (Join-Path $PSScriptRoot 'ado-lib.ps1')
  $raw = Read-HookStdin
  if (-not $raw) { exit 0 }
  $o = $raw | ConvertFrom-Json
  $tool = [string]$o.tool_name
  if ($tool -ne 'TaskCreate' -and $tool -ne 'TaskUpdate') { exit 0 }
  $target = Resolve-AdoTarget
  if (-not $target) { exit 0 }
  [void](Write-AdoMirror $target $o)
} catch { }
exit 0
