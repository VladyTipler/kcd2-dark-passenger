$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$deployScript = Join-Path $repoRoot 'tools\Deploy-DevLevelOverlay.ps1'
$fixtureRoot = Join-Path $repoRoot 'build\test-dev-level-overlay'
$fixtureBuild = Join-Path $fixtureRoot 'build'
$fixtureGame = Join-Path $fixtureRoot 'game'
$fixtureBackup = Join-Path $fixtureRoot 'backups'

function Write-AsciiFile {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Content
    )

    $parent = Split-Path -Parent $LiteralPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $LiteralPath,
        $Content,
        [System.Text.Encoding]::ASCII
    )
}

if (Test-Path -LiteralPath $fixtureRoot) {
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
    $resolvedBuild = [System.IO.Path]::GetFullPath(
        (Join-Path $repoRoot 'build')
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith(
        $resolvedBuild,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to replace fixture outside build root: $resolvedFixture"
    }
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}

$regions = @(
    [pscustomobject]@{
        id = 'kutnohorsko'
        levelHolderGuid = '10702dff-9271-4a74'
        questHolderName = 'dark_within_k'
        questHolderGuid = 'f4a73e20-28c5-4bd2'
        questHolderEntityId = '1831841'
        alias = 'DP_SearchArea_Kutnohorsko_Pritoky'
        areas = @(
            [pscustomobject]@{ guid = 'd0fa0ece-6af5-19f6'; entityId = '17080' }
            [pscustomobject]@{ guid = 'd2fc29a3-6787-141c'; entityId = '14696' }
            [pscustomobject]@{ guid = '1b6b6d4e-905c-4f9e'; entityId = '4803' }
        )
    }
    [pscustomobject]@{
        id = 'trosecko'
        levelHolderGuid = '30277b74-1c65-41e9'
        questHolderName = 'dark_within_t'
        questHolderGuid = 'a13d9e5c-7b42-4f61'
        questHolderEntityId = '1831842'
        alias = 'DP_SearchArea_Trosecko_Troskovice'
        areas = @(
            [pscustomobject]@{ guid = '0c34a13c-dd79-19a9'; entityId = '28001' }
        )
    }
)

New-Item -ItemType Directory -Path $fixtureBackup -Force | Out-Null
$sentinelHashes = @{}
foreach ($region in $regions) {
    $buildLevel = Join-Path $fixtureBuild "Data\Levels\$($region.id)"
    $gameLevel = Join-Path $fixtureGame "Data\Levels\$($region.id)"
    New-Item -ItemType Directory -Path $buildLevel, $gameLevel -Force |
        Out-Null

    $assetLinks = @(
        $region.areas | ForEach-Object {
            '      <Link TargetId="{0}" TargetGuid="00000000-0000-0000" Name="asset[''{1}'']" />' -f
                $_.entityId,
                $region.alias
        }
    ) -join "`r`n"
    $areaEntities = @(
        $region.areas | ForEach-Object {
            '  <Entity Name="area_{0}" EntityClass="TriggerArea" EntityId="{1}" EntityGuid="{0}"><EntityLinks /></Entity>' -f
                $_.guid,
                $_.entityId
        }
    ) -join "`r`n"
    $generatedObjects = @"
<?xml version="1.0" encoding="us-ascii"?>
<Objects>
  <Entity Name="$($region.id)" EntityClass="LevelHolder" EntityId="1" EntityGuid="$($region.levelHolderGuid)">
    <EntityLinks><Link TargetId="$($region.questHolderEntityId)" TargetGuid="00000000-0000-0000" Name="module" /></EntityLinks>
  </Entity>
  <Entity Name="$($region.questHolderName)" EntityClass="SmartObjectHolder" EntityId="$($region.questHolderEntityId)" EntityGuid="$($region.questHolderGuid)">
    <EntityLinks>
$assetLinks
    </EntityLinks>
  </Entity>
$areaEntities
  <Entity Name="vanilla_registry_$($region.id)" EntityClass="VanillaSentinel" EntityId="999" EntityGuid="99999999-9999-9999"><EntityLinks /></Entity>
</Objects>
"@
    Write-AsciiFile `
        -LiteralPath (Join-Path $buildLevel 'objects_mission0.xml') `
        -Content $generatedObjects

    $waitingAreaLinks = @(
        $region.areas | ForEach-Object {
            @"
    <WaitingLink SourceId="$($region.questHolderGuid)" TargetId="$($_.guid)">
      <LinkDefinition>asset[&apos;$($region.alias)&apos;]</LinkDefinition>
    </WaitingLink>
"@
        }
    ) -join ''
    $generatedWaitingLinks = @"
<?xml version="1.0" encoding="us-ascii"?>
<StaticLinksInfo version="1">
  <WaitingLinks>
    <WaitingLink SourceId="vanilla-source-$($region.id)" TargetId="vanilla-target-$($region.id)">
      <LinkDefinition>vanilla</LinkDefinition>
    </WaitingLink>
    <WaitingLink SourceId="$($region.levelHolderGuid)" TargetId="$($region.questHolderGuid)">
      <LinkDefinition>module</LinkDefinition>
    </WaitingLink>
$waitingAreaLinks  </WaitingLinks>
  <StreamableTargets />
</StaticLinksInfo>
"@
    Write-AsciiFile `
        -LiteralPath (Join-Path $buildLevel 'waitinglinks.xml') `
        -Content $generatedWaitingLinks

    Write-AsciiFile `
        -LiteralPath (Join-Path $gameLevel 'objects_mission0.xml') `
        -Content "<old-objects region=`"$($region.id)`" />"
    Write-AsciiFile `
        -LiteralPath (Join-Path $gameLevel 'waitinglinks.xml') `
        -Content "<old-waitinglinks region=`"$($region.id)`" />"

    foreach ($relativePath in @(
        'Layers\main.lyr',
        'whdata_1',
        'leveldata.xml',
        'unrelated-loose-registry.xml'
    )) {
        $sentinelPath = Join-Path $gameLevel $relativePath
        Write-AsciiFile `
            -LiteralPath $sentinelPath `
            -Content "<vanilla-sentinel region=`"$($region.id)`" path=`"$relativePath`" />"
        $sentinelHashes[$sentinelPath] = (
            Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256
        ).Hash
    }
}

$kuttenbergLevel = Join-Path $fixtureGame 'Data\Levels\kutnohorsko'
$troskyLevel = Join-Path $fixtureGame 'Data\Levels\trosecko'
$obsoleteRelativePaths = @(
    'Layers\darkpassenger_investigation_areas_1b986e82-f241-016c-c428-a298fa47119a.xml',
    'Layers\main\_quest\activity\darkpassenger_investigation_areas.lyr'
)
foreach ($relativePath in $obsoleteRelativePaths) {
    Write-AsciiFile `
        -LiteralPath (Join-Path $kuttenbergLevel $relativePath) `
        -Content '<obsolete-pritoky-layer />'
    Write-AsciiFile `
        -LiteralPath (Join-Path $troskyLevel $relativePath) `
        -Content '<same-name-trosky-sentinel />'
}
$unrelatedDarkPassengerFile =
    Join-Path $kuttenbergLevel 'Layers\darkpassenger_investigation_areas.keep'
Write-AsciiFile `
    -LiteralPath $unrelatedDarkPassengerFile `
    -Content '<unrelated-dark-passenger-file />'
$unrelatedHash = (
    Get-FileHash -LiteralPath $unrelatedDarkPassengerFile -Algorithm SHA256
).Hash

Write-AsciiFile `
    -LiteralPath (Join-Path $fixtureGame 'user.cfg') `
    -Content "sys_PakPriority = 0`r`n"

if (-not (Test-Path -LiteralPath $deployScript)) {
    throw "Missing dev level overlay deployer: $deployScript"
}
& $deployScript `
    -BuildRoot $fixtureBuild `
    -DevGameRoot $fixtureGame `
    -BackupRoot $fixtureBackup `
    -GameProcessName 'DarkPassengerOverlayTestNoProcess'

$backupDirectories = @(
    Get-ChildItem -LiteralPath $fixtureBackup -Directory |
        Where-Object Name -Like 'dev-level-*'
)
if ($backupDirectories.Count -ne 1) {
    throw 'Both regions must be preserved in one atomic deployment backup.'
}
$backupDirectory = $backupDirectories[0].FullName

foreach ($region in $regions) {
    $buildLevel = Join-Path $fixtureBuild "Data\Levels\$($region.id)"
    $gameLevel = Join-Path $fixtureGame "Data\Levels\$($region.id)"
    $backupLevel = Join-Path $backupDirectory $region.id
    foreach ($fileName in @('objects_mission0.xml', 'waitinglinks.xml')) {
        $sourcePath = Join-Path $buildLevel $fileName
        $deployedPath = Join-Path $gameLevel $fileName
        $backupPath = Join-Path $backupLevel $fileName
        $oldKind = if ($fileName -eq 'objects_mission0.xml') {
            'objects'
        }
        else {
            'waitinglinks'
        }
        if (
            -not (Test-Path -LiteralPath $deployedPath -PathType Leaf) -or
            (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $deployedPath -Algorithm SHA256).Hash
        ) {
            throw "Deployed $($region.id)/$fileName does not match the generated build."
        }
        if (
            -not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or
            [System.IO.File]::ReadAllText($backupPath) -ne
                "<old-$oldKind region=`"$($region.id)`" />"
        ) {
            throw "Backup does not preserve $($region.id)/$fileName exactly once."
        }
    }
}

foreach ($entry in $sentinelHashes.GetEnumerator()) {
    if (
        -not (Test-Path -LiteralPath $entry.Key -PathType Leaf) -or
        (Get-FileHash -LiteralPath $entry.Key -Algorithm SHA256).Hash -ne
            $entry.Value
    ) {
        throw "Vanilla loose level data was modified: $($entry.Key)"
    }
}
foreach ($relativePath in $obsoleteRelativePaths) {
    if (Test-Path -LiteralPath (Join-Path $kuttenbergLevel $relativePath)) {
        throw "Obsolete Pritoky layer survived deployment: $relativePath"
    }
    if (-not (Test-Path -LiteralPath (
        Join-Path $backupDirectory "kutnohorsko\obsolete\$relativePath"
    ))) {
        throw "Obsolete Pritoky layer was not backed up: $relativePath"
    }
    $troskySentinel = Join-Path $troskyLevel $relativePath
    if (
        -not (Test-Path -LiteralPath $troskySentinel -PathType Leaf) -or
        [System.IO.File]::ReadAllText($troskySentinel) -ne
            '<same-name-trosky-sentinel />'
    ) {
        throw "Deployment removed a non-Pritoky lookalike: $troskySentinel"
    }
}
if (
    -not (Test-Path -LiteralPath $unrelatedDarkPassengerFile -PathType Leaf) -or
    (Get-FileHash -LiteralPath $unrelatedDarkPassengerFile -Algorithm SHA256).Hash -ne
        $unrelatedHash
) {
    throw 'Deployment removed an unrelated Dark Passenger layer file.'
}

# Prove rollback across the regional boundary with a real locked target file.
foreach ($region in $regions) {
    $gameLevel = Join-Path $fixtureGame "Data\Levels\$($region.id)"
    Write-AsciiFile `
        -LiteralPath (Join-Path $gameLevel 'objects_mission0.xml') `
        -Content "<rollback-old-objects region=`"$($region.id)`" />"
    Write-AsciiFile `
        -LiteralPath (Join-Path $gameLevel 'waitinglinks.xml') `
        -Content "<rollback-old-waitinglinks region=`"$($region.id)`" />"
}
$lockedTroskyWaitingLinks = Join-Path $troskyLevel 'waitinglinks.xml'
$lockStream = [System.IO.File]::Open(
    $lockedTroskyWaitingLinks,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
)
$rollbackTriggered = $false
try {
    try {
        & $deployScript `
            -BuildRoot $fixtureBuild `
            -DevGameRoot $fixtureGame `
            -BackupRoot $fixtureBackup `
            -GameProcessName 'DarkPassengerOverlayTestNoProcess'
    }
    catch {
        $rollbackTriggered = $true
    }
}
finally {
    $lockStream.Dispose()
}
if (-not $rollbackTriggered) {
    throw 'Locked Trosky registry did not abort the regional deployment.'
}
foreach ($region in $regions) {
    $gameLevel = Join-Path $fixtureGame "Data\Levels\$($region.id)"
    if (
        [System.IO.File]::ReadAllText(
            (Join-Path $gameLevel 'objects_mission0.xml')
        ) -ne "<rollback-old-objects region=`"$($region.id)`" />" -or
        [System.IO.File]::ReadAllText(
            (Join-Path $gameLevel 'waitinglinks.xml')
        ) -ne "<rollback-old-waitinglinks region=`"$($region.id)`" />"
    ) {
        throw "Failed deployment left a partial regional overlay: $($region.id)"
    }
}

Write-Host 'RESULT: PASS (two-region atomic dev loose level overlay)'
