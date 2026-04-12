#!/bin/zsh
set -euo pipefail

TEST_DIR=${0:A:h}
PROJECT_DIR=${TEST_DIR:h}

bindkey() { :; }
last_message=""
zle() {
    case "$1" in
        -M)
            last_message="$2"
            ;;
        redisplay|-R|-N|expand-or-complete|down-line-or-history|up-line-or-history|accept-line|send-break)
            ;;
    esac
}
_zsh_autosuggest_start() { :; }

source "$PROJECT_DIR/ai-complete.zsh" >/dev/null

LINES=10
_AI_CURSOR_ROW=8
_ai_setup_render_mode
_ai_adjust_render_mode_for_space
[[ "$_AI_RENDER_MODE" == "inline" ]] || {
    print -u2 "expected low remaining space to switch into inline render mode"
    exit 1
}

_AI_SUGGESTIONS=('ls -la' 'ls -lh' 'ls -lt')
_AI_INDEX=1
_AI_ACTIVE=1
_AI_SCROLL=0
_ai_get_cursor_row() {
    print -- "8"
}
_ai_show

[[ "$last_message" == *"[2/3] ls -lh"* ]] || {
    print -u2 "expected inline message to show current suggestion index and content"
    exit 1
}

print "ok"
