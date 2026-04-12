#!/bin/zsh
set -euo pipefail

TEST_DIR=${0:A:h}
PROJECT_DIR=${TEST_DIR:h}

bindkey() { :; }
zle() { :; }
_zsh_autosuggest_start() { :; }

source "$PROJECT_DIR/ai-complete.zsh" >/dev/null

LINES=10
_ai_setup_render_mode

_AI_SUGGESTIONS=('ls -la' 'ls -lh' 'ls -laR' 'ls -lS' 'ls -lt')
_AI_SCROLL=0
_AI_INDEX=0
_AI_RENDER_MODE=multiline
_AI_CURSOR_ROW=8

_ai_adjust_render_mode_for_space
[[ "$_AI_RENDER_MODE" == "inline" ]] || {
    print -u2 "expected fallback to inline when remaining lines are insufficient"
    exit 1
}

_AI_RENDER_MODE=multiline
_AI_CURSOR_ROW=2
_ai_adjust_render_mode_for_space
[[ "$_AI_RENDER_MODE" == "multiline" ]] || {
    print -u2 "expected multiline to remain when enough lines are available"
    exit 1
}

LINES=0
_AI_RENDER_MODE=multiline
_AI_CURSOR_ROW=8
_ai_adjust_render_mode_for_space
[[ "$_AI_RENDER_MODE" == "multiline" ]] || {
    print -u2 "expected multiline to remain when terminal height is unavailable"
    exit 1
}

print "ok"
