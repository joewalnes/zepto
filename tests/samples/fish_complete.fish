#!/usr/bin/env fish
# Fish shell syntax highlighting sample

# Variables
set greeting "Hello, World!"
set -x PATH /usr/local/bin $PATH
set -g fish_greeting ""
set -l count 0
set -U favorite_color blue

# Lists
set fruits apple banana cherry
echo $fruits[1]
echo $fruits[2..3]
set -a fruits dragonfruit

# String operations
string match -r '^\d+' "42abc"
string replace -a 'old' 'new' "old text old"
string split ',' "a,b,c,d"
string trim "  spaces  "
string length "hello"

# Math
math "2 + 2"
math "sqrt(144)"
set result (math "3.14 * 2")

# Control flow
if test -f /etc/hostname
    echo "File exists"
else if test -d /tmp
    echo "Tmp exists"
else
    echo "Nothing found"
end

# Switch statement
switch $argv[1]
    case start
        echo "Starting..."
    case stop
        echo "Stopping..."
    case restart
        echo "Restarting..."
    case '*'
        echo "Unknown command"
end

# Loops
for file in *.txt
    echo "Processing: $file"
end

for i in (seq 1 10)
    if test $i -eq 5
        continue
    end
    echo $i
end

set counter 0
while test $counter -lt 5
    set counter (math "$counter + 1")
    echo "Count: $counter"
end

# Functions
function greet --description "Greet a user"
    argparse 'n/name=' 'l/loud' -- $argv
    or return

    set -l msg "Hello"
    if set -q _flag_name
        set msg "$msg, $_flag_name"
    else
        set msg "$msg, stranger"
    end

    if set -q _flag_loud
        string upper $msg
    else
        echo $msg
    end
end

function last_command_duration --on-event fish_postexec
    if test $CMD_DURATION -gt 5000
        echo "That took "(math "$CMD_DURATION / 1000")" seconds"
    end
end

function fish_prompt
    set -l last_status $status
    set -l cwd (prompt_pwd)
    set -l git_branch (git branch --show-current 2>/dev/null)

    set_color blue
    echo -n "$cwd"

    if test -n "$git_branch"
        set_color yellow
        echo -n " ($git_branch)"
    end

    if test $last_status -ne 0
        set_color red
    else
        set_color green
    end
    echo -n " \$ "
    set_color normal
end

# Command substitution
set current_dir (pwd)
set file_count (ls -1 | wc -l)
set git_status (git status --porcelain 2>/dev/null)

# Redirections and pipes
cat /etc/hosts | grep localhost > /dev/null 2>&1
command ls -la 2>/dev/null
echo "error" >&2

# Abbreviations
abbr -a gco 'git checkout'
abbr -a gst 'git status'
abbr -a ll 'ls -la'

# Completions
complete -c myapp -s h -l help -d "Show help"
complete -c myapp -s v -l verbose -d "Verbose output"
complete -c myapp -n "__fish_use_subcommand" -a "start stop restart"

# Status and test
if status is-interactive
    echo "Interactive session"
end

if command -sq docker
    echo "Docker is installed"
end

test -z "$DISPLAY"; and echo "No display"
test -n "$HOME"; or echo "No home"

# Builtins
builtin cd /tmp
type -t ls
functions -n

# Event handling
emit my_custom_event "data"
