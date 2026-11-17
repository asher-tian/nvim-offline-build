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

## 3. 字体安装（可选）

默认使用用户级安装，不需要 root：

~~~bash
cd /data/devtools/nvim
bash install-fonts.sh
~~~

字体文件始终保留在 fonts/maple-mono/，配置文件保存在安装目录的 config/fontconfig/。HOME 中只创建指向安装目录的 Fontconfig 配置软链接；如果系统不加载用户级 Fontconfig 配置，会回退到 ~/.fonts/nvim-offline-build 软链接。字体文件不会复制到 HOME。若 HOME 中还没有 Fontconfig 缓存目录，脚本会将 ~/.cache/fontconfig 链接到安装目录的 cache/fontconfig/；已有缓存目录或其他软链接不会被覆盖。

检查字体是否可用：

~~~bash
fc-list | grep -i 'Maple Mono NF CN'
fc-match 'Maple Mono NF CN'
~~~

然后在 GNOME Terminal 或 KDE Konsole 的 Profile / Appearance 中选择 Maple Mono NF CN，并重新打开终端。

如需为整台机器的所有用户注册字体（需要 root）：

~~~bash
sudo bash install-fonts.sh --system
~~~

卸载用户级注册：

~~~bash
bash uninstall-fonts.sh
~~~

卸载系统级注册：

~~~bash
sudo bash uninstall-fonts.sh --system
~~~

卸载只移除 Fontconfig 注册入口，不删除安装目录内的字体文件。

如果通过 SSH 在 Windows Terminal 中运行 Neovim，字体应安装并配置在 Windows 客户端；CentOS 上的字体安装不会改变 Windows Terminal 的字体。
