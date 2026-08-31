#!/usr/bin/env bash
# QA-SESS-005: Files deleted since the session was saved are skipped
# individually at restore, without aborting the rest of the session.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-SESS-005: Missing files skipped at restore"

qa_project; dir="$QA_PROJECT_DIR"
printf 'survivor\n' > a.txt
printf 'will vanish\n' > b.txt

qa_start
qa_keys "ctrl-o"
qa_send "a.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-o"
qa_send "b.txt" 0.3
qa_keys "enter" 0.3
qa_keys "ctrl-q"
sleep 0.4

# Delete b.txt from disk before the next launch. Since it's gone from
# disk, the file tree won't list it either, so a bare "b\.txt" check is
# unambiguous here (unlike sessions where the deleted file is still on
# disk — see sess_003/004, which use the "◢ name ⌥N" tab-bar marker).
rm -f "$dir/b.txt"

qa_restart
qa_wait_screen "◢ a\.txt ⌥1" 5

qa_assert_screen "◢ a\.txt ⌥1" "surviving file (a.txt) restored as the only tab"
qa_assert_not_screen "b\.txt" "deleted file (b.txt) is skipped entirely — gone from tree and tabs"
qa_assert_screen "survivor" "a.txt content loaded correctly"

qa_keys "ctrl-q"
qa_summary
