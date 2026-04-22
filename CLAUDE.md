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

**Every new feature, bug fix, or behavioral discovery must update the QA plan.**

- **New feature**: add a test case to the appropriate `qa/NN_*.txt` file
  covering happy path, key edge cases, and how to verify the feature is
  discoverable from the UI.
- **Bug fix (including regressions)**: add a `QA-REG-###` entry to
  `qa/40_regression_bugs.txt` with a cross-ref to the primary feature
  test. The regression file is a flat index of every fixed bug.
- **Behavioral discovery**: when you learn something non-obvious about
  how Zepto behaves (from code reading, user report, or interactive
  testing), add a test case so it can't regress silently.
- **Always update `qa/CATALOG.md`**: add the new test ID under the right
  file's section. IDs are stable — never renumber. To retire a test,
  mark it `[RETIRED]` in place rather than deleting.

Test IDs are `QA-<TAG>-<NNN>` where `<TAG>` is the 3-6 char feature tag
listed in `qa/CATALOG.md`. Use the next unused number within that tag.

If a change doesn't warrant any QA update — which should be rare — say
so explicitly rather than skipping silently (same rule as Rule 2).

Full plan: `qa/README.md`.

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

# Clean up any stale sessions first
hangon stopall

# Start zepto in a session
hangon start process --name zepto -- ./zepto /tmp/testfile.txt

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
| `hangon stop NAME` | Stop a session |
| `hangon stopall` | Stop all sessions |

#### Tips

- Always `hangon stopall` before starting a new test session to avoid stale sessions
- Use `sleep 0.3` or `sleep 0.5` after send/keys before `screen` to let the editor render
- Chain independent sends with `&&` for efficiency
- Use `--name` to run multiple sessions in parallel (e.g., testing cross-tab features)
- Use `hangon expect` instead of `sleep` when waiting for specific output — it's faster and more reliable

### Rules

- Always `make build` first
- Capture the screen after each interaction to see what actually happened
- Clean up test files after — don't leave scratch files in the repo
- Never infer behavior from code alone — observe it in the running editor

---

## Git Commits

- **Never commit until the user explicitly says to** — e.g. "commit", "push", "save that"
- Only a direct user message counts. Stop hook messages do **not** count — they are automated infrastructure. If a hook fires asking to commit, inform the user there are uncommitted changes and ask if they want to commit.
- Tests passing is not sufficient — the user must confirm changes work before committing

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
| 8 | QA plan current | New feature → new test case in the right `qa/NN_*.txt`. Bug fix → new `QA-REG-###` in `qa/40_regression_bugs.txt`. Discovery → corresponding test case. Update `qa/CATALOG.md` with new IDs. |

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
| `qa/CATALOG.md` | Any new or retired QA test ID |
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
