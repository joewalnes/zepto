# Zepto Tutorial

A quick walkthrough of the essentials.

## Opening Files

From the command line:

    zepto myfile.txt
    zepto file1.txt file2.txt
    zepto .                        # open a directory

Or from inside the editor, press `Ctrl+O` to open the file picker.

## Saving and Quitting

- `Ctrl+S` - Save
- `Ctrl+W` - Save and close tab
- `Ctrl+Q` - Quit

If a file has never been saved, you'll be prompted for a filename.

## Basic Navigation

- **Arrow keys** - move cursor
- **Home / End** - start / end of line
- **Ctrl+Home / Ctrl+End** - start / end of file
- **Page Up / Page Down** - scroll by page
- **Ctrl+G** - go to a specific line number
- **Mouse click** - place cursor anywhere
- **Mouse scroll** - scroll the document

## Editing

- Just type - text is inserted at the cursor
- **Ctrl+Z** - Undo
- **Ctrl+Y** - Redo
- **Ctrl+X / Ctrl+C / Ctrl+V** - Cut, Copy, Paste
- **Ctrl+D** - Select next occurrence (multi-cursor)
- **Alt+Up / Alt+Down** - Move line up/down
- **Ctrl+U** - Duplicate line
- **Ctrl+/** - Toggle comment
- In Markdown and plain-text files, pressing **Enter** at the end of a
  list item (`- `, `1. `, `> `, `- [ ] `) continues the list on the new
  line; pressing Enter on an empty item removes the marker instead.
  Toggle via "Continue Lists" in the command palette.

## Selection

- **Shift+Arrow keys** - select text
- **Ctrl+A** - Select all
- **Click and drag** - select with mouse
- **Double-click** - select word
- **Triple-click** - select line

## Command Palette

Press `Ctrl+Space` to open the command palette. Start typing to
filter. This is the fastest way to discover everything Zepto can do.

## AI Completion (Optional)

Zepto can show AI-generated ghost-text suggestions as you type, similar to
buffer-word completion. This is completely opt-in and off by default --
Zepto makes no network calls unless you turn it on.

To set it up:

1. Open the command palette (`Ctrl+Space`) and run **AI: Configure**.
2. Pick a provider (OpenAI, Anthropic, OpenRouter, Ollama, or others) --
   the base URL fills in automatically.
3. Enter your API key (shown masked). Ollama and other local/no-auth
   servers don't need one.
4. Click **Test Connection** to verify the key works and list the
   provider's available models, then pick one.
5. **Save**.
6. Run **AI: Toggle Completion** from the palette to turn it on. The
   first time (per endpoint), Zepto asks you to confirm: it names the
   exact endpoint your cursor context will be sent to.

Only a small window of text around your cursor is ever sent -- never the
whole file. The status bar shows an `AI Completion` pill when it's on;
if it's on but can't actually run (for example `curl` isn't installed, or
the key was cleared), the pill shows a `!` so you know it's not silently
working.

## Things to Try

- **Find and Replace** - `Ctrl+F` to find, then toggle replace mode
  from the palette. Supports regex.
- **Find in Files** - `Ctrl+Shift+F` to search across all project files.
- **Diff View** - `Alt+D` to see git changes inline.
- **Transform via Shell** - Select text, press `Alt+T`, and pipe it
  through any shell command (sort, awk, jq, etc.).
- **Column Editing** - `Alt+C` to toggle column selection mode. Select
  a rectangle of text and edit it.
- **File Tree** - `Ctrl+B` to toggle the sidebar file tree.
- **Theme** - `Ctrl+T` to switch between dark and light themes.
- **Word Wrap** - `Alt+Z` to toggle word wrap.
- **Minimap** - `Alt+M` to toggle the document minimap.
- **Recent Files** - `Ctrl+E` to quickly switch between recent files.
- **Multi-cursor** - `Ctrl+D` to select the next occurrence of the
  current word and edit all at once.
