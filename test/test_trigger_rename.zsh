#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
PLUGIN_FILE="$PROJECT_DIR/ai-complete.zsh"
content=$(<"$PLUGIN_FILE")

[[ "$content" == *"_ai_trigger()"* ]] || {
    print -u2 "expected trigger function to be renamed to _ai_trigger"
    exit 1
}

[[ "$content" == *"zle -N ai-trigger _ai_trigger"* ]] || {
    print -u2 "expected trigger widget registration to use ai-trigger/_ai_trigger"
    exit 1
}

[[ "$content" == *'bindkey "$_AI_TRIGGER_BINDKEY" ai-trigger'* ]] || {
    print -u2 "expected trigger binding to target ai-trigger"
    exit 1
}

[[ "$content" != *"_ai_tab()"* ]] || {
    print -u2 "expected legacy _ai_tab name to be removed"
    exit 1
}

print "ok"
