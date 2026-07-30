param(
    [switch]$SkipPackaging
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'src'
$buildRoot = Join-Path $repoRoot 'build\mod'
$buildParent = Join-Path $repoRoot 'build'
$generatorPath = Join-Path $PSScriptRoot 'Generate-VictimArtifacts.ps1'
$worldExporterPath = Join-Path $PSScriptRoot 'Export-WorldVictimCandidates.ps1'
$localizationRoot = Join-Path $repoRoot 'localization'
$rawEvidencePath = Join-Path $repoRoot 'evidence\world-candidates.raw.json'

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($repoRoot)
$resolvedBuildRoot = [System.IO.Path]::GetFullPath($buildRoot)
$requiredPrefix = [System.IO.Path]::GetFullPath($buildParent) +
    [System.IO.Path]::DirectorySeparatorChar

if (-not $resolvedBuildRoot.StartsWith(
    $requiredPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to replace build path outside repository build root: $resolvedBuildRoot"
}

if (Test-Path -LiteralPath $resolvedBuildRoot) {
    Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedBuildRoot -Force | Out-Null

foreach ($item in Get-ChildItem -LiteralPath $sourceRoot -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination $resolvedBuildRoot -Recurse
}

if (-not (Test-Path -LiteralPath $rawEvidencePath)) {
    & $worldExporterPath
}

& $generatorPath

if ($SkipPackaging) {
    Write-Host "Prepared generated build tree: $resolvedBuildRoot"
    exit 0
}

$sevenZip = (Get-Command 7z.exe -ErrorAction Stop).Source
$dataRoot = Join-Path $resolvedBuildRoot 'Data'
$dataPak = Join-Path $dataRoot 'darkpassengertest.pak'
$localizationOutput = Join-Path $resolvedBuildRoot 'Localization'
New-Item -ItemType Directory -Path $localizationOutput -Force | Out-Null

$dataInputs = @('AI', 'Libs', 'Quests', 'Scripts') |
    ForEach-Object { Join-Path $dataRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ }

& $sevenZip a -tzip -mx=9 -mtc=off $dataPak $dataInputs | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "7-Zip failed to build $dataPak"
}

$kuttenbergLevelRoot = Join-Path $dataRoot 'Levels\kutnohorsko'
if (Test-Path -LiteralPath $kuttenbergLevelRoot) {
    $kuttenbergLevelPak = Join-Path $kuttenbergLevelRoot 'darkpassengertest.pak'
    $kuttenbergLevelInputs = @('waitinglinks.xml', 'layers') |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $kuttenbergLevelRoot $_)
        }

    if ($kuttenbergLevelInputs.Count -gt 0) {
        Push-Location $kuttenbergLevelRoot
        try {
            & $sevenZip a -tzip -mx=9 -mtc=off $kuttenbergLevelPak $kuttenbergLevelInputs |
                Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7-Zip failed to build $kuttenbergLevelPak"
            }
        }
        finally {
            Pop-Location
        }

        & $sevenZip t $kuttenbergLevelPak | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip integrity test failed for $kuttenbergLevelPak"
        }
    }
}

foreach ($language in @('English', 'Russian')) {
    $sourceFile = Join-Path $localizationRoot "$language\text__darkpassengertest.xml"
    $outputPak = Join-Path $localizationOutput "${language}_xml.pak"
    Push-Location (Split-Path -Parent $sourceFile)
    try {
        & $sevenZip a -tzip -mx=9 -mtc=off $outputPak (Split-Path -Leaf $sourceFile) |
            Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip failed to build $outputPak"
        }
    }
    finally {
        Pop-Location
    }
}

& $sevenZip t $dataPak | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "7-Zip integrity test failed for $dataPak"
}

Write-Host "Built mod staging tree: $resolvedBuildRoot"
