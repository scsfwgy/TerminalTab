# TerminalTab

TerminalTab 是一个轻量的 zsh 插件。

它会在你输入命令后，通过 `Ctrl+L` 调用大模型 API，返回一组选好的完整命令建议，适合用来：
- 修正拼写错误
- 补全半截命令
- 为已有命令推荐常用参数组合

## 特性

- `Ctrl+L` 触发 AI 建议（l = list）
- `Ctrl+G` 向 AI 提问（g = generate）
- 垂直边框菜单展示结果
- `↑ / ↓` 切换高亮
- `Enter` 接受当前建议
- `Ctrl+C` 取消菜单并恢复原始输入
- 加载中动画直接显示在当前输入后面
- 建议结果会自动清洗：去重、去编号、去项目符号、去代码块残留
- 仅依赖 `curl` 和 `jq`

## 示例

![demo1](image/demo1.png)

![demo2](image/demo2.png)

![demo3](image/demo3.png)

## 原理

TerminalTab 的工作流程很简单：

1. 你在命令行里输入内容后按 `Ctrl+L`
2. `ai-complete.zsh` 读取当前输入，并在后台调用 `ai-command-list.sh`
3. `ai-command-list.sh` 把请求交给 `ai-command-request.sh`，让大模型返回“每行一条”的完整命令建议
4. 返回结果会在共享请求层本地再次清洗，过滤掉空行、编号、项目符号、代码块残留和重复项
5. 清洗后的结果交给 zsh 插件渲染成可选择的建议列表
6. 你可以用 `↑ / ↓` 切换，用 `Enter` 把选中的命令填回当前输入框

也就是说：这个项目不是直接替你执行命令，而是把大模型输出整理成更适合直接使用的命令候选，再交给你选择。

## 文件说明

- `ai-complete.zsh`：zsh 插件总入口，负责键位绑定、菜单渲染、状态管理
- `ai-command-list.sh`：`Ctrl+L` 建议入口，返回逐行命令建议
- `ai-command-generate.sh`：`Ctrl+G` 问答入口，返回纯文本回答
- `ai-command-request.sh`：共享请求层，负责配置校验、提示词加载、API 请求与结果清洗

## 依赖

请先确保系统已安装：

```bash
brew install jq curl
```

如果系统已自带 `curl`，通常只需要安装 `jq`。

此外，TerminalTab 现在依赖官方 `zsh-users/zsh-autosuggestions`。

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

快捷键值必须使用 zsh `bindkey` 原生语法，例如 `'^T'`、`'^Y'`。如果用户显式设置了非法值（例如空值、裸 `\e`、与方向键 / Enter / Ctrl+C 冲突、或两个快捷键重复），插件会直接报错并停止加载，而不会回退到默认快捷键。

`AI_COMPLETE_API_TYPE` 控制协议格式，默认 `openai`，使用 Claude 时设为 `claude`。

举例

```deepseek 举例
export AI_COMPLETE_API_KEY="sk-ebfbeed****854700044d"
export AI_COMPLETE_API_URL="https://api.deepseek.com/v1/chat/completions"
export AI_COMPLETE_MODEL="deepseek-chat"

source ~/TerminalTab/ai-complete.zsh
```

```Claude 举例
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
- `↑ / ↓`：切换高亮项
- `Enter`：接受当前高亮建议
- `Ctrl+C`：取消菜单并恢复输入

如果你设置了 `AI_COMPLETE_TRIGGER_BINDKEY` 或 `AI_COMPLETE_ASK_BINDKEY`，则以你配置的绑定为准；上面的 `Ctrl+L` / `Ctrl+G` 只是默认值。

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
