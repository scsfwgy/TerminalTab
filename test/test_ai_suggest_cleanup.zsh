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
        "content": "```bash\n1. ls -la\n- ls -lh\n\nls -la\n  ls -lt  \n• ls -lS\n```\n2) ls -lah\n"
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

output=$(PATH="$TMP_DIR:$PATH" AI_COMPLETE_API_URL="https://example.com/v1/chat/completions" AI_COMPLETE_MODEL="test-model" AI_COMPLETE_API_KEY="test-key" bash "$PROJECT_DIR/ai-command-list.sh" "ls")
expected=$'ls -la\nls -lh\nls -lt\nls -lS\nls -lah'

[[ "$output" == "$expected" ]] || {
    print -u2 "expected cleaned suggestions:"
    print -u2 "$expected"
    print -u2 "got:"
    print -u2 "$output"
    exit 1
}

suggest_prompt_template=$(<"$PROMPT_DIR/suggest.prompt")
[[ "$suggest_prompt_template" == *'{{INPUT}}'* ]] || {
    print -u2 "expected suggest.prompt to contain {{INPUT}} placeholder"
    print -u2 "$suggest_prompt_template"
    exit 1
}

print "ok"
