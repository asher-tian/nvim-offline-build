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

$repoRoot = $PSScriptRoot
$workRoot = Join-Path $repoRoot "work"
$bundleRoot = Join-Path $workRoot "bundle"
$npmWork = Join-Path $workRoot "npm"
$payloadRoot = Join-Path $bundleRoot "payload"

# Persistent caches are deliberately outside work/. A normal build recreates
# the bundle but keeps downloads, npm packages and Git objects for reuse.
$cacheRoot = Join-Path $repoRoot "cache"
$downloadCache = Join-Path $cacheRoot "downloads"
$npmDownloadCache = Join-Path $cacheRoot "npm-downloads"
$npmInstallCache = Join-Path $cacheRoot "npm-installs"
$pluginGitCacheRoot = Join-Path $cacheRoot "plugin-git"
$pluginSnapshotRoot = Join-Path $cacheRoot "plugin-snapshots"

if ($Clean) {
    if (Test-Path $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
    if (Test-Path $cacheRoot) {
        Remove-Item -LiteralPath $cacheRoot -Recurse -Force
    }
}

foreach ($directory in @($downloadCache, $npmDownloadCache, $npmInstallCache, $pluginGitCacheRoot, $pluginSnapshotRoot)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$outputFullPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$archiveName = "nvim-centos7-x86_64-node$($versions.runtime.node.version).tar.gz"

# One-time migration: reuse artifacts produced by the previous build layout.
# Prefer the previous work tree; if it is incomplete, seed the cache from the
# last successfully generated archive in OutputDirectory.
if (-not $Clean) {
    $legacyBundleRoot = Join-Path $workRoot "bundle"
    $legacyNpmRoot = Join-Path $workRoot "npm"
    $legacyBundleLock = Join-Path $legacyBundleRoot "manifest/plugins.lock.json"

    if (-not (Test-Path $legacyBundleLock)) {
        $legacyArchive = Join-Path $outputFullPath $archiveName
        if (Test-Path $legacyArchive) {
            $legacyExtractRoot = Join-Path $workRoot "legacy-cache-seed"
            if (Test-Path $legacyExtractRoot) {
                Remove-Item -LiteralPath $legacyExtractRoot -Recurse -Force
            }
            New-Item -ItemType Directory -Force -Path $legacyExtractRoot | Out-Null
            Write-Host "Seeding build cache from previous archive: $legacyArchive"
            & tar.exe -xzf $legacyArchive -C $legacyExtractRoot
            if ($LASTEXITCODE -eq 0) {
                $legacyBundleRoot = $legacyExtractRoot
            } else {
                Write-Warning "Could not extract the previous archive for cache migration; a normal build will populate the cache."
            }
        }
    }

    $legacyNpmComplete = (
        (Test-Path (Join-Path $legacyNpmRoot "node_modules")) -and
        (Test-Path (Join-Path $legacyNpmRoot "package.json")) -and
        (Test-Path (Join-Path $legacyNpmRoot "package-lock.json"))
    )
    if (-not $legacyNpmComplete) {
        $bundleNpmCandidate = Join-Path $legacyBundleRoot "runtime/npm"
        $bundleNpmComplete = (
            (Test-Path (Join-Path $bundleNpmCandidate "node_modules")) -and
            (Test-Path (Join-Path $bundleNpmCandidate "package.json")) -and
            (Test-Path (Join-Path $bundleNpmCandidate "package-lock.json"))
        )
        if ($bundleNpmComplete) {
            $legacyNpmRoot = $bundleNpmCandidate
        }
    }

    $legacyPayload = Join-Path $legacyBundleRoot "payload"
    if (Test-Path $legacyPayload) {
        foreach ($legacyFile in Get-ChildItem -LiteralPath $legacyPayload -File -Force) {
            $cachedFile = Join-Path $downloadCache $legacyFile.Name
            if (-not (Test-Path $cachedFile)) {
                Copy-Item -LiteralPath $legacyFile.FullName -Destination $cachedFile -Force
                Write-Host "Migrated previous download into cache: $($legacyFile.Name)"
            }
        }

        $legacyNodeChecksums = Join-Path $legacyPayload "node-SHASUMS256.txt"
        if ((Test-Path $legacyNodeChecksums) -and (-not (Test-Path (Join-Path $downloadCache ("node-" + $versions.runtime.node.version + "-SHASUMS256.txt"))))) {
            Copy-Item -LiteralPath $legacyNodeChecksums -Destination (Join-Path $downloadCache ("node-" + $versions.runtime.node.version + "-SHASUMS256.txt")) -Force
        }

        $legacyShfmtChecksums = Join-Path $legacyPayload "shfmt-sha256sums.txt"
        if ((Test-Path $legacyShfmtChecksums) -and (-not (Test-Path (Join-Path $downloadCache ("shfmt-" + $versions.tools.shfmt.version + "-sha256sums.txt"))))) {
            Copy-Item -LiteralPath $legacyShfmtChecksums -Destination (Join-Path $downloadCache ("shfmt-" + $versions.tools.shfmt.version + "-sha256sums.txt")) -Force
        }
    }

    # Migrate the previous npm installation into the new lock-keyed cache.
    $legacyNpmRoot = Join-Path $workRoot "npm"
    $legacyNodeModules = Join-Path $legacyNpmRoot "node_modules"
    $legacyPackageJson = Join-Path $repoRoot "package.json"
    $legacyPackageJsonInWork = Join-Path $legacyNpmRoot "package.json"
    $legacyLockSource = Join-Path $repoRoot "locks/npm/package-lock.json"
    $legacyLockInWork = Join-Path $legacyNpmRoot "package-lock.json"

    if ((Test-Path $legacyNodeModules) -and (Test-Path $legacyPackageJsonInWork) -and (Test-Path $legacyLockInWork)) {
        if (-not (Test-Path $legacyLockSource)) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $legacyLockSource) | Out-Null
            Copy-Item -LiteralPath $legacyLockInWork -Destination $legacyLockSource -Force
        }

        $oldPackageHash = (Get-FileHash -LiteralPath $legacyPackageJsonInWork -Algorithm SHA256).Hash.ToLowerInvariant()
        $currentPackageHash = (Get-FileHash -LiteralPath $legacyPackageJson -Algorithm SHA256).Hash.ToLowerInvariant()
        $oldLockHash = (Get-FileHash -LiteralPath $legacyLockInWork -Algorithm SHA256).Hash.ToLowerInvariant()
        $currentLockHash = (Get-FileHash -LiteralPath $legacyLockSource -Algorithm SHA256).Hash.ToLowerInvariant()
        $legacyDependenciesPresent = $true
        $legacyManifest = Get-Content -LiteralPath $legacyPackageJsonInWork -Raw | ConvertFrom-Json

        foreach ($legacyDependency in $legacyManifest.dependencies.PSObject.Properties) {
            $legacyDependencyPath = Join-Path $legacyNodeModules ($legacyDependency.Name -replace "/", "\")
            if (-not (Test-Path (Join-Path $legacyDependencyPath "package.json"))) {
                $legacyDependenciesPresent = $false
                break
            }
        }

        if (($oldPackageHash -eq $currentPackageHash) -and ($oldLockHash -eq $currentLockHash) -and $legacyDependenciesPresent) {
            $legacyNpmKey = Get-TextSha256 -Text ($currentPackageHash + "|" + $currentLockHash + "|" + $npmActual + "|linux-x64")
            $legacyNpmEntry = Join-Path $npmInstallCache $legacyNpmKey
            $legacyNpmMarker = Join-Path $legacyNpmEntry "cache-key.txt"

            if (-not (Test-Path $legacyNpmMarker)) {
                if (Test-Path $legacyNpmEntry) {
                    Remove-Item -LiteralPath $legacyNpmEntry -Recurse -Force
                }
                New-Item -ItemType Directory -Force -Path $legacyNpmEntry | Out-Null
                Copy-Item -LiteralPath $legacyNodeModules -Destination $legacyNpmEntry -Recurse -Force
                Write-Utf8Lf -Path $legacyNpmMarker -Content $legacyNpmKey
                Write-Host "Migrated previous npm node_modules into cache: $legacyNpmKey"
            }
        } else {
            Write-Host "Skipped legacy npm migration because package files changed or a direct dependency is missing."
        }
    }

    # Previous bundles already contained plugin trees checked out at the
    # commits recorded in locks/plugins.lock.json. Preserve them as snapshots.
    $legacyPluginRoot = Join-Path $legacyBundleRoot "data/nvim/site/pack/offline/start"
    $legacyPluginLock = Join-Path $legacyBundleRoot "manifest/plugins.lock.json"
    if ((Test-Path $legacyPluginRoot) -and (Test-Path $legacyPluginLock)) {
        $legacyPluginEntries = (Get-Content -LiteralPath $legacyPluginLock -Raw | ConvertFrom-Json).plugins
        foreach ($legacyPlugin in $legacyPluginEntries) {
            $legacyPluginSource = Join-Path $legacyPluginRoot $legacyPlugin.name
            $legacySnapshotParent = Join-Path $pluginSnapshotRoot $legacyPlugin.name
            $legacySnapshot = Join-Path $legacySnapshotParent $legacyPlugin.commit
            $legacySnapshotMarker = "$legacySnapshot.complete"

            if ((Test-Path $legacyPluginSource) -and (-not (Test-Path $legacySnapshotMarker))) {
                if (Test-Path $legacySnapshot) {
                    Remove-Item -LiteralPath $legacySnapshot -Recurse -Force
                }
                New-Item -ItemType Directory -Force -Path $legacySnapshotParent | Out-Null
                Copy-Item -LiteralPath $legacyPluginSource -Destination $legacySnapshot -Recurse -Force
                Write-Utf8Lf -Path $legacySnapshotMarker -Content $legacyPlugin.commit
                Write-Host "Migrated previous plugin snapshot: $($legacyPlugin.name) [$($legacyPlugin.commit)]"
            }
        }
    }
}

# work/ is disposable. Recreate it after attempting the one-time cache migration.
if (Test-Path $workRoot) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $bundleRoot | Out-Null

Write-Host ""
Write-Host "Building CentOS 7 x86_64 Neovim offline bundle"
Write-Host "Builder Node: $nodeActual / npm $npmActual"
Write-Host "Target Node: $($versions.runtime.node.version)"
Write-Host "Persistent cache: $cacheRoot"
if ($Clean) {
    Write-Host "Cache mode: clean rebuild"
} else {
    Write-Host "Cache mode: reuse verified downloads and dependencies"
}
Write-Host ""

$directories = @(
    "config",
    "data",
    "state",
    "cache",
    "logs",
    "manifest",
    "payload",
    "fonts/maple-mono",
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
Copy-Item -Path (Join-Path $repoRoot "templates/install-fonts.sh") -Destination (Join-Path $bundleRoot "install-fonts.sh") -Force
Copy-Item -Path (Join-Path $repoRoot "templates/uninstall-fonts.sh") -Destination (Join-Path $bundleRoot "uninstall-fonts.sh") -Force
Copy-Item -Path (Join-Path $repoRoot "templates/npmrc") -Destination (Join-Path $bundleRoot "config/npmrc") -Force

# 1. Download Linux runtime archives into the persistent cache.
# Existing files are reused only when their expected SHA256 matches.
$nvim = $versions.runtime.neovim
$nvimCached = Join-Path $downloadCache $nvim.file
Invoke-Download -Url $nvim.url -Destination $nvimCached -ExpectedSha256 $nvim.sha256
Assert-Sha256 -Path $nvimCached -Expected $nvim.sha256
Copy-Item -LiteralPath $nvimCached -Destination (Join-Path $payloadRoot $nvim.file) -Force

$node = $versions.runtime.node
$nodeChecksumsCached = Join-Path $downloadCache ("node-" + $node.version + "-SHASUMS256.txt")
Invoke-Download -Url $node.checksumUrl -Destination $nodeChecksumsCached
$nodeSha = Get-ChecksumFromFile -ChecksumFile $nodeChecksumsCached -AssetName $node.file
$nodeCached = Join-Path $downloadCache $node.file
Invoke-Download -Url $node.url -Destination $nodeCached -ExpectedSha256 $nodeSha
Assert-Sha256 -Path $nodeCached -Expected $nodeSha
Copy-Item -LiteralPath $nodeCached -Destination (Join-Path $payloadRoot $node.file) -Force
Copy-Item -LiteralPath $nodeChecksumsCached -Destination (Join-Path $payloadRoot "node-SHASUMS256.txt") -Force

# 2. Cache portable Linux command-line tools.
$rg = $versions.tools.ripgrep
$rgCached = Join-Path $downloadCache $rg.file
Invoke-Download -Url $rg.url -Destination $rgCached -ExpectedSha256 $rg.sha256
Assert-Sha256 -Path $rgCached -Expected $rg.sha256
Copy-Item -LiteralPath $rgCached -Destination (Join-Path $payloadRoot $rg.file) -Force

$shfmt = $versions.tools.shfmt
$shfmtChecksumsCached = Join-Path $downloadCache ("shfmt-" + $shfmt.version + "-sha256sums.txt")
Invoke-Download -Url $shfmt.checksumUrl -Destination $shfmtChecksumsCached
$shfmtSha = Get-ChecksumFromFile -ChecksumFile $shfmtChecksumsCached -AssetName $shfmt.file
$shfmtCached = Join-Path $downloadCache $shfmt.file
Invoke-Download -Url $shfmt.url -Destination $shfmtCached -ExpectedSha256 $shfmtSha
Assert-Sha256 -Path $shfmtCached -Expected $shfmtSha
Copy-Item -LiteralPath $shfmtCached -Destination (Join-Path $payloadRoot $shfmt.file) -Force
Copy-Item -LiteralPath $shfmtChecksumsCached -Destination (Join-Path $payloadRoot "shfmt-sha256sums.txt") -Force

# 2.1. Bundle Maple Mono Nerd Font for terminal icon glyphs.
# Download and verify the upstream checksum before extracting static TTF files.
$font = $versions.fonts.mapleMonoNf
$fontChecksumCached = Join-Path $downloadCache ("maple-mono-nf-" + $font.version + ".sha256")
Invoke-Download -Url $font.checksumUrl -Destination $fontChecksumCached
$fontSha = (Get-Content -LiteralPath $fontChecksumCached -Raw).Trim()
if ($fontSha -notmatch '^[0-9a-fA-F]{64}
# The npm download cache stores tarballs; npm-install cache stores a complete
# node_modules tree keyed by package.json + package-lock + npm + target platform.
$packageJsonSource = Join-Path $repoRoot "package.json"
$npmLockSource = Join-Path $repoRoot "locks/npm/package-lock.json"
$npmLockDestination = Join-Path $npmWork "package-lock.json"
$npmPackageDestination = Join-Path $npmWork "package.json"

Copy-Item -LiteralPath $packageJsonSource -Destination $npmPackageDestination -Force
$npmManifest = Get-Content -LiteralPath $npmPackageDestination -Raw | ConvertFrom-Json

$useExistingLock = (Test-Path $npmLockSource) -and (-not $RefreshLocks)
if ($useExistingLock) {
    Copy-Item -LiteralPath $npmLockSource -Destination $npmLockDestination -Force
}

$npmInstallEntry = $null
$npmCacheHit = $false

if ($useExistingLock) {
    $packageHash = (Get-FileHash -LiteralPath $npmPackageDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $lockHash = (Get-FileHash -LiteralPath $npmLockDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $npmCacheKey = Get-TextSha256 -Text ($packageHash + "|" + $lockHash + "|" + $npmActual + "|linux-x64")
    $npmInstallEntry = Join-Path $npmInstallCache $npmCacheKey
    $cachedNodeModules = Join-Path $npmInstallEntry "node_modules"
    $cacheMarker = Join-Path $npmInstallEntry "cache-key.txt"

    if ((Test-Path $cachedNodeModules) -and (Test-Path $cacheMarker)) {
        $markerValue = (Get-Content -LiteralPath $cacheMarker -Raw).Trim()
        if ($markerValue -eq $npmCacheKey) {
            $npmCacheHit = $true
            Write-Host "npm dependency cache hit: $npmCacheKey"
        }
    }
}

if (-not $npmCacheHit) {
    Push-Location $npmWork
    try {
        if ($useExistingLock) {
            Write-Host "Installing npm dependencies from package-lock.json (using persistent npm download cache)."
            & npm ci --os=linux --cpu=x64 --no-bin-links --no-audit --no-fund --ignore-scripts --cache $npmDownloadCache --prefer-offline
        } else {
            Write-Host "Resolving npm dependencies and updating package-lock.json."
            $npmRefreshPreference = "--prefer-offline"
            if ($RefreshLocks) {
                $npmRefreshPreference = "--prefer-online"
            }
            & npm install --save-exact --os=linux --cpu=x64 --no-bin-links --no-audit --no-fund --ignore-scripts --cache $npmDownloadCache $npmRefreshPreference
        }

        if ($LASTEXITCODE -ne 0) {
            throw "npm dependency installation failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $npmLockDestination)) {
        throw "npm did not generate package-lock.json."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $npmLockSource) | Out-Null
    Copy-Item -LiteralPath $npmLockDestination -Destination $npmLockSource -Force

    $packageHash = (Get-FileHash -LiteralPath $npmPackageDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $lockHash = (Get-FileHash -LiteralPath $npmLockDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $npmCacheKey = Get-TextSha256 -Text ($packageHash + "|" + $lockHash + "|" + $npmActual + "|linux-x64")
    $npmInstallEntry = Join-Path $npmInstallCache $npmCacheKey
    $cachedNodeModules = Join-Path $npmInstallEntry "node_modules"
    $cacheMarker = Join-Path $npmInstallEntry "cache-key.txt"

    $npmEntryAlreadyCached = $false
    if ((Test-Path $cachedNodeModules) -and (Test-Path $cacheMarker)) {
        $npmEntryAlreadyCached = ((Get-Content -LiteralPath $cacheMarker -Raw).Trim() -eq $npmCacheKey)
    }

    if ($npmEntryAlreadyCached) {
        Write-Host "npm dependency cache already contains this exact lock; reusing cached node_modules."
    } else {
        if (Test-Path $npmInstallEntry) {
            Remove-Item -LiteralPath $npmInstallEntry -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $npmInstallEntry | Out-Null
        Copy-Item -LiteralPath (Join-Path $npmWork "node_modules") -Destination $npmInstallEntry -Recurse -Force
        Write-Utf8Lf -Path $cacheMarker -Content $npmCacheKey
        Write-Host "Saved npm dependency cache: $npmCacheKey"
    }
}

Copy-Item -LiteralPath $npmPackageDestination -Destination (Join-Path $bundleRoot "runtime/npm/package.json") -Force
Copy-Item -LiteralPath $npmLockDestination -Destination (Join-Path $bundleRoot "runtime/npm/package-lock.json") -Force
$bundleNpmRoot = Join-Path $bundleRoot "runtime/npm"
Copy-Item -LiteralPath (Join-Path $npmInstallEntry "node_modules") -Destination $bundleNpmRoot -Recurse -Force
$nodeModules = Join-Path $npmInstallEntry "node_modules"

# Generate POSIX command shims from npm package bin metadata.
foreach ($dependency in $npmManifest.dependencies.PSObject.Properties) {
    $packageName = $dependency.Name
    $packagePath = Join-Path $nodeModules ($packageName -replace "/", "\")
    $packageJsonPath = Join-Path $packagePath "package.json"

    if (-not (Test-Path $packageJsonPath)) {
        throw "Installed npm package metadata is missing: $packageName"
    }

    $packageMetadata = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
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

        # Fail the build if Windows text handling ever corrupts a POSIX shim.
        $shimText = [System.IO.File]::ReadAllText($shimPath)
        $shimBytes = [System.IO.File]::ReadAllBytes($shimPath)
        if (-not $shimText.StartsWith(("#!/bin/sh" + [char]10), [System.StringComparison]::Ordinal)) {
            throw "Generated command shim has an invalid shebang or missing LF newline: $shimPath"
        }
        if ($shimText.Contains('\n')) {
            throw "Generated command shim contains literal backslash-n text: $shimPath"
        }
        if ([Array]::IndexOf($shimBytes, [byte]13) -ge 0) {
            throw "Generated command shim contains CR bytes instead of LF-only line endings: $shimPath"
        }
        if ($shimBytes.Length -ge 3 -and $shimBytes[0] -eq 239 -and $shimBytes[1] -eq 187 -and $shimBytes[2] -eq 191) {
            throw "Generated command shim must not contain a UTF-8 BOM: $shimPath"
        }
    }
}

# 4. Materialize plugins from commit-keyed snapshots and persistent bare Git caches.
$pluginManifest = Get-Content (Join-Path $repoRoot "plugins.json") -Raw | ConvertFrom-Json
$pluginLockPath = Join-Path $repoRoot "locks/plugins.lock.json"
$oldPluginLock = $null

if ((Test-Path $pluginLockPath) -and (-not $RefreshLocks)) {
    $oldPluginLock = Get-Content $pluginLockPath -Raw | ConvertFrom-Json
}

$pluginRoot = Join-Path $bundleRoot "data/nvim/site/pack/offline/start"
New-Item -ItemType Directory -Force -Path $pluginRoot | Out-Null
$resolvedPlugins = @()

foreach ($plugin in $pluginManifest.plugins) {
    $lockedPlugin = $null
    if ($oldPluginLock -and $oldPluginLock.plugins) {
        $lockedPlugin = $oldPluginLock.plugins |
            Where-Object { $_.name -eq $plugin.name } |
            Select-Object -First 1
    }

    $commit = $null
    $mustFetchBranch = [bool]$RefreshLocks
    if (-not $lockedPlugin) {
        $mustFetchBranch = $true
    } elseif (-not $lockedPlugin.commit) {
        $mustFetchBranch = $true
    } else {
        $commit = [string]$lockedPlugin.commit
    }

    $destination = Join-Path $pluginRoot $plugin.name
    $snapshotParent = Join-Path $pluginSnapshotRoot $plugin.name
    $snapshotPath = $null
    $snapshotMarker = $null

    if ($commit) {
        $snapshotPath = Join-Path $snapshotParent $commit
        $snapshotMarker = "$snapshotPath.complete"
    }

    # A complete snapshot for the locked commit needs no Git operation at all.
    if ((-not $mustFetchBranch) -and $snapshotPath -and (Test-Path $snapshotPath) -and (Test-Path $snapshotMarker)) {
        Copy-Item -LiteralPath $snapshotPath -Destination $destination -Recurse -Force
        Write-Host "Plugin snapshot cache hit: $($plugin.name) [$commit]"
        $resolvedPlugins += [pscustomobject]@{
            name = $plugin.name
            repo = $plugin.repo
            ref = $plugin.ref
            commit = $commit
        }
        continue
    }

    $cacheName = ([string]$plugin.name) + ".git"
    $pluginCacheRepo = Join-Path $pluginGitCacheRoot $cacheName

    if (-not (Test-Path (Join-Path $pluginCacheRepo "HEAD"))) {
        if (Test-Path $pluginCacheRepo) {
            Remove-Item -LiteralPath $pluginCacheRepo -Recurse -Force
        }
        & git init --bare $pluginCacheRepo
        if ($LASTEXITCODE -ne 0) {
            throw "Could not initialize plugin Git cache for $($plugin.name)"
        }
        & git "--git-dir=$pluginCacheRepo" config core.longpaths true
        if ($LASTEXITCODE -ne 0) {
            throw "Could not configure plugin Git cache for $($plugin.name)"
        }
        & git "--git-dir=$pluginCacheRepo" remote add origin $plugin.repo
        if ($LASTEXITCODE -ne 0) {
            throw "Could not configure plugin remote for $($plugin.name)"
        }
    } else {
        $remoteUrl = (& git "--git-dir=$pluginCacheRepo" remote get-url origin 2>$null)
        $remoteNeedsUpdate = $false
        if ($LASTEXITCODE -ne 0) {
            $remoteNeedsUpdate = $true
        } elseif ($remoteUrl.Trim() -ne $plugin.repo) {
            $remoteNeedsUpdate = $true
        }

        if ($remoteNeedsUpdate) {
            & git "--git-dir=$pluginCacheRepo" remote remove origin 2>$null
            & git "--git-dir=$pluginCacheRepo" remote add origin $plugin.repo
            if ($LASTEXITCODE -ne 0) {
                throw "Could not update plugin remote for $($plugin.name)"
            }
        }
    }

    if ($mustFetchBranch) {
        $fetchRef = "refs/heads/$($plugin.ref)"
        Write-Host "Fetching plugin branch: $($plugin.name) [$fetchRef]"
        & git "--git-dir=$pluginCacheRepo" fetch --depth 1 origin $fetchRef
        if ($LASTEXITCODE -ne 0) {
            throw "git fetch failed for plugin $($plugin.name), ref $fetchRef"
        }
        $commit = (& git "--git-dir=$pluginCacheRepo" rev-parse "FETCH_HEAD^{commit}").Trim()
    } else {
        $lockedCommit = $commit
        & git "--git-dir=$pluginCacheRepo" cat-file -e "$lockedCommit^{commit}" 2>$null
        $commitCached = ($LASTEXITCODE -eq 0)

        if ($commitCached) {
            Write-Host "Plugin Git object cache hit: $($plugin.name) [$commit]"
        } else {
            Write-Host "Plugin Git object cache miss: $($plugin.name) [$commit]"
            & git "--git-dir=$pluginCacheRepo" fetch --depth 1 origin $lockedCommit
            if ($LASTEXITCODE -ne 0) {
                throw "git fetch failed for plugin $($plugin.name), commit $lockedCommit"
            }
            $fetchedCommit = (& git "--git-dir=$pluginCacheRepo" rev-parse "FETCH_HEAD^{commit}").Trim()
            if ($fetchedCommit -ne $lockedCommit) {
                throw "Plugin lock mismatch for $($plugin.name): expected $lockedCommit, got $fetchedCommit"
            }
        }
    }

    # Give the bare cache a stable HEAD so a local --shared clone can
    # materialize commits fetched through FETCH_HEAD or by raw commit SHA.
    & git "--git-dir=$pluginCacheRepo" update-ref refs/heads/offline-cache $commit
    if ($LASTEXITCODE -ne 0) {
        throw "Could not update local cache ref for plugin $($plugin.name) at $commit"
    }
    & git "--git-dir=$pluginCacheRepo" symbolic-ref HEAD refs/heads/offline-cache
    if ($LASTEXITCODE -ne 0) {
        throw "Could not set local cache HEAD for plugin $($plugin.name)"
    }

    # A refreshed branch may resolve to a snapshot already present in cache.
    $snapshotPath = Join-Path $snapshotParent $commit
    $snapshotMarker = "$snapshotPath.complete"
    if ((Test-Path $snapshotPath) -and (Test-Path $snapshotMarker)) {
        Copy-Item -LiteralPath $snapshotPath -Destination $destination -Recurse -Force
        Write-Host "Plugin snapshot cache hit: $($plugin.name) [$commit]"
    } else {
        if (Test-Path $snapshotPath) {
            Remove-Item -LiteralPath $snapshotPath -Recurse -Force
        }
        if (Test-Path $snapshotMarker) {
            Remove-Item -LiteralPath $snapshotMarker -Force
        }

        & git clone --shared --no-checkout $pluginCacheRepo $destination
        if ($LASTEXITCODE -ne 0) {
            throw "Could not materialize cached plugin $($plugin.name)"
        }
        & git -C $destination config core.autocrlf false
        & git -C $destination config core.longpaths true
        & git -C $destination checkout --detach $commit
        if ($LASTEXITCODE -ne 0) {
            throw "Could not checkout plugin $($plugin.name) at $commit"
        }

        $checkedOutCommit = (& git -C $destination rev-parse HEAD).Trim()
        if ($checkedOutCommit -ne $commit) {
            throw "Plugin checkout mismatch for $($plugin.name): expected $commit, got $checkedOutCommit"
        }

        Remove-Item -LiteralPath (Join-Path $destination ".git") -Recurse -Force

        New-Item -ItemType Directory -Force -Path $snapshotParent | Out-Null
        Copy-Item -LiteralPath $destination -Destination $snapshotPath -Recurse -Force
        Write-Utf8Lf -Path $snapshotMarker -Content $commit
        Write-Host "Saved plugin snapshot: $($plugin.name) [$commit]"
    }

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
Get-ChildItem -LiteralPath $bundleRoot -Recurse -File -Force |
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
Write-Host "Persistent cache: $cacheRoot"
Write-Host ""
Write-Host "Normal builds reuse verified downloads, npm node_modules and pinned plugin commits."
Write-Host "Use -Clean only to discard all build caches and rebuild from scratch."
Write-Host "Use -RefreshLocks only when intentionally updating npm and plugin versions."
) {
    throw "Invalid Maple Mono SHA256 file: $fontChecksumCached"
}

$fontCached = Join-Path $downloadCache $font.file
Invoke-Download -Url $font.url -Destination $fontCached -ExpectedSha256 $fontSha
Assert-Sha256 -Path $fontCached -Expected $fontSha

$fontExtractRoot = Join-Path $workRoot "font-extract"
if (Test-Path $fontExtractRoot) {
    Remove-Item -LiteralPath $fontExtractRoot -Recurse -Force
}
Expand-Archive -LiteralPath $fontCached -DestinationPath $fontExtractRoot -Force
$fontFiles = @(Get-ChildItem -LiteralPath $fontExtractRoot -Filter "*.ttf" -File -Recurse)
if ($fontFiles.Count -eq 0) {
    throw "Maple Mono NF archive did not contain any TTF files."
}

$fontDestination = Join-Path $bundleRoot "fonts/maple-mono"
New-Item -ItemType Directory -Force -Path $fontDestination | Out-Null
foreach ($fontFile in $fontFiles) {
    Copy-Item -LiteralPath $fontFile.FullName -Destination $fontDestination -Force
}

Copy-Item -LiteralPath (Join-Path $repoRoot "licenses/MapleMono-OFL.txt") -Destination (Join-Path $fontDestination "OFL.txt") -Force
Write-Host "Bundled Maple Mono NF $($font.version): $($fontFiles.Count) TTF files"

# 3. Prepare Linux-targeted npm dependencies.
# The npm download cache stores tarballs; npm-install cache stores a complete
# node_modules tree keyed by package.json + package-lock + npm + target platform.
$packageJsonSource = Join-Path $repoRoot "package.json"
$npmLockSource = Join-Path $repoRoot "locks/npm/package-lock.json"
$npmLockDestination = Join-Path $npmWork "package-lock.json"
$npmPackageDestination = Join-Path $npmWork "package.json"

Copy-Item -LiteralPath $packageJsonSource -Destination $npmPackageDestination -Force
$npmManifest = Get-Content -LiteralPath $npmPackageDestination -Raw | ConvertFrom-Json

$useExistingLock = (Test-Path $npmLockSource) -and (-not $RefreshLocks)
if ($useExistingLock) {
    Copy-Item -LiteralPath $npmLockSource -Destination $npmLockDestination -Force
}

$npmInstallEntry = $null
$npmCacheHit = $false

if ($useExistingLock) {
    $packageHash = (Get-FileHash -LiteralPath $npmPackageDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $lockHash = (Get-FileHash -LiteralPath $npmLockDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $npmCacheKey = Get-TextSha256 -Text ($packageHash + "|" + $lockHash + "|" + $npmActual + "|linux-x64")
    $npmInstallEntry = Join-Path $npmInstallCache $npmCacheKey
    $cachedNodeModules = Join-Path $npmInstallEntry "node_modules"
    $cacheMarker = Join-Path $npmInstallEntry "cache-key.txt"

    if ((Test-Path $cachedNodeModules) -and (Test-Path $cacheMarker)) {
        $markerValue = (Get-Content -LiteralPath $cacheMarker -Raw).Trim()
        if ($markerValue -eq $npmCacheKey) {
            $npmCacheHit = $true
            Write-Host "npm dependency cache hit: $npmCacheKey"
        }
    }
}

if (-not $npmCacheHit) {
    Push-Location $npmWork
    try {
        if ($useExistingLock) {
            Write-Host "Installing npm dependencies from package-lock.json (using persistent npm download cache)."
            & npm ci --os=linux --cpu=x64 --no-bin-links --no-audit --no-fund --ignore-scripts --cache $npmDownloadCache --prefer-offline
        } else {
            Write-Host "Resolving npm dependencies and updating package-lock.json."
            $npmRefreshPreference = "--prefer-offline"
            if ($RefreshLocks) {
                $npmRefreshPreference = "--prefer-online"
            }
            & npm install --save-exact --os=linux --cpu=x64 --no-bin-links --no-audit --no-fund --ignore-scripts --cache $npmDownloadCache $npmRefreshPreference
        }

        if ($LASTEXITCODE -ne 0) {
            throw "npm dependency installation failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $npmLockDestination)) {
        throw "npm did not generate package-lock.json."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $npmLockSource) | Out-Null
    Copy-Item -LiteralPath $npmLockDestination -Destination $npmLockSource -Force

    $packageHash = (Get-FileHash -LiteralPath $npmPackageDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $lockHash = (Get-FileHash -LiteralPath $npmLockDestination -Algorithm SHA256).Hash.ToLowerInvariant()
    $npmCacheKey = Get-TextSha256 -Text ($packageHash + "|" + $lockHash + "|" + $npmActual + "|linux-x64")
    $npmInstallEntry = Join-Path $npmInstallCache $npmCacheKey
    $cachedNodeModules = Join-Path $npmInstallEntry "node_modules"
    $cacheMarker = Join-Path $npmInstallEntry "cache-key.txt"

    $npmEntryAlreadyCached = $false
    if ((Test-Path $cachedNodeModules) -and (Test-Path $cacheMarker)) {
        $npmEntryAlreadyCached = ((Get-Content -LiteralPath $cacheMarker -Raw).Trim() -eq $npmCacheKey)
    }

    if ($npmEntryAlreadyCached) {
        Write-Host "npm dependency cache already contains this exact lock; reusing cached node_modules."
    } else {
        if (Test-Path $npmInstallEntry) {
            Remove-Item -LiteralPath $npmInstallEntry -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $npmInstallEntry | Out-Null
        Copy-Item -LiteralPath (Join-Path $npmWork "node_modules") -Destination $npmInstallEntry -Recurse -Force
        Write-Utf8Lf -Path $cacheMarker -Content $npmCacheKey
        Write-Host "Saved npm dependency cache: $npmCacheKey"
    }
}

Copy-Item -LiteralPath $npmPackageDestination -Destination (Join-Path $bundleRoot "runtime/npm/package.json") -Force
Copy-Item -LiteralPath $npmLockDestination -Destination (Join-Path $bundleRoot "runtime/npm/package-lock.json") -Force
$bundleNpmRoot = Join-Path $bundleRoot "runtime/npm"
Copy-Item -LiteralPath (Join-Path $npmInstallEntry "node_modules") -Destination $bundleNpmRoot -Recurse -Force
$nodeModules = Join-Path $npmInstallEntry "node_modules"

# Generate POSIX command shims from npm package bin metadata.
foreach ($dependency in $npmManifest.dependencies.PSObject.Properties) {
    $packageName = $dependency.Name
    $packagePath = Join-Path $nodeModules ($packageName -replace "/", "\")
    $packageJsonPath = Join-Path $packagePath "package.json"

    if (-not (Test-Path $packageJsonPath)) {
        throw "Installed npm package metadata is missing: $packageName"
    }

    $packageMetadata = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
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

        # Fail the build if Windows text handling ever corrupts a POSIX shim.
        $shimText = [System.IO.File]::ReadAllText($shimPath)
        $shimBytes = [System.IO.File]::ReadAllBytes($shimPath)
        if (-not $shimText.StartsWith(("#!/bin/sh" + [char]10), [System.StringComparison]::Ordinal)) {
            throw "Generated command shim has an invalid shebang or missing LF newline: $shimPath"
        }
        if ($shimText.Contains('\n')) {
            throw "Generated command shim contains literal backslash-n text: $shimPath"
        }
        if ([Array]::IndexOf($shimBytes, [byte]13) -ge 0) {
            throw "Generated command shim contains CR bytes instead of LF-only line endings: $shimPath"
        }
        if ($shimBytes.Length -ge 3 -and $shimBytes[0] -eq 239 -and $shimBytes[1] -eq 187 -and $shimBytes[2] -eq 191) {
            throw "Generated command shim must not contain a UTF-8 BOM: $shimPath"
        }
    }
}

# 4. Materialize plugins from commit-keyed snapshots and persistent bare Git caches.
$pluginManifest = Get-Content (Join-Path $repoRoot "plugins.json") -Raw | ConvertFrom-Json
$pluginLockPath = Join-Path $repoRoot "locks/plugins.lock.json"
$oldPluginLock = $null

if ((Test-Path $pluginLockPath) -and (-not $RefreshLocks)) {
    $oldPluginLock = Get-Content $pluginLockPath -Raw | ConvertFrom-Json
}

$pluginRoot = Join-Path $bundleRoot "data/nvim/site/pack/offline/start"
New-Item -ItemType Directory -Force -Path $pluginRoot | Out-Null
$resolvedPlugins = @()

foreach ($plugin in $pluginManifest.plugins) {
    $lockedPlugin = $null
    if ($oldPluginLock -and $oldPluginLock.plugins) {
        $lockedPlugin = $oldPluginLock.plugins |
            Where-Object { $_.name -eq $plugin.name } |
            Select-Object -First 1
    }

    $commit = $null
    $mustFetchBranch = [bool]$RefreshLocks
    if (-not $lockedPlugin) {
        $mustFetchBranch = $true
    } elseif (-not $lockedPlugin.commit) {
        $mustFetchBranch = $true
    } else {
        $commit = [string]$lockedPlugin.commit
    }

    $destination = Join-Path $pluginRoot $plugin.name
    $snapshotParent = Join-Path $pluginSnapshotRoot $plugin.name
    $snapshotPath = $null
    $snapshotMarker = $null

    if ($commit) {
        $snapshotPath = Join-Path $snapshotParent $commit
        $snapshotMarker = "$snapshotPath.complete"
    }

    # A complete snapshot for the locked commit needs no Git operation at all.
    if ((-not $mustFetchBranch) -and $snapshotPath -and (Test-Path $snapshotPath) -and (Test-Path $snapshotMarker)) {
        Copy-Item -LiteralPath $snapshotPath -Destination $destination -Recurse -Force
        Write-Host "Plugin snapshot cache hit: $($plugin.name) [$commit]"
        $resolvedPlugins += [pscustomobject]@{
            name = $plugin.name
            repo = $plugin.repo
            ref = $plugin.ref
            commit = $commit
        }
        continue
    }

    $cacheName = ([string]$plugin.name) + ".git"
    $pluginCacheRepo = Join-Path $pluginGitCacheRoot $cacheName

    if (-not (Test-Path (Join-Path $pluginCacheRepo "HEAD"))) {
        if (Test-Path $pluginCacheRepo) {
            Remove-Item -LiteralPath $pluginCacheRepo -Recurse -Force
        }
        & git init --bare $pluginCacheRepo
        if ($LASTEXITCODE -ne 0) {
            throw "Could not initialize plugin Git cache for $($plugin.name)"
        }
        & git "--git-dir=$pluginCacheRepo" config core.longpaths true
        if ($LASTEXITCODE -ne 0) {
            throw "Could not configure plugin Git cache for $($plugin.name)"
        }
        & git "--git-dir=$pluginCacheRepo" remote add origin $plugin.repo
        if ($LASTEXITCODE -ne 0) {
            throw "Could not configure plugin remote for $($plugin.name)"
        }
    } else {
        $remoteUrl = (& git "--git-dir=$pluginCacheRepo" remote get-url origin 2>$null)
        $remoteNeedsUpdate = $false
        if ($LASTEXITCODE -ne 0) {
            $remoteNeedsUpdate = $true
        } elseif ($remoteUrl.Trim() -ne $plugin.repo) {
            $remoteNeedsUpdate = $true
        }

        if ($remoteNeedsUpdate) {
            & git "--git-dir=$pluginCacheRepo" remote remove origin 2>$null
            & git "--git-dir=$pluginCacheRepo" remote add origin $plugin.repo
            if ($LASTEXITCODE -ne 0) {
                throw "Could not update plugin remote for $($plugin.name)"
            }
        }
    }

    if ($mustFetchBranch) {
        $fetchRef = "refs/heads/$($plugin.ref)"
        Write-Host "Fetching plugin branch: $($plugin.name) [$fetchRef]"
        & git "--git-dir=$pluginCacheRepo" fetch --depth 1 origin $fetchRef
        if ($LASTEXITCODE -ne 0) {
            throw "git fetch failed for plugin $($plugin.name), ref $fetchRef"
        }
        $commit = (& git "--git-dir=$pluginCacheRepo" rev-parse "FETCH_HEAD^{commit}").Trim()
    } else {
        $lockedCommit = $commit
        & git "--git-dir=$pluginCacheRepo" cat-file -e "$lockedCommit^{commit}" 2>$null
        $commitCached = ($LASTEXITCODE -eq 0)

        if ($commitCached) {
            Write-Host "Plugin Git object cache hit: $($plugin.name) [$commit]"
        } else {
            Write-Host "Plugin Git object cache miss: $($plugin.name) [$commit]"
            & git "--git-dir=$pluginCacheRepo" fetch --depth 1 origin $lockedCommit
            if ($LASTEXITCODE -ne 0) {
                throw "git fetch failed for plugin $($plugin.name), commit $lockedCommit"
            }
            $fetchedCommit = (& git "--git-dir=$pluginCacheRepo" rev-parse "FETCH_HEAD^{commit}").Trim()
            if ($fetchedCommit -ne $lockedCommit) {
                throw "Plugin lock mismatch for $($plugin.name): expected $lockedCommit, got $fetchedCommit"
            }
        }
    }

    # Give the bare cache a stable HEAD so a local --shared clone can
    # materialize commits fetched through FETCH_HEAD or by raw commit SHA.
    & git "--git-dir=$pluginCacheRepo" update-ref refs/heads/offline-cache $commit
    if ($LASTEXITCODE -ne 0) {
        throw "Could not update local cache ref for plugin $($plugin.name) at $commit"
    }
    & git "--git-dir=$pluginCacheRepo" symbolic-ref HEAD refs/heads/offline-cache
    if ($LASTEXITCODE -ne 0) {
        throw "Could not set local cache HEAD for plugin $($plugin.name)"
    }

    # A refreshed branch may resolve to a snapshot already present in cache.
    $snapshotPath = Join-Path $snapshotParent $commit
    $snapshotMarker = "$snapshotPath.complete"
    if ((Test-Path $snapshotPath) -and (Test-Path $snapshotMarker)) {
        Copy-Item -LiteralPath $snapshotPath -Destination $destination -Recurse -Force
        Write-Host "Plugin snapshot cache hit: $($plugin.name) [$commit]"
    } else {
        if (Test-Path $snapshotPath) {
            Remove-Item -LiteralPath $snapshotPath -Recurse -Force
        }
        if (Test-Path $snapshotMarker) {
            Remove-Item -LiteralPath $snapshotMarker -Force
        }

        & git clone --shared --no-checkout $pluginCacheRepo $destination
        if ($LASTEXITCODE -ne 0) {
            throw "Could not materialize cached plugin $($plugin.name)"
        }
        & git -C $destination config core.autocrlf false
        & git -C $destination config core.longpaths true
        & git -C $destination checkout --detach $commit
        if ($LASTEXITCODE -ne 0) {
            throw "Could not checkout plugin $($plugin.name) at $commit"
        }

        $checkedOutCommit = (& git -C $destination rev-parse HEAD).Trim()
        if ($checkedOutCommit -ne $commit) {
            throw "Plugin checkout mismatch for $($plugin.name): expected $commit, got $checkedOutCommit"
        }

        Remove-Item -LiteralPath (Join-Path $destination ".git") -Recurse -Force

        New-Item -ItemType Directory -Force -Path $snapshotParent | Out-Null
        Copy-Item -LiteralPath $destination -Destination $snapshotPath -Recurse -Force
        Write-Utf8Lf -Path $snapshotMarker -Content $commit
        Write-Host "Saved plugin snapshot: $($plugin.name) [$commit]"
    }

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
Get-ChildItem -LiteralPath $bundleRoot -Recurse -File -Force |
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
Write-Host "Persistent cache: $cacheRoot"
Write-Host ""
Write-Host "Normal builds reuse verified downloads, npm node_modules and pinned plugin commits."
Write-Host "Use -Clean only to discard all build caches and rebuild from scratch."
Write-Host "Use -RefreshLocks only when intentionally updating npm and plugin versions."
