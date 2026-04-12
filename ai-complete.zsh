# AI-powered Tab completion for zsh — entry point
#
# Default shortcuts:
#   Ctrl+L → fetch / refresh suggestions (l = list)
#   Ctrl+G → ask AI (g = generate)
#   Ctrl+U → previous history suggestion
#   Ctrl+N → next history suggestion
#   Up/Down → navigate AI suggestions
#   Enter   → accept suggestion (press Enter again to execute)
#   Ctrl+C  → cancel menu, restore original input
#
# Config:
#   export AI_COMPLETE_API_KEY="sk-..."                  (required)
#   export AI_COMPLETE_MAX_ITEMS=5                       (optional, default 5)
#   export AI_COMPLETE_MODEL="gpt-4o-mini"             (optional)
#   export AI_COMPLETE_API_TYPE="openai"               (optional: openai or claude)
#   export AI_COMPLETE_TRIGGER_BINDKEY='^L'             (optional, default Ctrl+L)
#   export AI_COMPLETE_ASK_BINDKEY='^G'                 (optional, default Ctrl+G)
#   export AI_COMPLETE_HISTORY_PREV_BINDKEY='^U'        (optional, default Ctrl+U)
#   export AI_COMPLETE_HISTORY_NEXT_BINDKEY='^N'        (optional, default Ctrl+N)
#
# Dependencies: jq, curl, zsh-autosuggestions

# ── Setup ─────────────────────────────────────────────────────
_ai_script_dir() {
    print -- "${${(%):-%N}:A:h}"
}

_ai_setup() {
    local script_dir
    script_dir=$(_ai_script_dir)

    if [[ ":$PATH:" != *":$script_dir:"* ]]; then
        export PATH="$script_dir:$PATH"
    fi

    local request_script="$script_dir/ai-command-request.sh"
    if [[ ! -x "$request_script" && -f "$request_script" ]]; then
        chmod +x "$request_script" 2>/dev/null || true
    fi
}

_ai_is_official_autosuggestions_loaded() {
    (( ${+functions[_zsh_autosuggest_start]} ))
}

_ai_vendor_autosuggestions_path() {
    if [[ -n "${AI_COMPLETE_AUTOSUGGESTIONS_PATH:-}" ]]; then
        print -- "$AI_COMPLETE_AUTOSUGGESTIONS_PATH"
        return 0
    fi

    local script_dir
    script_dir=$(_ai_script_dir)
    print -- "$script_dir/vendor/zsh-autosuggestions/zsh-autosuggestions.zsh"
}

_ai_find_official_autosuggestions() {
    local -a candidates=()
    local brew_prefix="${HOMEBREW_PREFIX:-}"
    local vendor_path
    vendor_path=$(_ai_vendor_autosuggestions_path)

    [[ -n "$vendor_path" ]] && candidates+=("$vendor_path")

    if [[ -z "$brew_prefix" ]] && command -v brew >/dev/null 2>&1; then
        brew_prefix=$(brew --prefix 2>/dev/null)
    fi

    [[ -n "$brew_prefix" ]] && candidates+=(
        "$brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    )

    [[ -n "${ZSH_CUSTOM:-}" ]] && candidates+=(
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
    )

    [[ -n "${ZSH:-}" ]] && candidates+=(
        "$ZSH/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
    )

    candidates+=(
        "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
        "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        [[ -f "$candidate" ]] || continue
        print -- "$candidate"
        return 0
    done

    return 1
}

_ai_print_autosuggestions_install_help() {
    local vendor_path
    vendor_path=$(_ai_vendor_autosuggestions_path)
    print -u2 -- "TerminalTab requires zsh-users/zsh-autosuggestions."
    print -u2 -- "Choose one of the following:"
    print -u2 -- "  1) Install with Homebrew: brew install zsh-autosuggestions"
    print -u2 -- "  2) Auto-download to: $vendor_path"
    print -u2 -- "Repository: https://github.com/zsh-users/zsh-autosuggestions"
}

_ai_prompt_autosuggestions_install() {
    [[ -o interactive ]] || return 1
    [[ -r /dev/tty && -w /dev/tty ]] || return 1

    local tty_path=/dev/tty
    local choice

    printf '%s\n' "TerminalTab could not find zsh-autosuggestions." > "$tty_path"
    printf '%s\n' "[1] Auto-download now" > "$tty_path"
    printf '%s\n' "[2] I'll install it manually" > "$tty_path"
    printf '%s\n' "Enter 1 or 2, then press Enter:" > "$tty_path"
    if ! read -r choice < "$tty_path"; then
        return 1
    fi

    [[ "$choice" == '1' ]]
}

_ai_download_official_autosuggestions() {
    command -v git >/dev/null 2>&1 || {
        print -u2 -- "TerminalTab cannot auto-download zsh-autosuggestions because git is not installed."
        return 1
    }

    local plugin_dir plugin_path
    plugin_path=$(_ai_vendor_autosuggestions_path)
    plugin_dir="${plugin_path:h}"

    mkdir -p "$plugin_dir" || {
        print -u2 -- "TerminalTab could not create autosuggestions directory: $plugin_dir"
        return 1
    }

    if [[ -f "$plugin_path" ]]; then
        print -- "$plugin_path"
        return 0
    fi

    git clone https://github.com/zsh-users/zsh-autosuggestions.git "$plugin_dir" >/dev/null 2>&1 || {
        print -u2 -- "TerminalTab failed to download zsh-autosuggestions into: $plugin_dir"
        return 1
    }

    [[ -f "$plugin_path" ]] || {
        print -u2 -- "TerminalTab downloaded zsh-autosuggestions but did not find: $plugin_path"
        return 1
    }

    print -- "$plugin_path"
}

_ai_require_official_autosuggestions() {
    _ai_is_official_autosuggestions_loaded && return 0

    local plugin_path
    plugin_path=$(_ai_find_official_autosuggestions)

    if [[ -z "$plugin_path" ]]; then
        if _ai_prompt_autosuggestions_install; then
            plugin_path=$(_ai_download_official_autosuggestions) || {
                _ai_print_autosuggestions_install_help
                return 1
            }
        else
            _ai_print_autosuggestions_install_help
            return 1
        fi
    fi

    source "$plugin_path" || {
        print -u2 -- "TerminalTab found zsh-autosuggestions at: $plugin_path"
        print -u2 -- "but failed to source it. Please load zsh-autosuggestions before TerminalTab."
        return 1
    }

    _ai_is_official_autosuggestions_loaded && return 0

    print -u2 -- "TerminalTab sourced zsh-autosuggestions from: $plugin_path"
    print -u2 -- "but the plugin did not finish loading correctly. Please verify your zsh-autosuggestions installation."
    return 1
}

_ai_loading_frames() {
    :
}

_ai_setup_render_mode() {
    _AI_RENDER_MODE="multiline"
}

_ai_setup
_ai_require_official_autosuggestions || return 1
_ai_setup_render_mode
_ai_loading_frames

# ── Config ────────────────────────────────────────────────────
_AI_MAX_ITEMS=${AI_COMPLETE_MAX_ITEMS:-5}
if ! [[ "$_AI_MAX_ITEMS" == <-> ]] || (( _AI_MAX_ITEMS <= 0 )); then
    _AI_MAX_ITEMS=5
fi

_AI_TRIGGER_BINDKEY_DEFAULT='^L'
_AI_ASK_BINDKEY_DEFAULT='^G'
_AI_HISTORY_PREV_BINDKEY_DEFAULT='^U'
_AI_HISTORY_NEXT_BINDKEY_DEFAULT='^N'
_AI_RESERVED_BINDKEYS=($'\e' '\e[A' '\e[B' '\eOA' '\eOB' '^M' '^J' '^C')

_ai_fail_config() {
    print -u2 -- "$1"
    return 1 2>/dev/null || exit 1
}

_ai_bindkey_label() {
    local key="$1"
    if [[ "$key" == '^?' ]]; then
        print -- 'Ctrl+?'
    elif [[ "$key" == '^'[[:alpha:]] ]]; then
        print -- "Ctrl+${key[2]}"
    else
        print -- "$key"
    fi
}

_ai_validate_custom_bindkey() {
    local env_name="$1"
    local key="$2"
    local reserved

    [[ -n "$key" ]] || { _ai_fail_config "$env_name cannot be empty. Use zsh bindkey syntax like '^L'."; return 1; }
    [[ "$key" != $'\e' ]] || { _ai_fail_config "$env_name does not support bare Escape (\\e) because it conflicts with arrow-key sequences."; return 1; }

    for reserved in "${_AI_RESERVED_BINDKEYS[@]}"; do
        [[ "$key" != "$reserved" ]] || { _ai_fail_config "$env_name cannot use reserved key sequence $key."; return 1; }
    done
}

_ai_setup_bindkeys() {
    if [[ -n "${AI_COMPLETE_TRIGGER_BINDKEY+x}" ]]; then
        _AI_TRIGGER_BINDKEY=${AI_COMPLETE_TRIGGER_BINDKEY}
        _ai_validate_custom_bindkey "AI_COMPLETE_TRIGGER_BINDKEY" "$_AI_TRIGGER_BINDKEY" || return 1
    else
        _AI_TRIGGER_BINDKEY=$_AI_TRIGGER_BINDKEY_DEFAULT
    fi

    if [[ -n "${AI_COMPLETE_ASK_BINDKEY+x}" ]]; then
        _AI_ASK_BINDKEY=${AI_COMPLETE_ASK_BINDKEY}
        _ai_validate_custom_bindkey "AI_COMPLETE_ASK_BINDKEY" "$_AI_ASK_BINDKEY" || return 1
    else
        _AI_ASK_BINDKEY=$_AI_ASK_BINDKEY_DEFAULT
    fi

    if [[ -n "${AI_COMPLETE_HISTORY_PREV_BINDKEY+x}" ]]; then
        _AI_HISTORY_PREV_BINDKEY=${AI_COMPLETE_HISTORY_PREV_BINDKEY}
        _ai_validate_custom_bindkey "AI_COMPLETE_HISTORY_PREV_BINDKEY" "$_AI_HISTORY_PREV_BINDKEY" || return 1
    else
        _AI_HISTORY_PREV_BINDKEY=$_AI_HISTORY_PREV_BINDKEY_DEFAULT
    fi

    if [[ -n "${AI_COMPLETE_HISTORY_NEXT_BINDKEY+x}" ]]; then
        _AI_HISTORY_NEXT_BINDKEY=${AI_COMPLETE_HISTORY_NEXT_BINDKEY}
        _ai_validate_custom_bindkey "AI_COMPLETE_HISTORY_NEXT_BINDKEY" "$_AI_HISTORY_NEXT_BINDKEY" || return 1
    else
        _AI_HISTORY_NEXT_BINDKEY=$_AI_HISTORY_NEXT_BINDKEY_DEFAULT
    fi

    [[ "$_AI_TRIGGER_BINDKEY" != "$_AI_ASK_BINDKEY" ]] || _ai_fail_config "AI_COMPLETE_TRIGGER_BINDKEY and AI_COMPLETE_ASK_BINDKEY must be different."
    [[ "$_AI_TRIGGER_BINDKEY" != "$_AI_HISTORY_PREV_BINDKEY" ]] || _ai_fail_config "AI_COMPLETE_TRIGGER_BINDKEY and AI_COMPLETE_HISTORY_PREV_BINDKEY must be different."
    [[ "$_AI_TRIGGER_BINDKEY" != "$_AI_HISTORY_NEXT_BINDKEY" ]] || _ai_fail_config "AI_COMPLETE_TRIGGER_BINDKEY and AI_COMPLETE_HISTORY_NEXT_BINDKEY must be different."
    [[ "$_AI_ASK_BINDKEY" != "$_AI_HISTORY_PREV_BINDKEY" ]] || _ai_fail_config "AI_COMPLETE_ASK_BINDKEY and AI_COMPLETE_HISTORY_PREV_BINDKEY must be different."
    [[ "$_AI_ASK_BINDKEY" != "$_AI_HISTORY_NEXT_BINDKEY" ]] || _ai_fail_config "AI_COMPLETE_ASK_BINDKEY and AI_COMPLETE_HISTORY_NEXT_BINDKEY must be different."
    [[ "$_AI_HISTORY_PREV_BINDKEY" != "$_AI_HISTORY_NEXT_BINDKEY" ]] || _ai_fail_config "AI_COMPLETE_HISTORY_PREV_BINDKEY and AI_COMPLETE_HISTORY_NEXT_BINDKEY must be different."

    _AI_TRIGGER_BINDKEY_LABEL=$(_ai_bindkey_label "$_AI_TRIGGER_BINDKEY")
    _AI_ASK_BINDKEY_LABEL=$(_ai_bindkey_label "$_AI_ASK_BINDKEY")
    _AI_HISTORY_PREV_BINDKEY_LABEL=$(_ai_bindkey_label "$_AI_HISTORY_PREV_BINDKEY")
    _AI_HISTORY_NEXT_BINDKEY_LABEL=$(_ai_bindkey_label "$_AI_HISTORY_NEXT_BINDKEY")
}

_ai_setup_bindkeys || return 1

# ── Shared state ──────────────────────────────────────────────
_AI_LAST_OUTPUT=""

# ── History default handlers (overridden by enhance.sh) ──────
_ai_history_prev_handler() {
    zle kill-line
}

_ai_history_next_handler() {
    zle down-line-or-history
}

_ai_history_reset() {
    return 0
}

_ai_history_accept() {
    return 1
}

_ai_history_cancel() {
    return 1
}

# ── Shared helpers ────────────────────────────────────────────
_ai_missing_config_message() {
    local missing=()

    [[ -n "${AI_COMPLETE_API_URL:-}" ]] || missing+=("AI_COMPLETE_API_URL")
    [[ -n "${AI_COMPLETE_MODEL:-}" ]] || missing+=("AI_COMPLETE_MODEL")
    [[ -n "${AI_COMPLETE_API_KEY:-}" ]] || missing+=("AI_COMPLETE_API_KEY")

    (( ${#missing[@]} == 0 )) && return 1

    local message="AI Complete not configured"
    local name
    for name in "${missing[@]}"; do
        message+="\n- $name"
    done

    printf '%s' "$message"
    return 0
}

_ai_run_with_spinner() {
    local tmpf; tmpf=$(mktemp)
    { "$@" > "$tmpf" } 2>/dev/null &!
    local bg_pid=$!

    POSTDISPLAY=" AI generating..."
    zle redisplay

    while kill -0 "$bg_pid" 2>/dev/null; do
        sleep 0.2
    done

    _AI_LAST_OUTPUT=$(cat "$tmpf" 2>/dev/null)
    rm -f "$tmpf"
    if [[ -n "$POSTDISPLAY" ]]; then
        POSTDISPLAY=""
        zle redisplay
    fi
}

# ── Source core modules ───────────────────────────────────────
_AI_SOURCE_DIR=$(_ai_script_dir)
source "$_AI_SOURCE_DIR/ai-suggest.zsh"
source "$_AI_SOURCE_DIR/ai-generate.zsh"

# ── Dispatch widgets ─────────────────────────────────────────
_ai_history_prev() {
    if (( _AI_ACTIVE )); then
        _ai_suggest_up
        return
    fi
    _ai_history_prev_handler
}

_ai_history_next() {
    if (( _AI_ACTIVE )); then
        _ai_suggest_down
        return
    fi
    _ai_history_next_handler
}

_ai_up() {
    if (( _AI_ACTIVE )); then
        _ai_suggest_up
    else
        zle up-line-or-history
    fi
}

_ai_down() {
    if (( _AI_ACTIVE )); then
        _ai_suggest_down
    else
        zle down-line-or-history
    fi
}

_ai_enter() {
    if (( _AI_ACTIVE )); then
        _ai_suggest_accept
        return
    fi
    if _ai_history_accept; then
        return
    fi
    zle accept-line
}

_ai_cancel() {
    if (( _AI_ACTIVE )); then
        _ai_suggest_cancel
    elif _ai_history_cancel; then
        return
    else
        zle send-break
    fi
}

# ── Register widgets ──────────────────────────────────────────
zle -N ai-trigger _ai_trigger
zle -N ai-ask _ai_ask
zle -N ai-history-prev _ai_history_prev
zle -N ai-history-next _ai_history_next
zle -N ai-down   _ai_down
zle -N ai-up     _ai_up
zle -N ai-enter  _ai_enter
zle -N ai-cancel _ai_cancel

# ── Key bindings ──────────────────────────────────────────────
bindkey "$_AI_TRIGGER_BINDKEY" ai-trigger        # configurable trigger binding
bindkey "$_AI_ASK_BINDKEY" ai-ask                # configurable ask binding
bindkey "$_AI_HISTORY_PREV_BINDKEY" ai-history-prev  # configurable history previous binding
bindkey "$_AI_HISTORY_NEXT_BINDKEY" ai-history-next  # configurable history next binding
bindkey '\e[A' ai-up        # Up arrow
bindkey '\e[B' ai-down      # Down arrow
bindkey '\eOA' ai-up        # Up arrow (alt)
bindkey '\eOB' ai-down      # Down arrow (alt)
bindkey '^M'   ai-enter     # Enter
bindkey '^J'   ai-enter     # Enter (LF)
bindkey '^C'   ai-cancel    # Ctrl+C to cancel

_ai_bind_widget_key() {
    local key="$1"
    local widget="$2"

    bindkey "$key" "$widget" 2>/dev/null || true
    bindkey -M emacs "$key" "$widget" 2>/dev/null || true
    bindkey -M viins "$key" "$widget" 2>/dev/null || true
}

_ai_bind_widget_key "$_AI_TRIGGER_BINDKEY" ai-trigger
_ai_bind_widget_key "$_AI_ASK_BINDKEY" ai-ask
_ai_bind_widget_key "$_AI_HISTORY_PREV_BINDKEY" ai-history-prev
_ai_bind_widget_key "$_AI_HISTORY_NEXT_BINDKEY" ai-history-next
_ai_bind_widget_key '\e[A' ai-up
_ai_bind_widget_key '\e[B' ai-down
_ai_bind_widget_key '\eOA' ai-up
_ai_bind_widget_key '\eOB' ai-down
_ai_bind_widget_key '^M' ai-enter
_ai_bind_widget_key '^J' ai-enter
_ai_bind_widget_key '^C' ai-cancel

# ── History enhancement ───────────────────────────────────────
_ai_load_history_enhancement() {
    local script_dir
    script_dir=$(_ai_script_dir)
    local enhance_script="$script_dir/zsh-autosuggestions-enhance.sh"

    [[ -f "$enhance_script" ]] || return 0
    source "$enhance_script"
}

_ai_load_history_enhancement || return 1

# ── Init ──────────────────────────────────────────────────────
echo "AI command completion loaded. ${_AI_TRIGGER_BINDKEY_LABEL} → list suggestions, ${_AI_ASK_BINDKEY_LABEL} → ask AI, ${_AI_HISTORY_PREV_BINDKEY_LABEL}/${_AI_HISTORY_NEXT_BINDKEY_LABEL} → cycle history, ↑↓ → navigate, Enter → accept."
