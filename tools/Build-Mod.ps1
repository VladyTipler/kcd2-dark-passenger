param(
    [switch]$SkipPackaging,
    [switch]$SkipDialogueMedia,
    [switch]$ForceDialogueMedia,
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT,
    [string]$ReferenceDataRoot = $env:KCD2_REFERENCE_DATA_ROOT,
    [string]$WorldSoulTablePath = $env:KCD2_WORLD_SOUL_TABLE,
    [string]$DialogueMediaResultsPath = $env:DP_DIALOGUE_MEDIA_RESULTS,
    [string]$DialogueMediaPython = $env:DP_DIALOGUE_MEDIA_PYTHON,
    [string]$DialogueMediaModdingRoot = $env:DP_DIALOGUE_MEDIA_MODDING_ROOT,
    [string]$DialogueMediaBaselineRoot = $env:DP_DIALOGUE_MEDIA_BASELINE_ROOT,
    [string]$DialogueMediaBaseFacialImage = $env:DP_DIALOGUE_MEDIA_BASE_IMAGE,
    [string]$DialogueMediaPhonemeExecutable = $env:DP_DIALOGUE_MEDIA_PHONEMES,
    [string]$DialogueMediaCacheRoot = $env:DP_DIALOGUE_MEDIA_CACHE,
    [string]$DialogueMediaVoiceProfileRoot = $env:DP_DIALOGUE_MEDIA_PROFILES,
    [string]$DialogueMediaOutputRoot = $env:DP_DIALOGUE_MEDIA_OUTPUT,
    [string]$DialogueMediaServerUrl = 'http://127.0.0.1:7860'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$sourceRoot = Join-Path $repoRoot 'src'
$buildRoot = Join-Path $repoRoot 'build\mod'
$buildParent = Join-Path $repoRoot 'build'
$generatorPath = Join-Path $PSScriptRoot 'Generate-VictimArtifacts.ps1'
$caseCompilerPath = Join-Path $PSScriptRoot 'Compile-CaseSpecs.ps1'
$dialogueVoicePakBuilderPath = Join-Path $PSScriptRoot `
    'Build-DialogueVoicePak.ps1'
$dialogueFacialAssetBuilderPath = Join-Path $PSScriptRoot `
    'Build-DialogueFacialAssets.ps1'
$dialogueMediaResultsConsumerPath = Join-Path $PSScriptRoot `
    'Import-DialogueMediaResults.ps1'
$dialogueMediaKitRoot = Join-Path $workspaceRoot 'DialogueMediaKit'
$dialogueMediaBuilderPath = Join-Path $dialogueMediaKitRoot `
    'tools\Build-Kcd2Media.ps1'
$caseKitCompilerPath = Join-Path $repoRoot `
    'casekit\cli\Compile-CaseKit.ps1'
$worldIndexBuilderPath = Join-Path $repoRoot `
    'casekit\cli\Build-WorldSemanticIndex.ps1'
$archetypeRoot = Join-Path $repoRoot 'content\archetypes'
$storyRoot = Join-Path $repoRoot 'content\stories'
$evidenceModuleRoot = Join-Path $repoRoot 'content\evidence-modules'
$worldIndexPath = Join-Path $repoRoot 'config\world-semantic-index.json'
$settlementCatalogPath = Join-Path $repoRoot `
    'config\settlement-investigation-areas.json'
$settlementProfileRoot = Join-Path $repoRoot 'config\settlements'
$stableIdRegistryPath = Join-Path $repoRoot 'config\casekit-stable-ids.json'
$kcd2AdapterPath = Join-Path $repoRoot 'config\casekit-kcd2-native.json'
$caseVariantRoot = Join-Path $buildParent `
    'generated\casekit\compiler-input'
$areaBindingGeneratorPath =
    Join-Path $PSScriptRoot 'Generate-SettlementAreaBindings.ps1'
$levelRegistryMergeModulePath =
    Join-Path $PSScriptRoot 'LevelRegistryMerge.psm1'
$worldExporterPath = Join-Path $PSScriptRoot 'Export-WorldVictimCandidates.ps1'
$generatedLocalizationRoot = Join-Path $buildParent 'generated\localization'
$dialogueVoiceManifestPath = Join-Path $buildParent `
    'generated\voice\dialogue-voice-manifest.json'
$dialogueMediaJobsPath = Join-Path $buildParent `
    'generated\voice\dialogue-media-jobs.json'
$dialogueMediaResolvedJobsPath = Join-Path $buildParent `
    'generated\voice\dialogue-media-jobs-resolved.json'
if ([string]::IsNullOrWhiteSpace($DialogueMediaResultsPath)) {
    $DialogueMediaResultsPath = Join-Path $buildParent `
        'generated\voice\dialogue-media-results.json'
}
if ([string]::IsNullOrWhiteSpace($DialogueMediaOutputRoot)) {
    $DialogueMediaOutputRoot = Join-Path $buildParent `
        'generated\voice\media-output'
}
if ([string]::IsNullOrWhiteSpace($DialogueMediaCacheRoot)) {
    $DialogueMediaCacheRoot = Join-Path $dialogueMediaKitRoot `
        '.cache\dark-passenger-media'
}
if ([string]::IsNullOrWhiteSpace($DialogueMediaVoiceProfileRoot)) {
    $DialogueMediaVoiceProfileRoot = Join-Path $dialogueMediaKitRoot `
        '.cache\dark-passenger-voice-profiles'
}
if ([string]::IsNullOrWhiteSpace($DialogueMediaBaselineRoot)) {
    $DialogueMediaBaselineRoot = Join-Path $workspaceRoot `
        '_work\native-lipsync-pilot'
}
if ([string]::IsNullOrWhiteSpace($DialogueMediaBaseFacialImage)) {
    $DialogueMediaBaseFacialImage = Join-Path $workspaceRoot `
        '_work\retail-facials-2026-08-16\part0\Animations\FacialAnimations.img'
}
if ([string]::IsNullOrWhiteSpace($DialogueMediaPhonemeExecutable)) {
    $DialogueMediaPhonemeExecutable = Join-Path $workspaceRoot `
        '_work\facial-pipeline-2026-08-16\bin\dp-phonemes.exe'
}
$rawEvidencePath = Join-Path $repoRoot 'evidence\world-candidates.raw.json'
$victimCatalogPath = Join-Path $repoRoot 'config\victim-candidates.json'

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

if (-not [string]::IsNullOrWhiteSpace($ReferenceDataRoot)) {
    if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
        throw 'KCD2_DEV_ROOT or -DevGameRoot is required to refresh world data.'
    }
    if ([string]::IsNullOrWhiteSpace($WorldSoulTablePath)) {
        $WorldSoulTablePath = Join-Path $DevGameRoot `
            'Data\libs\CryHttp\xzar2\table-souls.json'
    }
    if (-not (Test-Path -LiteralPath $WorldSoulTablePath)) {
        throw 'KCD2_WORLD_SOUL_TABLE or -WorldSoulTablePath must point to table-souls.json.'
    }
    & $worldExporterPath `
        -KuttenbergObjectsPath (Join-Path $ReferenceDataRoot `
            'kutnohorsko\kut_objects_mission0.xml') `
        -TroskyObjectsPath (Join-Path $ReferenceDataRoot `
            'trosecko\tros_objects_mission0.xml') `
        -SoulTablePath $WorldSoulTablePath `
        -OutputPath $rawEvidencePath
}
elseif (-not (Test-Path -LiteralPath $rawEvidencePath)) {
    & $worldExporterPath
}

& $worldIndexBuilderPath `
    -RawWorldPath $rawEvidencePath `
    -VictimCatalogPath $victimCatalogPath `
    -OutputPath $worldIndexPath

& $caseKitCompilerPath `
    -ArchetypeRoot $archetypeRoot `
    -StoryRoot $storyRoot `
    -EvidenceModuleRoot $evidenceModuleRoot `
    -WorldIndexPath $worldIndexPath `
    -SettlementCatalogPath $settlementCatalogPath `
    -SettlementProfileRoot $settlementProfileRoot `
    -StableIdRegistryPath $stableIdRegistryPath `
    -Kcd2AdapterPath $kcd2AdapterPath `
    -MaxVariantsPerCombination 8 `
    -OutputRoot $caseVariantRoot

& $areaBindingGeneratorPath `
    -CompiledDefinitionsPath (
        Join-Path $caseVariantRoot 'compiled-definitions.json'
    ) `
    -SettlementBindingsPath (
        Join-Path $caseVariantRoot 'case-settlement-bindings.json'
    )

if (Test-Path -LiteralPath $resolvedBuildRoot) {
    Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedBuildRoot -Force | Out-Null

foreach ($item in Get-ChildItem -LiteralPath $sourceRoot -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination $resolvedBuildRoot -Recurse
}

$caseCompilerParameters = @{
    CaseVariantRoot = $caseVariantRoot
    BuildRoot = $buildParent
}
if (
    $SkipDialogueMedia -and
    (Test-Path -LiteralPath $DialogueMediaResultsPath -PathType Leaf)
) {
    if (-not (Test-Path -LiteralPath $dialogueMediaResolvedJobsPath `
        -PathType Leaf)) {
        throw 'DIALOGUE_MEDIA_JOBS_MISSING: Resolved jobs are required for ' +
            "dialogue media results: $dialogueMediaResolvedJobsPath"
    }
    $caseCompilerParameters.DialogueMediaResolvedJobsPath =
        $dialogueMediaResolvedJobsPath
    $caseCompilerParameters.DialogueMediaResultsPath =
        $DialogueMediaResultsPath
}
& $caseCompilerPath @caseCompilerParameters

if (-not $SkipDialogueMedia) {
    if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
        throw 'KCD2_DEV_ROOT or -DevGameRoot must point to the retail game ' +
            'root for automatic dialogue media preparation.'
    }
    if (-not (Test-Path -LiteralPath $dialogueMediaBuilderPath -PathType Leaf)) {
        throw "DialogueMediaKit builder is missing: $dialogueMediaBuilderPath"
    }
    if ([string]::IsNullOrWhiteSpace($DialogueMediaModdingRoot)) {
        $DialogueMediaModdingRoot = Join-Path (Split-Path -Parent $DevGameRoot) `
            'KCD2Mod'
    }
    if ([string]::IsNullOrWhiteSpace($DialogueMediaPython)) {
        $knownOmniPython = 'E:\AI\OmniVoice\.venv\Scripts\python.exe'
        if (Test-Path -LiteralPath $knownOmniPython -PathType Leaf) {
            $DialogueMediaPython = $knownOmniPython
        }
        else {
            $DialogueMediaPython = (Get-Command python.exe `
                -ErrorAction Stop).Source
        }
    }

    $mediaParameters = @{
        DemandsPath = Join-Path $buildParent `
            'generated\voice\dialogue-media-demands.json'
        GeneratedRoot = Join-Path $buildParent 'generated\voice'
        OutputRoot = $DialogueMediaOutputRoot
        ResultsPath = $DialogueMediaResultsPath
        TablesPak = Join-Path $DevGameRoot 'Data\Tables.pak'
        LocalizationRoot = Join-Path $DevGameRoot 'Localization'
        ModdingRoot = $DialogueMediaModdingRoot
        BaselineRoot = $DialogueMediaBaselineRoot
        BaseFacialImage = $DialogueMediaBaseFacialImage
        PhonemeExecutable = $DialogueMediaPhonemeExecutable
        PhonemePluginRoot = Join-Path $DialogueMediaModdingRoot `
            'Editor\Plugins\LipSync\Annosoft'
        SettingsPath = Join-Path $dialogueMediaKitRoot `
            'config\omnivoice-kcd2-english.json'
        CacheRoot = $DialogueMediaCacheRoot
        VoiceProfileRoot = $DialogueMediaVoiceProfileRoot
        PythonExecutable = $DialogueMediaPython
        ServerUrl = $DialogueMediaServerUrl
    }
    if ($ForceDialogueMedia) {
        $mediaParameters.Force = $true
    }
    & $dialogueMediaBuilderPath @mediaParameters

    $caseCompilerParameters.DialogueMediaResolvedJobsPath =
        $dialogueMediaResolvedJobsPath
    $caseCompilerParameters.DialogueMediaResultsPath =
        $DialogueMediaResultsPath
    & $caseCompilerPath @caseCompilerParameters
}

& $generatorPath

if (
    -not (Test-Path -LiteralPath $DialogueMediaResultsPath -PathType Leaf) -and
    (Test-Path -LiteralPath $dialogueVoiceManifestPath -PathType Leaf)
) {
    & $dialogueFacialAssetBuilderPath `
        -ManifestPath $dialogueVoiceManifestPath `
        -RepoRoot $repoRoot `
        -OutputDataRoot (Join-Path $resolvedBuildRoot 'Data')
}

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
    $confessionHolderDefinition =
        "asset['confessionProbeDialogueHolder']"
    $confessionLyingSpotDefinition =
        "asset['confessionProbeLyingSpot']"
    $confessionHolderGuid = 'cd93a0b2-762f-4d22'
    $confessionLyingSpotGuid = '8f827fee-38a5-41db'
    $confessionCameraGuids = @(
        '50df1113-ed8f-4845'
        'dc816990-06f3-4036'
        '9d3ae907-8eea-47d2'
        'b1e60d2c-7930-4c86'
        '454d309c-d364-4f1d'
        'f8c192db-9392-4871'
    )
    if (
        @($assetLinks | Where-Object {
            $definition = [string]$_.LinkDefinition
            $sourceGuid = [string]$_.SourceId
            $targetGuid = [string]$_.TargetId
            $isSettlementLink =
                $sourceGuid -eq $questHolderGuid -and
                $definition -match
                    "^asset\['DP_SearchArea_[A-Za-z0-9_]+'\]$"
            $isEvidenceStashLink =
                $sourceGuid -eq $questHolderGuid -and
                $definition -match
                    "^asset\['DP_EvidenceStash_[A-Za-z0-9_]+'\]$"
            $isGuidanceLink =
                $sourceGuid -eq $questHolderGuid -and
                $definition -match
                    "^asset\['DP_Guidance_[A-Za-z0-9_]+'\]$"
            $isLegacyPritokyLink =
                $region -eq 'kutnohorsko' -and
                $sourceGuid -eq $questHolderGuid -and
                $definition -eq $legacyPritokyDefinition
            $isConfessionHolderLink =
                $region -eq 'trosecko' -and
                $sourceGuid -eq $questHolderGuid -and
                $targetGuid -eq $confessionHolderGuid -and
                $definition -eq $confessionHolderDefinition
            $isConfessionLyingSpotLink =
                $region -eq 'trosecko' -and
                $sourceGuid -eq $questHolderGuid -and
                $targetGuid -eq $confessionLyingSpotGuid -and
                $definition -eq $confessionLyingSpotDefinition
            $isLyingSpotHolderLink =
                $region -eq 'trosecko' -and
                $sourceGuid -eq $confessionLyingSpotGuid -and
                $targetGuid -eq $confessionHolderGuid -and
                $definition -eq 'dialogueHolder'
            $isConfessionCameraLink =
                $region -eq 'trosecko' -and
                $sourceGuid -eq $confessionHolderGuid -and
                $targetGuid -in $confessionCameraGuids -and
                $definition -eq 'cameraOverride'
            -not (
                $isSettlementLink -or
                $isEvidenceStashLink -or
                $isGuidanceLink -or
                $isLegacyPritokyLink -or
                $isConfessionHolderLink -or
                $isConfessionLyingSpotLink -or
                $isLyingSpotHolderLink -or
                $isConfessionCameraLink
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
    $expectedMissionObjectCount = if ($region -eq 'trosecko') { 9 } else { 1 }
    if ($missionObjectEntries.Count -ne $expectedMissionObjectCount) {
        throw "Dark Passenger $region mission-object patch has an unexpected entity count."
    }
    try {
        $missionObjectsPatch = [xml]$missionObjectsPatchText
    }
    catch {
        throw "Dark Passenger $region mission-object patch is invalid XML: $($_.Exception.Message)"
    }
    $missionEntities = @($missionObjectsPatch.Objects.Entity)
    $questHolder = @(
        $missionEntities |
            Where-Object { [string]$_.EntityGuid -eq $questHolderGuid }
    )
    if (
        $questHolder.Count -ne 1 -or
        [string]$questHolder[0].EntityClass -ne 'SmartObjectHolder' -or
        [string]$questHolder[0].EntityGuid -ne $questHolderGuid
    ) {
        throw "Dark Passenger $region mission-object patch does not match its waitinglinks quest holder."
    }
    if ($region -eq 'trosecko') {
        $confessionHolder = @(
            $missionEntities |
                Where-Object {
                    [string]$_.EntityGuid -eq $confessionHolderGuid
                }
        )
        $confessionLyingSpot = @(
            $missionEntities |
                Where-Object {
                    [string]$_.EntityGuid -eq $confessionLyingSpotGuid
                }
        )
        $confessionCameras = @(
            $missionEntities |
                Where-Object {
                    [string]$_.EntityClass -eq 'CameraSource' -and
                    [string]$_.Name -like 'DP_ConfessionCameraRig_*'
                }
        )
        if (
            $confessionHolder.Count -ne 1 -or
            [string]$confessionHolder[0].EntityClass -ne
                'DialogueHolder' -or
            $confessionLyingSpot.Count -ne 1 -or
            [string]$confessionLyingSpot[0].EntityClass -ne
                'SO_LyingHarmed' -or
            [string]$confessionLyingSpot[0].Properties.guidSmartObjectType -ne
                'fac19edd-46e9-4dd5-914f-72502c70af07' -or
            $confessionCameras.Count -ne 6 -or
            @($confessionCameras | Where-Object {
                $null -eq $_.Properties.DialogueCamera -or
                $null -eq $_.CameraProxy
            }).Count -gt 0
        ) {
            throw 'Dark Passenger Trosky confession staging entities are invalid.'
        }
    }
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
    foreach ($missionEntity in $missionEntities) {
        $entityGuid = [string]$missionEntity.EntityGuid
        $entityId = [string]$missionEntity.EntityId
        $entityName = [string]$missionEntity.Name
        if (
            $objectsMissionText.Contains("EntityGuid=`"$entityGuid`"") -or
            $objectsMissionText.Contains("EntityId=`"$entityId`"") -or
            $objectsMissionText.Contains("Name=`"$entityName`"")
        ) {
            throw "Base $region mission objects already contain a Dark Passenger concept-graph identity."
        }
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

$dataInputs = @('AI', 'Animations', 'Libs', 'Quests', 'Scripts') |
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
    $sourceFile = Join-Path $generatedLocalizationRoot `
        "$language\text__darkpassengertest.xml"
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

if (Test-Path -LiteralPath $DialogueMediaResultsPath -PathType Leaf) {
    & $dialogueMediaResultsConsumerPath `
        -JobsManifestPath $dialogueMediaResolvedJobsPath `
        -ResultsManifestPath $DialogueMediaResultsPath `
        -OutputModRoot $resolvedBuildRoot
}
elseif (Test-Path -LiteralPath $dialogueMediaResolvedJobsPath -PathType Leaf) {
    $dialogueMediaJobs = [System.IO.File]::ReadAllText(
        $dialogueMediaResolvedJobsPath
    ) | ConvertFrom-Json -Depth 100
    if (@($dialogueMediaJobs.jobs).Count -gt 0) {
        throw 'DIALOGUE_MEDIA_RESULTS_MISSING: DialogueMediaKit results are ' +
            "required for $(@($dialogueMediaJobs.jobs).Count) jobs: " +
            $DialogueMediaResultsPath
    }
}
elseif (Test-Path -LiteralPath $dialogueVoiceManifestPath -PathType Leaf) {
    $dialogueVoiceManifest = [System.IO.File]::ReadAllText(
        $dialogueVoiceManifestPath
    ) | ConvertFrom-Json -Depth 100
    if (@($dialogueVoiceManifest.assets | Where-Object {
        [string]$_.packageLanguage -ceq 'english'
    }).Count -gt 0) {
        & $dialogueVoicePakBuilderPath `
            -ManifestPath $dialogueVoiceManifestPath `
            -RepoRoot $repoRoot `
            -OutputPak (Join-Path $localizationOutput 'english.pak') `
            -PackageLanguage 'english'
    }
}

& $sevenZip t $dataPak | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "7-Zip integrity test failed for $dataPak"
}

Write-Host "Built mod staging tree: $resolvedBuildRoot"
