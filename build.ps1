[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$RefreshLocks,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "dist")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # PowerShell 7 may already use modern TLS defaults.
}

. (Join-Path $PSScriptRoot "scripts/common.ps1")

$versions = Get-Content (Join-Path $PSScriptRoot "versions.json") -Raw | ConvertFrom-Json
$nodeExpected = "v$($versions.builder.node)"
$npmExpected = $versions.builder.npm

Assert-Command "node"
Assert-Command "npm"
Assert-Command "git"
Assert-Command "tar.exe"

$nodeActual = (& node --version).Trim()
$npmActual = (& npm --version).Trim()

if ($nodeActual -ne $nodeExpected) {
    throw "Windows build Node.js must be $nodeExpected; current version is $nodeActual. Run mise install and activate the repository tool version."
}
if ($npmActual -ne $npmExpected) {
    throw "Windows build npm must be $npmExpected; current version is $npmActual."
}

Write-Host ""
Write-Host "Building CentOS 7 x86_64 Neovim offline bundle"
Write-Host "Builder Node: $nodeActual / npm $npmActual"
Write-Host "Target Node: $($versions.runtime.node.version)"
Write-Host ""

$repoRoot = $PSScriptRoot
$workRoot = Join-Path $repoRoot "work"
$bundleRoot = Join-Path $workRoot "bundle"
$npmWork = Join-Path $workRoot "npm"
$payloadRoot = Join-Path $bundleRoot "payload"

if ($Clean -and (Test-Path $workRoot)) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}
if (Test-Path $bundleRoot) {
    Remove-Item -LiteralPath $bundleRoot -Recurse -Force
}
if (Test-Path $npmWork) {
    Remove-Item -LiteralPath $npmWork -Recurse -Force
}

$directories = @(
    "config",
    "data",
    "state",
    "cache",
    "logs",
    "manifest",
    "payload",
    "runtime/neovim",
    "runtime/node",
    "runtime/npm",
    "runtime/npm/node_modules",
    "runtime/npm-global",
    "runtime/commands",
    "runtime/tools/bin"
)

foreach ($directory in $directories) {
    New-Item -ItemType Directory -Force -Path (Join-Path $bundleRoot $directory) | Out-Null
}
New-Item -ItemType Directory -Force -Path $npmWork | Out-Null

Copy-Item -Path (Join-Path $repoRoot "config/nvim") -Destination (Join-Path $bundleRoot "config") -Recurse -Force
Copy-Item -Path (Join-Path $repoRoot "templates/nvim") -Destination (Join-Path $bundleRoot "nvim") -Force
Copy-Item -Path (Join-Path $repoRoot "templates/install.sh") -Destination (Join-Path $bundleRoot "install.sh") -Force
Copy-Item -Path (Join-Path $repoRoot "templates/verify.sh") -Destination (Join-Path $bundleRoot "verify.sh") -Force
Copy-Item -Path (Join-Path $repoRoot "templates/npmrc") -Destination (Join-Path $bundleRoot "config/npmrc") -Force

# 1. Download target Linux binaries. Keep their original archives intact on Windows.
$nvim = $versions.runtime.neovim
$nvimArchive = Join-Path $payloadRoot $nvim.file
Invoke-Download -Url $nvim.url -Destination $nvimArchive
Assert-Sha256 -Path $nvimArchive -Expected $nvim.sha256

$node = $versions.runtime.node
$nodeArchive = Join-Path $payloadRoot $node.file
$nodeChecksums = Join-Path $payloadRoot "node-SHASUMS256.txt"
Invoke-Download -Url $node.url -Destination $nodeArchive
Invoke-Download -Url $node.checksumUrl -Destination $nodeChecksums
$nodeSha = Get-ChecksumFromFile -ChecksumFile $nodeChecksums -AssetName $node.file
Assert-Sha256 -Path $nodeArchive -Expected $nodeSha

# 2. Download portable Linux command-line tools used by the IDE.
$rg = $versions.tools.ripgrep
$rgArchive = Join-Path $payloadRoot $rg.file
Invoke-Download -Url $rg.url -Destination $rgArchive
Assert-Sha256 -Path $rgArchive -Expected $rg.sha256

$shfmt = $versions.tools.shfmt
$shfmtBinary = Join-Path $payloadRoot $shfmt.file
$shfmtChecksums = Join-Path $payloadRoot "shfmt-sha256sums.txt"
Invoke-Download -Url $shfmt.url -Destination $shfmtBinary
Invoke-Download -Url $shfmt.checksumUrl -Destination $shfmtChecksums
$shfmtSha = Get-ChecksumFromFile -ChecksumFile $shfmtChecksums -AssetName $shfmt.file
Assert-Sha256 -Path $shfmtBinary -Expected $shfmtSha

# 3. Install JavaScript LSP packages on Windows for the Linux target platform.
# These packages are JavaScript; Node itself is supplied by the Linux Node archive.
Copy-Item -LiteralPath (Join-Path $repoRoot "package.json") -Destination (Join-Path $npmWork "package.json") -Force
$npmLockSource = Join-Path $repoRoot "locks/npm/package-lock.json"
$npmLockDestination = Join-Path $npmWork "package-lock.json"

Push-Location $npmWork
try {
    if ((Test-Path $npmLockSource) -and (-not $RefreshLocks)) {
        Copy-Item -LiteralPath $npmLockSource -Destination $npmLockDestination -Force
        & npm ci --os=linux --cpu=x64 --no-bin-links --no-audit --no-fund --ignore-scripts
    } else {
        & npm install --save-exact --os=linux --cpu=x64 --no-bin-links --no-audit --no-fund --ignore-scripts
    }

    if ($LASTEXITCODE -ne 0) {
        throw "npm dependency installation failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot "locks/npm") | Out-Null
Copy-Item -LiteralPath $npmLockDestination -Destination $npmLockSource -Force
Copy-Item -LiteralPath (Join-Path $npmWork "package.json") -Destination (Join-Path $bundleRoot "runtime/npm/package.json") -Force
Copy-Item -LiteralPath $npmLockDestination -Destination (Join-Path $bundleRoot "runtime/npm/package-lock.json") -Force
$bundleNodeModules = Join-Path $bundleRoot "runtime/npm/node_modules"
New-Item -ItemType Directory -Force -Path $bundleNodeModules | Out-Null
Copy-Item -Path (Join-Path $npmWork "node_modules/*") -Destination $bundleNodeModules -Recurse -Force

# Generate POSIX command shims from the installed npm packages' bin metadata.
$nodeModules = Join-Path $npmWork "node_modules"
$npmManifest = Get-Content (Join-Path $npmWork "package.json") -Raw | ConvertFrom-Json
foreach ($dependency in $npmManifest.dependencies.PSObject.Properties) {
    $packageName = $dependency.Name
    $packagePath = Join-Path $nodeModules ($packageName -replace "/", "\")
    $packageJsonPath = Join-Path $packagePath "package.json"

    if (-not (Test-Path $packageJsonPath)) {
        throw "Installed npm package metadata is missing: $packageName"
    }

    $packageMetadata = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
    if (-not $packageMetadata.bin) {
        continue
    }

    $binEntries = @()
    if ($packageMetadata.bin -is [string]) {
        $commandName = ($packageName -split "/")[-1]
        $binEntries += [pscustomobject]@{
            Name = $commandName
            Target = [string]$packageMetadata.bin
        }
    } else {
        foreach ($binEntry in $packageMetadata.bin.PSObject.Properties) {
            $binEntries += [pscustomobject]@{
                Name = $binEntry.Name
                Target = [string]$binEntry.Value
            }
        }
    }

    foreach ($binEntry in $binEntries) {
        if ($binEntry.Name -notmatch '^[A-Za-z0-9._-]+$') {
            throw "Unsupported npm command name: $($binEntry.Name)"
        }

        $target = $binEntry.Target -replace '^\./', ''
        $target = $target -replace '\\', '/'
        $packageRelative = $packageName -replace '\\', '/'
        $shimPath = Join-Path $bundleRoot ("runtime/commands/" + $binEntry.Name)

        $shim = @'
#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
exec "$ROOT/runtime/node/bin/node" "$ROOT/runtime/npm/node_modules/__PACKAGE__/__TARGET__" "$@"
'@
        $shim = $shim.Replace("__PACKAGE__", $packageRelative).Replace("__TARGET__", $target)
        Write-Utf8Lf -Path $shimPath -Content $shim
    }
}

# 4. Fetch plugins. First build resolves branch refs and writes a lock file.
# Subsequent builds fetch the exact commits from that lock file.
$pluginManifest = Get-Content (Join-Path $repoRoot "plugins.json") -Raw | ConvertFrom-Json
$pluginLockPath = Join-Path $repoRoot "locks/plugins.lock.json"
$oldPluginLock = $null

if ((Test-Path $pluginLockPath) -and (-not $RefreshLocks)) {
    $oldPluginLock = Get-Content $pluginLockPath -Raw | ConvertFrom-Json
}

$pluginRoot = Join-Path $bundleRoot "data/nvim/site/pack/offline/start"
$resolvedPlugins = @()

foreach ($plugin in $pluginManifest.plugins) {
    $lockedPlugin = $null
    if ($oldPluginLock -and $oldPluginLock.plugins) {
        $lockedPlugin = $oldPluginLock.plugins |
            Where-Object { $_.name -eq $plugin.name } |
            Select-Object -First 1
    }

    $destination = Join-Path $pluginRoot $plugin.name
    New-Item -ItemType Directory -Force -Path $destination | Out-Null

    & git -C $destination init
    if ($LASTEXITCODE -ne 0) { throw "git init failed for plugin $($plugin.name)" }
    & git -C $destination config core.autocrlf false
    & git -C $destination remote add origin $plugin.repo
    if ($LASTEXITCODE -ne 0) { throw "git remote add failed for plugin $($plugin.name)" }

    if ($lockedPlugin -and $lockedPlugin.commit) {
        $fetchRef = [string]$lockedPlugin.commit
    } else {
        $fetchRef = "refs/heads/$($plugin.ref)"
    }

    Write-Host "Plugin: $($plugin.name) [$fetchRef]"
    & git -C $destination fetch --depth 1 origin $fetchRef
    if ($LASTEXITCODE -ne 0) {
        throw "git fetch failed for plugin $($plugin.name), ref $fetchRef"
    }

    & git -C $destination checkout --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed for plugin $($plugin.name)" }

    $commit = (& git -C $destination rev-parse HEAD).Trim()
    if ($lockedPlugin -and $lockedPlugin.commit -and $commit -ne $lockedPlugin.commit) {
        throw "Plugin lock mismatch for $($plugin.name): expected $($lockedPlugin.commit), got $commit"
    }

    Remove-Item -LiteralPath (Join-Path $destination ".git") -Recurse -Force

    $resolvedPlugins += [pscustomobject]@{
        name = $plugin.name
        repo = $plugin.repo
        ref = $plugin.ref
        commit = $commit
    }
}

$pluginLock = [pscustomobject]@{
    schemaVersion = 1
    plugins = $resolvedPlugins
}
New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot "locks") | Out-Null
Write-JsonNoBom -Path $pluginLockPath -Value $pluginLock

# 5. Copy manifests and create a build record.
Copy-Item -LiteralPath (Join-Path $repoRoot "versions.json") -Destination (Join-Path $bundleRoot "manifest/versions.json") -Force
Copy-Item -LiteralPath $pluginLockPath -Destination (Join-Path $bundleRoot "manifest/plugins.lock.json") -Force
Copy-Item -LiteralPath $npmLockSource -Destination (Join-Path $bundleRoot "manifest/npm-package-lock.json") -Force

$buildInfo = @"
Target: CentOS 7 x86_64
Minimum glibc: 2.17
Neovim: $($versions.runtime.neovim.version) (unsupported glibc-2.17 build)
Node.js: $($versions.runtime.node.version) (linux-x64-glibc-217)
npm builder: $npmActual
Built at: $([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"))
"@
Write-Utf8Lf -Path (Join-Path $bundleRoot "manifest/BUILD-INFO.txt") -Content $buildInfo

# SHA256SUMS is generated after all payload, runtime, config and manifest files exist.
$checksumLines = @()
Get-ChildItem -LiteralPath $bundleRoot -Recurse -File |
    Where-Object { $_.FullName -ne (Join-Path $bundleRoot "manifest/SHA256SUMS.txt") } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($bundleRoot.Length + 1).Replace("\", "/")
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $checksumLines += "$hash  $relative"
    }

Write-Utf8Lf -Path (Join-Path $bundleRoot "manifest/SHA256SUMS.txt") -Content ([string]::Join([Environment]::NewLine, $checksumLines))

# 6. Package the bundle. The archive contains the contents of the bundle root,
# so it can be extracted directly into the chosen installation directory.
$outputFullPath = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null
$archivePath = Join-Path $outputFullPath "nvim-centos7-x86_64-node22.23.5.tar.gz"

if (Test-Path $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

& tar.exe -czf $archivePath -C $bundleRoot .
if ($LASTEXITCODE -ne 0) {
    throw "tar.exe failed to create the offline bundle."
}

& tar.exe -tzf $archivePath | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Generated archive failed tar integrity listing."
}

$archiveSize = [Math]::Round((Get-Item $archivePath).Length / 1MB, 2)
Write-Host ""
Write-Host "Build completed."
Write-Host "Archive: $archivePath"
Write-Host "Size: $archiveSize MB"
Write-Host ""
Write-Host "First build creates locks/npm/package-lock.json and locks/plugins.lock.json."
Write-Host "Commit both lock files to make subsequent builds reproducible."
