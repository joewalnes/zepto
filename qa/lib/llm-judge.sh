#!/usr/bin/env bash
# ===========================================================================
# llm-judge.sh — send a screenshot to a vision LLM for pass/fail judgment
# ===========================================================================
# Usage: llm-judge.sh /path/to/screenshot.png "Does the editor show..."
#
# Outputs one of:
#   PASS
#   FAIL: <reason>
#
# Configuration via environment:
#   ZEPTO_QA_API_URL   — OpenAI-compatible endpoint (default: Anthropic)
#   ZEPTO_QA_API_KEY   — API key (falls back to ANTHROPIC_API_KEY, OPENAI_API_KEY)
#   ZEPTO_QA_MODEL     — model name (default: claude-haiku-4-5-20251001)
#
# qa-helpers.sh sources qa-llm-defaults.sh before any of the above are
# read, which fills in a working default gateway/model/key for the machine
# this repo currently lives on (see that file's header) — so scripts that
# `source qa-helpers.sh` normally never hit the "no API key configured"
# path below unless ZEPTO_QA_SKIP_LLM=1 is set. Calling this script
# directly, without going through qa-helpers.sh, still requires one of the
# three env vars above to be set explicitly.
#
# Supports: Anthropic, OpenRouter, OpenAI, any OpenAI-compatible API,
#           local servers (Ollama, vLLM, llama.cpp)
#
# Network calls here are QA tooling only (never shipped in the zepto
# binary — CLAUDE.md's "never add network calls" rule is about the
# editor itself, see docs/SECURITY.md). Every curl call below sets
# --max-time so a misconfigured or unreachable endpoint fails fast as a
# FAIL rather than hanging the whole QA run.
# ===========================================================================

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: llm-judge.sh <screenshot.png> <prompt>" >&2
    exit 1
fi

SCREENSHOT="$1"
PROMPT="$2"

if [[ ! -f "$SCREENSHOT" ]]; then
    echo "FAIL: screenshot not found: $SCREENSHOT"
    exit 0
fi

# ---------------------------------------------------------------------------
# Resolve API configuration
# ---------------------------------------------------------------------------

API_KEY="${ZEPTO_QA_API_KEY:-${ANTHROPIC_API_KEY:-${OPENAI_API_KEY:-}}}"
if [[ -z "$API_KEY" ]]; then
    echo "FAIL: no API key configured (set ZEPTO_QA_API_KEY, ANTHROPIC_API_KEY, or OPENAI_API_KEY)"
    exit 0
fi

MODEL="${ZEPTO_QA_MODEL:-claude-haiku-4-5-20251001}"
API_URL="${ZEPTO_QA_API_URL:-}"

# ---------------------------------------------------------------------------
# Detect API format (Anthropic vs OpenAI-compatible)
# ---------------------------------------------------------------------------

USE_ANTHROPIC=0
if [[ -z "$API_URL" ]]; then
    # Default: use Anthropic native API
    API_URL="https://api.anthropic.com/v1/messages"
    USE_ANTHROPIC=1
elif [[ "$API_URL" == *"anthropic.com"* && "$API_URL" != *"/v1/chat"* ]]; then
    USE_ANTHROPIC=1
fi

# ---------------------------------------------------------------------------
# Encode image
# ---------------------------------------------------------------------------

IMAGE_B64=$(base64 < "$SCREENSHOT" | tr -d '\n')

# Detect media type
MEDIA_TYPE="image/png"
case "$SCREENSHOT" in
    *.jpg|*.jpeg) MEDIA_TYPE="image/jpeg" ;;
    *.svg) MEDIA_TYPE="image/svg+xml" ;;
    *.webp) MEDIA_TYPE="image/webp" ;;
esac

# ---------------------------------------------------------------------------
# Build system prompt
# ---------------------------------------------------------------------------

SYSTEM_PROMPT="You are a QA test judge for the Zepto terminal text editor. You will be shown a screenshot of the editor and asked to verify specific visual conditions.

Evaluate the screenshot against the given criteria. Be precise and strict.

Respond with EXACTLY one of:
  PASS
  FAIL: <brief reason>

Do not add any other text, explanation, or formatting. Just PASS or FAIL: reason."

# ---------------------------------------------------------------------------
# Call API
# ---------------------------------------------------------------------------

# Generous but bounded — vision + reasoning models can genuinely take
# 10-30s on a slow/loaded gateway, but an unreachable host (bad
# ZEPTO_QA_API_URL, VPN down, etc.) must not hang a whole QA run.
CURL_MAX_TIME="${ZEPTO_QA_CURL_MAX_TIME:-45}"

if [[ "$USE_ANTHROPIC" == "1" ]]; then
    # Anthropic Messages API format
    RESPONSE=$(curl -sS --max-time "$CURL_MAX_TIME" "$API_URL" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$(cat <<ENDJSON
{
    "model": "$MODEL",
    "max_tokens": 100,
    "system": $(printf '%s' "$SYSTEM_PROMPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))'),
    "messages": [{
        "role": "user",
        "content": [
            {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": "$MEDIA_TYPE",
                    "data": "$IMAGE_B64"
                }
            },
            {
                "type": "text",
                "text": $(printf '%s' "$PROMPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
            }
        ]
    }]
}
ENDJSON
)" 2>/dev/null)

    # Extract text from Anthropic response
    RESULT=$(echo "$RESPONSE" | python3 -c '
import sys, json
try:
    r = json.load(sys.stdin)
    if "content" in r and len(r["content"]) > 0:
        print(r["content"][0]["text"].strip())
    elif "error" in r:
        print("FAIL: API error: " + r["error"].get("message", str(r["error"])))
    else:
        print("FAIL: unexpected response format")
except Exception as e:
    print(f"FAIL: parse error: {e}")
' 2>/dev/null)

else
    # OpenAI-compatible API format (OpenRouter, OpenAI, Ollama, vLLM, etc.)
    # Ensure URL ends with /chat/completions
    CHAT_URL="$API_URL"
    if [[ "$CHAT_URL" != */chat/completions ]]; then
        CHAT_URL="${CHAT_URL%/}/chat/completions"
    fi

    RESPONSE=$(curl -sS --max-time "$CURL_MAX_TIME" "$CHAT_URL" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$(cat <<ENDJSON
{
    "model": "$MODEL",
    "max_tokens": ${ZEPTO_QA_MAX_TOKENS:-2000},
    "messages": [
        {
            "role": "system",
            "content": $(printf '%s' "$SYSTEM_PROMPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
        },
        {
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {
                        "url": "data:$MEDIA_TYPE;base64,$IMAGE_B64"
                    }
                },
                {
                    "type": "text",
                    "text": $(printf '%s' "$PROMPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
                }
            ]
        }
    ]
}
ENDJSON
)" 2>/dev/null)

    # Extract text from OpenAI-compatible response. Some models (reasoning
    # models, e.g. minimax-m3) put their actual analysis in a "reasoning"
    # field and leave "content" null until reasoning concludes — if the
    # token budget runs out first (finish_reason "length"), content stays
    # null forever. Fall back to "reasoning"/"reasoning_details" in that
    # case rather than crashing on a None.strip() — a real (if unlabeled)
    # judgment is more useful than a parse error.
    RESULT=$(echo "$RESPONSE" | python3 -c '
import sys, json
try:
    r = json.load(sys.stdin)
    if "choices" in r and len(r["choices"]) > 0:
        msg = r["choices"][0]["message"]
        content = msg.get("content")
        if content:
            print(content.strip())
        else:
            reasoning = msg.get("reasoning") or ""
            if not reasoning and msg.get("reasoning_details"):
                reasoning = "".join(
                    d.get("text", "") for d in msg["reasoning_details"]
                    if isinstance(d, dict)
                )
            finish = r["choices"][0].get("finish_reason", "")
            if reasoning:
                note = " [truncated: hit max_tokens before a final answer]" if finish == "length" else ""
                print(f"FAIL: model only produced reasoning, no final verdict{note}: " + reasoning.strip()[-500:])
            else:
                print("FAIL: empty response (content and reasoning both blank)")
    elif "error" in r:
        print("FAIL: API error: " + r["error"].get("message", str(r["error"])))
    else:
        print("FAIL: unexpected response format")
except Exception as e:
    print(f"FAIL: parse error: {e}")
' 2>/dev/null)
fi

# ---------------------------------------------------------------------------
# Normalize output
# ---------------------------------------------------------------------------

# Ensure output starts with PASS or FAIL
if [[ "$RESULT" == PASS* ]]; then
    echo "PASS"
elif [[ "$RESULT" == FAIL* ]]; then
    echo "$RESULT"
else
    echo "FAIL: LLM returned unexpected response: ${RESULT:0:200}"
fi
