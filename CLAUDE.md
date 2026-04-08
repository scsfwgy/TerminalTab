# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TerminalTab is a zsh plugin that provides AI-powered command suggestions on Tab key press. It calls an LLM API (OpenAI-compatible) to suggest complete commands for typos, partial input, or valid commands that could use more flags.

Two files, zero dependencies beyond `curl` + `jq`:
- `ai-suggest` — Bash script that calls LLM API, returns newline-separated command suggestions
- `ai-complete.zsh` — ZLE (Zsh Line Editor) plugin that hooks Tab/Up/Down/Enter keys

## Architecture

```
User presses Tab
  → ai-complete.zsh (_ai_tab widget)
    → ai-suggest (background process via &!)
    → Spinner via zle -R
    → _ai_show: zle redisplay → save cursor → printf border list → restore cursor
  → User presses Up/Down
    → _ai_show re-renders list with new selection in LBUFFER
  → User presses Enter
    → Selected command placed in buffer, list cleared
```

State is managed via global `_AI_*` variables in the zsh session. The `_AI_ACTIVE` flag controls whether special keybindings (arrow keys, Enter) route to AI navigation or fall through to normal zsh behavior.

## Setup

```bash
# In .zshrc:
export AI_COMPLETE_API_KEY="sk-..."
export AI_COMPLETE_MODEL="gpt-4o-mini"                    # optional
export AI_COMPLETE_API_URL="https://api.openai.com/..."    # optional
export AI_COMPLETE_MAX_ITEMS=5                             # optional
source ~/path/to/TerminalTab/ai-complete.zsh
```

## Key Lessons Learned (ZLE + Terminal Display)

These are non-obvious pitfalls discovered during development that future changes must respect:

### 1. ZLE display management
- **Never** use raw `printf` to the terminal without coordinating with ZLE. ZLE's auto-refresh (when a widget returns) WILL overwrite or corrupt anything it doesn't know about.
- The correct sequence: `zle redisplay` first (let ZLE handle command line), then `\e[s` (save cursor), then `printf` the list below, then `\e[u` (restore cursor). This prevents ZLE from fighting the display.

### 2. `zle -R "" list...` is unreliable for custom layout
- zsh's completion listing system auto-sorts items alphabetically, destroying intentional ordering (e.g. first suggestion should be selected).
- It also auto-arranges into columns (horizontal packing). Padding items to 200+ chars forces single-column but is hacky and caused `item=` variable echo issues.
- The `zle -R "multi\nline\nmessage"` approach does NOT render multi-line strings — only the first line appears.

### 3. `POSTDISPLAY` is single-line only
- Despite documentation suggesting otherwise, `POSTDISPLAY` only renders content inline after the cursor on the same line. Multi-line content (with `\n`) is NOT displayed as separate lines.

### 4. Background job notifications
- `{ cmd & } &!` syntax is required — not just `&` with `disown`. The `&!` operator (zsh-specific) immediately disowns the job, preventing `[N] + done cmd...` notifications from appearing.
- Do NOT use `wait $pid` inside ZLE widgets — it triggers job completion notifications. Use `kill -0 $pid` polling loop instead.

### 5. Variable declarations inside ZLE widget loops
- `local var` inside a `for` loop in a ZLE widget can cause the assignment to be echoed to the terminal (visible as `item='value'` text). Declare ALL variables outside the loop, assign inside.

### 6. ANSI escape codes in zsh strings
- `\e[7m` (reverse video) must be written as `$'\e[7m'` (quoted `$'...'` syntax), not `\e[7m` in double quotes. The latter prints literal `e[7m` text.

### 7. Escape key binding conflicts
- Do NOT `bindkey '\e'` (bare Escape) — it conflicts with arrow key sequences (`\e[A`, `\e[B`) since Escape starts all CSI sequences. Use `^C` for cancel instead.

## Extending

- To change the LLM prompt: edit `PROMPT` variable in `ai-suggest`
- To change max visible items: `export AI_COMPLETE_MAX_ITEMS=N` or edit `_AI_MAX_ITEMS` default
- To change border style: edit the `printf` format strings in `_ai_show()`
- The border width auto-calculates from the longest visible item (min 15, max 50 chars)
