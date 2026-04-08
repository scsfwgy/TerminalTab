#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
TEST_DIR="$ROOT_DIR/test"

run_test() {
    local name="$1"
    local script="$2"

    zsh "$script" >/dev/null
    print "$name: ok"
}

run_test "test folder layout regression" "$TEST_DIR/test_layout.zsh"
run_test "navigation buffer regression" "$TEST_DIR/test_navigation_buffer.zsh"
run_test "ai-suggest cleanup regression" "$TEST_DIR/test_ai_suggest_cleanup.zsh"
run_test "shift+tab binding regression" "$TEST_DIR/test_shift_tab_binding.zsh"
run_test "trigger rename regression" "$TEST_DIR/test_trigger_rename.zsh"
