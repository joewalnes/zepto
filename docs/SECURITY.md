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
| **Network** | Zepto makes zero network connections EXCEPT the opt-in AI completion feature (see "Network: AI Completion" below). Every other subsystem must remain fully offline permanently. |

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
- Enforce discovery limits (Config.pm): **10,000 files max**, **15 directory levels deep**

### Shell Execution

Shell commands are limited to four places:
- **VCS integration**: `git` commands in `lib/Zepto/VCS/Git.pm`
- **Clipboard tools**: xclip / pbcopy / xsel / wl-copy in `lib/Zepto/Terminal.pm`
- **File search**: `git grep`, `rg`, `grep` in `lib/Zepto/FileSearchEngine.pm`
- **AI completion HTTP transport**: `curl` in `lib/Zepto/AIHttp.pm` (the sole network-capable subprocess in the codebase — see "Network: AI Completion" below)

Rules:
- All user-controlled strings passed to the shell **must** be quoted with `_shell_quote()` or equivalent
- Prefer targeted git subcommands over generic shell pipelines
- Do not expand the set of shelled-out programs without security review

```perl
# Correct — safe
my $cmd = "git diff -- " . _shell_quote($path);

# Wrong — injectable
my $cmd = "git diff -- $path";
```

**File search** (`lib/Zepto/FileSearchEngine.pm`):
- Commands: `git grep`, `rg` (ripgrep), `grep` — for cross-file text search
- Quoting: list-form `open(my $fh, '-|', @cmd)` — no shell interpolation; search pattern passed via `-e` flag as a direct argument, never interpolated into a string
- Scope directory validated with `-d` before use
- Results are display-only until user explicitly selects one to open

If a new shell exec is needed, it must:
1. Accept only a fixed command with quoted arguments — never a user-supplied command string
2. Be documented here with its purpose and quoting approach

### Network: AI Completion

Zepto's only network-capable feature is AI ghost-text completion
(`lib/Zepto/AIComplete.pm`, `lib/Zepto/AIHttp.pm`, `lib/Zepto/AIProviders.pm`,
the AI Settings dialog in `lib/Zepto/Editor/Dialog.pm`). This is a
deliberate, owner-sanctioned exception to "no network calls" — not a
loophole. It is held to a stricter bar than the rest of the codebase:

- **Off by default.** `ai_provider` / `ai_api_url` / `ai_model` all default
  to empty, and `AIComplete->load_config()` always sets `enabled => 0`
  regardless of what's persisted. The only code path that can flip it on
  is the explicit "AI: Toggle Completion" command.
- **Explicit, endpoint-named consent required before every new endpoint.**
  Enabling shows: `Sends text near your cursor to <base_url> as you type.
  Enable?` (Y/N). Acceptance is remembered per-endpoint (StateStore
  `preferences` category, key `ai_consented_urls`) — pointing the feature
  at a *different* endpoint (changing provider or base URL) clears that
  memory for the new URL and re-asks. See `cmd_toggle_ai` /
  `_ai_enable_with_consent` in `lib/Zepto/Editor/Commands.pm`.
- **Only cursor-context snippets are sent** — roughly 30 lines before and
  5 after the cursor, plus the filename/language, never the whole file.
  Built by `AIComplete::_build_context`.
- **curl only, never wget**, and only two verbs: `POST {base}/chat/completions`
  and `GET {base}/models`. Every provider goes through the same
  OpenAI-compatible wire adapter (`Zepto::AIProviders`) — there is no
  per-provider bespoke request-building code to audit separately.
- **The API key and request body never touch argv, the child's
  environment, or any file.** `Zepto::AIHttp::start_request` forks a
  child whose argv is `curl -sS --config -` (flags only — no URL, no
  key). The parent writes a curl config document (`url`, `header`,
  `data` directives) to the child's stdin over a pipe. This was a
  deliberate fix: the previous implementation put `Authorization: Bearer
  <key>` on `-H` and the JSON body on `-d`, both directly on curl's
  argv, which is visible to any other user on the machine via `ps`.
- **curl config-string escaping is a reviewed, security-sensitive
  surface.** `Zepto::AIHttp::_escape_config_string` backslash-escapes
  `\` and `"` and encodes `\n`/`\r`/`\t`, per curl's documented `-K`
  config-file quoting rules. If this escaping is wrong, adversarial
  content reaching the config document (e.g. a source file whose text
  ends up in the AI context, containing a crafted quote+newline
  sequence) could inject additional curl config directives. Covered by
  `tests/ai_http.t`: unit tests for each escape case plus an end-to-end
  test that round-trips a payload containing quotes, backslashes, a raw
  newline, unicode, and curly braces through a real curl invocation
  against a local mock server and asserts byte-for-byte equality on the
  received body.
- **The key is stored at rest with mode 0600**, created atomically via
  `sysopen(..., O_CREAT|O_EXCL|O_WRONLY, 0600)` in `StateStore::put` —
  there is no window where the temp file exists with permissive
  permissions (the previous implementation did `open` then `chmod`
  afterward, which had exactly that window).
- **Auth failures are distinguishable from network failures.** curl's
  `write-out` reports the real HTTP status (401/403 vs. connection
  failure), so the Settings dialog's Test button and error messages
  don't conflate "wrong key" with "can't reach the server".
- **If `curl` is not installed**, every AI entry point (toggle, trigger,
  Test Connection) shows a clear message and the feature stays inert —
  it never silently does nothing or crashes. Detected once and cached
  (`Zepto::AIHttp::curl_available`).
- **Timeouts are bounded**: 5s for completion requests, 10s for model
  listing / the Test button — never a network call that can hang the
  editor.

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

- [ ] All shell-interpolated paths are quoted with `_shell_quote()`
- [ ] No new shell commands added without review
- [ ] File permissions preserved on save
- [ ] No new network calls introduced outside the sanctioned AI completion path (`lib/Zepto/AIHttp.pm`)
- [ ] Control characters from file content are neutralized before rendering
- [ ] Path operations stay within expected directories
- [ ] File size/depth limits respected

---

## Open Security Items

| Priority | Item | Location |
|----------|------|----------|
| P3 | Review symlink behavior in FileTree and FilePicker — confirm no unintended traversal | `lib/Zepto/FileTree.pm`, `lib/Zepto/FilePicker.pm` |

## Resolved Security Items

| Priority | Item | Resolution |
|----------|------|------------|
| P2 | Control character stripping in Renderer for file content | Fixed: `next if ord($char) < 0x20` in both render loops in `Renderer.pm` |
| P2 | Terminal title OSC injection via file names with ESC | Fixed: `$title =~ s/[\x00-\x1f]//g` in `set_title()` in `Terminal.pm` |
| P2 | Clipboard command construction in Terminal.pm | Audited: clipboard commands are hardcoded constants, never user-supplied; no injection path |
| P3 | Git path quoting completeness in VCS/Git.pm | Audited: all user-controlled paths go through `_shell_quote()` using correct single-quote escaping; no gaps |
| P1 | AI completion API key visible on `curl` child argv (`ps` on the machine could see `Authorization: Bearer <key>`) | Fixed: rebuilt on `Zepto::AIHttp` — curl child argv is `curl -sS --config -` only, key/body travel via a stdin pipe to `--config -`. Regression-tested in `tests/ai_http.t` (asserts the key never appears in the curl child's `/proc/<pid>/cmdline` or `ps` output while the request is in flight) — see QA-REG entry in `qa/40_regression_bugs.txt`. |
| P2 | AI API key briefly on disk with permissive permissions between file creation and `chmod 0600` (`StateStore::put`) | Fixed: `secrets` category now uses `sysopen(..., O_CREAT\|O_EXCL\|O_WRONLY, 0600)` so the restricted mode is set atomically at creation — no window. Regression-tested in `tests/state_store.t`. |

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
