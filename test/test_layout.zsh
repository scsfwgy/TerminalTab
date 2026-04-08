#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}

for file in \
    test_navigation_buffer.zsh \
    test_ai_suggest_cleanup.zsh \
    test_shift_tab_binding.zsh \
    test_trigger_rename.zsh \
    test_runner_smoke.zsh
 do
    [[ -f "$PROJECT_DIR/test/$file" ]] || {
        print -u2 "expected $file to live under test/"
        exit 1
    }

    [[ ! -f "$PROJECT_DIR/$file" ]] || {
        print -u2 "expected root-level $file to be removed"
        exit 1
    }
done

print "ok"
