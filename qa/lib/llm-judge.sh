#!/usr/bin/env bash
# ===========================================================================
# llm-judge.sh — send a screenshot to a vision LLM for pass/fail judgment
# ===========================================================================
# Usage:
#   llm-judge.sh <screenshot.png> <prompt>   # judge a screenshot
#   llm-judge.sh probe                       # cheap text-only reachability check
#   llm-judge.sh setup                       # force interactive (re)configuration
#
# Judge output (stdout), always one of:
#   PASS
#   FAIL: <reason>
#
# Exit codes:
#   0  = judge ran and produced a verdict (PASS or FAIL — check stdout)
#   10 = no judge config resolved ("tier 2 requires judge config")
#   11 = auth failure talking to the provider
#   12 = network error talking to the provider
#   13 = malformed reply from the provider
#
# probe subcommand prints "PROBE_OK: ..." or "PROBE_FAIL: <reason>" and
# exits 0/10/11/12/13 accordingly (10 = no config, matching the above).
#
# ---------------------------------------------------------------------------
# Configuration resolution order:
#   1. Environment: ZEPTO_JUDGE_PROVIDER / ZEPTO_JUDGE_MODEL /
#      ZEPTO_JUDGE_API_KEY / ZEPTO_JUDGE_BASE_URL
#      (active whenever ZEPTO_JUDGE_API_KEY is set; provider defaults to
#      "anthropic" if unset)
#   2. Config file: ~/.config/zepto-qa/judge.json
#      {"provider": "...", "model": "...", "base_url": "...", "api_key": "..."}
#   3. Interactive first-run setup — ONLY if stdin is a tty. Prompts for a
#      provider and key, probes it, and on success saves it to the config
#      file above (mode 0600).
#   4. None of the above resolved -> "no config" (exit 10).
#
# Providers: anthropic (default, Claude Haiku 4.5), openai, openrouter.
# See qa/lib/judge_request.py for wire-format details and qa/README.md for
# the full local + CI setup story.
#
# Key hygiene: the API key is written to a private 0600 temp file and
# handed to the Python/curl transport as a FILE PATH, never as a command
# line argument or in curl's own argv — see judge_request.py's docstring.
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYHELPER="$SCRIPT_DIR/judge_request.py"

CONFIG_DIR="${ZEPTO_JUDGE_CONFIG_DIR:-$HOME/.config/zepto-qa}"
CONFIG_FILE="$CONFIG_DIR/judge.json"

JUDGE_PROVIDER=""
JUDGE_MODEL=""
JUDGE_BASE_URL=""
JUDGE_API_KEY=""
JUDGE_SOURCE=""
JUDGE_KEY_FILE=""

_cleanup() {
    if [[ -n "$JUDGE_KEY_FILE" && -f "$JUDGE_KEY_FILE" ]]; then
        rm -f "$JUDGE_KEY_FILE"
    fi
}
trap _cleanup EXIT

usage() {
    cat >&2 <<'EOF'
Usage:
  llm-judge.sh <screenshot.png> <prompt>
  llm-judge.sh probe
  llm-judge.sh setup
EOF
}

_default_model() {
    case "$1" in
        anthropic)  echo "claude-haiku-4-5" ;;
        openai)     echo "gpt-5-mini" ;;
        openrouter) echo "qwen/qwen3-vl-8b-instruct" ;;
        *)          echo "" ;;
    esac
}

_default_base() {
    case "$1" in
        anthropic)  echo "https://api.anthropic.com" ;;
        openai)     echo "https://api.openai.com" ;;
        openrouter) echo "https://openrouter.ai/api/v1" ;;
        *)          echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# Config resolution
# ---------------------------------------------------------------------------

_read_config_file() {
    # Prints "provider\nmodel\nbase_url\napi_key\n" on success (model/base
    # may be empty strings), exits nonzero (no output) if the file is
    # missing, unreadable, malformed, or missing provider/api_key.
    python3 - "$CONFIG_FILE" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
    provider = c.get("provider", "") or ""
    key = c.get("api_key", "") or ""
    if not provider or not key:
        sys.exit(1)
    print(provider)
    print(c.get("model", "") or "")
    print(c.get("base_url", "") or "")
    print(key)
except Exception:
    sys.exit(1)
PY
}

_resolve_config() {
    if [[ -n "${ZEPTO_JUDGE_API_KEY:-}" ]]; then
        JUDGE_PROVIDER="${ZEPTO_JUDGE_PROVIDER:-anthropic}"
        JUDGE_API_KEY="$ZEPTO_JUDGE_API_KEY"
        JUDGE_MODEL="${ZEPTO_JUDGE_MODEL:-$(_default_model "$JUDGE_PROVIDER")}"
        JUDGE_BASE_URL="${ZEPTO_JUDGE_BASE_URL:-$(_default_base "$JUDGE_PROVIDER")}"
        JUDGE_SOURCE="env"
        return 0
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        local parsed
        if parsed=$(_read_config_file 2>/dev/null); then
            JUDGE_PROVIDER=$(sed -n '1p' <<<"$parsed")
            JUDGE_MODEL=$(sed -n '2p' <<<"$parsed")
            JUDGE_BASE_URL=$(sed -n '3p' <<<"$parsed")
            JUDGE_API_KEY=$(sed -n '4p' <<<"$parsed")
            [[ -z "$JUDGE_MODEL" ]] && JUDGE_MODEL="$(_default_model "$JUDGE_PROVIDER")"
            [[ -z "$JUDGE_BASE_URL" ]] && JUDGE_BASE_URL="$(_default_base "$JUDGE_PROVIDER")"
            JUDGE_SOURCE="config_file"
            return 0
        fi
    fi

    if [[ -t 0 && "${ZEPTO_JUDGE_NO_INTERACTIVE:-0}" != "1" ]]; then
        if _interactive_setup; then
            JUDGE_SOURCE="interactive"
            return 0
        fi
    fi

    return 1
}

_write_key_file() {
    local dir="${QA_TMPDIR:-${TMPDIR:-/tmp}}"
    JUDGE_KEY_FILE=$(mktemp "$dir/.zepto_judge_key.XXXXXX")
    chmod 600 "$JUDGE_KEY_FILE"
    printf '%s' "$JUDGE_API_KEY" > "$JUDGE_KEY_FILE"
}

# ---------------------------------------------------------------------------
# Interactive first-run setup (tty only)
# ---------------------------------------------------------------------------

_interactive_setup() {
    echo "Zepto QA tier-2 visual judge is not configured." >&2
    echo "" >&2
    echo "Pick a provider:" >&2
    echo "  1) anthropic  (default — Claude Haiku 4.5)" >&2
    echo "  2) openai" >&2
    echo "  3) openrouter" >&2
    local choice
    read -r -p "Provider [1]: " choice </dev/tty || return 1

    case "${choice:-1}" in
        2) JUDGE_PROVIDER=openai ;;
        3) JUDGE_PROVIDER=openrouter ;;
        1|"") JUDGE_PROVIDER=anthropic ;;
        *) echo "Unrecognized choice: $choice" >&2; return 1 ;;
    esac

    JUDGE_MODEL="$(_default_model "$JUDGE_PROVIDER")"
    JUDGE_BASE_URL="$(_default_base "$JUDGE_PROVIDER")"

    read -r -s -p "API key for $JUDGE_PROVIDER: " JUDGE_API_KEY </dev/tty || return 1
    echo "" >&2

    if [[ -z "$JUDGE_API_KEY" ]]; then
        echo "No key entered — aborting setup." >&2
        return 1
    fi

    _write_key_file
    local out rc
    out=$(python3 "$PYHELPER" probe "$JUDGE_PROVIDER" "$JUDGE_MODEL" "$JUDGE_BASE_URL" "$JUDGE_KEY_FILE" 2>&1)
    rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "Probe failed with the entered key/provider — not saving config." >&2
        echo "  $out" >&2
        return 1
    fi
    echo "Probe OK: $out" >&2

    mkdir -p "$CONFIG_DIR"
    local tmp_cfg
    tmp_cfg=$(mktemp "$CONFIG_DIR/.judge.json.XXXXXX")
    python3 - "$tmp_cfg" "$JUDGE_PROVIDER" "$JUDGE_MODEL" "$JUDGE_BASE_URL" "$JUDGE_KEY_FILE" <<'PY'
import json, sys
tmp_path, provider, model, base, key_file = sys.argv[1:6]
with open(key_file) as f:
    key = f.read().strip()
with open(tmp_path, "w") as f:
    json.dump({"provider": provider, "model": model, "base_url": base, "api_key": key}, f, indent=2)
    f.write("\n")
PY
    chmod 600 "$tmp_cfg"
    mv "$tmp_cfg" "$CONFIG_FILE"
    echo "Saved judge config to $CONFIG_FILE (mode 600)." >&2
    return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_probe() {
    if ! _resolve_config; then
        echo "PROBE_FAIL: tier 2 requires judge config (set ZEPTO_JUDGE_PROVIDER + ZEPTO_JUDGE_API_KEY, run 'llm-judge.sh setup', or create $CONFIG_FILE)"
        exit 10
    fi
    _write_key_file
    local out rc
    set +e
    out=$(python3 "$PYHELPER" probe "$JUDGE_PROVIDER" "$JUDGE_MODEL" "$JUDGE_BASE_URL" "$JUDGE_KEY_FILE")
    rc=$?
    set -e
    echo "$out"
    case $rc in
        0) exit 0 ;;
        1) exit 11 ;;
        2) exit 12 ;;
        3) exit 12 ;;
        *) exit 13 ;;
    esac
}

cmd_setup() {
    if [[ ! -t 0 ]]; then
        echo "FAIL: setup requires an interactive terminal (stdin is not a tty)" >&2
        exit 10
    fi
    if _interactive_setup; then
        echo "PROBE_OK: provider=$JUDGE_PROVIDER model=$JUDGE_MODEL"
        exit 0
    else
        echo "PROBE_FAIL: setup did not complete"
        exit 10
    fi
}

cmd_judge() {
    local screenshot="$1" prompt="$2"

    if [[ ! -f "$screenshot" ]]; then
        echo "FAIL: screenshot not found: $screenshot"
        exit 1
    fi

    if ! _resolve_config; then
        echo "FAIL: tier 2 requires judge config (set ZEPTO_JUDGE_PROVIDER + ZEPTO_JUDGE_API_KEY, run 'llm-judge.sh setup', or create $CONFIG_FILE)"
        exit 10
    fi

    _write_key_file
    local out rc
    set +e
    out=$(python3 "$PYHELPER" judge "$JUDGE_PROVIDER" "$JUDGE_MODEL" "$JUDGE_BASE_URL" "$JUDGE_KEY_FILE" "$screenshot" "$prompt")
    rc=$?
    set -e
    echo "$out"
    case $rc in
        0) exit 0 ;;
        1) exit 11 ;;
        2) exit 12 ;;
        3) exit 12 ;;
        *) exit 13 ;;
    esac
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
    probe)
        cmd_probe
        ;;
    setup)
        cmd_setup
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        if [[ $# -lt 2 ]]; then
            usage
            exit 1
        fi
        cmd_judge "$1" "$2"
        ;;
esac
