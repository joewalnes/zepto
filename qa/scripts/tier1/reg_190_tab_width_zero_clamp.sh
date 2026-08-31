#!/usr/bin/env bash
# QA-REG-190: A hand-edited "tab_width": 0 in preferences.json no longer
# crashes or wedges Zepto -- Preferences::set()/_load_from_store() now
# clamp non-positive tab_width to 1 instead of persisting/loading it
# as-is.
#
# Bug: Preferences::set() performed zero validation, and a hand-edited
# tab_width: 0 in preferences.json (intentionally hand-editable per this
# project's docs) would load straight into memory unvalidated. The one
# place that actually divides by tab_width (Preferences::visual_width())
# would then hit an uncaught "Illegal modulus zero" fatal the moment
# anything called it. See bugs.md P3 "Preferences::visual_width divides
# by zero on tab_width == 0" and tests/preferences.t for the unit-level
# proof (including a load-path-specific regression: _load_from_store()
# writes directly into $self->{prefs}, bypassing set() entirely, so the
# clamp had to be shared via _validate_value() rather than living only in
# set()).
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-REG-190: A poisoned tab_width=0 in preferences.json is clamped, not fatal"

# preferences.json lives directly at $state_dir/preferences.json (see
# StateStore::_file_path: "$base_dir/$category.json"). Pre-seed a
# poisoned value exactly as a user hand-editing the file might produce.
echo '{"tab_width": 0}' > "$QA_STATE_DIR/preferences.json"

file=$(qa_tmpfile_nl "reg190.txt" "hello")
qa_start "$file"

qa_assert_expect "hello" "editor starts up normally with a poisoned tab_width=0 in preferences.json (no crash)"

# The clamped value must be visible wherever the preference itself is
# surfaced -- the Tab Width palette command's prefilled current value.
qa_keys "ctrl-space"
qa_send "Tab Width"
qa_keys "enter"
sleep 0.3
qa_assert_screen "Tab Width: 1" "Tab Width command shows the clamped value (1), not the poisoned 0"

qa_keys "escape"
sleep 0.2
qa_keys "ctrl-q"
sleep 0.2
qa_send "n"
qa_summary
