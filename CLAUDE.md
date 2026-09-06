# Claude Code Guidelines for Zepto Editor

**This is a living document.** Update it as the project evolves — new rules, workflow changes, communication preferences, and lessons learned.

---

## The 8 Rules

Every commit must satisfy all of these. No exceptions.

### 1. Build integrity

The compiled `./zepto` must run correctly and depend only on the Perl standard library.

- `make build` must succeed
- The built binary must be self-contained — no CPAN modules, no external files
- Verify basic operation after every non-trivial change (see Testing Workflow below)
- Architecture and bundling: `DESIGN.md`, `build.pl`

### 2. UI discoverability

Every feature must be discoverable through the UI without reading help, docs, or source code.

- All features must be accessible via command palette (`⌃Space`) and/or status bar pills
- This **must** be verified interactively — run the program and check with your own eyes
- "It's just a bug fix" does **not** exempt you from interactive testing. Any change to key handling, commands, or rendering is a UI change.
- Full UI standards: `docs/UI_GUIDELINES.md`

### 3. Tests and lint pass, with no noise

- `make test` must pass completely
- `make check` (Perl syntax check) must pass
- No unexpected output on stdout/stderr during test runs
- Tests must be fast — slowness is a bug
- Full testing standards: `docs/CODE_QUALITY.md`

### 4. Security

This editor runs on users' desktops with access to their files. They trust it. Security matters.

- Read `docs/SECURITY.md` before touching file I/O, shell execution, or rendering
- Flag any new shell exec, path handling, or file operation for security review
- Never add network calls — Zepto is intentionally offline

### 5. Test before, fix, test after

For every bug or change:

1. **Reproduce first**: write a failing test or capture broken interactive behavior before touching code
2. **Fix it**
3. **Verify**: confirm the test now passes and interactive behavior is correct

Do not call work done without completing all three steps.

### 6. Bug tracking

Known bugs live in `bugs.md` with priorities P0–P3.

- **P0**: Data loss, crash, or fundamentally wrong behavior
- **P1**: Significant usability issue
- **P2**: Polish — inconsistency or minor misbehavior
- **P3**: Cosmetic / edge case

When you find a bug (even while working on something else), add it to `bugs.md` immediately. During a bug bash: work through bugs in priority order, fix and verify each one before moving to the next.

### 7. Code quality

- Follow established conventions — don't invent new patterns without a good reason
- Audit code for quality, architecture, and consistency as you work
- Full standards and ongoing audit status: `docs/CODE_QUALITY.md`

### 8. QA plan is kept current

The `qa/` directory contains the end-to-end QA test plan — one test case
per user-visible behavior. It is the executable spec that a QA engineer
(or future you) uses to validate a release.

**Every new feature, bug fix, or behavioral discovery must have a QA script. No exceptions.**

This means:
- **New feature**: add an executable test script in `qa/scripts/tier1/` AND
  a test case to the appropriate `qa/NN_*.txt` file covering happy path,
  key edge cases, and how to verify the feature is discoverable from the UI.
- **Bug fix (including regressions)**: add a test script that reproduces
  the bug AND a `QA-REG-###` entry to `qa/40_regression_bugs.txt` with a
  cross-ref to the primary feature test.
- **Behavioral discovery**: when you learn something non-obvious about
  how Zepto behaves (from code reading, user report, or interactive
  testing), add a test script and test case so it can't regress silently.
- **IDs are stable — never renumber.** To retire a test, mark it
  `[RETIRED]` in place in its `qa/NN_*.txt` file rather than deleting.
  (There is no separate catalog file — it was removed because a manual
  index drifts; `grep -r 'QA-<TAG>-' qa/*.txt` is the index.)
- **Run `make qa`** to verify the new test passes along with all existing tests.

Work is not done until the QA script exists and passes. "I'll add the test later" is not acceptable.

Test IDs are `QA-<TAG>-<NNN>` where `<TAG>` is the 3-6 char feature tag
used in the corresponding `qa/NN_*.txt` file. Find the next unused number
with `grep -rho 'QA-<TAG>-[0-9]*' qa/ | sort -V | tail -1`.

Full plan: `qa/README.md`.

---

## Cross-platform compatibility

Zepto targets macOS, Linux, and most Unix-like systems. The only runtime dependency is Perl (core modules only — no CPAN). Testing requires a few additional tools (see below).

### Runtime

- **Perl standard library only.** No CPAN modules — Zepto ships as a single self-contained file.
- **No platform-specific system calls or paths.** Use portable Perl idioms. Avoid anything that assumes a specific OS layout.

### Code and scripts

- **No hardcoded paths.** Never embed `/Users/joe/...` or any machine-specific path. Use `$PWD`, `$OLDPWD`, `$HOME`, `$(dirname "$0")`, or variables.
- **No platform-specific commands without guards.** `sed -i ''` is macOS-only; GNU `sed -i` has no empty argument. Use a platform check (`if [[ "$(uname)" == "Darwin" ]]`) or avoid the divergent syntax entirely. Same applies to `stat`, `readlink`, `mktemp` flags, clipboard commands, etc.
- **Prefer POSIX-compatible shell constructs** where possible. When bash-isms are needed, scripts must use `#!/usr/bin/env bash`.

### Testing dependencies

These are required for development/CI but not for end users:

| Tool | Purpose |
|------|---------|
| Perl 5.20+ | Runtime + unit tests (`make test`) |
| `prove` | Test harness (ships with Perl) |
| `hangon` | QA session automation (`make qa`) |
| `tmux` | Required by hangon |
| `git` | VCS integration tests |

### Verification

When in doubt, ask: "would this work on a fresh Ubuntu runner with just Perl, tmux, hangon, and git?"

---

## No sloppy assumptions

Be precise. Don't assume things that could change or differ between environments.

- **Don't hardcode paths** — compute them from context (`$PWD`, `$OLDPWD`, `$(dirname "$0")`).
- **Don't assume directory structure** — use variables, not string literals.
- **Don't assume tool behavior is uniform** — verify flags work on both macOS and Linux.
- **Don't write tautological tests** — every assertion must fail if the feature is broken. Ask: "would this pass on a no-op implementation?" See `qa/README.md` for anti-patterns.
- **Don't leave temp state** — clean up temp files, sessions, and directories. Use traps.

Past examples of sloppy assumptions that caused CI failures:
- `cd /Users/joe/src/zepto` hardcoded in 5 test scripts — broke on Ubuntu
- `sed -i ''` — macOS-only syntax, fails on Linux
- Tests that asserted "screen changed" instead of checking specific content — passed even when features were broken

---

## Testing Workflow

**Every UI change must be tested interactively.** Unit tests alone are not sufficient for a TUI.

**Do this BEFORE `make test`, not after.** Running unit tests first creates a false sense of completion that makes it easy to skip the interactive step. The order is: build → interact → then run tests.

### Using `hangon` (required)

`hangon` is a persistent session manager that makes interactive TUI testing scriptable. **Always use `hangon` for interactive testing — do not use raw tmux commands.**

`hangon` should already be installed and available in PATH. If not, install it:

```bash
brew install joewalnes/tap/hangon
```

Or see https://github.com/joewalnes/hangon for other installation methods (binary download, from source).

#### Example workflow

```bash
make build

# Check for stale/orphaned sessions and reap only the dead ones — do NOT
# use `hangon stopall` as routine housekeeping. It kills every session in
# the shared state dir, including ones started by other concurrent agents
# or processes on the same machine, and has caused real incidents this way.
hangon gc

# Start zepto in a session — always pass --state-dir pointing at a scratch
# directory. Without it, zepto reads/writes your real ~/.config/zepto
# preferences and history (see bugs.md QA-REG-162 for an incident where
# skipping this flipped real preferences on a dev machine).
hangon start process --name zepto -- ./zepto --state-dir /tmp/zepto-qa-state /tmp/testfile.txt

# Wait for it to load, then inspect the screen
sleep 1
hangon screen zepto

# Type text, send keys, observe results
hangon send zepto "hello world"
hangon keys zepto "enter"
hangon keys zepto "ctrl-s"
sleep 0.3
hangon screen zepto                # see current screen state

# Clean up
hangon keys zepto "ctrl-q"
hangon stop zepto
```

#### Command reference

| Command | Description |
|---------|-------------|
| `hangon start process --name NAME -- ./zepto FILE` | Start a session |
| `hangon screen NAME` | Capture current terminal screen as text |
| `hangon send NAME "text"` | Type literal characters |
| `hangon sendline NAME "text"` | Type text + Enter |
| `hangon keys NAME "ctrl-z"` | Send special keys (ctrl-a..z, ctrl-space, ctrl-up/down/left/right, shift-up/down/left/right, shift-home/end, alt-a..z, alt-./,/=/-,  alt-up/down/left/right, enter, tab, escape, backspace, delete, up, down, left, right, home, end, pageup, pagedown, f1..f12) |
| `hangon expect NAME "pattern"` | Wait for regex to appear in output |
| `hangon screenshot NAME file.png` | Capture screen as SVG/PNG image |
| `hangon alive NAME` | Check if process is running (exit 0=yes, 1=no) |
| `hangon list` | List all tracked sessions (name, type, holder PID, alive) |
| `hangon gc [--dry-run]` | Reap dead/orphaned sessions only — safe to run anytime, touches nothing live |
| `hangon stop NAME` | Stop a session by name |
| `hangon stopall --force` | Stop **every** session in the shared state dir, including other agents'/processes' — see warning below |

#### Tips

- **Never use `hangon stopall` as routine cleanup.** It requires `--force` specifically because it's a machine-wide "kill everything sharing this state dir" — it has repeatedly killed unrelated sessions started by other concurrent agents on the same machine. Use `hangon gc` to reap only dead/orphaned sessions, and `hangon stop NAME` to stop a specific session you started. Only reach for `hangon stopall --force` when you are certain nothing else is using hangon on this machine — check `hangon list` first if in doubt.
- Give every session a unique, descriptive `--name` (not a generic name like `zepto`) so it can't collide with another concurrent agent's session, and clean up your own by name (`hangon stop NAME`) when done rather than relying on a blanket stop.
- Use `sleep 0.3` or `sleep 0.5` after send/keys before `screen` to let the editor render
- Chain independent sends with `&&` for efficiency
- Use `--name` to run multiple sessions in parallel (e.g., testing cross-tab features)
- Use `hangon expect` instead of `sleep` when waiting for specific output — it's faster and more reliable

### Rules

- Always `make build` first
- Capture the screen after each interaction to see what actually happened
- Clean up test files after — don't leave scratch files in the repo
- Never infer behavior from code alone — observe it in the running editor
- **`hangon screenshot` cannot be fully trusted for pixel-color or cell-boundary claims.** Four separate confirmed rendering bugs in `hangon`'s own SVG/PNG renderer have been found via this project alone (see `bugs.md`, search "screenshot rendering artifact") — a light-theme background-fill fallback, under-rendered box-drawing glyphs, hairline inter-cell gaps, and a pill-cap color mismatch. Each looked like a real Zepto bug until traced further. If a screenshot shows something color- or boundary-related that seems surprising (a mismatched color, a seam, a gap that shouldn't be there), corroborate before treating it as a real bug or reverting a fix: pull the raw ANSI via `hangon readall` and check the actual SGR color codes at that position, or ask the user to look at a real terminal directly. `hangon screen` (plain text) and `hangon readall` (raw bytes) don't go through the SVG rendering path and are more trustworthy for exactly the claims screenshots have been wrong about. Screenshots remain fine for everything else (layout, text content, general "does this look right").

---

## Git Commits

**Commit once the pre-commit checklist below is fully satisfied — not before, and not gated on a separate per-change go-ahead.** This project's earlier rule ("never commit until the user explicitly says to") was revoked 2026-09-01, replaced by go-team's own standard: functionality that has actually cleared the bar — build, interactive verification, tests, security review where relevant, bug tracking, code quality, QA plan currency, all satisfied — is validated, and validated work gets committed. Passing the checklist *is* the go-ahead. Pushing to `origin/main` follows the same standard (see `## Agent operations`'s autonomy policy below) unless a specific session has been told otherwise.

This still means: **do not commit work that hasn't actually cleared the checklist**, no matter how close it looks — an unverified change is not "probably fine," it's unvalidated, and unvalidated work stays uncommitted regardless of how the rest of this section reads.

### Pre-commit checklist — all 8 rules, every time, no exceptions

Before every commit, verify each rule in order:

| # | Rule | How to verify |
|---|------|---------------|
| 1 | Build integrity | `make check && make build` — must succeed cleanly |
| 2 | UI discoverability | **Run interactively via `hangon`** (see Testing Workflow above). Do this before `make test`. Any change to key handling, commands, or rendering counts. "It's just a bug fix" is not an exemption. |
| 3 | Tests pass, no noise | `make test` — must pass (or pre-existing failures explicitly acknowledged and user-approved) |
| 4 | Security | If file I/O, shell exec, or rendering changed: flag it and confirm it was reviewed against `docs/SECURITY.md` |
| 5 | Test before, fix, test after | Confirm a failing test or broken behavior was captured *before* the fix, not just after |
| 6 | Bug tracking | Any bugs found (even incidentally) are recorded in `bugs.md` |
| 7 | Code quality | Changes follow existing conventions; no new patterns introduced without reason |
| 8 | QA plan current | New feature or bug fix → new executable test script in `qa/scripts/tier1/` + test case in the right `qa/NN_*.txt`. Bug fix also gets `QA-REG-###` in `qa/40_regression_bugs.txt`. Run `make qa` to verify. No exceptions. |

If any rule is not satisfied:
- **Do not commit.**
- If a rule doesn't apply to the change (e.g. Rule 2 for a docs-only change), state that explicitly rather than silently skipping it.
- "It's only a docs change" is not a blanket exemption — still run Rules 1, 3, 7, and 8 at minimum.

---

## Keeping Docs Current

| File | Update when |
|------|-------------|
| `CLAUDE.md` | Rules change, workflow improves, new communication preferences |
| `bugs.md` | Bug found or fixed |
| `qa/*.txt` | **Every new feature, fix, or behavioral discovery** — see Rule 8 |
| `docs/CODE_QUALITY.md` | New patterns, pitfalls, testing lessons |
| `docs/SECURITY.md` | New security concerns or mitigations |
| `docs/UI_GUIDELINES.md` | New UI standards or design decisions |
| `README.md` | Features added or removed |
| `docs/help/changelog.md` | Every commit — add user-visible changes to the changelog |

### Embedded Help Docs

Built-in documentation lives in `docs/help/*.md` and is embedded into the zepto binary by `build.pl`. These docs are accessible from the command palette under the DOCUMENTATION section, and the Tutorial is bound to F1.

When committing, update `docs/help/changelog.md` with any user-visible changes. Group entries by date, keep bullets short and readable. Only include things an end-user would care about.

To add a new help doc:
1. Create `docs/help/newdoc.md`
2. Add entry to `%DOCS` and `@DOC_ORDER` in `lib/Zepto/HelpDocs.pm`
3. Add command entry in `lib/Zepto/CommandRegistry.pm` under DOCUMENTATION section
4. Add handler method in `lib/Zepto/Editor/Commands.pm` (call `_open_help_doc`)

---

## Agent operations

Configuration for running a parallel agent fleet (`/go-team`) unattended on this project. Hand-written 2026-09-01 on the fleet's first run — no formal `/project-setup` pass has been done; treat this section as version 1 and revisit it if `/project-setup` ever becomes available.

### Autonomy policy — full autonomy: merge and push once verified

**Updated 2026-09-01.** The earlier "merge-locally-only, ask before push" compromise is retired along with the standing per-change commit rule it was reconciling. The fleet now follows go-team's own default model directly:

- Agents work in isolated worktrees, branched from local `main`.
- The foreman verifies each claim behaviourally — build, interact via `hangon`, then test — **in an isolated worktree, never the shared checkout** (see `/go-team`'s "Verifying a worker's branch" section; this project hit the exact incident that rule exists to prevent — see `bugs.md`'s 2026-09-01 "Repo hygiene" entry for the recovery).
- Once verified, the foreman **merges into local `main` and pushes to `origin/main`**, following the gate in the `/go-team` skill. No separate per-batch go-ahead is required — passing the full pre-commit checklist (Rules 1–8, below) *is* the go-ahead, same as for any other commit in this project now.
- Rules 1–8 in this file (build integrity, interactive UI verification, tests/lint, security, test-before/fix/test-after, bug tracking, code quality, QA plan currency) apply to every merge exactly as they do to any other change — the pre-commit checklist is not relaxed for agent-authored work.

### Fleet size

5 concurrent agents (skill default), confirmed with the user on the first run (2026-09-01). Cost is real at this scale — reconfirm with the user before raising it.

### Verification recipe

The **Testing Workflow** section above (build → `hangon gc` → `hangon start process --name <unique> --state-dir <scratch> -- ./zepto <file>` → interact → `make test`) is the real end-to-end recipe — it drives the actual compiled binary, not just unit tests. Every agent's claim must be reproduced this way, not trusted from its report. `make check && make build && make test` is the fast gate; interactive `hangon` verification is required in addition for any change touching key handling, commands, or rendering (Rule 2 — no exceptions for "just a bug fix").

### Shared singletons — must not collide

- **`hangon`'s shared state dir** (`~/.hangon`) — every session needs a unique `--name` (not a generic one) to avoid colliding with another concurrent agent's session. `hangon gc` is safe to run anytime (reaps only dead/orphaned sessions); `hangon stopall --force` is **never** safe during a fleet run — it kills every session sharing the state dir, including other agents'.
- **Zepto's real preferences** (`~/.config/zepto`) — every `hangon`-launched zepto instance MUST pass `--state-dir` pointing at a per-agent scratch directory. Skipping this once already corrupted a real dev machine's preferences (see `bugs.md` `QA-REG-162`).
- **Git worktrees** — each agent gets its own, named uniquely (`.claude/worktrees/agent-<id>` is the established convention in this repo). The foreman is responsible for removing an agent's worktree and branch once its work is merged or abandoned — 24 empty worktrees and 44 stale merged branches were found to have silently piled up before this policy existed (`bugs.md`, 2026-09-01 "Repo hygiene" entry). Check `git worktree list` / `git branch --merged main` periodically and clean up what's actually safe to remove (0 commits ahead, 0 uncommitted files, or already merged) — never force-delete a branch with real unmerged/uncommitted work without investigating it first.
- **The primary checkout** (`/Users/joe/src/zepto`, no worktree suffix) — must always stay on `main`. No agent may switch it to another branch. The gate's branch guard (see `/go-team` skill) enforces this mechanically; don't rely on instruction alone.

### Do-not-touch

- `backup-pre-history-cleanup` branch — a deliberate safety snapshot from a May 2026 history rewrite (diverged root, ~90 commits). Not agent debris; leave it alone.
- Any UX/design decision (visual treatment, interaction model, wording users will read) — surface it to the user via the foreman's `DECISION NEEDED` line rather than picking one. Scorecard/code-quality findings do not require this; user-facing behavior changes do.
- Do not skip or shortcut the pre-commit checklist (Rules 1–8) to push faster, even under a green gate or a time-sensitive-seeming fix — full autonomy on *when* to push doesn't change the bar for *what's* allowed to be pushed.

### Requests lane

`ASKS.md` (repo root) — the user's own asks, ranked, tracked separately from machine-found work (`bugs.md`'s "Still open" list and `/scorecard` findings). One agent must always be working the top open item in `ASKS.md` before any scorecard-remediation or other machine-originated work is dispatched.

### Setup version

v1, hand-written 2026-09-01. No formal `/project-setup` baseline exists for this repo.
