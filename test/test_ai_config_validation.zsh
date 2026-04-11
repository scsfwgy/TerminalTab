#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}

missing_all_output=$(env -i PATH="$PATH" bash "$PROJECT_DIR/ai-suggest.sh" "ls")
[[ "$missing_all_output" == *"AI Complete is not configured. Missing required environment variables:"* ]] || {
    print -u2 "expected config guidance header for missing vars"
    print -u2 "$missing_all_output"
    exit 1
}
[[ "$missing_all_output" == *"- AI_COMPLETE_API_URL"* ]] || {
    print -u2 "expected missing URL in config guidance"
    print -u2 "$missing_all_output"
    exit 1
}
[[ "$missing_all_output" == *"- AI_COMPLETE_MODEL"* ]] || {
    print -u2 "expected missing MODEL in config guidance"
    print -u2 "$missing_all_output"
    exit 1
}
[[ "$missing_all_output" == *"- AI_COMPLETE_API_KEY"* ]] || {
    print -u2 "expected missing API key in config guidance"
    print -u2 "$missing_all_output"
    exit 1
}

missing_model_output=$(env -i PATH="$PATH" AI_COMPLETE_API_URL="https://example.com/v1/chat/completions" AI_COMPLETE_API_KEY="test-key" bash "$PROJECT_DIR/ai-suggest.sh" "ls")
[[ "$missing_model_output" == *"- AI_COMPLETE_MODEL"* ]] || {
    print -u2 "expected missing MODEL when only model is unset"
    print -u2 "$missing_model_output"
    exit 1
}
[[ "$missing_model_output" != *"- AI_COMPLETE_API_URL"* ]] || {
    print -u2 "did not expect URL to be reported missing"
    print -u2 "$missing_model_output"
    exit 1
}
[[ "$missing_model_output" != *"- AI_COMPLETE_API_KEY"* ]] || {
    print -u2 "did not expect API key to be reported missing"
    print -u2 "$missing_model_output"
    exit 1
}

print "ok"
