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
$buffPath = "$stageRoot\Data\Libs\Tables\rpg\buff__darkpassengertest.xml"
$scriptContextPath = "$stageRoot\Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml"
$questPath = "$stageRoot\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml"
$troskyQuestPath = "$stageRoot\Data\Quests\darkpassengertest\trosecko\dark_within_t.xml"
$levelPath = "$stageRoot\Data\Quests\darkpassengertest\kutnohorsko.xml"
$troskyLevelPath = "$stageRoot\Data\Quests\darkpassengertest\trosecko.xml"
$projectPath = "$stageRoot\Data\Quests\darkpassengertest.xml"
$luaPath = "$stageRoot\Data\Scripts\mods\dpsatisfaction.lua"
$hungerLuaPath = "$stageRoot\Data\Scripts\mods\dphunger.lua"
$aftermathLuaPath = "$stageRoot\Data\Scripts\mods\dpaftermath.lua"
$runtimeLuaPath = "$stageRoot\Data\Scripts\mods\darkpassengertest.lua"
$pakPath = "$stageRoot\Data\darkpassengertest.pak"
$kuttenbergLevelPakPath = "$stageRoot\Data\Levels\kutnohorsko\darkpassengertest.pak"
$candidateCatalogPath = "$testRoot\config\victim-candidates.json"
$generatorPath = "$testRoot\tools\Generate-VictimArtifacts.ps1"
$questTemplatePath = "$stageRoot\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template"
$troskyQuestTemplatePath = "$stageRoot\Data\Quests\darkpassengertest\trosecko\dark_within_t.xml.template"
$questBridgeModulePath = "$stageRoot\Data\Quests\darkpassengertest\kutnohorsko\dp_lua_call.xml"
$schedulerBridgePath = "$stageRoot\Data\AI\player\scheduler\darkPassengerExecuteLua.xml"
$generatedCatalogLuaPath = "$stageRoot\Data\Scripts\mods\generated\dp_candidate_catalog.lua"
$kuttenbergWaitingLinksPath = "$stageRoot\Data\Levels\kutnohorsko\waitinglinks.xml"
$assetLinkerRoot = $ReferenceDataRoot
$kuttenbergBaseWaitingLinksPath = "$assetLinkerRoot\kutnohorsko\kut_waitinglinks.xml"
$kuttenbergObjectsPath = "$assetLinkerRoot\kutnohorsko\kut_objects_mission0.xml"
$troskyObjectsPath = "$assetLinkerRoot\trosecko\tros_objects_mission0.xml"
$soulTablePath = Join-Path $DevGameRoot 'Data\libs\CryHttp\xzar2\table-souls.json'
$worldExporterPath = "$testRoot\tools\Export-WorldVictimCandidates.ps1"
$catalogBuilderPath = "$testRoot\tools\Build-VictimCatalog.ps1"
$victimPolicyPath = "$testRoot\config\victim-policy.json"
$rawWorldCandidatesPath = "$testRoot\evidence\world-candidates.raw.json"
$englishPath = "$testRoot\localization\English\text__darkpassengertest.xml"
$russianPath = "$testRoot\localization\Russian\text__darkpassengertest.xml"

$expectedGuid = '16de3823-48bf-4f86-8498-ce45819a48f0'
$expectedTag = '23'
$satisfactionGateGuid = 'b5c59e05-cc10-4bf8-b82e-d82b913c841f'
$targetGuid = 'a6046bb4-57c1-4a95-b743-880aba11f5ba'
$targetTag = '24'
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
$buffText = Read-OptionalText -LiteralPath $buffPath
$scriptContextText = Read-OptionalText -LiteralPath $scriptContextPath
$questText = Read-OptionalText -LiteralPath $questPath
$questTemplateText = Read-OptionalText -LiteralPath $questTemplatePath
$questBridgeModuleText = Read-OptionalText -LiteralPath $questBridgeModulePath
$schedulerBridgeText = Read-OptionalText -LiteralPath $schedulerBridgePath
$generatedCatalogLuaText = Read-OptionalText -LiteralPath $generatedCatalogLuaPath
$kuttenbergWaitingLinksText = Read-OptionalText -LiteralPath $kuttenbergWaitingLinksPath
$levelText = Read-OptionalText -LiteralPath $levelPath
$troskyLevelText = Read-OptionalText -LiteralPath $troskyLevelPath
$projectText = Read-OptionalText -LiteralPath $projectPath
$luaText = Read-OptionalText -LiteralPath $luaPath
$hungerLuaText = Read-OptionalText -LiteralPath $hungerLuaPath
$aftermathLuaText = Read-OptionalText -LiteralPath $aftermathLuaPath
$runtimeLuaText = Read-OptionalText -LiteralPath $runtimeLuaPath
$englishText = Read-OptionalText -LiteralPath $englishPath
$russianText = Read-OptionalText -LiteralPath $russianPath
$manifestText = Read-OptionalText -LiteralPath $manifestPath

Add-Result (
    (Test-Path -LiteralPath $manifestPath) -and
    $manifestText.Contains('<modifies_level>true</modifies_level>')
) 'mod manifest enables level and AI scheduler modifications'

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
        '{{DP_TARGET_STATE_EDGES}}',
        '{{DP_TARGET_SELECTION_STOP_EDGES}}',
        '{{DP_TARGET_DETECTION_NODES}}',
        '{{DP_TARGET_DEATH_NODES}}',
        '{{DP_TARGET_DEATH_REWARD_EDGES}}',
        '{{DP_TARGET_ASSETS}}',
        '{{DP_TARGET_LOGS}}'
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
            $questText.Contains("<MakeArray Name=`"$($slotNode)Souls`"") -and
            $questText.Contains("<Function Name=`"$($slotNode)TagCheck`"") -and
            $questText.Contains("<If Name=`"$($slotNode)Tagged`"") -and
            $questText.Contains(
                "<Edge From=`"$($slotNode)Tagged.True`" To=`"Set$slotName`" />"
            )
        ) "generated quest has tag-check branch for $slotName"

        Add-Result (
            $questText -match (
                "(?s)<SoulDeathTrigger Name=`"$($slotNode)Death`">.*?" +
                "<Asset Name=`"Souls`" Alias=`"$escapedAlias`" />.*?" +
                "<Edge From=`"targetObjectiveProgress\.$slotName`" To=`"IsActive`" />"
            )
        ) "generated quest has death branch for $slotName"
    }
}

Add-Result (
    -not (Test-Path -LiteralPath $kuttenbergWaitingLinksPath)
) 'quest marker generation has no Asset Linker waitinglinks dependency'

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
    $assetAliases = @(
        $questXml.SelectNodes('//SoulAsset') |
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
    $allMarkerAliasesExist = (
        $markerAliases.Count -eq $enabledKuttenbergCandidateCount -and
        @($markerAliases | Where-Object { $_ -notin $assetAliases }).Count -eq 0
    )
}
Add-Result ($allMarkerAliasesExist) 'every generated marker references an existing Soul alias'

Add-Result (Test-Path -LiteralPath $tagPath) 'custom buff AI tag table exists'
Add-Result ($tagText.Contains('buff_ai_tag_id="23"')) 'custom AI tag uses id 23'
Add-Result ($tagText.Contains('buff_ai_tag_name="darkpassenger_satisfaction"')) 'custom AI tag has expected name'
Add-Result ($tagText.Contains("buff_ai_tag_id=`"$targetTag`"")) 'target AI tag uses id 24'
Add-Result ($tagText.Contains('buff_ai_tag_name="darkpassenger_target"')) 'target AI tag has expected name'

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
    )
) 'both regional victim-selection contexts are registered'

Add-Result ($levelText.Contains('<Edge From="OnWake" To="arm"')) 'Kuttenberg level arms quest watcher'
Add-Result ($troskyLevelText.Contains('<Edge From="OnWake" To="arm"')) 'Trosky level arms quest watcher'
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
    $questText.Contains('<Edge From="targetTagTrigger.OnAdded" To="SetTrue"')
) 'chosen runtime victim marks target resolution'
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
    $questText.Contains('<Edge From="targetTagTrigger.OnAdded" To="SetDone"') -and
    $questText.Contains('To="SetTarget001"') -and
    $questText.Contains('To="SetTarget002"') -and
    $questText.Contains('To="SetTarget003"')
) 'search objective hands off to one generated target state'
Add-Result (
    $questText.Contains('<Edge From="targetSlot001Death.OnDeath" To="SetDone"') -and
    $questText.Contains('<Edge From="targetSlot002Death.OnDeath" To="SetDone"') -and
    $questText.Contains('<Edge From="targetSlot003Death.OnDeath" To="SetDone"')
) 'selected victim death completes the generated hunt objective'
Add-Result (
    $questText.Contains('<Function Name="grantSatisfactionOnTargetDeath"') -and
    $questText.Contains("<Constant Name=`"Buff`" Value=`"$satisfactionGateGuid`"")
) 'selected victim death grants satisfaction from the quest graph'

Add-Result (Test-Path -LiteralPath $luaPath) 'satisfaction Lua bridge exists'
Add-Result ($luaText.Contains($satisfactionGateGuid)) 'Lua bridge uses hidden satisfaction gate GUID'
Add-Result ($luaText.Contains('dp_satisfaction_add')) 'Lua bridge registers add command'
Add-Result ($luaText.Contains('dp_satisfaction_remove')) 'Lua bridge registers remove command'
Add-Result ($luaText.Contains('dp_satisfaction_status')) 'Lua bridge registers status command'
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
        '(?s)function DarkPassengerHunger\.ResetAfterHunt\(\).*?' +
        'DarkPassengerHunger\.ResetNow\(\).*?' +
        'DarkPassengerHunger\.satisfactionGateExpected = true.*?' +
        'DarkPassengerHunger\.currentTier = nil.*?' +
        'DarkPassengerHunger\.Evaluate\(\)'
    )
) 'resolved hunt directly resets persistent hunger without probing the gate buff'
Add-Result (
    $runtimeLuaText -match (
        '(?s)requestBecameInactive.*?' +
        'DarkPassengerTarget\.targetCandidate ~= nil.*?' +
        'DarkPassengerHunger\.ResetAfterHunt\(\).*?' +
        'DarkPassengerTarget\.ResetCase\(request\.region\)'
    )
) 'quest request falling edge resets hunger before target cleanup'
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
Add-Result ($runtimeLuaText.Contains('result == "RESOLVED_CORRECT"')) 'correct case resolution is explicitly gated'
Add-Result ($runtimeLuaText.Contains('previousState ~= "RESOLVED_CORRECT"')) 'already resolved cases cannot grant satisfaction twice'
Add-Result (
    $questText.Contains('<Function Name="grantSatisfactionOnTargetDeath"')
) 'target death grants satisfaction independently of kill attribution'
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
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_begin"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_suspicion"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_witness_removed"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_exit"') -and
    $runtimeLuaText.Contains('System.AddCCommand("dp_aftermath_status"')
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
    $runtimeLuaText -match (
        '(?s)OnReloadEvent.*?DarkPassengerAftermath\.Restore' +
        '.*?OnInitEvent.*?DarkPassengerAftermath\.Restore'
    )
) 'player load lifecycle restores aftermath state'
Add-Result (
    $aftermathLuaText.Contains('dp_aftermath_attention_v1_') -and
    $aftermathLuaText.Contains('dp_aftermath_blood_trail_v1_') -and
    $aftermathLuaText.Contains(
        'function DarkPassengerAftermath.AdjustSettlementMetrics'
    )
) 'aftermath persists versioned settlement attention and blood trail'
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
    -not $levelText.Contains('<Definition File="kutnohorsko/dp_lua_call.xml" />') -and
    -not $questTemplateText.Contains('<dp_lua_call Name="selectVictimPolicy"') -and
    -not $projectText.Contains('<SmartObjectAsset Name="player_scheduler" />')
) 'standalone quest no longer depends on the Barbora player scheduler asset'
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
    $questText.Contains('Name="targetSlot001ValidationDelay"') -and
    $questText.Contains(
        '<Edge From="targetSlot001ValidationDelay.OnFinished" To="Exec" />'
    )
) 'quest delays marker-state checks and verifies the hidden target tag directly'
Add-Result (
    -not $questText.Contains('<Constant Name="Duration" Value="0.1s" />') -and
    $questText -match (
        '(?s)<Timer Name="targetSlot001ValidationDelay">.*?' +
        '<Constant Name="Duration" Value="1s" />'
    )
) 'target validation delay uses a valid whole-second TimeSpan'
Add-Result (
    $questText.Contains(
        '<Function Name="grantSatisfactionOnTargetDeath" MethodName="wh::rpgmodule::AddBuff" DeclaringType="wh::rpgmodule">'
    ) -and
    $questText.Contains(
        "<Constant Name=`"Buff`" Value=`"$satisfactionGateGuid`" />"
    ) -and
    $questText.Contains(
        '<Edge From="targetSlot001Death.OnDeath" To="Exec" />'
    )
) 'selected target death grants satisfaction through the native quest graph'
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
    -not $questText.Contains(
        '<Edge From="targetSlot001Death.OnDeath" To="SetActive" />'
    ) -and
    -not $questText.Contains(
        '<Edge From="targetSlot001Death.OnDeath" To="SetNone" />'
    )
) 'target death completes the active target objective without reopening search'
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
    $questText.Contains('<Edge From="questProgress.OnActive" To="SetNone" />') -and
    $questText.Contains('<Edge From="questProgress.OnActive" To="SetActive" />')
) 'empty candidate pool leaves search active and target objective inactive'

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
    }).Count -eq 819 -and
    @($candidateCatalog.candidates | Where-Object {
        $_.enabled -eq $true -and $_.gameRegion -eq 'trosecko'
    }).Count -eq 140
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

$sevenZip = (Get-Command 7z.exe -ErrorAction SilentlyContinue).Source
if ($sevenZip -and (Test-Path -LiteralPath $pakPath)) {
    $pakMetadata = (& $sevenZip l -slt $pakPath) -join "`n"
    Add-Result (
        -not $pakMetadata.Contains('Characteristics = NTFS')
    ) 'pak entries contain no KCD2-incompatible NTFS timestamp metadata'
    Add-Result (
        -not $pakMetadata.Contains('Levels\kutnohorsko\waitinglinks.xml')
    ) 'main data pak does not hide waitinglinks inside the wrong archive scope'
} else {
    Add-Result $false 'pak entries contain no KCD2-incompatible NTFS timestamp metadata'
    Add-Result $false 'main data pak does not hide waitinglinks inside the wrong archive scope'
}

Add-Result (
    -not (Test-Path -LiteralPath $kuttenbergLevelPakPath)
) 'quest marker packaging has no Asset Linker level pak dependency'

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
    $russianText.Contains('Найти того, кто заслуживает смерти')
) 'Russian objective title uses approved lore'
Add-Result (
    $russianText.Contains('Мне нужна жертва — виновный')
) 'Russian active objective log uses approved lore'
Add-Result (
    $russianText.Contains('<Cell>dark_within_target_name</Cell><Cell>Настигнуть избранную жертву</Cell>')
) 'Russian target objective title is localized'
Add-Result (
    $englishText.Contains('<Cell>dark_within_target_name</Cell><Cell>Hunt down the chosen victim</Cell>')
) 'English target objective title is localized'
Add-Result (
    $englishText.Contains('I have learned to keep this darkness on a leash.')
) 'English quest description matches approved tone'
Add-Result (
    $englishText.Contains('Find someone who deserves to die')
) 'English objective title matches approved tone'
Add-Result (
    $questText.Contains('I have learned to keep this darkness on a leash.')
) 'quest fallback description matches approved lore'
Add-Result (
    $questText.Contains('Find someone who deserves to die')
) 'quest fallback objective title matches approved lore'

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
