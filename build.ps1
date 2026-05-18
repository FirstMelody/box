Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$RepoRoot = $PSScriptRoot
$ModuleProp = Join-Path $RepoRoot 'module.prop'

if (-not (Test-Path -LiteralPath $ModuleProp)) {
    throw "module.prop not found: $ModuleProp"
}

$Version = $null
foreach ($Line in Get-Content -LiteralPath $ModuleProp) {
    if ($Line -match '^version=(.+)$') {
        $Version = $Matches[1].Trim()
        break
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    throw 'failed to read version from module.prop'
}

$OutputName = "box-$Version.zip"
$OutputPath = Join-Path $RepoRoot $OutputName
$ResolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\', '/')
$RepoRootPrefix = $ResolvedRepoRoot + [System.IO.Path]::DirectorySeparatorChar

$ExcludedExact = @(
    'CHANGELOG.md',
    'LICENSE',
    'build.ps1',
    'build.sh',
    'update.json'
)

$ExcludedPrefixes = @(
    '.git/',
    '.github/',
    '.codex_tmp/',
    'debug/'
)

$ExcludedPatterns = @(
    'box-*.zip',
    'KernelSU_bugreport_*.tar.gz'
)

$LfNormalizedPrefixes = @(
    'META-INF/com/google/android/',
    'box/scripts/'
)

$LfNormalizedExact = @(
    'action.sh',
    'box/settings.ini',
    'box_service.sh',
    'build.sh',
    'customize.sh',
    'uninstall.sh'
)

function Test-ExcludedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $Normalized = $RelativePath.Replace('\', '/')

    foreach ($Exact in $ExcludedExact) {
        if ($Normalized -eq $Exact) {
            return $true
        }
    }

    foreach ($Prefix in $ExcludedPrefixes) {
        if ($Normalized.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    foreach ($Pattern in $ExcludedPatterns) {
        if ($Normalized -like $Pattern) {
            return $true
        }
    }

    return $false
}

function Test-NormalizeLfPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $Normalized = $RelativePath.Replace('\', '/')

    foreach ($Exact in $LfNormalizedExact) {
        if ($Normalized -eq $Exact) {
            return $true
        }
    }

    foreach ($Prefix in $LfNormalizedPrefixes) {
        if ($Normalized.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Convert-ToLfBytes {
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $Output = New-Object 'System.Collections.Generic.List[byte]'

    for ($Index = 0; $Index -lt $Bytes.Length; $Index++) {
        $Byte = $Bytes[$Index]

        if ($Byte -eq 13) {
            $Output.Add([byte]10)
            if (($Index + 1) -lt $Bytes.Length -and $Bytes[$Index + 1] -eq 10) {
                $Index++
            }
            continue
        }

        $Output.Add($Byte)
    }

    return $Output.ToArray()
}

if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}

$Files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File
$Archive = [System.IO.Compression.ZipFile]::Open($OutputPath, [System.IO.Compression.ZipArchiveMode]::Create)

try {
    foreach ($File in $Files) {
        if (-not $File.FullName.StartsWith($RepoRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $RelativePath = $File.FullName.Substring($RepoRootPrefix.Length)
        if (Test-ExcludedPath -RelativePath $RelativePath) {
            continue
        }

        $EntryName = $RelativePath.Replace('\', '/')
        if (Test-NormalizeLfPath -RelativePath $RelativePath) {
            $Entry = $Archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $EntryStream = $Entry.Open()

            try {
                $Bytes = [System.IO.File]::ReadAllBytes($File.FullName)
                $NormalizedBytes = Convert-ToLfBytes -Bytes $Bytes
                $EntryStream.Write($NormalizedBytes, 0, $NormalizedBytes.Length)
            }
            finally {
                $EntryStream.Dispose()
            }
        }
        else {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $Archive,
                $File.FullName,
                $EntryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
}
finally {
    $Archive.Dispose()
}

Write-Host "Created $OutputName"
