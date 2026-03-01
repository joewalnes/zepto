Output website/out/screencaps/hero.mp4
Set Width 960
Set Height 600
Set FontSize 14
Set FontFamily "JetBrainsMono Nerd Font"
Set Padding 0
Set Shell zsh
Set TypingSpeed 50ms
Set PlaybackSpeed 1

# Open editor with the Renderer (large file, good for demo)
Type "zepto lib/Zepto/Renderer.pm"
Enter
Sleep 2s

# --- 1. File tree: explore and open files ---
# Toggle file tree
Ctrl+B
Sleep 1s
# Navigate down the tree
Down 5
Sleep 500ms
Down 3
Sleep 500ms
# Open a file from tree
Enter
Sleep 1s

# --- 2. Fuzzy file finder ---
Ctrl+O
Sleep 500ms
Type "editor"
Sleep 1s
# Select result
Enter
Sleep 1s

# --- 3. Scroll through large file, showing minimap ---
# Switch to Renderer.pm tab via command palette
Ctrl+Space
Sleep 300ms
Type "prev tab"
Sleep 300ms
Enter
Sleep 300ms
Ctrl+Space
Sleep 300ms
Type "prev tab"
Sleep 300ms
Enter
Sleep 500ms
# Toggle minimap on
Alt+M
Sleep 500ms
# Scroll through the file
PageDown
Sleep 400ms
PageDown
Sleep 400ms
PageDown
Sleep 400ms
PageDown
Sleep 400ms
PageDown
Sleep 400ms
PageDown
Sleep 400ms
# Scroll back up
PageUp
PageUp
PageUp
PageUp
PageUp
PageUp
Sleep 1s

# --- 4. Make edits, then show diffs ---
# Go to a line and make an edit
Ctrl+G
Sleep 300ms
Type "50"
Enter
Sleep 500ms
# Type some new code
Enter
Type "    # Demo edit: add a comment"
Sleep 500ms
Enter
Type "    my $demo_var = 42;"
Sleep 1s
# Show git diff
Alt+D
Sleep 2s
# Close diff
Escape
Sleep 500ms

# --- 5. Interactive find and replace ---
Ctrl+F
Sleep 300ms
Type "render"
Sleep 1s
# Step through matches
Ctrl+J
Sleep 300ms
Ctrl+J
Sleep 300ms
Ctrl+J
Sleep 500ms
# Close find
Escape
Sleep 500ms

# --- 6. Column (block) editing ---
# Go to a specific area
Ctrl+G
Sleep 300ms
Type "20"
Enter
Sleep 500ms
# Enter column selection mode
Alt+C
Sleep 300ms
# Select a block
Down 4
Right 10
Sleep 1s
# Type to insert on all lines
Type "XX"
Sleep 1s
# Undo to clean up
Ctrl+Z
Ctrl+Z
Sleep 500ms
# Exit column mode
Escape
Sleep 500ms

# --- 7. Theme switching ---
Ctrl+T
Sleep 1s
Down
Down
Enter
Sleep 1.5s
# Switch back
Ctrl+T
Sleep 500ms
Enter
Sleep 1s

# --- 8. Command palette ---
Ctrl+Space
Sleep 500ms
Type "word wrap"
Sleep 1s
# Close it
Escape
Sleep 1s

# --- 9. Multiple tabs ---
Ctrl+Space
Sleep 300ms
Type "next tab"
Sleep 300ms
Enter
Sleep 500ms
Ctrl+Space
Sleep 300ms
Type "next tab"
Sleep 300ms
Enter
Sleep 1s

# Final pause
Sleep 2s
