.PHONY: all test test-verbose clean build install check loc website website-screencaps website-clean

PREFIX ?= $(HOME)/.local

# Default target: test, build, check, loc
all: test build check loc

# Run all tests (fast, parallel)
test:
	@prove -l tests/*.t

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

zepto: $(MODULES)
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
