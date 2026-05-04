#!/usr/bin/env bash
# QA-REG-054: Save preserves file permissions
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-054: Save preserves permissions"

file=$(qa_tmpfile_nl "reg054.sh" "#!/bin/bash\necho hello")
chmod 755 "$file"

qa_start "$file"

# Modify and save
qa_keys "end"
qa_send " world"
qa_keys "ctrl-s"
sleep 0.3

# Check permissions preserved
perms=$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null || true)
if [[ "$perms" == "755" ]]; then
    qa_pass "file permissions preserved after save (755)"
elif [[ -x "$file" ]]; then
    qa_pass "file still executable after save"
else
    qa_fail "file permissions preserved (got $perms)"
fi

qa_keys "ctrl-q"
qa_summary
