#!/bin/zsh
set -euo pipefail

TEST_DIR=${0:A:h}
PROJECT_DIR=${TEST_DIR:h}

bindkey() { :; }
zle() { :; }
_zsh_autosuggest_start() { :; }

source "$PROJECT_DIR/ai-complete.zsh" >/dev/null

[[ "$(_ai_parse_cursor_row $'\e[12;34R')" == "12" ]] || {
    print -u2 "expected cursor row parser to extract row number from CPR response"
    exit 1
}

[[ "$(_ai_parse_cursor_row 'garbage')" == "" ]] || {
    print -u2 "expected invalid CPR response to produce empty row"
    exit 1
}

query_log=$(mktemp)
mock_read_buffer=($'\e' '[' '9' ';' '3' '4' 'R')
stty() {
    if [[ "$1" == "-g" ]]; then
        print -- "saved-state"
        return 0
    fi
    return 0
}
read() {
    local target_var="${@: -1}"
    (( ${#mock_read_buffer} > 0 )) || return 1
    REPLY="${mock_read_buffer[1]}"
    mock_read_buffer=("${mock_read_buffer[@]:1}")
    [[ -n "$target_var" && "$target_var" != read ]] && typeset -g "$target_var=$REPLY"
    return 0
}
_ai_write_cursor_query() {
    print -r -- "$1" > "$query_log"
}

_AI_TTY_PATH=/dev/null
[[ "$(_ai_get_cursor_row)" == "9" ]] || {
    rm -f "$query_log"
    print -u2 "expected cursor row reader to parse terminal CPR response"
    exit 1
}

[[ "$(<"$query_log")" == "/dev/null" ]] || {
    rm -f "$query_log"
    print -u2 "expected cursor row reader to request cursor position from terminal"
    exit 1
}
rm -f "$query_log"

LINES=20
_AI_SUGGESTIONS=('ls -la' 'ls -lh' 'ls -laR' 'ls -lS' 'ls -lt')
_AI_SCROLL=0
_AI_INDEX=0

_AI_CURSOR_ROW=14
_ai_adjust_render_mode_for_space
[[ "$_AI_RENDER_MODE" == "inline" ]] || {
    print -u2 "expected inline fallback when menu would hit bottom from current cursor row"
    exit 1
}

_AI_CURSOR_ROW=5
_ai_adjust_render_mode_for_space
[[ "$_AI_RENDER_MODE" == "multiline" ]] || {
    print -u2 "expected multiline render when enough rows remain below cursor"
    exit 1
}

print "ok"
