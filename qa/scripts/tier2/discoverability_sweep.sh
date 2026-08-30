#!/usr/bin/env bash
# QA-DISC-001: Discoverability Contract visual sweep
#
# Enforces docs/UI_GUIDELINES.md's "Discoverability Contract" — this is a
# judgment call an LLM can make and a contrast formula can't ("can a
# first-time user tell how to get back to editing, switch tabs, close a
# tab, or quit from this screen?"). Sweeps a matrix of {context x width x
# theme}, screenshots each, and asks a vision-capable LLM a structured
# question per screenshot. Requires ZEPTO_QA_API_KEY/ANTHROPIC_API_KEY/
# OPENAI_API_KEY (see qa/lib/llm-judge.sh) — skips gracefully without one.
#
# This does NOT replace tests/discoverability_core_nav.t (the
# deterministic "is this command even eligible for a pill" check) — it
# catches what that test structurally cannot: whether a command that IS
# eligible actually renders somewhere the user can see it in their
# CURRENT context, and whether the overall screen reads as discoverable
# to a first-time user, not just a registry table.
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-DISC-001: Discoverability Contract sweep"

if ! qa_llm_available; then
    qa_skip "discoverability sweep" "LLM not configured (set ANTHROPIC_API_KEY or ZEPTO_QA_API_KEY)"
    qa_summary
    exit 0
fi

DISC_PROMPT='You are auditing a terminal text editor against this rule: "A user has never read any documentation and never will. Everything must be discoverable by looking at the running application alone." Looking ONLY at this screenshot, answer: can a first-time user tell (a) how to quit, (b) how to switch to the next/previous tab, (c) how to close the current tab, (d) how to move focus between the file tree and the editor (if a tree is visible), and (e) where to go to find every other command if the one they want is not visible? For each of the 5, say YES (a visible on-screen hint exists) or NO (not shown anywhere on this screen). Also flag anything else that looks broken, misaligned, or illegible. Reply PASS only if all 5 are YES and nothing looks visually broken; otherwise reply FAIL: <which of a-e are NO, plus any other issue>.'

sweep_one() {
    local label="$1" cols="$2" rows="$3" theme_keys="$4" setup_fn="$5"
    file=$(qa_tmpfile_nl "disc_${label}.txt" "alpha
beta
gamma")
    qa_start "$file"
    qa_resize_window "$cols" "$rows"
    "$setup_fn"
    for tk in $theme_keys; do
        if [[ "$tk" == "light" ]]; then
            qa_keys "ctrl-t" 0.4
        fi
        shot="$QA_TMPDIR/disc_${label}_${cols}x${rows}_${tk}.png"
        qa_screenshot "$shot"
        qa_assert_visual "$shot" "$DISC_PROMPT" "${label} @ ${cols}x${rows}, ${tk} theme"
    done
    qa_stop
}

noop() { :; }
focus_tree() { qa_keys "ctrl-b" 0.4; }

# Document context: default width, narrow, very narrow — both themes.
sweep_one "document" 80 24 "dark light" noop
sweep_one "document" 60 20 "dark light" noop
sweep_one "document" 40 15 "dark light" noop

# File tree focused: does the on-screen hint set change to explain
# tree<->editor focus switching, or does it stay document-oriented?
sweep_one "filetree" 80 24 "dark light" focus_tree

qa_summary
