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
| **Network** | Zepto makes zero network connections. This must remain true permanently. |

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

Shell commands are limited to two places:
- **VCS integration**: `git` commands in `lib/Zepto/VCS/Git.pm`
- **Clipboard tools**: xclip / pbcopy / xsel / wl-copy in `lib/Zepto/Terminal.pm`

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

If a new shell exec is needed, it must:
1. Accept only a fixed command with quoted arguments — never a user-supplied command string
2. Be documented here with its purpose and quoting approach

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
- [ ] No network calls introduced
- [ ] Control characters from file content are neutralized before rendering
- [ ] Path operations stay within expected directories
- [ ] File size/depth limits respected

---

## Open Security Items

| Priority | Item | Location |
|----------|------|----------|
| P2 | Audit Terminal.pm clipboard command construction for injection edge cases | `lib/Zepto/Terminal.pm` |
| P2 | Verify control character stripping in Renderer for file content | `lib/Zepto/Renderer.pm` |
| P3 | Review symlink behavior in FileTree and FilePicker — confirm no unintended traversal | `lib/Zepto/FileTree.pm`, `lib/Zepto/FilePicker.pm` |
| P3 | Verify git path quoting is complete for all commands in VCS/Git.pm | `lib/Zepto/VCS/Git.pm` |

When an item above is investigated and resolved, document the finding and remove it from this list (or move to bugs.md if it becomes a tracked bug).
