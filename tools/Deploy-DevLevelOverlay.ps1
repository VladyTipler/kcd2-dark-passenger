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
$levelRoot = Join-Path $resolvedDevRoot 'Data\Levels\kutnohorsko'
$targetObjects = Join-Path $levelRoot 'objects_mission0.xml'
$targetWaitingLinks = Join-Path $levelRoot 'waitinglinks.xml'
$obsoleteCustomLayerTargets = @(
    Join-Path $levelRoot `
        'Layers\darkpassenger_investigation_areas_1b986e82-f241-016c-c428-a298fa47119a.xml'
    Join-Path $levelRoot `
        'Layers\main\_quest\activity\darkpassenger_investigation_areas.lyr'
)

if (-not (Test-Path -LiteralPath $sourceObjects -PathType Leaf)) {
    throw "Generated mission objects not found: $sourceObjects"
}
if (-not (Test-Path -LiteralPath $sourceWaitingLinks -PathType Leaf)) {
    throw "Generated waitinglinks not found: $sourceWaitingLinks"
}
if (-not [System.IO.Path]::GetFullPath($targetObjects).StartsWith(
    $devPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to deploy outside dev root: $targetObjects"
}
foreach ($obsoleteTarget in $obsoleteCustomLayerTargets) {
    if (-not [System.IO.Path]::GetFullPath($obsoleteTarget).StartsWith(
        $devPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to clean obsolete layer outside dev root: $obsoleteTarget"
    }
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

$sourceText = [System.IO.File]::ReadAllText($sourceObjects)
$requiredFragments = @(
    'EntityGuid="10702dff-9271-4a74"',
    'EntityGuid="f4a73e20-28c5-4bd2"'
)
foreach ($fragment in $requiredFragments) {
    if (-not $sourceText.Contains($fragment)) {
        throw "Generated mission objects lack required area binding: $fragment"
    }
}
$requiredPatterns = @(
    '(?s)<Entity\b(?=[^>]*Name="kutnohorsko")(?=[^>]*EntityClass="LevelHolder")(?=[^>]*EntityGuid="10702dff-9271-4a74")[^>]*>.*?<Link TargetId="1831841" TargetGuid="00000000-0000-0000" Name="module" />.*?</Entity>'
)
foreach ($pattern in $requiredPatterns) {
    if ($sourceText -notmatch $pattern) {
        throw "Generated mission objects lack a vanilla-format concept-graph link: $pattern"
    }
}
$requiredAreaTargetIds = @(17080, 14696, 4803)
foreach ($targetId in $requiredAreaTargetIds) {
    $fragment = (
        '<Link TargetId="{0}" TargetGuid="00000000-0000-0000" ' +
        'Name="asset[''DP_PritokySearchArea'']" />'
    ) -f $targetId
    if (-not $sourceText.Contains($fragment)) {
        throw "Generated mission objects lack Pritoky area target: $targetId"
    }
}
if (([regex]::Matches(
    $sourceText,
    "asset\['DP_PritokySearchArea'\]"
).Count) -ne 3) {
    throw 'Generated mission objects must bind exactly three Pritoky areas.'
}
$sourceWaitingLinksText =
    [System.IO.File]::ReadAllText($sourceWaitingLinks)
$requiredWaitingLinksFragments = @(
    '<StaticLinksInfo version="1">',
    '<WaitingLink SourceId="10702dff-9271-4a74" TargetId="f4a73e20-28c5-4bd2">',
    '<WaitingLink SourceId="f4a73e20-28c5-4bd2" TargetId="d0fa0ece-6af5-19f6">',
    '<WaitingLink SourceId="f4a73e20-28c5-4bd2" TargetId="d2fc29a3-6787-141c">',
    '<WaitingLink SourceId="f4a73e20-28c5-4bd2" TargetId="1b6b6d4e-905c-4f9e">',
    '<LinkDefinition>asset[&apos;DP_PritokySearchArea&apos;]</LinkDefinition>'
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
foreach ($obsoleteTarget in $obsoleteCustomLayerTargets) {
    if (Test-Path -LiteralPath $obsoleteTarget -PathType Leaf) {
        $relativePath = [System.IO.Path]::GetRelativePath(
            $levelRoot,
            $obsoleteTarget
        )
        $backupTarget = Join-Path $backupDir $relativePath
        if (-not [System.IO.Path]::GetFullPath($backupTarget).StartsWith(
            $backupPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Refusing to back up obsolete layer outside backup root: $backupTarget"
        }
        New-Item -ItemType Directory -Force -Path (
            Split-Path -Parent $backupTarget
        ) | Out-Null
        Move-Item -LiteralPath $obsoleteTarget -Destination $backupTarget
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
