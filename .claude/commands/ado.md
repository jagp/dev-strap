---
name: ado
description: Show the ado task board, or add your own item to it (per-project, git-ignored).
---

`ado` is a live, aggregated board of every task list the session's agents and
subagents spin up, mirrored automatically by the `ado-tool` PostToolUse hook into
`.claude/task.ado` (git-ignored working state). Blocks are chronological, one per
source (`main`, or `<agent_type> #<id>` for a subagent); items show status as
`- [ ]` pending, `- [~]` in progress, `- [x]` done.

**Arguments:** `$ARGUMENTS`

Behavior:

- **No arguments** — read `.claude/task.ado` (resolve via `$env:ADO_FILE`, else
  `$CLAUDE_PROJECT_DIR/.claude/task.ado`) and show it verbatim. If it does not exist
  yet, say the board is empty and that it fills in as agents create/update tasks.

- **`add <text>`** — append the user's own item to a `### user` block (create the
  block at the end if absent), so it lives alongside the agents' mirrored lists.
  Write the item as `- [ ] <text>` (no `#id` — user items are not tool-tracked).
  Keep the file ASCII and preserve every existing line (append only; never rewrite
  or reorder the agents' blocks). Confirm what you added.

Notes to relay if relevant: ado is **observe-only** by default — it holds a
*separate master copy* and never touches the agents' real task lists. Reconciling
the two directions is a planned opt-in capability, not wired up yet. Board scope
(per-project / global / off) is configured like omnilog; `$env:ADO_FILE` overrides.
