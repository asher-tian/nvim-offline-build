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
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$ExpectedSha256
    )

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if (Test-Path $Destination) {
        $existing = Get-Item -LiteralPath $Destination
        if ($existing.Length -gt 0) {
            if ($ExpectedSha256) {
                $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actual -eq $ExpectedSha256.ToLowerInvariant()) {
                    Write-Host "Download cache hit: $(Split-Path -Leaf $Destination)"
                    return
                }

                Write-Warning "Cached download checksum mismatch; downloading again: $Destination"
                Remove-Item -LiteralPath $Destination -Force
            } else {
                Write-Host "Download cache hit: $(Split-Path -Leaf $Destination)"
                return
            }
        } else {
            Remove-Item -LiteralPath $Destination -Force
        }
    }

    $temporary = "$Destination.download"
    if (Test-Path $temporary) {
        Remove-Item -LiteralPath $temporary -Force
    }

    Write-Host "Download: $Url"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $temporary -UseBasicParsing -TimeoutSec 900

        if (-not (Test-Path $temporary) -or (Get-Item -LiteralPath $temporary).Length -eq 0) {
            throw "Download produced an empty file: $Url"
        }

        if ($ExpectedSha256) {
            $actual = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
                throw "SHA256 mismatch for downloaded file $Url. Expected $ExpectedSha256, got $actual"
            }
        }

        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    } catch {
        if (Test-Path $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
        throw
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

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha256.ComputeHash($bytes)
        return [BitConverter]::ToString($hash).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
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
