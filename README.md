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
- **AI completion** (opt-in) — ghost-text suggestions from OpenAI, Anthropic, OpenRouter, Ollama, and other OpenAI-compatible providers; off by default, asks for consent before sending anything ([details](FEATURES.md#ai-completion-opt-in))
- **Single file, zero dependencies** — just Perl 5.14+ standard library

## Install

```bash
curl -fsSL https://zepto.now/get | sh
```

Or install to a custom location:

```bash
curl -fsSL https://zepto.now/get | sh -s -- /usr/local/bin/zepto
```

Or [download manually](https://github.com/joewalnes/zepto/releases/download/latest/zepto) and run `zepto --install`.

## Requirements

- Perl 5.14+ (standard library only, no CPAN modules)
- Any terminal with ANSI support

## Building from Source

```bash
make build    # Creates single-file 'zepto' executable
make test     # Run unit tests
make qa       # Run end-to-end QA tests (requires hangon)
```

## License

MIT
