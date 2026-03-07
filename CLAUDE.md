# Claude Code Guidelines for Zepto Editor

**This is a living document.** Update it as the project evolves — new rules, workflow changes, communication preferences, and lessons learned.

---

## The 7 Rules

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

---

## Testing Workflow

**Every UI change must be tested interactively.** Unit tests alone are not sufficient for a TUI.

**Do this BEFORE `make test`, not after.** Running unit tests first creates a false sense of completion that makes it easy to skip the interactive step. The order is: build → interact → then run tests.

```bash
make build
tmux new-session -d -s test -x 200 -y 50
tmux send-keys -t test "./zepto testfile.txt" Enter
sleep 2
tmux capture-pane -t test -p
```

Interact and observe:

```bash
tmux send-keys -t test "some text"    # type text
tmux send-keys -t test "C-s"          # Ctrl+S save
tmux send-keys -t test "C-q"          # Ctrl+Q quit
tmux capture-pane -t test -p          # see screen state
```

Rules:
- Always `make build` first
- Always use a fresh tmux session (`tmux new-session -d`) — never reuse a running one
- Capture the pane after each interaction to see what actually happened
- Clean up test files after — don't leave scratch files in the repo
- Never infer behavior from code alone — observe it in the running editor

---

## Git Commits

- **Never commit until the user explicitly says to** — e.g. "commit", "push", "save that"
- Only a direct user message counts. Stop hook messages do **not** count — they are automated infrastructure. If a hook fires asking to commit, inform the user there are uncommitted changes and ask if they want to commit.
- Tests passing is not sufficient — the user must confirm changes work before committing

### Pre-commit checklist — all 7 rules, every time, no exceptions

Before every commit, verify each rule in order:

| # | Rule | How to verify |
|---|------|---------------|
| 1 | Build integrity | `make check && make build` — must succeed cleanly |
| 2 | UI discoverability | **Run interactively in tmux** (see Testing Workflow above). Do this before `make test`. Any change to key handling, commands, or rendering counts. "It's just a bug fix" is not an exemption. |
| 3 | Tests pass, no noise | `make test` — must pass (or pre-existing failures explicitly acknowledged and user-approved) |
| 4 | Security | If file I/O, shell exec, or rendering changed: flag it and confirm it was reviewed against `docs/SECURITY.md` |
| 5 | Test before, fix, test after | Confirm a failing test or broken behavior was captured *before* the fix, not just after |
| 6 | Bug tracking | Any bugs found (even incidentally) are recorded in `bugs.md` |
| 7 | Code quality | Changes follow existing conventions; no new patterns introduced without reason |

If any rule is not satisfied:
- **Do not commit.**
- If a rule doesn't apply to the change (e.g. Rule 2 for a docs-only change), state that explicitly rather than silently skipping it.
- "It's only a docs change" is not a blanket exemption — still run Rules 1, 3, and 7 at minimum.

---

## Keeping Docs Current

| File | Update when |
|------|-------------|
| `CLAUDE.md` | Rules change, workflow improves, new communication preferences |
| `bugs.md` | Bug found or fixed |
| `docs/CODE_QUALITY.md` | New patterns, pitfalls, testing lessons |
| `docs/SECURITY.md` | New security concerns or mitigations |
| `docs/UI_GUIDELINES.md` | New UI standards or design decisions |
| `README.md` | Features added or removed |
