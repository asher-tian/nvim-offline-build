Set-StrictMode -Version Latest

function Assert-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if (Test-Path $Destination) {
        Remove-Item -LiteralPath $Destination -Force
    }

    Write-Host "Download: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 900

    if (-not (Test-Path $Destination) -or (Get-Item $Destination).Length -eq 0) {
        throw "Download produced an empty file: $Destination"
    }
}

function Get-ChecksumFromFile {
    param(
        [Parameter(Mandatory = $true)][string]$ChecksumFile,
        [Parameter(Mandatory = $true)][string]$AssetName
    )

    $escapedName = [regex]::Escape($AssetName)
    $line = Get-Content -LiteralPath $ChecksumFile |
        Where-Object { $_ -match $escapedName } |
        Select-Object -First 1

    if (-not $line) {
        throw "Checksum entry not found for $AssetName in $ChecksumFile"
    }

    $match = [regex]::Match([string]$line, '(?i)\b[0-9a-f]{64}\b')
    if (-not $match.Success) {
        throw "Could not parse SHA256 for $AssetName from: $line"
    }

    return $match.Value.ToLowerInvariant()
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected.ToLowerInvariant()) {
        throw "SHA256 mismatch for $Path. Expected $Expected, got $actual"
    }

    Write-Host "SHA256 OK: $(Split-Path -Leaf $Path)"
}

function Write-Utf8Lf {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    # PowerShell does not use C-style \n escapes. Write an actual LF character.
    $normalized = [regex]::Replace($Content, '\r\n?', [string][char]10)
    [System.IO.File]::WriteAllText(
        $Path,
        $normalized,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText(
        $Path,
        $json + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}
