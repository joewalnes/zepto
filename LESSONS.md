# Lessons

Append-only ledger for `/go-team` — add an entry only when something actually bites, not per cycle. Before adding, check whether an existing entry should be sharpened instead of duplicated.

```markdown
## <short title>
**What happened:** ...
**What it cost:** ...
**The rule that would have prevented it:** ...
**Scope:** project | general
```

---

## `git stash` is a shared singleton across worktrees, not per-worktree

**What happened:** the foreman's dispatch brief told workers to prove their guard/test fails pre-fix and passes post-fix by `git stash push -- <changed file>` / build / test / `git stash pop`, following the pattern this project's own history had already used successfully (single-worktree, single-agent). Run concurrently across multiple worktrees on the fleet's first cycle, two workers (`agent-undo-group`, and a sibling worktree) both used `git stash` at overlapping times. `git stash`'s ref (`refs/stash`) is shared by the whole repository, not scoped per-worktree, even though the worktrees themselves are isolated — so two agents stashing concurrently can clobber or cross-apply each other's stash. Caught and self-recovered by `agent-undo-group` mid-run without using stash again; no lasting damage this time, but it was luck, not the design, that prevented it.

**What it cost:** one worker had to detect and recover from a stash collision mid-task (time cost, and a genuine risk of one agent applying another agent's diff to its own files had the timing been slightly different).

**The rule that would have prevented it:** treat `git stash` as a shared machine-wide singleton exactly like `hangon`'s state dir or the primary checkout's branch — never use it for anything that must run correctly under concurrent agents. Prove pre-fix-fails/post-fix-passes without it instead: build the pre-fix binary from a throwaway worktree at the parent commit (`git worktree add -f --detach <tmp> HEAD~1` or similar, if the change is already committed), or diff/patch a scratch copy of just the file (`git show HEAD:path/to/file.pm > /tmp/prefix-file.pm`, swap it in for one build, swap back) instead of stashing in the shared checkout. Update the foreman's standing worker-dispatch template to say this explicitly, not just this one cycle's briefs.

**Scope:** general — this applies to any multi-worktree fleet on any project, not just Zepto.

---

## Dispatched workers have no way to address the foreman directly

**What happened:** the foreman's brief told it to dispatch worker agents, but didn't tell those workers the foreman's actual resolvable address (an agent ID, not the generic type name "general-purpose"). Every worker that finished tried to report back, failed to resolve an address, and fell back to messaging the top-level session ("main") instead — which worked only because the account-manager session happened to be watching and relayed manually. Workers also don't have the `ListAgents` tool themselves, so they can't self-resolve even if they tried harder.

**What it cost:** three separate ad hoc relay messages the account manager had to notice, parse, and forward by hand instead of the foreman receiving them directly and processing them in its own verify/gate/merge loop — a manual workaround standing in for a missing piece of dispatch design, and a real risk that a report gets missed if the account manager isn't actively watching.

**The rule that would have prevented it:** every worker dispatch brief must include the foreman's own literal resolvable address (whatever `ListAgents`/the spawn result shows for the foreman itself) with an explicit instruction to `SendMessage` its final report there — not rely on the worker guessing a name, and not rely on a human/account-manager acting as an accidental relay. If the foreman doesn't know its own address, it should ask (or the account manager should tell it up front, in the initial dispatch brief) rather than leaving it for workers to discover by failing.

**Scope:** general — applies to any orchestrator spawning sub-workers that need to report back asynchronously.

---

## Per-catalog QA ID numbering collisions aren't limited to QA-REG

**What happened:** the foreman's dispatch briefs told each worker to find its next free `QA-REG-###` number and warned about cross-branch `QA-REG` collisions (which did happen, and were caught). But `qa/09_find_replace.txt` uses its own separate `QA-FIND-###` numbering, and two unrelated fixes in the same cycle (`add-sigwarn-handler` and `fix-document-replace-undo-group`) each independently added a *new* `QA-FIND-031` catalog entry — a straight duplicate ID, not just a near-miss like the `QA-REG` case. Neither worker could have caught this: each only checked the one catalog its own fix touched, and CLAUDE.md's own generic numbering convention (`grep -rho 'QA-<TAG>-[0-9]*' qa/ | sort -V | tail -1`) was never given to workers explicitly — only a `QA-REG`-specific reminder was. Caught by the foreman only at merge-gating time, via a duplicate-ID sweep across every `qa/*.txt` catalog's `^ID:` lines (not just the one file being merged) — an ad hoc check invented on the spot, not a standing part of the gating checklist yet.

**What it cost:** one silent duplicate primary ID that would have shipped to `main` if the foreman had only diffed the merging branch's own catalog file (which showed no internal conflict — the two `QA-FIND-031` entries lived in *different*, not-yet-merged branches, so a same-branch check wouldn't have seen the clash either). Required a manual renumber (`QA-FIND-031` → `QA-FIND-032`) plus every cross-reference (`bugs.md`, `qa/40_regression_bugs.txt`'s CROSS-REF field) fixed to match, after the fact.

**The rule that would have prevented it:** any feature area's fix can add a new ID to a catalog *other than* `qa/40_regression_bugs.txt` (feature-specific files like `qa/09_find_replace.txt` have their own `QA-<TAG>-###` sequence) — remind workers of the general convention, not just `QA-REG`, whenever a fix might also need a feature-catalog entry (most bug fixes do, per Rule 8's cross-ref requirement). More importantly: at every merge-gating step, run a duplicate-ID sweep across *all* `qa/*.txt` catalogs' `^ID:` lines (`for f in qa/*.txt; do grep -oh '^ID:\s*QA-[A-Z]*-[0-9]*' "$f"; done | awk '{print $2}' | sort | uniq -d` — must be empty), not just the numbering scheme of the one file the current merge touches. Make this a standing step in the gate checklist, every merge, not an ad hoc catch.

**Scope:** general — applies to any fleet where concurrent workers can each add catalog/index entries with their own locally-computed "next free number."

---

## Tight-millisecond-bound perf tests flake under fleet-scale CPU contention

**What happened:** across a single wave of 5 concurrent workers (each building/testing in its own worktree, plus the foreman gating each merge in yet another isolated worktree), `tests/find_engine_perf.t` and `tests/filetree_vcs_perf.t` — both pre-existing timing tests with tight absolute-millisecond bounds (e.g. "P95 < 20ms") — flaked repeatedly during gating, on branches that touched neither file. One worker measured a load average of 119 on a 16-core machine while this was happening. Every flake resolved on an immediate rerun with zero code changes, and re-running the exact same test on a fresh, unrelated worktree at the same commit sometimes passed clean — confirming it was never a real regression, just CPU contention from the fleet's own scale.

**What it cost:** repeated, near-identical diagnostic work at multiple gates in the same session (the foreman re-derived "this is pre-existing and load-related" from scratch more than once before two separate workers independently reported the same root cause, which then had to be cross-checked rather than simply trusted).

**The rule that would have prevented it:** any test asserting an absolute wall-clock bound (not a relative before/after ratio) is a known false-positive risk under a fleet's own concurrent load, and should be triaged that way by default: (1) confirm the failing test doesn't touch any file the branch under test actually changed, (2) rerun once in isolation, (3) if it passes, treat it as environmental and move on — don't re-investigate from scratch at every subsequent gate. Longer-term, these tests should either use relative bounds (compare against a freshly-measured baseline in the same run, the way the project's own newer perf tests already do — e.g. `filetree_vcs_perf.t`'s "old vs new, same process" pattern) or skip/widen their bound when system load is detectably high, rather than hardcoding an absolute millisecond ceiling that assumes an idle machine.

**Scope:** general — applies to any project with absolute-timing tests run under a concurrent multi-worker fleet, not just this one.
