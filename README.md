# Zepto

A modern, intuitive, terminal text editor. Single file. No dependencies. No config.

**Website: [zepto.now](https://zepto.now)** | **[Full feature list](FEATURES.md)**

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
