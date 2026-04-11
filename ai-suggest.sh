#!/bin/bash
# AI-powered command suggestion engine
# Usage: ai-suggest.sh [--ask] "user typed text"
# Output:
#   suggest mode → newline-separated COMPLETE command suggestions
#   ask mode     → plain assistant response

set -o pipefail

MODE="suggest"
if [[ "${1:-}" == "--ask" ]]; then
    MODE="ask"
    shift
fi

INPUT="$*"

if [[ -z "$INPUT" ]]; then
    exit 0
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_DIR="${AI_COMPLETE_PROMPT_DIR:-$SCRIPT_DIR/prompts}"

# ── Config (set in .zshrc / .bashrc) ──────────────────────────
# AI_COMPLETE_API_TYPE    - API protocol: "openai" or "claude" (default: openai)
# AI_COMPLETE_API_URL     - API endpoint (required)
# AI_COMPLETE_API_KEY     - Your API key (required)
# AI_COMPLETE_MODEL       - Model name (required)
# AI_COMPLETE_TIMEOUT     - Timeout in seconds (default: 15)
# AI_COMPLETE_PROMPT_DIR  - Prompt directory (optional, default: prompts next to ai-suggest.sh)
# ──────────────────────────────────────────────────────────────

API_TYPE="${AI_COMPLETE_API_TYPE:-openai}"
API_URL="${AI_COMPLETE_API_URL:-}"
API_KEY="${AI_COMPLETE_API_KEY:-}"
MODEL="${AI_COMPLETE_MODEL:-}"
TIMEOUT="${AI_COMPLETE_TIMEOUT:-15}"

print_config_error() {
    local missing=()

    [[ -n "$API_URL" ]] || missing+=("AI_COMPLETE_API_URL")
    [[ -n "$MODEL" ]] || missing+=("AI_COMPLETE_MODEL")
    [[ -n "$API_KEY" ]] || missing+=("AI_COMPLETE_API_KEY")

    (( ${#missing[@]} == 0 )) && return 0

    printf 'AI Complete is not configured. Missing required environment variables:\n'
    local name
    for name in "${missing[@]}"; do
        printf -- '- %s\n' "$name"
    done

    printf '\nAdd the missing exports to your shell config, for example:\n\n'
    printf '%s\n' '# OpenAI-compatible API'
    printf '%s\n' 'export AI_COMPLETE_API_URL="https://api.openai.com/v1/chat/completions"'
    printf '%s\n' 'export AI_COMPLETE_MODEL="gpt-4o-mini"'
    printf '%s\n' 'export AI_COMPLETE_API_KEY="sk-..."'
    printf '\n'
    printf '%s\n' '# Claude API'
    printf '%s\n' 'export AI_COMPLETE_API_TYPE="claude"'
    printf '%s\n' 'export AI_COMPLETE_API_URL="https://api.anthropic.com/v1/messages"'
    printf '%s\n' 'export AI_COMPLETE_MODEL="claude-sonnet-4-5"'
    printf '%s\n' 'export AI_COMPLETE_API_KEY="sk-ant-..."'
    exit 0
}

load_prompt() {
    local prompt_name prompt_path prompt_content sanitized_input

    if [[ "$MODE" == "ask" ]]; then
        prompt_name="ask.prompt"
    else
        prompt_name="suggest.prompt"
    fi

    prompt_path="$PROMPT_DIR/$prompt_name"
    if [[ ! -f "$prompt_path" ]]; then
        printf 'Prompt file not found: %s\n' "$prompt_path"
        return 1
    fi

    prompt_content=$(<"$prompt_path") || {
        printf 'Failed to read prompt file: %s\n' "$prompt_path"
        return 1
    }

    sanitized_input=${INPUT//\{\{INPUT\}\}/}
    PROMPT=${prompt_content//\{\{INPUT\}\}/$sanitized_input}
}

print_config_error
load_prompt || exit 0

extract_api_error() {
    local response="$1"
    local api_error

    api_error=$(printf '%s' "$response" | jq -r '
        .error.message //
        .error //
        .message //
        .detail //
        .details //
        .title //
        (.errors[0].message // empty) //
        (.errors[0] // empty)
    ' 2>/dev/null) || true

    [[ "$api_error" == "null" ]] && api_error=""
    printf '%s' "$api_error"
}

extract_response_content() {
    local response="$1"
    local content

    if [[ "$API_TYPE" == "claude" ]]; then
        content=$(printf '%s' "$response" | jq -r '.content[0].text // empty' 2>/dev/null) || true
    else
        content=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null) || true
    fi

    [[ "$content" == "null" ]] && content=""
    printf '%s' "$content"
}

response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

# Call LLM API
if [[ "$API_TYPE" == "claude" ]]; then
    http_code=$(curl -sS --max-time "$TIMEOUT" -o "$response_file" -w '%{http_code}' "$API_URL" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --arg prompt "$PROMPT" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                max_tokens: 300
            }')" 2>/dev/null) || {
        printf '%s\n' "API request failed (timeout or network error)"
        exit 0
    }
else
    http_code=$(curl -sS --max-time "$TIMEOUT" -o "$response_file" -w '%{http_code}' "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --arg prompt "$PROMPT" \
            '{
                model: $model,
                messages: [{"role": "user", "content": $prompt}],
                temperature: 0.3,
                max_tokens: 300
            }')" 2>/dev/null) || {
        printf '%s\n' "API request failed (timeout or network error)"
        exit 0
    }
fi

response=$(cat "$response_file" 2>/dev/null)
content=$(extract_response_content "$response")
api_error=$(extract_api_error "$response")

# Prefer explicit model/API errors when present
if [[ -n "$api_error" ]]; then
    printf '%s\n' "$api_error"
    exit 0
fi

# If HTTP failed but body had no parseable message, still show the status directly
if [[ "$http_code" != "000" && "$http_code" -ge 400 ]] 2>/dev/null; then
    if [[ -n "$response" ]]; then
        printf '%s\n' "$response"
    else
        printf 'API request failed with HTTP %s\n' "$http_code"
    fi
    exit 0
fi

# If parsed content is empty, fall back to raw response
[[ -n "$content" ]] || content="$response"

# If still empty, return fixed message
if [[ -z "$content" ]]; then
    printf 'no response\n'
    exit 0
fi

if [[ "$MODE" == "ask" ]]; then
    printf '%s\n' "$content"
    exit 0
fi

# Extract and clean suggestions
output=$(printf '%s' "$content" | awk '
    BEGIN { count = 0 }
    {
        gsub(/\r/, "")
        sub(/^[[:space:]]+/, "")
        sub(/[[:space:]]+$/, "")
        if ($0 == "" || $0 ~ /^```/) next
        sub(/^[0-9]+[.)][[:space:]]+/, "")
        sub(/^[-*•][[:space:]]+/, "")
        sub(/^[[:space:]]+/, "")
        sub(/[[:space:]]+$/, "")
        if ($0 == "" || seen[$0]++) next
        print
        count++
        if (count >= 8) exit
    }
')

# If awk cleaned to nothing, show raw content as fallback
if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
else
    printf '%s\n' "$content"
fi
