#!/bin/sh
# SessionStart hook for Zepto.
#
# Ensures the interactive-testing toolchain (hangon + tmux) required by
# CLAUDE.md's Testing Workflow is available in this session. Best-effort:
# installs hangon via `go install` if it's missing and `go` is available,
# and makes sure $HOME/go/bin ends up on PATH for the rest of the session.
#
# POSIX sh only (no bashisms — must run under /bin/sh on any Unix).
# Always exits 0: this hook must never block session start, even if
# installation fails or the toolchain can't be found.

log() {
    printf 'session-start: %s\n' "$*" >&2
}

# --- hangon ------------------------------------------------------------

if command -v hangon >/dev/null 2>&1; then
    log "hangon already installed ($(command -v hangon))"
else
    if command -v go >/dev/null 2>&1; then
        log "hangon not found; installing via 'go install github.com/joewalnes/hangon@main'..."
        if go install github.com/joewalnes/hangon@main >/dev/null 2>&1; then
            log "hangon installed"
        else
            log "WARNING: 'go install github.com/joewalnes/hangon@main' failed."
            log "Install manually: https://github.com/joewalnes/hangon (e.g. brew install joewalnes/tap/hangon)"
        fi
    else
        log "WARNING: 'go' not found on PATH; cannot auto-install hangon."
        log "Install manually: https://github.com/joewalnes/hangon (e.g. brew install joewalnes/tap/hangon, or download a release binary)"
    fi

    # Make sure the go install destination is on PATH, whether or not the
    # install above just succeeded (it may already have been installed
    # there in a previous session on a cached container).
    gobin_dir="${GOBIN:-${GOPATH:-$HOME/go}/bin}"
    if [ -d "$gobin_dir" ]; then
        case ":$PATH:" in
            *":$gobin_dir:"*)
                : # already on PATH
                ;;
            *)
                if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
                    echo "export PATH=\"$gobin_dir:\$PATH\"" >> "$CLAUDE_ENV_FILE"
                    log "added $gobin_dir to PATH via \$CLAUDE_ENV_FILE"
                else
                    log "add $gobin_dir to your PATH to use hangon, e.g.:"
                    log "  export PATH=\"$gobin_dir:\$PATH\""
                fi
                ;;
        esac
    fi
fi

# --- tmux ----------------------------------------------------------------

if command -v tmux >/dev/null 2>&1; then
    log "tmux already installed ($(command -v tmux))"
else
    log "WARNING: tmux not found. hangon requires tmux to run QA sessions."
    log "Install it via your package manager, e.g.:"
    log "  Debian/Ubuntu: sudo apt-get install -y tmux"
    log "  macOS:         brew install tmux"
fi

exit 0
