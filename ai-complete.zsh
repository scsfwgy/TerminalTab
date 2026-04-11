# AI-powered Tab completion for zsh
#
# Ctrl+L → fetch / refresh suggestions (l = list)
# Ctrl+G → ask AI (g = generate)
# Up/Down  → navigate suggestions
# Enter    → accept suggestion (press Enter again to execute)
# Ctrl+C   → cancel menu, restore original input
#
# Config:
#   export AI_COMPLETE_API_KEY="sk-..."          (required)
#   export AI_COMPLETE_MAX_ITEMS=5               (optional, default 5)
#   export AI_COMPLETE_MODEL="gpt-4o-mini"       (optional)
#   export AI_COMPLETE_API_TYPE="openai"         (optional: openai or claude)
#
# Dependencies: jq, curl

# ── Setup ─────────────────────────────────────────────────────
_ai_setup() {
    local script_dir="${0:A:h}"
    local suggest_script="$script_dir/ai-suggest.sh"
    if [[ ":$PATH:" != *":$script_dir:"* ]]; then
        export PATH="$script_dir:$PATH"
    fi
    if [[ ! -x "$suggest_script" && -f "$suggest_script" ]]; then
        chmod +x "$suggest_script" 2>/dev/null || true
    fi
}

_ai_loading_frames() {
    _AI_LOADING_FRAMES=('|' '/' '-' '\\')
    _AI_LOADING_INTERVAL=0.2
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
_ai_setup_render_mode
_ai_loading_frames

# ── Config ────────────────────────────────────────────────────
_AI_MAX_ITEMS=${AI_COMPLETE_MAX_ITEMS:-5}
if ! [[ "$_AI_MAX_ITEMS" == <-> ]] || (( _AI_MAX_ITEMS <= 0 )); then
    _AI_MAX_ITEMS=5
fi

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

    local frames=(${_AI_LOADING_FRAMES[@]})
    local frame_count=${#frames}
    local si=0

    while kill -0 "$bg_pid" 2>/dev/null; do
        local next_postdisplay=" ${frames[$(( si % frame_count + 1 ))]}"
        if [[ "$POSTDISPLAY" != "$next_postdisplay" ]]; then
            POSTDISPLAY="$next_postdisplay"
            zle redisplay
        fi
        si=$(( si + 1 ))
        sleep "${_AI_LOADING_INTERVAL}"
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

    _ai_run_with_spinner ai-suggest.sh "$input"
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

    _ai_run_with_spinner ai-suggest.sh --ask "$input"
    local answer="$_AI_LAST_OUTPUT"

    _ai_show_answer "${answer:-no response}"
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
        LBUFFER="${_AI_SUGGESTIONS[$(( _AI_INDEX + 1 ))]}"
        RBUFFER="$_AI_RIGHT"
        _ai_reset_menu
        zle redisplay
        return
    fi
    zle accept-line
}

# ── Ctrl+C: cancel menu ──────────────────────────────────────
_ai_cancel() {
    if (( _AI_ACTIVE )); then
        _ai_clear_menu
        LBUFFER="$_AI_ORIGINAL"
        RBUFFER="$_AI_RIGHT"
        _ai_reset_menu
        zle redisplay
    else
        zle send-break
    fi
}

# ── Register widgets ──────────────────────────────────────────
zle -N ai-trigger _ai_trigger
zle -N ai-ask _ai_ask
zle -N ai-down   _ai_down
zle -N ai-up     _ai_up
zle -N ai-enter  _ai_enter
zle -N ai-cancel _ai_cancel

# ── Key bindings ──────────────────────────────────────────────
bindkey '^L'   ai-trigger  # Ctrl+L (l = list)
bindkey '^G'   ai-ask      # Ctrl+G (g = generate)
bindkey '\e[A' ai-up        # Up arrow
bindkey '\e[B' ai-down      # Down arrow
bindkey '\eOA' ai-up        # Up arrow (alt)
bindkey '\eOB' ai-down      # Down arrow (alt)
bindkey '^M'   ai-enter     # Enter
bindkey '^J'   ai-enter     # Enter (LF)
bindkey '^C'   ai-cancel    # Ctrl+C to cancel

# ── Init ──────────────────────────────────────────────────────
echo "AI command completion loaded. Ctrl+L → list suggestions, Ctrl+G → ask AI, ↑↓ → navigate, Enter → accept."
