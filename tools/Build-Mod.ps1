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
$worldExporterPath = Join-Path $PSScriptRoot 'Export-WorldVictimCandidates.ps1'
$localizationRoot = Join-Path $repoRoot 'localization'
$rawEvidencePath = Join-Path $repoRoot 'evidence\world-candidates.raw.json'

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($repoRoot)
$resolvedBuildRoot = [System.IO.Path]::GetFullPath($buildRoot)
$requiredPrefix = [System.IO.Path]::GetFullPath($buildParent) +
    [System.IO.Path]::DirectorySeparatorChar

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
$barboraKuttenbergRoot =
    Join-Path $resolvedBuildRoot 'Data\Quests\Final\Barbora'
$barboraKuttenbergPatchPath =
    Join-Path $barboraKuttenbergRoot 'kutnohorsko.patch.xml'
if (Test-Path -LiteralPath $barboraKuttenbergPatchPath) {
    if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
        throw 'KCD2_DEV_ROOT or -DevGameRoot is required to merge the Barbora Kuttenberg graph.'
    }

    $barboraPatchText =
        [System.IO.File]::ReadAllText($barboraKuttenbergPatchPath)
    try {
        $barboraPatch = [xml]$barboraPatchText
    }
    catch {
        throw "Dark Passenger Barbora Kuttenberg patch is invalid XML: $($_.Exception.Message)"
    }
    $definitionMatch = [regex]::Match(
        $barboraPatchText,
        '<Definition\s+File="kutnohorsko/dark_within_k\.xml"\s*/>'
    )
    $nodeMatch = [regex]::Match(
        $barboraPatchText,
        '(?s)<dark_within_k\b.*?</dark_within_k>'
    )
    if (-not $definitionMatch.Success -or -not $nodeMatch.Success) {
        throw 'Dark Passenger Barbora Kuttenberg patch must contain one definition and quest node.'
    }

    $baseScriptsPak = Join-Path $DevGameRoot 'Data\Scripts.pak'
    if (-not (Test-Path -LiteralPath $baseScriptsPak)) {
        throw "Base Scripts pak not found: $baseScriptsPak"
    }
    $baseScriptsPakItem = Get-Item -LiteralPath $baseScriptsPak
    if ($baseScriptsPakItem.LinkType -and $baseScriptsPakItem.Target) {
        $baseScriptsPak = [string]@($baseScriptsPakItem.Target)[0]
    }
    New-Item -ItemType Directory -Force -Path $barboraKuttenbergRoot |
        Out-Null
    $barboraKuttenbergPath =
        Join-Path $barboraKuttenbergRoot 'kutnohorsko.xml'
    & $sevenZip e -y "-o$barboraKuttenbergRoot" $baseScriptsPak `
        'Quests\Final\Barbora\kutnohorsko.xml' |
        Out-Null
    if (
        $LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $barboraKuttenbergPath)
    ) {
        throw "Unable to extract Barbora Kuttenberg graph from $baseScriptsPak"
    }

    $barboraKuttenbergText =
        [System.IO.File]::ReadAllText($barboraKuttenbergPath)
    if (
        $barboraKuttenbergText.Contains(
            '<Definition File="kutnohorsko/dark_within_k.xml" />'
        ) -or
        $barboraKuttenbergText -match '<dark_within_k\b'
    ) {
        throw 'Base Barbora Kuttenberg graph already contains dark_within_k.'
    }
    $definitionsEnd = $barboraKuttenbergText.IndexOf('</Definitions>')
    $nodesEnd = $barboraKuttenbergText.IndexOf('</Nodes>')
    if ($definitionsEnd -lt 0 -or $nodesEnd -lt 0) {
        throw 'Base Barbora Kuttenberg graph lacks Definitions or Nodes terminator.'
    }
    $definitionBlock =
        "`t`t`t$($definitionMatch.Value)`r`n`t`t"
    $barboraKuttenbergText = $barboraKuttenbergText.Insert(
        $definitionsEnd,
        $definitionBlock
    )
    $nodesEnd = $barboraKuttenbergText.IndexOf('</Nodes>')
    $nodeBlock = (
        $nodeMatch.Value.Trim() -split "`r?`n" |
            ForEach-Object { "`t`t`t$($_.TrimStart())" }
    ) -join "`r`n"
    $barboraKuttenbergText = $barboraKuttenbergText.Insert(
        $nodesEnd,
        "$nodeBlock`r`n`t`t"
    )
    try {
        $null = [xml]$barboraKuttenbergText
    }
    catch {
        throw "Generated Barbora Kuttenberg graph is invalid XML: $($_.Exception.Message)"
    }
    [System.IO.File]::WriteAllText(
        $barboraKuttenbergPath,
        $barboraKuttenbergText,
        [System.Text.UTF8Encoding]::new($false)
    )
    Remove-Item -LiteralPath $barboraKuttenbergPatchPath -Force
}

$kuttenbergLevelRoot = Join-Path $resolvedBuildRoot 'Data\Levels\kutnohorsko'
if (Test-Path -LiteralPath $kuttenbergLevelRoot) {
    if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
        throw 'KCD2_DEV_ROOT or -DevGameRoot is required to build the Kuttenberg asset link.'
    }

    $baseLevelPak = Join-Path $DevGameRoot 'Data\Levels\kutnohorsko\level.pak'
    if (-not (Test-Path -LiteralPath $baseLevelPak)) {
        throw "Base Kuttenberg level pak not found: $baseLevelPak"
    }

    $baseLevelPakItem = Get-Item -LiteralPath $baseLevelPak
    if ($baseLevelPakItem.LinkType -and $baseLevelPakItem.Target) {
        $baseLevelPak = [string]@($baseLevelPakItem.Target)[0]
    }

    $waitingLinksPath = Join-Path $kuttenbergLevelRoot 'waitinglinks.xml'
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
    if ($waitingLinkEntries.Count -ne 2) {
        throw 'Dark Passenger waitinglinks patch must contain the Barbora Level, Quest, and area chain.'
    }
    $linkSignatures = @(
        $waitingLinkEntries | ForEach-Object {
            "$([string]$_.SourceId)|$([string]$_.TargetId)|$([string]$_.LinkDefinition)"
        }
    )
    if (
        '10702dff-9271-4a74|f4a73e20-28c5-4bd2|module' -notin
            $linkSignatures -or
        "f4a73e20-28c5-4bd2|d0fa0ece-6af5-19f6|asset['DP_PritokySearchArea']" -notin
            $linkSignatures
    ) {
        throw 'Dark Passenger waitinglinks patch has an unexpected Barbora-Level-Quest binding.'
    }

    $missionObjectsPatchPath =
        Join-Path $kuttenbergLevelRoot 'objects_mission0.patch.xml'
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

    $objectsMissionPath =
        Join-Path $kuttenbergLevelRoot 'objects_mission0.xml'
    & $sevenZip e -y "-o$kuttenbergLevelRoot" $baseLevelPak `
        'objects_mission0.xml' |
        Out-Null
    if (
        $LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath $objectsMissionPath)
    ) {
        throw "Unable to extract Kuttenberg mission objects from $baseLevelPak"
    }

    $objectsMissionText =
        [System.IO.File]::ReadAllText($objectsMissionPath)
    if ($objectsMissionText.Contains('EntityGuid="f4a73e20-28c5-4bd2"') -or
        $objectsMissionText.Contains('EntityId="1831841"') -or
        $objectsMissionText.Contains('Name="dark_within_k"')) {
        throw 'Base Kuttenberg mission objects already contain a Dark Passenger concept-graph identity.'
    }
    $objectsEnd = $objectsMissionText.LastIndexOf('</Objects>')
    if ($objectsEnd -lt 0) {
        throw 'Base Kuttenberg mission objects have no Objects root terminator.'
    }
    $missionObjectBlock = @(
        $missionObjectEntries | ForEach-Object { $_.Value.Trim() }
    ) -join "`r`n`t"
    $objectsMissionText = $objectsMissionText.Insert(
        $objectsEnd,
        "`t$missionObjectBlock`r`n"
    )

    foreach ($waitingLink in $waitingLinkEntries) {
        $sourceGuid = [string]$waitingLink.SourceId
        $targetGuid = [string]$waitingLink.TargetId
        $linkDefinition = [string]$waitingLink.LinkDefinition
        $sourceGuidPattern = [regex]::Escape($sourceGuid)
        $targetGuidPattern = [regex]::Escape($targetGuid)
        $sourceMatches = @(
            [regex]::Matches(
                $objectsMissionText,
                "(?s)<Entity\b(?=[^>]*EntityGuid=`"$sourceGuidPattern`")[^>]*>.*?</Entity>"
            )
        )
        $targetMatches = @(
            [regex]::Matches(
                $objectsMissionText,
                "<Entity\b(?=[^>]*EntityGuid=`"$targetGuidPattern`")[^>]*>"
            )
        )
        if ($sourceMatches.Count -ne 1 -or $targetMatches.Count -ne 1) {
            throw (
                'Unable to resolve unique Kuttenberg link entities: ' +
                "sourceGuid=$sourceGuid source=$($sourceMatches.Count) " +
                "targetGuid=$targetGuid target=$($targetMatches.Count)"
            )
        }

        $targetIdMatch = [regex]::Match(
            $targetMatches[0].Value,
            'EntityId="([0-9]+)"'
        )
        if (-not $targetIdMatch.Success) {
            throw "Kuttenberg link target '$targetGuid' has no numeric EntityId."
        }
        $targetEntityId = $targetIdMatch.Groups[1].Value
        $targetEntityIdPattern = [regex]::Escape($targetEntityId)
        $sourceEntityText = $sourceMatches[0].Value
        $duplicateLinkPattern =
            "<Link\b(?=[^>]*TargetId=`"$targetEntityIdPattern`")(?=[^>]*Name=`"$([regex]::Escape($linkDefinition))`")[^>]*/>"
        if ([regex]::IsMatch($sourceEntityText, $duplicateLinkPattern)) {
            throw "Kuttenberg source '$sourceGuid' already contains '$linkDefinition'."
        }
        $entityLink =
            "`t`t`t<Link TargetId=`"$targetEntityId`" TargetGuid=`"00000000-0000-0000`" Name=`"$linkDefinition`" />`r`n`t`t"
        if ($sourceEntityText -match '<EntityLinks\s*/>') {
            $sourceEntityText = [regex]::Replace(
                $sourceEntityText,
                '<EntityLinks\s*/>',
                "<EntityLinks>`r`n$entityLink</EntityLinks>",
                1
            )
        }
        else {
            $entityLinksEnd = $sourceEntityText.IndexOf('</EntityLinks>')
            if ($entityLinksEnd -lt 0) {
                throw "Kuttenberg source '$sourceGuid' has no EntityLinks section."
            }
            $sourceEntityText =
                $sourceEntityText.Insert($entityLinksEnd, $entityLink)
        }
        $objectsMissionText =
            $objectsMissionText.Remove(
                $sourceMatches[0].Index,
                $sourceMatches[0].Length
            ).Insert($sourceMatches[0].Index, $sourceEntityText)
    }
    try {
        $null = [xml]$objectsMissionText
    }
    catch {
        throw "Generated Kuttenberg mission objects are invalid XML: $($_.Exception.Message)"
    }
    [System.IO.File]::WriteAllText(
        $objectsMissionPath,
        $objectsMissionText,
        [System.Text.Encoding]::ASCII
    )

    $baseExtractRoot = Join-Path $kuttenbergLevelRoot '_base_level'
    $resolvedBaseExtractRoot = [System.IO.Path]::GetFullPath(
        $baseExtractRoot
    )
    $resolvedLevelPrefix =
        [System.IO.Path]::GetFullPath($kuttenbergLevelRoot) +
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
            throw "Unable to extract Kuttenberg waitinglinks from $baseLevelPak"
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
                'Base Kuttenberg waitinglinks already contain a Dark Passenger link: ' +
                "$sourceGuid -> $targetGuid"
            )
        }
    }
    $waitingLinksEnd =
        $baseWaitingLinksText.LastIndexOf('</WaitingLinks>')
    if ($waitingLinksEnd -lt 0) {
        throw 'Base Kuttenberg waitinglinks have no WaitingLinks terminator.'
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
        throw "Generated Kuttenberg waitinglinks are invalid XML: $($_.Exception.Message)"
    }
    [System.IO.File]::WriteAllText(
        $waitingLinksPath,
        $mergedWaitingLinksText,
        [System.Text.Encoding]::ASCII
    )
    Remove-Item -LiteralPath $missionObjectsPatchPath -Force
}

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

if (Test-Path -LiteralPath $kuttenbergLevelRoot) {
    $kuttenbergLevelPak = Join-Path $kuttenbergLevelRoot 'darkpassengertest.pak'
    $kuttenbergLevelInputs = @(
        'objects_mission0.xml',
        'waitinglinks.xml'
    ) |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $kuttenbergLevelRoot $_)
        }

    if ($kuttenbergLevelInputs.Count -gt 0) {
        Push-Location $kuttenbergLevelRoot
        try {
            & $sevenZip a -tzip -mx=9 -mtc=off `
                $kuttenbergLevelPak $kuttenbergLevelInputs |
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
