#!/usr/bin/env bash
# QA-SYN-001: Python syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-001: Python syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn001.py" "#!/usr/bin/env python3
import os
from pathlib import Path

# Global constant
MAX_RETRIES = 3

def greet(name: str) -> str:
    \"\"\"Return a greeting message.\"\"\"
    message = f'Hello, {name}!'
    count = 42 + 0xFF
    return message

class Worker:
    def __init__(self):
        self.active = True
        self.items = [1, 2, 3]

    async def run(self):
        while self.active:
            await self.process()

if __name__ == '__main__':
    w = Worker()
    print(greet('world'))")
qa_start "$file"

shot="$QA_TMPDIR/python_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Python file in a terminal text editor with syntax highlighting. Verify ALL of these: (1) Keywords like 'def', 'class', 'import', 'from', 'return', 'if', 'while', 'async', 'await' are highlighted in a distinct color (typically purple/violet). (2) Strings like 'Hello, {name}!' are in a different color (typically green). (3) The comment '# Global constant' is in a muted/gray color, clearly different from code. (4) Numbers like 42 and 0xFF are in another color (typically orange). (5) The triple-quoted docstring is highlighted as a string. (6) At least 4 distinct colors are visible across the code." \
    "Python syntax highlighting with distinct token colors"

qa_keys "ctrl-q"

qa_summary
