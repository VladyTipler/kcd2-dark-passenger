param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputDataRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Dialogue media manifest not found: $ManifestPath"
}

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$repoPrefix = $resolvedRepoRoot + [System.IO.Path]::DirectorySeparatorChar
$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputDataRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)

$manifest = [System.IO.File]::ReadAllText($ManifestPath) |
    ConvertFrom-Json -Depth 100
if ([int]$manifest.schemaVersion -ne 1) {
    throw "Dialogue media manifest schemaVersion must be 1: $ManifestPath"
}

$seenDestinations = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($asset in @($manifest.facialAssets)) {
    $sourceAsset = ([string]$asset.sourceAsset).Replace('/', '\')
    $destination = ([string]$asset.destination).Replace('\', '/')
    if (
        [string]::IsNullOrWhiteSpace($sourceAsset) -or
        [System.IO.Path]::IsPathRooted($sourceAsset) -or
        $sourceAsset -match '(^|\\)\.\.(\\|$)'
    ) {
        throw "Facial asset has unsafe source path: '$sourceAsset'."
    }
    if (
        $destination -notmatch
            '^Animations/facial_sequences/darkpassenger/[A-Za-z0-9_.-]+\.fsq$' -or
        -not $seenDestinations.Add($destination)
    ) {
        throw "Facial asset has invalid or duplicated destination: '$destination'."
    }

    $sourcePath = [System.IO.Path]::GetFullPath(
        (Join-Path $resolvedRepoRoot $sourceAsset)
    )
    if (-not $sourcePath.StartsWith(
        $repoPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Facial source escapes the repository: $sourcePath"
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Facial source not found: $sourcePath"
    }
    [xml]$facial = [System.IO.File]::ReadAllText($sourcePath)
    if (
        $null -eq $facial.FacialSequence -or
        $null -eq $facial.FacialSequence.Sentence -or
        [decimal]$facial.FacialSequence.EndTime -le 0
    ) {
        throw "Facial source is not a timed FacialSequence: $sourcePath"
    }

    $destinationPath = [System.IO.Path]::GetFullPath(
        (Join-Path $resolvedOutputRoot $destination.Replace('/', '\'))
    )
    $outputPrefix = $resolvedOutputRoot +
        [System.IO.Path]::DirectorySeparatorChar
    if (-not $destinationPath.StartsWith(
        $outputPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Facial destination escapes Data root: $destinationPath"
    }
    New-Item -ItemType Directory -Force -Path (
        Split-Path -Parent $destinationPath
    ) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

Write-Host (
    'Staged {0} dialogue facial asset(s): {1}' -f
        $seenDestinations.Count,
        $resolvedOutputRoot
)
