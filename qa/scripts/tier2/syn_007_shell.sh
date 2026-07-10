#!/usr/bin/env bash
# QA-SYN-007: Shell script syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-007: Shell script syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn007.sh" '#!/usr/bin/env bash
# Deploy script for production
set -euo pipefail

VERSION="1.2.3"
MAX_RETRIES=5
LOGFILE="/var/log/deploy.log"

# Check prerequisites
if [[ -z "${API_KEY:-}" ]]; then
    echo "Error: API_KEY not set" >&2
    exit 1
fi

deploy() {
    local target="$1"
    local count=0

    while [[ $count -lt $MAX_RETRIES ]]; do
        echo "Deploying to $target (attempt $((count + 1)))"
        if curl -s "https://api.example.com/$target" | grep -q "ok"; then
            return 0
        fi
        count=$((count + 1))
        sleep 2
    done
    return 1
}

# Main execution
for env in staging production; do
    deploy "$env" >> "$LOGFILE" 2>&1 || echo "Failed: $env"
done

echo "Done at $(date +%Y-%m-%d)"')
qa_start "$file"

shot="$QA_TMPDIR/shell_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a shell/bash script in a terminal text editor with syntax highlighting. Verify ALL of these: (1) Keywords like 'if', 'then', 'fi', 'while', 'do', 'done', 'for', 'in', 'function', 'local', 'return', 'exit' are highlighted in a distinct color. (2) Strings in double quotes like '1.2.3', 'Error: API_KEY not set' are highlighted as strings. (3) Variable references like \$1, \$target, \$MAX_RETRIES, \$count are in a distinct color. (4) Comments starting with # are in a muted/gray color. (5) The shebang line #!/usr/bin/env bash is highlighted. (6) Numbers like 5, 1, 0, 2 are visible. (7) Command substitution \$(date ...) is distinguishable. (8) At least 4 distinct colors are used." \
    "Shell script syntax highlighting with keywords, variables, strings, comments"

qa_keys "ctrl-q"

qa_summary
