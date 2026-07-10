.PHONY: all test test-verbose clean build install check loc website website-screencaps website-clean qa qa-visual qa-full qa-list qa-coverage

PREFIX ?= $(HOME)/.local

# Default target: test, build, check, loc
all: test build check loc

# Run all tests (fast, parallel)
test:
	@PERL_UNICODE=S prove -l tests/*.t

# Run tests with verbose output
test-verbose:
	@prove -lv tests/*.t

# Run a single test file
test-one:
	@perl -Ilib $(FILE)

# Run tests and show timing
test-timing:
	@time prove -l tests/*.t

# Build website (copy src and pre-built assets to out)
website:
	@mkdir -p website/out/screencaps
	@cp -r website/src/* website/out
	@cp website/assets/screencaps/* website/out/screencaps/
	@cp website/assets/preview-1200x630.png website/out/
	@echo "Website built: website/out/"

# Render screencaps from .tape files (requires vhs, ffmpeg, ttyd)
website-screencaps:
	@mkdir -p website/out/screencaps
	@for tape in website/tapes/*.tape; do \
		echo "Recording $$tape..."; \
		vhs "$$tape" || exit 1; \
	done
	@echo "Screencaps rendered: website/out/screencaps/"

# Clean temporary files
clean:
	@rm -f zepto
	@rm -rf tests/tmp_*
	@rm -rf website/out
	@find . -name '*.bak' -delete

# Build single-file distribution (to be implemented)
build: zepto

MODULES := $(shell find lib -name '*.pm')

zepto: $(MODULES) build.pl
	@echo "Building single-file zepto..."
	@perl build.pl > zepto
	@chmod +x zepto
	@echo "Built: zepto"

# Install to PREFIX/bin
install: zepto
	@mkdir -p $(PREFIX)/bin
	@cp zepto $(PREFIX)/bin/zepto
	@echo "Installed: $(PREFIX)/bin/zepto"

# Check Perl syntax of all modules
check:
	@for f in $$(find lib -name '*.pm'); do perl -c -Ilib $$f || exit 1; done
	@echo "All modules OK"

# Count lines of code
loc:
	@wc -l lib/Zepto/*.pm | tail -1
	@echo "Test lines:"
	@wc -l tests/*.t | tail -1

# =============================================================================
# QA end-to-end tests (require hangon: brew install joewalnes/tap/hangon)
# =============================================================================

# Tier 1 only — deterministic hangon scripts (fast, free, no LLM)
qa: build
	@perl qa/runner.pl --tier 1

# Tier 1 + Tier 2 — includes LLM visual checks. Judge config comes from
# env (ZEPTO_JUDGE_*), ~/.config/zepto-qa/judge.json, or interactive
# first-run setup (tty only) — see qa/README.md. --probe-judge here is a
# non-fatal pre-flight: it just prints an early banner so an unconfigured
# run tells you immediately rather than after tier1 finishes; the runner
# itself re-probes and loudly SKIPS (not silently) tier2 either way.
qa-visual: build
	@-perl qa/runner.pl --probe-judge
	@perl qa/runner.pl --tier 1,2

# All automated tiers
qa-full: build
	@perl qa/runner.pl --tier 1,2

# List available QA scripts without running
qa-list:
	@perl qa/runner.pl --list --tier 1,2

# Report documented-vs-scripted QA coverage (qa/CATALOG.md numbers)
qa-coverage:
	@perl qa/coverage.pl

# Pixel QA tier — drives ./zepto through a real terminal (ttyd) rendered in
# a real browser (Playwright), for real mouse-pixel interactions and (opt-in
# via ZEPTO_PIXEL_SNAPSHOTS=1) visual screenshot diffing. See qa/pixel/README.md.
# Requires: ttyd, Node.js/npm.
qa-pixel: build
	@cd qa/pixel && npm install --no-fund --no-audit && npx playwright test
