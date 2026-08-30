#!/usr/bin/env bash
# ===========================================================================
# qa-llm-defaults.sh — default vision-judge credentials for THIS machine
# ===========================================================================
# Without this file, ZEPTO_QA_API_KEY/_URL/_MODEL are unset by default, so
# qa_llm_available() (qa-helpers.sh) silently SKIPs every tier2 LLM-judge
# script whenever a fresh shell runs `make qa-visual`/`make qa-full` —
# which is exactly what happened for most of one real session before
# anyone noticed the skips (see bugs.md / commit history, 2026-08-30). A
# silently-skipped safety net is worse than an absent one: it looks green.
#
# This file sets a DEFAULT gateway + model for the developer machine this
# repo currently lives on: a local OpenAI-compatible proxy reachable at
# http://ai over the user's Tailscale network, serving several open-weight
# and commercial models with `requires_client_auth: false` (confirmed via
# `curl http://ai/v1/models` — no real secret is embedded here, "x" below
# is a placeholder the gateway ignores). It will NOT work on a machine
# without access to that gateway (a fresh CI runner, another developer's
# laptop, etc.) — that is fine and expected. In that case:
#   - vision-judge (tier2) scripts will fail fast (llm-judge.sh sets an
#     explicit curl --max-time, so a bad/unreachable endpoint is a quick
#     FAIL, not a hang) rather than silently skipping, which is arguably
#     more honest — but if you don't want that noise, either export
#     ZEPTO_QA_SKIP_LLM=1, or point these three vars at a gateway you do
#     have access to.
#   - tier1 scripts (`make qa`, the default target, and everything CI
#     runs) never touch this file's variables at all — no LLM dependency.
#
# Override any of these by exporting the same-named variable before
# running `make qa-visual`/`make qa-full`/a script directly — the
# `: "${VAR:=default}"` pattern below only fills in what's NOT already set,
# so an existing env var (or a different model/gateway entirely) always
# wins over this file's defaults.
#
# Model choice: minimax/minimax-m3 — open-weight, vision-capable, and the
# model this whole LLM-judge pipeline was originally validated end-to-end
# against (see llm-judge.sh's reasoning-field fallback, added specifically
# for this model's response shape). Cheap ($0.30/$1.20 per M input/output
# tokens on this gateway as of 2026-08-30) relative to the closed frontier
# models also listed at http://ai/v1/models — picked deliberately to avoid
# "burning the bank" on a QA sweep that runs many screenshots per pass.
# ===========================================================================

: "${ZEPTO_QA_API_URL:=http://ai/v1/chat/completions}"
: "${ZEPTO_QA_API_KEY:=x}"
: "${ZEPTO_QA_MODEL:=minimax/minimax-m3}"

# minimax-m3 is a reasoning model: its actual analysis goes into a
# "reasoning" field before (or instead of) a terse final "content"
# answer (see llm-judge.sh's response-parsing comment). llm-judge.sh's
# own default max_tokens (2000) is sometimes too tight for that reasoning
# to complete AND leave room for the final PASS/FAIL line on more
# detailed prompts — confirmed while validating editor_correctness_
# visual_sweep.sh's "paste" case: the model's reasoning correctly
# concluded no bug was visible, but got cut off (finish_reason "length")
# right as it started writing the final answer, so llm-judge.sh's
# fallback correctly reported it as "no final verdict" rather than
# silently guessing PASS or FAIL from partial text. Raising the ceiling
# here fixes that class of false-negative for every tier2 script, not
# just this one.
: "${ZEPTO_QA_MAX_TOKENS:=3500}"

export ZEPTO_QA_API_URL ZEPTO_QA_API_KEY ZEPTO_QA_MODEL ZEPTO_QA_MAX_TOKENS
