#!/usr/bin/env bash
# QA-SEC-001: Path traversal via symlink escape is bounded
#
# The original version of this script "tested" Save-As with a traversal
# path that normalized right back into /tmp (not a real escape attempt)
# and had no qa_fail branch anywhere — it could not catch a regression
# no matter what. Investigation (see bugs.md FIXED writeup) found that
# Save-As has NO root-confinement in Zepto by design: it's a normal
# desktop-editor Save As that can write anywhere the OS user can write,
# exactly like every other text editor. There is no "sandbox" for Save-As
# to escape, so a traversal test against it can never be meaningful.
#
# The real, documented path-traversal protection in this app is the
# symlink-escape check in FileTree.pm's _path_within_root() (see
# docs/SECURITY.md P3 entry, audited). It is implemented independently
# in two places:
#   - _scan_dir_one_level() — powers the interactive tree widget
#     (already covered by QA-SEC-003 / sec_003_symlink.sh)
#   - _walk_for_files() — powers the Ctrl+O "Open File" fuzzy picker
#     (NOT covered elsewhere)
# This script exercises the second, distinct code path: a symlink placed
# inside a project that points outside the project root must not have
# its contents surfaced through the Open File picker's fuzzy file list.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SEC-001: Path traversal via symlink escape is bounded"

qa_project; dir="$QA_PROJECT_DIR"

# A real, in-project file — proves the picker + fuzzy filter actually
# work at all, so a "not found" result below means traversal was
# blocked, not that the picker itself is broken/no-op.
echo "real content" > "$dir/real_file_sec001.txt"

# A file OUTSIDE the project root that traversal would need to reach.
outside_dir=$(mktemp -d /tmp/zepto_qa_sec001_outside_XXXXXX)
echo "should never be listed" > "$outside_dir/secret_outside_sec001.txt"

# Symlink inside the project pointing outside its root — the classic
# path-traversal-via-symlink vector _path_within_root() must block.
ln -s "$outside_dir" "$dir/escape_link_sec001"

qa_start "$dir/real_file_sec001.txt"

# Open the picker WITHOUT typing any filter text. With an empty query,
# _filter_all_files() lists every discovered project file directly (no
# fuzzy scoring/echo involved), so nothing we type can leak into the
# screen and contaminate the assertions below — the picker's rendered
# list is the only source of these strings.
qa_keys "ctrl-o"
sleep 0.3

# Sanity check: the in-project file is listed (catches a broken/no-op
# picker, which would otherwise make the negative check below pass for
# the wrong reason).
qa_assert_screen "real_file_sec001" "in-project file is discoverable via Open File picker (sanity check)"

# Protection check: the file that only exists by walking through the
# escaping symlink must NOT be listed.
qa_assert_not_screen "secret_outside_sec001" "file reached only via symlink escape is NOT exposed by Open File picker (path traversal blocked)"

qa_keys "escape"
qa_keys "ctrl-q"
rm -rf "$outside_dir"
qa_summary
