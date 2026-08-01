param(
    [string]$BuildRoot = (
        Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mod'
    ),
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT,
    [string]$BackupRoot = (
        Join-Path (
            Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        ) '_deployment-backups\DarkPassenger'
    ),
    [string]$GameProcessName = 'KingdomCome'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
    throw 'KCD2_DEV_ROOT or -DevGameRoot is required.'
}

$resolvedBuildRoot = [System.IO.Path]::GetFullPath($BuildRoot)
$resolvedDevRoot = [System.IO.Path]::GetFullPath($DevGameRoot)
$resolvedBackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)
$devPrefix = $resolvedDevRoot + [System.IO.Path]::DirectorySeparatorChar
$backupPrefix =
    $resolvedBackupRoot + [System.IO.Path]::DirectorySeparatorChar
$sourceObjects = Join-Path $resolvedBuildRoot `
    'Data\Levels\kutnohorsko\objects_mission0.xml'
$sourceWaitingLinks = Join-Path $resolvedBuildRoot `
    'Data\Levels\kutnohorsko\waitinglinks.xml'
$sourceAreaCatalog = Join-Path $resolvedBuildRoot `
    'Data\Scripts\mods\generated\dp_investigation_area_catalog.lua'
$levelRoot = Join-Path $resolvedDevRoot 'Data\Levels\kutnohorsko'
$targetObjects = Join-Path $levelRoot 'objects_mission0.xml'
$targetWaitingLinks = Join-Path $levelRoot 'waitinglinks.xml'

if (-not (Test-Path -LiteralPath $sourceObjects -PathType Leaf)) {
    throw "Generated mission objects not found: $sourceObjects"
}
if (-not (Test-Path -LiteralPath $sourceWaitingLinks -PathType Leaf)) {
    throw "Generated waitinglinks not found: $sourceWaitingLinks"
}
if (-not (Test-Path -LiteralPath $sourceAreaCatalog -PathType Leaf)) {
    throw "Generated investigation area catalogue not found: $sourceAreaCatalog"
}
if (-not [System.IO.Path]::GetFullPath($targetObjects).StartsWith(
    $devPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to deploy outside dev root: $targetObjects"
}
if (Get-Process -Name $GameProcessName -ErrorAction SilentlyContinue) {
    throw "Close $GameProcessName before deploying the dev level overlay."
}

$userCfg = Join-Path $resolvedDevRoot 'user.cfg'
$userCfgText = ''
if (Test-Path -LiteralPath $userCfg -PathType Leaf) {
    $userCfgText = [System.IO.File]::ReadAllText($userCfg)
}
if ($userCfgText -notmatch '(?m)^\s*sys_PakPriority\s*=\s*0\s*$') {
    throw 'Dev loose overlay requires sys_PakPriority = 0.'
}

$areaCatalogText = [System.IO.File]::ReadAllText($sourceAreaCatalog)
$areaCatalogMatch = [regex]::Match(
    $areaCatalogText,
    '(?s)\["kutnohorsko"\]\s*=\s*\{.*?' +
    '\["pritoky"\]\s*=\s*\{.*?' +
    'alias\s*=\s*"([^"]+)".*?' +
    'entityName\s*=\s*"([^"]+)".*?' +
    'entityGuid\s*=\s*"([0-9a-fA-F-]+)"'
)
if (-not $areaCatalogMatch.Success) {
    throw 'Generated investigation area catalogue has no Kuttenberg Pritoky entry.'
}
$expectedAreaAlias = $areaCatalogMatch.Groups[1].Value
$expectedAreaName = $areaCatalogMatch.Groups[2].Value
$expectedAreaGuid = $areaCatalogMatch.Groups[3].Value
$expectedLinkName = "asset['$expectedAreaAlias']"

$sourceText = [System.IO.File]::ReadAllText($sourceObjects)
$requiredFragments = @(
    'EntityGuid="10702dff-9271-4a74"',
    'EntityGuid="f4a73e20-28c5-4bd2"',
    "Name=`"$expectedAreaName`"",
    "EntityGuid=`"$expectedAreaGuid`""
)
foreach ($fragment in $requiredFragments) {
    if (-not $sourceText.Contains($fragment)) {
        throw "Generated mission objects lack required area binding: $fragment"
    }
}
$requiredPatterns = @(
    '(?s)<Entity\b(?=[^>]*Name="kutnohorsko")(?=[^>]*EntityClass="LevelHolder")(?=[^>]*EntityGuid="10702dff-9271-4a74")[^>]*>.*?<Link TargetId="1831841" TargetGuid="00000000-0000-0000" Name="module" />.*?</Entity>',
    ('(?s)<Entity\b[^>]*Name="dark_within_k"[^>]*EntityGuid="f4a73e20-28c5-4bd2".*?<Link TargetId="\d+" TargetGuid="00000000-0000-0000" Name="' + [regex]::Escape($expectedLinkName) + '" />'),
    ('<Entity\b(?=[^>]*Name="' + [regex]::Escape($expectedAreaName) + '")(?=[^>]*EntityClass="SmartAreaShape")(?=[^>]*EntityGuid="' + [regex]::Escape($expectedAreaGuid) + '")[^>]*>')
)
foreach ($pattern in $requiredPatterns) {
    if ($sourceText -notmatch $pattern) {
        throw "Generated mission objects lack a vanilla-format concept-graph link: $pattern"
    }
}
$sourceWaitingLinksText =
    [System.IO.File]::ReadAllText($sourceWaitingLinks)
$requiredWaitingLinksFragments = @(
    '<StaticLinksInfo version="1">',
    '<WaitingLink SourceId="10702dff-9271-4a74" TargetId="f4a73e20-28c5-4bd2">',
    "<WaitingLink SourceId=`"f4a73e20-28c5-4bd2`" TargetId=`"$expectedAreaGuid`">",
    ('<LinkDefinition>' + $expectedLinkName.Replace("'", '&apos;') + '</LinkDefinition>')
)
foreach ($fragment in $requiredWaitingLinksFragments) {
    if (-not $sourceWaitingLinksText.Contains($fragment)) {
        throw "Generated waitinglinks lack required resolver binding: $fragment"
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backupDir = Join-Path $resolvedBackupRoot "dev-level-$stamp"
if (-not [System.IO.Path]::GetFullPath($backupDir).StartsWith(
    $backupPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to back up outside backup root: $backupDir"
}
New-Item -ItemType Directory -Force -Path $backupDir, $levelRoot |
    Out-Null

foreach ($existingFile in @($targetObjects, $targetWaitingLinks)) {
    if (Test-Path -LiteralPath $existingFile -PathType Leaf) {
        Move-Item -LiteralPath $existingFile -Destination (
            Join-Path $backupDir (Split-Path -Leaf $existingFile)
        )
    }
}

Copy-Item -LiteralPath $sourceObjects -Destination $targetObjects
Copy-Item -LiteralPath $sourceWaitingLinks -Destination $targetWaitingLinks
$sourceHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceObjects).Hash
$targetHash =
    (Get-FileHash -Algorithm SHA256 -LiteralPath $targetObjects).Hash
if ($sourceHash -ne $targetHash) {
    throw 'Dev loose mission-object overlay hash mismatch.'
}
$sourceWaitingLinksHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $sourceWaitingLinks
).Hash
$targetWaitingLinksHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $targetWaitingLinks
).Hash
if ($sourceWaitingLinksHash -ne $targetWaitingLinksHash) {
    throw 'Dev loose waitinglinks overlay hash mismatch.'
}

Write-Host "Dev level overlay deployed: $targetObjects, $targetWaitingLinks"
Write-Host "Backup: $backupDir"
Write-Host "SHA-256: objects=$targetHash waitinglinks=$targetWaitingLinksHash"
