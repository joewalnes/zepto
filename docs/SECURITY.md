# Zepto Security Guidelines

Zepto runs on users' desktops with read/write access to all their files. Users trust it. Security is non-negotiable.

**This is a living document.** Update it whenever security concerns are identified or mitigated.

---

## Threat Model

| Threat | Notes |
|--------|-------|
| **File system access** | Zepto can read/write any file the user can. Must stay within user intent — don't access files the user didn't open or navigate to. |
| **Shell injection** | Zepto shells out to git and clipboard tools. Any user-controlled path or content passed to the shell must be safely quoted. |
| **Malicious file content** | Opened files may contain adversarial terminal escape sequences. File content must be sanitized before rendering. |
| **Privilege escalation** | Zepto must not execute with elevated privileges. Never use setuid or sudo. |
| **Network** | Zepto makes zero network connections by default. Optional AI completion feature (disabled by default, requires explicit user configuration of API endpoint + key) makes opt-in calls to OpenAI-compatible APIs via curl. Setup (`cmd_ai_setup`) rejects any API URL that doesn't start with `https://`, so the wizard can't be used to configure a plaintext endpoint — see "AI completion" under Shell Execution below for how the API key itself is kept off the process argv. No network calls are made for any other feature. |

---

## Rules

### File I/O

- Check readability before operating: `-r $path`
- Preserve file permissions on save:
  ```perl
  my $perms = (stat($path))[2] & 07777;
  chmod($perms, $path);
  ```
- Do not follow symlinks outside the working directory without deliberate user action
- Validate that resolved paths stay within expected roots — no `../../../etc/passwd` traversal
- Temp files: never build a predictable path by string concatenation (e.g. `"$tmpdir/prefix-$$-$name"`) and open it with a plain `open`/`>`. Use `File::Temp::tempfile()` (unpredictable name, exclusive `O_EXCL` creation) — the established pattern, first used in `Document.pm`'s atomic save, and now also `ImageConverter.pm`'s conversion output and `AIComplete.pm`'s curl `-K` header file. A predictable name with no exclusive creation lets a local attacker who can guess the path (e.g. from a visible PID) pre-plant a symlink that gets followed and written through. If a temp file needs specific permissions tighter than the process default (e.g. secrets), set them atomically at creation with `sysopen(..., O_CREAT|O_EXCL|O_WRONLY, $mode)` rather than `open` followed by a later `chmod` — the gap between the two is a real window where the file exists at the wrong (more permissive) mode. A temp file holding a secret must also be deleted as soon as it's no longer needed (not left for the OS/tmp-cleaner to eventually reap) — `AIComplete.pm` unlinks its header file both on normal request completion and from a `SIGTERM` handler, since the editor cancels in-flight AI requests via signal on essentially every keystroke.
- Enforce discovery limits (Config.pm): **10,000 files max**, **15 directory levels deep**

### Shell Execution

Shell commands are limited to six places, all using safe list-form `exec()` or `system()` with argument arrays (no shell interpolation):

1. **VCS integration** (`lib/Zepto/VCS/Git.pm`): `git` commands via list-form `open(FH, '-|')` + `exec('git', @args)`
2. **Clipboard tools** (`lib/Zepto/Terminal.pm`): xclip / pbcopy / xsel / wl-copy via list-form pipes and `exec()`
3. **File search** (`lib/Zepto/FileSearchEngine.pm`): `git grep`, `rg` (ripgrep), `grep` via list-form `open()` and `exec()`. Search pattern passed via `-e` flag as a direct argument, never interpolated into a string. Scope directory validated with `-d` before use. Results are display-only until user explicitly selects one to open.
4. **Image format conversion** (`lib/Zepto/ImageConverter.pm`): `sips` (macOS) or `convert` (ImageMagick) via `system()` with argument arrays. Command detection uses backtick `which` but only for hardcoded literal commands, never user-supplied. The conversion output path is created via `File::Temp::tempfile()` (unpredictable name, exclusive `O_EXCL`-backed creation) — matching `Document.pm`'s atomic-save pattern — so `sips`/`convert` can never be pointed at a pre-planted symlink.
5. **Text transformation** (`lib/Zepto/Editor/Commands.pm` `cmd_transform`, Alt+T): User-typed shell command piped to `sh -c`. This is an intentional capability — users consciously choose to run arbitrary shell commands on selected text, similar to a terminal. Not injection; users are explicitly requesting shell execution.
6. **AI completion** (`lib/Zepto/AIComplete.pm`): `curl` for requests to AI APIs via list-form fork+`exec('curl', ...)`. Only enabled when user configures an API endpoint + key (disabled by default). The `Authorization: Bearer <key>` header is **not** passed as a `-H` argv token — process argv is visible to any local user via `ps`/`/proc/<pid>/cmdline` for the curl child's whole lifetime, and this request fires repeatedly while typing. Instead, `_child_http_request()` writes `header = "Authorization: Bearer <key>"` to a short-lived temp file (`File::Temp::tempfile()`, same unpredictable-name + exclusive-creation pattern as `Document.pm`/`ImageConverter.pm`, plus `chmod 0600`) and passes it via `curl -K <file>`, deleting the file immediately after the request completes or is cancelled (including via the `SIGTERM` the editor sends to cancel an in-flight request on the next keystroke). See bugs.md and `qa/40_regression_bugs.txt` QA-REG-209.

**Current mitigation strategy:**
- All shell execution uses list-form pipes and `exec()`, never shell string interpolation
- This is fundamentally safer than string quoting because it eliminates the shell as an interpreter entirely
- User-controlled data (file paths, search patterns, etc.) never reaches the shell; they're passed as direct arguments to command invocations

**Rules for new shell execution:**
1. Use list-form `open(my $fh, '-|', @cmd)` + `exec()` or list-form `system(@args)` — never build command strings
2. Fixed commands only — never user-supplied command names
3. User-controlled data passed as arguments, not interpolated into command strings
4. Document the new location here with its purpose and approach
5. Flag for security review before merging

### Rendering Safety

- Terminal escape sequences in file content must be stripped or neutralized before display — a crafted file must not be able to hijack the terminal
- Box-drawing characters and UI escape sequences come from trusted constants only (never from file content)
- ANSI color codes from file content must not pass through to the terminal unescaped

### UTF-8 Handling

- Use Unicode codepoints (`\x{XXXX}`) — never raw byte strings like `"\xe2\x94\x82"`
- Add `use utf8` to any file containing Unicode literals
- Encode before final output: `utf8::encode($output) if utf8::is_utf8($output)`
- Never use `length()` for display width — it returns character count, not column width; CJK and combining characters break naive length assumptions

### Clipboard

- Clipboard content from the OS is untrusted user input — never auto-execute it
- Paste inserts content as literal text into the buffer — no interpretation, no execution

---

## Audit Checklist

Run through this before committing any change that touches file I/O, shell execution, or rendering:

- [ ] All shell execution uses list-form pipes/`system()` — never shell string interpolation
- [ ] No new shell commands added without review and documentation in this file
- [ ] File permissions preserved on save
- [ ] No network calls introduced (except via AI completion, which must be opt-in with user config)
- [ ] Control characters from file content are neutralized before rendering
- [ ] Path operations stay within expected directories (use `Cwd::realpath()` to resolve symlinks)
- [ ] File size/depth limits respected

---

## Open Security Items

(No open items at this time)

## Resolved Security Items

| Priority | Item | Resolution |
|----------|------|------------|
| P3 | Symlink traversal in FileTree and FilePicker | Audited: `Cwd::realpath()` resolves symlinks in root and all discovered paths. Traversal prevention uses `index($real, "$root/") == 0` which correctly requires a slash after root directory (preventing "/root" vs "/rootevil" bypass bug). Both `lib/Zepto/FileTree.pm` (line 112-115) and `lib/Zepto/FilePicker.pm` (line 93-95) implement this pattern correctly. |
| P2 | Control character stripping in Renderer for file content | Fixed: `next if ord($char) < 0x20` in both render loops in `Renderer.pm` |
| P2 | Terminal title OSC injection via file names with ESC | Fixed: `$title =~ s/[\x00-\x1f]//g` in `set_title()` in `Terminal.pm` |
| P2 | Clipboard command construction in Terminal.pm | Audited: clipboard commands are hardcoded constants, never user-supplied; no injection path |
| P3 | Git path quoting completeness in VCS/Git.pm | Audited: all user-controlled paths use list-form `exec()` without shell interpolation; no quoting-bypass gaps |
| P2 | Predictable temp filename with no exclusive creation in `ImageConverter.pm` (symlink-follow risk) | Fixed: conversion output path now created via `File::Temp::tempfile()` (unpredictable name, exclusive `O_EXCL` creation) instead of `"$tmpdir/zepto-img-$$-$basename"` string concatenation. See bugs.md and `qa/40_regression_bugs.txt` QA-REG-193. |
| P2 | AI API key briefly world-readable before `chmod 0600` catches up in `StateStore.pm` | Fixed: the `secrets` category now uses `sysopen(..., O_WRONLY\|O_CREAT\|O_EXCL, 0600)` — mode set atomically at creation, no window. Other categories intentionally keep default umask permissions (no secrets). See bugs.md and `qa/40_regression_bugs.txt` QA-REG-194. |
| P2 | `VCS/Git.pm::is_tracked()` git argument-injection edge case (dash-prefixed filename) | Fixed: added `'--'` separator before the pathspec in the `ls-files` call. Audited every other `_git(...)` call site in the file; no other gaps found. See bugs.md and `qa/40_regression_bugs.txt` QA-REG-195. |
| P2 | AI API key passed as a `curl` command-line argument (`-H "Authorization: Bearer $api_key"`), visible to other local users via `ps`/`/proc/<pid>/cmdline` for the curl child's lifetime — fires on every AI completion request while typing | Fixed: `AIComplete.pm::_child_http_request()` now writes the header to a short-lived, mode-0600 `File::Temp` file and passes it via `curl -K <file>` instead, deleting it after the request completes or is cancelled (including via `SIGTERM`). See bugs.md and `qa/40_regression_bugs.txt` QA-REG-209. |
| P3 | AI API URL had no scheme enforcement — a mistyped/pasted `http://` endpoint would silently send the API key in plaintext | Fixed: `cmd_ai_setup`'s step-1 URL prompt now rejects any non-`https://` URL via `show_error_message()` before saving anything. See bugs.md and `qa/40_regression_bugs.txt` QA-REG-210. |

When an item above is investigated and resolved, document the finding and remove it from this list (or move to bugs.md if it becomes a tracked bug).

---

## Perl CVE Assessment (5.34+)

Users may run any Perl version shipped with their OS. We cannot require upgrades — instead we avoid dangerous patterns and minimize exposure.

**Last reviewed:** 2026-03-02

### Relevant CVEs

| CVE | Fixed In | Feature | Zepto Risk | Notes |
|-----|----------|---------|-----------|-------|
| **CVE-2023-47038** | 5.40 | `qr//` with illegal Unicode property | Medium | Heap overflow during regex compilation. Reachable via find engine when user enables regex mode — but user is crafting the pattern themselves, so this is self-inflicted. |
| **CVE-2024-56406** | 5.42 | `tr//` with non-ASCII LHS bytes | Low | Heap overflow in transliteration. Zepto only uses `tr//` with hardcoded literal patterns, so not reachable in practice. |
| **CVE-2025-40909** | 5.42 | Thread cloning race | None | Zepto is single-threaded. |
| **CVE-2023-47039** | 5.40 | Windows cmd.exe hijack | None | Windows-only. |

### Rules to Limit Exposure

1. **Never construct `qr//` or `tr//` from file content.** User-typed find patterns are acceptable (self-inflicted risk). But never programmatically compile regexes or transliterations derived from an opened file — that turns a "user opens untrusted file" scenario into a code execution vector.
2. **Keep all `tr//` patterns as string literals.** No dynamic construction.
3. **Never use string `eval` with file-derived content.** The `eval "require $class"` in `Highlighter.pm` is acceptable only because `$class` comes from a hardcoded mapping.
4. **Treat file content as higher risk than keyboard input.** A user typing a crafted regex is attacking themselves. A file silently triggering an overflow on open is an actual exploit. Design accordingly — file content should never reach regex compilation, `tr//`, or `eval`.

### Assessing Future Perl CVEs

1. **What Perl feature is affected?** (regex, `tr//`, IO layers, specific module, etc.)
2. **Does Zepto use it?** `grep -rn 'pattern' lib/ build.pl`
3. **Can file content reach it?** File content reaching the vulnerable path = real risk. User keyboard input reaching it = low risk (self-inflicted). Hardcoded literals reaching it = no risk.
4. **Add to the table above** with the risk assessment. Add defensive rules if needed.

**Where to check:** Perl release deltas (`perldoc.perl.org`), CPANSec (`security.metacpan.org`), NVD (`nvd.nist.gov`).
