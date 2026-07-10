#!/usr/bin/env bash
# QA-JUDGE-001: qa/lib/llm-judge.sh wiring — provider wire shapes, config
# resolution order, pass/fail/malformed handling, probe, and key hygiene.
# All against qa/lib/judge_mock_server.pl — never touches the real network
# or a real API key (see CLAUDE.md: "there is NO real API key in this
# environment — never attempt a real provider call").
source "$(dirname "$0")/../../lib/qa-helpers.sh"
qa_header "QA-JUDGE-001: LLM judge wiring (mock)"

JUDGE="$_QA_HELPERS_DIR/llm-judge.sh"

# A tiny valid 4x4 PNG fixture (python3's zlib module — core stdlib, no
# CPAN/PyPI — matches this file's "curl + python3 are fine for dev-side
# tooling" allowance).
FIXTURE="$QA_TMPDIR/fixture.png"
FIXTURE="$FIXTURE" python3 -c '
import os, struct, zlib

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

w, h = 4, 4
raw = b"".join(b"\x00" + b"\xff\x00\x00" * w for _ in range(h))
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw))
png += chunk(b"IEND", b"")
with open(os.environ["FIXTURE"], "wb") as f:
    f.write(png)
'
qa_assert_file_exists "$FIXTURE" "PNG fixture created"

# ---------------------------------------------------------------------------
# 1. No config resolved (non-interactive, no env, no config file) — distinct
#    exit code, clear "requires judge config" message, not a silent SKIP.
# ---------------------------------------------------------------------------
(
    set +e
    unset ZEPTO_JUDGE_PROVIDER ZEPTO_JUDGE_MODEL ZEPTO_JUDGE_API_KEY ZEPTO_JUDGE_BASE_URL
    export ZEPTO_JUDGE_CONFIG_DIR="$QA_TMPDIR/no_such_config_dir"
    export ZEPTO_JUDGE_NO_INTERACTIVE=1
    out=$(bash "$JUDGE" "$FIXTURE" "anything" </dev/null 2>&1)
    rc=$?
    echo "$out" > "$QA_TMPDIR/noconfig.out"
    echo "$rc" > "$QA_TMPDIR/noconfig.rc"
)
noconfig_out=$(cat "$QA_TMPDIR/noconfig.out")
noconfig_rc=$(cat "$QA_TMPDIR/noconfig.rc")
[[ "$noconfig_rc" == "10" ]] && qa_pass "no-config judge call exits with distinct code 10" \
    || qa_fail "no-config judge call exits with distinct code 10" "got rc=$noconfig_rc"
[[ "$noconfig_out" == *"requires judge config"* ]] && qa_pass "no-config message names the exact problem" \
    || qa_fail "no-config message names the exact problem" "got: $noconfig_out"

# probe subcommand mirrors the same no-config failure
(
    set +e
    unset ZEPTO_JUDGE_PROVIDER ZEPTO_JUDGE_MODEL ZEPTO_JUDGE_API_KEY ZEPTO_JUDGE_BASE_URL
    export ZEPTO_JUDGE_CONFIG_DIR="$QA_TMPDIR/no_such_config_dir"
    export ZEPTO_JUDGE_NO_INTERACTIVE=1
    out=$(bash "$JUDGE" probe </dev/null 2>&1)
    rc=$?
    echo "$out" > "$QA_TMPDIR/noconfig_probe.out"
    echo "$rc" > "$QA_TMPDIR/noconfig_probe.rc"
)
[[ "$(cat "$QA_TMPDIR/noconfig_probe.rc")" == "10" ]] && qa_pass "probe with no config exits 10" \
    || qa_fail "probe with no config exits 10" "got rc=$(cat "$QA_TMPDIR/noconfig_probe.rc")"
[[ "$(cat "$QA_TMPDIR/noconfig_probe.out")" == PROBE_FAIL:* ]] && qa_pass "probe with no config prints PROBE_FAIL" \
    || qa_fail "probe with no config prints PROBE_FAIL" "got: $(cat "$QA_TMPDIR/noconfig_probe.out")"

# ---------------------------------------------------------------------------
# 2. Config resolution order: env beats config file.
# ---------------------------------------------------------------------------
qa_judge_mock_start "pass" "env-server criteria met" "$QA_TMPDIR/req_env.log"
env_url="$QA_JUDGE_MOCK_URL"
qa_judge_mock_start "fail" "file-server would have failed" "$QA_TMPDIR/req_file.log"
file_url="$QA_JUDGE_MOCK_URL"

cfgdir="$QA_TMPDIR/cfg_precedence"
mkdir -p "$cfgdir"
cat > "$cfgdir/judge.json" <<EOF
{"provider": "openai", "model": "gpt-5-mini", "base_url": "$file_url", "api_key": "file-key-should-be-ignored"}
EOF
chmod 600 "$cfgdir/judge.json"

(
    set +e
    export ZEPTO_JUDGE_CONFIG_DIR="$cfgdir"
    export ZEPTO_JUDGE_PROVIDER=anthropic
    export ZEPTO_JUDGE_API_KEY=env-key-wins
    export ZEPTO_JUDGE_BASE_URL="$env_url"
    out=$(bash "$JUDGE" "$FIXTURE" "criteria" </dev/null 2>&1)
    echo "$out" > "$QA_TMPDIR/precedence.out"
)
[[ "$(cat "$QA_TMPDIR/precedence.out")" == "PASS" ]] && \
    qa_pass "env config takes precedence over config file (hit env-server, got PASS)" \
    || qa_fail "env config takes precedence over config file" "got: $(cat "$QA_TMPDIR/precedence.out")"

# ---------------------------------------------------------------------------
# 3. Config file alone (no env) resolves and is used.
# ---------------------------------------------------------------------------
(
    set +e
    unset ZEPTO_JUDGE_PROVIDER ZEPTO_JUDGE_MODEL ZEPTO_JUDGE_API_KEY ZEPTO_JUDGE_BASE_URL
    export ZEPTO_JUDGE_CONFIG_DIR="$cfgdir"
    export ZEPTO_JUDGE_NO_INTERACTIVE=1
    out=$(bash "$JUDGE" "$FIXTURE" "criteria" </dev/null 2>&1)
    echo "$out" > "$QA_TMPDIR/filecfg.out"
)
[[ "$(cat "$QA_TMPDIR/filecfg.out")" == FAIL:* ]] && \
    qa_pass "config file alone resolves and is used (hit file-server, got FAIL)" \
    || qa_fail "config file alone resolves and is used" "got: $(cat "$QA_TMPDIR/filecfg.out")"
[[ "$(cat "$QA_TMPDIR/filecfg.out")" == *"file-server would have failed"* ]] && \
    qa_pass "config-file-resolved FAIL carries the model's reason text" \
    || qa_fail "config-file-resolved FAIL carries the model's reason text" "got: $(cat "$QA_TMPDIR/filecfg.out")"

qa_judge_mock_stop

# ---------------------------------------------------------------------------
# 4. Anthropic wire shape: correct endpoint + headers.
# ---------------------------------------------------------------------------
qa_judge_mock_start "pass" "anthropic ok" "$QA_TMPDIR/req_anthropic.log"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=anthropic
    export ZEPTO_JUDGE_MODEL=claude-haiku-4-5
    export ZEPTO_JUDGE_API_KEY=anthropic-test-key
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    out=$(bash "$JUDGE" "$FIXTURE" "criteria" </dev/null 2>&1)
    echo "$out" > "$QA_TMPDIR/anthropic.out"
)
[[ "$(cat "$QA_TMPDIR/anthropic.out")" == "PASS" ]] && qa_pass "anthropic: judge call succeeds against mock" \
    || qa_fail "anthropic: judge call succeeds against mock" "got: $(cat "$QA_TMPDIR/anthropic.out")"
qa_assert_file_contains "$QA_TMPDIR/req_anthropic.log" "path=/v1/messages" \
    "anthropic: request hit /v1/messages"
qa_assert_file_contains "$QA_TMPDIR/req_anthropic.log" "anthropic_version=1" \
    "anthropic: anthropic-version header sent"
qa_assert_file_contains "$QA_TMPDIR/req_anthropic.log" "auth_header=1" \
    "anthropic: x-api-key header sent"
qa_assert_file_contains "$QA_TMPDIR/req_anthropic.log" "model=claude-haiku-4-5" \
    "anthropic: request body carries the configured model"
qa_judge_mock_stop

# ---------------------------------------------------------------------------
# 5. OpenAI wire shape: correct endpoint + headers (also covers openrouter,
#    which is byte-for-byte the same wire shape at a different base URL).
# ---------------------------------------------------------------------------
qa_judge_mock_start "pass" "openai ok" "$QA_TMPDIR/req_openai.log"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=openai
    export ZEPTO_JUDGE_API_KEY=openai-test-key
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    out=$(bash "$JUDGE" "$FIXTURE" "criteria" </dev/null 2>&1)
    echo "$out" > "$QA_TMPDIR/openai.out"
)
[[ "$(cat "$QA_TMPDIR/openai.out")" == "PASS" ]] && qa_pass "openai: judge call succeeds against mock" \
    || qa_fail "openai: judge call succeeds against mock" "got: $(cat "$QA_TMPDIR/openai.out")"
qa_assert_file_contains "$QA_TMPDIR/req_openai.log" "path=/v1/chat/completions" \
    "openai: request hit /v1/chat/completions"
qa_assert_file_contains "$QA_TMPDIR/req_openai.log" "bearer=1" \
    "openai: Authorization: Bearer header sent"
qa_assert_file_contains "$QA_TMPDIR/req_openai.log" "model=gpt-5-mini" \
    "openai: default model (gpt-5-mini) used when none configured"
qa_judge_mock_stop

# ---------------------------------------------------------------------------
# 6. openrouter default model.
# ---------------------------------------------------------------------------
qa_judge_mock_start "pass" "openrouter ok" "$QA_TMPDIR/req_openrouter.log"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=openrouter
    export ZEPTO_JUDGE_API_KEY=openrouter-test-key
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    bash "$JUDGE" "$FIXTURE" "criteria" </dev/null >/dev/null 2>&1
)
qa_assert_file_contains "$QA_TMPDIR/req_openrouter.log" "model=qwen/qwen3-vl-8b-instruct" \
    "openrouter: default model (qwen/qwen3-vl-8b-instruct) used when none configured"
qa_judge_mock_stop

# ---------------------------------------------------------------------------
# 7. Fail-verdict handling: model's JSON says pass=false -> FAIL with reason.
# ---------------------------------------------------------------------------
qa_judge_mock_start "fail" "wrap pill shows no highlight" "$QA_TMPDIR/req_fail.log"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=anthropic
    export ZEPTO_JUDGE_API_KEY=k
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    out=$(bash "$JUDGE" "$FIXTURE" "criteria" </dev/null 2>&1)
    echo "$out" > "$QA_TMPDIR/failverdict.out"
)
[[ "$(cat "$QA_TMPDIR/failverdict.out")" == "FAIL: wrap pill shows no highlight" ]] && \
    qa_pass "fail verdict: exact reason relayed from model JSON" \
    || qa_fail "fail verdict: exact reason relayed from model JSON" "got: $(cat "$QA_TMPDIR/failverdict.out")"
qa_judge_mock_stop

# ---------------------------------------------------------------------------
# 8. Malformed reply (non-JSON) is an ERROR, never silently treated as PASS.
# ---------------------------------------------------------------------------
qa_judge_mock_start "malformed" "" "$QA_TMPDIR/req_malformed.log"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=anthropic
    export ZEPTO_JUDGE_API_KEY=k
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    out=$(bash "$JUDGE" "$FIXTURE" "criteria" </dev/null 2>&1)
    rc=$?
    echo "$out" > "$QA_TMPDIR/malformed.out"
    echo "$rc" > "$QA_TMPDIR/malformed.rc"
)
[[ "$(cat "$QA_TMPDIR/malformed.out")" != "PASS" ]] && qa_pass "malformed reply is never treated as PASS" \
    || qa_fail "malformed reply is never treated as PASS" "malformed reply produced PASS"
[[ "$(cat "$QA_TMPDIR/malformed.rc")" == "13" ]] && qa_pass "malformed reply exits with distinct code 13" \
    || qa_fail "malformed reply exits with distinct code 13" "got rc=$(cat "$QA_TMPDIR/malformed.rc")"
qa_judge_mock_stop

# ---------------------------------------------------------------------------
# 9. Auth failure is reported distinctly, not confused with "no config".
# ---------------------------------------------------------------------------
qa_judge_mock_start "unauth" "" "$QA_TMPDIR/req_unauth.log"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=anthropic
    export ZEPTO_JUDGE_API_KEY=bad-key
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    out=$(bash "$JUDGE" "$FIXTURE" "criteria" </dev/null 2>&1)
    rc=$?
    echo "$out" > "$QA_TMPDIR/unauth.out"
    echo "$rc" > "$QA_TMPDIR/unauth.rc"
)
[[ "$(cat "$QA_TMPDIR/unauth.rc")" == "11" ]] && qa_pass "auth failure exits with distinct code 11" \
    || qa_fail "auth failure exits with distinct code 11" "got rc=$(cat "$QA_TMPDIR/unauth.rc")"
[[ "$(cat "$QA_TMPDIR/unauth.out")" == *"auth failed"* ]] && qa_pass "auth failure message says so" \
    || qa_fail "auth failure message says so" "got: $(cat "$QA_TMPDIR/unauth.out")"
qa_judge_mock_stop

# ---------------------------------------------------------------------------
# 10. probe: success and failure paths.
# ---------------------------------------------------------------------------
qa_judge_mock_start "pass" "probe" "$QA_TMPDIR/req_probe_ok.log"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=anthropic
    export ZEPTO_JUDGE_API_KEY=k
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    out=$(bash "$JUDGE" probe </dev/null 2>&1)
    rc=$?
    echo "$out" > "$QA_TMPDIR/probe_ok.out"
    echo "$rc" > "$QA_TMPDIR/probe_ok.rc"
)
[[ "$(cat "$QA_TMPDIR/probe_ok.rc")" == "0" ]] && qa_pass "probe succeeds (exit 0) against healthy mock" \
    || qa_fail "probe succeeds (exit 0) against healthy mock" "got rc=$(cat "$QA_TMPDIR/probe_ok.rc")"
[[ "$(cat "$QA_TMPDIR/probe_ok.out")" == PROBE_OK:* ]] && qa_pass "probe success message is PROBE_OK" \
    || qa_fail "probe success message is PROBE_OK" "got: $(cat "$QA_TMPDIR/probe_ok.out")"
qa_judge_mock_stop

qa_judge_mock_start "unauth" "" "$QA_TMPDIR/req_probe_fail.log"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=anthropic
    export ZEPTO_JUDGE_API_KEY=bad-key
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    out=$(bash "$JUDGE" probe </dev/null 2>&1)
    rc=$?
    echo "$out" > "$QA_TMPDIR/probe_fail.out"
    echo "$rc" > "$QA_TMPDIR/probe_fail.rc"
)
[[ "$(cat "$QA_TMPDIR/probe_fail.rc")" == "11" ]] && qa_pass "probe failure exits 11 on bad auth" \
    || qa_fail "probe failure exits 11 on bad auth" "got rc=$(cat "$QA_TMPDIR/probe_fail.rc")"
[[ "$(cat "$QA_TMPDIR/probe_fail.out")" == PROBE_FAIL:* ]] && qa_pass "probe failure message is PROBE_FAIL" \
    || qa_fail "probe failure message is PROBE_FAIL" "got: $(cat "$QA_TMPDIR/probe_fail.out")"
qa_judge_mock_stop

# ---------------------------------------------------------------------------
# 11. Key hygiene: the API key must never appear in `ps` output while the
#     call is in flight (mock server delays its response so we get a
#     window to snapshot ps mid-call).
# ---------------------------------------------------------------------------
SECRET_KEY="qa-secret-key-$$-$(date +%s)-do-not-leak"
qa_judge_mock_start "pass" "delayed ok" "$QA_TMPDIR/req_delayed.log" "1.5"
(
    set +e
    export ZEPTO_JUDGE_PROVIDER=anthropic
    export ZEPTO_JUDGE_API_KEY="$SECRET_KEY"
    export ZEPTO_JUDGE_BASE_URL="$QA_JUDGE_MOCK_URL"
    bash "$JUDGE" "$FIXTURE" "criteria" </dev/null > "$QA_TMPDIR/delayed.out" 2>&1
) &
judge_bgpid=$!
sleep 0.6

# Sanity: the check is meaningful only if we actually caught the transport
# mid-flight — confirm curl (or its wrapping python3) is running right now.
ps_snapshot=$(ps -eo args 2>/dev/null || ps -e -o args 2>/dev/null)
in_flight=0
echo "$ps_snapshot" | grep -qE 'curl .*--config|judge_request\.py' && in_flight=1
if [[ "$in_flight" == "1" ]]; then
    qa_pass "sanity: judge call is actually in-flight during the ps snapshot"
else
    qa_skip "sanity: judge call is actually in-flight during the ps snapshot" "transport finished before snapshot — key-leak check below is not meaningful this run"
fi

if echo "$ps_snapshot" | grep -qF "$SECRET_KEY"; then
    qa_fail "API key never appears in ps output during the call" "key found in: $(echo "$ps_snapshot" | grep -F "$SECRET_KEY")"
else
    qa_pass "API key never appears in ps output during the call"
fi

wait "$judge_bgpid" 2>/dev/null || true
[[ "$(cat "$QA_TMPDIR/delayed.out")" == "PASS" ]] && qa_pass "delayed call still completes correctly after the sleep" \
    || qa_fail "delayed call still completes correctly after the sleep" "got: $(cat "$QA_TMPDIR/delayed.out")"
qa_judge_mock_stop

qa_summary
