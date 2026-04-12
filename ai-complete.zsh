# AI-powered Tab completion for zsh
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
    local script_path
    local -a command_scripts=(
        "$script_dir/ai-command-list.sh"
        "$script_dir/ai-command-generate.sh"
        "$script_dir/ai-command-request.sh"
    )

    if [[ ":$PATH:" != *":$script_dir:"* ]]; then
        export PATH="$script_dir:$PATH"
    fi

    for script_path in "${command_scripts[@]}"; do
        if [[ ! -x "$script_path" && -f "$script_path" ]]; then
            chmod +x "$script_path" 2>/dev/null || true
        fi
    done
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

_ai_menu_lines() {
    local n=${#_AI_SUGGESTIONS}
    local max=${_AI_MAX_ITEMS}
    (( max > n )) && max=$n
    print $(( max + 2 ))
}

_ai_adjust_render_mode_for_space() {
    _AI_RENDER_MODE="multiline"

    local lines_available=${LINES:-0}
    local menu_lines=$(_ai_menu_lines)
    local cursor_row=${_AI_CURSOR_ROW:-0}
    local remaining_lines=$(( lines_available - cursor_row ))
    if (( lines_available > 0 && cursor_row > 0 && remaining_lines <= menu_lines )); then
        _AI_RENDER_MODE="inline"
    fi
}

_ai_parse_cursor_row() {
    local response="$1"
    local payload row column

    [[ "$response" == $'\e['*';'*'R' ]] || return

    payload="${response#$'\e['}"
    row="${payload%%;*}"
    column="${payload#*;}"
    column="${column%R}"

    [[ "$row" == <-> && "$column" == <-> ]] || return
    print -- "$row"
}

_ai_write_cursor_query() {
    local tty_path="$1"
    printf '\e[6n' > "$tty_path"
}

_ai_get_cursor_row() {
    local tty_path="${_AI_TTY_PATH:-/dev/tty}"
    local saved_stty response char row

    saved_stty=$(stty -g < "$tty_path" 2>/dev/null) || {
        print -- ""
        return
    }

    {
        stty -echo -icanon time 1 min 0 < "$tty_path" 2>/dev/null || return
        _ai_write_cursor_query "$tty_path"

        while read -r -k 1 char < "$tty_path" 2>/dev/null; do
            response+="$char"
            [[ "$char" == "R" ]] && break
        done
    } always {
        [[ -n "$saved_stty" ]] && stty "$saved_stty" < "$tty_path" 2>/dev/null
    }

    row=$(_ai_parse_cursor_row "$response")
    print -- "$row"
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

# ── State ─────────────────────────────────────────────────────
_AI_SUGGESTIONS=()
_AI_INDEX=0
_AI_ACTIVE=0
_AI_ORIGINAL=""
_AI_RIGHT=""
_AI_SCROLL=0
_AI_LIST_LINES=0
_AI_CURSOR_ROW=0
_AI_LAST_LINES=0
_AI_RENDER_MODE="${_AI_RENDER_MODE:-multiline}"
_AI_LAST_OUTPUT=""

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

# ── Clamp scroll window ──────────────────────────────────────
_ai_clamp_scroll() {
    (( _AI_INDEX < _AI_SCROLL )) && _AI_SCROLL=$((_AI_INDEX))
    (( _AI_INDEX >= _AI_SCROLL + _AI_MAX_ITEMS )) && _AI_SCROLL=$(( _AI_INDEX - _AI_MAX_ITEMS + 1 ))
    (( _AI_SCROLL < 0 )) && _AI_SCROLL=0
}

# ── Clear rendered menu ───────────────────────────────────────
_ai_clear_menu() {
    if [[ "$_AI_RENDER_MODE" == "inline" ]]; then
        zle -M ""
        _AI_LIST_LINES=0
        return
    fi

    (( _AI_LIST_LINES > 0 )) || return

    local i
    printf '\e7'
    printf '\e[B\r'
    for (( i = 0; i < _AI_LIST_LINES; i++ )); do
        printf '\r\e[2K'
        (( i + 1 < _AI_LIST_LINES )) && printf '\e[B'
    done
    printf '\e8'
    _AI_LIST_LINES=0
}

# ── Reset menu state ──────────────────────────────────────────
_ai_reset_menu() {
    _AI_ACTIVE=0
    _AI_SUGGESTIONS=()
    _AI_INDEX=0
    _AI_SCROLL=0
    _AI_LIST_LINES=0
    _AI_RIGHT=""
}

# ── Detect whether buffer changed since menu opened ───────────
_ai_buffer_changed() {
    [[ "$LBUFFER" != "$_AI_ORIGINAL" || "$RBUFFER" != "$_AI_RIGHT" ]]
}

# ── Render current suggestion inline ──────────────────────────
_ai_show_inline() {
    local n=${#_AI_SUGGESTIONS}
    local item="${_AI_SUGGESTIONS[$(( _AI_INDEX + 1 ))]}"
    zle -M "AI [$(( _AI_INDEX + 1 ))/$n] $item"
    _AI_LIST_LINES=0
}

# ── Render bordered vertical list ────────────────────────────
_ai_show() {
    (( ${#_AI_SUGGESTIONS} > 0 )) || return

    _AI_CURSOR_ROW=$(_ai_get_cursor_row)
    _ai_adjust_render_mode_for_space
    if [[ "$_AI_RENDER_MODE" == "inline" ]]; then
        _ai_show_inline
        return
    fi

    _ai_clamp_scroll

    _ai_clear_menu

    # Let ZLE refresh the command line AFTER old menu is cleared
    zle redisplay

    # DEC save cursor (separate slot from CSI s/u, avoids ZLE conflicts)
    printf '\e7'
    # Move down one line, go to col 0, clear to end of screen
    printf '\e[B\r\e[J'

    local n=${#_AI_SUGGESTIONS}
    local max=${_AI_MAX_ITEMS}
    (( max > n )) && max=$n
    local s=$_AI_SCROLL
    local e=$(( s + max ))
    (( e > n )) && e=$n

    # Max item width
    local w=15 idx ilen
    for (( idx = s; idx < e; idx++ )); do
        ilen=${#_AI_SUGGESTIONS[$(( idx + 1 ))]}
        (( ilen > w )) && w=$ilen
    done
    (( w > 50 )) && w=50

    local inner=$(( w + 5 ))
    local dashes="${(l:$(( inner ))::─:)}"

    # Top border
    local header=" AI"
    (( s > 0 )) && header+=" ▲"
    (( e < n )) && header+=" ▼"
    header+=" "
    local left_dashes="${(l:$(( inner - ${#header} ))::─:)}"
    printf '┌%s%s┐\n' "$header" "$left_dashes"

    # Items
    local item pad
    for (( idx = s; idx < e; idx++ )); do
        item="${_AI_SUGGESTIONS[$(( idx + 1 ))]}"
        pad="${(l:$(( w - ${#item} )):: :)}"
        if (( idx == _AI_INDEX )); then
            printf '│ ❯  %s%s │\n' "$item" "$pad"
        else
            printf '│    %s%s │\n' "$item" "$pad"
        fi
    done

    # Bottom border
    printf '└%s┘' "$dashes"

    _AI_LIST_LINES=$(( e - s + 2 ))  # items + top + bottom

    # DEC restore cursor to command line
    printf '\e8'
}

_ai_show_answer() {
    local text="$1"
    [[ -n "$text" ]] || return

    _ai_clear_menu
    zle redisplay

    # Print answer below command line (question text stays above as history)
    printf '\e[B\r\e[J'
    printf '%s\n' "$text"

    # New empty prompt at current cursor position (after the answer)
    # Do NOT use zle -I here — it causes full screen redraw on some systems
    LBUFFER=""
    RBUFFER=""
    zle reset-prompt
}

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

# ── Ctrl+L: fetch / refresh suggestions ───────────────────
_ai_trigger() {
    local input="${LBUFFER}"
    local config_message

    _ai_history_reset

    [[ -z "${input// /}" ]] && { zle expand-or-complete; return }

    if config_message=$(_ai_missing_config_message); then
        _ai_clear_menu
        _ai_reset_menu
        zle -M "$config_message"
        return
    fi

    if (( _AI_ACTIVE )); then
        _ai_clear_menu
        _ai_reset_menu
    fi

    _AI_ORIGINAL="$input"
    _AI_RIGHT="$RBUFFER"
    _AI_INDEX=0
    _AI_SCROLL=0

    _ai_run_with_spinner ai-command-list.sh "$input"
    local raw="$_AI_LAST_OUTPUT"

    [[ -z "$raw" ]] && { _ai_reset_menu; zle expand-or-complete; return }

    _AI_SUGGESTIONS=("${(@f)raw}")
    (( ${#_AI_SUGGESTIONS} > 0 )) || { _ai_reset_menu; zle expand-or-complete; return }

    _AI_ACTIVE=1
    _ai_show
}

# ── Ctrl+G: ask AI and render answer (g = generate) ──────────
_ai_ask() {
    local input="${LBUFFER}"
    local config_message

    _ai_history_reset
    [[ -z "${input// /}" ]] && return

    if config_message=$(_ai_missing_config_message); then
        _ai_clear_menu
        _ai_reset_menu
        zle -M "$config_message"
        return
    fi

    if (( _AI_ACTIVE )); then
        _ai_clear_menu
        _ai_reset_menu
    fi

    _ai_run_with_spinner ai-command-generate.sh "$input"
    local answer="$_AI_LAST_OUTPUT"

    _ai_show_answer "${answer:-no response}"
}

# ── History previous suggestion ───────────────────────────────
_ai_history_prev() {
    if (( _AI_ACTIVE )); then
        _ai_up
        return
    fi
    _ai_history_prev_handler
}

# ── Down arrow: next suggestion ──────────────────────────────
_ai_down() {
    if (( _AI_ACTIVE && ${#_AI_SUGGESTIONS} > 0 )); then
        _AI_INDEX=$(( (_AI_INDEX + 1) % ${#_AI_SUGGESTIONS} ))
        _ai_show
    else
        zle down-line-or-history
    fi
}

# ── History next suggestion ──────────────────────────────────
_ai_history_next() {
    if (( _AI_ACTIVE )); then
        _ai_down
        return
    fi
    _ai_history_next_handler
}

# ── Up arrow: previous suggestion ────────────────────────────
_ai_up() {
    if (( _AI_ACTIVE && ${#_AI_SUGGESTIONS} > 0 )); then
        _AI_INDEX=$(( (_AI_INDEX - 1 + ${#_AI_SUGGESTIONS}) % ${#_AI_SUGGESTIONS} ))
        _ai_show
    else
        zle up-line-or-history
    fi
}

# ── Enter: accept or execute ─────────────────────────────────
_ai_enter() {
    if (( _AI_ACTIVE && ${#_AI_SUGGESTIONS} > 0 )); then
        _ai_clear_menu
        _ai_history_reset
        LBUFFER="${_AI_SUGGESTIONS[$(( _AI_INDEX + 1 ))]}"
        RBUFFER="$_AI_RIGHT"
        _ai_reset_menu
        zle redisplay
        return
    fi
    if _ai_history_accept; then
        return
    fi
    zle accept-line
}

# ── Ctrl+C: cancel menu ──────────────────────────────────────
_ai_cancel() {
    if (( _AI_ACTIVE )); then
        _ai_clear_menu
        _ai_history_reset
        LBUFFER="$_AI_ORIGINAL"
        RBUFFER="$_AI_RIGHT"
        _ai_reset_menu
        zle redisplay
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
