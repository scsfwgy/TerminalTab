#!/bin/zsh
set -euo pipefail

TEST_DIR=${0:A:h}
PROJECT_DIR=${TEST_DIR:h}

bindkey() { :; }
zle() { :; }
_zsh_autosuggest_start() { :; }

source "$PROJECT_DIR/ai-complete.zsh" >/dev/null

AI_COMPLETE_RENDER_MODE=multiline
TERM_PROGRAM=Apple_Terminal
_ai_setup_render_mode
[[ "$_AI_RENDER_MODE" == "multiline" ]] || {
    print -u2 "expected explicit multiline mode to override terminal auto fallback"
    exit 1
}

AI_COMPLETE_RENDER_MODE=inline
TERM_PROGRAM=
_ai_setup_render_mode
[[ "$_AI_RENDER_MODE" == "inline" ]] || {
    print -u2 "expected explicit inline mode to be respected"
    exit 1
}

AI_COMPLETE_RENDER_MODE=auto
TERM_PROGRAM=Apple_Terminal
_ai_setup_render_mode
[[ "$_AI_RENDER_MODE" == "multiline" ]] || {
    print -u2 "expected auto mode to start in multiline and defer fallback until space check"
    exit 1
}

AI_COMPLETE_RENDER_MODE=auto
TERM_PROGRAM=
_ai_setup_render_mode
[[ "$_AI_RENDER_MODE" == "multiline" ]] || {
    print -u2 "expected auto mode to use multiline for other terminals"
    exit 1
}

print "ok"
