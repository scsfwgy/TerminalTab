#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
PLUGIN_FILE="$PROJECT_DIR/ai-complete.zsh"
TEST_TMP=$(mktemp -d)
VENDOR_DIR="$PROJECT_DIR/vendor/zsh-autosuggestions"
trap 'rm -rf "$TEST_TMP" "$VENDOR_DIR"' EXIT

run_with_stub() {
    local home_dir="$1"
    shift
    mkdir -p "$VENDOR_DIR"
    printf "%s\n" "_zsh_autosuggest_start() { :; }" > "$VENDOR_DIR/zsh-autosuggestions.zsh"
    env -i PATH="$PATH" HOME="$home_dir" "$@" zsh -c '
        source "'$PLUGIN_FILE'"
    ' 2>&1
}

missing_all_output=$(env -i PATH="$PATH" bash "$PROJECT_DIR/ai-command-request.sh" list "ls")
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

missing_model_output=$(env -i PATH="$PATH" AI_COMPLETE_API_URL="https://example.com/v1/chat/completions" AI_COMPLETE_API_KEY="test-key" bash "$PROJECT_DIR/ai-command-request.sh" list "ls")
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

empty_trigger_error=$(run_with_stub "$TEST_TMP/home0")
[[ "$empty_trigger_error" != *"AI_COMPLETE_TRIGGER_BINDKEY cannot be empty"* ]] || {
    print -u2 "expected empty trigger test to require explicit env override"
    exit 1
}

invalid_trigger_output=$(run_with_stub "$TEST_TMP/home1" AI_COMPLETE_TRIGGER_BINDKEY='' || true)
[[ "$invalid_trigger_output" == *"AI_COMPLETE_TRIGGER_BINDKEY cannot be empty"* ]] || {
    print -u2 "expected empty trigger bindkey to fail"
    print -u2 "$invalid_trigger_output"
    exit 1
}

escape_trigger_output=$(run_with_stub "$TEST_TMP/home2" AI_COMPLETE_TRIGGER_BINDKEY=$'\e' || true)
[[ "$escape_trigger_output" == *"AI_COMPLETE_TRIGGER_BINDKEY does not support bare Escape"* ]] || {
    print -u2 "expected bare escape bindkey to fail"
    print -u2 "$escape_trigger_output"
    exit 1
}

reserved_ask_output=$(run_with_stub "$TEST_TMP/home3" AI_COMPLETE_ASK_BINDKEY='^C' || true)
[[ "$reserved_ask_output" == *"AI_COMPLETE_ASK_BINDKEY cannot use reserved key sequence ^C."* ]] || {
    print -u2 "expected reserved ask bindkey to fail"
    print -u2 "$reserved_ask_output"
    exit 1
}

duplicate_bindings_output=$(run_with_stub "$TEST_TMP/home4" AI_COMPLETE_TRIGGER_BINDKEY='^T' AI_COMPLETE_ASK_BINDKEY='^T' || true)
[[ "$duplicate_bindings_output" == *"AI_COMPLETE_TRIGGER_BINDKEY and AI_COMPLETE_ASK_BINDKEY must be different."* ]] || {
    print -u2 "expected duplicate custom bindkeys to fail"
    print -u2 "$duplicate_bindings_output"
    exit 1
}

valid_custom_output=$(run_with_stub "$TEST_TMP/home5" AI_COMPLETE_TRIGGER_BINDKEY='^T' AI_COMPLETE_ASK_BINDKEY='^Y')
[[ "$valid_custom_output" == *"Ctrl+T → list suggestions, Ctrl+Y → ask AI"* ]] || {
    print -u2 "expected valid custom bindkeys to appear in startup text"
    print -u2 "$valid_custom_output"
    exit 1
}

print "ok"
