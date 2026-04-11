#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
PROMPT_DIR="$PROJECT_DIR/prompts"

cat > "$TMP_DIR/curl" <<'EOF'
#!/bin/sh
body='{
  "choices": [
    {
      "message": {
        "content": "Here is the answer.\n- keep this bullet\n\nUse grep -R foo ."
      }
    }
  ]
}'
outfile=""
writeout=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      outfile="$2"
      shift 2
      ;;
    -w)
      writeout="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s' "$body" > "$outfile"
printf '%s' "${writeout//%\{http_code\}/200}"
EOF
chmod +x "$TMP_DIR/curl"

output=$(PATH="$TMP_DIR:$PATH" AI_COMPLETE_API_URL="https://example.com/v1/chat/completions" AI_COMPLETE_MODEL="test-model" AI_COMPLETE_API_KEY="test-key" bash "$PROJECT_DIR/ai-suggest.sh" --ask "why did grep fail")
expected=$'Here is the answer.\n- keep this bullet\n\nUse grep -R foo .'

[[ "$output" == "$expected" ]] || {
    print -u2 "expected plain assistant response:"
    print -u2 "$expected"
    print -u2 "got:"
    print -u2 "$output"
    exit 1
}

cat > "$TMP_DIR/curl" <<'EOF'
#!/bin/sh
body='{
  "error": {
    "message": "invalid_api_key"
  }
}'
outfile=""
writeout=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      outfile="$2"
      shift 2
      ;;
    -w)
      writeout="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s' "$body" > "$outfile"
printf '%s' "${writeout//%\{http_code\}/401}"
EOF
chmod +x "$TMP_DIR/curl"

error_output=$(PATH="$TMP_DIR:$PATH" AI_COMPLETE_API_URL="https://example.com/v1/chat/completions" AI_COMPLETE_MODEL="test-model" AI_COMPLETE_API_KEY="test-key" bash "$PROJECT_DIR/ai-suggest.sh" --ask "bash和zsh的区别？")
error_expected='invalid_api_key'

[[ "$error_output" == "$error_expected" ]] || {
    print -u2 "expected API error message:"
    print -u2 "$error_expected"
    print -u2 "got:"
    print -u2 "$error_output"
    exit 1
}

cat > "$TMP_DIR/curl" <<'EOF'
#!/bin/sh
outfile=""
writeout=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      outfile="$2"
      shift 2
      ;;
    -w)
      writeout="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
: > "$outfile"
printf '%s' "${writeout//%\{http_code\}/200}"
EOF
chmod +x "$TMP_DIR/curl"

empty_output=$(PATH="$TMP_DIR:$PATH" AI_COMPLETE_API_URL="https://example.com/v1/chat/completions" AI_COMPLETE_MODEL="test-model" AI_COMPLETE_API_KEY="test-key" bash "$PROJECT_DIR/ai-suggest.sh" --ask "bash和zsh的区别？")
empty_expected='no response'

[[ "$empty_output" == "$empty_expected" ]] || {
    print -u2 "expected empty-response warning:"
    print -u2 "$empty_expected"
    print -u2 "got:"
    print -u2 "$empty_output"
    exit 1
}

prompt_missing_output=$(PATH="$TMP_DIR:$PATH" AI_COMPLETE_API_URL="https://example.com/v1/chat/completions" AI_COMPLETE_MODEL="test-model" AI_COMPLETE_API_KEY="test-key" AI_COMPLETE_PROMPT_DIR="$TMP_DIR/missing-prompts" bash "$PROJECT_DIR/ai-suggest.sh" --ask "why did grep fail")
[[ "$prompt_missing_output" == *"Prompt file not found:"* ]] || {
    print -u2 "expected missing prompt file error"
    print -u2 "$prompt_missing_output"
    exit 1
}

ask_prompt_template=$(<"$PROMPT_DIR/ask.prompt")
[[ "$ask_prompt_template" == *'{{INPUT}}'* ]] || {
    print -u2 "expected ask.prompt to contain {{INPUT}} placeholder"
    print -u2 "$ask_prompt_template"
    exit 1
}

print "ok"
