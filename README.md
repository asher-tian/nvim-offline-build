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

## 3. Python 虚拟环境

已集成 `venv-selector.nvim`，用于发现、选择并记住各项目的 Python 虚拟环境。离线包同时内置 `fd`，用于搜索解释器。

首次打开 Python 项目时：

~~~vim
:VenvSelect
~~~

也可以使用快捷键 `Space vs`。选择项目中的 `.venv` / `venv`，或 Poetry、Conda、Pipenv、Pyenv 等环境。选择结果按项目缓存；后续重新打开该项目的 Python 文件时会自动恢复，并同步给 Pyright。Lualine 状态栏会显示当前环境名称。

- `fd`、Telescope 和 Pyright 均随离线包提供。
- Neovim 新开终端会继承当前选中的虚拟环境。
- 虚拟环境缓存位于安装目录的 XDG cache 下，不写入 HOME。
- 每个项目首次选择一次即可；无需为虚拟环境单独修改 `pyrightconfig.json`。

项目特有的内部模块搜索路径仍可单独写在项目根目录的 `pyrightconfig.json`：

~~~json
{
  "extraPaths": [
    "code/python",
    "lib/tool"
  ]
}
~~~

## 4. ICL / PDL 自定义语法高亮

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

## 5. 字体安装（可选）

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
