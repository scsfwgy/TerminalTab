#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
RUNNER="$PROJECT_DIR/test.sh"

output=$("$RUNNER" 2>&1)
exit_code=$?

if (( exit_code != 0 )); then
    print -u2 "expected test runner to succeed, got exit code $exit_code"
    print -u2 "$output"
    exit 1
fi

[[ "$output" == *"navigation buffer regression: ok"* ]] || {
    print -u2 "expected runner output to include navigation buffer regression result"
    print -u2 "$output"
    exit 1
}

[[ "$output" == *"trigger rename regression: ok"* ]] || {
    print -u2 "expected runner output to include trigger rename regression result"
    print -u2 "$output"
    exit 1
}

print "ok"
