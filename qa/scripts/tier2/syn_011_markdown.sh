#!/usr/bin/env bash
# QA-SYN-011: Markdown syntax highlighting appearance
source "$(dirname "$0")/../../lib/qa-helpers.sh"
QA_TIER=2
qa_header "QA-SYN-011: Markdown syntax highlighting (visual)"

file=$(qa_tmpfile_nl "syn011.md" '# Main Heading

## Section Two

This is regular paragraph text with **bold text** and *italic text* and `inline code`.

### Third Level

- First bullet item
- Second item with [a link](https://example.com)
- Third item

1. Numbered list
2. Second numbered

> This is a blockquote
> with multiple lines

```python
def hello():
    print("world")
```

Here is a [reference link][1] and an image: ![alt text](image.png)

---

[1]: https://example.com "Example"

Final paragraph with ~~strikethrough~~ text.')
qa_start "$file"
sleep 0.5

shot="$QA_TMPDIR/markdown_syntax.png"
qa_screenshot "$shot"

qa_assert_visual "$shot" \
    "This shows a Markdown file in a terminal text editor. Verify: (1) Headings starting with # are in a different color from body text. (2) At least 2 distinct colors are used across the document. (3) The file is readable and properly formatted in the editor." \
    "Markdown syntax highlighting with headings distinct from body"

qa_keys "ctrl-q"

qa_summary
