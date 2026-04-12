#!/bin/zsh
set -euo pipefail

TEST_DIR=${0:A:h}
PROJECT_DIR=${TEST_DIR:h}

bindkey() { :; }
zle() { :; }
_zsh_autosuggest_start() { :; }

source "$PROJECT_DIR/ai-complete.zsh" >/dev/null

_AI_ACTIVE=1
_AI_SUGGESTIONS=('ls -la' 'ls -lh' 'ls -lt')
_AI_INDEX=1
_AI_SCROLL=0
_AI_LIST_LINES=0
_AI_ORIGINAL='ls'
_AI_RIGHT=' --color=auto'
LBUFFER='ls'
RBUFFER=' --color=auto'

if _ai_buffer_changed; then
    print -u2 "expected buffer to still be considered unchanged while only highlight moved"
    exit 1
fi

print "ok"
