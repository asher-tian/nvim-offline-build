# nvim-offline-build

面向 CentOS 7 x86_64 的 Neovim 离线 IDE 构建工程。**只需要 Windows + PowerShell，不需要 WSL2、虚拟机、Docker 或 Linux 构建环境。**

构建产物包含 Linux 目标程序、Node.js 运行时、LSP、Neovim 插件、配置和初始化脚本。CentOS 7 不需要预装 Node.js/npm，也不需要联网。

## 目标环境

- CentOS 7 x86_64
- glibc 2.17 或更新版本
- 安装目录由部署者指定，例如 /data/devtools/nvim
- Node.js **22.23.5**（固定版本，linux-x64-glibc-217 构建）
- Neovim 0.12.5（glibc 2.17 兼容的 unsupported build）

Node.js glibc-217 构建来自 nodejs/unofficial-builds，属于社区维护的非官方构建，保障等级低于 Node.js 官方标准 Linux 构建。Neovim 也使用官方列出的旧 glibc unsupported build。请在目标 CentOS 机器上执行安装和验证脚本。

## Windows 构建前提

- Windows 10/11 x86_64
- PowerShell 5.1 或 PowerShell 7
- Git for Windows
- mise（推荐）或已安装 Node.js 22.23.5
- npm 10.9.9
- Windows 自带 tar.exe

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

仓库已经提交 locks/plugins.lock.json，固定了第一版插件 Git commit。首次构建会生成 locks/npm/package-lock.json，记录 npm 依赖的完整版本树。

**首次构建后应将 locks/npm/package-lock.json 提交到 Git。** 后续构建使用锁定的插件 commit 和 npm package-lock，不会自动追随上游更新。

需要主动升级插件或 npm 依赖时，执行：

~~~powershell
.\build.ps1 -RefreshLocks
~~~

检查 locks/plugins.lock.json 和 locks/npm/package-lock.json 的差异并提交后，再发布新的离线包。不要在日常构建中使用 -RefreshLocks。

## 增量构建与缓存

构建缓存保存在仓库根目录的 `cache/`，不会打进 CentOS 离线包，也已经加入 .gitignore：

~~~text
cache/
├── downloads/             # Neovim、Node.js、ripgrep、shfmt 原始文件
├── npm-downloads/         # npm 下载的包缓存
├── npm-installs/           # 按 package.json / package-lock 锁定的 node_modules
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
- 插件按锁定 commit 查找快照；命中后不访问 GitHub。快照不存在时才使用本地 Git 对象缓存，必要时才 fetch。
- 配置、启动脚本、manifest 和最终离线包每次重新组装，确保仓库中的最新修改进入产物。

首次启用增量构建时，脚本会优先迁移旧版 `work/bundle/payload`、`work/npm` 和 `work/bundle/data/.../start`；如果旧工作目录不完整，则尝试从 `dist/` 中上一次成功生成的 tar.gz 提取缓存。迁移后的二进制仍会重新校验 SHA256，npm 迁移会核对 package.json / package-lock，插件快照按旧构建 manifest 中的 commit 保存。

参数：

~~~powershell
# 默认：增量构建，复用 cache/
.\build.ps1

# 清除 work/ 和 cache/，重新下载、安装和构建；保留锁文件及 dist/
.\build.ps1 -Clean

# 主动更新插件分支和 npm 依赖锁文件；仍复用已有下载缓存
.\build.ps1 -RefreshLocks

# 指定最终产物目录
.\build.ps1 -OutputDirectory D:\Artifacts
~~~

`-Clean` 与 `-RefreshLocks` 可以组合使用。正常修改 Lua 配置、Shell 脚本或构建模板时，不需要使用这两个参数。修改 `package.json` 中的依赖版本时，应执行 `-RefreshLocks` 更新 npm 锁文件；之后提交更新后的 `locks/npm/package-lock.json`。

## CentOS 7 部署

把构建产物复制到 CentOS 7，然后解压到你指定的独立目录。以下使用 /data/devtools/nvim 举例：

~~~bash
mkdir -p /data/devtools/nvim

tar -xzf nvim-centos7-x86_64-node22.23.5.tar.gz \
  -C /data/devtools/nvim

cd /data/devtools/nvim
bash install.sh

# 可选：将安装目录内的 Maple Mono NF 注册到系统 Fontconfig（需要 root）
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
│   ├── nvim/                    # Neovim 配置
│   └── npmrc                    # 私有 npm 配置
├── fonts/maple-mono/            # Maple Mono NF 静态 TTF + OFL license
├── install-fonts.sh             # 可选：注册系统字体
└── uninstall-fonts.sh           # 可选：移除字体注册
├── data/nvim/site/pack/          # 插件
├── state/nvim/                  # undo、swap、backup 等状态
├── cache/                       # Neovim、Pyright、npm、临时缓存
├── logs/
├── runtime/
│   ├── neovim/                  # Linux Neovim 程序
│   ├── node/                    # Linux Node.js 22.23.5 + npm
│   ├── npm/node_modules/        # 离线 LSP 和 formatter 依赖
│   ├── commands/                # LSP / formatter POSIX 启动脚本
│   ├── npm-global/
│   └── tools/bin/               # ripgrep、shfmt
├── payload/                     # 原始 Linux 发行包
└── manifest/                    # 版本、锁文件、SHA256 清单
~~~

启动脚本通过自身位置计算安装根目录，并设置 XDG_CONFIG_HOME、XDG_DATA_HOME、XDG_STATE_HOME、XDG_CACHE_HOME。不会把 Neovim 配置、插件或缓存写入 HOME。

runtime/commands 是该 Neovim 安装目录私有的命令目录，不是系统公共 bin。

## 语言支持

| 语言 | 支持 |
|---|---|
| Python | Pyright：补全、诊断、跳转、引用、重命名 |
| Bash | bash-language-server；shfmt 格式化 |
| HTML | vscode-html-language-server |
| CSS | vscode-css-language-server |
| JavaScript | TypeScript Language Server |
| TypeScript | TypeScript Language Server |
| JSON | vscode-json-language-server |
| Tcl / Tk | Neovim 内置 Tcl 语法高亮；额外识别 `.tm`、`.itcl`、`.tk` 扩展名；没有配置第三方 LSP |\n| CSH / TCSH | Neovim 内置语法和文件类型识别；没有配置第三方 LSP |

Pyright 通过 Node.js 运行。目标机器仍需有可用的 Python 解释器，Pyright 才能分析项目环境和解释器依赖。

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
- 默认包含 Maple Mono NF 字体文件，包含 Nerd Font 图标字形；字体文件和 OFL license 均放在安装目录内。
- 注册字体后，GNOME Terminal / KDE Konsole 仍需在终端配置中手动选择 `Maple Mono NF`。
- Maple Mono NF 本身不内置完整 CJK 字形；中文、日文由系统已有的 CJK 字体 fallback。若目标系统没有 CJK 字体，需要另外准备 Maple Mono NF CN（体积明显更大）。
- 如果 Neovim 是通过 SSH 在 Windows Terminal 中运行，字体必须安装并配置在 Windows 客户端；CentOS 端的字体包不会改变 Windows Terminal 的字体。

注册和移除字体：

~~~bash
sudo bash install-fonts.sh
# 在 GNOME Terminal / Konsole 的 Profile / Appearance 中选择 Maple Mono NF
sudo bash uninstall-fonts.sh
~~~

字体只影响终端渲染，不会由 Neovim 自身设置。Neovim TUI 不能替终端模拟器选择字体。

## 完全离线边界

- CentOS 不访问 npm、GitHub 或其他网络服务。
- 不使用 Mason、Lazy.nvim 在线安装或自动更新插件。
- 所有 npm 语言服务器和插件在 Windows 构建时准备。
- Node.js、Neovim、ripgrep、shfmt 的 Linux 目标文件在 Windows 侧下载原始归档，保留原始归档，在 CentOS 解压。
- Tcl/Tk 使用 Neovim 自带 Tcl 语法高亮；额外识别 .tm、.itcl、.tk，并设置 4 空格缩进。它不是 Tcl LSP。
- CSH/TCSH 当前提供语法识别，不宣称具备成熟 LSP 能力。

## 完整性

构建包内 manifest/SHA256SUMS.txt 列出文件 SHA256。Node.js 归档在构建时使用 unofficial-builds 提供的 SHASUMS256.txt 校验；Neovim 归档使用固定 SHA256 校验；ripgrep 和 shfmt 使用上游校验文件。

## 限制

CentOS 7 已停止常规维护。Node.js glibc-217 与 Neovim 旧 glibc 构建均属于兼容性方案，不应视为现代受支持发行版。该项目只保证构建目标是 CentOS 7 x86_64 / glibc 2.17，并通过目标机上的 install.sh、verify.sh 做最终验证。
