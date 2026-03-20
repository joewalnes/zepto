#!/bin/sh
# Zepto installer — https://zepto.now
# Usage: curl -fsSL https://zepto.now/get | sh
#    or: curl -fsSL https://zepto.now/get | sh -s -- /custom/path
set -e

ZEPTO_URL="https://github.com/joewalnes/zepto/releases/download/latest/zepto"

TMPFILE=$(mktemp "${TMPDIR:-/tmp}/zepto-install.XXXXXX")
trap 'rm -f "$TMPFILE"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$ZEPTO_URL" -o "$TMPFILE"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMPFILE" "$ZEPTO_URL"
else
    echo "Error: curl or wget is required to download zepto" >&2
    exit 1
fi

perl "$TMPFILE" --install "$@"
