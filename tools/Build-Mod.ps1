param(
    [switch]$SkipPackaging,
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot 'src'
$buildRoot = Join-Path $repoRoot 'build\mod'
$buildParent = Join-Path $repoRoot 'build'
$generatorPath = Join-Path $PSScriptRoot 'Generate-VictimArtifacts.ps1'
$areaBindingGeneratorPath =
    Join-Path $PSScriptRoot 'Generate-SettlementAreaBindings.ps1'
$levelRegistryMergeModulePath =
    Join-Path $PSScriptRoot 'LevelRegistryMerge.psm1'
$worldExporterPath = Join-Path $PSScriptRoot 'Export-WorldVictimCandidates.ps1'
$localizationRoot = Join-Path $repoRoot 'localization'
$rawEvidencePath = Join-Path $repoRoot 'evidence\world-candidates.raw.json'

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($repoRoot)
$resolvedBuildRoot = [System.IO.Path]::GetFullPath($buildRoot)
$requiredPrefix = [System.IO.Path]::GetFullPath($buildParent) +
    [System.IO.Path]::DirectorySeparatorChar

Import-Module $levelRegistryMergeModulePath -Force

function Set-ReproducibleTimestamps {
    param([string]$LiteralPath)

    $timestamp = [datetime]::new(
        2000,
        1,
        1,
        0,
        0,
        0,
        [System.DateTimeKind]::Utc
    )
    $items = @(Get-ChildItem -LiteralPath $LiteralPath -Recurse -Force)

    foreach ($item in $items | Where-Object { -not $_.PSIsContainer }) {
        $item.LastWriteTimeUtc = $timestamp
    }
    foreach (
        $item in $items |
            Where-Object { $_.PSIsContainer } |
            Sort-Object { $_.FullName.Length } -Descending
    ) {
        $item.LastWriteTimeUtc = $timestamp
    }

    (Get-Item -LiteralPath $LiteralPath).LastWriteTimeUtc = $timestamp
}

if (-not $resolvedBuildRoot.StartsWith(
    $requiredPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to replace build path outside repository build root: $resolvedBuildRoot"
}

& $areaBindingGeneratorPath

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

$sevenZip = (Get-Command 7z.exe -ErrorAction Stop).Source
function Merge-BarboraRegionalGraph {
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$QuestName
    )

    $barboraRoot =
        Join-Path $resolvedBuildRoot 'Data\Quests\Final\Barbora'
    $patchPath = Join-Path $barboraRoot "$Region.patch.xml"
    if (-not (Test-Path -LiteralPath $patchPath)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
        throw "KCD2_DEV_ROOT or -DevGameRoot is required to merge the Barbora $Region graph."
    }

    $patchText = [System.IO.File]::ReadAllText($patchPath)
    try {
        $null = [xml]$patchText
    }
    catch {
        throw "Dark Passenger Barbora $Region patch is invalid XML: $($_.Exception.Message)"
    }
    $escapedRegion = [regex]::Escape($Region)
    $escapedQuestName = [regex]::Escape($QuestName)
    $definitionMatch = [regex]::Match(
        $patchText,
        "<Definition\s+File=`"$escapedRegion/$escapedQuestName\.xml`"\s*/>"
    )
    $nodeMatch = [regex]::Match(
        $patchText,
        "(?s)<$escapedQuestName\b.*?</$escapedQuestName>"
    )
    if (-not $definitionMatch.Success -or -not $nodeMatch.Success) {
        throw "Dark Passenger Barbora $Region patch must contain one definition and quest node."
    }

    $baseScriptsPak = Join-Path $DevGameRoot 'Data\Scripts.pak'
    if (-not (Test-Path -LiteralPath $baseScriptsPak)) {
        throw "Base Scripts pak not found: $baseScriptsPak"
    }
    $baseScriptsPakItem = Get-Item -LiteralPath $baseScriptsPak
    if ($baseScriptsPakItem.LinkType -and $baseScriptsPakItem.Target) {
        $baseScriptsPak = [string]@($baseScriptsPakItem.Target)[0]
    }
    New-Item -ItemType Directory -Force -Path $barboraRoot | Out-Null
    $regionalGraphPath = Join-Path $barboraRoot "$Region.xml"
    & $sevenZip e -y "-o$barboraRoot" $baseScriptsPak `
        "Quests\Final\Barbora\$Region.xml" |
        Out-Null
    if (
        $LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $regionalGraphPath)
    ) {
        throw "Unable to extract Barbora $Region graph from $baseScriptsPak"
    }

    $regionalGraphText = [System.IO.File]::ReadAllText($regionalGraphPath)
    if (
        $regionalGraphText.Contains(
            "<Definition File=`"$Region/$QuestName.xml`" />"
        ) -or
        $regionalGraphText -match "<$escapedQuestName\b"
    ) {
        throw "Base Barbora $Region graph already contains $QuestName."
    }
    $definitionsEnd = $regionalGraphText.IndexOf('</Definitions>')
    $nodesEnd = $regionalGraphText.IndexOf('</Nodes>')
    if ($definitionsEnd -lt 0 -or $nodesEnd -lt 0) {
        throw "Base Barbora $Region graph lacks Definitions or Nodes terminator."
    }
    $regionalGraphText = $regionalGraphText.Insert(
        $definitionsEnd,
        "`t`t`t$($definitionMatch.Value)`r`n`t`t"
    )
    $nodesEnd = $regionalGraphText.IndexOf('</Nodes>')
    $nodeBlock = (
        $nodeMatch.Value.Trim() -split "`r?`n" |
            ForEach-Object { "`t`t`t$($_.TrimStart())" }
    ) -join "`r`n"
    $regionalGraphText = $regionalGraphText.Insert(
        $nodesEnd,
        "$nodeBlock`r`n`t`t"
    )
    try {
        $null = [xml]$regionalGraphText
    }
    catch {
        throw "Generated Barbora $Region graph is invalid XML: $($_.Exception.Message)"
    }
    [System.IO.File]::WriteAllText(
        $regionalGraphPath,
        $regionalGraphText,
        [System.Text.UTF8Encoding]::new($false)
    )
    Remove-Item -LiteralPath $patchPath -Force
}

Merge-BarboraRegionalGraph -Region 'kutnohorsko' -QuestName 'dark_within_k'
Merge-BarboraRegionalGraph -Region 'trosecko' -QuestName 'dark_within_t'

$levelHolderGuids = @{
    kutnohorsko = '10702dff-9271-4a74'
    trosecko = '30277b74-1c65-41e9'
}
$regionalLevelRoots = [System.Collections.Generic.List[string]]::new()
$regionalRegistryStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($region in @('kutnohorsko', 'trosecko')) {
    $regionalLevelRoot = Join-Path $resolvedBuildRoot "Data\Levels\$region"
    if (-not (Test-Path -LiteralPath $regionalLevelRoot)) {
        continue
    }
    $regionalLevelRoots.Add($regionalLevelRoot)
    if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
        throw "KCD2_DEV_ROOT or -DevGameRoot is required to build the $region asset links."
    }

    $baseLevelPak = Join-Path $DevGameRoot "Data\Levels\$region\level.pak"
    if (-not (Test-Path -LiteralPath $baseLevelPak)) {
        throw "Base $region level pak not found: $baseLevelPak"
    }

    $baseLevelPakItem = Get-Item -LiteralPath $baseLevelPak
    if ($baseLevelPakItem.LinkType -and $baseLevelPakItem.Target) {
        $baseLevelPak = [string]@($baseLevelPakItem.Target)[0]
    }

    $waitingLinksPath = Join-Path $regionalLevelRoot 'waitinglinks.xml'
    $waitingLinksPatchText =
        [System.IO.File]::ReadAllText($waitingLinksPath)
    try {
        $waitingLinksPatch = [xml]$waitingLinksPatchText
    }
    catch {
        throw "Dark Passenger waitinglinks patch is invalid XML: $($_.Exception.Message)"
    }
    $waitingLinkEntries = @(
        $waitingLinksPatch.StaticLinksInfo.WaitingLinks.WaitingLink
    )
    if ($waitingLinkEntries.Count -lt 2) {
        throw "Dark Passenger $region waitinglinks patch must contain a module link and settlement area links."
    }
    $linkSignatures = @(
        $waitingLinkEntries | ForEach-Object {
            "$([string]$_.SourceId)|$([string]$_.TargetId)|$([string]$_.LinkDefinition)"
        }
    )
    $duplicateLinkSignature = $linkSignatures |
        Group-Object |
        Where-Object Count -gt 1 |
        Select-Object -First 1
    $moduleLinks = @(
        $waitingLinkEntries |
            Where-Object { [string]$_.LinkDefinition -eq 'module' }
    )
    if (
        $null -ne $duplicateLinkSignature -or
        $moduleLinks.Count -ne 1 -or
        [string]$moduleLinks[0].SourceId -ne $levelHolderGuids[$region]
    ) {
        throw "Dark Passenger $region waitinglinks patch has an invalid module link."
    }
    $questHolderGuid = [string]$moduleLinks[0].TargetId
    $assetLinks = @(
        $waitingLinkEntries |
            Where-Object { [string]$_.LinkDefinition -ne 'module' }
    )
    $legacyPritokyDefinition = "asset['DP_PritokySearchArea']"
    $legacyPritokyLinks = @(
        $assetLinks |
            Where-Object {
                [string]$_.LinkDefinition -eq $legacyPritokyDefinition
            }
    )
    $expectedLegacyPritokyLinks = if ($region -eq 'kutnohorsko') {
        3
    }
    else {
        0
    }
    if (
        @($assetLinks | Where-Object {
            $definition = [string]$_.LinkDefinition
            [string]$_.SourceId -ne $questHolderGuid -or
            (
                $definition -notmatch
                    "^asset\['DP_SearchArea_[A-Za-z0-9_]+'\]$" -and
                -not (
                    $region -eq 'kutnohorsko' -and
                    $definition -eq $legacyPritokyDefinition
                )
            )
        }).Count -gt 0 -or
        $legacyPritokyLinks.Count -ne $expectedLegacyPritokyLinks
    ) {
        throw "Dark Passenger $region waitinglinks patch has an invalid settlement area link."
    }

    $missionObjectsPatchPath =
        Join-Path $regionalLevelRoot 'objects_mission0.patch.xml'
    $missionObjectsPatchText =
        [System.IO.File]::ReadAllText($missionObjectsPatchPath)
    $missionObjectEntries = @(
        [regex]::Matches(
            $missionObjectsPatchText,
            '(?s)<Entity\b.*?</Entity>'
        )
    )
    if ($missionObjectEntries.Count -ne 1) {
        throw 'Dark Passenger mission-object patch must contain only the Quest holder.'
    }
    try {
        $missionObjectsPatch = [xml]$missionObjectsPatchText
    }
    catch {
        throw "Dark Passenger $region mission-object patch is invalid XML: $($_.Exception.Message)"
    }
    $questHolder = @($missionObjectsPatch.Objects.Entity)
    if (
        $questHolder.Count -ne 1 -or
        [string]$questHolder[0].EntityClass -ne 'SmartObjectHolder' -or
        [string]$questHolder[0].EntityGuid -ne $questHolderGuid
    ) {
        throw "Dark Passenger $region mission-object patch does not match its waitinglinks quest holder."
    }
    $questHolderEntityId = [string]$questHolder[0].EntityId
    $questHolderName = [string]$questHolder[0].Name

    $objectsMissionPath =
        Join-Path $regionalLevelRoot 'objects_mission0.xml'
    & $sevenZip e -y "-o$regionalLevelRoot" $baseLevelPak `
        'objects_mission0.xml' |
        Out-Null
    if (
        $LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $objectsMissionPath)
    ) {
        throw "Unable to extract $region mission objects from $baseLevelPak"
    }

    $objectsMissionText =
        [System.IO.File]::ReadAllText($objectsMissionPath)
    if ($objectsMissionText.Contains("EntityGuid=`"$questHolderGuid`"") -or
        $objectsMissionText.Contains("EntityId=`"$questHolderEntityId`"") -or
        $objectsMissionText.Contains("Name=`"$questHolderName`"")) {
        throw "Base $region mission objects already contain a Dark Passenger concept-graph identity."
    }
    $missionObjectBlock = @(
        $missionObjectEntries | ForEach-Object { $_.Value.Trim() }
    ) -join "`r`n`t"
    $objectsMissionText = Merge-LevelMissionObjects `
        -BaseObjectsText $objectsMissionText `
        -MissionObjectBlock $missionObjectBlock `
        -WaitingLinks $waitingLinkEntries `
        -Region $region
    try {
        $null = [xml]$objectsMissionText
    }
    catch {
        throw "Generated $region mission objects are invalid XML: $($_.Exception.Message)"
    }
    [System.IO.File]::WriteAllText(
        $objectsMissionPath,
        $objectsMissionText,
        [System.Text.Encoding]::ASCII
    )

    $baseExtractRoot = Join-Path $regionalLevelRoot '_base_level'
    $resolvedBaseExtractRoot = [System.IO.Path]::GetFullPath(
        $baseExtractRoot
    )
    $resolvedLevelPrefix =
        [System.IO.Path]::GetFullPath($regionalLevelRoot) +
        [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedBaseExtractRoot.StartsWith(
        $resolvedLevelPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to replace base extraction outside build level root: $resolvedBaseExtractRoot"
    }
    if (Test-Path -LiteralPath $baseExtractRoot) {
        Remove-Item -LiteralPath $baseExtractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $baseExtractRoot -Force |
        Out-Null
    try {
        & $sevenZip e -y "-o$baseExtractRoot" $baseLevelPak `
            'waitinglinks.xml' |
            Out-Null
        $baseWaitingLinksPath =
            Join-Path $baseExtractRoot 'waitinglinks.xml'
        if (
            $LASTEXITCODE -ne 0 -or
            -not (Test-Path -LiteralPath $baseWaitingLinksPath)
        ) {
            throw "Unable to extract $region waitinglinks from $baseLevelPak"
        }
        $baseWaitingLinksText =
            [System.IO.File]::ReadAllText($baseWaitingLinksPath)
    }
    finally {
        if (Test-Path -LiteralPath $baseExtractRoot) {
            Remove-Item -LiteralPath $baseExtractRoot -Recurse -Force
        }
    }

    foreach ($waitingLink in $waitingLinkEntries) {
        $sourceGuid = [string]$waitingLink.SourceId
        $targetGuid = [string]$waitingLink.TargetId
        if (
            $baseWaitingLinksText.Contains(
                "SourceId=`"$sourceGuid`" TargetId=`"$targetGuid`""
            )
        ) {
            throw (
                "Base $region waitinglinks already contain a Dark Passenger link: " +
                "$sourceGuid -> $targetGuid"
            )
        }
    }
    $waitingLinksEnd =
        $baseWaitingLinksText.LastIndexOf('</WaitingLinks>')
    if ($waitingLinksEnd -lt 0) {
        throw "Base $region waitinglinks have no WaitingLinks terminator."
    }
    $customWaitingLinks = @(
        $waitingLinkEntries | ForEach-Object {
            $sourceGuid = [string]$_.SourceId
            $targetGuid = [string]$_.TargetId
            $linkDefinition = [string]$_.LinkDefinition
            $encodedDefinition = $linkDefinition.Replace(
                '&',
                '&amp;'
            ).Replace("'", '&apos;')
            @(
                "`t`t<WaitingLink SourceId=`"$sourceGuid`" TargetId=`"$targetGuid`">"
                "`t`t`t<LinkDefinition>$encodedDefinition</LinkDefinition>"
                "`t`t</WaitingLink>"
            ) -join "`r`n"
        }
    ) -join "`r`n"
    $mergedWaitingLinksText = $baseWaitingLinksText.Insert(
        $waitingLinksEnd,
        "$customWaitingLinks`r`n`t"
    )
    try {
        $null = [xml]$mergedWaitingLinksText
    }
    catch {
        throw "Generated $region waitinglinks are invalid XML: $($_.Exception.Message)"
    }
    [System.IO.File]::WriteAllText(
        $waitingLinksPath,
        $mergedWaitingLinksText,
        [System.Text.Encoding]::ASCII
    )
    Remove-Item -LiteralPath $missionObjectsPatchPath -Force
}
$regionalRegistryStopwatch.Stop()
Write-Host (
    'Merged regional level registries in {0:N2}s' -f
        $regionalRegistryStopwatch.Elapsed.TotalSeconds
)

Set-ReproducibleTimestamps -LiteralPath $resolvedBuildRoot

if ($SkipPackaging) {
    Write-Host "Prepared generated build tree: $resolvedBuildRoot"
    exit 0
}

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

foreach ($regionalLevelRoot in $regionalLevelRoots) {
    $regionalLevelPak = Join-Path $regionalLevelRoot 'darkpassengertest.pak'
    $regionalLevelInputs = @(
        'objects_mission0.xml',
        'waitinglinks.xml'
    ) |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $regionalLevelRoot $_)
        }

    if ($regionalLevelInputs.Count -gt 0) {
        Push-Location $regionalLevelRoot
        try {
            & $sevenZip a -tzip -mx=9 -mtc=off `
                $regionalLevelPak $regionalLevelInputs |
                Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "7-Zip failed to build $regionalLevelPak"
            }
        }
        finally {
            Pop-Location
        }

        & $sevenZip t $regionalLevelPak | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip integrity test failed for $regionalLevelPak"
        }
    }
}

foreach ($language in @('English', 'Russian')) {
    $sourceFile = Join-Path $localizationRoot "$language\text__darkpassengertest.xml"
    $outputPak = Join-Path $localizationOutput "${language}_xml.pak"
    Push-Location (Split-Path -Parent $sourceFile)
    try {
        & $sevenZip a -tzip -mx=9 -mtc=off `
            $outputPak (Split-Path -Leaf $sourceFile) |
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
