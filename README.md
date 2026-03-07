# Zepto

A modern, intuitive, terminal text editor. Single file. No dependencies. No config.

**Website: [zepto.now](https://zepto.now)** | **[Full feature list](FEATURES.md)**

## Features

- **Command palette** (`⌃Space`) — discover and run any command
- **50+ syntax languages** — Perl, Python, JS/TS, Go, Rust, C/C++, Java, Ruby, and more
- **Find & replace** with regex support, case toggle, and match highlighting
- **Find in files** — project-wide search with grouped results
- **File tree** sidebar with fuzzy file picker (`⌃O`)
- **Multi-tab** editing with recent files (`⌃E`)
- **Git integration** — inline diff gutter markers, diff view (`⌥D`), change navigation
- **Minimap** overview of document structure
- **Word wrap**, column selection, smart Home/End, location history
- **Dark and light themes** (`⌃T`)
- **Transform via shell** (`⌥T`) — pipe selected text through any command
- **Single file, zero dependencies** — just Perl 5.10+ standard library

## Install

```bash
mkdir -p ~/.local/bin && \
  curl -fsSL https://github.com/joewalnes/zepto/releases/download/latest/zepto \
    -o ~/.local/bin/zepto && \
  chmod +x ~/.local/bin/zepto
```

Then run `zepto myfile.txt`. Or [download manually](https://github.com/joewalnes/zepto/releases/download/latest/zepto).

## Requirements

- Perl 5.10+ (standard library only, no CPAN modules)
- Any terminal with ANSI support

## Building from Source

```bash
make build    # Creates single-file 'zepto' executable
make test     # Run tests
```

## License

MIT
