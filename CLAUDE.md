# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中工作时提供指导。

## 项目概述

TerminalTab 是一个 zsh 插件，提供四个核心快捷键：
- `Ctrl+L` — 调用大模型 API 返回命令建议列表（l = list）
- `Ctrl+G` — 向 AI 提问（g = generate）
- `Ctrl+U` — 切换到上一个历史 inline suggestion（u = up）
- `Ctrl+N` — 切换到下一个历史 inline suggestion（n = next）

四个快捷键均支持自定义，通过环境变量覆盖默认值，详见"配置"一节。

核心分为五层：
- `ai-complete.zsh` — ZLE（Zsh 行编辑器）总入口，负责快捷键注册与校验、loading、AI 菜单渲染、统一状态管理
- `zsh-autosuggestions-enhance.sh` — 基于官方 autosuggestions 的历史多候选 inline cycling 增强层
- `ai-command-list.sh` — Ctrl+L 建议入口
- `ai-command-generate.sh` — Ctrl+G 问答入口
- `ai-command-request.sh` — 共享 LLM 请求层，负责配置校验、prompt 加载、API 请求、响应提取与建议清洗

## 架构

### Ctrl+L AI 建议流程

```
用户按 Ctrl+L (l = list)
  → ai-complete.zsh (_ai_trigger widget)
    → ai-command-list.sh（通过 &! 后台运行）
    → ai-command-request.sh（共享请求层）
    → 通过 POSTDISPLAY 在输入内容后显示 "AI generating..." 提示
    → _ai_show: zle redisplay → 清理旧列表 → DEC 保存光标 → printf 边框列表 → DEC 恢复光标
  → 用户按 上/下
    → _ai_show 重新渲染列表，更新选中项到 LBUFFER
  → 用户按 回车
    → 选中命令填入缓冲区，列表清除并重置状态
  → 用户按 Ctrl+C
    → 恢复原始输入，列表清除并重置状态
```

### Ctrl+U / Ctrl+N 历史候选流程

```
用户输入前缀（如 git checkout ），按 Ctrl+N
  → ai-complete.zsh (_ai_history_next widget)
    → _ai_history_next_handler（由 zsh-autosuggestions-enhance.sh 覆写）
    → _ai_hist_collect_candidates：通过 fc -rln 1 收集历史，过滤前缀匹配、去重、限数
    → _ai_hist_show_inline：设置 POSTDISPLAY 为候选的未输入尾部（灰色 inline suggestion）
  → 用户继续按 Ctrl+N / Ctrl+U
    → 循环切换候选，刷新 POSTDISPLAY
  → 用户按 回车
    → _ai_history_accept：当前候选写入 LBUFFER，清理 history 状态
  → 无候选时
    → Ctrl+U 回退到 zle kill-line
    → Ctrl+N 回退到 zle down-line-or-history
```

### 状态管理

AI 菜单和历史 cycling 使用独立的状态变量，互不干扰：
- AI 菜单：`_AI_ACTIVE`、`_AI_SUGGESTIONS`、`_AI_INDEX`、`_AI_SCROLL`、`_AI_LIST_LINES`
- 历史 cycling：`_AI_HIST_ACTIVE`、`_AI_HIST_SUGGESTIONS`、`_AI_HIST_INDEX`、`_AI_HIST_PREFIX`、`_AI_HIST_RIGHT`

## 配置

```bash
# 在 .zshrc 中：
export AI_COMPLETE_API_KEY="sk-..."                        # 必填
export AI_COMPLETE_MODEL="gpt-4o-mini"                     # 必填
export AI_COMPLETE_API_URL="https://api.openai.com/..."    # 必填
export AI_COMPLETE_API_TYPE="openai"                       # 可选：openai（默认）或 claude
export AI_COMPLETE_MAX_ITEMS=5                             # 可选，默认 5
export AI_COMPLETE_TRIGGER_BINDKEY='^L'                    # 可选，默认 Ctrl+L
export AI_COMPLETE_ASK_BINDKEY='^G'                        # 可选，默认 Ctrl+G
export AI_COMPLETE_HISTORY_PREV_BINDKEY='^U'               # 可选，默认 Ctrl+U
export AI_COMPLETE_HISTORY_NEXT_BINDKEY='^N'               # 可选，默认 Ctrl+N
source ~/path/to/TerminalTab/ai-complete.zsh
```

快捷键值必须使用 zsh `bindkey` 原生语法（如 `'^T'`、`'^Y'`）。非法值（空值、裸 `\e`、与保留键冲突、四个键彼此重复）会导致插件报错并停止加载。

## 关键经验（ZLE + 终端显示）

以下是开发中发现的重要踩坑点，后续修改必须遵守：

### 1. ZLE 显示管理
- **绝不**在未与 ZLE 协调的情况下直接 `printf` 到终端。ZLE 的自动刷新（widget 返回时）会覆盖或破坏它不知道的任何内容。
- 渲染列表的正确顺序：先 `zle redisplay`（让 ZLE 处理命令行），再清理旧列表，然后 `\e7`（DEC 保存光标），接着 `printf` 列表内容，最后 `\e8`（DEC 恢复光标）。使用 DEC 保存/恢复而非 CSI s/u，避免与 ZLE 内部冲突。
- 列表清理逻辑必须统一，避免 `_ai_show` / Enter / Ctrl+C 各自使用不同的 ANSI 序列，否则容易出现残影、错位和状态不同步。
- 导航（上/下）时旧列表必须先清掉再重绘；关闭菜单时也必须走同一套清理路径。
- 如果已经记录了菜单高度（如 `_AI_LIST_LINES`），清理时应按实际行数逐行清除，而不是直接 `\e[J` 清到屏幕底部，避免误清终端其它内容。

### 2. Loading 提示与列表显示要分层处理
- Loading 提示适合用 `POSTDISPLAY`，直接显示在用户当前输入内容后面，如 `ls AI generating...`。
- **不要**用 Braille 动画帧做 spinner——不同终端对 Braille 字符的渲染宽度不一致，容易导致抖动和光标错位。改用静态文字。
- 多行边框列表**不能**用 `POSTDISPLAY`，因为它只支持单行；多行列表仍需使用 `printf` + 光标保存/恢复来绘制。
- `POSTDISPLAY` 使用完后必须及时清空，否则会残留在命令行尾部。

### 3. `zle -R "" list...` 不适合自定义布局
- zsh 的补全列表系统会按字母排序，破坏原有顺序（如第一个建议应该默认选中）。
- 它还会自动横向排列成多列。用 200+ 字符填充强制单列属于 hack 方案，且会导致 `item=` 变量回显问题。
- `zle -R "多行\n消息"` 方式不会渲染多行字符串——只显示第一行。

### 4. `POSTDISPLAY` 仅支持单行
- 尽管文档暗示支持多行，`POSTDISPLAY` 只在光标后同一行内渲染。含 `\n` 的多行内容不会显示为多行。

### 5. 后台任务通知
- 必须使用 `{ cmd & } &!` 语法——不能仅用 `&` 加 `disown`。`&!`（zsh 专用）会立即剥离任务，防止出现 `[N] + done cmd...` 通知。
- **不要**在 ZLE widget 内使用 `wait $pid`——它会触发任务完成通知。改用 `kill -0 $pid` 轮询循环。

### 6. ZLE widget 循环内的变量声明
- ZLE widget 的 `for` 循环内使用 `local var` 会导致赋值被回显到终端（显示为 `item='value'` 文本）。所有变量需在循环外声明，循环内赋值。

### 7. 建议结果清洗必须在源头完成
- `ai-command-request.sh` 的 list 模式返回值不能直接信任。模型可能返回编号列表、项目符号、代码块围栏、空行、重复命令。
- 应在共享请求层内统一做清洗：trim、去编号/项目符号、去代码块残留、去重、保序、限制最大条数。
- 前端菜单应尽量只处理"已经清洗好的完整命令列表"，不要把脏数据留给 `ai-complete.zsh` 再兜底。

### 8. 菜单关闭必须统一重置状态
- 关闭菜单时不能只清屏，还必须统一重置 `_AI_ACTIVE`、`_AI_SUGGESTIONS`、`_AI_INDEX`、`_AI_SCROLL`、`_AI_LIST_LINES`。
- Enter 接受和 Ctrl+C 取消都应复用同一套状态重置逻辑，否则下一次打开菜单时容易出现状态残留。

### 9. Esc 键绑定冲突
- **不要** `bindkey '\e'`（裸 Escape）——它会与方向键序列（`\e[A`、`\e[B`）冲突，因为 Escape 是所有 CSI 序列的起始。改用 `^C` 取消。

### 10. zsh 字符串中的 ANSI 转义码
- `\e[7m`（反色显示）必须用 `$'\e[7m'`（`$'...'` 引用语法），不能用双引号中的 `\e[7m`，后者会原样输出 `e[7m` 文本。

### 11. 入口层与 autosuggestions 增强层分离
- `ai-complete.zsh` 应保持为入口和装配层：负责快捷键注册、AI 菜单、loading、统一生命周期。
- 历史多候选 inline suggestion cycling 放在 `zsh-autosuggestions-enhance.sh`，不要把这部分逻辑重新塞回 `ai-complete.zsh`。
- `Ctrl+U` / `Ctrl+N` 的默认行为和校验仍由入口层负责，但具体 history candidate 收集、inline overlay、accept/cancel/reset 由增强层实现。

### 12. zsh-autosuggestions widget 交互
- 官方 `zsh-autosuggestions` 会把用户自定义 widget 包裹为"modify"类型，导致它在 widget 执行后自动清除 `POSTDISPLAY`。
- 自定义的 history cycling widget（`ai-history-prev`、`ai-history-next`）必须注册到 `ZSH_AUTOSUGGEST_IGNORE_WIDGETS`，避免 autosuggestions 干扰自定义的 `POSTDISPLAY` 管理。
- 设置 `POSTDISPLAY` 后需要调用 `_zsh_autosuggest_highlight_reset` + `_zsh_autosuggest_highlight_apply`，否则灰色高亮不会生效。

### 13. zsh `nounset` (`set -u`) 与数组下标访问
- 在 `set -u` 环境下，访问未定义数组的下标（如 `arr[(r)val]`）会报 `parameter not set` 错误，即使外面有 `${+var}` 守卫也不行。
- 正确做法：先用 `typeset -ga` 声明数组，再初始化为安全的空值（如 `arr=(${arr[@]-})`），然后再做下标查找。
- 测试脚本通常使用 `set -euo pipefail`，因此增强模块的代码必须在 `nounset` 下安全运行。

## 扩展

- 修改 LLM 提示词：编辑 `prompts/suggest.prompt` 和 `prompts/ask.prompt`
- 修改最大显示条目数：`export AI_COMPLETE_MAX_ITEMS=N` 或编辑 `_AI_MAX_ITEMS` 默认值
- 修改边框样式：编辑 `_ai_show()` 中的 `printf` 格式字符串
- 边框宽度根据最长可见条目自动计算（最小 15，最大 50 字符）
