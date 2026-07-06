# Shared helpers for ado - the live cross-agent task board (omnilog's task-state
# sibling). Unlike omnilog (append-only ledger), ado is a *living document*: block
# ORDER is chronological/append-only (new task lists stack below), item STATE
# within a block is rewritten in place as status changes.
#
# Design notes:
#   * Observe-only. The passive hook NEVER mutates the real task system; a bug here
#     must be incapable of affecting the session (ado-tool.ps1 exits 0 on any throw).
#   * Items carry a visible #<id>. TaskUpdate's payload has only taskId + status
#     (no text, no reliable agent grouping), so updates are located by scanning the
#     whole file for #<id>; block identity only decides where NEW items land.
#   * ASCII-only via omnilog-lib's ConvertTo-Ascii, so the board renders identically
#     everywhere. Verified by tests/ado.ps1.
. (Join-Path $PSScriptRoot 'omnilog-lib.ps1')   # Read-HookStdin, ConvertTo-Ascii

$script:AdoTitle = '# ado -- live task board (git-ignored working state)'

function Resolve-AdoTarget {
  # The board path, or $null meaning "do not mirror".
  # $env:ADO_FILE overrides all (tests + power users). A future Phase-1 change folds
  # this onto omnilog's shared scope resolver; for now a minimal per-project default.
  if ($env:ADO_SCOPE -eq 'off') { return $null }
  if ($env:ADO_FILE) { return $env:ADO_FILE }
  if ($env:CLAUDE_PROJECT_DIR) { return (Join-Path $env:CLAUDE_PROJECT_DIR '.claude\task.ado') }
  return (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.claude\task.ado')
}

function Get-AdoMark([string]$status) {
  switch ($status) {
    'in_progress' { '~' }
    'completed'   { 'x' }
    default       { ' ' }   # pending / unknown
  }
}

function Get-AdoBlockId($o) {
  # A stable identifier for the source of a task list. MUST NOT include the
  # timestamp (identity has to survive across create/update to find the block).
  $aid = [string]$o.agent_id
  if (-not $aid) { $aid = [string]$o.agentId }
  if ($aid) {
    $atype = [string]$o.agent_type
    if (-not $atype) { $atype = [string]$o.subagent_type }
    if (-not $atype) { $atype = 'agent' }
    $short = if ($aid.Length -gt 8) { $aid.Substring(0, 8) } else { $aid }
    return (ConvertTo-Ascii "$atype #$short")
  }
  return 'main'
}

function Get-AdoCreateItem($o) {
  # From a TaskCreate event: subject (item text) + id parsed from the response
  # string ("Task #<id> created successfully: ..."). $null if no subject.
  $subject = [string]$o.tool_input.subject
  if (-not $subject) { return $null }
  $id = ''
  $tr = [string]$o.tool_response
  if ($tr) { $m = [regex]::Match($tr, 'Task #(\d+)'); if ($m.Success) { $id = $m.Groups[1].Value } }
  $text = ((ConvertTo-Ascii $subject) -replace '\s+', ' ').Trim()
  return @{ id = $id; text = $text; status = 'pending' }
}

function Get-AdoUpdate($o) {
  # From a TaskUpdate event: taskId + new status (and/or new subject). $null if
  # neither a status nor a subject change is present.
  $id = [string]$o.tool_input.taskId
  if (-not $id) { return $null }
  $status = [string]$o.tool_input.status
  $text   = [string]$o.tool_input.subject
  if (-not $status -and -not $text) { return $null }
  $r = @{ id = $id; status = $status }
  if ($text) { $r.text = ((ConvertTo-Ascii $text) -replace '\s+', ' ').Trim() }
  return $r
}

function New-AdoItemLine([string]$id, [string]$text, [string]$status) {
  $mark = Get-AdoMark $status
  if ($id) { return "- [$mark] #$id $text" }
  return "- [$mark] $text"
}

function Add-AdoItemToBlock($lines, [string]$blockId, $item) {
  # Insert a new item under its block (append the block chronologically if new).
  $itemLine = New-AdoItemLine $item.id $item.text $item.status
  $hdrPat = '^### ' + [regex]::Escape($blockId) + '(\s|$)'
  $hdr = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $hdrPat) { $hdr = $i; break } }
  if ($hdr -ge 0) {
    $end = $lines.Count
    for ($i = $hdr + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^### ') { $end = $i; break } }
    $ins = $end
    while ($ins -gt ($hdr + 1) -and [string]::IsNullOrWhiteSpace($lines[$ins - 1])) { $ins-- }
    $lines.Insert($ins, $itemLine)
  } else {
    $ts = Get-Date -Format 'HH:mm'
    if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) { [void]$lines.Add('') }
    [void]$lines.Add("### $blockId  @ $ts")
    [void]$lines.Add($itemLine)
  }
}

function Set-AdoItem($lines, $upd) {
  # Locate #<id> anywhere in the file and rewrite its mark (and text if provided);
  # 'deleted' removes the line. A text-only update preserves the existing mark.
  $pat = '^- \[(.)\] #' + [regex]::Escape($upd.id) + ' (.*)$'
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $m = [regex]::Match($lines[$i], $pat)
    if ($m.Success) {
      if ($upd.status -eq 'deleted') { $lines.RemoveAt($i); return }
      $mark = if ($upd.status) { Get-AdoMark $upd.status } else { $m.Groups[1].Value }
      $text = if ($upd.text)   { $upd.text }             else { $m.Groups[2].Value }
      $lines[$i] = "- [$mark] #$($upd.id) $text"
      return
    }
  }
}

function Get-AdoUpdatedContent([string]$content, $o) {
  # PURE: given the current board text and a hook event object, return the new text.
  # No IO - the locked read/write lives in Write-AdoMirror.
  $lines = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($content)) {
    foreach ($l in ($content -split "`r?`n")) { [void]$lines.Add($l) }
  }
  if ($lines.Count -eq 0 -or $lines[0] -ne $script:AdoTitle) {
    if (-not ($lines -contains $script:AdoTitle)) {
      $lines.Insert(0, '')
      $lines.Insert(0, $script:AdoTitle)
    }
  }
  switch ([string]$o.tool_name) {
    'TaskCreate' { $item = Get-AdoCreateItem $o; if ($item) { Add-AdoItemToBlock $lines (Get-AdoBlockId $o) $item } }
    'TaskUpdate' { $upd  = Get-AdoUpdate $o;     if ($upd)  { Set-AdoItem $lines $upd } }
  }
  return (($lines -join "`n").TrimEnd() + "`n")
}

function Write-AdoMirror([string]$target, $o) {
  # Read-modify-write under an EXCLUSIVE lock (parallel agents all mirror to one
  # file). Truncate-in-place while holding the handle - atomic enough and avoids
  # move races. If the lock can't be had in ~0.5s, drop the update silently: a
  # missed mirror line is acceptable, corruption is not (Safety Invariant).
  $dir = Split-Path $target -Parent
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  for ($try = 0; $try -lt 20; $try++) {
    try {
      $fs = [System.IO.File]::Open($target, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    } catch [System.IO.IOException] {
      Start-Sleep -Milliseconds 25; continue
    }
    try {
      $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::ASCII)
      $content = $sr.ReadToEnd()
      $new = Get-AdoUpdatedContent $content $o
      $fs.SetLength(0); $fs.Position = 0
      $sw = New-Object System.IO.StreamWriter($fs, (New-Object System.Text.ASCIIEncoding))
      $sw.Write($new); $sw.Flush()
      return $true
    } finally { $fs.Dispose() }
  }
  return $false
}
