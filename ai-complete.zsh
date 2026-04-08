# AI-powered Tab completion for zsh
#
# Tab      → show suggestions / cycle forward
# Up/Down  → navigate suggestions
# Enter    → accept suggestion (press Enter again to execute)
# Ctrl+C   → cancel menu, restore original input
#
# Config:
#   export AI_COMPLETE_API_KEY="sk-..."          (required)
#   export AI_COMPLETE_MAX_ITEMS=5               (optional, default 5)
#   export AI_COMPLETE_MODEL="gpt-4o-mini"       (optional)
#   export AI_COMPLETE_API_URL="https://..."      (optional)
#
# Dependencies: jq, curl

# ── Setup ─────────────────────────────────────────────────────
_ai_setup() {
    local script_dir="${0:A:h}"
    if [[ ":$PATH:" != *":$script_dir:"* ]]; then
        export PATH="$script_dir:$PATH"
    fi
}
_ai_setup

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

# ── Clamp scroll window ──────────────────────────────────────
_ai_clamp_scroll() {
    (( _AI_INDEX < _AI_SCROLL )) && _AI_SCROLL=$((_AI_INDEX))
    (( _AI_INDEX >= _AI_SCROLL + _AI_MAX_ITEMS )) && _AI_SCROLL=$(( _AI_INDEX - _AI_MAX_ITEMS + 1 ))
    (( _AI_SCROLL < 0 )) && _AI_SCROLL=0
}

# ── Clear rendered menu ───────────────────────────────────────
_ai_clear_menu() {
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

# ── Render bordered vertical list ────────────────────────────
_ai_show() {
    (( ${#_AI_SUGGESTIONS} > 0 )) || return

    _ai_clamp_scroll

    LBUFFER="${_AI_SUGGESTIONS[$(( _AI_INDEX + 1 ))]}"
    RBUFFER="$_AI_RIGHT"

    # Let ZLE refresh the command line FIRST (positions cursor correctly)
    zle redisplay

    _ai_clear_menu

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

# ── Tab: open menu / cycle forward ───────────────────────────
_ai_tab() {
    local input="${LBUFFER}"

    [[ -z "${input// /}" ]] && { zle expand-or-complete; return }

    # Menu already open → cycle
    if (( _AI_ACTIVE )); then
        _AI_INDEX=$(( (_AI_INDEX + 1) % ${#_AI_SUGGESTIONS} ))
        _ai_show
        return
    fi

    _AI_ORIGINAL="$input"
    _AI_RIGHT="$RBUFFER"
    _AI_INDEX=0
    _AI_SCROLL=0

    # Run ai-suggest in background
    local tmpf; tmpf=$(mktemp)
    { ai-suggest "$input" > "$tmpf" } 2>/dev/null &!
    local bg_pid=$!

    # Inline spinner after current input
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠧' '⠇' '⠏')
    local si=0
    while kill -0 "$bg_pid" 2>/dev/null; do
        LBUFFER="$input"
        POSTDISPLAY=" ${spin[$(( si % 9 + 1 ))]}"
        zle redisplay
        si=$(( si + 1 ))
        sleep 0.1
    done

    local raw; raw=$(cat "$tmpf" 2>/dev/null)
    rm -f "$tmpf"
    POSTDISPLAY=""
    zle redisplay

    [[ -z "$raw" ]] && { _ai_reset_menu; zle expand-or-complete; return }

    _AI_SUGGESTIONS=("${(@f)raw}")
    (( ${#_AI_SUGGESTIONS} > 0 )) || { _ai_reset_menu; zle expand-or-complete; return }

    _AI_ACTIVE=1
    _ai_show
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
zle -N ai-tab    _ai_tab
zle -N ai-down   _ai_down
zle -N ai-up     _ai_up
zle -N ai-enter  _ai_enter
zle -N ai-cancel _ai_cancel

# ── Key bindings ──────────────────────────────────────────────
bindkey '^I'   ai-tab       # Tab
bindkey '\e[A' ai-up        # Up arrow
bindkey '\e[B' ai-down      # Down arrow
bindkey '\eOA' ai-up        # Up arrow (alt)
bindkey '\eOB' ai-down      # Down arrow (alt)
bindkey '^M'   ai-enter     # Enter
bindkey '^J'   ai-enter     # Enter (LF)
bindkey '^C'   ai-cancel    # Ctrl+C to cancel

# ── Init ──────────────────────────────────────────────────────
echo "AI Tab completion loaded. Tab → suggest, ↑↓ → navigate, Enter → accept."
