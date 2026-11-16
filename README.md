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

可选参数：

~~~powershell
.\build.ps1 -Clean
.\build.ps1 -OutputDirectory D:\Artifacts
~~~

## CentOS 7 部署

把构建产物复制到 CentOS 7，然后解压到你指定的独立目录。以下使用 /data/devtools/nvim 举例：

~~~bash
mkdir -p /data/devtools/nvim

tar -xzf nvim-centos7-x86_64-node22.23.5.tar.gz \
  -C /data/devtools/nvim

cd /data/devtools/nvim
bash install.sh
~~~

安装不需要 root，不会修改 /usr/bin、/usr/local/bin、系统 PATH 或用户 Home 下的 Neovim 配置。

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
| CSH / TCSH | Neovim 内置语法和文件类型识别；没有配置第三方 LSP |

Pyright 通过 Node.js 运行。目标机器仍需有可用的 Python 解释器，Pyright 才能分析项目环境和解释器依赖。

## 常用插件

- nvim-lspconfig、nvim-cmp、LuaSnip
- Telescope + plenary.nvim
- nvim-tree + nvim-web-devicons
- lualine、which-key
- gitsigns、Comment.nvim
- nvim-autopairs、nvim-surround
- conform.nvim

全文搜索依赖打包的 ripgrep。Git 差异显示依赖目标系统已有 Git；本项目不替换系统 Git。

## 完全离线边界

- CentOS 不访问 npm、GitHub 或其他网络服务。
- 不使用 Mason、Lazy.nvim 在线安装或自动更新插件。
- 所有 npm 语言服务器和插件在 Windows 构建时准备。
- Node.js、Neovim、ripgrep、shfmt 的 Linux 目标文件在 Windows 侧下载原始归档，保留原始归档，在 CentOS 解压。
- CSH/TCSH 当前提供语法识别，不宣称具备成熟 LSP 能力。

## 完整性

构建包内 manifest/SHA256SUMS.txt 列出文件 SHA256。Node.js 归档在构建时使用 unofficial-builds 提供的 SHASUMS256.txt 校验；Neovim 归档使用固定 SHA256 校验；ripgrep 和 shfmt 使用上游校验文件。

## 限制

CentOS 7 已停止常规维护。Node.js glibc-217 与 Neovim 旧 glibc 构建均属于兼容性方案，不应视为现代受支持发行版。该项目只保证构建目标是 CentOS 7 x86_64 / glibc 2.17，并通过目标机上的 install.sh、verify.sh 做最终验证。
