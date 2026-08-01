param(
    [string]$CatalogPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\victim-candidates.json'),
    [string]$AreaManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\settlement-investigation-areas.json'),
    [string]$TemplatePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'),
    [string]$EnglishLocalizationPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'localization\English\text__darkpassengertest.xml'),
    [string]$RussianLocalizationPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'localization\Russian\text__darkpassengertest.xml'),
    [string]$KuttenbergQuestOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mod\Data\Quests\Final\Barbora\kutnohorsko\dark_within_k.xml'),
    [string]$TroskyQuestOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mod\Data\Quests\Final\Barbora\trosecko\dark_within_t.xml'),
    [string]$LuaOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mod\Data\Scripts\mods\generated\dp_candidate_catalog.lua'),
    [int]$MaxCandidatesPerRegion = 1000,
    [int]$MaxQuestBytesPerRegion = 12582912
)

$ErrorActionPreference = 'Stop'

function Assert-UniqueCandidateField {
    param([object[]]$Candidates, [string]$Field)

    $values = @($Candidates | ForEach-Object { $_.$Field })
    if (@($values | Where-Object { $null -eq $_ -or "$_".Length -eq 0 }).Count -gt 0) {
        throw "Candidate field '$Field' must be present and non-empty."
    }
    $duplicate = $values | Group-Object | Where-Object { $_.Count -gt 1 } |
        Select-Object -First 1
    if ($null -ne $duplicate) {
        throw "Candidate field '$Field' contains duplicate value '$($duplicate.Name)'."
    }
}

function ConvertTo-LuaString {
    param([string]$Value)

    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function ConvertTo-LuaBoolean {
    param([bool]$Value)

    if ($Value) { return 'true' }
    return 'false'
}

function ConvertTo-XmlText {
    param([string]$Value)

    return [System.Security.SecurityElement]::Escape($Value)
}

function Get-SearchLocalizationKey {
    param([string]$RegionId, [string]$SettlementId)

    $suffix = (($RegionId + '_' + $SettlementId) -replace '[^A-Za-z0-9]+', '_').ToLowerInvariant()
    return "dark_within_search_$suffix"
}

function Get-LocalizationKeys {
    param([string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        throw "Localization table not found: $LiteralPath"
    }
    [xml]$localization = Get-Content -Raw -LiteralPath $LiteralPath
    $keys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($row in @($localization.Table.Row)) {
        if (@($row.Cell).Count -gt 0) {
            [void]$keys.Add([string]$row.Cell[0])
        }
    }
    return ,$keys
}

function Write-Utf8NoBom {
    param([string]$LiteralPath, [string]$Content)

    $directory = Split-Path -Parent $LiteralPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $LiteralPath,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function New-RegionalQuest {
    param(
        [object[]]$Candidates,
        [object[]]$SearchAreas,
        [string]$RegionId,
        [string]$QuestName,
        [string]$SearchObjectiveName,
        [string]$TargetObjectiveName,
        [string]$CleanupObjectiveName,
        [string]$QuestDescriptionKey,
        [string]$RequestContext,
        [string]$TargetDeathContext,
        [string]$OutputPath,
        [string]$Template
    )

    if ($Candidates.Count -gt $MaxCandidatesPerRegion) {
        throw "Region '$RegionId' has $($Candidates.Count) candidates; limit is $MaxCandidatesPerRegion."
    }
    if ($SearchAreas.Count -eq 0) {
        throw "Region '$RegionId' has no generated settlement search areas."
    }

    $searchTypeEnumerations = [System.Collections.Generic.List[string]]::new()
    $searchStateEdges = [System.Collections.Generic.List[string]]::new()
    $searchAreaAssets = [System.Collections.Generic.List[string]]::new()
    $searchLogs = [System.Collections.Generic.List[string]]::new()
    $selectedTypeEnumerations = [System.Collections.Generic.List[string]]::new()
    $targetTypeEnumerations = [System.Collections.Generic.List[string]]::new()
    $selectedStateEdges = [System.Collections.Generic.List[string]]::new()
    $targetStateEdges = [System.Collections.Generic.List[string]]::new()
    $searchRevealEdges = [System.Collections.Generic.List[string]]::new()
    $selectionStopEdges = [System.Collections.Generic.List[string]]::new()
    $cleanupEdges = [System.Collections.Generic.List[string]]::new()
    $targetDeathContextEdges = [System.Collections.Generic.List[string]]::new()
    $detectionNodes = [System.Collections.Generic.List[string]]::new()
    $deathNodes = [System.Collections.Generic.List[string]]::new()
    $assets = [System.Collections.Generic.List[string]]::new()
    $logs = [System.Collections.Generic.List[string]]::new()
    $presentationSignal = 'Revealed'

    $candidateSlots = @($Candidates | ForEach-Object { [int]$_.slot })
    $mappedSlots = @(
        $SearchAreas |
            ForEach-Object { $_.candidateSlots } |
            ForEach-Object { [int]$_ }
    )
    $duplicateMappedSlot = $mappedSlots |
        Group-Object |
        Where-Object Count -gt 1 |
        Select-Object -First 1
    if ($null -ne $duplicateMappedSlot) {
        throw "Region '$RegionId' maps candidate slot '$($duplicateMappedSlot.Name)' to multiple search areas."
    }
    $missingMappedSlots = @($candidateSlots | Where-Object { $_ -notin $mappedSlots })
    $unknownMappedSlots = @($mappedSlots | Where-Object { $_ -notin $candidateSlots })
    if ($missingMappedSlots.Count -gt 0 -or $unknownMappedSlots.Count -gt 0) {
        throw "Region '$RegionId' search-area candidate slots do not match the enabled candidate pool."
    }

    foreach ($searchArea in $SearchAreas) {
        $stateName = [string]$searchArea.alias
        if ($stateName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Search-area alias '$stateName' is not a valid Skald identifier."
        }
        $englishDisplayName = [string]$searchArea.displayName.english
        $russianDisplayName = [string]$searchArea.displayName.russian
        if (
            [string]::IsNullOrWhiteSpace($englishDisplayName) -or
            [string]::IsNullOrWhiteSpace($russianDisplayName)
        ) {
            throw "Search area '$RegionId/$($searchArea.id)' requires bilingual display names."
        }
        $localizationKey = Get-SearchLocalizationKey `
            -RegionId $RegionId `
            -SettlementId ([string]$searchArea.id)
        $fallbackText = ConvertTo-XmlText (
            "The trail leads to $englishDisplayName. Somewhere within this ground is someone whose guilt may deserve a sentence. I must listen, watch, and be certain."
        )

        $searchTypeEnumerations.Add(
            "          <StateTypeEnumeration Name=`"$stateName`" ObjectiveValueType=`"Started`" />"
        )
        $searchAreaAssets.Add(
            "        <TriggerAreaAsset Name=`"$stateName`" />"
        )
        $searchLogs.Add(
            "            <EnumLog Type=`"Started`" Name=`"$stateName`" IsTracked=`"true`" Marker=`"$stateName`">"
        )
        $searchLogs.Add(
            "              <Log StringName=`"$localizationKey`" Text=`"$fallbackText`">"
        )
        $searchLogs.Add(
            "                <Localization Text=`"$fallbackText`" Language=`"WHS`" />"
        )
        $searchLogs.Add('              </Log>')
        $searchLogs.Add('            </EnumLog>')

        foreach ($slot in @($searchArea.candidateSlots)) {
            $slotNode = 'targetSlot{0:D3}' -f [int]$slot
            $searchStateEdges.Add(
                "          <Edge From=`"$($slotNode)Tagged.True`" To=`"Set$stateName`" />"
            )
        }
    }

    foreach ($candidate in $Candidates) {
        $slotNumber = [int]$candidate.slot
        $slotName = 'Target{0:D3}' -f $slotNumber
        $slotNode = 'targetSlot{0:D3}' -f $slotNumber

        $selectedTypeEnumerations.Add(
            "        <StateTypeEnumeration Name=`"$slotName`" ObjectiveValueType=`"Started`" />"
        )
        $targetTypeEnumerations.Add(
            "        <StateTypeEnumeration Name=`"$slotName`" ObjectiveValueType=`"Started`" />"
        )
        $selectedStateEdges.Add(
            "          <Edge From=`"$($slotNode)Tagged.True`" To=`"Set$slotName`" />"
        )
        $targetStateEdges.Add(
            "          <Edge From=`"$slotNode$presentationSignal.True`" To=`"Set$slotName`" />"
        )
        $searchRevealEdges.Add(
            "          <Edge From=`"$slotNode$presentationSignal.True`" To=`"SetDone`" />"
        )
        $targetStateEdges.Add(
            "          <Edge From=`"$($slotNode)Death.OnDeath`" To=`"SetDone`" />"
        )
        $selectionStopEdges.Add("          <Edge From=`"$($slotNode)Death.OnDeath`" To=`"SetFalse`" />")
        $cleanupEdges.Add("          <Edge From=`"$($slotNode)Death.OnDeath`" To=`"SetActive`" />")
        $targetDeathContextEdges.Add("          <Edge From=`"$($slotNode)Death.OnDeath`" To=`"SetTrue`" />")

        $detectionNodes.Add("        <MakeArray Name=`"$($slotNode)Souls`" TypeT=`"wh::rpgmodule::Souls`">")
        $detectionNodes.Add("          <Asset Name=`"A`" Alias=`"$($candidate.alias)`" />")
        $detectionNodes.Add('        </MakeArray>')
        $detectionNodes.Add("        <Function Name=`"$($slotNode)TagCheck`" MethodName=`"wh::rpgmodule::BuffTagCheck`" DeclaringType=`"wh::rpgmodule`">")
        $detectionNodes.Add('          <Constant Name="BuffTag" Value="24" />')
        $detectionNodes.Add("          <Edge From=`"$($slotNode)Souls.Array`" To=`"Souls`" />")
        $detectionNodes.Add('        </Function>')
        $detectionNodes.Add("        <Timer Name=`"$($slotNode)ValidationDelay`">")
        $detectionNodes.Add('          <Constant Name="Duration" Value="1s" />')
        $detectionNodes.Add('          <Constant Name="TimeType" Value="GameTime" />')
        $detectionNodes.Add('          <Edge From="targetTagTrigger.OnAdded" To="SetRunning" />')
        $detectionNodes.Add('        </Timer>')
        $detectionNodes.Add("        <If Name=`"$($slotNode)Tagged`">")
        $detectionNodes.Add("          <Edge From=`"$($slotNode)TagCheck.HaveBuffTag`" To=`"Condition`" />")
        $detectionNodes.Add("          <Edge From=`"$($slotNode)ValidationDelay.OnFinished`" To=`"Exec`" />")
        $detectionNodes.Add('        </If>')
        $detectionNodes.Add("        <Function Name=`"$($slotNode)RevealCheck`" MethodName=`"wh::rpgmodule::BuffTagCheck`" DeclaringType=`"wh::rpgmodule`">")
        $detectionNodes.Add('          <Constant Name="BuffTag" Value="30" />')
        $detectionNodes.Add("          <Edge From=`"$($slotNode)Souls.Array`" To=`"Souls`" />")
        $detectionNodes.Add('        </Function>')
        $detectionNodes.Add("        <Timer Name=`"$($slotNode)RevealDelay`">")
        $detectionNodes.Add('          <Constant Name="Duration" Value="1s" />')
        $detectionNodes.Add('          <Constant Name="TimeType" Value="GameTime" />')
        $detectionNodes.Add('          <Edge From="revealTagTrigger.OnAdded" To="SetRunning" />')
        $detectionNodes.Add('        </Timer>')
        $detectionNodes.Add("        <If Name=`"$($slotNode)Revealed`">")
        $detectionNodes.Add("          <Edge From=`"$($slotNode)RevealCheck.HaveBuffTag`" To=`"Condition`" />")
        $detectionNodes.Add("          <Edge From=`"$($slotNode)RevealDelay.OnFinished`" To=`"Exec`" />")
        $detectionNodes.Add('        </If>')

        $deathNodes.Add("        <SoulDeathTrigger Name=`"$($slotNode)Death`">")
        $deathNodes.Add("          <Asset Name=`"Souls`" Alias=`"$($candidate.alias)`" />")
        $deathNodes.Add("          <Edge From=`"selectedTarget.$slotName`" To=`"IsActive`" />")
        $deathNodes.Add('        </SoulDeathTrigger>')

        $assets.Add("        <SoulAsset Name=`"$($candidate.alias)`" SharedSoulGuids=`"$($candidate.guid)`" />")
        $logs.Add("            <EnumLog Type=`"Started`" Name=`"$slotName`" IsTracked=`"true`" Marker=`"$($candidate.alias)`">")
        $logs.Add('              <Log StringName="dark_within_target" Text="Every whisper and trace now points to one person. The Passenger has chosen; all that remains is to carry out the sentence.">')
        $logs.Add('                <Localization Text="Every whisper and trace now points to one person. The Passenger has chosen; all that remains is to carry out the sentence." Language="WHS" />')
        $logs.Add('              </Log>')
        $logs.Add('            </EnumLog>')
    }

    $replacements = [ordered]@{
        '{{DP_QUEST_NAME}}' = $QuestName
        '{{DP_REGION_ID}}' = $RegionId
        '{{DP_REQUEST_CONTEXT}}' = $RequestContext
        '{{DP_TARGET_DEATH_CONTEXT}}' = $TargetDeathContext
        '{{DP_SEARCH_OBJECTIVE_NAME}}' = $SearchObjectiveName
        '{{DP_TARGET_OBJECTIVE_NAME}}' = $TargetObjectiveName
        '{{DP_CLEANUP_OBJECTIVE_NAME}}' = $CleanupObjectiveName
        '{{DP_QUEST_DESCRIPTION_KEY}}' = $QuestDescriptionKey
        '{{DP_TARGET_POOL_GUIDS}}' = (@($Candidates.guid) -join ' ')
        '{{DP_SEARCH_TYPE_ENUMS}}' = $searchTypeEnumerations -join "`n"
        '{{DP_SEARCH_STATE_EDGES}}' = $searchStateEdges -join "`n"
        '{{DP_SEARCH_AREA_ASSETS}}' = $searchAreaAssets -join "`n"
        '{{DP_SEARCH_LOGS}}' = $searchLogs -join "`n"
        '{{DP_SELECTED_TYPE_ENUMS}}' = $selectedTypeEnumerations -join "`n"
        '{{DP_TARGET_TYPE_ENUMS}}' = $targetTypeEnumerations -join "`n"
        '{{DP_SELECTED_STATE_EDGES}}' = $selectedStateEdges -join "`n"
        '{{DP_TARGET_STATE_EDGES}}' = $targetStateEdges -join "`n"
        '{{DP_TARGET_SEARCH_REVEAL_EDGES}}' = $searchRevealEdges -join "`n"
        '{{DP_TARGET_SEARCH_RESET_EDGES}}' = ''
        '{{DP_TARGET_SELECTION_STOP_EDGES}}' = $selectionStopEdges -join "`n"
        '{{DP_TARGET_CLEANUP_EDGES}}' = $cleanupEdges -join "`n"
        '{{DP_TARGET_DEATH_CONTEXT_EDGES}}' = $targetDeathContextEdges -join "`n"
        '{{DP_TARGET_DETECTION_NODES}}' = $detectionNodes -join "`n"
        '{{DP_TARGET_DEATH_NODES}}' = $deathNodes -join "`n"
        '{{DP_TARGET_ASSETS}}' = $assets -join "`n"
        '{{DP_TARGET_LOGS}}' = $logs -join "`n"
    }

    $questXml = $Template
    foreach ($token in $replacements.Keys) {
        if (-not $questXml.Contains($token)) {
            throw "Template token '$token' is missing."
        }
        $questXml = $questXml.Replace($token, [string]$replacements[$token])
    }
    if ($questXml -match '\{\{DP_[A-Z_]+\}\}') {
        throw "Generated quest '$QuestName' contains unresolved DP template tokens."
    }

    $questBytes = [System.Text.Encoding]::UTF8.GetByteCount($questXml)
    if ($questBytes -gt $MaxQuestBytesPerRegion) {
        throw "Region '$RegionId' quest is $questBytes bytes; limit is $MaxQuestBytesPerRegion."
    }

    [xml]$null = $questXml
    Write-Utf8NoBom -LiteralPath $OutputPath -Content $questXml
    Write-Host "Generated $RegionId graph: $($Candidates.Count) candidates, $questBytes bytes."
}

if (-not (Test-Path -LiteralPath $CatalogPath)) {
    throw "Candidate catalogue not found: $CatalogPath"
}
if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Quest template not found: $TemplatePath"
}
if (-not (Test-Path -LiteralPath $AreaManifestPath)) {
    throw "Settlement investigation area manifest not found: $AreaManifestPath"
}

$catalog = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
if ($catalog.schemaVersion -ne 2) {
    throw "Unsupported candidate catalogue schemaVersion '$($catalog.schemaVersion)'."
}
$areaManifest = Get-Content -Raw -LiteralPath $AreaManifestPath | ConvertFrom-Json
if ($areaManifest.schemaVersion -ne 1) {
    throw "Unsupported settlement area manifest schemaVersion '$($areaManifest.schemaVersion)'."
}
$allSearchAreas = @(
    $areaManifest.regions |
        ForEach-Object { $_.settlements } |
        Sort-Object gameRegion, id
)
if ($allSearchAreas.Count -eq 0) {
    throw 'Settlement investigation area manifest is empty.'
}
Assert-UniqueCandidateField -Candidates $allSearchAreas -Field 'alias'
$englishLocalizationKeys = Get-LocalizationKeys `
    -LiteralPath $EnglishLocalizationPath
$russianLocalizationKeys = Get-LocalizationKeys `
    -LiteralPath $RussianLocalizationPath
foreach ($searchArea in $allSearchAreas) {
    $localizationKey = Get-SearchLocalizationKey `
        -RegionId ([string]$searchArea.gameRegion) `
        -SettlementId ([string]$searchArea.id)
    if (
        -not $englishLocalizationKeys.Contains($localizationKey) -or
        -not $russianLocalizationKeys.Contains($localizationKey)
    ) {
        throw "Settlement search localization key '$localizationKey' is missing from English or Russian tables."
    }
}

$allCandidates = @($catalog.candidates)
if ($allCandidates.Count -eq 0) {
    throw 'Candidate catalogue is empty.'
}
foreach ($field in 'slot', 'alias', 'guid', 'entityName') {
    Assert-UniqueCandidateField -Candidates $allCandidates -Field $field
}

$enabledCandidates = @(
    $allCandidates |
        Where-Object { $_.enabled -eq $true } |
        Sort-Object { [int]$_.slot }
)
foreach ($candidate in $enabledCandidates) {
    if ([int]$candidate.slot -lt 1) {
        throw "Candidate slot '$($candidate.slot)' must be positive."
    }
    if ($candidate.alias -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "Candidate alias '$($candidate.alias)' is not a valid Skald identifier."
    }
    $parsedGuid = [guid]::Empty
    if (-not [guid]::TryParse([string]$candidate.guid, [ref]$parsedGuid)) {
        throw "Candidate GUID '$($candidate.guid)' is invalid."
    }
    if ([double]$candidate.weight -le 0) {
        throw "Candidate '$($candidate.entityName)' must have positive weight."
    }
}

$template = Get-Content -Raw -LiteralPath $TemplatePath
$regionSpecifications = @(
    [ordered]@{
        region = 'kutnohorsko'
        quest = 'dark_within_k'
        searchObjective = 'dark_within_objk'
        targetObjective = 'dark_within_targetk'
        cleanupObjective = 'dark_within_cleanupk'
        descriptionKey = 'dark_within_description_k'
        requestContext = 'dp_select_victim_kutnohorsko'
        targetDeathContext = 'dp_target_dead_kutnohorsko'
        output = $KuttenbergQuestOutputPath
    }
    [ordered]@{
        region = 'trosecko'
        quest = 'dark_within_t'
        searchObjective = 'dark_within_objt'
        targetObjective = 'dark_within_targett'
        cleanupObjective = 'dark_within_cleanupt'
        descriptionKey = 'dark_within_description_t'
        requestContext = 'dp_select_victim_trosecko'
        targetDeathContext = 'dp_target_dead_trosecko'
        output = $TroskyQuestOutputPath
    }
)

foreach ($specification in $regionSpecifications) {
    $regionalCandidates = @(
        $enabledCandidates |
            Where-Object { $_.gameRegion -eq $specification.region }
    )
    $regionalSearchAreas = @(
        $allSearchAreas |
            Where-Object { $_.gameRegion -eq $specification.region }
    )
    New-RegionalQuest `
        -Candidates $regionalCandidates `
        -SearchAreas $regionalSearchAreas `
        -RegionId $specification.region `
        -QuestName $specification.quest `
        -SearchObjectiveName $specification.searchObjective `
        -TargetObjectiveName $specification.targetObjective `
        -CleanupObjectiveName $specification.cleanupObjective `
        -QuestDescriptionKey $specification.descriptionKey `
        -RequestContext $specification.requestContext `
        -TargetDeathContext $specification.targetDeathContext `
        -OutputPath $specification.output `
        -Template $template
}

$luaRecords = [System.Collections.Generic.List[string]]::new()
foreach ($candidate in $enabledCandidates) {
    $luaTags = @(
        $candidate.tags |
            ForEach-Object { ConvertTo-LuaString -Value ([string]$_) }
    ) -join ', '
    $luaRecords.Add('    {')
    $luaRecords.Add("        slot = $([int]$candidate.slot),")
    $luaRecords.Add("        gameRegion = $(ConvertTo-LuaString ([string]$candidate.gameRegion)),")
    $luaRecords.Add("        settlement = $(ConvertTo-LuaString ([string]$candidate.settlement)),")
    $luaRecords.Add("        alias = $(ConvertTo-LuaString ([string]$candidate.alias)),")
    $luaRecords.Add("        guid = $(ConvertTo-LuaString ([string]$candidate.guid)),")
    $luaRecords.Add("        entityName = $(ConvertTo-LuaString ([string]$candidate.entityName)),")
    $luaRecords.Add("        tags = { $luaTags },")
    $luaRecords.Add("        weight = $([double]$candidate.weight),")
    $luaRecords.Add("        killableVerified = $(ConvertTo-LuaBoolean ([bool]$candidate.killableVerified)),")
    $luaRecords.Add("        storyCritical = $(ConvertTo-LuaBoolean ([bool]$candidate.storyCritical)),")
    $luaRecords.Add("        questCritical = $(ConvertTo-LuaBoolean ([bool]$candidate.questCritical)),")
    $luaRecords.Add("        immortal = $(ConvertTo-LuaBoolean ([bool]$candidate.immortal)),")
    $luaRecords.Add("        dead = $(ConvertTo-LuaBoolean ([bool]$candidate.dead)),")
    $luaRecords.Add('    },')
}

$settlementRecords = [System.Collections.Generic.List[string]]::new()
foreach ($settlement in @($catalog.settlements | Sort-Object gameRegion, id)) {
    $settlementRecords.Add('    {')
    $settlementRecords.Add("        id = $(ConvertTo-LuaString ([string]$settlement.id)),")
    $settlementRecords.Add("        gameRegion = $(ConvertTo-LuaString ([string]$settlement.gameRegion)),")
    $settlementRecords.Add("        displayName = $(ConvertTo-LuaString ([string]$settlement.displayName)),")
    $settlementRecords.Add("        x = $([double]$settlement.center.x),")
    $settlementRecords.Add("        y = $([double]$settlement.center.y),")
    $settlementRecords.Add("        z = $([double]$settlement.center.z),")
    $settlementRecords.Add('    },')
}

$lua = @(
    '-- Generated by tools/Generate-VictimArtifacts.ps1. Do not edit by hand.'
    'DarkPassengerGeneratedSettlements = {'
    $settlementRecords
    '}'
    ''
    'DarkPassengerGeneratedCandidates = {'
    $luaRecords
    '}'
    ''
    'return DarkPassengerGeneratedCandidates'
    ''
) -join "`n"

Write-Utf8NoBom -LiteralPath $LuaOutputPath -Content $lua
Write-Host "Generated Lua catalogue: $($enabledCandidates.Count) candidates, $(@($catalog.settlements).Count) settlements."
