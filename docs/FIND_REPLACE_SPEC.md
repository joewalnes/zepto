# Find/Replace Functional Specification

## Overview

Zepto provides a live, interactive find/replace experience similar to modern editors like VS Code. The find bar appears in the status bar area at the bottom of the screen, and matches are highlighted in real-time as the user types.

## Modes

### Find Mode (Ctrl+F)
- Opens find bar with query input field
- User types search query, matches highlight live in document
- Navigate between matches with Up/Down arrows
- Press Enter to exit find mode with current match selected
- Press Escape to cancel and return to editing
- Press Tab to switch to Replace mode

### Replace Mode (Ctrl+R or Tab from Find)
- Opens find bar with both query and replacement fields
- Tab switches focus between query and replacement fields
- As user types replacement, document shows live preview of what text will look like after replacement (green highlighting)
- Press Enter to execute replace-all
- Press Escape to cancel

## UI Layout

### Find-Only Footer (80 columns)
```
Find:[query field] [.*]^R[Aa]^I 1/17 ↑↓ Tab:repl Enter Esc
     |-- 12 chars-|                    |-- hints --|
```

### Replace Footer (80 columns)
```
Find:[query    ]→[replace   ] [.*]^R[Aa]^I 1/17 ↑↓ Enter:all Esc
     |--10 ch--|  |--10 ch--|              |-- hints --|
```

## Controls

### Keyboard
| Key | Action |
|-----|--------|
| Ctrl+F | Open find mode |
| Ctrl+R | Open replace mode |
| Escape | Close find/replace, return to editing |
| Enter | Find mode: exit with match selected. Replace mode: replace all |
| Tab | Toggle between find and replace fields |
| Up Arrow | Navigate to previous match |
| Down Arrow | Navigate to next match |
| Alt+R (or ^R) | Toggle regex mode |
| Alt+I (or ^I) | Toggle case sensitivity |
| Backspace | Delete character in active field |
| Any character | Add to active field (query or replace) |

### Mouse
- Click on [.*] button to toggle regex
- Click on [Aa] button to toggle case sensitivity

## Toggle Buttons

### Regex Toggle [.*]
- When ON (highlighted): Query is treated as PCRE regex
- When OFF: Query is literal text (special chars escaped)
- Default: ON

### Case Sensitivity Toggle [Aa]
- When highlighted (case sensitive): Matches exact case
- When not highlighted (case insensitive): Ignores case
- Default: Case insensitive (not highlighted)

## Match Highlighting

### In Document
- All matches: Yellow/orange background (match_bg color)
- Current match: Brighter orange background (current_match_bg color)
- Replacement preview: Green background (replacement_bg color)

### Match Counter
- Shows "N/M" where N is current match index (1-based) and M is total matches
- Shows "0" when no matches found

## Behavior Details

### Live Search
1. As user types in query field, matches update immediately
2. View scrolls to show first match
3. Current match index resets to 0 (first match)

### Match Navigation
1. Down arrow: Move to next match, wrap to first if at end
2. Up arrow: Move to previous match, wrap to last if at start
3. View scrolls to keep current match visible

### Live Replacement Preview
1. Only shown when replacement field is non-empty
2. Document displays what text would look like after all replacements
3. Replacement text shown with green highlight (replacement_bg)
4. Original document is NOT modified until Enter is pressed

### Replace All
1. Triggered by Enter in replace mode
2. All matches replaced simultaneously
3. Document marked as modified
4. Find mode closes, returns to editing

### Regex Replacement
- Supports backreferences: $1, $2, etc.
- Example: Find `(\w+)@(\w+)` Replace `$2:$1` transforms `foo@bar` to `bar:foo`

## State Machine

```
                    Ctrl+F
    EDITING ─────────────────► FIND
       ▲                         │
       │                         │ Tab
       │     Escape              ▼
       ├─────────────────────── REPLACE
       │                         │
       │     Enter (replace)     │
       └─────────────────────────┘
```

## Error Handling

### Invalid Regex
- When regex mode is ON and query is invalid regex
- No matches shown (matches array empty)
- No error message (silent failure)
- User can continue typing to fix regex

### Empty Query
- No matches highlighted
- Match counter shows "0"

### No Matches Found
- Match counter shows "0"
- Up/Down navigation does nothing

## Data Structures

### Find State (`$editor->{find}`)
```perl
{
    query           => '',      # Search pattern
    replace         => '',      # Replacement text
    field           => 'find',  # Active field: 'find' or 'replace'
    regex           => 1,       # Regex mode enabled
    case_insensitive => 1,      # Case insensitive mode
    matches         => [],      # Array of match objects
    current         => 0,       # Index of current match
    show_replace    => 0,       # Show replace field
}
```

### Match Object
```perl
{
    start     => 0,       # Byte offset in document
    end       => 5,       # End byte offset
    line      => 0,       # Line number (0-indexed)
    col       => 0,       # Column number (0-indexed)
    end_line  => 0,       # End line
    end_col   => 5,       # End column
    text      => 'match', # Matched text (for backrefs)
}
```

## Theme Colors

| Color Key | Purpose |
|-----------|---------|
| match_bg | Background for non-current matches |
| match_fg | Foreground for non-current matches |
| current_match_bg | Background for current match |
| current_match_fg | Foreground for current match |
| replacement_bg | Background for replacement preview |
| replacement_fg | Foreground for replacement preview |
| dialog_input_bg | Background for active input field |
| dialog_input_fg | Foreground for active input field |

## Known Issues / TODO

1. Multi-line matches not fully supported in preview
2. Incremental replace (one at a time) not implemented
3. Replace with confirmation not implemented
4. Find in selection not implemented
5. Whole word matching option not implemented
6. Search history not implemented

## Implementation Files

- `lib/Zepto/Editor.pm` - State management, event handling
- `lib/Zepto/Editor/Commands.pm` - cmd_find entry point (unified find/replace)
- `lib/Zepto/Renderer.pm` - Find footer rendering, match highlighting
- `lib/Zepto/Theme.pm` - Match highlight colors
