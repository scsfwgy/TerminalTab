#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
PLUGIN_FILE="$PROJECT_DIR/ai-complete.zsh"
content=$(<"$PLUGIN_FILE")

[[ "$content" == *"zle -N ai-ask _ai_ask"* ]] || {
    print -u2 "expected ai-ask widget to be registered"
    exit 1
}

[[ "$content" == *"_AI_ASK_BINDKEY_DEFAULT='^G'"* ]] || {
    print -u2 "expected default ask bindkey to remain Ctrl+G"
    exit 1
}

[[ "$content" == *'bindkey "$_AI_ASK_BINDKEY" ai-ask'* ]] || {
    print -u2 "expected ask binding to use configurable bindkey variable"
    exit 1
}

[[ "$content" == *'${_AI_ASK_BINDKEY_LABEL} → ask AI'* ]] || {
    print -u2 "expected startup text to mention ask shortcut label"
    exit 1
}

print "ok"
