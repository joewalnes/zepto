#!/usr/bin/env bash
# QA-PERF-017: Pasting a large block of text completes within budget
# (not a hang, not gross sluggishness)
#
# See qa/lib/qa-perf-helpers.sh header for why this is timing-based, not
# vision-based, and for the pass/slow/hang distinction.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
source "$(dirname "$0")/../../lib/qa-perf-helpers.sh"
qa_header "QA-PERF-017: Large paste completes within budget"

# 6000 lines. Line 4000 carries a unique marker that will become the LAST
# line of the pasted block (see selection below) -- it's far enough from
# the paste target (near line 6000) to be off-screen before the paste,
# and the cursor lands exactly on it once the paste completes, so its
# appearance on screen is an unambiguous "paste finished rendering"
# signal (unlike a marker that's already scrolled into view beforehand).
content=""
for i in $(seq 1 3999); do content+="noisepasteline${i}"$'\n'; done
content+="PASTEBLOCK_TAIL_UNIQUE"$'\n'
for i in $(seq 4001 5999); do content+="noisepasteline${i}"$'\n'; done
content+="ORIGINALTAILMARKER"$'\n'
file=$(qa_tmpfile_nl "perf017.txt" "$content")
qa_start "$file"

# Select lines 1-4000 (a large ~4000-line block) and copy it: jump to
# line 4001 col 1 (goto-line lands BEFORE that line's content, so this
# is the boundary right after all of line 4000), then Shift+Ctrl+Home
# selects back up to the doc start -- this is the fix for a real off-by-
# one found while validating this script: landing at 4000:1 instead and
# selecting from there only captures lines 1-3999 plus an empty prefix
# of line 4000, silently excluding line 4000's actual content. Shift+
# Ctrl+Home has no hangon key name (see sel_018_shift_ctrl_home.sh for
# precedent): CSI 1;6H.
qa_keys "ctrl-g" 0.1
qa_send "4001" 0.2
qa_keys "enter" 0.2
qa_raw $'\x1b[1;6H' 0.3
qa_keys "ctrl-c" 0.2

# Jump to the true end of the file and open a fresh line to paste onto.
qa_raw $'\x1b[1;5F' 0.2   # Ctrl+End
qa_keys "enter" 0.1

t0=$(qa_perf_now)
qa_keys "ctrl-v" 0

qa_assert_perf "large paste (~4K lines) completes and renders" 4 "PASTEBLOCK_TAIL_UNIQUE" 20 "$t0"

qa_keys "ctrl-q" 0.2
sleep 0.2
qa_send "n" 0.2   # decline save if a dirty-quit prompt appears
qa_summary
