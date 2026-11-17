# Neovim Offline Build

为 CentOS 7 x86_64 构建独立的 Neovim 离线开发环境。构建只需要 Windows + PowerShell，不需要 WSL2、虚拟机或 Linux 构建机。

## 1. Windows 构建

### 环境要求

- Windows 10/11 x86_64
- PowerShell 5.1 或 PowerShell 7
- Git for Windows
- mise
- Node.js 22.23.5
- npm 10.9.9
- Windows 自带 tar.exe

在仓库根目录执行：

~~~powershell
mise install
mise exec -- node --version
mise exec -- npm --version
git --version
tar --version
~~~

确认 Node.js 为 v22.23.5、npm 为 10.9.9 后，执行构建：

~~~powershell
.\build.ps1
~~~

如果当前 PowerShell 没有启用 mise 自动激活，可显式通过 mise 启动构建：

~~~powershell
mise exec -- powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
~~~

使用 PowerShell 7 时，将命令中的 powershell 替换为 pwsh。

首次构建会下载 Linux 运行时、字体、语言工具和插件，并生成依赖锁文件。将首次构建生成或更新的以下文件提交到 Git：

- locks/npm/package-lock.json
- locks/python/tclint-requirements.txt
- locks/plugins.lock.json

提交锁文件：

~~~powershell
git add locks/plugins.lock.json locks/npm/package-lock.json locks/python/tclint-requirements.txt
git commit -m "build: update offline dependency locks"
~~~

后续日常构建：

~~~powershell
.\build.ps1
~~~

只有主动更新插件或 npm / Python 依赖时才执行：

~~~powershell
.\build.ps1 -RefreshLocks
~~~

构建缓存保存在仓库的 cache/，临时组装目录为 work/，最终产物为：

~~~text
dist/
└── nvim-centos7-x86_64-node22.23.5.tar.gz
~~~

## 2. CentOS 7 部署

将 tar.gz 复制到 CentOS 7。以下以 /data/devtools/nvim 为安装目录：

~~~bash
mkdir -p /data/devtools/nvim
tar -xzf nvim-centos7-x86_64-node22.23.5.tar.gz -C /data/devtools/nvim

cd /data/devtools/nvim

# 初始化运行时并恢复所有必要的执行权限
bash install.sh

# 验证运行时、插件和语言工具
./verify.sh

# 启动 Neovim
./nvim
~~~

安装不需要 root。安装目录所在文件系统必须允许执行（不能以 noexec 挂载）。Neovim 的配置、插件、运行时、缓存和日志均保留在安装目录内，不写入 HOME 或系统公共 bin。

## 3. Python 项目配置

Python 项目使用 uv 管理依赖，约定在项目根目录创建 `.venv`。Pyright 通过项目自己的 `pyrightconfig.json` 使用该环境，不需要 Neovim 虚拟环境选择插件。

在项目根目录配置：

~~~json
{
  "venvPath": ".",
  "venv": ".venv",
  "extraPaths": [
    "code/python",
    "lib/tool"
  ]
}
~~~

- `venvPath` 和 `venv` 指定项目虚拟环境。
- `extraPaths` 指定项目内部模块的额外搜索目录，按实际项目结构填写。
- `pyrightconfig.json` 可以提交到项目仓库，避免每位开发者单独配置绝对路径。
- 修改配置后，在 Neovim 中执行 `:lsp restart pyright`，让 Pyright 重新加载配置。

Neovim 不负责创建或选择 Python 虚拟环境。使用 uv 在项目根目录创建并同步环境：

~~~bash
uv sync
~~~
## 4. 常用快捷键与开发场景

Leader 键为 `Space`。除特别说明外，快捷键在 Normal 模式下使用；按 `Esc` 可返回 Normal 模式。

### 文件导航与搜索

| 快捷键 / 命令 | 功能 | 常见场景 |
|---|---|---|
| `Space e` | 打开 / 关闭文件树 | 浏览项目目录、新建或重命名文件 |
| `Space ff` | 按文件名查找 | 不记得文件所在目录时快速打开 |
| `Space fg` | 全项目文本搜索 | 查找函数名、变量名、配置项或错误信息 |
| `Space fb` | 切换已打开文件 | 在多个 Buffer 之间切换 |
| `Space fh` | 搜索 Neovim 帮助 | 查询内置命令和快捷键 |
| `Ctrl-^` | 切换到上一个文件 | 在两个文件之间来回对照 |
| `:bnext` / `:bprevious` | 下一个 / 上一个 Buffer | 顺序浏览已打开文件 |
| `:ls` | 列出已打开的 Buffer | 查看当前打开了哪些文件 |

Telescope 搜索时输入关键词即可模糊匹配；按 `Enter` 打开结果，按 `Esc` 退出搜索。

### 日常编辑

| 按键 | 功能 |
|---|---|
| `i` / `a` | 在光标前 / 后进入输入模式 |
| `o` / `O` | 在当前行下方 / 上方新建一行 |
| `Esc` | 返回 Normal 模式 |
| `dd` / `yy` / `p` | 删除行 / 复制行 / 粘贴 |
| `u` / `Ctrl-r` | 撤销 / 重做 |
| `ciw` | 修改光标所在单词 |
| `V` | 按行选择；再用 `j`、`k` 扩展选择 |
| `gcc` | 注释 / 取消注释当前行 |
| Visual 选择后 `gc` | 注释 / 取消注释选中范围 |
| `/`、`n`、`N` | 向下查找、下一个匹配、上一个匹配 |
| `0` / `^` / `$` | 行首 / 首个非空字符 / 行尾 |
| `gg` / `G` | 文件开头 / 文件末尾 |
| `:120` | 跳转到第 120 行（数字可替换） |
| `Space w` | 保存当前文件 |
| `:q` / `:wq` | 关闭窗口 / 保存并关闭 |

### 窗口与分屏

| 命令 / 按键 | 功能 |
|---|---|
| `:vsplit` | 左右分屏 |
| `:split` | 上下分屏 |
| `Ctrl-w h/j/k/l` | 切换到左 / 下 / 上 / 右窗口 |
| `Ctrl-w =` | 平均调整窗口大小 |
| `:q` | 关闭当前窗口 |

### 代码导航、补全与诊断

以下 LSP 快捷键在对应语言服务器已附加到当前文件时可用，使用 Neovim 原生映射：

| 快捷键 | 功能 | 常见场景 |
|---|---|---|
| `grr` | 查找引用 | 查看函数或变量在哪里被使用 |
| `grn` | 重命名符号 | 修改变量、函数或类名 |
| `gra` | Code Action | 应用语言服务器提供的代码操作 |
| `gri` | 跳转到实现 | 从接口或声明查看实现 |
| `K` | 查看悬浮文档 | 查看函数签名、类型和说明 |
| `Ctrl-s`（Insert 模式） | 查看签名帮助 | 输入函数参数时查看参数信息 |
| `[d` / `]d` | 上一个 / 下一个诊断 | 在错误和警告之间定位 |
| `Space xx` | 将诊断放入 Location List | 集中浏览当前文件的诊断 |

补全菜单打开时：

| 按键 | 功能 |
|---|---|
| `Ctrl-Space` | 手动触发补全 |
| `Tab` / `Shift-Tab` | 下一个 / 上一个补全项 |
| `Enter` | 确认补全 |
| `Ctrl-e` | 取消补全 |

### Python 项目

| 命令 | 功能 |
|---|---|
| `:lsp restart pyright` | 重启 Pyright，重新加载项目配置 |

项目虚拟环境由 `pyrightconfig.json` 指定，项目内部模块搜索路径由 `extraPaths` 管理。Neovim 不需要额外选择解释器。

### 格式化

- `Space f`：格式化当前文件。
- 已配置自动保存格式化的文件类型：JavaScript / TypeScript、JSON、HTML、CSS / SCSS、YAML、Markdown、Bash、Tcl、Verilog / SystemVerilog。
- Python 当前没有配置 Conform Formatter；不要将 `Space f` 理解为已配置 Python 格式化。

### 常见开发流程

**场景一：打开项目并定位代码**

1. 使用 `Space ff` 打开入口文件，或 `Space e` 浏览目录。
2. 使用 `Space fg` 搜索函数名或变量名。
3. 使用 `grr` 查看引用，使用 `K` 查看文档。

**场景二：修改函数并检查影响**

1. 使用 `grr` 查找调用位置。
2. 使用 `grn` 重命名，或使用 `ciw` 修改普通文本。
3. 使用 `[d` / `]d` 检查诊断。
4. 使用 `Space w` 保存。

**场景三：在多个文件之间协作**

1. 使用 `Space ff` 打开相关文件。
2. 使用 `:vsplit` 并排查看。
3. 使用 `Ctrl-w h/j/k/l` 切换窗口。
4. 使用 `Ctrl-^` 在最近两个文件之间快速切换。

**场景四：开始 Python 项目开发**

1. 确认项目根目录的 `pyrightconfig.json` 指定了 `.venv` 和必要的 `extraPaths`。
2. 使用 `Space fg` 搜索项目内部模块。
3. 使用 `grr`、`grn`、`K` 进行代码导航和理解。

快捷键不熟悉时，可以按 `Space` 查看 which-key 提示，或执行 `:Tutor` 学习 Vim 基础操作。

## 5. ICL / PDL 自定义语法高亮

仓库不内置 ICL、PDL 语法文件。Neovim 已配置文件类型识别：

- `.icl` → `icl`
- `.pdl` → `pdl`

将自己准备的 Vim Syntax 文件分别命名为 `icl.vim`、`pdl.vim`，部署到 Neovim 配置目录的 `syntax/` 下：

~~~bash
cd /data/devtools/nvim
mkdir -p config/nvim/syntax

cp /path/to/icl.vim config/nvim/syntax/icl.vim
cp /path/to/pdl.vim config/nvim/syntax/pdl.vim
~~~

无需重新构建或安装插件，重新打开对应文件即可生效。也可以在 Neovim 中执行 `:set filetype=icl` 或 `:set filetype=pdl` 手动切换文件类型。

如果希望将自己的语法文件直接包含在后续离线包中，则在 Windows 构建前，将它们放入仓库的 `config/nvim/syntax/` 目录；`build.ps1` 会将该目录一并打包。

## 6. 字体安装（可选）

默认安装到当前用户的 HOME，不需要 root：

~~~bash
cd /data/devtools/nvim
bash install-fonts.sh
~~~

只安装一个字体文件：`MapleMono-NF-CN-Regular.ttf`，包含中文字符和 Nerd Font 图标，不安装其他字重、斜体变体或额外字体文件。文件复制到：

~~~text
~/.local/share/fonts/nvim-offline-build/
└── MapleMono-NF-CN-Regular.ttf
~~~

该目录是工具专用目录。每次运行安装脚本都会先替换这个目录，确保旧字重或旧文件不会残留；HOME 中其他字体目录和文件不受影响。脚本不修改系统字体目录。CentOS 7 的旧版 Fontconfig 如果不扫描 `~/.local/share/fonts`，脚本会额外创建兼容软链接 `~/.fonts/nvim-offline-build`。Fontconfig 缓存由系统生成在用户缓存目录中。

检查字体是否可用：

~~~bash
fc-list | grep -i 'Maple Mono NF CN'
fc-match 'Maple Mono NF CN'
~~~

然后在 GNOME Terminal 或 KDE Konsole 的 Profile / Appearance 中选择 Maple Mono NF CN，并重新打开终端。该字体包含 Nerd Font 图标字形，可用于显示 Neovim 的文件、状态栏和界面图标。

卸载用户字体：

~~~bash
bash uninstall-fonts.sh
~~~

卸载只删除本工具安装的 Regular 字体文件和必要的兼容软链接；如果字体目录中存在其他文件，会保留该目录及其中的文件。

如需为整台机器的所有用户注册字体（需要 root），仍可使用：

~~~bash
sudo bash install-fonts.sh --system
sudo bash uninstall-fonts.sh --system
~~~

如果通过 SSH 在 Windows Terminal 中运行 Neovim，字体应安装并配置在 Windows 客户端；CentOS 上的字体安装不会改变 Windows Terminal 的字体。
