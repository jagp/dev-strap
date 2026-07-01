# Plugin Conversion — Deferred Decisions & TODOs

Parking lot for things that are fine as-is in the current **local / project-scoped** form
of dev-strap, but must be revisited when it becomes a **distributable plugin**. Plugins
install globally and their hooks fire in *every* session/project — so several choices that
don't matter locally become real forks at that point.

---

## 1. Logging scope — make it a first-activation choice

**Decision (2026-07-01):** the scope of `omnilog` logging is a legitimate either/or with no
obviously "more intuitive" default, so it should be an **install-time / first-activation
prompt**, not a baked-in behavior. Deferred until conversion; current local form left as-is.

**The two modes a user might reasonably want:**

- **Per-project (local):** each repo gets its own `omnilog.md` in its root, a sibling of
  CLAUDE.md, visible in that repo's file tree / IDE. Hook writes to
  `$CLAUDE_PROJECT_DIR/omnilog.md`, gated by an opt-in marker so unrelated repos aren't
  littered. Natural marker = the presence of `omnilog.md` (the scaffolder creates it):
  ```powershell
  if (-not (Test-Path -LiteralPath $log)) { exit 0 }   # project didn't opt in — do nothing
  ```
- **Global (aggregate):** one central log across every project, at a fixed/configured path
  (e.g. the plugin data dir or a user-set location). Hook always fires; no per-project guard.

**Current state:** local form. Hooks in `dev-strap/.claude/settings.json` (project-scoped,
so they only fire inside dev-strap) writing to `$CLAUDE_PROJECT_DIR/omnilog.md`. No opt-in
guard yet — safe precisely because project settings don't fire in other projects.

**At conversion, do:**
- [ ] Move hook registrations from project `.claude/settings.json` into the plugin's hooks
      manifest (plugin hooks fire globally).
- [ ] Add a first-activation prompt: **per-project / global / off**.
- [ ] If per-project: add the opt-in guard above; have the scaffolder create `omnilog.md`
      as the marker when it sets up a new repo.
- [ ] If global: point the log path at a fixed/configured location; drop the guard.
- [ ] Persist the choice (plugin settings / env var / marker file).

Ref: `autologging.md` §6–§7.

---

_Secrets handling was resolved during the local phase — the log stores model-authored
descriptions (`tool_input.description`), never raw command text or file content — so it is no longer a
deferred item. See `autologging.md` §7._
