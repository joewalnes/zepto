#!/bin/bash
# A complete Shell script demonstrating various syntax elements

set -euo pipefail

# Constants/Environment variables
readonly MAX_VALUE=100
export PI=3.14159
declare -r GREETING="Hello, World!"

# Variables
name="World"
count=42
unset unused_var

# Arrays
items=(one two three "four with spaces")
declare -a numbers=(1 2 3 4 5)
declare -A config=(
    [host]="localhost"
    [port]=8080
)

# String operations
echo "Hello, $name!"
echo "Hello, ${name}!"
echo "Length: ${#name}"
echo "Substring: ${name:0:3}"
echo "Replace: ${name/o/0}"
echo "Default: ${undefined:-default}"
echo "Assign: ${unset:=value}"

# Quoting
single='No $expansion here'
double="With $name expansion"
escaped="Quotes: \"nested\" and 'mixed'"
literal=$'Special\tcharacters\n'

# Here documents
cat <<EOF
This is a here-doc
with variable expansion: $name
EOF

cat <<'NOEXPAND'
This is a literal here-doc
$name is not expanded
NOEXPAND

cat <<-INDENTED
	Indented here-doc
	tabs are stripped
INDENTED

# Command substitution
current_date=$(date +%Y-%m-%d)
old_style=`whoami`

# Arithmetic
result=$((count + 10))
((count++))
let "count += 5"

# Conditionals
if [[ $count -gt 0 ]]; then
    echo "Positive"
elif [[ $count -eq 0 ]]; then
    echo "Zero"
else
    echo "Negative"
fi

# Test operators
[[ -f /etc/passwd ]] && echo "File exists"
[[ -d /tmp ]] || echo "Not a directory"
[[ -n "$name" ]] && echo "Not empty"
[[ -z "$empty" ]] && echo "Is empty"
[[ "$name" == "World" ]] && echo "Match"
[[ "$name" =~ ^[A-Z] ]] && echo "Starts with capital"

# Case statement
case "$name" in
    World)
        echo "Hello World"
        ;;
    [Uu]niverse)
        echo "Hello Universe"
        ;;
    *)
        echo "Hello someone"
        ;;
esac

# Loops
for item in "${items[@]}"; do
    echo "$item"
done

for ((i=0; i<10; i++)); do
    [[ $((i % 2)) -eq 0 ]] && continue
    [[ $i -gt 5 ]] && break
    echo "$i"
done

while [[ $count -gt 0 ]]; do
    ((count--))
done

until [[ $count -ge 5 ]]; do
    ((count++))
done

# Functions
function greet() {
    local who="${1:-World}"
    echo "Hello, $who!"
    return 0
}

# Alternative function syntax
process_data() {
    local -r data="$1"
    local -i number=42
    echo "Processing: $data"
}

# Call functions
greet "User"
result=$(greet)

# Pipes and redirections
echo "test" | grep -o "e"
ls -la > /tmp/output.txt 2>&1
cat < /etc/hostname
command 2>/dev/null || true
exec 3>&1

# Process substitution
diff <(ls dir1) <(ls dir2)
while read -r line; do
    echo "$line"
done < <(cat /etc/passwd)

# Brace expansion
echo {a,b,c}
echo {1..10}
echo {01..10..2}

# Parameter expansion
echo "${items[*]}"
echo "${items[@]}"
echo "${!config[@]}"
echo "${#items[@]}"

# Special variables
echo "Script: $0"
echo "Args: $@"
echo "Count: $#"
echo "PID: $$"
echo "Exit: $?"
echo "Last bg: $!"

# Subshell
(
    cd /tmp
    pwd
)

# Group commands
{ echo "one"; echo "two"; } > output.txt

# Coprocess
coproc mycoproc { cat; }

# Trap
trap 'echo "Cleanup"; exit' EXIT SIGINT SIGTERM

# Source/include
source ./lib.sh 2>/dev/null || true
. ./config.sh 2>/dev/null || true

# Exit
exit 0
