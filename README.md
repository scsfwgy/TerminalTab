# TerminalTab

TerminalTab 是一个轻量的 zsh 插件，提供 AI 命令建议和历史命令增强两大核心能力。

## 四个核心快捷键

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| `Ctrl+L` | AI 建议列表 | 调用大模型，返回一组完整的命令建议（l = list） |
| `Ctrl+G` | AI 问答 | 向 AI 提问，返回纯文本回答（g = generate） |
| `Ctrl+U` | 上一个历史命令 | 基于当前输入内容，显示上一条匹配的历史命令（u = up） |
| `Ctrl+N` | 下一个历史命令 | 基于当前输入内容，显示下一条匹配的历史命令（n = next） |

四个快捷键均可通过环境变量自定义。

## 特性

- AI 建议列表：垂直边框菜单展示，`↑ / ↓` 切换高亮，`Enter` 接受，`Ctrl+C` 取消
- AI 问答：直接在终端下方显示回答
- 历史 inline suggestion：基于当前输入内容，通过灰色文字显示匹配的历史命令，`Ctrl+U / Ctrl+N` 切换
- AI 加载时显示 `AI generating...` 提示
- 建议结果会自动清洗：去重、去编号、去项目符号、去代码块残留
- 仅依赖 `curl`、`jq` 和 `zsh-autosuggestions`

## 示例

![demo1](image/demo1.png)

![demo2](image/demo2.png)

![demo3](image/demo3.png)

## 原理

### AI 建议（Ctrl+L）

1. 你在命令行里输入内容后按 `Ctrl+L`
2. `ai-complete.zsh` 读取当前输入，并在后台调用 `ai-command-list.sh`
3. `ai-command-list.sh` 把请求交给 `ai-command-request.sh`，让大模型返回"每行一条"的完整命令建议
4. 返回结果会在共享请求层本地再次清洗，过滤掉空行、编号、项目符号、代码块残留和重复项
5. 清洗后的结果交给 zsh 插件渲染成可选择的建议列表
6. 你可以用 `↑ / ↓` 切换，用 `Enter` 把选中的命令填回当前输入框

### AI 问答（Ctrl+G）

1. 输入问题后按 `Ctrl+G`
2. 后台调用 `ai-command-generate.sh`，获取纯文本回答
3. 回答直接显示在终端下方

### 历史命令增强（Ctrl+U / Ctrl+N）

TerminalTab 复用官方 `zsh-users/zsh-autosuggestions` 做历史增强：基于你当前输入的内容，从命令历史中找到匹配的命令，以灰色 inline suggestion 形式显示，而不进入 `Ctrl+L` 的多行 AI 菜单。

- 输入内容（如 `git checkout `）后按 `Ctrl+N`，会基于当前输入显示下一条匹配的历史命令
- 按 `Ctrl+U` 显示上一条匹配的历史命令
- 按 `Enter` 接受当前显示的历史命令，填入完整命令
- 如果没有匹配的历史命令，`Ctrl+U` 保持原生 `kill-line` 行为，`Ctrl+N` 保持原生 `down-line-or-history` 行为

## 文件说明

- `ai-complete.zsh`：zsh 插件总入口，负责快捷键注册与校验、AI 菜单渲染、状态管理
- `zsh-autosuggestions-enhance.sh`：基于官方 `zsh-users/zsh-autosuggestions` 的历史多候选 inline cycling 增强层
- `ai-command-list.sh`：`Ctrl+L` 建议入口，返回逐行命令建议
- `ai-command-generate.sh`：`Ctrl+G` 问答入口，返回纯文本回答
- `ai-command-request.sh`：共享请求层，负责配置校验、提示词加载、API 请求与结果清洗

## 依赖

请先确保系统已安装：

```bash
brew install jq curl
```

如果系统已自带 `curl`，通常只需要安装 `jq`。

此外，TerminalTab 依赖官方 `zsh-users/zsh-autosuggestions`。

推荐方式是直接让 TerminalTab 在首次加载时自动下载到当前仓库的 `vendor/zsh-autosuggestions`；该目录适合加入 `.gitignore`，避免产生 git 噪音。

如果你更偏好系统级安装，也可以使用 Homebrew：

```bash
brew install zsh-autosuggestions
```

加载 `ai-complete.zsh` 时会按以下顺序处理：
- 如果官方 `zsh-autosuggestions` 已经加载，直接跳过
- 如果当前仓库的 `vendor/zsh-autosuggestions` 已存在，TerminalTab 会优先自动 `source`
- 如果系统里已安装但尚未加载，TerminalTab 会自动 `source`
- 如果未安装，TerminalTab 会在交互式 shell 中让你选择：自动下载到当前仓库的 `vendor/zsh-autosuggestions`，或稍后手动安装
- 如果是非交互式环境，TerminalTab 会直接打印安装指引并停止加载

## 安装

1. 克隆仓库：

```bash
git clone https://github.com/scsfwgy/TerminalTab
cd TerminalTab
```

2. 在 `~/.zshrc` 中加入配置：

最简配置：

```bash
export AI_COMPLETE_API_KEY="sk-..."
export AI_COMPLETE_MODEL="gpt-4o-mini"
export AI_COMPLETE_API_URL="https://api.openai.com/v1/chat/completions"

source /path/to/TerminalTab/ai-complete.zsh
```

首次 `source /path/to/TerminalTab/ai-complete.zsh` 时：
- 如果当前仓库下已经有 `vendor/zsh-autosuggestions`，会直接复用
- 如果还没有，TerminalTab 会提示你选择是否自动下载到当前仓库的 `vendor/zsh-autosuggestions`
- 该目录适合加入 `.gitignore`，避免产生 git 噪音

完整配置示例：

```bash
export AI_COMPLETE_API_TYPE="openai"
export AI_COMPLETE_API_KEY="sk-..."
export AI_COMPLETE_MODEL="gpt-4o-mini"
export AI_COMPLETE_API_URL="https://api.openai.com/v1/chat/completions"
export AI_COMPLETE_MAX_ITEMS=5
export AI_COMPLETE_TRIGGER_BINDKEY='^L'
export AI_COMPLETE_ASK_BINDKEY='^G'
export AI_COMPLETE_HISTORY_PREV_BINDKEY='^U'
export AI_COMPLETE_HISTORY_NEXT_BINDKEY='^N'

source /path/to/TerminalTab/ai-complete.zsh
```

如果你更希望用系统级安装，也可以先通过 Homebrew 安装，或手动在 `~/.zshrc` 中先加载官方插件：

```bash
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /path/to/TerminalTab/ai-complete.zsh
```

其中以下 3 个变量是必填项：
- `AI_COMPLETE_API_URL`
- `AI_COMPLETE_MODEL`
- `AI_COMPLETE_API_KEY`

可选快捷键配置：
- `AI_COMPLETE_TRIGGER_BINDKEY`：触发建议列表，默认 `'^L'`（即 `Ctrl+L`）
- `AI_COMPLETE_ASK_BINDKEY`：向 AI 提问，默认 `'^G'`（即 `Ctrl+G`）
- `AI_COMPLETE_HISTORY_PREV_BINDKEY`：显示上一条匹配的历史命令，默认 `'^U'`（即 `Ctrl+U`）
- `AI_COMPLETE_HISTORY_NEXT_BINDKEY`：显示下一条匹配的历史命令，默认 `'^N'`（即 `Ctrl+N`）

快捷键值必须使用 zsh `bindkey` 原生语法，例如 `'^T'`、`'^Y'`。如果用户显式设置了非法值（例如空值、裸 `\e`、与方向键 / Enter / Ctrl+C 冲突、或快捷键之间重复），插件会直接报错并停止加载，而不会回退到默认快捷键。

`AI_COMPLETE_API_TYPE` 控制协议格式，默认 `openai`，使用 Claude 时设为 `claude`。

举例：

```bash
# DeepSeek 举例
export AI_COMPLETE_API_KEY="sk-ebfbeed****854700044d"
export AI_COMPLETE_API_URL="https://api.deepseek.com/v1/chat/completions"
export AI_COMPLETE_MODEL="deepseek-chat"

source ~/TerminalTab/ai-complete.zsh
```

```bash
# Claude 举例
export AI_COMPLETE_API_TYPE="claude"
export AI_COMPLETE_API_KEY="sk-ant-..."
export AI_COMPLETE_API_URL="https://api.anthropic.com/v1/messages"
export AI_COMPLETE_MODEL="claude-sonnet-4-20250514"

source ~/TerminalTab/ai-complete.zsh
```

3. 重新加载 shell：

```bash
source ~/.zshrc
```

## 使用方式

默认快捷键：
- `Ctrl+L`：请求 / 刷新 AI 建议（l = list）
- `Ctrl+G`：向 AI 提问（g = generate）
- `Ctrl+U`：基于当前输入内容，显示上一条匹配的历史命令（u = up）
- `Ctrl+N`：基于当前输入内容，显示下一条匹配的历史命令（n = next）
- `↑ / ↓`：切换 AI 菜单高亮项
- `Enter`：接受当前高亮建议或当前历史候选
- `Ctrl+C`：取消菜单并恢复输入

如果你设置了 `AI_COMPLETE_TRIGGER_BINDKEY`、`AI_COMPLETE_ASK_BINDKEY`、`AI_COMPLETE_HISTORY_PREV_BINDKEY` 或 `AI_COMPLETE_HISTORY_NEXT_BINDKEY`，则以你配置的绑定为准；上面的快捷键只是默认值。

示例：

```bash
ls
```

按下 `Ctrl+L` 后，可能得到：

```bash
ls -la
ls -lh
ls -lt
ls -lS
```

如果输入的是拼写错误，例如：

```bash
toush
```

按下 `Ctrl+L` 后，可能得到：

```bash
touch filename
touch -c filename
touch -a filename
```

## 注意事项

- 本插件依赖 zsh 的 ZLE 机制，不适用于 bash
- `Tab` 和 `Shift+Tab` 均未被占用，仍可保留给原生补全或其它插件
