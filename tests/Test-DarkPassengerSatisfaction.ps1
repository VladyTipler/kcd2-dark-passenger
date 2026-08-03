param(
    [string]$ReferenceDataRoot = $env:KCD2_REFERENCE_DATA_ROOT,
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ReferenceDataRoot)) {
    throw 'Set KCD2_REFERENCE_DATA_ROOT or pass -ReferenceDataRoot.'
}
if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
    throw 'Set KCD2_DEV_ROOT or pass -DevGameRoot.'
}

$testRoot = Split-Path -Parent $PSScriptRoot
$stageRoot = Join-Path $testRoot 'build\mod'
$manifestPath = "$stageRoot\mod.manifest"
$tagPath = "$stageRoot\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml"
$buffClassPath = "$stageRoot\Data\Libs\Tables\rpg\buff_class__darkpassengertest.xml"
$buffPath = "$stageRoot\Data\Libs\Tables\rpg\buff__darkpassengertest.xml"
$scriptContextPath = "$stageRoot\Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml"
$smartEntityPath =
    "$stageRoot\Data\Libs\Tables\ai\smartEntity\SmartEntity__darkpassengertest.xml"
$questPath = "$stageRoot\Data\Quests\Final\Barbora\kutnohorsko\dark_within_k.xml"
$troskyQuestPath = "$stageRoot\Data\Quests\Final\Barbora\trosecko\dark_within_t.xml"
$levelPath = "$stageRoot\Data\Quests\Final\Barbora\kutnohorsko.xml"
$troskyLevelPath = "$stageRoot\Data\Quests\Final\Barbora\trosecko.xml"
$standaloneKuttenbergLevelPath =
    "$stageRoot\Data\Quests\darkpassengertest\kutnohorsko.xml"
$standaloneTroskyLevelPath =
    "$stageRoot\Data\Quests\darkpassengertest\trosecko.xml"
$projectPath = "$stageRoot\Data\Quests\darkpassengertest.xml"
$luaPath = "$stageRoot\Data\Scripts\mods\dpsatisfaction.lua"
$hungerLuaPath = "$stageRoot\Data\Scripts\mods\dphunger.lua"
$aftermathLuaPath = "$stageRoot\Data\Scripts\mods\dpaftermath.lua"
$investigationLuaPath = "$stageRoot\Data\Scripts\mods\dpinvestigation.lua"
$burialLuaPath = "$stageRoot\Data\Scripts\mods\dpburial.lua"
$interactionsLuaPath = "$stageRoot\Data\Scripts\mods\dpinteractions.lua"
$evidenceLuaPath = "$stageRoot\Data\Scripts\mods\dpevidence.lua"
$witnessLuaPath = "$stageRoot\Data\Scripts\mods\dpwitness.lua"
$witnessDetectorLuaPath = "$stageRoot\Data\Scripts\mods\dpwitnessdetector.lua"
$runtimeLuaPath = "$stageRoot\Data\Scripts\mods\darkpassengertest.lua"
$pakPath = "$stageRoot\Data\darkpassengertest.pak"
$kuttenbergLevelRoot = "$stageRoot\Data\Levels\kutnohorsko"
$kuttenbergLevelPakPath = "$stageRoot\Data\Levels\kutnohorsko\darkpassengertest.pak"
$kuttenbergObjectsMissionPath =
    "$stageRoot\Data\Levels\kutnohorsko\objects_mission0.xml"
$troskyLevelRoot = "$stageRoot\Data\Levels\trosecko"
$troskyLevelPakPath = "$troskyLevelRoot\darkpassengertest.pak"
$troskyObjectsMissionPath = "$troskyLevelRoot\objects_mission0.xml"
$troskyWaitingLinksPath = "$troskyLevelRoot\waitinglinks.xml"
$sourceWaitingLinksPath =
    "$testRoot\src\Data\Levels\kutnohorsko\waitinglinks.xml"
$sourceMissionObjectsPatchPath =
    "$testRoot\src\Data\Levels\kutnohorsko\objects_mission0.patch.xml"
$sourceTroskyWaitingLinksPath =
    "$testRoot\src\Data\Levels\trosecko\waitinglinks.xml"
$sourceTroskyMissionObjectsPatchPath =
    "$testRoot\src\Data\Levels\trosecko\objects_mission0.patch.xml"
$barboraKuttenbergPatchPath =
    "$testRoot\src\Data\Quests\Final\Barbora\kutnohorsko.patch.xml"
$barboraTroskyPatchPath =
    "$testRoot\src\Data\Quests\Final\Barbora\trosecko.patch.xml"
$candidateCatalogPath = "$testRoot\config\victim-candidates.json"
$settlementAreaManifestPath =
    "$testRoot\config\settlement-investigation-areas.json"
$generatorPath = "$testRoot\tools\Generate-VictimArtifacts.ps1"
$areaBindingGeneratorPath =
    "$testRoot\tools\Generate-SettlementAreaBindings.ps1"
$questTemplatePath = "$stageRoot\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template"
$troskyQuestTemplatePath = "$stageRoot\Data\Quests\darkpassengertest\trosecko\dark_within_t.xml.template"
$questBridgeModulePath = "$stageRoot\Data\Quests\darkpassengertest\kutnohorsko\dp_lua_call.xml"
$schedulerBridgePath = "$stageRoot\Data\AI\player\scheduler\darkPassengerExecuteLua.xml"
$burialRecoveryTreePath =
    "$stageRoot\Data\Scripts\AI\BehaviorTrees\darkPassengerRecoverBuriedBody.xml"
$legacyBurialRecoveryTreePath =
    "$stageRoot\Data\AI\world\darkPassengerRecoverBuriedBody.xml"
$generatedCatalogLuaPath = "$stageRoot\Data\Scripts\mods\generated\dp_candidate_catalog.lua"
$investigationAreaCatalogLuaPath =
    "$stageRoot\Data\Scripts\mods\generated\dp_investigation_area_catalog.lua"
$questItemCatalogLuaPath = "$stageRoot\Data\Scripts\mods\generated\dp_quest_item_catalog.lua"
$questItemGeneratorPath = "$testRoot\tools\Generate-QuestItemCatalog.ps1"
$kuttenbergWaitingLinksPath = "$stageRoot\Data\Levels\kutnohorsko\waitinglinks.xml"
$kuttenbergBaseLevelPakPath =
    Join-Path $DevGameRoot 'Data\Levels\kutnohorsko\level.pak'
$troskyBaseLevelPakPath =
    Join-Path $DevGameRoot 'Data\Levels\trosecko\level.pak'
$assetLinkerRoot = $ReferenceDataRoot
$kuttenbergBaseWaitingLinksPath = "$assetLinkerRoot\kutnohorsko\kut_waitinglinks.xml"
$kuttenbergObjectsPath = "$assetLinkerRoot\kutnohorsko\kut_objects_mission0.xml"
$troskyObjectsPath = "$assetLinkerRoot\trosecko\tros_objects_mission0.xml"
$soulTablePath = Join-Path $DevGameRoot 'Data\libs\CryHttp\xzar2\table-souls.json'
$worldExporterPath = "$testRoot\tools\Export-WorldVictimCandidates.ps1"
$catalogBuilderPath = "$testRoot\tools\Build-VictimCatalog.ps1"
$victimPolicyPath = "$testRoot\config\victim-policy.json"
$rawWorldCandidatesPath = "$testRoot\evidence\world-candidates.raw.json"
$buildScriptPath = "$testRoot\tools\Build-Mod.ps1"
$caseCompilerPath = "$testRoot\tools\Compile-CaseSpecs.ps1"
$caseCompilerModulePath = "$testRoot\tools\CaseSpecCompiler.psm1"
$caseCatalogPath =
    "$stageRoot\Data\Scripts\mods\generated\dp_case_catalog.lua"
$caseCompatibilityPath =
    "$testRoot\build\generated\cases\case-compatibility.json"
$areaInventoryPath = "$testRoot\build\generated\vanilla-trigger-areas.json"
$englishPath = "$testRoot\localization\English\text__darkpassengertest.xml"
$russianPath = "$testRoot\localization\Russian\text__darkpassengertest.xml"

$expectedGuid = '16de3823-48bf-4f86-8498-ce45819a48f0'
$expectedTag = '23'
$hungerBuffClassId = '2301'
$satisfactionGateGuid = 'b5c59e05-cc10-4bf8-b82e-d82b913c841f'
$targetGuid = 'a6046bb4-57c1-4a95-b743-880aba11f5ba'
$targetTag = '24'
$witnessSignalGuid = '4804f2b2-1462-44f1-b76d-5602426bcc1'
$witnessSignalTag = '29'
$targetRevealedGuid = '1aff569d-80ee-4250-b28e-0f08d0524aa4'
$targetRevealedTag = '30'
$aftermathSignals = @(
    @{
        Result = 'clean'
        Guid = 'ff7f94d9-51d5-4aff-9261-d259a63b005c'
        Tag = '25'
    },
    @{
        Result = 'controlled'
        Guid = '02978719-2983-4f1a-bfde-5910f810e079'
        Tag = '26'
    },
    @{
        Result = 'noisy'
        Guid = '16e10153-a09e-4df3-943e-26cb74aa555d'
        Tag = '27'
    },
    @{
        Result = 'external'
        Guid = 'd79b7e38-cae0-404a-9df5-40a7e714cb40'
        Tag = '28'
    }
)
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if ($Condition) {
        $script:passes.Add($Message)
    }
    else {
        $script:failures.Add($Message)
    }
}

function Read-OptionalText {
    param([string]$LiteralPath)

    if (Test-Path -LiteralPath $LiteralPath) {
        return Get-Content -Raw -LiteralPath $LiteralPath
    }

    return ''
}

function Has-NoUtf8Bom {
    param([string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return $true
    }

    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    return -not (
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    )
}

$generatorDeterministic = $false
$duplicateCatalogueRejected = $false
if (
    (Test-Path -LiteralPath $generatorPath) -and
    (Test-Path -LiteralPath $candidateCatalogPath) -and
    (Test-Path -LiteralPath $questTemplatePath)
) {
    & pwsh -NoProfile -File $generatorPath *> $null
    if (
        $LASTEXITCODE -eq 0 -and
        (Test-Path -LiteralPath $questPath) -and
        (Test-Path -LiteralPath $generatedCatalogLuaPath)
    ) {
        $firstQuestHash = (Get-FileHash -LiteralPath $questPath -Algorithm SHA256).Hash
        $firstLuaHash = (Get-FileHash -LiteralPath $generatedCatalogLuaPath -Algorithm SHA256).Hash

        & pwsh -NoProfile -File $generatorPath *> $null
        if ($LASTEXITCODE -eq 0) {
            $secondQuestHash = (Get-FileHash -LiteralPath $questPath -Algorithm SHA256).Hash
            $secondLuaHash = (Get-FileHash -LiteralPath $generatedCatalogLuaPath -Algorithm SHA256).Hash
            $generatorDeterministic = (
                $firstQuestHash -eq $secondQuestHash -and
                $firstLuaHash -eq $secondLuaHash
            )
        }
    }

    $duplicateCataloguePath = Join-Path ([System.IO.Path]::GetTempPath()) (
        'dp-duplicate-catalogue-' + [guid]::NewGuid().ToString('N') + '.json'
    )
    $duplicateQuestOutputPath = Join-Path ([System.IO.Path]::GetTempPath()) (
        'dp-duplicate-quest-' + [guid]::NewGuid().ToString('N') + '.xml'
    )
    $duplicateTroskyQuestOutputPath = Join-Path ([System.IO.Path]::GetTempPath()) (
        'dp-duplicate-trosky-quest-' + [guid]::NewGuid().ToString('N') + '.xml'
    )
    $duplicateLuaOutputPath = Join-Path ([System.IO.Path]::GetTempPath()) (
        'dp-duplicate-catalogue-' + [guid]::NewGuid().ToString('N') + '.lua'
    )

    try {
        $duplicateCatalogue = Get-Content -Raw -LiteralPath $candidateCatalogPath |
            ConvertFrom-Json
        $duplicateRecord = $duplicateCatalogue.candidates[0] |
            ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $duplicateCatalogue.candidates = @($duplicateCatalogue.candidates) + @($duplicateRecord)
        $duplicateJson = $duplicateCatalogue | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText(
            $duplicateCataloguePath,
            $duplicateJson,
            [System.Text.UTF8Encoding]::new($false)
        )

        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & pwsh -NoProfile -File $generatorPath `
                -CatalogPath $duplicateCataloguePath `
                -TemplatePath $questTemplatePath `
                -KuttenbergQuestOutputPath $duplicateQuestOutputPath `
                -TroskyQuestOutputPath $duplicateTroskyQuestOutputPath `
                -LuaOutputPath $duplicateLuaOutputPath *> $null
            $duplicateCatalogueRejected = $LASTEXITCODE -ne 0
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }
    finally {
        foreach (
            $temporaryPath in
                $duplicateCataloguePath,
                $duplicateQuestOutputPath,
                $duplicateTroskyQuestOutputPath,
                $duplicateLuaOutputPath
        ) {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    }
}

$tagText = Read-OptionalText -LiteralPath $tagPath
$buffClassText = Read-OptionalText -LiteralPath $buffClassPath
$buffText = Read-OptionalText -LiteralPath $buffPath
$scriptContextText = Read-OptionalText -LiteralPath $scriptContextPath
$smartEntityText = Read-OptionalText -LiteralPath $smartEntityPath
$questText = Read-OptionalText -LiteralPath $questPath
$questTemplateText = Read-OptionalText -LiteralPath $questTemplatePath
$questBridgeModuleText = Read-OptionalText -LiteralPath $questBridgeModulePath
$schedulerBridgeText = Read-OptionalText -LiteralPath $schedulerBridgePath
$generatedCatalogLuaText = Read-OptionalText -LiteralPath $generatedCatalogLuaPath
$investigationAreaCatalogLuaText =
    Read-OptionalText -LiteralPath $investigationAreaCatalogLuaPath
$kuttenbergWaitingLinksText = Read-OptionalText -LiteralPath $kuttenbergWaitingLinksPath
$kuttenbergObjectsMissionText =
    Read-OptionalText -LiteralPath $kuttenbergObjectsMissionPath
$troskyWaitingLinksText = Read-OptionalText -LiteralPath $troskyWaitingLinksPath
$troskyObjectsMissionText =
    Read-OptionalText -LiteralPath $troskyObjectsMissionPath
$levelText = Read-OptionalText -LiteralPath $levelPath
$troskyLevelText = Read-OptionalText -LiteralPath $troskyLevelPath
$projectText = Read-OptionalText -LiteralPath $projectPath
$luaText = Read-OptionalText -LiteralPath $luaPath
$hungerLuaText = Read-OptionalText -LiteralPath $hungerLuaPath
$aftermathLuaText = Read-OptionalText -LiteralPath $aftermathLuaPath
$investigationLuaText =
    Read-OptionalText -LiteralPath $investigationLuaPath
$burialLuaText = Read-OptionalText -LiteralPath $burialLuaPath
$interactionsLuaText = Read-OptionalText -LiteralPath $interactionsLuaPath
$evidenceLuaText = Read-OptionalText -LiteralPath $evidenceLuaPath
$witnessLuaText = Read-OptionalText -LiteralPath $witnessLuaPath
$witnessDetectorLuaText =
    Read-OptionalText -LiteralPath $witnessDetectorLuaPath
$runtimeLuaText = Read-OptionalText -LiteralPath $runtimeLuaPath
$questItemCatalogLuaText =
    Read-OptionalText -LiteralPath $questItemCatalogLuaPath
$buildScriptText = Read-OptionalText -LiteralPath $buildScriptPath
$caseCompilerText = Read-OptionalText -LiteralPath $caseCompilerPath
$caseCatalogText = Read-OptionalText -LiteralPath $caseCatalogPath
$caseCompatibility = $null
if (Test-Path -LiteralPath $caseCompatibilityPath) {
    try {
        $caseCompatibility = Get-Content -Raw `
            -LiteralPath $caseCompatibilityPath | ConvertFrom-Json -Depth 100
    }
    catch {
        $caseCompatibility = $null
    }
}
$englishText = Read-OptionalText -LiteralPath $englishPath
$russianText = Read-OptionalText -LiteralPath $russianPath
$manifestText = Read-OptionalText -LiteralPath $manifestPath
$baseWaitingLinkCount = -1
$baseRegionModuleLinkCount = -1
$baseStreamableTargetCount = -1
$sevenZip = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
if (
    $sevenZip -and
    (Test-Path -LiteralPath $kuttenbergBaseLevelPakPath)
) {
    $baseWaitingLinksLines = @(
        & $sevenZip x -so `
            $kuttenbergBaseLevelPakPath 'waitinglinks.xml'
    )
    if ($LASTEXITCODE -eq 0) {
        $baseWaitingLinkCount = @(
            $baseWaitingLinksLines |
                Select-String -SimpleMatch '<WaitingLink '
        ).Count
        $baseRegionModuleLinkCount = @(
            $baseWaitingLinksLines |
                Select-String -SimpleMatch `
                    'SourceId="10702dff-9271-4a74"'
        ).Count
        $baseStreamableTargetCount = @(
            $baseWaitingLinksLines |
                Select-String -SimpleMatch '<StreamableTarget '
        ).Count
    }
}

Add-Result (
    (Test-Path -LiteralPath $manifestPath) -and
    $manifestText.Contains('<modifies_level>true</modifies_level>')
) 'mod manifest enables level and AI scheduler modifications'
Add-Result (
    (Test-Path -LiteralPath $caseCompilerPath) -and
    $caseCompilerText.Contains('Get-DpValidatedCaseSpecs')
) 'CaseSpec compiler entry point exists'
Add-Result (
    $buildScriptText.Contains('Compile-CaseSpecs.ps1') -and
    $buildScriptText.Contains('& $caseCompilerPath')
) 'build invokes CaseSpec compiler'
Add-Result (
    $caseCatalogText.Contains('id = "convenient_accident"') -and
    $caseCatalogText.Contains('code = 1001')
) 'build contains compiled convenient-accident catalog'
Add-Result (
    $null -ne $caseCompatibility -and
    @($caseCompatibility.cases | Where-Object {
        $_.id -eq 'convenient_accident' -and [int]$_.code -eq 1001
    }).Count -eq 1
) 'build compatibility report contains convenient accident'

Add-Result (Test-Path -LiteralPath $candidateCatalogPath) 'victim candidate catalogue exists'

$candidateCatalog = $null
if (Test-Path -LiteralPath $candidateCatalogPath) {
    try {
        $candidateCatalog = Get-Content -Raw -LiteralPath $candidateCatalogPath |
            ConvertFrom-Json
    }
    catch {
        $candidateCatalog = $null
    }
}

Add-Result ($null -ne $candidateCatalog) 'victim candidate catalogue is valid JSON'
Add-Result (
    $null -ne $candidateCatalog -and $candidateCatalog.schemaVersion -eq 2
) 'victim candidate catalogue uses schema version 2'
Add-Result (
    $null -ne $candidateCatalog -and
    @($candidateCatalog.regions).Count -eq 2 -and
    @($candidateCatalog.regions.id) -contains 'kutnohorsko' -and
    @($candidateCatalog.regions.id) -contains 'trosecko'
) 'schema v2 declares both game regions'
Add-Result (
    $null -ne $candidateCatalog -and
    @($candidateCatalog.settlements | Where-Object { $_.id -eq 'pritoky' }).Count -eq 1
) 'schema v2 declares Pritoky settlement metadata'

$settlementAreaManifest = $null
if (Test-Path -LiteralPath $settlementAreaManifestPath) {
    try {
        $settlementAreaManifest =
            Get-Content -Raw -LiteralPath $settlementAreaManifestPath |
            ConvertFrom-Json
    }
    catch {
        $settlementAreaManifest = $null
    }
}
$supportedInvestigationAreas = @()
if ($null -ne $settlementAreaManifest) {
    $supportedInvestigationAreas = @(
        $settlementAreaManifest.regions |
            ForEach-Object { $_.settlements }
    )
}
Add-Result (
    $null -ne $settlementAreaManifest -and
    $settlementAreaManifest.schemaVersion -eq 1 -and
    $supportedInvestigationAreas.Count -eq 36
) 'settlement investigation manifest declares all supported search areas'

$enabledPritokyCandidates = @()
if ($null -ne $candidateCatalog) {
    $enabledPritokyCandidates = @(
        $candidateCatalog.candidates |
            Where-Object { $_.enabled -eq $true -and $_.settlement -eq 'pritoky' }
    )
}

Add-Result (
    $enabledPritokyCandidates.Count -eq 37
) 'catalogue enables the broad 37-actor generic Pritoky pool'
Add-Result (
    @($enabledPritokyCandidates.entityName) -notcontains 'kpri_krizan' -and
    @($enabledPritokyCandidates.entityName) -notcontains 'kpri_man_14'
) 'catalogue conservatively excludes named Pritoky narrative risks'
Add-Result (
    @(
        $enabledPritokyCandidates |
            Where-Object {
                $_.permanentResident -ne $true -or
                $_.mainStoryCritical -ne $false -or
                $null -eq $_.sideQuestRisk
            }
    ).Count -eq 0
) 'every enabled resident has explicit residency and narrative policy'

$entityLinkedCandidates = @(
    $enabledPritokyCandidates |
        Where-Object { $_.bindingMode -eq 'entityLink' }
)
Add-Result (
    $entityLinkedCandidates.Count -eq 0
) 'catalogue rejects EntityGuid-only quest marker candidates'
Add-Result (
    @(
        $enabledPritokyCandidates |
            Where-Object {
                $_.guid -notmatch (
                    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-' +
                    '[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                )
            }
    ).Count -eq 0
) 'every enabled quest marker candidate has a full SharedSoul GUID'
Add-Result (
    (Test-Path -LiteralPath $kuttenbergBaseWaitingLinksPath) -and
    (Test-Path -LiteralPath $kuttenbergObjectsPath)
) 'Asset Linker authoritative Kuttenberg sources are available'
Add-Result (Test-Path -LiteralPath $soulTablePath) 'full SharedSoul table source is available'
Add-Result (Test-Path -LiteralPath $worldExporterPath) 'world victim candidate exporter exists'
Add-Result (Test-Path -LiteralPath $catalogBuilderPath) 'shipping victim catalogue builder exists'
Add-Result (Test-Path -LiteralPath $victimPolicyPath) 'victim selection policy exists'
Add-Result (Test-Path -LiteralPath $rawWorldCandidatesPath) 'raw world candidate export exists'

$rawWorldCandidates = $null
if (Test-Path -LiteralPath $rawWorldCandidatesPath) {
    try {
        $rawWorldCandidates = Get-Content -Raw -LiteralPath $rawWorldCandidatesPath |
            ConvertFrom-Json
    }
    catch {
        $rawWorldCandidates = $null
    }
}
Add-Result ($null -ne $rawWorldCandidates) 'raw world candidate export is valid JSON'

$knownPritokyRaw = @()
if ($null -ne $rawWorldCandidates) {
    $knownPritokyRaw = @(
        $rawWorldCandidates.candidates |
            Where-Object {
                $_.entityName -in @('kpri_man_23', 'kpri_man_26', 'kpri_man_34')
            }
    )
}
Add-Result (
    $knownPritokyRaw.Count -eq 3 -and
    @($knownPritokyRaw.soulGuid) -contains '88b271f6-d283-4a19-a3e7-123fded5413a' -and
    @($knownPritokyRaw.soulGuid) -contains 'aed6b35c-7220-4b63-b2ba-12e91cd3c161' -and
    @($knownPritokyRaw.soulGuid) -contains '58d0827f-4254-4de2-93d5-aecfde1d7065'
) 'raw extractor recovers all three known Pritoky SharedSoul records'
Add-Result (
    $knownPritokyRaw.Count -eq 3 -and
    @($knownPritokyRaw | Where-Object { $_.permanentResidentEvidence -ne $true }).Count -eq 0
) 'raw extractor proves permanent residency for known Pritoky residents'

foreach ($field in 'slot', 'alias', 'guid', 'entityName') {
    $values = @($enabledPritokyCandidates | ForEach-Object { $_.$field })
    Add-Result (
        $values.Count -eq 37 -and
        @($values | Where-Object { $null -eq $_ -or "$_".Length -eq 0 }).Count -eq 0 -and
        @($values | Sort-Object -Unique).Count -eq 37
    ) "Pritoky candidate $field values are present and unique"
}

Add-Result (
    $enabledPritokyCandidates.Count -eq 37 -and
    @(
        $enabledPritokyCandidates |
            Where-Object {
                $_.gameRegion -ne 'kutnohorsko' -or
                $_.settlement -ne 'pritoky' -or
                $null -eq $_.weight -or
                [double]$_.weight -le 0 -or
                $_.killableVerified -ne $true
            }
    ).Count -eq 0
) 'Pritoky candidates have region, settlement, positive weight, and verified killability'

Add-Result (
    $enabledPritokyCandidates.Count -eq 37 -and
    @(
        $enabledPritokyCandidates |
            Where-Object {
                $_.storyCritical -ne $false -or
                $_.questCritical -ne $false -or
                $_.immortal -ne $false -or
                $_.dead -ne $false
            }
    ).Count -eq 0
) 'Pritoky candidates exclude story-critical, quest-critical, immortal, and dead NPCs'

Add-Result (Test-Path -LiteralPath $generatorPath) 'victim artifact generator exists'
Add-Result (Test-Path -LiteralPath $questTemplatePath) 'quest generator template exists'
foreach (
    $token in
        '{{DP_TARGET_TYPE_ENUMS}}',
        '{{DP_SEARCH_TYPE_ENUMS}}',
        '{{DP_SEARCH_STATE_EDGES}}',
        '{{DP_SEARCH_AREA_ASSETS}}',
        '{{DP_SEARCH_LOGS}}',
        '{{DP_SELECTED_TYPE_ENUMS}}',
        '{{DP_SELECTED_STATE_EDGES}}',
        '{{DP_TARGET_STATE_EDGES}}',
        '{{DP_TARGET_SEARCH_REVEAL_EDGES}}',
        '{{DP_TARGET_SELECTION_STOP_EDGES}}',
        '{{DP_TARGET_DETECTION_NODES}}',
        '{{DP_TARGET_DEATH_NODES}}',
        '{{DP_TARGET_DEATH_CONTEXT}}',
        '{{DP_TARGET_DEATH_CONTEXT_EDGES}}',
        '{{DP_TARGET_CLEANUP_EDGES}}',
        '{{DP_TARGET_ASSETS}}',
        '{{DP_TARGET_LOGS}}',
        '{{DP_SEARCH_PROGRESS_TYPE}}',
        '{{DP_SELECTED_TARGET_TYPE}}',
        '{{DP_TARGET_PROGRESS_TYPE}}'
) {
    Add-Result ($questTemplateText.Contains($token)) "quest template contains $token"
}
Add-Result (Test-Path -LiteralPath $generatedCatalogLuaPath) 'generated Lua candidate catalogue exists'
Add-Result ($generatorDeterministic) 'victim artifact generator is deterministic'
Add-Result ($duplicateCatalogueRejected) 'victim artifact generator rejects duplicate candidate keys'
Add-Result (
    $questText -notmatch '\{\{DP_[A-Z_]+\}\}'
) 'generated quest contains no unresolved template tokens'

if ($enabledPritokyCandidates.Count -eq 37) {
    foreach ($candidate in $enabledPritokyCandidates) {
        $slotName = 'Target{0:D3}' -f [int]$candidate.slot
        $slotNode = 'targetSlot{0:D3}' -f [int]$candidate.slot
        $escapedAlias = [regex]::Escape([string]$candidate.alias)
        $escapedGuid = [regex]::Escape([string]$candidate.guid)

        Add-Result (
            $generatedCatalogLuaText.Contains("slot = $([int]$candidate.slot)") -and
            $generatedCatalogLuaText.Contains("alias = `"$($candidate.alias)`"") -and
            $generatedCatalogLuaText.Contains("guid = `"$($candidate.guid)`"") -and
            $generatedCatalogLuaText.Contains("entityName = `"$($candidate.entityName)`"")
        ) "generated Lua contains $slotName candidate"

        Add-Result (
            $questText.Contains(
                "<StateTypeEnumeration Name=`"$slotName`" ObjectiveValueType=`"Started`" />"
            )
        ) "generated quest declares $slotName"

        Add-Result (
            $questText -match (
                "<SoulAsset Name=`"$escapedAlias`" SharedSoulGuids=`"$escapedGuid`" />"
            )
        ) "generated quest declares SharedSoul-bound $($candidate.alias) asset"

        Add-Result (
            $questText -match (
                "(?s)<EnumLog Type=`"Started`" Name=`"$slotName`" " +
                "IsTracked=`"true`" Marker=`"$escapedAlias`">"
            )
        ) "generated quest log $slotName owns $($candidate.alias) marker"

        Add-Result (
            $questText -match (
                "(?s)<State Name=`"selectedTarget`" TypeT=`"DP_SelectedTarget`">.*?" +
                "<Edge From=`"$($slotNode)Tagged.True`" To=`"Set$slotName`" />.*?" +
                "</State>"
            )
        ) "tag 24 selects internal $slotName without exposing its marker"
        Add-Result (
            $questText.Contains("<MakeArray Name=`"$($slotNode)Souls`"") -and
            $questText.Contains("<Function Name=`"$($slotNode)TagCheck`"") -and
            $questText.Contains("<If Name=`"$($slotNode)Tagged`"") -and
            $questText.Contains("<Function Name=`"$($slotNode)RevealCheck`"") -and
            $questText.Contains("<If Name=`"$($slotNode)Revealed`"")
        ) "generated quest has hidden selection and reveal checks for $slotName"
        Add-Result (
            $questText -match (
                "(?s)<State Name=`"targetObjectiveProgress`" TypeT=`"DP_TargetProgress`">.*?" +
                "<Edge From=`"$($slotNode)Revealed.True`" To=`"Set$slotName`" />.*?" +
                "</State>"
            ) -and
            $questText -match (
                "(?s)<State Name=`"objectiveProgress`" TypeT=`"DP_SearchProgress`">.*?" +
                "<Edge From=`"$($slotNode)Revealed.True`" To=`"SetDone`" />.*?" +
                "</State>"
            )
        ) "tag 30 reveals $slotName and completes the search area"

        Add-Result (
            $questText -match (
                "(?s)<SoulDeathTrigger Name=`"$($slotNode)Death`">.*?" +
                "<Asset Name=`"Souls`" Alias=`"$escapedAlias`" />.*?" +
                "<Edge From=`"selectedTarget\.$slotName`" To=`"IsActive`" />"
            )
        ) "pre-reveal death remains active for selected $slotName"
        Add-Result (
            $questText.Contains(
                "<Edge From=`"$($slotNode)Death.OnDeath`" To=`"SetTrue`" />"
            )
        ) "generated quest raises Lua-polled death context for $slotName"
        Add-Result (
            ([regex]::Matches(
                $questText,
                "Marker=`"$escapedAlias`""
            ).Count -eq 1) -and
            ([regex]::Matches(
                $questText,
                "From=`"$($slotNode)Revealed.True`" To=`"Set$slotName`""
            ).Count -eq 1)
        ) "exact marker and objective update for $slotName exist only once"
    }
}

Add-Result (
    $questTemplateText.Contains('{{DP_SEARCH_TYPE_ENUMS}}') -and
    $questTemplateText.Contains('{{DP_SEARCH_STATE_EDGES}}') -and
    $questTemplateText.Contains('{{DP_SEARCH_AREA_ASSETS}}') -and
    $questTemplateText.Contains('{{DP_SEARCH_LOGS}}')
) 'quest template exposes generated settlement search-state tokens'
Add-Result (
    -not $questText.Contains('DP_PritokySearchProfile') -and
    -not $questText.Contains('pritokySearchAreaProfile')
) 'search marker does not depend on a quest-activated custom holder profile'
$areaBindingGeneratorDeterministic = $false
if (Test-Path -LiteralPath $areaBindingGeneratorPath) {
    $temporaryBindingRoot = Join-Path (
        [System.IO.Path]::GetTempPath()
    ) ('dp-area-bindings-' + [guid]::NewGuid().ToString('N'))
    $temporaryAreaCatalogPath =
        Join-Path $temporaryBindingRoot 'dp_investigation_area_catalog.lua'
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & pwsh -NoProfile -File $areaBindingGeneratorPath `
            -ManifestPath $settlementAreaManifestPath `
            -AreaInventoryPath $areaInventoryPath `
            -OutputRoot $temporaryBindingRoot `
            -LuaOutputPath $temporaryAreaCatalogPath *> $null
        if ($LASTEXITCODE -eq 0) {
            $firstBindingHashes = @{}
            foreach ($relativePath in @(
                'kutnohorsko\objects_mission0.patch.xml',
                'kutnohorsko\waitinglinks.xml',
                'trosecko\objects_mission0.patch.xml',
                'trosecko\waitinglinks.xml',
                'dp_investigation_area_catalog.lua'
            )) {
                $generatedPath = Join-Path $temporaryBindingRoot $relativePath
                if (Test-Path -LiteralPath $generatedPath) {
                    $firstBindingHashes[$relativePath] = (
                        Get-FileHash -LiteralPath $generatedPath -Algorithm SHA256
                    ).Hash
                }
            }
            & pwsh -NoProfile -File $areaBindingGeneratorPath `
                -ManifestPath $settlementAreaManifestPath `
                -AreaInventoryPath $areaInventoryPath `
                -OutputRoot $temporaryBindingRoot `
                -LuaOutputPath $temporaryAreaCatalogPath *> $null
            if ($LASTEXITCODE -eq 0 -and $firstBindingHashes.Count -eq 5) {
                $areaBindingGeneratorDeterministic = $true
                foreach ($relativePath in $firstBindingHashes.Keys) {
                    $generatedPath = Join-Path $temporaryBindingRoot $relativePath
                    if (
                        (Get-FileHash -LiteralPath $generatedPath -Algorithm SHA256).Hash -ne
                            $firstBindingHashes[$relativePath]
                    ) {
                        $areaBindingGeneratorDeterministic = $false
                    }
                }
            }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if (Test-Path -LiteralPath $temporaryBindingRoot) {
            Remove-Item -LiteralPath $temporaryBindingRoot -Recurse -Force
        }
    }
}
Add-Result (
    $areaBindingGeneratorDeterministic
) 'settlement area binding generator emits deterministic regional files and Lua catalog'

$areaBindingSpecs = @(
    [pscustomobject]@{
        region = 'kutnohorsko'
        levelHolderGuid = '10702dff-9271-4a74'
        questHolderName = 'dark_within_k'
        questHolderGuid = 'f4a73e20-28c5-4bd2'
        questHolderEntityId = '1831841'
        smartEntityGuid = 'a125563a-5dfe-428f-9581-d218e82b849f'
        sourceWaitingLinksPath = $sourceWaitingLinksPath
        sourceMissionObjectsPath = $sourceMissionObjectsPatchPath
        buildWaitingLinksPath = $kuttenbergWaitingLinksPath
        buildObjectsMissionPath = $kuttenbergObjectsMissionPath
        baseLevelPakPath = $kuttenbergBaseLevelPakPath
        levelPakPath = $kuttenbergLevelPakPath
    }
    [pscustomobject]@{
        region = 'trosecko'
        levelHolderGuid = '30277b74-1c65-41e9'
        questHolderName = 'dark_within_t'
        questHolderGuid = 'a13d9e5c-7b42-4f61'
        questHolderEntityId = '1831842'
        smartEntityGuid = 'd4a6f10b-f8cd-4d4d-9a6c-fbc186429bca'
        sourceWaitingLinksPath = $sourceTroskyWaitingLinksPath
        sourceMissionObjectsPath = $sourceTroskyMissionObjectsPatchPath
        buildWaitingLinksPath = $troskyWaitingLinksPath
        buildObjectsMissionPath = $troskyObjectsMissionPath
        baseLevelPakPath = $troskyBaseLevelPakPath
        levelPakPath = $troskyLevelPakPath
    }
)
$sourceAreaBindingsComplete = $supportedInvestigationAreas.Count -eq 36
$builtAreaBindingsComplete = $supportedInvestigationAreas.Count -eq 36
foreach ($bindingSpec in $areaBindingSpecs) {
    $regionalAreas = @(
        $supportedInvestigationAreas |
            Where-Object gameRegion -eq $bindingSpec.region
    )
    $expectedLinks = [System.Collections.Generic.List[string]]::new()
    $expectedLinks.Add(
        "$($bindingSpec.levelHolderGuid)|$($bindingSpec.questHolderGuid)|module"
    )
    foreach ($searchArea in $regionalAreas) {
        $areaAliases = @([string]$searchArea.alias) +
            @($searchArea.legacyAliases | ForEach-Object { [string]$_ })
        foreach ($areaGuid in @($searchArea.areaGuids)) {
            foreach ($areaAlias in $areaAliases) {
                $expectedLinks.Add(
                    "$($bindingSpec.questHolderGuid)|$areaGuid|asset['$areaAlias']"
                )
            }
        }
    }

    $sourceWaitingLinksText =
        Read-OptionalText -LiteralPath $bindingSpec.sourceWaitingLinksPath
    $sourceMissionObjectsText =
        Read-OptionalText -LiteralPath $bindingSpec.sourceMissionObjectsPath
    try {
        [xml]$sourceWaitingLinksXml = $sourceWaitingLinksText
        [xml]$sourceMissionObjectsXml = $sourceMissionObjectsText
        $actualSourceLinks = @(
            $sourceWaitingLinksXml.StaticLinksInfo.WaitingLinks.WaitingLink |
                ForEach-Object {
                    "$([string]$_.SourceId)|$([string]$_.TargetId)|$([string]$_.LinkDefinition)"
                }
        )
        $sourceHolder = @($sourceMissionObjectsXml.Objects.Entity)
        if (
            $sourceHolder.Count -ne 1 -or
            [string]$sourceHolder[0].Name -ne $bindingSpec.questHolderName -or
            [string]$sourceHolder[0].EntityClass -ne 'SmartObjectHolder' -or
            [string]$sourceHolder[0].EntityGuid -ne $bindingSpec.questHolderGuid -or
            [string]$sourceHolder[0].EntityId -ne $bindingSpec.questHolderEntityId -or
            [string]$sourceHolder[0].Properties.guidSmartObjectType -ne
                $bindingSpec.smartEntityGuid -or
            $sourceMissionObjectsText.Contains('EntityClass="LevelHolder"') -or
            $sourceMissionObjectsText.Contains('EntityClass="TriggerArea"') -or
            @($actualSourceLinks).Count -ne $expectedLinks.Count -or
            @(Compare-Object $expectedLinks $actualSourceLinks).Count -ne 0
        ) {
            $sourceAreaBindingsComplete = $false
        }
    }
    catch {
        $sourceAreaBindingsComplete = $false
    }

    $builtWaitingLinksText =
        Read-OptionalText -LiteralPath $bindingSpec.buildWaitingLinksPath
    $builtObjectsMissionText =
        Read-OptionalText -LiteralPath $bindingSpec.buildObjectsMissionPath
    if (
        [string]::IsNullOrWhiteSpace($builtWaitingLinksText) -or
        [string]::IsNullOrWhiteSpace($builtObjectsMissionText) -or
        -not $sevenZip -or
        -not (Test-Path -LiteralPath $bindingSpec.baseLevelPakPath)
    ) {
        $builtAreaBindingsComplete = $false
        continue
    }

    $baseWaitingLinksLines = @(
        & $sevenZip x -so $bindingSpec.baseLevelPakPath 'waitinglinks.xml'
    )
    if ($LASTEXITCODE -ne 0) {
        $builtAreaBindingsComplete = $false
        continue
    }
    $baseWaitingLinksCount = @(
        $baseWaitingLinksLines |
            Select-String -SimpleMatch '<WaitingLink '
    ).Count
    $baseStreamableTargetsCount = @(
        $baseWaitingLinksLines |
            Select-String -SimpleMatch '<StreamableTarget '
    ).Count
    try {
        [xml]$builtWaitingLinksXml = $builtWaitingLinksText
        $actualBuiltLinks = @(
            $builtWaitingLinksXml.StaticLinksInfo.WaitingLinks.WaitingLink |
                ForEach-Object {
                    "$([string]$_.SourceId)|$([string]$_.TargetId)|$([string]$_.LinkDefinition)"
                }
        )
        if (
            $actualBuiltLinks.Count -ne ($baseWaitingLinksCount + $expectedLinks.Count) -or
            ([regex]::Matches(
                $builtWaitingLinksText,
                '<StreamableTarget '
            )).Count -ne $baseStreamableTargetsCount -or
            @($expectedLinks | Where-Object { $_ -notin $actualBuiltLinks }).Count -ne 0
        ) {
            $builtAreaBindingsComplete = $false
            continue
        }
    }
    catch {
        $builtAreaBindingsComplete = $false
        continue
    }

    $entityIdsByGuid = @{}
    foreach ($entityTag in [regex]::Matches(
        $builtObjectsMissionText,
        '<Entity\b[^>]*>'
    )) {
        $guidMatch = [regex]::Match($entityTag.Value, 'EntityGuid="([^"]+)"')
        $idMatch = [regex]::Match($entityTag.Value, 'EntityId="([0-9]+)"')
        if ($guidMatch.Success -and $idMatch.Success) {
            $entityIdsByGuid[$guidMatch.Groups[1].Value] =
                $idMatch.Groups[1].Value
        }
    }
    $levelHolderBlock = [regex]::Match(
        $builtObjectsMissionText,
        "(?s)<Entity\b(?=[^>]*EntityGuid=`"$([regex]::Escape($bindingSpec.levelHolderGuid))`")[^>]*>.*?</Entity>"
    ).Value
    $questHolderBlock = [regex]::Match(
        $builtObjectsMissionText,
        "(?s)<Entity\b(?=[^>]*EntityGuid=`"$([regex]::Escape($bindingSpec.questHolderGuid))`")[^>]*>.*?</Entity>"
    ).Value
    if (
        [string]::IsNullOrWhiteSpace($levelHolderBlock) -or
        [string]::IsNullOrWhiteSpace($questHolderBlock) -or
        -not $levelHolderBlock.Contains(
            "TargetId=`"$($bindingSpec.questHolderEntityId)`" TargetGuid=`"00000000-0000-0000`" Name=`"module`""
        )
    ) {
        $builtAreaBindingsComplete = $false
        continue
    }
    $expectedAssetLinkCount = $expectedLinks.Count - 1
    if (([regex]::Matches(
        $questHolderBlock,
        'Name="asset\['
    )).Count -ne $expectedAssetLinkCount) {
        $builtAreaBindingsComplete = $false
        continue
    }
    foreach ($searchArea in $regionalAreas) {
        $areaAliases = @([string]$searchArea.alias) +
            @($searchArea.legacyAliases | ForEach-Object { [string]$_ })
        foreach ($areaGuid in @($searchArea.areaGuids)) {
            $targetEntityId = [string]$entityIdsByGuid[$areaGuid]
            foreach ($areaAlias in $areaAliases) {
                if (
                    [string]::IsNullOrWhiteSpace($targetEntityId) -or
                    -not $questHolderBlock.Contains(
                        "TargetId=`"$targetEntityId`" TargetGuid=`"00000000-0000-0000`" Name=`"asset['$areaAlias']`""
                    )
                ) {
                    $builtAreaBindingsComplete = $false
                }
            }
        }
    }
}
Add-Result (
    $sourceAreaBindingsComplete
) 'both regional source bindings contain the exact module and settlement-area links'
Add-Result (
    $builtAreaBindingsComplete
) 'both merged regional registries resolve every waiting link to the same mission-object link'
Add-Result (
    $sourceTroskyWaitingLinksPath -and
    (Read-OptionalText -LiteralPath $sourceTroskyWaitingLinksPath).Contains(
        'SourceId="30277b74-1c65-41e9"'
    )
) 'Trosky binding uses the real regional LevelHolder GUID'
Add-Result (
    (Test-Path -LiteralPath $barboraKuttenbergPatchPath) -and
    (Read-OptionalText -LiteralPath $barboraKuttenbergPatchPath).Contains(
        '<Definition File="kutnohorsko/dark_within_k.xml" />'
    ) -and
    (Test-Path -LiteralPath $barboraTroskyPatchPath) -and
    (Read-OptionalText -LiteralPath $barboraTroskyPatchPath).Contains(
        '<Definition File="trosecko/dark_within_t.xml" />'
    )
) 'both Dark Passenger quests patch their live Barbora regional parents'
Add-Result (
    (Test-Path -LiteralPath $smartEntityPath) -and
    $smartEntityText.Contains(
        '<SmartEntityTemplate DatabaseId="a125563a-5dfe-428f-9581-d218e82b849f" Name="dark_within_k" UpdatePriority="false" />'
    ) -and
    $smartEntityText.Contains(
        '<SmartEntityTemplate DatabaseId="d4a6f10b-f8cd-4d4d-9a6c-fbc186429bca" Name="dark_within_t" UpdatePriority="false" />'
    )
) 'both regional quest holders own registered SmartEntity types'

$questXml = $null
try {
    $questXml = [xml]$questText
}
catch {
    $questXml = $null
}
Add-Result ($null -ne $questXml) 'generated quest is valid XML'

$targetTypeIsQuestScoped = $false
if ($null -ne $questXml) {
    $targetTypeIsQuestScoped = (
        $null -eq $questXml.SelectSingleNode('/Database/Skald/Types') -and
        $null -ne $questXml.SelectSingleNode(
            '/Database/Skald/Quest/Nodes/following-sibling::*[1][self::Types]/Type[@TypeName="DP_TargetProgress"]'
        )
    )
}
Add-Result (
    $targetTypeIsQuestScoped
) 'custom target progress type is scoped inside Quest immediately after Nodes'

$allMarkerAliasesExist = $false
if ($null -ne $questXml) {
    $soulAssetAliases = @(
        $questXml.SelectNodes('//SoulAsset') |
            ForEach-Object { $_.Name }
    )
    $triggerAreaAliases = @(
        $questXml.SelectNodes('//TriggerAreaAsset') |
            ForEach-Object { $_.Name }
    )
    $markerAliases = @(
        $questXml.SelectNodes('//EnumLog[@Marker]') |
            ForEach-Object { $_.Marker }
    )
    $enabledKuttenbergCandidateCount = @(
        $candidateCatalog.candidates |
            Where-Object {
                $_.enabled -eq $true -and
                $_.gameRegion -eq 'kutnohorsko'
            }
    ).Count
    $kuttenbergSearchAreaCount = @(
        $supportedInvestigationAreas |
            Where-Object gameRegion -eq 'kutnohorsko'
    ).Count
    $allMarkerAliasesExist = (
        $markerAliases.Count -eq (
            $enabledKuttenbergCandidateCount +
                $kuttenbergSearchAreaCount +
                1 # Legacy Active save bridge reuses the Pritoky area alias.
        ) -and
        @(
            $markerAliases |
                Where-Object {
                    $_ -notin $soulAssetAliases -and
                    $_ -notin $triggerAreaAliases
                }
        ).Count -eq 0
    )
}
Add-Result (
    $allMarkerAliasesExist
) 'every generated marker references an existing Soul or TriggerArea alias'

Add-Result (Test-Path -LiteralPath $tagPath) 'custom buff AI tag table exists'
Add-Result ($tagText.Contains('buff_ai_tag_id="23"')) 'custom AI tag uses id 23'
Add-Result ($tagText.Contains('buff_ai_tag_name="darkpassenger_satisfaction"')) 'custom AI tag has expected name'
Add-Result (Test-Path -LiteralPath $buffClassPath) 'custom Dark Passenger buff class table exists'
Add-Result (
    $buffClassText.Contains(
        "buff_class_id=`"$hungerBuffClassId`" buff_class_name=`"DarkPassengerHunger`""
    )
) 'hunger tiers own a custom buff class'
Add-Result ($tagText.Contains("buff_ai_tag_id=`"$targetTag`"")) 'target AI tag uses id 24'
Add-Result ($tagText.Contains('buff_ai_tag_name="darkpassenger_target"')) 'target AI tag has expected name'
foreach ($signal in $aftermathSignals) {
    Add-Result (
        $tagText.Contains(
            "buff_ai_tag_id=`"$($signal.Tag)`" buff_ai_tag_name=`"darkpassenger_result_$($signal.Result)`""
        )
    ) "aftermath $($signal.Result) result owns AI tag $($signal.Tag)"
    Add-Result (
        $buffText -match (
            '<buff (?=[^>]*buff_ai_tag_id="' +
            [regex]::Escape($signal.Tag) +
            '")(?=[^>]*buff_exclusivity_id="0")' +
            '(?=[^>]*buff_id="' +
            [regex]::Escape($signal.Guid) +
            '")(?=[^>]*buff_name="dp_result_' +
            [regex]::Escape($signal.Result) +
            '")(?=[^>]*buff_ui_visibility_id="0")[^>]*/>'
        )
    ) "aftermath $($signal.Result) result signal is hidden and non-exclusive"
    Add-Result (
        $aftermathLuaText.Contains(
            "[$([char]34)$($signal.Result)$([char]34)] = $([char]34)$($signal.Guid)$([char]34)"
        )
    ) "aftermath Lua maps $($signal.Result) to its unique result buff"
}
$signalGuids = @($aftermathSignals.Guid)
$signalTags = @($aftermathSignals.Tag)
Add-Result (
    @($signalGuids | Select-Object -Unique).Count -eq 4 -and
    @($signalTags | Select-Object -Unique).Count -eq 4 -and
    -not ($signalTags -contains $expectedTag) -and
    -not ($signalTags -contains $targetTag)
) 'aftermath result GUIDs and AI tags are unique and do not reuse core tags'
Add-Result (
    $tagText.Contains(
        "buff_ai_tag_id=`"$witnessSignalTag`" buff_ai_tag_name=`"darkpassenger_witness_detected`""
    )
) 'anonymous witness update owns AI tag 29'
Add-Result (
    $buffText -match (
        '<buff (?=[^>]*buff_ai_tag_id="' +
        [regex]::Escape($witnessSignalTag) +
        '")(?=[^>]*buff_exclusivity_id="0")' +
        '(?=[^>]*buff_id="' +
        [regex]::Escape($witnessSignalGuid) +
        '")(?=[^>]*buff_name="dp_witness_detected")' +
        '(?=[^>]*buff_ui_visibility_id="0")[^>]*/>'
    )
) 'anonymous witness update signal is hidden and non-exclusive'
Add-Result (
    $tagText.Contains(
        "buff_ai_tag_id=`"$targetRevealedTag`" buff_ai_tag_name=`"darkpassenger_target_revealed`""
    )
) 'target reveal signal owns AI tag 30'
Add-Result (
    $buffText -match (
        '<buff (?=[^>]*buff_ai_tag_id="' +
        [regex]::Escape($targetRevealedTag) +
        '")(?=[^>]*buff_class_id="1")' +
        '(?=[^>]*buff_exclusivity_id="0")' +
        '(?=[^>]*buff_id="' +
        [regex]::Escape($targetRevealedGuid) +
        '")(?=[^>]*buff_lifetime_id="0")' +
        '(?=[^>]*buff_name="dp_target_revealed")' +
        '(?=[^>]*buff_ui_visibility_id="0")' +
        '(?=[^>]*duration="-1")' +
        '(?=[^>]*implementation="Cpp:Constant")' +
        '(?=[^>]*is_persistent="true")[^>]*/>'
    ) -and
    ([regex]::Matches(
        $buffText,
        [regex]::Escape($targetRevealedGuid)
    ).Count -eq 1)
) 'target reveal buff is one unique hidden persistent constant signal'
Add-Result (
    -not $englishText.Contains('dp_target_revealed') -and
    -not $russianText.Contains('dp_target_revealed') -and
    $buffText -notmatch (
        '<buff (?=[^>]*buff_id="' +
        [regex]::Escape($targetRevealedGuid) +
        '")(?=[^>]*(?:buff_desc|buff_ui_name|slot_buff_ui_name)=)[^>]*/>'
    )
) 'target reveal transport signal has no localization or UI metadata'

Add-Result ($buffText.Contains('buff_name="dp_darkness_within"')) 'existing darkness debuff is preserved'
Add-Result ($buffText.Contains("buff_id=`"$expectedGuid`"")) 'satisfaction buff uses expected GUID'
Add-Result (
    $buffText -match (
        'buff_ai_tag_id="23"[^>]*buff_id="' +
        [regex]::Escape($satisfactionGateGuid) +
        '"|buff_id="' + [regex]::Escape($satisfactionGateGuid) +
        '"[^>]*buff_ai_tag_id="23"'
    )
) 'hidden satisfaction gate owns AI tag 23'
Add-Result (
    $buffText -match (
        'buff_id="' + [regex]::Escape($satisfactionGateGuid) +
        '"[^>]*buff_name="dp_satisfaction_gate"[^>]*buff_ui_visibility_id="0"|' +
        'buff_name="dp_satisfaction_gate"[^>]*buff_id="' +
        [regex]::Escape($satisfactionGateGuid) +
        '"[^>]*buff_ui_visibility_id="0"'
    )
) 'satisfaction quest gate is hidden from UI'
Add-Result (
    $buffText -match (
        'buff_exclusivity_id="0"[^>]*buff_id="' +
        [regex]::Escape($satisfactionGateGuid) +
        '"|buff_id="' + [regex]::Escape($satisfactionGateGuid) +
        '"[^>]*buff_exclusivity_id="0"'
    )
) 'satisfaction quest gate uses the non-exclusive vanilla tag-buff pattern'
Add-Result (
    $buffText -match (
        'buff_id="' + [regex]::Escape($expectedGuid) +
        '".*?duration="-1"'
    )
) 'full satisfaction is controlled by hunger instead of a real-time duration'
Add-Result ($buffText.Contains('icon_id="sex_time_well_spent"')) 'satisfaction uses Time Well Spent icon'
Add-Result ($buffText.Contains('buff_ui_type_id="1"')) 'satisfaction is a positive UI buff'
Add-Result (
    $buffText.Contains(
        'buff_params="strength+2,agility+2,vitality+2,marksmanship+2,stealth+3,thievery+2,speech+2,charisma+2"'
    )
) 'full satisfaction modifiers match design'
Add-Result (
    @(
        'dp_satisfaction',
        'dp_satisfaction_10',
        'dp_satisfaction_20',
        'dp_satisfaction_30',
        'dp_satisfaction_40',
        'dp_hunger_60',
        'dp_hunger_70',
        'dp_hunger_80',
        'dp_hunger_90',
        'dp_hunger_100'
    ).Where({ $buffText.Contains("buff_name=`"$_`"") }).Count -eq 10 -and
    -not $buffText.Contains('buff_name="dp_hunger_50"')
) 'buff table defines every ten-percent hunger tier except neutral fifty'
$visibleHungerBuffNames = @(
    'dp_satisfaction',
    'dp_satisfaction_10',
    'dp_satisfaction_20',
    'dp_satisfaction_30',
    'dp_satisfaction_40',
    'dp_hunger_60',
    'dp_hunger_70',
    'dp_hunger_80',
    'dp_hunger_90',
    'dp_hunger_100'
)
Add-Result (
    @(
        $visibleHungerBuffNames |
            Where-Object {
                $buffText -notmatch (
                    '<buff (?=[^>]*buff_class_id="' +
                    [regex]::Escape($hungerBuffClassId) +
                    '")(?=[^>]*buff_name="' +
                    [regex]::Escape($_) +
                    '")[^>]*/>'
                )
            }
    ).Count -eq 0
) 'every visible hunger tier is isolated from vanilla buff classes'
Add-Result (
    ([regex]::Matches(
        $buffText,
        'buff_name="dp_satisfaction(?:_(?:10|20|30|40))?".*?buff_ai_tag_id="23"|' +
        'buff_ai_tag_id="23".*?buff_name="dp_satisfaction(?:_(?:10|20|30|40))?"'
    )).Count -eq 0
) 'visible positive hunger tiers do not emit quest-tag transitions'
Add-Result (
    ([regex]::Matches(
        $buffText,
        'buff_name="dp_hunger_(?:60|70|80|90|100)"[^>]*icon_id="starvation"'
    )).Count -eq 5
) 'all negative hunger tiers use the starvation icon'
$approvedHungerEffects = [ordered]@{
    'dp_satisfaction' = 'strength+2,agility+2,vitality+2,marksmanship+2,stealth+3,thievery+2,speech+2,charisma+2'
    'dp_satisfaction_10' = 'strength+1,agility+2,vitality+1,marksmanship+2,stealth+2,thievery+2,speech+2,charisma+2'
    'dp_satisfaction_20' = 'strength+1,agility+1,vitality+1,marksmanship+1,stealth+2,thievery+1,speech+1,charisma+1'
    'dp_satisfaction_30' = 'strength+1,agility+1,vitality+1,marksmanship+1,stealth+1,thievery+1,speech+1,charisma+1'
    'dp_satisfaction_40' = 'marksmanship+1,stealth+1,speech+1,charisma+1'
    'dp_hunger_60' = 'strength-1,marksmanship-1,stealth-1,speech-1,charisma-1'
    'dp_hunger_70' = 'strength-1,agility-1,vitality-1,marksmanship-1,stealth-1,thievery-1,speech-1,charisma-2'
    'dp_hunger_80' = 'strength-2,agility-2,vitality-1,marksmanship-2,stealth-2,thievery-2,speech-2,charisma-3'
    'dp_hunger_90' = 'strength-2,agility-2,vitality-2,marksmanship-3,stealth-3,thievery-3,speech-3,charisma-4'
    'dp_hunger_100' = 'strength-3,agility-3,vitality-3,marksmanship-4,stealth-4,thievery-3,speech-4,charisma-5'
}
foreach ($entry in $approvedHungerEffects.GetEnumerator()) {
    Add-Result (
        $buffText -match (
            'buff_name="' + [regex]::Escape($entry.Key) +
            '"[^>]*buff_params="' +
            [regex]::Escape($entry.Value) + '"'
        )
    ) "approved effects match tier $($entry.Key)"
}
Add-Result (
    @(
        [regex]::Matches(
            $buffText,
            'buff_name="(?:dp_satisfaction(?:_(?:10|20|30|40))?|dp_hunger_(?:60|70|80|90|100))"[^>]*buff_params="([^"]+)"'
        ) |
            ForEach-Object {
                $_.Groups[1].Value -split ',' |
                    ForEach-Object { ($_ -split '[+\-=*]')[0] }
            } |
            Where-Object {
                $_ -notin @(
                    'strength',
                    'agility',
                    'vitality',
                    'marksmanship',
                    'stealth',
                    'thievery',
                    'speech',
                    'charisma'
                )
            }
    ).Count -eq 0
) 'hunger tiers modify only the eight approved player parameters'
Add-Result ($buffText.Contains("buff_id=`"$targetGuid`"")) 'target marker buff uses expected GUID'
Add-Result ($buffText.Contains("buff_ai_tag_id=`"$targetTag`"")) 'target marker buff uses AI tag 24'
Add-Result (
    $buffText.Contains('buff_name="dp_is_target"') -and
    $buffText.Contains('buff_ui_visibility_id="0"')
) 'target marker buff is hidden from UI'
Add-Result (
    (Test-Path -LiteralPath $scriptContextPath) -and
    $scriptContextText.Contains(
        '<ScriptContextDatabaseNode Name="dp_select_victim_kutnohorsko" Class="Entity" />'
    ) -and
    $scriptContextText.Contains(
        '<ScriptContextDatabaseNode Name="dp_select_victim_trosecko" Class="Entity" />'
    ) -and
    $scriptContextText.Contains(
        '<ScriptContextDatabaseNode Name="dp_target_dead_kutnohorsko" Class="Entity" />'
    ) -and
    $scriptContextText.Contains(
        '<ScriptContextDatabaseNode Name="dp_target_dead_trosecko" Class="Entity" />'
    )
) 'both regional victim-selection and death contexts are registered'

Add-Result (
    $levelText.Contains(
        '<Definition File="kutnohorsko/dark_within_k.xml" />'
    ) -and
    $levelText -match (
        '(?s)<dark_within_k Name="dark_within_k" ' +
        'RequiredForOutput="kutnohorsko">.*?' +
        '<Edge From="OnWake" To="arm" />.*?</dark_within_k>'
    ) -and
    ([regex]::Matches($levelText, '<Definition File=').Count -gt 100) -and
    ([regex]::Matches($levelText, '<dark_within_k\b').Count -eq 1) -and
    (Test-Path -LiteralPath $standaloneKuttenbergLevelPath) -and
    $troskyLevelText.Contains(
        '<Definition File="trosecko/dark_within_t.xml" />'
    ) -and
    $troskyLevelText -match (
        '(?s)<dark_within_t Name="dark_within_t" ' +
        'RequiredForOutput="trosecko">.*?' +
        '<Edge From="OnWake" To="arm" />.*?</dark_within_t>'
    ) -and
    ([regex]::Matches($troskyLevelText, '<Definition File=').Count -gt 100) -and
    ([regex]::Matches($troskyLevelText, '<dark_within_t\b').Count -eq 1) -and
    (Test-Path -LiteralPath $standaloneTroskyLevelPath) -and
    $projectText.Contains(
        '<Definition File="darkpassengertest/kutnohorsko.xml" />'
    ) -and
    $projectText.Contains('<kutnohorsko Name="kutnohorsko"') -and
    $projectText.Contains(
        '<Definition File="darkpassengertest/trosecko.xml" />'
    ) -and
    $projectText.Contains('<trosecko Name="trosecko"') -and
    -not $projectText.Contains('<dark_within_k') -and
    -not $projectText.Contains('<dark_within_t')
) 'regional quests stay in Barbora while the global kill observer uses its own project'
Add-Result (
    -not $levelText.Contains('dp_lua_call.xml') -and
    -not $troskyLevelText.Contains('dp_lua_call.xml')
) 'regional levels avoid the unresolved scheduler bridge module'
Add-Result ($questText.Contains('<BuffTagTrigger Name="satisfactionTrigger"')) 'quest contains BuffTagTrigger'
Add-Result ($questText.Contains('<Constant Name="A" Value="23"')) 'quest watches AI tag 23'
Add-Result ($questText.Contains('satisfactionTrigger.OnAdded')) 'quest reacts to buff OnAdded'
Add-Result ($questText.Contains('To="SetDone"')) 'buff addition can complete objective/quest'
Add-Result ($questText.Contains('satisfactionTrigger.OnRemoved')) 'quest reacts to buff OnRemoved'
Add-Result ($questText.Contains('To="SetNone"')) 'buff removal resets repeatable quest state'
Add-Result ($questText.Contains('removeResetDelay.OnFinished')) 'quest reactivation is delayed after reset'
Add-Result ($questText.Contains('To="SetActive"')) 'quest can reactivate after reset'
Add-Result ($questText.Contains('<Timer Name="bootDelay">')) 'quest contains cold-start boot timer'
Add-Result ($questText.Contains('<Constant Name="Duration" Value="2s"')) 'cold-start boot check waits two seconds'
Add-Result ($questText.Contains('<Edge From="arm" To="SetRunning"')) 'arming lifecycle starts cold-start timer'
Add-Result ($questText.Contains('<State Name="satisfiedAtWake"')) 'quest tracks satisfaction during boot window'
Add-Result (
    -not $questText.Contains(
        '<Edge From="arm" To="SetFalse" />'
    ) -and
    $questText.Contains(
        '<Edge From="satisfactionTrigger.OnAdded" To="SetTrue" />'
    ) -and
    $questText.Contains(
        '<Edge From="satisfactionTrigger.OnRemoved" To="SetFalse" />'
    )
) 'saved satisfaction latch survives wake and changes only with the real buff tag'
Add-Result (
    $questText.Contains('<Edge From="satisfactionTrigger.OnAdded" To="SetTrue"')
) 'buff presence marks cold start as satisfied'
Add-Result (
    $questText.Contains('<Edge From="satisfactionTrigger.OnRemoved" To="SetFalse"')
) 'buff removal clears cold-start satisfaction latch'
Add-Result ($questText.Contains('<IfFunction Name="coldStartUnsatisfied"')) 'cold start checks satisfaction absence'
Add-Result ($questText.Contains('<IfFunction Name="coldStartQuestNotActive"')) 'cold start guards against active quest restart'
Add-Result (
    $questText.Contains('<Edge From="coldStartQuestNotActive.True" To="SetNone"')
) 'eligible cold start enters repeatable quest reset path'
Add-Result (
    $questText.Contains('<Edge From="coldStartQuestNotActive.True" To="SetRunning"')
) 'eligible cold start schedules delayed activation'

Add-Result (
    $questText.Contains('<SoulAsset Name="RegionalTargetSouls" SharedSoulGuids=')
) 'quest registers the generated regional NPC pool'
Add-Result (
    $questText.Contains('<SetEntityContext Name="selectVictimRequest"') -and
    $questText.Contains('<Constant Name="Context" Value="dp_select_victim_kutnohorsko" />')
) 'quest delegates victim selection to Lua through player script context'
Add-Result (
    $questText.Contains('<BuffTagTrigger Name="targetTagTrigger"') -and
    $questText.Contains('<Constant Name="A" Value="24"')
) 'quest watches the regional pool for dp_is_target'
Add-Result (
    $questText.Contains(
        '<State Name="selectedTarget" TypeT="DP_SelectedTarget">'
    ) -and
    $questText.Contains(
        '<Edge From="targetSlot001Tagged.True" To="SetTarget001" />'
    )
) 'chosen runtime victim marks hidden target selection'
Add-Result (
    -not $questText.Contains('<Function Name="clearTargetTag"')
) 'quest leaves hidden target tag ownership to Lua'
Add-Result (
    $questText.Contains('<State Name="targetObjectiveProgress" TypeT="DP_TargetProgress">') -and
    $questText.Contains('<dark_within_targetk Name="targetVisual">')
) 'quest exposes a second tracked target objective'
Add-Result (
    $questText.Contains('<Objective TypeT="DP_TargetProgress" Name="dark_within_targetk">')
) 'tracked target objective uses generated marker-state type'
Add-Result (
    $questText.Contains(
        '<Edge From="targetSlot001Revealed.True" To="SetDone" />'
    ) -and
    $questText.Contains(
        '<Edge From="targetSlot001Revealed.True" To="SetTarget001" />'
    ) -and
    $questText.Contains(
        '<Edge From="targetSlot002Revealed.True" To="SetTarget002" />'
    )
) 'reveal completes search and hands off to one generated target state'
Add-Result (
    $questText.Contains('<Edge From="targetSlot001Death.OnDeath" To="SetDone"') -and
    $questText.Contains('<Edge From="targetSlot002Death.OnDeath" To="SetDone"') -and
    $questText.Contains('<Edge From="targetSlot003Death.OnDeath" To="SetDone"')
) 'selected victim death completes the generated hunt objective'
Add-Result (
    $questText.Contains(
        '<State Name="cleanupProgress" TypeT="DP_CleanupProgress">'
    ) -and
    $questText.Contains(
        '<dark_within_cleanupk Name="cleanupVisual">'
    ) -and
    $questText.Contains(
        '<Objective TypeT="DP_CleanupProgress" Name="dark_within_cleanupk">'
    )
) 'selected victim death hands off to a tracked cleanup objective'
Add-Result (
    $questText.Contains('<Constant Name="A" Value="25" />') -and
    $questText.Contains('<Constant Name="A" Value="26" />') -and
    $questText.Contains('<Constant Name="A" Value="27" />') -and
    $questText.Contains('<Constant Name="A" Value="28" />') -and
    $questText.Contains(
        '<Edge From="cleanResultTrigger.OnAdded" To="SetDone" />'
    ) -and
    $questText.Contains(
        '<Edge From="controlledResultTrigger.OnAdded" To="SetDone" />'
    ) -and
    $questText.Contains(
        '<Edge From="noisyResultTrigger.OnAdded" To="SetDone" />'
    ) -and
    $questText.Contains(
        '<Edge From="externalResultTrigger.OnAdded" To="SetDone" />'
    ) -and
    -not $questText.Contains(
        '<Edge From="cleanupProgress.OnDone" To="SetDone" />'
    )
) 'all four result tags complete cleanup and the Case directly'
Add-Result (
    $questText.Contains('<MakeArray Name="witnessDetectedTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">') -and
    $questText.Contains(
        "<Constant Name=`"A`" Value=`"$witnessSignalTag`" />"
    ) -and
    $questText -match (
        '(?s)<BuffTagTrigger Name="witnessDetectedTrigger">' +
        '.*?<Asset Name="Souls" Alias="player" />' +
        '.*?<Edge From="witnessDetectedTags\.Array" To="BuffTags" />' +
        '.*?<Edge From="questProgress\.Active" To="IsActive" />' +
        '.*?</BuffTagTrigger>'
    )
) 'quest watches the player for the anonymous witness signal'
Add-Result (
    $questText.Contains(
        '<Edge From="witnessDetectedTrigger.OnAdded" To="SetWitnessed" />'
    ) -and
    $questText.Contains(
        '<StateTypeEnumeration Name="Witnessed" ObjectiveValueType="Started" />'
    ) -and
    $questText -match (
        '(?s)<EnumLog Type="Started" Name="Witnessed" IsTracked="true">' +
        '.*?StringName="dark_within_cleanup_witnessed".*?</EnumLog>'
    )
) 'first witness advances cleanup to a tracked anonymous update'
Add-Result (
    $questText -notmatch (
        '(?s)<EnumLog Type="Started" Name="Witnessed".*?' +
        '(?:Marker=|Alias="RegionalTargetSouls"|Alias="PritokySouls").*?' +
        '</EnumLog>'
    )
) 'anonymous witness update exposes no witness identity or marker'

Add-Result (Test-Path -LiteralPath $luaPath) 'satisfaction Lua bridge exists'
Add-Result ($luaText.Contains($satisfactionGateGuid)) 'Lua bridge uses hidden satisfaction gate GUID'
Add-Result ($luaText.Contains('dp_satisfaction_add')) 'Lua bridge registers add command'
Add-Result ($luaText.Contains('dp_satisfaction_remove')) 'Lua bridge registers remove command'
Add-Result ($luaText.Contains('dp_satisfaction_status')) 'Lua bridge registers status command'
Add-Result (
    $luaText -match (
        '(?s)function DarkPassengerSatisfaction\.Add\(\).*?' +
        'if HasBuff\(soul\) then.*?return true.*?end.*?' +
        'DarkPassengerSatisfaction\.buffHandle = nil.*?' +
        'soul:RemoveAllBuffsByGuid'
    ) -and
    -not $luaText.Contains(
        'if DarkPassengerSatisfaction.buffHandle ~= nil then'
    )
) 'satisfaction add trusts the current player soul over a stale runtime handle'
Add-Result (
    $luaText.Contains(
        'soul:RemoveAllBuffsByGuid(DarkPassengerSatisfaction.BUFF_GUID)'
    ) -and
    -not $luaText.Contains(
        'soul:RemoveBuff(DarkPassengerSatisfaction.BUFF_GUID)'
    )
) 'satisfaction removal uses the GUID-specific retail API'
Add-Result (
    $luaText.Contains(
        'DarkPassengerSatisfaction.buffHandle = handleOrError'
    ) -and
    $luaText.Contains('DarkPassengerSatisfaction.buffHandle = nil')
) 'satisfaction bridge retains and clears the runtime buff handle'
Add-Result (
    $runtimeLuaText.Contains('Script.ReloadScript("Scripts/mods/dpsatisfaction.lua")')
) 'mod init explicitly loads satisfaction Lua bridge'
Add-Result (Test-Path -LiteralPath $hungerLuaPath) 'persistent hunger Lua module exists'
Add-Result (
    $hungerLuaText.Contains('dp_hunger_schema_version') -and
    $hungerLuaText.Contains('dp_last_satisfaction_world_time') -and
    $hungerLuaText.Contains('Variables.SetGlobal') -and
    $hungerLuaText.Contains('Variables.GetGlobal')
) 'hunger timestamp uses the confirmed persistent Variables store'
Add-Result (
    -not $hungerLuaText.Contains('g_localActor.AI.DarkPassenger') -and
    -not $hungerLuaText.Contains('Player.OnSaveAI') -and
    -not $hungerLuaText.Contains('Player.OnLoadAI')
) 'hunger no longer relies on unused legacy player Lua serialization'
Add-Result (
    $hungerLuaText.Contains('Calendar.GetWorldTime()') -and
    $hungerLuaText.Contains('Calendar.GetGameTime()') -and
    $hungerLuaText.Contains('Calendar.GetWorldDay()') -and
    $hungerLuaText.Contains('Calendar.GetWorldHourOfDay()')
) 'clock probe logs every candidate KCD2 time source'
Add-Result (
    $hungerLuaText.Contains('System.IsDevModeEnable()')
) 'clock probe reports whether the current executable runs in dev mode'
Add-Result (
    $hungerLuaText.Contains('dp_hunger_probe') -and
    $hungerLuaText.Contains('dp_hunger_probe_set') -and
    $hungerLuaText.Contains('dp_hunger_probe_clear')
) 'clock probe registers inspect set and clear commands'
Add-Result (
    $hungerLuaText.Contains('function DarkPassengerHunger.Calculate') -and
    $hungerLuaText.Contains('SECONDS_PER_DAY = 86400') -and
    $hungerLuaText.Contains('HUNGER_PER_DAY = 10') -and
    $hungerLuaText.Contains('MAX_HUNGER = 100')
) 'hunger calculation uses ten percent per complete game day'
Add-Result (
    $hungerLuaText.Contains('FIRST_INSTALL_DAYS = 5') -and
    $hungerLuaText.Contains('function DarkPassengerHunger.EnsureInitialized') -and
    -not $hungerLuaText.Contains('lastSatisfaction > 0')
) 'missing hunger state initializes at the first hunt threshold'
Add-Result (
    $hungerLuaText.Contains('dp_hunger_status') -and
    $hungerLuaText.Contains('dp_hunger_set') -and
    $hungerLuaText.Contains('function DarkPassengerHunger.Evaluate')
) 'hunger runtime exposes status debug override and evaluation'
Add-Result (
    $hungerLuaText.Contains('DarkPassengerHunger.BUFF_BY_TIER = {') -and
    $hungerLuaText.Contains('[0] = "16de3823-48bf-4f86-8498-ce45819a48f0"') -and
    $hungerLuaText.Contains('[100] = "03fc0db7-fc98-4562-924d-ddd2c6879262"') -and
    -not $hungerLuaText.Contains('[50] =')
) 'hunger runtime maps every visible tier and leaves fifty neutral'
Add-Result (
    $hungerLuaText.Contains('function DarkPassengerHunger.ApplyTier') -and
    $hungerLuaText.Contains('soul:RemoveAllBuffsByGuid(buffGuid)') -and
    $hungerLuaText.Contains('soul:AddBuff(desiredGuid)')
) 'hunger evaluation keeps exactly one tier buff active'
Add-Result (
    $hungerLuaText -match (
        '(?s)function DarkPassengerHunger\.ApplyTier\(soul, tier\).*?' +
        'if DarkPassengerHunger\.currentTier == tier then return true end.*?' +
        'soul:AddBuff\(desiredGuid\)'
    )
) 'repeated hunger evaluation leaves the current tier buff untouched'
Add-Result (
    $hungerLuaText -match (
        '(?s)function DarkPassengerHunger\.ApplyTier.*?' +
        'soul:AddBuff\(desiredGuid\).*?' +
        'for _, buffGuid in pairs\(DarkPassengerHunger\.BUFF_BY_TIER\)'
    )
) 'positive tier swaps add the replacement before removing the old quest tag'
Add-Result (
    $hungerLuaText -match (
        '(?s)function DarkPassengerHunger\.ResetAfterHunt\(graceDays, result\).*?' +
        'DarkPassengerHunger\.ResetNow\(graceDays\).*?' +
        'DarkPassengerHunger\.satisfactionGateExpected = true.*?' +
        'DarkPassengerHunger\.currentTier = nil.*?' +
        'DarkPassengerHunger\.Evaluate\(\)'
    )
) 'resolved hunt directly resets persistent hunger without probing the gate buff'
Add-Result (
    $hungerLuaText -match (
        '(?s)function DarkPassengerHunger\.ResetNow\(graceDays\).*?' +
        'now \+.*?clampedGraceDays.*?' +
        'DarkPassengerHunger\.SECONDS_PER_DAY'
    ) -and
    $hungerLuaText.Contains(
        'local elapsed = math.max(0, current - previous)'
    )
) 'hunger grace advances the existing timestamp anchor and clamps elapsed time'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.ApplyHungerOutcome\(result\).*?' +
        'result == "clean".*?ResetAfterHunt\(2, result\).*?' +
        'result == "controlled".*?ResetAfterHunt\(1, result\).*?' +
        'result == "noisy".*?ResetAfterHunt\(0, result\)'
    ) -and
    $aftermathLuaText -match (
        '(?s)if result == "external" then\s*return true'
    )
) 'aftermath maps clean controlled noisy and external outcomes to hunger grace'
Add-Result (
    $hungerLuaText -match (
        '(?s)function DarkPassengerHunger\.Status\(\).*?' +
        'graceRemainingDays.*?lastResult.*?effectiveAnchor'
    )
) 'hunger status logs grace result and effective growth anchor'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerQuestBridge\.PollSelectionRequest.*?' +
        'DarkPassengerTarget\.IsRegionQuestActive\(\s*request\.region\s*\).*?' +
        'DarkPassengerTarget\.ResetCase\(request\.region\)'
    ) -and
    $runtimeLuaText -notmatch (
        '(?s)function DarkPassengerQuestBridge\.PollSelectionRequest.*?' +
        'DarkPassengerHunger\.ResetAfterHunt'
    )
) 'quest polling preserves target during cleanup and leaves hunger to aftermath'
Add-Result (
    $hungerLuaText.Contains(
        'DarkPassengerHunger.satisfactionGateExpected'
    ) -and
    -not $hungerLuaText.Contains(
        'HasBuff(soul, DarkPassengerHunger.SATISFACTION_GATE_GUID)'
    )
) 'hidden satisfaction gate lifecycle does not depend on HasBuffDebug'
Add-Result (
    $hungerLuaText.Contains('DarkPassengerHunger.EVALUATION_INTERVAL_MS = 10000') -and
    $hungerLuaText.Contains(
        '"DarkPassengerHunger.OnEvaluationTimer"'
    )
) 'hunger tiers reevaluate after world-time changes without save reload'
Add-Result (
    $hungerLuaText.Contains(
        'function DarkPassengerHunger.StartEvaluation(reason)'
    ) -and
    $hungerLuaText.Contains(
        '{ generation = generation }'
    ) -and
    $hungerLuaText.Contains(
        'requestedGeneration ~= DarkPassengerHunger.evaluationGeneration'
    ) -and
    $hungerLuaText -match (
        '(?s)Script\.SetTimerForFunction\(.*?' +
        '"DarkPassengerHunger\.OnEvaluationTimer".*?' +
        '\{\s*generation\s*=\s*generation\s*\}'
    )
) 'hunger evaluation timer uses retail-safe serializable generation userdata'
Add-Result (
    $runtimeLuaText.Contains(
        'DarkPassengerHunger.StartEvaluation("player_reload")'
    ) -and
    $runtimeLuaText.Contains(
        'DarkPassengerHunger.StartEvaluation("player_init")'
    )
) 'player load lifecycle immediately restarts hunger tier evaluation'
Add-Result (
    $hungerLuaText.Contains(
        'function DarkPassengerHunger.EnsureEvaluationFromPlayerAction'
    ) -and
    $hungerLuaText.Contains(
        'DarkPassengerHunger.StartEvaluation("first_player_action")'
    ) -and
    $runtimeLuaText.Contains(
        'DarkPassengerHunger.EnsureEvaluationFromPlayerAction(...)'
    )
) 'first player action restarts hunger evaluation after save loading cancels timers'
Add-Result (
    $hungerLuaText.Contains('Variables.SetGlobal') -and
    $hungerLuaText.Contains('Variables.GetGlobal') -and
    $hungerLuaText.Contains('GameToken.SetToken') -and
    $hungerLuaText.Contains('GameToken.GetToken') -and
    $hungerLuaText.Contains('XGenAIModule.SetBrainVariable') -and
    $hungerLuaText.Contains('XGenAIModule.GetBrainVariable')
) 'store capability probe compares Variables GameToken and XGen brain storage'
Add-Result (
    $hungerLuaText.Contains('dp_hunger_store_probe') -and
    $hungerLuaText.Contains('dp_hunger_store_read')
) 'store capability probe has live write and read-only console commands'
Add-Result (
    $runtimeLuaText.Contains('Script.ReloadScript("Scripts/mods/dphunger.lua")')
) 'mod init explicitly loads persistent hunger probe'
Add-Result (
    Test-Path -LiteralPath $investigationLuaPath
) 'persistent investigation Lua module exists'
Add-Result (
    $investigationLuaText.Contains(
        'DarkPassengerInvestigation.SCHEMA_VERSION = 1'
    ) -and
    $investigationLuaText.Contains(
        'DarkPassengerInvestigation.REVEAL_THRESHOLD = 70'
    )
) 'investigation owns schema version 1 and seventy confidence threshold'
foreach (
    $investigationFunction in
        'Open',
        'Restore',
        'AddEvidence',
        'OnTargetDeath',
        'Clear',
        'Status'
) {
    Add-Result (
        $investigationLuaText.Contains(
            "function DarkPassengerInvestigation.$investigationFunction"
        )
    ) "investigation exports $investigationFunction"
}
Add-Result (
    $investigationLuaText.Contains(
        'function DarkPassengerInvestigation.Transition'
    ) -and
    $investigationLuaText.Contains(
        'function DarkPassengerInvestigation.RunSelfTest'
    ) -and
    $investigationLuaText.Contains(
        'DarkPassengerInvestigation.Transition('
    )
) 'investigation exposes one pure transition used by its self-test'
foreach (
    $investigationKey in
        'dp_investigation_schema_version',
        'dp_investigation_active_generation',
        'dp_investigation_confidence',
        'dp_investigation_revealed',
        'dp_investigation_reveal_dispatched'
) {
    Add-Result (
        $investigationLuaText.Contains($investigationKey)
    ) "investigation persists $investigationKey"
}
Add-Result (
    $investigationLuaText.Contains('dp_active_target_slot') -and
    -not $investigationLuaText.Contains('dp_investigation_target_slot')
) 'investigation reuses the canonical target slot without duplicating identity'
Add-Result (
    $investigationLuaText.Contains('Variables.GetGlobal') -and
    $investigationLuaText.Contains('Variables.SetGlobal') -and
    $investigationLuaText.Contains('pcall(function()')
) 'investigation protects scalar persistence calls'
Add-Result (
    $investigationLuaText -match (
        '(?s)PersistState\(nextState\).*?' +
        'AddBuff\(DarkPassengerInvestigation.REVEAL_BUFF_GUID\).*?' +
        'nextState.revealDispatched = true.*?PersistState\(nextState\)'
    )
) 'investigation persists reveal before buff and dispatch after acceptance'
Add-Result (
    $investigationLuaText.Contains(
        'System.AddCCommand("dp_investigation_status"'
    ) -and
    $investigationLuaText.Contains(
        'System.AddCCommand("dp_investigation_selftest"'
    )
) 'investigation registers status and self-test commands'
$investigationReload =
    'Script.ReloadScript("Scripts/mods/dpinvestigation.lua")'
$investigationReloadIndex = $runtimeLuaText.IndexOf($investigationReload)
$targetLifecycleIndex =
    $runtimeLuaText.IndexOf('DarkPassengerTarget = DarkPassengerTarget or {}')
Add-Result (
    $investigationReloadIndex -ge 0 -and
    $targetLifecycleIndex -gt $investigationReloadIndex
) 'mod init loads investigation before target lifecycle code'
Add-Result (
    $runtimeLuaText -match (
        '(?s)RememberTarget\(selectedCandidate\).*?' +
        'DarkPassengerInvestigation\.Open\(selectedCandidate, selected\)'
    )
) 'successful target selection opens investigation after slot persistence'
Add-Result (
    $runtimeLuaText -match (
        '(?s)local function BindRecoveredTarget\(candidate, entity\).*?' +
        'DarkPassengerInvestigation\.Restore\(candidate, entity\).*?' +
        'end'
    ) -and
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.RestoreExisting\(gameRegion\).*?' +
        'BindRecoveredTarget\(.*?' +
        'end\s+local function OrderedSettlements'
    ) -and
    $runtimeLuaText -notmatch (
        '(?s)function DarkPassengerTarget\.RestoreExisting\(gameRegion\).*?' +
        'RememberTarget\(.*?' +
        'end\s+local function OrderedSettlements'
    )
) 'every recovered target restores investigation through one binding path'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.OnTargetDeath.*?' +
        'DarkPassengerInvestigation\.OnTargetDeath\(.*?' +
        'DarkPassengerTarget\.Clear\(\)'
    )
) 'target death notifies investigation before target state is cleared'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.Clear\(\).*?' +
        'DarkPassengerInvestigation\.Clear\(previous\).*?' +
        'ForgetPersistedTarget\(\)'
    )
) 'target reset removes reveal signal and clears investigation state'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.SelectNearest\(gameRegion\).*?' +
        'DarkPassengerTarget\.RestoreExisting\(gameRegion\).*?' +
        'DarkPassengerTarget\.Select\('
    )
) 'nearest selection restores a valid target instead of rerolling it'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTest\.Evidence\(argsLine\).*?' +
        'DarkPassengerInvestigation\.AddEvidence\(amount, label\).*?' +
        'end'
    ) -and
    $runtimeLuaText -notmatch (
        '(?s)function DarkPassengerTest\.Evidence\(argsLine\).*?' +
        'DarkPassengerCase\.AddEvidence\(.*?end'
    )
) 'legacy evidence command delegates only to persistent investigation'
Add-Result (
    $investigationLuaText.Contains(
        'DarkPassengerInvestigation.SLICE_SETTLEMENT_OVERRIDES'
    ) -and
    $investigationLuaText.Contains(
        'function DarkPassengerInvestigation.GetSettlementOverride'
    ) -and
    ([regex]::Matches(
        $investigationLuaText,
        '"pritoky"'
    ).Count -eq 1) -and
    $runtimeLuaText -match (
        '(?s)function NeedsQuestSelectionMigration\(candidate\).*?' +
        'candidate\.gameRegion == "kutnohorsko".*?' +
        'candidate\.settlement == "pritoky"'
    )
) 'Pritoky selection override and legacy migration remain separately scoped'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.SelectNearest\(gameRegion\).*?' +
        'DarkPassengerInvestigation\.GetSettlementOverride\(gameRegion\).*?' +
        'DarkPassengerTarget\.Select\(gameRegion, settlementOverride\)'
    )
) 'automatic Kuttenberg selection uses the investigation settlement override'
Add-Result ($runtimeLuaText.Contains('result == "RESOLVED_CORRECT"')) 'correct case resolution is explicitly gated'
Add-Result ($runtimeLuaText.Contains('previousState ~= "RESOLVED_CORRECT"')) 'already resolved cases cannot grant satisfaction twice'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.OnTargetDeath.*?' +
        'DarkPassengerAftermath\.Begin\(.*?' +
        'gameRegion.*?settlement.*?expectedSlot'
    ) -and
    -not $runtimeLuaText.Contains('replacing after graph delay')
) 'any selected-target death starts aftermath instead of choosing a replacement'
Add-Result (
    $runtimeLuaText.Contains('function DarkPassengerTest.TestHudObjectiveMarker')
) 'runtime exposes HUD objective marker probe'
Add-Result (
    $runtimeLuaText.Contains('Quest.RegisterQuestEntity(target.id)')
) 'HUD marker probe registers the runtime quest entity'
Add-Result (
    $runtimeLuaText.Contains('HUD.SetObjectiveEntity("dark_within_obj", entityName)') -and
    $runtimeLuaText.Contains('HUD.SetObjectiveEntity("dark_within_objk", entityName)')
) 'HUD marker probe binds both candidate objective ids to runtime entity'
Add-Result (
    $runtimeLuaText.Contains('dp_test_hud_marker')
) 'HUD marker probe has a retail console command'
Add-Result (
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_probe_status"')
) 'aftermath exposes read-only status probe'
Add-Result (
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_probe_nearby"')
) 'aftermath exposes read-only nearby-entity probe'
Add-Result (
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_probe_crime"')
) 'aftermath exposes read-only crime-state probe'
Add-Result (
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_probe_attribution"')
) 'aftermath exposes read-only attribution probe'
Add-Result (
    $runtimeLuaText.Contains(
        'function DarkPassengerAftermathProbe.WitnessArm'
    ) -and
    $runtimeLuaText.Contains(
        'function DarkPassengerAftermathProbe.WitnessSample'
    ) -and
    $runtimeLuaText.Contains(
        'function DarkPassengerAftermathProbe.WitnessClear'
    )
) 'aftermath exposes witness snapshot and diff probes'
Add-Result (
    $runtimeLuaText.Contains('System.AddCCommand("dp_witness_probe_arm"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_witness_probe_sample"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_witness_probe_clear"')
) 'witness probes have explicit read-only console commands'
Add-Result (
    $runtimeLuaText.Contains(
        'function DarkPassengerAftermathProbe.WitnessWatch'
    ) -and
    $runtimeLuaText.Contains(
        'function DarkPassengerAftermathProbe.WitnessWatchStop'
    ) -and
    $runtimeLuaText.Contains(
        'System.AddCCommand("dp_witness_probe_watch"'
    ) -and
    $runtimeLuaText.Contains(
        'System.AddCCommand("dp_witness_probe_stop"'
    )
) 'witness probe exposes a bounded live watcher'
$witnessProbeReadOnlyMatch = [regex]::Match(
    $runtimeLuaText,
    '(?s)-- DP_WITNESS_PROBE_READ_ONLY_BEGIN(.*?)' +
    '-- DP_WITNESS_PROBE_READ_ONLY_END'
)
Add-Result (
    $witnessProbeReadOnlyMatch.Success
) 'witness probe marks its read-only implementation boundary'
$witnessProbeReadOnlyText = $witnessProbeReadOnlyMatch.Groups[1].Value
Add-Result (
    $witnessProbeReadOnlyMatch.Success -and
    -not $witnessProbeReadOnlyText.Contains(':AddBuff(') -and
    -not $witnessProbeReadOnlyText.Contains('SetEntityContext') -and
    -not $witnessProbeReadOnlyText.Contains('RecordSuspicion') -and
    -not $witnessProbeReadOnlyText.Contains('Resolve(')
) 'witness snapshot probes cannot mutate quest or aftermath state'
Add-Result (
    $witnessProbeReadOnlyMatch.Success -and
    $witnessProbeReadOnlyText.Contains(
        'XGenAIModule.FindLinks(linkSourceId, tag)'
    ) -and
    -not $witnessProbeReadOnlyText.Contains(
        'XGenAIModule.FindLinks(entity.id, tag)'
    )
) 'witness link probe queries the NPC soul WUID'
Add-Result (
    $runtimeLuaText.Contains('"crime_anchor"') -and
    $runtimeLuaText.Contains('"crime_playerAwareness"')
) 'witness link probe covers active crime ownership links'
Add-Result (
    $runtimeLuaText.Contains('"crime_interruptReport_reporting"')
) 'witness watcher observes the native completed-report handoff phase'
Add-Result (
    $witnessProbeReadOnlyMatch.Success -and
    $witnessProbeReadOnlyText.Contains(
        'DarkPassengerAftermathProbe.WITNESS_WATCH_INTERVAL_MS = 500'
    ) -and
    $witnessProbeReadOnlyText.Contains(
        'DarkPassengerAftermathProbe.WitnessSample(tostring(radius), false)'
    )
) 'live witness watcher samples context and links without noisy brain reads'
Add-Result (
    $witnessProbeReadOnlyMatch.Success -and
    $witnessProbeReadOnlyText.Contains(
        'if includeBrain ~= false or reporting == true then'
    ) -and
    $witnessProbeReadOnlyText.Contains(
        'brain = WitnessProbeBrain(entity)'
    )
) 'live witness watcher reads brain state only for active reporters'
Add-Result (
    -not $runtimeLuaText.Contains('"crime_greyOutEAndDisableChat"')
) 'witness probe excludes the nonexistent grey-out chat context'
Add-Result (
    Test-Path -LiteralPath $witnessLuaPath
) 'persistent witness ledger module exists'
foreach ($stateName in @(
    'STATE_UNREPORTED',
    'STATE_REPORTED',
    'STATE_SILENCED_BEFORE_REPORT',
    'STATE_SILENCED_AFTER_REPORT',
    'STATE_LOST'
)) {
    Add-Result (
        $witnessLuaText.Contains(
            "DarkPassengerWitness.$stateName"
        )
    ) "witness ledger exports $stateName"
}
foreach ($functionName in @(
    'BeginCase',
    'Confirm',
    'GetRecord',
    'MarkReported',
    'MarkDead',
    'MarkLost',
    'GetCaseOutcome',
    'Persist',
    'Restore',
    'Status'
)) {
    Add-Result (
        $witnessLuaText.Contains(
            "function DarkPassengerWitness.$functionName"
        )
    ) "witness ledger exports $functionName"
}
foreach ($schemaKey in @(
    'dp_witness_schema_version',
    'dp_witness_record_count',
    'dp_witness_next_record_id',
    'dp_witness_active_case_generation',
    'dp_witness_noisy_locked',
    'dp_witness_notification_emitted',
    'dp_witness_v1_'
)) {
    Add-Result (
        $witnessLuaText.Contains($schemaKey)
    ) "witness ledger persists $schemaKey"
}
Add-Result (
    $witnessLuaText -match (
        '(?s)local function ResetRuntimeState\(\).*?' +
        'DarkPassengerWitness\.records\s*=\s*\{\}.*?' +
        'DarkPassengerWitness\.index\s*=\s*\{\}.*?' +
        'DarkPassengerWitness\.recordCount\s*=\s*0.*?' +
        'DarkPassengerWitness\.nextRecordId\s*=\s*1'
    ) -and
    $witnessLuaText -match (
        '(?s)function DarkPassengerWitness\.Restore\(reason\)\s*' +
        'ResetRuntimeState\(\)\s*local keys.*?' +
        'if ReadGlobal\(keys\.schema\)\s*~=\s*' +
        'DarkPassengerWitness\.SCHEMA_VERSION'
    )
) 'missing save witness schema clears stale runtime records before restore'
Add-Result (
    $witnessLuaText -match (
        '(?s)STATE_UNREPORTED\]\s*=\s*' +
        'DarkPassengerWitness\.STATE_SILENCED_BEFORE_REPORT'
    ) -and
    $witnessLuaText -match (
        '(?s)STATE_REPORTED\]\s*=\s*' +
        'DarkPassengerWitness\.STATE_SILENCED_AFTER_REPORT'
    )
) 'witness death transition preserves whether reporting already happened'
Add-Result (
    $witnessLuaText.Contains('return "clean"') -and
    $witnessLuaText.Contains('return "controlled"') -and
    $witnessLuaText.Contains('return "noisy"')
) 'witness ledger exposes clean controlled and noisy outcomes'
Add-Result (
    $witnessLuaText -match (
        '(?s)local function CaseCode\(value\).*?' +
        'type\(value\)\s*==\s*"number".*?return value.*?' +
        'return StableCode\(value\)'
    ) -and
    $witnessLuaText -match (
        '(?s)function DarkPassengerWitness\.BeginCase.*?' +
        'activeRegionCode\s*=\s*CaseCode\(region\).*?' +
        'activeSettlementCode\s*=\s*CaseCode\(settlement\)'
    )
) 'witness case preserves numeric region and settlement codes on restore'
Add-Result (
    Test-Path -LiteralPath $witnessDetectorLuaPath
) 'runtime witness detector module exists'
Add-Result (
    $witnessDetectorLuaText -match 'SCAN_INTERVAL_MS\s*=\s*500' -and
    $witnessDetectorLuaText.Contains(
        'System.GetEntitiesInSphere(origin, radius)'
    ) -and
    $witnessDetectorLuaText.Contains(
        'DarkPassengerAftermath.deathX'
    ) -and
    $witnessDetectorLuaText.Contains(
        'DarkPassengerAftermath.zoneRadius'
    )
) 'witness detector scans only the bounded aftermath zone every 500 ms'
Add-Result (
    $witnessDetectorLuaText.Contains(
        'HasScriptContext("crime_interruptReport")'
    ) -and
    $witnessDetectorLuaText.Contains(
        'HasScriptContext("crime_interruptReport_reporting")'
    ) -and
    -not $witnessDetectorLuaText.Contains(
        'HasScriptContext("crime_interrupt")'
    ) -and
    -not $witnessDetectorLuaText.Contains('wanted')
) 'witness detector uses only proven report intent and handoff contexts'
Add-Result (
    $witnessDetectorLuaText -match (
        '(?s)if reportIntent and not previous\.reportIntent then.*?' +
        'DarkPassengerAftermath\.RecordWitness\('
    ) -and
    $witnessDetectorLuaText -match (
        '(?s)if reporting and not previous\.reporting then.*?' +
        'DarkPassengerAftermath\.RecordReport\('
    )
) 'witness detector maps rising native report edges into the ledger'
Add-Result (
    $witnessDetectorLuaText.Contains('entity.soul:GetId()') -and
    $witnessDetectorLuaText.Contains(
        'DarkPassengerWitness.IdentityFromWuid(soulId)'
    )
) 'witness detector keys records by stable Soul WUID halves'
Add-Result (
    $witnessDetectorLuaText.Contains('Calendar.GetWorldTime()')
) 'witness ledger event times survive save reloads in game-world time'
Add-Result (
    $witnessDetectorLuaText -match (
        '(?s)DarkPassengerWitness\.GetRecord\(.*?' +
        'DarkPassengerAftermath\.RecordWitnessDeath\('
    ) -and
    $witnessDetectorLuaText.Contains(
        'function DarkPassengerWitnessDetector.RecordAttributedDeath'
    ) -and
    $runtimeLuaText.Contains(
        'DarkPassengerWitnessDetector.RecordAttributedDeath(victim, method)'
    )
) 'witness detector tracks later death and verified Henry attribution'
Add-Result (
    $witnessDetectorLuaText -match (
        '(?s)Script\.SetTimerForFunction\(.*?' +
        '"DarkPassengerWitnessDetector\.OnTimer".*?' +
        'generationToken.*?timerSerial'
    )
) 'witness detector timer rejects stale case generations'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.Begin.*?' +
        'DarkPassengerWitnessDetector\.Start\('
    ) -and
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.Restore.*?' +
        'DarkPassengerWitnessDetector\.Start\('
    ) -and
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.Resolve.*?' +
        'DarkPassengerWitnessDetector\.Stop\('
    )
) 'aftermath owns witness detector start restore and stop lifecycle'
Add-Result (
    $runtimeLuaText -match (
        '(?s)Script\.ReloadScript\("Scripts/mods/dpwitness\.lua"\).*?' +
        'Script\.ReloadScript\("Scripts/mods/dpaftermath\.lua"\).*?' +
        'Script\.ReloadScript\("Scripts/mods/dpwitnessdetector\.lua"\)'
    )
) 'mod init loads witness ledger aftermath and detector in dependency order'
Add-Result (
    $runtimeLuaText.Contains('Script.ReloadScript("Scripts/mods/dpaftermath.lua")')
) 'mod init explicitly loads aftermath state machine'
Add-Result (
    $aftermathLuaText.Contains('DarkPassengerAftermath.PHASE_HUNTING') -and
    $aftermathLuaText.Contains('DarkPassengerAftermath.PHASE_SILENCE_CHECK') -and
    $aftermathLuaText.Contains('DarkPassengerAftermath.PHASE_CLEANUP') -and
    $aftermathLuaText.Contains('DarkPassengerAftermath.PHASE_RESOLVED')
) 'aftermath exports all phase constants'
Add-Result (
    $aftermathLuaText -match 'SILENCE_DURATION_MS\s*=\s*90000'
) 'aftermath silence check lasts 90 seconds'
foreach ($aftermathFunction in @(
    'Begin',
    'RecordSuspicion',
    'RecordWitness',
    'RecordReport',
    'RecordWitnessDeath',
    'LockNoisy',
    'RecordWitnessRemoved',
    'OnPlayerPosition',
    'Resolve',
    'Status'
)) {
    Add-Result (
        $aftermathLuaText.Contains(
            "function DarkPassengerAftermath.$aftermathFunction"
        )
    ) "aftermath exports $aftermathFunction"
}
Add-Result (
    $aftermathLuaText.Contains('Script.SetTimerForFunction(') -and
    $aftermathLuaText.Contains('generationToken')
) 'aftermath silence timer rejects stale generations'
Add-Result (
    $aftermathLuaText.Contains('distanceFromDeath >= zoneRadius') -and
    -not $aftermathLuaText.Contains('wanted')
) 'aftermath zone exit resolves independently of wanted status'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.RecordWitnessRemoved.*?' +
        'RecordSuspicion\("witness_removed"\)'
    )
) 'removing a witness cancels clean silence and enters cleanup'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.Begin.*?' +
        'DarkPassengerWitness\.BeginCase\('
    )
) 'aftermath begins a matching persistent witness case'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.RecordWitness.*?' +
        'DarkPassengerWitness\.Confirm\('
    )
) 'aftermath confirms a witness without immediately locking noisy'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.RecordReport.*?' +
        'DarkPassengerWitness\.MarkReported\('
    ) -and
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.RecordReport.*?' +
        'DarkPassengerWitness\.LockNoisy\('
    )
) 'completed witness report irreversibly locks noisy'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.RecordWitnessDeath.*?' +
        'DarkPassengerWitness\.MarkDead\('
    )
) 'aftermath maps witness death into the persistent ledger'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.OnPlayerPosition.*?' +
        'DarkPassengerWitness\.GetCaseOutcome\('
    ) -and
    $aftermathLuaText -notmatch (
        '(?s)PHASE_CLEANUP.*?Resolve\("noisy"\)'
    )
) 'cleanup zone exit resolves from witness state instead of unconditional noisy'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.Restore.*?' +
        'DarkPassengerWitness\.Restore\('
    )
) 'aftermath restore reloads the matching witness ledger'
Add-Result (
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_begin"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_suspicion"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_witness_removed"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_exit"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_status"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_recover"')
) 'aftermath state machine exposes debug-only transition commands'
Add-Result (
    $aftermathLuaText.Contains('dp_aftermath_schema_version') -and
    $aftermathLuaText.Contains('dp_aftermath_phase') -and
    $aftermathLuaText.Contains('dp_aftermath_region_code') -and
    $aftermathLuaText.Contains('dp_aftermath_settlement_code') -and
    $aftermathLuaText.Contains('dp_aftermath_target_slot')
) 'aftermath persists versioned case identity'
Add-Result (
    $aftermathLuaText.Contains('dp_aftermath_death_x') -and
    $aftermathLuaText.Contains('dp_aftermath_death_y') -and
    $aftermathLuaText.Contains('dp_aftermath_death_z') -and
    $aftermathLuaText.Contains('dp_aftermath_zone_radius')
) 'aftermath persists death position and zone radius'
Add-Result (
    $aftermathLuaText.Contains('dp_aftermath_silence_remaining_ms') -and
    $aftermathLuaText.Contains('dp_aftermath_generation') -and
    $aftermathLuaText.Contains('dp_aftermath_resolved_generation')
) 'aftermath persists timer and idempotency generations'
Add-Result (
    $aftermathLuaText.Contains('dp_aftermath_exposed') -and
    $aftermathLuaText.Contains('dp_aftermath_collateral_count') -and
    $aftermathLuaText.Contains('dp_aftermath_witness_removed_count')
) 'aftermath persists exposure and collateral state'
Add-Result (
    $aftermathLuaText.Contains('Variables.GetGlobal') -and
    $aftermathLuaText.Contains('Variables.SetGlobal') -and
    $aftermathLuaText.Contains('function DarkPassengerAftermath.Persist') -and
    $aftermathLuaText.Contains('function DarkPassengerAftermath.Restore')
) 'aftermath uses protected Variables scalar persistence'
Add-Result (
    $aftermathLuaText.Contains('silenceRemainingMs') -and
    $aftermathLuaText.Contains('timerSerial') -and
    $aftermathLuaText.Contains('OnPersistenceHeartbeat')
) 'aftermath resumes active-play silence time without duplicate timers'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.OnPersistenceHeartbeat' +
        '.*?PlayerPosition\(\).*?' +
        'DarkPassengerAftermath\.OnPlayerPosition' +
        '.*?function DarkPassengerAftermath\.OnPlayerPosition'
    )
) 'aftermath heartbeat polls player position for automatic zone exit'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.Restore\(reason\)' +
        '.*?PHASE_CLEANUP.*?SchedulePersistenceHeartbeat' +
        '.*?function DarkPassengerAftermath\.OnDeferredRestore'
    ) -and
    $aftermathLuaText -match (
        '(?s)local function EnterCleanup\(reason, exposed\)' +
        '.*?PHASE_CLEANUP.*?SchedulePersistenceHeartbeat' +
        '.*?function DarkPassengerAftermath\.RecordSuspicion\(reason\)'
    )
) 'cleanup zone polling starts on suspicion and resumes after load'
Add-Result (
    $aftermathLuaText.Contains(
        'function DarkPassengerAftermath.EmitResultSignal(result)'
    ) -and
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.Resolve\(result\).*?' +
        'PHASE_RESOLVED.*?return false.*?' +
        'resolvedGeneration\s*=\s*DarkPassengerAftermath\.generation.*?' +
        'DarkPassengerAftermath\.EmitResultSignal'
    ) -and
    $aftermathLuaText.Contains('playerSoul:AddBuff(resultGuid)')
) 'aftermath emits one hidden result signal only on first resolution'
Add-Result (
    $aftermathLuaText.Contains($witnessSignalGuid) -and
    $aftermathLuaText.Contains(
        'function DarkPassengerAftermath.EmitWitnessSignal()'
    ) -and
    $aftermathLuaText.Contains(
        'DarkPassengerWitness.SetNotificationEmitted()'
    ) -and
    $aftermathLuaText -match (
        'playerSoul:AddBuff\(\s*' +
        'DarkPassengerAftermath\.WITNESS_SIGNAL_BUFF_GUID\s*\)'
    )
) 'aftermath emits the witness signal and persists one-shot delivery'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.Begin\(.*?' +
        'RemoveAllBuffsByGuid\(\s*' +
        'DarkPassengerAftermath\.WITNESS_SIGNAL_BUFF_GUID\s*\).*?' +
        'DarkPassengerWitnessDetector\.Start'
    )
) 'new aftermath clears the previous witness signal before detector scan'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.RecordWitness\(.*?' +
        'DarkPassengerAftermath\.EmitWitnessSignal\(\).*?' +
        'return true'
    )
) 'confirmed witness requests the anonymous update signal'
Add-Result (
    $runtimeLuaText -match (
        '(?s)OnReloadEvent.*?DarkPassengerAftermath\.ScheduleRestore' +
        '.*?OnInitEvent.*?DarkPassengerAftermath\.ScheduleRestore'
    )
) 'player load lifecycle schedules aftermath restore after load settles'
Add-Result (
    $aftermathLuaText.Contains(
        'function DarkPassengerAftermath.ScheduleRestore'
    ) -and
    $aftermathLuaText.Contains(
        '"DarkPassengerAftermath.OnDeferredRestore"'
    ) -and
    $aftermathLuaText.Contains(
        'function DarkPassengerAftermath.OnDeferredRestore'
    )
) 'aftermath defers load restore so game loading cannot cancel resumed timers'
Add-Result (
    $runtimeLuaText -match (
        '(?s)OnActionEvent.*?' +
        'DarkPassengerAftermath\.EnsureRestoreFromPlayerAction'
    ) -and
    $aftermathLuaText.Contains(
        'function DarkPassengerAftermath.EnsureRestoreFromPlayerAction'
    ) -and
    $aftermathLuaText.Contains(
        'DarkPassengerAftermath.HEARTBEAT_STALE_MS'
    ) -and
    $aftermathLuaText.Contains(
        'nowMs - DarkPassengerAftermath.lastHeartbeatTimeMs'
    )
) 'first player action retries aftermath restore when heartbeat becomes stale'
Add-Result (
    $aftermathLuaText.Contains('dp_aftermath_attention_v1_') -and
    $aftermathLuaText.Contains('dp_aftermath_blood_trail_v1_') -and
    $aftermathLuaText.Contains(
        'function DarkPassengerAftermath.AdjustSettlementMetrics'
    )
) 'aftermath persists versioned settlement attention and blood trail'
Add-Result (
    Test-Path -LiteralPath $questItemGeneratorPath
) 'quest-item catalog generator exists'
Add-Result (
    Test-Path -LiteralPath $questItemCatalogLuaPath
) 'generated base-game quest-item catalog exists'
Add-Result (
    $questItemCatalogLuaText.Contains(
        'DarkPassengerQuestItemCatalog = {'
    ) -and
    ([regex]::Matches($questItemCatalogLuaText, '= true')).Count -eq 293 -and
    -not $questItemCatalogLuaText.Contains(
        '73762008-de9b-4c42-b509-235e63e60840'
    )
) 'quest-item catalog contains only the 293 authoritative base classes'
Add-Result (
    Test-Path -LiteralPath $burialLuaPath
) 'global corpse burial Lua module exists'
foreach ($export in @(
    'InstallActionHook',
    'AddBuryAction',
    'CanBury',
    'HasQuestItem',
    'IsDiggableGround',
    'OnBuryBody',
    'OnSkipTimeStep',
    'RecoverEntity',
    'Finish'
)) {
    Add-Result (
        $burialLuaText.Contains(
            "function DarkPassengerBurial.$export"
        )
    ) "corpse burial exports $export"
}
Add-Result (
    $runtimeLuaText.IndexOf(
        'Script.ReloadScript("Scripts/mods/generated/dp_quest_item_catalog.lua")'
    ) -ge 0 -and
    $runtimeLuaText.IndexOf(
        'Script.ReloadScript("Scripts/mods/dpburial.lua")'
    ) -gt
    $runtimeLuaText.IndexOf(
        'Script.ReloadScript("Scripts/mods/generated/dp_quest_item_catalog.lua")'
    )
) 'mod init loads quest-item catalog before corpse burial'
Add-Result (
    $interactionsLuaText.Contains(
        'local actionClassNames = { "NPC", "NPC_Female", "NPC_NAI" }'
    )
) 'shared interaction registry targets the live NPC action classes'
Add-Result (
    $interactionsLuaText.Contains('classTable.GetActions = wrapper') -and
    $interactionsLuaText.Contains(
        'DarkPassengerInteractions.Dispatch('
    )
) 'shared registry injects providers through the live NPC class method'
Add-Result (
    $burialLuaText.Contains('DarkPassengerInteractions.RegisterProvider(') -and
    $burialLuaText.Contains('"burial"') -and
    -not $burialLuaText.Contains('classTable.GetActions = wrapper')
) 'burial registers one named provider without owning class hooks'
Add-Result (
    -not $interactionsLuaText.Contains('BasicAIActions.GetActions = wrapper')
) 'interaction registry does not mutate the invisible base action table'
Add-Result (
    $burialLuaText.Contains(':uiOrder(3)')
) 'burial action uses the proven Mercenaries interaction ordering'
Add-Result (
    $burialLuaText -notmatch (
        '(?s)function DarkPassengerBurial\.AddBuryAction.*?' +
        'if firstFast and #output > 0 then return false end'
    )
) 'burial action remains available beside the fast vanilla corpse action'
Add-Result (
    $burialLuaText.Contains('corpse.human == nil') -and
    $burialLuaText.Contains('corpse.actor:IsDead()')
) 'burial is restricted to dead humans'
Add-Result (
    $burialLuaText.Contains(
        '85409fc6-36ff-4de7-b337-e2889e435f1b'
    ) -and
    $burialLuaText.Contains('GetCountOfClass') -and
    -not $burialLuaText.Contains('DeleteItemOfClass')
) 'burial requires but never consumes the shovel'
Add-Result (
    $burialLuaText.Contains('GetInventoryTable') -and
    $burialLuaText.Contains('ItemManager.GetItem') -and
    $burialLuaText.Contains('DarkPassengerQuestItemCatalog') -and
    $burialLuaText.Contains('quest_catalog_unavailable')
) 'burial blocks quest items and fails closed when metadata is unavailable'
Add-Result (
    $burialLuaText.Contains('Physics.RayWorldIntersection') -and
    $burialLuaText.Contains('System.GetSurfaceTypeNameById') -and
    @(
        'mat_soil',
        'mat_mud',
        'mat_grass',
        'mat_forest',
        'mat_gravel',
        'mat_road',
        'mat_field'
    ).Where({ $burialLuaText.Contains($_) }).Count -eq 7
) 'burial validates the proven diggable surface families'
Add-Result (
    $burialLuaText.Contains('@dp_burial_action') -and
    $burialLuaText.Contains(':action("butcher")') -and
    $burialLuaText.Contains('AHT_HOLD') -and
    $burialLuaText.Contains(':reason(reason)')
) 'burial uses the native held-F contextual action with disabled reasons'
$burialCanBuryMatch = [regex]::Match(
    $burialLuaText,
    '(?s)function DarkPassengerBurial\.CanBury\(corpse, user\).*?^end$',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$burialCanBuryText = $burialCanBuryMatch.Value
Add-Result (
    $burialLuaText.Contains(
        'local function IsInCombatDanger(actor)'
    ) -and
    $burialLuaText.Contains(
        'actor.soul:IsInCombatDanger()'
    ) -and
    $burialLuaText.Contains(
        'pcall(function()'
    )
) 'burial reads native combat danger through a protected helper'
Add-Result (
    $burialCanBuryMatch.Success -and
    $burialCanBuryText.Contains(
        'return false, "@dp_burial_in_combat"'
    ) -and
    $burialCanBuryText.IndexOf(
        'IsInCombatDanger(actor)'
    ) -ge 0 -and
    $burialCanBuryText.IndexOf(
        'IsInCombatDanger(actor)'
    ) -lt $burialCanBuryText.IndexOf(
        'HasShovel(actor)'
    )
) 'burial disables the action for combat before inventory and ground checks'
$burialInvokeMatch = [regex]::Match(
    $burialLuaText,
    '(?s)function DarkPassengerBurial\.OnBuryBody\(corpse, user, slotId\).*?^end$',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)
Add-Result (
    $burialInvokeMatch.Success -and
    $burialInvokeMatch.Value.Contains(
        'DarkPassengerBurial.CanBury(corpse, user)'
    )
) 'burial revalidates combat danger when the held action is invoked'
Add-Result (
    $burialLuaText -match 'TOTAL_TIME_SECONDS\s*=\s*7' -and
    $burialLuaText -match 'WORLD_TIME_SECONDS\s*=\s*3600' -and
    $burialLuaText -match 'EXHAUST_COST\s*=\s*10' -and
    $burialLuaText -match 'HUNGER_COST\s*=\s*5'
) 'burial uses the approved duration time and stat costs'
Add-Result (
    $burialLuaText.Contains('UIAction.HideElement("hud", 0)') -and
    $burialLuaText.Contains('"AddOverlay"') -and
    $burialLuaText.Contains('"AddDialog"') -and
    $burialLuaText.Contains('"SetStats"') -and
    $burialLuaText.Contains('"SetInterval"') -and
    $burialLuaText.Contains('"SetTime"') -and
    $burialLuaText.Contains('"FadeOutDialog"')
) 'burial uses the live-proven native SkipTime presentation'
Add-Result (
    $burialLuaText.Contains('special_skiptime_digging') -and
    $burialLuaText.Contains('AudioUtils.LookupTriggerID') -and
    $burialLuaText.Contains('actor:StopAudioTrigger(') -and
    $burialLuaText.Contains('actor:GetDefaultAuxAudioProxyID()')
) 'burial stops digging audio through the proven native entity method'
Add-Result (
    $burialLuaText.Contains('Game.AddSaveLock(') -and
    $burialLuaText.Contains('Game.RemoveSaveLock(') -and
    $burialLuaText.Contains('function DarkPassengerBurial.OnFailsafe')
) 'burial always has save-lock and failsafe cleanup'
Add-Result (
    -not (Test-Path -LiteralPath $burialRecoveryTreePath) -and
    -not (Test-Path -LiteralPath $legacyBurialRecoveryTreePath) -and
    -not $burialLuaText.Contains('AI.StartModularBehaviorTree(')
) 'burial does not invoke the incompatible CryEngine modular tree loader'
$burialBeginPresentationMatch = [regex]::Match(
    $burialLuaText,
    '(?s)local function BeginPresentation\(corpse, actor\).*?^end$',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)
Add-Result (
    $burialBeginPresentationMatch.Success -and
    $burialBeginPresentationMatch.Value.Contains(
        'DarkPassengerBurial.RecoverEntity(corpse)'
    ) -and
    $burialBeginPresentationMatch.Value.IndexOf(
        'DarkPassengerBurial.RecoverEntity(corpse)'
    ) -lt $burialBeginPresentationMatch.Value.IndexOf(
        'Calendar.SetWorldTime('
    )
) 'burial moves the corpse before advancing SkipTime world time'
Add-Result (
    $burialLuaText.Contains(
        'local function SameEntityId(left, right)'
    ) -and
    $burialLuaText.Contains(
        'not SameEntityId(corpse.id, active.corpseId)'
    )
) 'burial accepts equivalent engine handles returned by a fresh entity lookup'
Add-Result (
    $burialLuaText -match 'RECOVERY_EDGE_MIN\s*=\s*16' -and
    $burialLuaText -match 'RECOVERY_GRID_SIZE\s*=\s*16' -and
    $burialLuaText -match 'RECOVERY_GRID_STEP\s*=\s*2' -and
    $burialLuaText.Contains('System.GetTerrainElevation(position)')
) 'burial derives an in-bounds map-edge recovery grid from live terrain'
Add-Result (
    (Test-Path -LiteralPath (
        Join-Path $DevGameRoot 'Data\Levels\kutnohorsko\terrainnm\00_00.bmp'
    )) -and
    (Test-Path -LiteralPath (
        Join-Path $DevGameRoot 'Data\Levels\trosecko\terrainnm\00_00.bmp'
    ))
) 'both open-world regions contain terrain at the recovery edge'
Add-Result (
    $null -ne $rawWorldCandidates -and
    @($rawWorldCandidates.candidates | Where-Object {
        [double]$_.position.x -le 50 -and
        [double]$_.position.y -le 50
    }).Count -eq 0
) 'the recovery grid contains no extracted settlement NPC'
Add-Result (
    -not $burialLuaText.Contains('System.RemoveEntity') -and
    -not $burialLuaText.Contains('System.ReturnEntityToPool') -and
    -not $burialLuaText.Contains(':Hide(') -and
    -not $burialLuaText.Contains('RemoveAllItems')
) 'burial never destroys or hides a persistent NPC entity'
$burialSkipStepMatch = [regex]::Match(
    $burialLuaText,
    '(?s)function DarkPassengerBurial\.OnSkipTimeStep.*?^end$',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$burialSkipStepText = $burialSkipStepMatch.Value
Add-Result (
    $burialSkipStepMatch.Success -and
    $burialSkipStepText.IndexOf(
        'UIAction.CallFunction("Overlay", 1, "SetAlpha", 5, 255)'
    ) -ge 0 -and
    $burialSkipStepText.IndexOf('BeginCorpseRecovery(active)') -gt
        $burialSkipStepText.IndexOf(
            'UIAction.CallFunction("Overlay", 1, "SetAlpha", 5, 255)'
        ) -and
    $burialSkipStepText.IndexOf('BeginCorpseRecovery(active)') -lt
        $burialSkipStepText.IndexOf('local elapsed =')
) 'burial starts corpse recovery while the opening overlay is fully black'
Add-Result (
    $burialSkipStepMatch.Success -and
    $burialSkipStepText.IndexOf('BeginCorpseRecovery(active)') -ge 0 -and
    $burialSkipStepText.IndexOf('"FadeOutDialog"') -ge 0 -and
    $burialSkipStepText.IndexOf('BeginCorpseRecovery(active)') -lt
        $burialSkipStepText.IndexOf('"FadeOutDialog"')
) 'burial starts corpse recovery before the SkipTime overlay reveals the world'
$burialFinishMatch = [regex]::Match(
    $burialLuaText,
    '(?s)function DarkPassengerBurial\.Finish.*?^end$',
    [System.Text.RegularExpressions.RegexOptions]::Multiline
)
$burialFinishText = $burialFinishMatch.Value
Add-Result (
    $burialFinishMatch.Success -and
    $burialFinishText.IndexOf('FinishCorpseRecovery(active)') -ge 0 -and
    $burialFinishText.IndexOf('RestorePresentation()') -ge 0 -and
    $burialFinishText.IndexOf('FinishCorpseRecovery(active)') -lt
        $burialFinishText.IndexOf('RestorePresentation()')
) 'burial verifies corpse recovery before restoring the world'
Add-Result (
    (
        $burialLuaText.Contains(
            'DarkPassengerAftermath.RecordBurial(corpse.id)'
        ) -or
        $burialLuaText.Contains(
            'DarkPassengerAftermath.RecordBurial(corpseId)'
        ) -or
        $burialLuaText.Contains(
            'DarkPassengerAftermath.RecordBurial(active.corpseId)'
        )
    ) -and
    $aftermathLuaText.Contains(
        'function DarkPassengerAftermath.RecordBurial(corpseId)'
    )
) 'target burial reports into the aftermath state machine'
Add-Result (
    $aftermathLuaText -match (
        '(?s)function DarkPassengerAftermath\.RecordBurial\(corpseId\).*?' +
        'PHASE_SILENCE_CHECK.*?currentCase\.target_id.*?' +
        'DarkPassengerAftermath\.Resolve\("clean"\)'
    ) -and
    $aftermathLuaText -notmatch (
        '(?s)function DarkPassengerAftermath\.RecordBurial.*?' +
        '(MarkReported|LockNoisy|noisyLocked\s*=\s*false)'
    )
) 'target burial resolves only a still-clean silence check'
Add-Result (
    $runtimeLuaText.Contains("DarkPassengerTarget.TARGET_BUFF_GUID = `"$targetGuid`"")
) 'Lua target selector uses the hidden target buff'
Add-Result (
    $runtimeLuaText.Contains('function DarkPassengerTarget.SelectPritoky')
) 'Lua exposes Pritoky victim selection'
Add-Result (
    $runtimeLuaText.Contains('System.GetEntityByName(candidate.entityName)')
) 'Lua resolves only generated catalogue candidates'
Add-Result (
    $runtimeLuaText.Contains('candidate.gameRegion ~= gameRegion') -and
    $runtimeLuaText.Contains('candidate.settlement ~= settlement')
) 'Lua restricts candidates to selected region and settlement'
Add-Result (
    $runtimeLuaText.Contains('ent.id == g_localActor.id')
) 'Lua excludes the player from victim candidates'
Add-Result (
    $runtimeLuaText.Contains(
        'candidateEntry.entity.soul:AddBuff('
    )
) 'Lua tags the selected runtime victim'
Add-Result (
    $runtimeLuaText.Contains('local function WeightedCandidate') -and
    $runtimeLuaText.Contains('random(1, 1000000)')
) 'Lua performs weighted random selection over eligible candidates'

Add-Result (
    $runtimeLuaText.Contains(
        'Script.ReloadScript("Scripts/mods/generated/dp_candidate_catalog.lua")'
    )
) 'Lua selector loads the generated candidate catalogue'
Add-Result (
    $runtimeLuaText.Contains(
        'function DarkPassengerTarget.Select(gameRegion, settlement)'
    )
) 'Lua exposes metadata-aware region and settlement selection'
Add-Result (
    $runtimeLuaText.Contains('candidate.gameRegion ~= gameRegion') -and
    $runtimeLuaText.Contains('candidate.settlement ~= settlement')
) 'Lua filters candidates by game region and settlement'
Add-Result (
    $runtimeLuaText.Contains('candidate.killableVerified ~= true') -and
    $runtimeLuaText.Contains('candidate.storyCritical == true') -and
    $runtimeLuaText.Contains('candidate.questCritical == true') -and
    $runtimeLuaText.Contains('candidate.immortal == true')
) 'Lua rejects every catalogue safety exclusion'
Add-Result (
    $runtimeLuaText.Contains('System.GetEntityByName(candidate.entityName)') -and
    $runtimeLuaText.Contains('ent.soul == nil') -and
    $runtimeLuaText.Contains('ent.actor == nil') -and
    $runtimeLuaText.Contains('ent.actor:IsDead()')
) 'Lua resolves catalogue entities and rejects missing Soul, actor, and dead targets'
Add-Result (
    $runtimeLuaText.Contains('ent.id == g_localActor.id')
) 'Lua metadata selector rejects the player'
Add-Result (
    $runtimeLuaText.Contains('local function WeightedCandidate') -and
    $runtimeLuaText.Contains('candidate.weight')
) 'Lua performs weighted random selection'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.Select\(gameRegion, settlement\).*?' +
        'DarkPassengerTarget\.Clear\(\).*?' +
        'candidateEntry\.entity\.soul:AddBuff\('
    )
) 'Lua clears the previous target before tagging exactly one selected candidate'
Add-Result (
    $runtimeLuaText.Contains('DarkPassengerTarget.targetBuffHandle') -and
    $runtimeLuaText.Contains(
        'previous.soul:RemoveAllBuffsByGuid('
    )
) 'Lua retains the runtime handle but cleans the target tag by persistent GUID'
Add-Result (
    $runtimeLuaText -match (
        '(?s)if #eligible == 0 then.*?return false'
    )
) 'Lua returns failure without tagging when the eligible pool is empty'
Add-Result (
    $runtimeLuaText.Contains('function DarkPassengerTarget.SelectCommand(argsLine)') -and
    $runtimeLuaText.Contains(
        'System.AddCCommand("dp_target_select", "DarkPassengerTarget.SelectCommand(%line)"'
    )
) 'console bridge forwards region and settlement to the selector'
Add-Result (
    $questTemplateText.Contains('<SetEntityContext Name="selectVictimRequest"') -and
    $questTemplateText.Contains('<Constant Name="Context" Value="{{DP_REQUEST_CONTEXT}}" />') -and
    $questTemplateText.Contains('<Asset Name="Souls" Alias="player" />') -and
    $questTemplateText.Contains(
        '<Edge From="selectionRequestActive.State" To="IsActive" />'
    ) -and
    $questTemplateText.Contains(
        '<State Name="selectionRequestActive" TypeT="bool">'
    ) -and
    $questTemplateText.Contains(
        '<Edge From="wakeQuestActive.True" To="SetTrue" />'
    )
) 'active quest exposes a player script-context request for Lua selection'
Add-Result (
    -not $questTemplateText.Contains('<dp_lua_call') -and
    -not $projectText.Contains('<SmartObjectAsset Name="player_scheduler" />') -and
    $questTemplateText.Contains('<SetEntityContext Name="targetDeathRequest">') -and
    $questTemplateText.Contains(
        '<Constant Name="Context" Value="{{DP_TARGET_DEATH_CONTEXT}}" />'
    )
) 'quest death handoff avoids unresolved scheduler assets'
Add-Result (
    $runtimeLuaText.Contains('DarkPassengerQuestBridge.REQUESTS = {') -and
    $runtimeLuaText -match (
        '(?s)playerEntity\.soul:HasScriptContext\(\s*' +
        'request\.context\s*\)'
    ) -and
    $runtimeLuaText.Contains(
        'Script.SetTimerForFunction('
    ) -and
    $runtimeLuaText.Contains(
        '"DarkPassengerQuestBridge.PollSelectionRequest"'
    ) -and
    $runtimeLuaText.Contains('DarkPassengerTarget.SelectNearest(request.region)')
) 'Lua polls regional quest contexts and selects from the nearest settlement'
Add-Result (
    $runtimeLuaText.Contains('deathContext = "dp_target_dead_kutnohorsko"') -and
    $runtimeLuaText.Contains('deathContext = "dp_target_dead_trosecko"') -and
    $runtimeLuaText.Contains('request.deathContext') -and
    $runtimeLuaText.Contains('DarkPassengerTarget.OnTargetDeath(')
) 'Lua starts aftermath from the regional target-death context'
Add-Result (
    $runtimeLuaText.IndexOf('recovered tagged quest target region=') -lt
        $runtimeLuaText.IndexOf('preserved persisted quest target region=') -and
    $runtimeLuaText.Contains('candidate = FindCandidateBySlot(expectedSlot)') -and
    -not $runtimeLuaText.Contains('ignored stale target death callback')
) 'save-local target tag outranks stale global slot state'
Add-Result (
    $runtimeLuaText -match (
        '(?s)local requestBecameActive =.*?' +
        'previousState ~= true.*?' +
        'DarkPassengerTarget\.RestoreExisting\(request\.region\).*?' +
        'if not existingTargetPreserved then.*?' +
        'DarkPassengerTarget\.SelectNearest\(request\.region\)'
    )
) 'an existing quest target is restored instead of randomly replaced after load'
Add-Result (
    $runtimeLuaText.Contains(
        'DarkPassengerTarget.ACTIVE_TARGET_SLOT_KEY = "dp_active_target_slot"'
    ) -and
    $runtimeLuaText -match (
        '(?s)Variables\.SetGlobal\(\s*' +
        'DarkPassengerTarget\.ACTIVE_TARGET_SLOT_KEY'
    ) -and
    $runtimeLuaText -match (
        '(?s)Variables\.GetGlobal\(\s*' +
        'DarkPassengerTarget\.ACTIVE_TARGET_SLOT_KEY\s*\)'
    )
) 'selected victim slot persists independently of Lua runtime memory'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.Clear\(\).*?' +
        'previous\.soul:RemoveAllBuffsByGuid\(\s*' +
        'DarkPassengerTarget\.TARGET_BUFF_GUID\s*\)'
    )
) 'target cleanup removes the hidden tag by GUID after save-load handle loss'
Add-Result (
    $runtimeLuaText -match (
        '(?s)entity\.soul:HasBuffDebug\(\s*' +
        'DarkPassengerTarget\.TARGET_BUFF_GUID\s*\)'
    ) -and
    $runtimeLuaText.Contains(
        'function DarkPassengerTarget.RestoreExisting(gameRegion)'
    )
) 'loaded quest can recover the already tagged victim without changing it'
Add-Result (
    $runtimeLuaText.Contains(
        'function DarkPassengerQuestBridge.StartPolling(reason)'
    ) -and
    $runtimeLuaText.Contains(
        'PlayerEventDispatcher:Register("OnReloadEvent"'
    ) -and
    $runtimeLuaText.Contains(
        'PlayerEventDispatcher:Register("OnInitEvent"'
    ) -and
    $runtimeLuaText.Contains(
        'PlayerEventDispatcher:Register("OnActionEvent"'
    ) -and
    $runtimeLuaText.Contains(
        'function DarkPassengerQuestBridge.EnsurePollingFromPlayerAction('
    ) -and
    $runtimeLuaText.Contains(
        'DarkPassengerQuestBridge.StartPolling("first_player_action")'
    ) -and
    $runtimeLuaText.Contains('quest-context polling started reason=') -and
    $runtimeLuaText.Contains('quest-context poll alive generation=')
) 'Lua restarts and diagnoses quest-context polling after player initialization'
Add-Result (
    -not $questText.Contains('MethodName="math::random::RandomIntegerRange"') -and
    -not $questText.Contains('<Switch Name="victimByIndex"')
) 'generated quest no longer performs XML random victim selection'

Add-Result (
    $runtimeLuaText.Contains('DarkPassengerTarget.MAX_SELECTION_ATTEMPTS = 3') -and
    $runtimeLuaText.Contains(
        'while attempts < DarkPassengerTarget.MAX_SELECTION_ATTEMPTS'
    )
) 'Lua selection retries are explicitly bounded'
Add-Result (
    $runtimeLuaText.Contains(
        'function DarkPassengerTarget.Revalidate(gameRegion, settlement, slot)'
    ) -and
    $runtimeLuaText.Contains('IsLivingCandidate(currentEntity)')
) 'Lua revalidates the selected target immediately before marker state'
Add-Result (
    -not $questText.Contains('<dp_lua_call') -and
    $questText.Contains(
        '<Constant Name="Context" Value="dp_target_dead_kutnohorsko" />'
    ) -and
    $questText.Contains('Name="targetSlot001ValidationDelay"') -and
    $questText.Contains(
        '<Edge From="targetSlot001ValidationDelay.OnFinished" To="Exec" />'
    )
) 'quest uses script context for death handoff and keeps marker validation native'
Add-Result (
    -not $questText.Contains('<Constant Name="Duration" Value="0.1s" />') -and
    $questText -match (
        '(?s)<Timer Name="targetSlot001ValidationDelay">.*?' +
        '<Constant Name="Duration" Value="1s" />'
    )
) 'target validation delay uses a valid whole-second TimeSpan'
Add-Result (
    -not $questText.Contains(
        '<Function Name="grantSatisfactionOnTargetDeath"'
    ) -and
    $questText.Contains('<BuffTagTrigger Name="cleanResultTrigger">') -and
    $questText.Contains('<BuffTagTrigger Name="controlledResultTrigger">') -and
    $questText.Contains('<BuffTagTrigger Name="noisyResultTrigger">') -and
    $questText.Contains('<BuffTagTrigger Name="externalResultTrigger">') -and
    $questText.Contains('<Function Name="grantSatisfactionOnCleanResult"') -and
    $questText.Contains('<Function Name="grantSatisfactionOnControlledResult"') -and
    $questText.Contains('<Function Name="grantSatisfactionOnNoisyResult"')
) 'result tags finish cleanup and only attributed outcomes grant satisfaction'
Add-Result (
    $runtimeLuaText.Contains('local function IsVerifiedHenry(user)') -and
    $runtimeLuaText.Contains('user.id == g_localActor.id') -and
    $runtimeLuaText.Contains('if not IsVerifiedHenry(user) then')
) 'Lua reward path requires a verified Henry player event'
Add-Result (
    $runtimeLuaText.Contains('InstallVictimAwareActionHook("OnStealthKill"') -and
    $runtimeLuaText -match (
        '(?s)local function InstallVictimAwareActionHook.*?' +
        'callback\(user, slotId, self\).*?' +
        'return original\(self, user, slotId, \.\.\.\)'
    )
) 'stealth-kill hook forwards NPC self before the original death action'
Add-Result (
    -not $runtimeLuaText.Contains(
        'PlayerEventDispatcher:Register("BasicAIActionsOnStealthKill"'
    )
) 'stealth-kill attribution does not use the victim-less dispatcher event'
Add-Result (
    $runtimeLuaText -notmatch (
        '(?s)local function Report\(.*?' +
        'DarkPassengerSatisfaction\.Add\(\).*?' +
        'return result'
    )
) 'special kill hooks do not duplicate the graph-owned satisfaction reward'
Add-Result (
    -not $questText.Contains('Name="targetSlot001ReplacementDelay"') -and
    -not $questText.Contains('Name="targetSlot001DeathFallback"') -and
    $runtimeLuaText -match (
        '(?s)function DarkPassengerQuestBridge\.PollSelectionRequest.*?' +
        'DarkPassengerTarget\.RestoreExisting\(request\.region\).*?' +
        'if not existingTargetPreserved then.*?' +
        'DarkPassengerTarget\.SelectNearest\(request\.region\)'
    )
) 'Lua polling preserves or reconstructs a target without scheduler callbacks'
Add-Result (
    $questText.Contains(
        '<Edge From="targetSlot001Death.OnDeath" To="SetDone" />'
    ) -and
    $questText.Contains(
        '<Edge From="targetSlot001Death.OnDeath" To="SetActive" />'
    ) -and
    -not $questText.Contains(
        '<Edge From="targetSlot001Death.OnDeath" To="SetNone" />'
    )
) 'target death completes target objective and activates cleanup'
Add-Result (
    $questText.Contains(
        '<Edge From="targetSlot001Death.OnDeath" To="SetFalse" />'
    )
) 'target death disables the selection request before polling can replace it'
Add-Result (
    $runtimeLuaText.Contains(
        'System.AddCCommand("dp_target_validate", "DarkPassengerTarget.ValidateCommand(%line)"'
    ) -and
    $runtimeLuaText.Contains(
        'System.AddCCommand("dp_target_death", "DarkPassengerTarget.DeathCommand(%line)"'
    )
) 'console bridge exposes validation and death fallback commands'
Add-Result (
    $runtimeLuaText.Contains('function DarkPassengerTarget.QuestStatus()') -and
    $runtimeLuaText.Contains(
        'QuestSystem.IsQuestActive("dark_within_k")'
    ) -and
    $runtimeLuaText.Contains(
        'System.AddCCommand("dp_quest_status", "DarkPassengerTarget.QuestStatus()"'
    )
) 'runtime exposes a read-only active-quest API probe'
Add-Result (
    $runtimeLuaText.Contains(
        'function DarkPassengerTarget.DumpActiveObjectives()'
    ) -and
    $runtimeLuaText.Contains(
        'local questApi = QuestSystem or Quest'
    ) -and
    $runtimeLuaText.Contains(
        'questApi.GetActiveObjectives(questName)'
    ) -and
    $runtimeLuaText.Contains(
        'System.AddCCommand("dp_quest_objectives", "DarkPassengerTarget.DumpActiveObjectives()"'
    )
) 'runtime can diagnose the active objective ids of both regional quests'
Add-Result (
    ([regex]::Matches(
        $questText,
        '<Edge From="questProgress\.OnActive" To="SetNone" />'
    )).Count -ge 2 -and
    -not $questText.Contains(
        '<Edge From="questProgress.OnActive" To="SetActive" />'
    )
) 'empty candidate pool leaves search target and evidence objectives inactive'

$troskyQuestText = Read-OptionalText -LiteralPath $troskyQuestPath
$troskyTemplateText = Read-OptionalText -LiteralPath $troskyQuestTemplatePath

Add-Result (
    Test-Path -LiteralPath $troskyObjectsPath
) 'Asset Linker authoritative Trosky world source is available'
Add-Result (
    $null -ne $rawWorldCandidates -and
    @($rawWorldCandidates.candidates | Where-Object {
        $_.gameRegion -eq 'kutnohorsko'
    }).Count -eq 976 -and
    @($rawWorldCandidates.candidates | Where-Object {
        $_.gameRegion -eq 'trosecko'
    }).Count -eq 205
) 'raw extraction covers all joined settlement NPCs in both regions'
Add-Result (
    $null -ne $candidateCatalog -and
    @($candidateCatalog.settlements).Count -eq 38 -and
    @($candidateCatalog.settlements | Where-Object {
        $_.gameRegion -eq 'kutnohorsko'
    }).Count -eq 23 -and
    @($candidateCatalog.settlements | Where-Object {
        $_.gameRegion -eq 'trosecko'
    }).Count -eq 15
) 'catalogue declares every populated settlement layer in both regions'
Add-Result (
    $null -ne $candidateCatalog -and
    @($candidateCatalog.candidates | Where-Object {
        $_.enabled -eq $true -and $_.gameRegion -eq 'kutnohorsko'
    }).Count -eq 814 -and
    @($candidateCatalog.candidates | Where-Object {
        $_.enabled -eq $true -and $_.gameRegion -eq 'trosecko'
    }).Count -eq 137
) 'catalogue includes the broad generic settlement population'
Add-Result (
    $questTemplateText.Contains('{{DP_REGION_ID}}') -and
    $questTemplateText.Contains('{{DP_REQUEST_CONTEXT}}') -and
    $questTemplateText.Contains('{{DP_QUEST_NAME}}')
) 'one region-neutral quest template is the generation source of truth'
Add-Result (
    $troskyQuestText.Length -gt 0 -and
    $troskyQuestText -notmatch '\{\{DP_[A-Z_]+\}\}' -and
    $troskyQuestText.Contains('SharedSoulGuids=')
) 'Trosky quest graph is generated with static Soul aliases'

$regionalQuestTexts = @{
    kutnohorsko = $questText
    trosecko = $troskyQuestText
}
$dynamicSearchGraphComplete = $supportedInvestigationAreas.Count -eq 36
$candidateSettlementMappingsComplete = $true
$searchRevealCompletionExact = $true
$searchLocalizationKeys = [System.Collections.Generic.List[string]]::new()
foreach ($searchArea in $supportedInvestigationAreas) {
    $regionalQuestText = [string]$regionalQuestTexts[$searchArea.gameRegion]
    $stateName = [string]$searchArea.alias
    $localizationSuffix = (
        ([string]$searchArea.gameRegion + '_' + [string]$searchArea.id) -replace
            '[^A-Za-z0-9]+', '_'
    ).ToLowerInvariant()
    $localizationKey = "dark_within_search_$localizationSuffix"
    $searchLocalizationKeys.Add($localizationKey)

    if (
        -not $regionalQuestText.Contains(
            "<StateTypeEnumeration Name=`"$stateName`" ObjectiveValueType=`"Started`" />"
        ) -or
        -not $regionalQuestText.Contains(
            "<TriggerAreaAsset Name=`"$stateName`" />"
        ) -or
        $regionalQuestText -notmatch (
            "(?s)<EnumLog Type=`"Started`" Name=`"$([regex]::Escape($stateName))`" " +
            "IsTracked=`"true`" Marker=`"$([regex]::Escape($stateName))`">.*?" +
            "StringName=`"$localizationKey`""
        )
    ) {
        $dynamicSearchGraphComplete = $false
    }

    foreach ($slot in @($searchArea.candidateSlots)) {
        $slotNode = 'targetSlot{0:D3}' -f [int]$slot
        if (-not $regionalQuestText.Contains(
            "<Edge From=`"$($slotNode)Tagged.True`" To=`"Set$stateName`" />"
        )) {
            $candidateSettlementMappingsComplete = $false
        }
        if (([regex]::Matches(
            $regionalQuestText,
            "From=`"$($slotNode)Revealed\.True`" To=`"SetDone`""
        )).Count -ne 1) {
            $searchRevealCompletionExact = $false
        }
    }
}

Add-Result (
    $dynamicSearchGraphComplete -and
    $questText.Contains('<State Name="objectiveProgress" TypeT="DP_SearchProgress">') -and
    $troskyQuestText.Contains('<State Name="objectiveProgress" TypeT="DP_TroseckoSearchProgress">')
) 'both regional quests declare every supported settlement search state, asset, and log with region-safe types'
Add-Result (
    $questText.Contains('<State Name="selectedTarget" TypeT="DP_SelectedTarget">') -and
    $questText.Contains('<State Name="targetObjectiveProgress" TypeT="DP_TargetProgress">') -and
    $troskyQuestText.Contains('<State Name="selectedTarget" TypeT="DP_TroseckoSelectedTarget">') -and
    $troskyQuestText.Contains('<State Name="targetObjectiveProgress" TypeT="DP_TroseckoTargetProgress">') -and
    $troskyQuestText.Contains('<Type TypeName="DP_TroseckoSearchProgress">') -and
    $troskyQuestText.Contains('<Type TypeName="DP_TroseckoSelectedTarget">') -and
    $troskyQuestText.Contains('<Type TypeName="DP_TroseckoTargetProgress">') -and
    -not $troskyQuestText.Contains('<Type TypeName="DP_SearchProgress">') -and
    -not $troskyQuestText.Contains('<Type TypeName="DP_SelectedTarget">') -and
    -not $troskyQuestText.Contains('<Type TypeName="DP_TargetProgress">')
) 'regional candidate and marker enums cannot collide across Barbora graphs'
Add-Result (
    $candidateSettlementMappingsComplete
) 'every candidate slot activates its settlement search state'
Add-Result (
    $searchRevealCompletionExact
) 'target reveal completes the active settlement search objective exactly once'
Add-Result (
    -not $questTemplateText.Contains('{{DP_SEARCH_AREA_ASSET}}') -and
    -not $questTemplateText.Contains('{{DP_SEARCH_MARKER_ATTRIBUTE}}') -and
    -not $troskyQuestText.Contains('DP_PritokySearchArea') -and
    ([regex]::Matches(
        $questText,
        '<EnumLog Type="Started" Name="Active" IsTracked="true" Marker="DP_PritokySearchArea">'
    )).Count -eq 1 -and
    ([regex]::Matches(
        $questText,
        '<EnumLog Type="Started" Name="DP_SearchArea_Kutnohorsko_Pritoky" IsTracked="true" Marker="DP_SearchArea_Kutnohorsko_Pritoky">'
    )).Count -eq 1 -and
    ([regex]::Matches(
        $troskyQuestText,
        '<EnumLog Type="Started" Name="Active" IsTracked="true" Marker='
    )).Count -eq 0
) 'regional quests contain only the legacy Kuttenberg Active save bridge'
Add-Result (
    @($searchLocalizationKeys | Where-Object {
        -not $englishText.Contains("<Cell>$_</Cell>") -or
        -not $russianText.Contains("<Cell>$_</Cell>")
    }).Count -eq 0
) 'every generated settlement search log has English and Russian localization'
Add-Result (
    $questText -match (
        '(?s)<State Name="targetObjectiveProgress" TypeT="DP_TargetProgress">.*?' +
        '<Edge From="targetSlot\d+Revealed\.True" To="SetTarget\d+" />'
    ) -and
    $troskyQuestText -match (
        '(?s)<State Name="targetObjectiveProgress" TypeT="DP_TroseckoTargetProgress">.*?' +
        '<Edge From="targetSlot\d+Revealed\.True" To="SetTarget\d+" />'
    )
) 'both regions reveal the victim only after investigation confidence is met'
Add-Result (
    $runtimeLuaText.Contains(
        'function DarkPassengerTarget.SelectNearest(gameRegion)'
    ) -and
    $runtimeLuaText.Contains('local distanceSquared = dx * dx + dy * dy') -and
    $runtimeLuaText.Contains('DarkPassengerGeneratedSettlements')
) 'Lua chooses a nearest settlement using planar squared distance'
Add-Result (
    $questText.Contains(
        '<Constant Name="Context" Value="dp_select_victim_kutnohorsko" />'
    ) -and
    $troskyQuestText.Contains(
        '<Constant Name="Context" Value="dp_select_victim_trosecko" />'
    )
) 'regional quest graphs expose distinct victim-selection contexts'
Add-Result (
    $runtimeLuaText.Contains('dp_select_victim_kutnohorsko') -and
    $runtimeLuaText.Contains('dp_select_victim_trosecko') -and
    $runtimeLuaText.Contains(
        'DarkPassengerTarget.SelectNearest(request.region)'
    ) -and
    -not $runtimeLuaText.Contains(
        'DarkPassengerTarget.Select("kutnohorsko", "pritoky")'
    )
) 'Lua routes regional requests without a hard-coded Pritoky selection'
Add-Result (
    $runtimeLuaText.Contains(
        'function DarkPassengerTarget.ResetCase(gameRegion)'
    ) -and
    $runtimeLuaText -match (
        '(?s)if requestBecameActive then\s*' +
        'DarkPassengerTarget\.ResetCase\(request\.region\)\s*' +
        'end.*?' +
        'DarkPassengerTarget\.SelectNearest\(request\.region\)'
    )
) 'a new quest cycle discards the previous fixed settlement before reselection'
$areaInventory = $null
if (Test-Path -LiteralPath $areaInventoryPath) {
    try {
        $areaInventory =
            Get-Content -Raw -LiteralPath $areaInventoryPath |
            ConvertFrom-Json
    }
    catch {
        $areaInventory = $null
    }
}
$areaCatalogMatchesManifest =
    $null -ne $areaInventory -and
    $supportedInvestigationAreas.Count -eq 36 -and
    $investigationAreaCatalogLuaText.Contains(
        'DarkPassengerInvestigationAreaCatalog = {'
    ) -and
    $investigationAreaCatalogLuaText.Contains('schemaVersion = 1')
$selectedAreaCount = 0
if ($areaCatalogMatchesManifest) {
    foreach ($manifestRegion in @($settlementAreaManifest.regions)) {
        $gameRegion = [string]$manifestRegion.id
        foreach ($settlement in @($manifestRegion.settlements)) {
            $catalogKey = "$gameRegion/$([string]$settlement.id)"
            if (
                -not $investigationAreaCatalogLuaText.Contains(
                    "key = `"$catalogKey`""
                ) -or
                -not $investigationAreaCatalogLuaText.Contains(
                    "alias = `"$([string]$settlement.alias)`""
                )
            ) {
                $areaCatalogMatchesManifest = $false
            }
            foreach ($areaGuid in @($settlement.areaGuids)) {
                $selectedAreaCount++
                $inventoryMatches = @(
                    $areaInventory.areas |
                        Where-Object {
                            [string]$_.region -eq $gameRegion -and
                            [string]$_.guid -eq [string]$areaGuid
                        }
                )
                if (
                    $inventoryMatches.Count -ne 1 -or
                    -not $investigationAreaCatalogLuaText.Contains(
                        "name = `"$([string]$inventoryMatches[0].name)`""
                    ) -or
                    -not $investigationAreaCatalogLuaText.Contains(
                        "guid = `"$([string]$areaGuid)`""
                    )
                ) {
                    $areaCatalogMatchesManifest = $false
                }
            }
        }
    }
}
Add-Result (
    $areaCatalogMatchesManifest -and
    $selectedAreaCount -eq 71
) 'generated Lua area catalog groups all selected entities by region and settlement'
Add-Result (
    $runtimeLuaText.Contains(
        'Script.ReloadScript("Scripts/mods/generated/dp_investigation_area_catalog.lua")'
    ) -and
    -not $runtimeLuaText.Contains('DarkPassengerAreaBridge.TARGET_NAMES') -and
    -not $runtimeLuaText.Contains('DP_PritokySearchArea')
) 'runtime loads the generated area catalog without hard-coded Pritoky identities'

$areaBridgeText = ''
$areaBridgeMatch = [regex]::Match(
    $runtimeLuaText,
    '(?s)DarkPassengerAreaBridge =.*?(?=DarkPassengerQuestBridge = )'
)
if ($areaBridgeMatch.Success) {
    $areaBridgeText = $areaBridgeMatch.Value
}
Add-Result (
    $areaBridgeText.Contains(
        'function DarkPassengerAreaBridge.EnsureSettlementLinked(gameRegion, settlement)'
    ) -and
    $areaBridgeText.Contains(
        'DarkPassengerInvestigationAreaCatalog.regions[gameRegion]'
    ) -and
    $areaBridgeText.Contains('region.settlements[settlement]') -and
    $areaBridgeText.Contains(
        'System.GetEntityByName(region.levelHolderName)'
    ) -and
    $areaBridgeText.Contains(
        'System.GetEntityByName(region.questHolderName)'
    ) -and
    $areaBridgeText.Contains(
        'for _, area in ipairs(settlementEntry.areas) do'
    ) -and
    $areaBridgeText.Contains('System.GetEntityByName(area.name)') -and
    $areaBridgeText.Contains(
        'local aliases = { settlementEntry.alias }'
    ) -and
    $areaBridgeText.Contains(
        'ipairs(settlementEntry.legacyAliases or {})'
    ) -and
    $areaBridgeText.Contains(
        'local linkName = "asset[''" .. alias .. "'']"'
    ) -and
    $areaBridgeText.Contains(
        'function DarkPassengerAreaBridge.EnsureModuleLink(source, target, label)'
    ) -and
    $areaBridgeText.Contains('return source:CountLinks()') -and
    $areaBridgeText.Contains('return source:GetLink(index)') -and
    $areaBridgeText.Contains('linkName == expectedName')
) 'area bridge repairs only the requested settlement current and legacy aliases'
Add-Result (
    $areaBridgeText.Contains(
        'DarkPassengerAreaBridge.EnsureSettlementLinked(gameRegion, settlement)'
    ) -and
    $areaBridgeText.Contains('gameRegion = gameRegion') -and
    $areaBridgeText.Contains('settlement = settlement') -and
    $areaBridgeText.Contains(
        'ScheduleAreaLinkPoll(generation, attempt + 1, gameRegion, settlement)'
    ) -and
    -not $areaBridgeText.Contains('DarkPassengerTarget.Select(') -and
    -not $areaBridgeText.Contains('DarkPassengerTarget.Clear(')
) 'missing streamed areas retry without replacing the target or settlement'
Add-Result (
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.RestoreExisting\(gameRegion\).*?' +
        'BindRecoveredTarget\(.*?return true.*?' +
        'function DarkPassengerTarget\.SelectNearest\(gameRegion\).*?' +
        'if DarkPassengerTarget\.RestoreExisting\(gameRegion\) then return true end'
    ) -and
    $runtimeLuaText -match (
        '(?s)function BindRecoveredTarget\(candidate, entity\).*?' +
        'DarkPassengerAreaBridge\.StartPolling\(\s*' +
        '"target_restore",\s*candidate\.gameRegion,\s*candidate\.settlement'
    ) -and
    $runtimeLuaText -match (
        '(?s)function DarkPassengerTarget\.Select\(gameRegion, settlement\).*?' +
        'DarkPassengerAreaBridge\.StartPolling\(\s*' +
        '"target_select",\s*gameRegion,\s*settlement'
    )
) 'target restoration and selection activate only their persisted settlement area'
Add-Result (
    $runtimeLuaText.Contains(
        'DarkPassengerAreaBridge.StartPolling("script_load")'
    ) -and
    $runtimeLuaText -match (
        '(?s)OnReloadEvent.*?' +
        'DarkPassengerAreaBridge\.StartPolling\("player_reload"\).*?' +
        'DarkPassengerQuestBridge\.StartPolling\("player_reload"\)'
    ) -and
    $runtimeLuaText -match (
        '(?s)OnInitEvent.*?' +
        'DarkPassengerAreaBridge\.StartPolling\("player_init"\).*?' +
        'DarkPassengerQuestBridge\.StartPolling\("player_init"\)'
    )
) 'save and player lifecycle restore area links before any new case selection'

$luaCompilerPath =
    Join-Path $DevGameRoot 'Bin\Win64SharedPrivate\LuaCompiler.exe'
$areaBridgeLuaParses = $false
if (
    (Test-Path -LiteralPath $luaCompilerPath) -and
    (Test-Path -LiteralPath $runtimeLuaPath) -and
    (Test-Path -LiteralPath $investigationAreaCatalogLuaPath)
) {
    & $luaCompilerPath -p `
        $runtimeLuaPath `
        $investigationAreaCatalogLuaPath *> $null
    $areaBridgeLuaParses = $LASTEXITCODE -eq 0
}
Add-Result (
    $areaBridgeLuaParses
) 'runtime bridge and generated investigation area catalog pass LuaCompiler'

Add-Result (
    $buildScriptText.Contains('function Set-ReproducibleTimestamps') -and
    $buildScriptText.Contains(
        'Set-ReproducibleTimestamps -LiteralPath $resolvedBuildRoot'
    ) -and
    (
        [regex]::Matches(
            $buildScriptText,
            '& \$sevenZip a -tzip -mx=9 -mtc=off'
        )
    ).Count -eq 3
) 'all mod archives omit mutable file timestamps for reproducible packaging'

if ($sevenZip -and (Test-Path -LiteralPath $pakPath)) {
    $pakMetadata = (& $sevenZip l -slt $pakPath) -join "`n"
    Add-Result (
        -not $pakMetadata.Contains('Characteristics = NTFS')
    ) 'pak entries contain no KCD2-incompatible NTFS timestamp metadata'
    Add-Result (
        -not $pakMetadata.Contains('Levels\kutnohorsko\waitinglinks.xml') -and
        -not $pakMetadata.Contains('Levels\trosecko\waitinglinks.xml')
    ) 'main data pak does not hide waitinglinks inside the wrong archive scope'
} else {
    Add-Result $false 'pak entries contain no KCD2-incompatible NTFS timestamp metadata'
    Add-Result $false 'main data pak does not hide waitinglinks inside the wrong archive scope'
}

$regionalLevelPaksValid = $true
foreach ($bindingSpec in $areaBindingSpecs) {
    if (-not $sevenZip -or -not (Test-Path -LiteralPath $bindingSpec.levelPakPath)) {
        $regionalLevelPaksValid = $false
        continue
    }
    $levelPakMetadata =
        (& $sevenZip l -slt $bindingSpec.levelPakPath) -join "`n"
    & $sevenZip t $bindingSpec.levelPakPath *> $null
    if (
        $LASTEXITCODE -ne 0 -or
        -not $levelPakMetadata.Contains('Path = objects_mission0.xml') -or
        -not $levelPakMetadata.Contains('Path = waitinglinks.xml') -or
        $levelPakMetadata.Contains('Path = layers\') -or
        $levelPakMetadata.Contains('Path = whdata_1') -or
        $levelPakMetadata.Contains('Path = leveldata.xml') -or
        $levelPakMetadata.Contains('Path = terrain') -or
        $levelPakMetadata.Contains('Path = bai_') -or
        $levelPakMetadata.Contains('Characteristics = NTFS')
    ) {
        $regionalLevelPaksValid = $false
    }
}
Add-Result (
    $regionalLevelPaksValid
) 'both regional level paks contain only the two full resolver registries'

Add-Result ($englishText.Contains('<Cell>dp_satisfaction_name</Cell><Cell>The Silence Within</Cell>')) 'English buff name is localized'
Add-Result ($englishText.Contains('<Cell>dp_satisfaction_desc</Cell>')) 'English buff description is localized'
Add-Result (
    $russianText -match '<Cell>dp_satisfaction_name</Cell><Cell>[^<]+</Cell>'
) 'Russian buff name is localized'
Add-Result ($russianText.Contains('<Cell>dp_satisfaction_desc</Cell>')) 'Russian buff description is localized'
Add-Result (
    @(
        'dp_satisfaction_10_desc',
        'dp_satisfaction_20_desc',
        'dp_satisfaction_30_desc',
        'dp_satisfaction_40_desc',
        'dp_hunger_name',
        'dp_hunger_60_desc',
        'dp_hunger_70_desc',
        'dp_hunger_80_desc',
        'dp_hunger_90_desc',
        'dp_hunger_100_desc'
    ).Where({
        $englishText.Contains("<Cell>$_</Cell>") -and
        $russianText.Contains("<Cell>$_</Cell>")
    }).Count -eq 10
) 'every hunger tier has English and Russian lore localization'
$englishEffectLines = @(
    'Effects: Strength +2, agility +2, vitality +2, marksmanship +2, stealth +3, thievery +2, speech +2, charisma +2.',
    'Effects: Strength +1, agility +2, vitality +1, marksmanship +2, stealth +2, thievery +2, speech +2, charisma +2.',
    'Effects: Strength +1, agility +1, vitality +1, marksmanship +1, stealth +2, thievery +1, speech +1, charisma +1.',
    'Effects: Strength +1, agility +1, vitality +1, marksmanship +1, stealth +1, thievery +1, speech +1, charisma +1.',
    'Effects: Marksmanship +1, stealth +1, speech +1, charisma +1.',
    'Effects: Strength -1, marksmanship -1, stealth -1, speech -1, charisma -1.',
    'Effects: Strength -1, agility -1, vitality -1, marksmanship -1, stealth -1, thievery -1, speech -1, charisma -2.',
    'Effects: Strength -2, agility -2, vitality -1, marksmanship -2, stealth -2, thievery -2, speech -2, charisma -3.',
    'Effects: Strength -2, agility -2, vitality -2, marksmanship -3, stealth -3, thievery -3, speech -3, charisma -4.',
    'Effects: Strength -3, agility -3, vitality -3, marksmanship -4, stealth -4, thievery -3, speech -4, charisma -5.'
)
$russianEffectLines = @(
    'Эффекты: Сила +2, ловкость +2, живучесть +2, меткость +2, скрытность +3, воровство +2, красноречие +2, харизма +2.',
    'Эффекты: Сила +1, ловкость +2, живучесть +1, меткость +2, скрытность +2, воровство +2, красноречие +2, харизма +2.',
    'Эффекты: Сила +1, ловкость +1, живучесть +1, меткость +1, скрытность +2, воровство +1, красноречие +1, харизма +1.',
    'Эффекты: Сила +1, ловкость +1, живучесть +1, меткость +1, скрытность +1, воровство +1, красноречие +1, харизма +1.',
    'Эффекты: Меткость +1, скрытность +1, красноречие +1, харизма +1.',
    'Эффекты: Сила -1, меткость -1, скрытность -1, красноречие -1, харизма -1.',
    'Эффекты: Сила -1, ловкость -1, живучесть -1, меткость -1, скрытность -1, воровство -1, красноречие -1, харизма -2.',
    'Эффекты: Сила -2, ловкость -2, живучесть -1, меткость -2, скрытность -2, воровство -2, красноречие -2, харизма -3.',
    'Эффекты: Сила -2, ловкость -2, живучесть -2, меткость -3, скрытность -3, воровство -3, красноречие -3, харизма -4.',
    'Эффекты: Сила -3, ловкость -3, живучесть -3, меткость -4, скрытность -4, воровство -3, красноречие -4, харизма -5.'
)
Add-Result (
    @($englishEffectLines | Where-Object {
        -not $englishText.Contains("&lt;/p&gt;&lt;p&gt;$_&lt;/p&gt;")
    }).Count -eq 0 -and
    @($russianEffectLines | Where-Object {
        -not $russianText.Contains("&lt;/p&gt;&lt;p&gt;$_&lt;/p&gt;")
    }).Count -eq 0
) 'every tier renders lore and mechanical effects as separate rich-text paragraphs'
Add-Result (
    $russianText.Contains('Я научился держать эту тьму в узде.')
) 'Russian quest description uses approved lore'
Add-Result (
    $russianText.Contains(
        '<Cell>dark_within_obj_name</Cell><Cell>Найти того, кто заслуживает приговора</Cell>'
    )
) 'Russian search-area objective uses settlement-neutral lore'
Add-Result (
    $russianText.Contains(
        '<Cell>dark_within_obj</Cell><Cell>Пассажир не даёт мне покоя. Прежде чем вершить приговор, нужно найти того, чья вина не оставляет сомнений.</Cell>'
    )
) 'Russian search-area log keeps confidence hidden'
Add-Result (
    $russianText.Contains('<Cell>dark_within_target_name</Cell><Cell>Настигнуть избранную жертву</Cell>')
) 'Russian target objective title is localized'
Add-Result (
    $englishText.Contains('<Cell>dark_within_target_name</Cell><Cell>Hunt down the chosen victim</Cell>')
) 'English target objective title is localized'
Add-Result (
    $englishText.Contains(
        '<Cell>dark_within_target</Cell><Cell>Every whisper and trace now points to one person. The Passenger has chosen; all that remains is to carry out the sentence.</Cell>'
    ) -and
    $russianText.Contains(
        '<Cell>dark_within_target</Cell><Cell>Все слухи и следы теперь ведут к одному человеку. Пассажир сделал свой выбор; осталось привести приговор в исполнение.</Cell>'
    )
) 'reveal update is localized in English and Russian'
$investigationLocalizationKeys = @(
    'dark_within_obj_name',
    'dark_within_obj',
    'dark_within_target_name',
    'dark_within_target'
)
Add-Result (
    @($investigationLocalizationKeys | Where-Object {
        -not $englishText.Contains("<Cell>$_</Cell>") -or
        -not $russianText.Contains("<Cell>$_</Cell>") -or
        $englishText.Contains("@$_") -or
        $russianText.Contains("@$_")
    }).Count -eq 0
) 'investigation copy has matching RU EN keys without raw key output'
Add-Result (
    $englishText.Contains('<Cell>dark_within_target_done</Cell>') -and
    $russianText.Contains('<Cell>dark_within_target_done</Cell>') -and
    $questTemplateText -match (
        '(?s)<EnumLog Type="Completed" Name="Done">.*?' +
        'StringName="dark_within_target_done".*?</EnumLog>'
    )
) 'completed target objective remains in the journal as case history'
foreach ($localizationText in @($englishText, $russianText)) {
    foreach ($cleanupKey in @(
        'dark_within_cleanup_name',
        'dark_within_cleanup',
        'dark_within_cleanup_witnessed',
        'dark_within_cleanup_clean',
        'dark_within_cleanup_controlled',
        'dark_within_cleanup_noisy',
        'dark_within_cleanup_external'
    )) {
        Add-Result (
            $localizationText.Contains("<Cell>$cleanupKey</Cell>")
        ) "cleanup localization contains $cleanupKey"
    }
}
Add-Result (
    $questTemplateText.Contains('<State Name="cleanupProgress" TypeT="DP_CleanupProgress">') -and
    $questTemplateText.Contains('<StateTypeEnumeration Name="Witnessed" ObjectiveValueType="Started" />') -and
    $questTemplateText.Contains('<StateTypeEnumeration Name="Clean" ObjectiveValueType="Completed" />') -and
    $questTemplateText.Contains('<StateTypeEnumeration Name="Controlled" ObjectiveValueType="Completed" />') -and
    $questTemplateText.Contains('<StateTypeEnumeration Name="Noisy" ObjectiveValueType="Completed" />') -and
    $questTemplateText.Contains('<StateTypeEnumeration Name="External" ObjectiveValueType="Completed" />')
) 'cleanup objective keeps a distinct completed state for every outcome'
Add-Result (
    $englishText.Contains(
        '<Cell>dark_within_cleanup_witnessed</Cell><Cell>Someone saw too much.</Cell>'
    ) -and
    $russianText.Contains(
        '<Cell>dark_within_cleanup_witnessed</Cell><Cell>Кто-то видел слишком много.</Cell>'
    )
) 'anonymous witness update is localized in English and Russian'
foreach ($key in @(
    'dp_burial_action',
    'dp_burial_no_shovel',
    'dp_burial_bad_ground',
    'dp_burial_quest_item',
    'dp_burial_busy',
    'dp_burial_in_combat',
    'dp_burial_skiptime'
)) {
    Add-Result (
        $englishText.Contains("<Cell>$key</Cell>") -and
        $russianText.Contains("<Cell>$key</Cell>")
    ) "burial localization contains $key in English and Russian"
}
Add-Result (
    $questTemplateText.Contains('<Edge From="cleanResultTrigger.OnAdded" To="SetClean" />') -and
    $questTemplateText.Contains('<Edge From="controlledResultTrigger.OnAdded" To="SetControlled" />') -and
    $questTemplateText.Contains('<Edge From="noisyResultTrigger.OnAdded" To="SetNoisy" />') -and
    $questTemplateText.Contains('<Edge From="externalResultTrigger.OnAdded" To="SetExternal" />')
) 'result tags select their matching cleanup epilogues'
Add-Result (
    $questTemplateText.Contains('StringName="dark_within_cleanup_clean"') -and
    $questTemplateText.Contains('StringName="dark_within_cleanup_controlled"') -and
    $questTemplateText.Contains('StringName="dark_within_cleanup_noisy"') -and
    $questTemplateText.Contains('StringName="dark_within_cleanup_external"')
) 'generated quest references all cleanup epilogue localization keys'
Add-Result (
    $englishText.Contains('I have learned to keep this darkness on a leash.')
) 'English quest description matches approved tone'
Add-Result (
    $englishText.Contains(
        '<Cell>dark_within_obj_name</Cell><Cell>Find someone who deserves the sentence</Cell>'
    ) -and
    $englishText.Contains(
        '<Cell>dark_within_obj</Cell><Cell>The Passenger is restless. Before I pass sentence, I must find someone whose guilt leaves no room for doubt.</Cell>'
    )
) 'English search-area copy matches approved tone'
Add-Result (
    $questText.Contains('I have learned to keep this darkness on a leash.')
) 'quest fallback description matches approved lore'
Add-Result (
    $questText.Contains('Find someone who deserves the sentence') -and
    $questText.Contains(
        'Every whisper and trace now points to one person.'
    )
) 'quest fallback investigation copy matches approved lore'

$textFiles = @(
    Get-ChildItem -LiteralPath $stageRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.xml', '.lua') }
    Get-ChildItem -LiteralPath "$testRoot\localization" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.xml' }
)

foreach ($file in $textFiles) {
    Add-Result (Has-NoUtf8Bom -LiteralPath $file.FullName) "no UTF-8 BOM: $($file.FullName)"
}

foreach ($message in $passes) {
    Write-Host "PASS: $message" -ForegroundColor Green
}

foreach ($message in $failures) {
    Write-Host "FAIL: $message" -ForegroundColor Red
}

if ($failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($failures.Count) failed checks)" -ForegroundColor Red
    exit 1
}

Write-Host "RESULT: PASS ($($passes.Count) checks)" -ForegroundColor Green
