#!/bin/zsh

_AI_HIST_ACTIVE=${_AI_HIST_ACTIVE:-0}
typeset -ga _AI_HIST_SUGGESTIONS
_AI_HIST_SUGGESTIONS=(${_AI_HIST_SUGGESTIONS[@]})
_AI_HIST_INDEX=${_AI_HIST_INDEX:-0}
_AI_HIST_PREFIX=${_AI_HIST_PREFIX:-""}
_AI_HIST_RIGHT=${_AI_HIST_RIGHT:-""}
_AI_HIST_LIMIT=${_AI_HIST_LIMIT:-20}

_ai_hist_register_ignore_widgets() {
    (( ${+ZSH_AUTOSUGGEST_IGNORE_WIDGETS} )) || typeset -ga ZSH_AUTOSUGGEST_IGNORE_WIDGETS
    ZSH_AUTOSUGGEST_IGNORE_WIDGETS=(${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[@]-})
    [[ " ${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[*]} " == *" ai-history-prev "* ]] || ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(ai-history-prev)
    [[ " ${ZSH_AUTOSUGGEST_IGNORE_WIDGETS[*]} " == *" ai-history-next "* ]] || ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(ai-history-next)
}

_ai_hist_highlight_reset() {
    (( ${+functions[_zsh_autosuggest_highlight_reset]} )) || return 0
    _zsh_autosuggest_highlight_reset
}

_ai_hist_highlight_apply() {
    (( ${+functions[_zsh_autosuggest_highlight_apply]} )) || return 0
    _zsh_autosuggest_highlight_apply
}

_ai_hist_register_ignore_widgets

_ai_hist_normalize_line() {
    local line="$1"

    [[ "$line" == ': '*';'* ]] && line="${line#*;}"
    line="${line##[[:space:]]#}"
    if [[ "$line" == <->' '* ]]; then
        line="${line##<-> ##}"
    fi
    line="${line##[[:space:]]#}"

    print -- "$line"
}

_ai_hist_collect_candidates() {
    local prefix="$1"
    local line normalized
    local -a matches=()
    local -a history_lines=()
    local -A seen=()
    local idx

    [[ -n "$prefix" ]] || return 0

    history_lines=("${(@f)$(fc -rln 1 2>/dev/null)}")

    if (( ${#history_lines} == 0 )) && [[ -n "${HISTFILE:-}" && -r "${HISTFILE}" ]]; then
        history_lines=("${(@f)$(<"$HISTFILE")}")
        for (( idx = ${#history_lines}; idx >= 1; idx-- )); do
            line="${history_lines[$idx]}"
            normalized=$(_ai_hist_normalize_line "$line")
            [[ -n "$normalized" ]] || continue
            [[ "$normalized" == "$prefix" ]] && continue
            [[ "$normalized" == "$prefix"* ]] || continue
            [[ -n "${seen[$normalized]:-}" ]] && continue
            seen[$normalized]=1
            matches+=("$normalized")
            (( ${#matches} >= _AI_HIST_LIMIT )) && break
        done
    else
        for line in "${history_lines[@]}"; do
            normalized=$(_ai_hist_normalize_line "$line")
            [[ -n "$normalized" ]] || continue
            [[ "$normalized" == "$prefix" ]] && continue
            [[ "$normalized" == "$prefix"* ]] || continue
            [[ -n "${seen[$normalized]:-}" ]] && continue
            seen[$normalized]=1
            matches+=("$normalized")
            (( ${#matches} >= _AI_HIST_LIMIT )) && break
        done
    fi

    print -r -- "${(F)matches}"
}

_ai_hist_current_item() {
    (( ${#_AI_HIST_SUGGESTIONS} > 0 )) || return 1
    print -- "${_AI_HIST_SUGGESTIONS[$(( _AI_HIST_INDEX + 1 ))]}"
}

_ai_hist_visible_suffix() {
    local item="$1"
    local prefix="$2"
    local prefix_len=${#prefix}

    [[ "$prefix_len" -le "${#item}" ]] || return 1
    [[ "${item[1,prefix_len]}" == "$prefix" ]] || return 1
    print -- "${item:$prefix_len}"
}

_ai_hist_clear_overlay() {
    POSTDISPLAY=""
}

_ai_history_reset() {
    _ai_hist_clear_overlay
    _ai_hist_highlight_reset
    _AI_HIST_ACTIVE=0
    _AI_HIST_SUGGESTIONS=()
    _AI_HIST_INDEX=0
    _AI_HIST_PREFIX=""
    _AI_HIST_RIGHT=""
    return 0
}

_ai_hist_show_inline() {
    local item suffix
    item=$(_ai_hist_current_item) || return 1
    suffix=$(_ai_hist_visible_suffix "$item" "$LBUFFER") || return 1
    POSTDISPLAY="$suffix"
    _AI_HIST_ACTIVE=1
    _AI_HIST_RIGHT="$RBUFFER"
    _ai_hist_highlight_reset
    _ai_hist_highlight_apply
    zle redisplay
}

_ai_hist_refresh_if_needed() {
    local prefix="$LBUFFER"
    local raw

    if [[ "$prefix" != "$_AI_HIST_PREFIX" || "$RBUFFER" != "$_AI_HIST_RIGHT" || ${#_AI_HIST_SUGGESTIONS} -eq 0 ]]; then
        raw=$(_ai_hist_collect_candidates "$prefix")
        if [[ -z "$raw" ]]; then
            _ai_history_reset
            return 1
        fi
        _AI_HIST_SUGGESTIONS=("${(@f)raw}")
        _AI_HIST_PREFIX="$prefix"
        _AI_HIST_INDEX=0
    fi

    return 0
}

_ai_history_prev_handler() {
    if ! _ai_hist_refresh_if_needed; then
        zle kill-line
        return
    fi

    _AI_HIST_INDEX=$(( (_AI_HIST_INDEX - 1 + ${#_AI_HIST_SUGGESTIONS}) % ${#_AI_HIST_SUGGESTIONS} ))
    if ! _ai_hist_show_inline; then
        _ai_history_reset
    fi
}

_ai_history_next_handler() {
    if ! _ai_hist_refresh_if_needed; then
        zle down-line-or-history
        return
    fi

    if (( !_AI_HIST_ACTIVE )); then
        _AI_HIST_INDEX=0
    else
        _AI_HIST_INDEX=$(( (_AI_HIST_INDEX + 1) % ${#_AI_HIST_SUGGESTIONS} ))
    fi
    if ! _ai_hist_show_inline; then
        _ai_history_reset
    fi
}

_ai_history_accept() {
    (( _AI_HIST_ACTIVE && ${#_AI_HIST_SUGGESTIONS} > 0 )) || return 1
    local item
    item=$(_ai_hist_current_item) || return 1
    LBUFFER="$item"
    RBUFFER="$_AI_HIST_RIGHT"
    _ai_history_reset
    zle redisplay
    return 0
}

_ai_history_cancel() {
    (( _AI_HIST_ACTIVE )) || return 1
    _ai_history_reset
    zle redisplay
    return 0
}
