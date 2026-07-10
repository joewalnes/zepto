#!/usr/bin/env python3
# =============================================================================
# judge_request.py — one HTTP call to a vision-LLM QA judge provider
# =============================================================================
#
# Invoked by qa/lib/llm-judge.sh. Not a public interface — argument shapes
# can change freely as long as llm-judge.sh is updated to match.
#
# Usage:
#   judge_request.py probe <provider> <model> <base_url> <key_file>
#   judge_request.py judge <provider> <model> <base_url> <key_file> <image_path> <prompt>
#
# Key hygiene: the API key is read from <key_file> (a caller-managed 0600
# temp file), never taken on this script's own argv, and is handed to curl
# ONLY via a --config document written to curl's stdin -- curl's own argv
# is exactly ["curl", "-sS", "--config", "-"], so neither this process's
# nor curl's argv ever contains the key. This mirrors lib/Zepto/AIHttp.pm's
# transport design (see that file's module docstring) without importing
# from it -- this is dev-side QA tooling, not shipped editor code, so it
# is intentionally a separate, simpler implementation in Python rather
# than a dependency on Zepto's own Perl modules.
#
# Exit codes:
#   0 = success  (probe: printed "PROBE_OK: ..."; judge: printed "PASS" or
#                 "FAIL: <reason>" decoded from the model's own verdict)
#   1 = auth failure (401/403)
#   2 = network error (no HTTP response reached us)
#   3 = other HTTP error (4xx/5xx, not auth)
#   4 = malformed response (200 OK but couldn't extract/parse the reply)
# =============================================================================
import base64
import json
import subprocess
import sys

STATUS_MARKER = "ZEPTO_JUDGE_HTTP_STATUS:"

DEFAULT_MODEL = {
    "anthropic": "claude-haiku-4-5",
    "openai": "gpt-5-mini",
    "openrouter": "qwen/qwen3-vl-8b-instruct",
}

SYSTEM_PROMPT = (
    "You are a strict QA visual judge for the Zepto terminal text editor. "
    "You will be shown a screenshot of the editor and a specific pass/fail "
    "criterion. Judge STRICTLY: if the criteria are not clearly met in the "
    "screenshot, fail. Reply with ONLY a single-line, strict JSON object "
    "and nothing else -- no markdown fences, no commentary before or "
    'after it: {"pass": true or false, "reason": "one brief sentence"}'
)

PROBE_PROMPT = 'Reply with ONLY this exact JSON and nothing else: {"pass": true, "reason": "probe"}'


def _esc(s):
    # Same escaping rules as lib/Zepto/AIHttp.pm::_escape_config_string --
    # curl -K/--config quoted-string escapes: backslash first, then the
    # rest, or later substitutions would double-escape.
    s = s.replace("\\", "\\\\")
    s = s.replace('"', '\\"')
    s = s.replace("\n", "\\n")
    s = s.replace("\r", "\\r")
    s = s.replace("\t", "\\t")
    return s


def _cfg_line(key, value):
    return '%s = "%s"\n' % (key, _esc(value))


def _media_type(path):
    p = path.lower()
    if p.endswith((".jpg", ".jpeg")):
        return "image/jpeg"
    if p.endswith(".webp"):
        return "image/webp"
    if p.endswith(".svg"):
        return "image/svg+xml"
    return "image/png"


def build_request(mode, provider, model, base_url, image_path, prompt):
    """Returns (url, headers, body_dict)."""
    model = model or DEFAULT_MODEL.get(provider, "")
    is_probe = mode == "probe"
    max_tokens = 20 if is_probe else 300
    user_text = PROBE_PROMPT if is_probe else prompt

    image_block = None
    if not is_probe:
        with open(image_path, "rb") as f:
            data = f.read()
        b64 = base64.b64encode(data).decode("ascii")
        media_type = _media_type(image_path)

    if provider == "anthropic":
        url = base_url.rstrip("/") + "/v1/messages"
        headers = [
            ("x-api-key", "__KEY__"),
            ("anthropic-version", "2023-06-01"),
            ("content-type", "application/json"),
        ]
        content = []
        if not is_probe:
            content.append(
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": media_type, "data": b64},
                }
            )
        content.append({"type": "text", "text": user_text})
        body = {
            "model": model,
            "max_tokens": max_tokens,
            "system": SYSTEM_PROMPT,
            "messages": [{"role": "user", "content": content}],
        }
    elif provider in ("openai", "openrouter"):
        url = base_url.rstrip("/") + "/v1/chat/completions"
        headers = [
            ("Authorization", "Bearer __KEY__"),
            ("Content-Type", "application/json"),
        ]
        content = [{"type": "text", "text": user_text}]
        if not is_probe:
            content.append(
                {"type": "image_url", "image_url": {"url": "data:%s;base64,%s" % (media_type, b64)}}
            )
        body = {
            "model": model,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": content},
            ],
        }
    else:
        raise ValueError("unknown provider: %r" % provider)

    return url, headers, body


def run_curl(url, headers, body, api_key, timeout=30):
    """Executes the request via `curl -sS --config -`, with the config
    document (containing the URL, headers, and body -- including the API
    key) written to curl's stdin. curl's argv never contains the key.
    Returns (raw_body_str, http_status_str_or_None, transport_error_or_None).
    """
    config = ""
    config += _cfg_line("url", url)
    config += _cfg_line("request", "POST")
    config += "silent\n"
    config += "show-error\n"
    config += _cfg_line("max-time", str(timeout))
    config += _cfg_line("write-out", "\n" + STATUS_MARKER + "%{http_code}\n")
    for name, value in headers:
        value = value.replace("__KEY__", api_key)
        config += _cfg_line("header", "%s: %s" % (name, value))
    config += _cfg_line("data", json.dumps(body))

    try:
        proc = subprocess.run(
            ["curl", "-sS", "--config", "-"],
            input=config.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout + 5,
        )
    except FileNotFoundError:
        return "", None, "curl not found on PATH"
    except subprocess.TimeoutExpired:
        return "", None, "request timed out"

    raw = proc.stdout.decode("utf-8", errors="replace")
    marker = STATUS_MARKER
    idx = raw.rfind("\n" + marker)
    if idx == -1:
        # No marker at all -- curl itself never completed the transfer.
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        return raw, None, err or "curl exited without a response"

    body_str = raw[:idx]
    status = raw[idx + 1 + len(marker):].strip()
    return body_str, status, None


def extract_text(provider, body_str):
    """Returns (text_or_None, error_message_or_None)."""
    try:
        r = json.loads(body_str)
    except Exception as e:
        return None, "response body was not JSON: %s" % e

    if isinstance(r, dict) and "error" in r:
        err = r["error"]
        msg = err.get("message", str(err)) if isinstance(err, dict) else str(err)
        return None, msg

    try:
        if provider == "anthropic":
            return r["content"][0]["text"].strip(), None
        else:
            return r["choices"][0]["message"]["content"].strip(), None
    except (KeyError, IndexError, TypeError):
        return None, "unexpected response shape"


def parse_verdict(text):
    """Parses the model's strict-JSON verdict. Returns (pass_bool, reason)
    or (None, error_message) if the reply wasn't valid JSON with a 'pass'
    field. Defensive: strips a stray markdown fence if the model added one
    anyway, but does NOT try to guess intent beyond that -- a genuinely
    non-JSON reply is an error, not a pass."""
    t = text.strip()
    if t.startswith("```"):
        # Strip a fenced code block some models wrap JSON in despite
        # instructions not to.
        lines = t.split("\n")
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        t = "\n".join(lines).strip()

    try:
        obj = json.loads(t)
    except Exception:
        return None, "reply was not valid JSON: %s" % text[:200]

    if not isinstance(obj, dict) or "pass" not in obj:
        return None, "reply JSON missing 'pass' field: %s" % text[:200]

    verdict = obj.get("pass")
    if not isinstance(verdict, bool):
        return None, "reply 'pass' field was not a boolean: %s" % text[:200]

    reason = obj.get("reason", "")
    return verdict, str(reason)[:300]


def main():
    if len(sys.argv) < 6:
        print("FAIL: judge_request.py: bad arguments", file=sys.stdout)
        sys.exit(4)

    mode, provider, model, base_url, key_file = sys.argv[1:6]
    image_path = sys.argv[6] if len(sys.argv) > 6 else ""
    prompt = sys.argv[7] if len(sys.argv) > 7 else ""

    try:
        with open(key_file, "r") as f:
            api_key = f.read().strip()
    except OSError as e:
        print("FAIL: could not read key file: %s" % e)
        sys.exit(4)

    if not api_key:
        print("FAIL: empty judge API key")
        sys.exit(1)

    try:
        url, headers, body = build_request(mode, provider, model, base_url, image_path, prompt)
    except Exception as e:
        print("FAIL: could not build request: %s" % e)
        sys.exit(4)

    body_str, status, transport_err = run_curl(url, headers, body, api_key)

    if transport_err is not None or status is None:
        reason = transport_err or "no HTTP response received"
        if mode == "probe":
            print("PROBE_FAIL: network error: %s" % reason)
        else:
            print("FAIL: judge network error: %s" % reason)
        sys.exit(2)

    if status == "000":
        if mode == "probe":
            print("PROBE_FAIL: network error: connection failed")
        else:
            print("FAIL: judge network error: connection failed")
        sys.exit(2)

    if status in ("401", "403"):
        text, err = extract_text(provider, body_str)
        detail = err or text or "unauthorized"
        if mode == "probe":
            print("PROBE_FAIL: auth failed (HTTP %s): %s" % (status, detail))
        else:
            print("FAIL: judge auth failed (HTTP %s): %s" % (status, detail))
        sys.exit(1)

    if not status.startswith("2"):
        text, err = extract_text(provider, body_str)
        detail = err or text or body_str[:200]
        if mode == "probe":
            print("PROBE_FAIL: HTTP %s: %s" % (status, detail))
        else:
            print("FAIL: judge HTTP error %s: %s" % (status, detail))
        sys.exit(3)

    text, err = extract_text(provider, body_str)
    if text is None:
        if mode == "probe":
            print("PROBE_FAIL: malformed response: %s" % err)
        else:
            print("FAIL: judge returned malformed reply: %s" % err)
        sys.exit(4)

    if mode == "probe":
        print("PROBE_OK: provider=%s model=%s" % (provider, model))
        sys.exit(0)

    verdict, reason = parse_verdict(text)
    if verdict is None:
        print("FAIL: judge returned malformed reply: %s" % reason)
        sys.exit(4)

    if verdict:
        print("PASS")
    else:
        print("FAIL: %s" % (reason or "criteria not met"))
    sys.exit(0)


if __name__ == "__main__":
    main()
