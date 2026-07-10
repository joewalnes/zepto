#!/usr/bin/env bash
# QA-REG-021: New saved file visible in file tree
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-021: New saved file appears in tree"

proj_dir=$(mktemp -d /tmp/zepto_qa_reg021_XXXXXX)
echo "existing" > "$proj_dir/existing.txt"

QA_ZEPTO="$(cd "$(dirname "$QA_ZEPTO")" && pwd)/$(basename "$QA_ZEPTO")"
cd "$proj_dir" || exit 1
qa_start existing.txt

# Create a new tab and save it to the same directory. NOTE: deliberately
# NOT opening the tree yet — while the tree panel is focused, keystrokes
# route to it (Editor.pm: "If file tree is focused ... route to tree"), so
# opening it before ctrl-n would silently swallow the typed content below
# (discovered the hard way: "new file content" never reached the buffer
# with the tree open first). Open the tree later, only once we need to
# check it.
qa_keys "ctrl-n"
sleep 0.3
qa_send "new file content"

# Save (untitled buffer -> triggers Save As prompt), per the established
# QA-FILE-002 pattern. NOTE: deliberately NOT using Ctrl+Space here —
# Ctrl+Space is context-sensitive (Editor.pm ~1292-1312): with the cursor
# immediately after a word character (exactly the state right after typing
# "new file content"), it opens the completion menu instead of the command
# palette, so a "ctrl-space" -> type "save as" -> enter flow silently types
# "save as" into the document instead of invoking the command (discovered
# the hard way).
qa_keys "ctrl-s"
qa_expect "Save|save|name|path" 3 || true

newpath="$proj_dir/newfile.txt"
qa_keys "ctrl-a" 0.1
qa_send "$newpath" 0.3
qa_keys "enter"

# Poll for the file to land on disk rather than a blind fixed sleep.
for _ in $(seq 1 20); do
    [[ -f "$newpath" ]] && break
    sleep 0.1
done

# Check the file landed on disk
qa_assert_file_exists "$newpath" "new file saved to disk"

# Now open the tree and confirm the new file is listed.
qa_keys "ctrl-b"
sleep 0.5
qa_assert_screen "newfile" "new file appears in tree"

qa_keys "escape"
qa_keys "ctrl-q"
cd "$OLDPWD"
rm -rf "$proj_dir"
qa_summary
