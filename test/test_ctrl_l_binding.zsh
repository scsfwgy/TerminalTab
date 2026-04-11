#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
PLUGIN_FILE="$PROJECT_DIR/ai-complete.zsh"
content=$(<"$PLUGIN_FILE")

[[ "$content" == *"_AI_TRIGGER_BINDKEY_DEFAULT='^L'"* ]] || {
    print -u2 "expected default trigger bindkey to remain Ctrl+L"
    exit 1
}

[[ "$content" == *'bindkey "$_AI_TRIGGER_BINDKEY" ai-trigger'* ]] || {
    print -u2 "expected trigger binding to use configurable bindkey variable"
    exit 1
}

[[ "$content" != *"bindkey '^S'  "* ]] || {
    print -u2 "expected old Ctrl+S binding to be removed"
    exit 1
}

[[ "$content" == *'${_AI_TRIGGER_BINDKEY_LABEL} → list suggestions'* ]] || {
    print -u2 "expected startup text to mention trigger shortcut label"
    exit 1
}

print "ok"
