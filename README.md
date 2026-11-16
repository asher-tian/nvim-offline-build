# nvim-offline-build

面向 CentOS 7 x86_64 的 Neovim 离线 IDE 构建工程。**只需要 Windows + PowerShell，不需要 WSL2、虚拟机、Docker 或 Linux 构建环境。**

构建产物包含 Linux 目标程序、Node.js 运行时、LSP、Neovim 插件、配置和初始化脚本。CentOS 7 不需要预装 Node.js/npm，也不需要联网。

## 目标环境

- CentOS 7 x86_64
- glibc 2.17 或更新版本
- 安装目录由部署者指定，例如 /data/devtools/nvim
- Node.js **22.23.5**（固定版本，linux-x64-glibc-217 构建）
- Neovim 0.12.5（glibc 2.17 兼容的 unsupported build）
- 独立 CPython 3.11.18（仅供 Tcl LSP / tclint 使用，不依赖 CentOS 系统 Python）

Node.js glibc-217 构建来自 nodejs/unofficial-builds，属于社区维护的非官方构建，保障等级低于 Node.js 官方标准 Linux 构建。Neovim 也使用官方列出的旧 glibc unsupported build。请在目标 CentOS 机器上执行安装和验证脚本。

## Windows 构建前提

- Windows 10/11 x86_64
- PowerShell 5.1 或 PowerShell 7
- Git for Windows
- mise（推荐）或已安装 Node.js 22.23.5
- npm 10.9.9
- Windows 自带 tar.exe
- 不要求预装 Python 或 uv；构建脚本会下载固定版本的 Windows uv，用于解析 Linux 目标的 Python wheels

仓库的 .mise.toml 固定 Windows 构建 Node.js 为 22.23.5：

~~~powershell
mise install
mise exec -- node --version
mise exec -- npm --version
git --version
tar --version
~~~

如果当前 PowerShell 没有启用 mise 自动激活，可通过 mise 启动构建进程：

~~~powershell
mise exec -- powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
~~~

预期 Node.js 为 v22.23.5，npm 为 10.9.9。

## 构建

在仓库根目录运行：

~~~powershell
.\build.ps1
~~~

输出：

~~~text
dist/
└── nvim-centos7-x86_64-node22.23.5.tar.gz
~~~

仓库已经提交 locks/plugins.lock.json，固定了第一版插件 Git commit。首次构建会生成两个依赖锁文件：

- locks/npm/package-lock.json：Node.js LSP / formatter 依赖。
- locks/python/tclint-requirements.txt：Tcl LSP 的 Linux x86_64 / CPython 3.11 wheels，包含 SHA256。

**首次构建后应将这两个锁文件提交到 Git。** 后续构建使用锁定的插件 commit、npm package-lock 和 Python requirements lock，不会自动追随上游更新。

需要主动升级插件、npm 依赖或 Tcl Python 依赖时，执行：

~~~powershell
.\build.ps1 -RefreshLocks
~~~

检查 locks/plugins.lock.json、locks/npm/package-lock.json 和 locks/python/tclint-requirements.txt 的差异并提交后，再发布新的离线包。不要在日常构建中使用 -RefreshLocks。

## 增量构建与缓存

构建缓存保存在仓库根目录的 `cache/`，不会打进 CentOS 离线包，也已经加入 .gitignore：

~~~text
cache/
├── downloads/             # Neovim、Node.js、CPython、字体、ShellCheck、Verible 等原始文件
├── npm-downloads/         # npm 下载的包缓存
├── npm-installs/           # 按 package.json / package-lock 锁定的 node_modules
├── builder/                # 固定版本的 Windows uv 构建工具
├── uv-cache/               # Tcl Python wheels 的下载缓存
├── source-cache/            # ShellCheck 对应的 GPL 源码快照
├── plugin-git/             # 插件 Git 对象缓存
└── plugin-snapshots/       # 按插件 commit 保存的工作树快照

work/
├── bundle/                 # 每次重新组装的离线包目录
└── npm/                    # npm 临时安装目录

dist/                       # 最终 tar.gz
~~~

普通执行 `.\build.ps1` 时：

- 下载文件存在且 SHA256 正确：直接复用；校验失败才重新下载。
- npm 的 package.json、package-lock、npm 版本和 linux-x64 目标均未变化：复用完整 node_modules，不再执行 npm 安装。
- npm 下载缓存独立保留；即使 node_modules 缓存缺失，也优先复用已下载的 npm 包。
- Tcl Python wheels 使用独立 uv-cache；Python site-packages 每次从锁文件重新组装到离线包。
- ShellCheck 对应源码按固定 commit 保存在 source-cache，重复构建不会重新 clone。
- 插件按锁定 commit 查找快照；命中后不访问 GitHub。快照不存在时才使用本地 Git 对象缓存，必要时才 fetch。
- 配置、启动脚本、manifest 和最终离线包每次重新组装，确保仓库中的最新修改进入产物。

首次启用增量构建时，脚本会优先迁移旧版 `work/bundle/payload`、`work/npm` 和 `work/bundle/data/.../start`；如果旧工作目录不完整，则尝试从 `dist/` 中上一次成功生成的 tar.gz 提取缓存。迁移后的二进制仍会重新校验 SHA256，npm 迁移会核对 package.json / package-lock，插件快照按旧构建 manifest 中的 commit 保存。

参数：

~~~powershell
# 默认：增量构建，复用 cache/
.\build.ps1

# 清除 work/ 和 cache/，重新下载、安装和构建；保留锁文件及 dist/
.\build.ps1 -Clean

# 主动更新插件分支、npm 和 Tcl Python 依赖锁文件；仍复用已有下载缓存
.\build.ps1 -RefreshLocks

# 指定最终产物目录
.\build.ps1 -OutputDirectory D:\Artifacts
~~~

`-Clean` 与 `-RefreshLocks` 可以组合使用。正常修改 Lua 配置、Shell 脚本或构建模板时，不需要使用这两个参数。修改 `package.json` 中的依赖版本时，应执行 `-RefreshLocks` 更新 npm 锁文件；调整 Tcl 工具版本或 Python 依赖时，也执行 `-RefreshLocks` 更新 Python 锁文件。之后提交更新后的两个锁文件。

## CentOS 7 部署

把构建产物复制到 CentOS 7，然后解压到你指定的独立目录。以下使用 /data/devtools/nvim 举例：

~~~bash
mkdir -p /data/devtools/nvim

tar -xzf nvim-centos7-x86_64-node22.23.5.tar.gz \
  -C /data/devtools/nvim

cd /data/devtools/nvim
bash install.sh

# 可选：将安装目录内的 Maple Mono NF CN 注册到系统 Fontconfig（需要 root）
sudo bash install-fonts.sh
~~~

Neovim 本体安装不需要 root，不会修改 /usr/bin、/usr/local/bin、系统 PATH 或用户 Home 下的 Neovim 配置。字体注册是独立的可选步骤，需要 root 和 fontconfig；它只在 /etc/fonts/conf.d 写入一个配置，让系统直接读取安装目录内的字体，不会把字体复制到 Home。

启动：

~~~bash
/data/devtools/nvim/nvim
~~~

验证：

~~~bash
/data/devtools/nvim/verify.sh
~~~

注意：安装目录所在文件系统不能以 noexec 挂载。install.sh 会检查这一点。建议将整个目录作为一个独立版本部署；升级时先部署到新的版本目录，验证通过后再切换软链接。

## 最终安装目录

所有 Neovim 专属文件都在指定目录内：

~~~text
nvim/
├── nvim                         # 根目录启动入口
├── install.sh
├── verify.sh
├── config/
│   ├── nvim/
│   │   ├── lua/                 # Neovim Lua 配置
│   │   └── syntax/
│   │       └── icl.vim          # IEEE 1687 ICL 语法高亮
│   └── npmrc                    # 私有 npm 配置
├── fonts/maple-mono/            # Maple Mono NF CN 静态 TTF + OFL license
├── licenses/                    # 第三方工具许可证及 ShellCheck GPL 源码
├── install-fonts.sh             # 可选：注册系统字体
├── uninstall-fonts.sh           # 可选：移除字体注册
├── data/nvim/site/pack/          # 插件
├── state/nvim/                  # undo、swap、backup 等状态
├── cache/                       # Neovim、Pyright、npm、临时缓存
├── logs/
├── runtime/
│   ├── neovim/                  # Linux Neovim 程序
│   ├── node/                    # Linux Node.js 22.23.5 + npm
│   ├── python/                  # 独立 CPython 3.11.18
│   ├── python-packages/         # tclint / pygls 等 Python wheels
│   ├── npm/node_modules/        # Node LSP 和 formatter 依赖
│   ├── commands/                # LSP / formatter POSIX 启动脚本
│   ├── npm-global/
│   └── tools/bin/               # ripgrep、shfmt、ShellCheck、Verible
├── payload/                     # 原始 Linux 发行包
└── manifest/                    # 版本、锁文件、SHA256 清单
~~~

启动脚本通过自身位置计算安装根目录，并设置 XDG_CONFIG_HOME、XDG_DATA_HOME、XDG_STATE_HOME、XDG_CACHE_HOME。不会把 Neovim 配置、插件或缓存写入 HOME。

runtime/commands 是该 Neovim 安装目录私有的命令目录，不是系统公共 bin。Tcl LSP 使用打包的 CPython 3.11.18 和 runtime/python-packages，不会调用 CentOS 系统 Python。

runtime/tools/bin 中的 Verible 是 Linux x86_64 静态构建；ShellCheck 使用上游 Linux x86_64 发布包。install.sh 在 CentOS 上解压并设置可执行权限。

## 语言支持

| 语言 / 文件 | 支持 |
|---|---|
| Python | Pyright：补全、诊断、跳转、引用、重命名 |
| Bash / Shell | bash-language-server；ShellCheck 诊断；shfmt 格式化 |
| Tcl / Tk | tclint / tclsp：诊断和语法错误提示；tclfmt 格式化 |
| SDC / XDC / UPF | 按 Tcl 处理，启用 tclsp 和 tclfmt |
| CSH / TCSH | Neovim 内置语法高亮和文件类型识别；不安装不成熟的通用 LSP |
| ICL / IJTAG | 仓库自带 Vim Syntax；.icl 自动识别；仅语法高亮，不需要 LSP |
| Verilog / SystemVerilog RTL | Verible LSP、Lint、Formatter；支持 .v、.vh、.sv、.svh |

### Tcl / EDA Tcl

tclsp 由独立 CPython 3.11.18 运行，包含 tclint、pygls 及其依赖。目标 CentOS 不需要预装 Python 3.10+。

tclint 支持通过 tclint.toml 定义 EDA 工具命令插件。不同 EDA 工具的命令集差异较大，建议在具体项目中配置自定义命令规格，避免把工具扩展命令误判为普通 Tcl 命令。

### RTL

Verible 提供 verible-verilog-ls、verible-verilog-lint 和 verible-verilog-format。跨文件符号导航建议在 RTL 项目根目录提供 verible.filelist，列出参与分析的源文件。

### ICL 与 CSH

ICL 只提供语法高亮，不做语义检查或 LSP。CSH/TCSH 同样使用 Neovim 自带语法文件，不额外引入服务端进程。

Pyright 仍然分析项目自己的 Python 环境。打包的 CPython 3.11.18 是 Tcl 工具的私有运行时，不会替换项目 .venv 或 CentOS 系统 Python.

## 常用插件

- nvim-lspconfig、nvim-cmp、LuaSnip、Catppuccin Mocha
- Telescope + plenary.nvim
- nvim-tree + nvim-web-devicons
- lualine、which-key
- gitsigns、Comment.nvim
- nvim-autopairs、nvim-surround
- conform.nvim

全文搜索依赖打包的 ripgrep。Git 差异显示依赖目标系统已有 Git；本项目不替换系统 Git。

## 默认主题与终端字体

- 默认主题为 Catppuccin Mocha，主题插件随离线包一起部署。
- 默认打包 **Maple Mono NF CN 7.9**，同时包含 Nerd Font 图标字形和中文字符，不再依赖系统另外安装 CJK 字体。
- 上游 MapleMono-NF-CN.zip 下载体积约 **152.1 MiB**，明显大于纯 Nerd Font 版本；这是完整中文字体覆盖带来的主要体积增加。最终离线包大小以构建输出为准。
- 注册字体后，在 GNOME Terminal / KDE Konsole 的 Profile / Appearance 中选择 Maple Mono NF CN。
- 如果 Neovim 是通过 SSH 在 Windows Terminal 中运行，字体必须安装并配置在 Windows 客户端；CentOS 端的字体包不会改变 Windows Terminal 的字体。

注册和移除字体：

~~~bash
sudo bash install-fonts.sh
# 在 GNOME Terminal / Konsole 的 Profile / Appearance 中选择 Maple Mono NF CN
sudo bash uninstall-fonts.sh
~~~

字体注册只在 /etc/fonts/conf.d 写入一个 Fontconfig 配置，让系统直接读取安装目录内的字体，不会把字体复制到 HOME。Neovim TUI 不能替终端模拟器选择字体。

## 完全离线边界

- CentOS 不访问 npm、GitHub、PyPI 或其他网络服务。
- 不使用 Mason、Lazy.nvim 在线安装或自动更新插件。
- 所有 npm 语言服务器、Python wheels、Neovim 插件和 POSIX 启动脚本都在 Windows 构建阶段准备。
- Windows 构建阶段通过固定版本的 uv 为 Linux x86_64 / CPython 3.11 解析和安装 Tcl 工具依赖；目标机器不需要 uv。
- Node.js、Neovim、CPython、ripgrep、shfmt、ShellCheck 和 Verible 的 Linux 目标文件在 Windows 侧下载原始归档，保留原始归档，在 CentOS 解压。
- Tcl/Tk 使用 tclint LSP；CSH/TCSH 使用 Neovim 内置语法；ICL 使用仓库自带 Vim Syntax。
- Verilog/SystemVerilog 使用 Verible。所有语言服务器和格式化工具都在指定安装目录内，不写入 HOME 或系统公共 bin。

## 完整性

构建包内 manifest/SHA256SUMS.txt 列出文件 SHA256。Node.js 归档在构建时使用 unofficial-builds 提供的 SHASUMS256.txt 校验；Neovim、CPython、uv、ShellCheck、Verible 和字体归档使用固定 SHA256 校验；ripgrep 和 shfmt 使用上游校验文件。ShellCheck 的 GPL-3.0 对应源码按固定 Git commit 一并放在 licenses/sources/。

## 限制

CentOS 7 已停止常规维护。Node.js glibc-217、CPython Linux 构建与 Neovim 旧 glibc 构建均属于兼容性方案，不应视为现代受支持发行版。该项目只保证构建目标是 CentOS 7 x86_64 / glibc 2.17，并通过目标机上的 install.sh、verify.sh 做最终验证。
