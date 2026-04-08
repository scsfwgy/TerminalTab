#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
PLUGIN_FILE="$PROJECT_DIR/ai-complete.zsh"
content=$(<"$PLUGIN_FILE")

[[ "$content" == *"bindkey '^[[Z' ai-trigger"* ]] || {
    print -u2 "expected Shift+Tab to be bound to ai-trigger"
    exit 1
}

[[ "$content" != *"bindkey '^I'   ai-tab"* ]] || {
    print -u2 "expected Tab binding for ai-tab to be removed"
    exit 1
}

[[ "$content" == *"AI command completion loaded. Shift+Tab → suggest"* ]] || {
    print -u2 "expected startup text to use AI command completion loaded"
    exit 1
}

print "ok"
