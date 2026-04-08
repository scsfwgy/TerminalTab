#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/curl" <<'EOF'
#!/bin/sh
cat <<'JSON'
{
  "choices": [
    {
      "message": {
        "content": "```bash\n1. ls -la\n- ls -lh\n\nls -la\n  ls -lt  \n• ls -lS\n```\n2) ls -lah\n"
      }
    }
  ]
}
JSON
EOF
chmod +x "$TMP_DIR/curl"

output=$(PATH="$TMP_DIR:$PATH" AI_COMPLETE_API_KEY="test-key" bash "$PROJECT_DIR/ai-suggest" "ls")
expected=$'ls -la\nls -lh\nls -lt\nls -lS\nls -lah'

[[ "$output" == "$expected" ]] || {
    print -u2 "expected cleaned suggestions:"
    print -u2 "$expected"
    print -u2 "got:"
    print -u2 "$output"
    exit 1
}

print "ok"
