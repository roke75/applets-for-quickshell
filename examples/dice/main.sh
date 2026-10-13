#!/usr/bin/env bash
# State lives in $APPLET_DATA/last; actions update it and print the new state.
set -euo pipefail
last_file="$APPLET_DATA/last"

if [[ "${1:-}" == action ]]; then
    case "$2" in
        coin) result=$( (( RANDOM % 2 )) && echo Heads || echo Tails ) ;;
        d*) result=$(( RANDOM % ${2#d} + 1 )) ;;  # d6, d20, d100: sides after the "d"
        *) echo "unknown action $2" >&2; exit 1 ;;
    esac
    printf '%s: %s\n' "$2" "$result" > "$last_file"
fi

last=$(cat "$last_file" 2>/dev/null || echo "Nothing rolled yet")
cat <<JSON
{
  "text": "${last#*: }",
  "body": "$last",
  "items": [
    {"icon": "◐", "text": "Flip a coin", "run": "coin"},
    {"icon": "⚀", "text": "Roll d6", "run": "d6"},
    {"icon": "◆", "text": "Roll d20", "run": "d20"},
    {"icon": "%", "text": "Roll d100", "run": "d100"}
  ]
}
JSON
