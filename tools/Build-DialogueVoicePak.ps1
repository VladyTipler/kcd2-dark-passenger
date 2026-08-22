param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputPak,
    [string]$PackageLanguage = 'english'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Dialogue voice manifest not found: $ManifestPath"
}
$manifest = [System.IO.File]::ReadAllText($ManifestPath) |
    ConvertFrom-Json -Depth 100
if ([int]$manifest.schemaVersion -ne 1) {
    throw "Dialogue voice manifest schemaVersion must be 1: $ManifestPath"
}
$assets = @($manifest.assets | Where-Object {
    [string]$_.packageLanguage -ceq $PackageLanguage
} | Sort-Object destination)
if ($assets.Count -eq 0) {
    throw "Dialogue voice manifest has no '$PackageLanguage' assets."
}
$duplicateDestination = $assets | Group-Object {
    [string]$_.destination
} | Where-Object { $_.Count -gt 1 } | Select-Object -First 1
if ($null -ne $duplicateDestination) {
    throw "Dialogue voice destination is duplicated: " +
        [string]$duplicateDestination.Name
}

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$repoPrefix = $resolvedRepoRoot + [System.IO.Path]::DirectorySeparatorChar
$resolvedOutputPak = [System.IO.Path]::GetFullPath($OutputPak)
if (Test-Path -LiteralPath $resolvedOutputPak) {
    throw "Refusing to append to existing dialogue voice PAK: $resolvedOutputPak"
}
$outputParent = Split-Path -Parent $resolvedOutputPak
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null

$tempBase = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::GetTempPath()
)
$stagingRoot = Join-Path $tempBase (
    'dark-passenger-dialogue-voice-pak-' +
    [guid]::NewGuid().ToString('N')
)
$resolvedStagingRoot = [System.IO.Path]::GetFullPath($stagingRoot)
if (-not $resolvedStagingRoot.StartsWith(
    $tempBase,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to stage dialogue voices outside temp: $stagingRoot"
}
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

try {
    $timestamp = [datetime]::new(
        2000,
        1,
        1,
        0,
        0,
        0,
        [System.DateTimeKind]::Utc
    )
    foreach ($asset in $assets) {
        $sourceRelative = ([string]$asset.sourceAsset).Replace('/', '\')
        $sourcePath = [System.IO.Path]::GetFullPath(
            (Join-Path $resolvedRepoRoot $sourceRelative)
        )
        if (-not $sourcePath.StartsWith(
            $repoPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Dialogue voice source escapes repository: $sourceRelative"
        }
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Dialogue voice source not found: $sourcePath"
        }
        $destination = ([string]$asset.destination).Replace('\', '/')
        if ($destination -notmatch (
            '^dialog/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/' +
            '[A-Za-z0-9_.-]+\.ogg$'
        ) -or
            $destination -match '(^|/)\.\.(/|$)') {
            throw "Unsafe dialogue voice destination: $destination"
        }
        $destinationPath = Join-Path $stagingRoot (
            $destination.Replace('/', '\')
        )
        New-Item -ItemType Directory -Path (
            Split-Path -Parent $destinationPath
        ) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
        (Get-Item -LiteralPath $destinationPath).LastWriteTimeUtc = $timestamp
    }

    $sevenZip = (Get-Command 7z.exe -ErrorAction Stop).Source
    Push-Location $stagingRoot
    try {
        & $sevenZip a -tzip -mx=9 -mtc=off $resolvedOutputPak 'dialog' |
            Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip failed to build $resolvedOutputPak"
        }
    }
    finally {
        Pop-Location
    }
    & $sevenZip t $resolvedOutputPak | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip integrity test failed for $resolvedOutputPak"
    }
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        $verifiedStagingRoot = [System.IO.Path]::GetFullPath($stagingRoot)
        if (-not $verifiedStagingRoot.StartsWith(
            $tempBase,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Refusing to clean unexpected staging path: $stagingRoot"
        }
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}

Write-Host "Built $PackageLanguage dialogue voice PAK: $resolvedOutputPak"
