param(
    [string]$CatalogPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\victim-candidates.json'),
    [string]$TemplatePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'),
    [string]$KuttenbergQuestOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml'),
    [string]$TroskyQuestOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\mod\Data\Quests\darkpassengertest\trosecko\dark_within_t.xml'),
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
        [string]$RegionId,
        [string]$QuestName,
        [string]$SearchObjectiveName,
        [string]$TargetObjectiveName,
        [string]$CleanupObjectiveName,
        [string]$QuestDescriptionKey,
        [string]$RequestContext,
        [string]$OutputPath,
        [string]$Template
    )

    if ($Candidates.Count -gt $MaxCandidatesPerRegion) {
        throw "Region '$RegionId' has $($Candidates.Count) candidates; limit is $MaxCandidatesPerRegion."
    }

    $typeEnumerations = [System.Collections.Generic.List[string]]::new()
    $stateEdges = [System.Collections.Generic.List[string]]::new()
    $selectionStopEdges = [System.Collections.Generic.List[string]]::new()
    $cleanupEdges = [System.Collections.Generic.List[string]]::new()
    $detectionNodes = [System.Collections.Generic.List[string]]::new()
    $deathNodes = [System.Collections.Generic.List[string]]::new()
    $deathBridgeNodes = [System.Collections.Generic.List[string]]::new()
    $assets = [System.Collections.Generic.List[string]]::new()
    $logs = [System.Collections.Generic.List[string]]::new()

    foreach ($candidate in $Candidates) {
        $slotNumber = [int]$candidate.slot
        $slotName = 'Target{0:D3}' -f $slotNumber
        $slotNode = 'targetSlot{0:D3}' -f $slotNumber

        $typeEnumerations.Add(
            "        <StateTypeEnumeration Name=`"$slotName`" ObjectiveValueType=`"Started`" />"
        )
        $stateEdges.Add("          <Edge From=`"$($slotNode)Tagged.True`" To=`"Set$slotName`" />")
        $stateEdges.Add("          <Edge From=`"$($slotNode)Death.OnDeath`" To=`"SetDone`" />")
        $selectionStopEdges.Add("          <Edge From=`"$($slotNode)Death.OnDeath`" To=`"SetFalse`" />")
        $cleanupEdges.Add("          <Edge From=`"$($slotNode)Death.OnDeath`" To=`"SetActive`" />")

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

        $deathNodes.Add("        <SoulDeathTrigger Name=`"$($slotNode)Death`">")
        $deathNodes.Add("          <Asset Name=`"Souls`" Alias=`"$($candidate.alias)`" />")
        $deathNodes.Add("          <Edge From=`"targetObjectiveProgress.$slotName`" To=`"IsActive`" />")
        $deathNodes.Add('        </SoulDeathTrigger>')

        $deathAction =
            "death|$($candidate.gameRegion)|$($candidate.settlement)|$slotNumber"
        $deathBridgeNodes.Add("        <dp_lua_call Name=`"$($slotNode)DeathBridge`">")
        $deathBridgeNodes.Add("          <Constant Name=`"action`" Value=`"$deathAction`" />")
        $deathBridgeNodes.Add("          <Edge From=`"$($slotNode)Death.OnDeath`" To=`"run`" />")
        $deathBridgeNodes.Add('        </dp_lua_call>')

        $assets.Add("        <SoulAsset Name=`"$($candidate.alias)`" SharedSoulGuids=`"$($candidate.guid)`" />")
        $logs.Add("            <EnumLog Type=`"Started`" Name=`"$slotName`" IsTracked=`"true`" Marker=`"$($candidate.alias)`">")
        $logs.Add('              <Log StringName="dark_within_target" Text="The Dark Passenger has made its choice. I must hunt the victim down and carry out the sentence.">')
        $logs.Add('                <Localization Text="The Dark Passenger has made its choice. I must hunt the victim down and carry out the sentence." Language="WHS" />')
        $logs.Add('              </Log>')
        $logs.Add('            </EnumLog>')
    }

    $replacements = [ordered]@{
        '{{DP_QUEST_NAME}}' = $QuestName
        '{{DP_REGION_ID}}' = $RegionId
        '{{DP_REQUEST_CONTEXT}}' = $RequestContext
        '{{DP_SEARCH_OBJECTIVE_NAME}}' = $SearchObjectiveName
        '{{DP_TARGET_OBJECTIVE_NAME}}' = $TargetObjectiveName
        '{{DP_CLEANUP_OBJECTIVE_NAME}}' = $CleanupObjectiveName
        '{{DP_QUEST_DESCRIPTION_KEY}}' = $QuestDescriptionKey
        '{{DP_TARGET_POOL_GUIDS}}' = (@($Candidates.guid) -join ' ')
        '{{DP_TARGET_TYPE_ENUMS}}' = $typeEnumerations -join "`n"
        '{{DP_TARGET_STATE_EDGES}}' = $stateEdges -join "`n"
        '{{DP_TARGET_SEARCH_RESET_EDGES}}' = ''
        '{{DP_TARGET_SELECTION_STOP_EDGES}}' = $selectionStopEdges -join "`n"
        '{{DP_TARGET_CLEANUP_EDGES}}' = $cleanupEdges -join "`n"
        '{{DP_TARGET_DETECTION_NODES}}' = $detectionNodes -join "`n"
        '{{DP_TARGET_DEATH_NODES}}' = $deathNodes -join "`n"
        '{{DP_TARGET_DEATH_BRIDGE_NODES}}' = $deathBridgeNodes -join "`n"
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

$catalog = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
if ($catalog.schemaVersion -ne 2) {
    throw "Unsupported candidate catalogue schemaVersion '$($catalog.schemaVersion)'."
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
        output = $TroskyQuestOutputPath
    }
)

foreach ($specification in $regionSpecifications) {
    $regionalCandidates = @(
        $enabledCandidates |
            Where-Object { $_.gameRegion -eq $specification.region }
    )
    New-RegionalQuest `
        -Candidates $regionalCandidates `
        -RegionId $specification.region `
        -QuestName $specification.quest `
        -SearchObjectiveName $specification.searchObjective `
        -TargetObjectiveName $specification.targetObjective `
        -CleanupObjectiveName $specification.cleanupObjective `
        -QuestDescriptionKey $specification.descriptionKey `
        -RequestContext $specification.requestContext `
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
