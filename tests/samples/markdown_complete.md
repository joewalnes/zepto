# Complete Markdown Example

This document demonstrates various Markdown syntax elements.

## Table of Contents

1. [Headers](#headers)
2. [Emphasis](#emphasis)
3. [Lists](#lists)
4. [Links and Images](#links-and-images)
5. [Code](#code)
6. [Tables](#tables)
7. [Blockquotes](#blockquotes)

---

## Headers

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6

Alternative H1
==============

Alternative H2
--------------

## Emphasis

This is **bold text** and this is also __bold__.

This is *italic text* and this is also _italic_.

This is ***bold and italic*** and also ___bold italic___.

This is ~~strikethrough~~ text.

This is ==highlighted== text (some flavors).

## Lists

### Unordered Lists

- Item 1
- Item 2
  - Nested item 2.1
  - Nested item 2.2
    - Deeply nested 2.2.1
- Item 3

* Alternative marker 1
* Alternative marker 2

+ Another marker 1
+ Another marker 2

### Ordered Lists

1. First item
2. Second item
   1. Nested 2.1
   2. Nested 2.2
3. Third item

1) Alternative style 1
2) Alternative style 2

### Task Lists

- [x] Completed task
- [ ] Incomplete task
- [x] Another completed task
  - [ ] Nested incomplete
  - [x] Nested complete

### Definition Lists

Term 1
: Definition for term 1

Term 2
: Definition for term 2
: Another definition

## Links and Images

### Links

[Inline link](https://example.com)

[Inline link with title](https://example.com "Title text")

[Reference link][ref1]

[Numbered reference][1]

[Link to heading](#headers)

<https://autolink-example.com>

<email@example.com>

[ref1]: https://example.com "Reference 1"
[1]: https://example.com "Numbered Reference"

### Images

![Alt text](image.png)

![Alt text with title](image.png "Image title")

[![Linked image](image.png)](https://example.com)

![Reference image][img1]

[img1]: image.png "Reference image title"

## Code

### Inline Code

Use `console.log()` for debugging.

The `<html>` element is the root.

Press `Ctrl+C` to copy.

### Code Blocks

```
Plain code block
No syntax highlighting
```

```javascript
// JavaScript code block
function greet(name) {
    console.log(`Hello, ${name}!`);
}

const items = [1, 2, 3];
items.forEach(item => console.log(item));
```

```python
# Python code block
def factorial(n):
    """Calculate factorial recursively."""
    if n <= 1:
        return 1
    return n * factorial(n - 1)

result = factorial(5)
print(f"5! = {result}")
```

```rust
// Rust code block
fn main() {
    let x: i32 = 42;
    println!("The answer is {}", x);
}
```

    Indented code block (4 spaces)
    Also works for code
    No syntax highlighting

### Diff Syntax

```diff
- Removed line
+ Added line
  Unchanged line
! Changed line
# Comment
```

## Tables

| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |

| Left | Center | Right |
|:-----|:------:|------:|
| L1   |   C1   |    R1 |
| L2   |   C2   |    R2 |

| Compact | Table |
|-|-|
| A | B |
| C | D |

## Blockquotes

> Simple blockquote

> Multi-line blockquote
> continues here
> and here.

> Blockquote with other elements
>
> - List item 1
> - List item 2
>
> ```python
> print("Code in blockquote")
> ```

> Nested blockquote
>
>> Inner level
>>
>>> Even deeper
>>
>> Back to second level

## Horizontal Rules

---

***

___

## Footnotes

Here is a footnote reference[^1] and another[^2].

Here is a named footnote[^named].

[^1]: This is the first footnote.
[^2]: This is the second footnote with multiple paragraphs.

    Indented content belongs to the footnote.

[^named]: A named footnote for clarity.

## Math (LaTeX)

Inline math: $E = mc^2$

Display math:

$$
\frac{n!}{k!(n-k)!} = \binom{n}{k}
$$

## HTML in Markdown

<details>
<summary>Click to expand</summary>

Hidden content that can be expanded.

- Can contain **Markdown**
- With `code` and other elements

</details>

<div align="center">
  <strong>Centered content</strong>
</div>

<kbd>Ctrl</kbd> + <kbd>C</kbd>

Text with <mark>highlighted</mark> content.

## Escaping

\*Not italic\*

\**Not bold\**

\# Not a header

\[Not a link\](url)

\`Not code\`

## Abbreviations

HTML is a markup language.

*[HTML]: Hypertext Markup Language

## Emoji

:smile: :heart: :thumbsup: :rocket:

😀 ❤️ 👍 🚀 (Unicode emoji)

## Comments

[//]: # (This is a comment)
[comment]: <> (Another comment style)

<!-- HTML comment also works -->

## Admonitions (Some flavors)

!!! note "Title"
    This is a note admonition.

!!! warning
    This is a warning without title.

!!! danger "Important"
    Critical information here.

---

*Document end*
