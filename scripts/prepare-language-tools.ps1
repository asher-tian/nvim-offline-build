# Prepare Linux language tooling using Windows-only downloads and uv cross-platform resolution.
# This script is dot-sourced by build.ps1 and shares its build variables.

$builderRoot = Join-Path $cacheRoot "builder"
$uvCacheRoot = Join-Path $cacheRoot "uv-cache"
New-Item -ItemType Directory -Force -Path $builderRoot, $uvCacheRoot | Out-Null

# Download a pinned Windows uv executable. No Python installation is required
# on the Windows build host.
$uv = $versions.builder.uv
$uvArchive = Join-Path $downloadCache $uv.file
Invoke-Download -Url $uv.url -Destination $uvArchive -ExpectedSha256 $uv.sha256
Assert-Sha256 -Path $uvArchive -Expected $uv.sha256

$uvExtractRoot = Join-Path $builderRoot ("uv-" + $uv.version)
$uvExecutable = $null
if (Test-Path $uvExtractRoot) {
    $uvCandidate = Get-ChildItem -LiteralPath $uvExtractRoot -Filter "uv.exe" -File -Recurse | Select-Object -First 1
    if ($uvCandidate) {
        $uvExecutable = $uvCandidate.FullName
    }
}
if (-not $uvExecutable) {
    if (Test-Path $uvExtractRoot) {
        Remove-Item -LiteralPath $uvExtractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $uvExtractRoot | Out-Null
    Expand-Archive -LiteralPath $uvArchive -DestinationPath $uvExtractRoot -Force
    $uvCandidate = Get-ChildItem -LiteralPath $uvExtractRoot -Filter "uv.exe" -File -Recurse | Select-Object -First 1
    if ($uvCandidate) {
        $uvExecutable = $uvCandidate.FullName
    } else {
        throw "The uv archive did not contain uv.exe."
    }
}

$uvActual = (& $uvExecutable --version).Trim()
if ($LASTEXITCODE -ne 0 -or $uvActual -notmatch ("^uv " + [regex]::Escape($uv.version) + "(\s|$)")) {
    throw "Unexpected uv version. Expected uv $($uv.version), got $uvActual"
}

# Preserve the target Linux runtime archives in payload/. They are extracted
# only on CentOS; the Windows builder never executes Linux binaries.
$python = $versions.runtime.python
$pythonCached = Join-Path $downloadCache $python.file
Invoke-Download -Url $python.url -Destination $pythonCached -ExpectedSha256 $python.sha256
Assert-Sha256 -Path $pythonCached -Expected $python.sha256
Copy-Item -LiteralPath $pythonCached -Destination (Join-Path $payloadRoot $python.file) -Force

foreach ($toolName in @("shellcheck", "verible")) {
    $tool = $versions.tools.$toolName
    $toolCached = Join-Path $downloadCache $tool.file
    Invoke-Download -Url $tool.url -Destination $toolCached -ExpectedSha256 $tool.sha256
    Assert-Sha256 -Path $toolCached -Expected $tool.sha256
    Copy-Item -LiteralPath $toolCached -Destination (Join-Path $payloadRoot $tool.file) -Force
}

# ShellCheck is GPL-3.0. Ship the exact corresponding source tree with the
# offline binary so the bundle retains the complete license materials.
$shellcheck = $versions.tools.shellcheck
$shellcheckSourceCache = Join-Path $cacheRoot ("source-cache/shellcheck-" + $shellcheck.version)
$shellcheckSourceCommit = $null
if (Test-Path (Join-Path $shellcheckSourceCache ".git")) {
    $shellcheckSourceCommit = (& git -C $shellcheckSourceCache rev-parse HEAD).Trim()
}
if ($shellcheckSourceCommit -ne $shellcheck.sourceCommit) {
    if (Test-Path $shellcheckSourceCache) {
        Remove-Item -LiteralPath $shellcheckSourceCache -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $shellcheckSourceCache) | Out-Null
    & git clone --depth 1 --branch $shellcheck.sourceRef $shellcheck.sourceRepo $shellcheckSourceCache
    if ($LASTEXITCODE -ne 0) {
        throw "Could not fetch the ShellCheck $($shellcheck.version) corresponding source."
    }
    $shellcheckSourceCommit = (& git -C $shellcheckSourceCache rev-parse HEAD).Trim()
}
if ($shellcheckSourceCommit -ne $shellcheck.sourceCommit) {
    throw "ShellCheck source commit mismatch: expected $($shellcheck.sourceCommit), got $shellcheckSourceCommit"
}

$shellcheckSourceDestination = Join-Path $bundleRoot ("licenses/sources/shellcheck-" + $shellcheck.version)
New-Item -ItemType Directory -Force -Path $shellcheckSourceDestination | Out-Null
Get-ChildItem -LiteralPath $shellcheckSourceCache -Force |
    Where-Object { $_.Name -ne ".git" } |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $shellcheckSourceDestination -Recurse -Force
    }

# Resolve and install only prebuilt wheels for CPython 3.11 / Linux x86_64.
# uv performs target-platform resolution on Windows, so no WSL/VM/Linux host is
# needed. The generated lock includes hashes and is committed for repeatability.
$pythonRequirementsInput = Join-Path $repoRoot "requirements/tclint.in"
$pythonLockSource = Join-Path $repoRoot "locks/python/tclint-requirements.txt"
$pythonLockWork = Join-Path $workRoot "python/tclint-requirements.txt"
$pythonPackages = Join-Path $bundleRoot "runtime/python-packages"
$pythonMinor = ($python.version.Split(".")[0..1] -join ".")
$pythonPlatform = $versions.target.pythonPlatform

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pythonLockWork), $pythonPackages | Out-Null

if ((Test-Path $pythonLockSource) -and (-not $RefreshLocks)) {
    Copy-Item -LiteralPath $pythonLockSource -Destination $pythonLockWork -Force
    Write-Host "Using pinned Tcl tooling Python lock: $pythonLockSource"
} else {
    Write-Host "Resolving Tcl tooling Python dependencies for CPython $pythonMinor / $pythonPlatform"
    & $uvExecutable pip compile $pythonRequirementsInput --python-version $pythonMinor --python-platform $pythonPlatform --only-binary :all: --generate-hashes --no-config --cache-dir $uvCacheRoot --output-file $pythonLockWork
    if ($LASTEXITCODE -ne 0) {
        throw "uv pip compile failed for Tcl tooling dependencies."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pythonLockSource) | Out-Null
    Copy-Item -LiteralPath $pythonLockWork -Destination $pythonLockSource -Force
    Write-Host "Updated Python dependency lock: $pythonLockSource"
}

Write-Host "Installing Tcl tooling wheels into the offline bundle."
& $uvExecutable pip install --target $pythonPackages --python-version $pythonMinor --python-platform $pythonPlatform --only-binary :all: --require-hashes --no-config --cache-dir $uvCacheRoot --requirements $pythonLockWork
if ($LASTEXITCODE -ne 0) {
    throw "uv pip install failed for Tcl tooling dependencies."
}

# POSIX launchers keep the Tcl LSP and CLI independent of CentOS system Python.
$commandRoot = Join-Path $bundleRoot "runtime/commands"
New-Item -ItemType Directory -Force -Path $commandRoot | Out-Null

$pythonCommandShims = @{
    "tclsp" = @'
#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/runtime/python/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="$ROOT/runtime/python-packages${PYTHONPATH:+:$PYTHONPATH}"
exec "$ROOT/runtime/python/bin/python3.11" -c 'import sys; from tclint.cli.tclsp import main; sys.exit(main())' "$@"
'@
    "tclint" = @'
#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/runtime/python/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="$ROOT/runtime/python-packages${PYTHONPATH:+:$PYTHONPATH}"
exec "$ROOT/runtime/python/bin/python3.11" -c 'import sys; from tclint.cli.tclint import main; sys.exit(main())' "$@"
'@
    "tclfmt" = @'
#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/runtime/python/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="$ROOT/runtime/python-packages${PYTHONPATH:+:$PYTHONPATH}"
exec "$ROOT/runtime/python/bin/python3.11" -c 'import sys; from tclint.cli.tclfmt import main; sys.exit(main())' "$@"
'@
}

foreach ($commandName in $pythonCommandShims.Keys) {
    Write-Utf8Lf -Path (Join-Path $commandRoot $commandName) -Content $pythonCommandShims[$commandName]
}

# Keep all third-party notices with the redistributed offline tools.
$bundleLicenses = Join-Path $bundleRoot "licenses"
New-Item -ItemType Directory -Force -Path $bundleLicenses | Out-Null
foreach ($licenseFile in @(
    "tclint-MIT.txt",
    "Verible-Apache-2.0.txt",
    "ShellCheck-GPL-3.0.txt",
    "python-build-standalone-MPL-2.0.txt",
    "MapleMono-OFL.txt"
)) {
    $sourceLicense = Join-Path $repoRoot ("licenses/" + $licenseFile)
    if (-not (Test-Path $sourceLicense)) {
        throw "Missing third-party license file: $sourceLicense"
    }
    Copy-Item -LiteralPath $sourceLicense -Destination $bundleLicenses -Force
}

Write-Host "Prepared Tcl LSP/formatter, ShellCheck, Verible and bundled Python $($python.version)."
