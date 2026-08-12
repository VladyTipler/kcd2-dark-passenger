param(
    [string]$CatalogPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\victim-candidates.json'),
    [string]$AreaManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\settlement-investigation-areas.json'),
    [string]$TemplatePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'),
    [string]$NativeWiringPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\generated\cases\native-wiring.json'),
    [string]$PoseProbeDialogSourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Data\Quests\darkpassengertest\pose_probe_male.xml'),
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

function Resolve-DpQuestObjectivePresentation {
    param(
        $JournalObjectives,
        [Parameter(Mandatory)][string]$ObjectiveId,
        [Parameter(Mandatory)]$Fallback
    )

    if ($null -eq $JournalObjectives) { return $Fallback }
    $property = $JournalObjectives.PSObject.Properties[$ObjectiveId]
    if ($null -eq $property) { return $Fallback }

    $configured = $property.Value
    if ($null -eq $configured) { return $Fallback }
    $configuredStates = if (
        $null -ne $configured.PSObject.Properties['states']
    ) { $configured.states } else { $null }
    $states = [ordered]@{}
    foreach ($fallbackState in $Fallback.states.PSObject.Properties) {
        $configuredState = if ($null -eq $configuredStates) { $null } else {
            $configuredStates.PSObject.Properties[$fallbackState.Name]
        }
        $configuredValue = if ($null -eq $configuredState) {
            $null
        }
        else {
            $configuredState.Value
        }
        $configuredKey = if ($null -eq $configuredValue) { '' } else {
            [string]$configuredValue.key
        }
        $configuredText = if ($null -eq $configuredValue) { '' } else {
            [string]$configuredValue.fallback
        }
        $states[$fallbackState.Name] = [pscustomobject][ordered]@{
            key = if ([string]::IsNullOrWhiteSpace($configuredKey)) {
                [string]$fallbackState.Value.key
            }
            else {
                $configuredKey
            }
            fallback = if ([string]::IsNullOrWhiteSpace($configuredText)) {
                [string]$fallbackState.Value.fallback
            }
            else {
                $configuredText
            }
        }
    }
    if ($null -ne $configuredStates) {
        foreach ($configuredState in $configuredStates.PSObject.Properties) {
            if (-not $states.Contains($configuredState.Name)) {
                $states[$configuredState.Name] = $configuredState.Value
            }
        }
    }

    $configuredNameKey = [string]$configured.nameKey
    $configuredFallbackName = [string]$configured.fallbackName
    return [pscustomobject][ordered]@{
        nameKey = if ([string]::IsNullOrWhiteSpace($configuredNameKey)) {
            [string]$Fallback.nameKey
        }
        else {
            $configuredNameKey
        }
        fallbackName = if (
            [string]::IsNullOrWhiteSpace($configuredFallbackName)
        ) {
            [string]$Fallback.fallbackName
        }
        else {
            $configuredFallbackName
        }
        states = [pscustomobject]$states
    }
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
        [string]$SearchProgressTypeName,
        [string]$EvidenceProgressTypeName,
        [string]$CleanupProgressTypeName,
        [string]$SelectedTargetTypeName,
        [string]$TargetProgressTypeName,
        [string]$SearchObjectiveName,
        [string]$EvidenceObjectiveName,
        [string]$TargetObjectiveName,
        [string]$CleanupObjectiveName,
        [string]$QuestDescriptionKey,
        [string]$RequestContext,
        [string]$TargetDeathContext,
        [string]$OutputPath,
        [string]$Template,
        $NativeWiring,
        [string]$PoseProbeDialogSourcePath
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
    $rumorDialogDefinition = ''
    $rumorDialogNodes = ''
    $witnessNodes = ''
    $overheardNodes = ''
    $overheardAssets = ''
    $evidenceStateNodes = ''
    $evidenceStateEdges = ''
    $evidenceType = ''
    $evidenceLogs = ''
    $evidenceResetPort = 'SetNone'
    $evidenceWitnessEdge = ''
    $witnessObjectiveNodes = ''
    $witnessType = ''
    $witnessObjective = ''
    $confessionProbeDefinition = ''
    $confessionProbeNodes = ''
    $questItemPlacementNodes = ''
    $questItemPlacementAssets = ''
    $guidanceNodes = ''
    $guidanceTypes = ''
    $guidanceAssets = ''
    $guidanceObjectives = ''
    $confessionProbeAssets = ''
    $storyModules = @()
    $primaryStoryModule = $null
    $primaryCaseActiveState = ''
    $caseActivationRevalidationEdges = @()

    if ($null -ne $NativeWiring) {
        $storyModules = @($NativeWiring.storyModules)
        if ($storyModules.Count -gt 0) {
            $primaryStoryModule = $storyModules[0]
            $primaryCaseActiveState = 'case{0}Active.State' -f
                [int]$primaryStoryModule.caseCode
            $caseActivationRevalidationEdges = @(
                $storyModules |
                    Sort-Object { [int]$_.caseCode } |
                    ForEach-Object {
                        '          <Edge From="case{0}ActiveTrigger.OnAdded" To="SetRunning" />' -f
                            [int]$_.caseCode
                    }
            )
        }
        $rumorDialogDefinition = [string]$NativeWiring.dialogDefinitions
        $rumorDialogNodes = [string]$NativeWiring.rumorNodes
        $witnessNodes = [string]$NativeWiring.witnessNodes
        $overheardNodes = [string]$NativeWiring.overheardNodes
        $overheardAssets = [string]$NativeWiring.overheardAssets
        $evidenceStateNodes = [string]$NativeWiring.evidenceStateNodes
        $evidenceStateEdges = [string]$NativeWiring.evidenceStateEdges
        $questItemPlacementNodes = [string]$NativeWiring.questItemPlacementNodes
        $questItemPlacementAssets = [string]$NativeWiring.questItemPlacementAssets
        $guidanceNodes = [string]$NativeWiring.guidanceNodes
        $guidanceTypes = [string]$NativeWiring.guidanceTypes
        $guidanceAssets = [string]$NativeWiring.guidanceAssets
        $guidanceObjectives = [string]$NativeWiring.guidanceObjectives
        $evidenceType = [string]$NativeWiring.evidenceType
        $evidenceLogs = [string]$NativeWiring.evidenceLogs
        $initialEvidenceStates = @(
            $NativeWiring.journalStates |
                Where-Object { [int]$_.code -eq 0 }
        )
        if ($initialEvidenceStates.Count -ne 1) {
            throw "Region '$RegionId' requires exactly one initial evidence state."
        }
        $evidenceResetPort = 'Set' + [string]$initialEvidenceStates[0].state_name
        $evidenceWitnessEdge = [string]$NativeWiring.evidenceWitnessEdge
        $witnessObjectiveNodes = [string]$NativeWiring.witnessObjectiveNodes
        $witnessType = [string]$NativeWiring.witnessType
        $witnessObjective = [string]$NativeWiring.witnessObjective
    }

    $fallbackObjectives = [pscustomobject][ordered]@{
        search = [pscustomobject][ordered]@{
            nameKey = 'dark_within_obj_name'
            fallbackName = 'Find someone who deserves the sentence'
            states = [pscustomobject][ordered]@{
                active = [pscustomobject][ordered]@{
                    key = 'dark_within_search'
                    fallback = 'Search the marked area for someone whose guilt deserves a sentence.'
                }
            }
        }
        investigation = [pscustomobject][ordered]@{
            nameKey = 'dark_within_evidence_name'
            fallbackName = 'Gather proof of guilt'
            states = [pscustomobject][ordered]@{}
        }
        target = [pscustomobject][ordered]@{
            nameKey = 'dark_within_target_name'
            fallbackName = 'Hunt down the chosen victim'
            states = [pscustomobject][ordered]@{
                active = [pscustomobject][ordered]@{
                    key = 'dark_within_target'
                    fallback = 'Every whisper and trace now points to one person. The Passenger has chosen; all that remains is to carry out the sentence.'
                }
                done = [pscustomobject][ordered]@{
                    key = 'dark_within_target_done'
                    fallback = 'The sentence has been carried out. Now I must leave no trace.'
                }
            }
        }
        cleanup = [pscustomobject][ordered]@{
            nameKey = 'dark_within_cleanup_name'
            fallbackName = 'Leave no trace'
            states = [pscustomobject][ordered]@{
                active = [pscustomobject][ordered]@{
                    key = 'dark_within_cleanup'
                    fallback = 'The work is done. Now I must make sure no one connects it to me.'
                }
                witnessed = [pscustomobject][ordered]@{
                    key = 'dark_within_cleanup_witnessed'
                    fallback = 'Someone saw too much.'
                }
                clean = [pscustomobject][ordered]@{
                    key = 'dark_within_cleanup_clean'
                    fallback = 'Everything is quiet. No one saw a thing. The Passenger is satisfied, and the world is a little cleaner.'
                }
                controlled = [pscustomobject][ordered]@{
                    key = 'dark_within_cleanup_controlled'
                    fallback = 'There were loose ends, but I cut them. It is enough to quiet the Passenger.'
                }
                noisy = [pscustomobject][ordered]@{
                    key = 'dark_within_cleanup_noisy'
                    fallback = 'It was not clean. I left too much noise behind. The hunger is sated, but the price will keep rising.'
                }
                external = [pscustomobject][ordered]@{
                    key = 'dark_within_cleanup_external'
                    fallback = 'Death found the chosen one without me. The case is closed, but the Passenger got nothing from it.'
                }
            }
        }
    }
    $journalObjectives = if (
        $null -ne $NativeWiring -and
        $null -ne $NativeWiring.PSObject.Properties['journalObjectives']
    ) { $NativeWiring.journalObjectives } else { $null }
    $hasConfiguredJournal = $null -ne $journalObjectives
    $searchPresentation = Resolve-DpQuestObjectivePresentation `
        -JournalObjectives $journalObjectives -ObjectiveId 'search' `
        -Fallback $fallbackObjectives.search
    $investigationPresentation = Resolve-DpQuestObjectivePresentation `
        -JournalObjectives $journalObjectives -ObjectiveId 'investigation' `
        -Fallback $fallbackObjectives.investigation
    $targetPresentation = Resolve-DpQuestObjectivePresentation `
        -JournalObjectives $journalObjectives -ObjectiveId 'target' `
        -Fallback $fallbackObjectives.target
    $cleanupPresentation = Resolve-DpQuestObjectivePresentation `
        -JournalObjectives $journalObjectives -ObjectiveId 'cleanup' `
        -Fallback $fallbackObjectives.cleanup

    if ($RegionId -eq 'trosecko') {
        if (-not (Test-Path -LiteralPath $PoseProbeDialogSourcePath)) {
            throw "Confession probe dialog not found: $PoseProbeDialogSourcePath"
        }
        $definitionsEnd = '      </Definitions>'
        if (-not $rumorDialogDefinition.Contains($definitionsEnd)) {
            throw "Trosky native wiring lacks a Definitions terminator."
        }
        $rumorDialogDefinition = $rumorDialogDefinition.Replace(
            $definitionsEnd,
            "        <Definition File=`"dark_within_t/pose_probe_male.xml`" />`n$definitionsEnd"
        )
        $confessionProbeNodes = @'
        <MakeArray Name="confessionProbeTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">
          <Constant Name="A" Value="120" />
        </MakeArray>
        <MakeArray Name="confessionProbeStanceTags" TypeT="wh::rpgmodule::BuffDefinitionAITags">
          <Constant Name="A" Value="121" />
        </MakeArray>
        <BuffTagTrigger Name="confessionProbeTrigger">
          <Asset Name="Souls" Alias="player" />
          <Edge From="confessionProbeTags.Array" To="BuffTags" />
          <Edge From="watcherActive.State" To="IsActive" />
        </BuffTagTrigger>
        <BuffTagTrigger Name="confessionProbeStanceTrigger">
          <Asset Name="Souls" Alias="player" />
          <Edge From="confessionProbeStanceTags.Array" To="BuffTags" />
          <Edge From="watcherActive.State" To="IsActive" />
        </BuffTagTrigger>
        <State Name="confessionProbeActive" TypeT="bool">
          <Edge From="confessionProbeTrigger.OnAdded" To="SetTrue" />
          <Edge From="confessionProbeTrigger.OnRemoved" To="SetFalse" />
          <Edge From="confessionProbeSceneFinished.OnFinished" To="SetFalse" />
        </State>
        <State Name="confessionProbeStanceActive" TypeT="bool">
          <Edge From="confessionProbeStanceTrigger.OnAdded" To="SetTrue" />
          <Edge From="confessionProbeStanceTrigger.OnRemoved" To="SetFalse" />
        </State>
        <Function Name="confessionProbeDialogParams" MethodName="wh::dialogmodule::CreateDialogParams" DeclaringType="wh::dialogmodule">
          <Asset Name="Participants" Alias="poseProbeLavrentiy" />
          <Constant Name="EnableEnding" Value="true" />
          <Constant Name="MovePlayer" Value="true" />
          <Constant Name="RotateParticipants" Value="true" />
          <Constant Name="HideNearbyNPCs" Value="false" />
        </Function>
        <EnableBehavior Name="confessionProbeLyingBehavior" Signature="empty" EventSet="">
          <Constant Name="Behavior" Value="lyingHarmed" />
          <Constant Name="ForceKick" Value="true" />
          <Asset Name="SmartEntity" Alias="confessionProbeLyingSpot" />
          <Asset Name="NPC" Alias="poseProbeLavrentiy" />
          <Edge From="confessionProbeStanceActive.State" To="IsActive" />
        </EnableBehavior>
        <InstantSendMessage Name="confessionProbeHolsterWeapon" MessageType="player:holsterWeapon">
          <Asset Name="Receiver" Alias="player" />
          <Constant Name="Content_keepTorch" Value="true" />
          <Edge From="confessionProbeTrigger.OnAdded" To="Exec" />
        </InstantSendMessage>
        <pose_probe_male Name="confessionProbeDialog">
          <Asset Name="DialogueHolder" Alias="confessionProbeDialogueHolder" />
          <Edge From="confessionProbeActive.State" To="available" />
          <Edge From="confessionProbeDialogParams.DialogParams" To="DialogParams" />
          <Edge From="confessionProbeHolsterWeapon.OnExec" To="EnqueueDialogue" />
        </pose_probe_male>
        <SceneFinishedWaiter Name="confessionProbeSceneFinished">
          <Edge From="confessionProbeDialog.started" To="Enqueue" />
        </SceneFinishedWaiter>
        <Function Name="removeConfessionProbeBuff" MethodName="wh::rpgmodule::RemoveBuff" DeclaringType="wh::rpgmodule">
          <Asset Name="Souls" Alias="player" />
          <Constant Name="Buff" Value="d0c1935f-2d7a-4f4e-bb5c-9ce734d99271" />
          <Edge From="confessionProbeSceneFinished.OnFinished" To="Exec" />
        </Function>
        <Function Name="returnLavrentiyToUnconsciousness" MethodName="wh::rpgmodule::AddBuff" DeclaringType="wh::rpgmodule">
          <Asset Name="Souls" Alias="poseProbeLavrentiy" />
          <Constant Name="Buff" Value="f8d60fe4-e2c1-420a-946a-213e1cd09265" />
          <Edge From="confessionProbeSceneFinished.OnFinished" To="Exec" />
        </Function>
        <Timer Name="confessionProbeReleaseStanceDelay">
          <Constant Name="Duration" Value="500ms" />
          <Constant Name="TimeType" Value="GameTime" />
          <Edge From="confessionProbeSceneFinished.OnFinished" To="SetRunning" />
        </Timer>
        <Function Name="removeConfessionProbeStanceBuff" MethodName="wh::rpgmodule::RemoveBuff" DeclaringType="wh::rpgmodule">
          <Asset Name="Souls" Alias="player" />
          <Constant Name="Buff" Value="5138624d-76d9-42de-ae19-e144031249cc" />
          <Edge From="confessionProbeReleaseStanceDelay.OnFinished" To="Exec" />
        </Function>
'@
        $confessionProbeAssets = @'
        <SoulAsset Name="poseProbeLavrentiy" SharedSoulGuids="449022cc-0fbf-ffa4-021b-2b4b13e113be" />
        <DialogueHolderAsset Name="confessionProbeDialogueHolder" />
        <SmartObjectAsset Name="confessionProbeLyingSpot" />
'@
    }

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

    if ($RegionId -eq 'kutnohorsko') {
        $legacySearchAreas = @(
            $SearchAreas | Where-Object { [string]$_.id -eq 'pritoky' }
        )
        if ($legacySearchAreas.Count -ne 1) {
            throw 'Legacy Pritoky save compatibility requires one Pritoky search area.'
        }
        $legacySearchArea = $legacySearchAreas[0]
        $legacyAliases = @($legacySearchArea.legacyAliases)
        if ($legacyAliases.Count -ne 1) {
            throw 'Legacy Pritoky save compatibility requires one marker alias.'
        }
        $legacyMarkerAlias = [string]$legacyAliases[0]
        if ($legacyMarkerAlias -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Legacy Pritoky marker alias '$legacyMarkerAlias' is invalid."
        }
        $legacyDisplayName = [string]$legacySearchArea.displayName.english
        $legacyLocalizationKey = if ($hasConfiguredJournal) {
            [string]$searchPresentation.states.active.key
        }
        else {
            Get-SearchLocalizationKey -RegionId $RegionId `
                -SettlementId ([string]$legacySearchArea.id)
        }
        $legacyFallbackText = ConvertTo-XmlText $(if ($hasConfiguredJournal) {
            [string]$searchPresentation.states.active.fallback
        }
        else {
            "The trail leads to $legacyDisplayName. Somewhere within this ground is someone whose guilt may deserve a sentence. I must listen, watch, and be certain."
        })
        $searchTypeEnumerations.Add(
            '          <StateTypeEnumeration Name="Active" ObjectiveValueType="Started" />'
        )
        $searchAreaAssets.Add(
            "        <TriggerAreaAsset Name=`"$legacyMarkerAlias`" />"
        )
        $searchLogs.Add(
            "            <EnumLog Type=`"Started`" Name=`"Active`" IsTracked=`"true`" Marker=`"$legacyMarkerAlias`">"
        )
        $searchLogs.Add(
            "              <Log StringName=`"$legacyLocalizationKey`" Text=`"$legacyFallbackText`">"
        )
        $searchLogs.Add(
            "                <Localization Text=`"$legacyFallbackText`" Language=`"WHS`" />"
        )
        $searchLogs.Add('              </Log>')
        $searchLogs.Add('            </EnumLog>')
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
        $localizationKey = if ($hasConfiguredJournal) {
            [string]$searchPresentation.states.active.key
        }
        else {
            Get-SearchLocalizationKey -RegionId $RegionId `
                -SettlementId ([string]$searchArea.id)
        }
        $fallbackText = ConvertTo-XmlText $(if ($hasConfiguredJournal) {
            [string]$searchPresentation.states.active.fallback
        }
        else {
            "The trail leads to $englishDisplayName. Somewhere within this ground is someone whose guilt may deserve a sentence. I must listen, watch, and be certain."
        })

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
        $detectionNodes.Add('          <Edge From="questProgress.OnActive" To="SetRunning" />')
        foreach ($caseActivationEdge in $caseActivationRevalidationEdges) {
            $detectionNodes.Add($caseActivationEdge)
        }
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
        $targetActiveKey = ConvertTo-XmlText `
            ([string]$targetPresentation.states.active.key)
        $targetActiveText = ConvertTo-XmlText `
            ([string]$targetPresentation.states.active.fallback)
        $logs.Add("              <Log StringName=`"$targetActiveKey`" Text=`"$targetActiveText`">")
        $logs.Add("                <Localization Text=`"$targetActiveText`" Language=`"WHS`" />")
        $logs.Add('              </Log>')
        $logs.Add('            </EnumLog>')
    }

    $casePresentationGateNodes =
        [System.Collections.Generic.List[string]]::new()
    $additionalStoryNodes = [System.Collections.Generic.List[string]]::new()
    $additionalStoryTypes = [System.Collections.Generic.List[string]]::new()
    $additionalStoryObjectives = [System.Collections.Generic.List[string]]::new()
    $gateState = @{ Index = 0 }
    $gateEdges = {
        param(
            [object[]]$Edges,
            [string]$CaseActiveState,
            [string]$Stem
        )
        if ([string]::IsNullOrWhiteSpace($CaseActiveState)) {
            return @($Edges)
        }
        $result = [System.Collections.Generic.List[string]]::new()
        foreach ($edge in @($Edges)) {
            $match = [regex]::Match(
                [string]$edge,
                '<Edge From="([^"]+)" To="([^"]+)"\s*/>'
            )
            if (-not $match.Success) {
                throw "Cannot case-gate malformed edge '$edge'."
            }
            $gateState.Index++
            $gateName = '{0}Gate{1:D4}' -f $Stem, $gateState.Index
            $casePresentationGateNodes.Add(
                "        <If Name=`"$gateName`">"
            )
            $casePresentationGateNodes.Add(
                "          <Edge From=`"$CaseActiveState`" To=`"Condition`" />"
            )
            $casePresentationGateNodes.Add(
                "          <Edge From=`"$($match.Groups[1].Value)`" To=`"Exec`" />"
            )
            $casePresentationGateNodes.Add('        </If>')
            $result.Add(
                "          <Edge From=`"$gateName.True`" To=`"$($match.Groups[2].Value)`" />"
            )
        }
        return $result.ToArray()
    }

    $baseSearchStateEdges = @($searchStateEdges)
    $baseSearchRevealEdges = @($searchRevealEdges)
    $baseTargetStateEdges = @($targetStateEdges)
    $baseCleanupEdges = @($cleanupEdges)
    $primaryEvidenceDoneEdge = @(
        '          <Edge From="revealTagTrigger.OnAdded" To="SetDone" />'
    )
    $primaryCleanupResultEdges = @(
        '          <Edge From="witnessDetectedTrigger.OnAdded" To="SetWitnessed" />',
        '          <Edge From="cleanResultTrigger.OnAdded" To="SetClean" />',
        '          <Edge From="controlledResultTrigger.OnAdded" To="SetControlled" />',
        '          <Edge From="noisyResultTrigger.OnAdded" To="SetNoisy" />',
        '          <Edge From="externalResultTrigger.OnAdded" To="SetExternal" />'
    )
    if (-not [string]::IsNullOrWhiteSpace($primaryCaseActiveState)) {
        $searchStateEdges = @(& $gateEdges $baseSearchStateEdges `
            $primaryCaseActiveState 'primarySearch')
        $searchRevealEdges = @(& $gateEdges $baseSearchRevealEdges `
            $primaryCaseActiveState 'primarySearchReveal')
        $targetStateEdges = @(& $gateEdges $baseTargetStateEdges `
            $primaryCaseActiveState 'primaryTarget')
        $cleanupEdges = @(& $gateEdges $baseCleanupEdges `
            $primaryCaseActiveState 'primaryCleanup')
        $primaryEvidenceDoneEdge = @(& $gateEdges `
            $primaryEvidenceDoneEdge $primaryCaseActiveState `
            'primaryEvidenceDone')
        $primaryCleanupResultEdges = @(& $gateEdges `
            $primaryCleanupResultEdges $primaryCaseActiveState `
            'primaryCleanupResult')
    }

    $regionSuffix = if ($RegionId -eq 'trosecko') { 't' } else { 'k' }
    for ($storyIndex = 1; $storyIndex -lt $storyModules.Count; $storyIndex++) {
        $story = $storyModules[$storyIndex]
        $caseCode = [int]$story.caseCode
        $casePrefix = "case$caseCode"
        $caseActiveState = "${casePrefix}Active.State"
        $searchType = "DP_Case${caseCode}SearchProgress_$regionSuffix"
        $evidenceProgressType =
            "DP_Case${caseCode}EvidenceProgress_$regionSuffix"
        $targetType = "DP_Case${caseCode}TargetProgress_$regionSuffix"
        $cleanupType = "DP_Case${caseCode}CleanupProgress_$regionSuffix"
        $searchObjective = "DarkWithinCase${caseCode}Search_$regionSuffix"
        $evidenceObjective =
            "DarkWithinCase${caseCode}Evidence_$regionSuffix"
        $targetObjective = "DarkWithinCase${caseCode}Target_$regionSuffix"
        $cleanupObjective = "DarkWithinCase${caseCode}Cleanup_$regionSuffix"
        $objectives = $story.journalObjectives
        $storySearch = Resolve-DpQuestObjectivePresentation `
            -JournalObjectives $objectives -ObjectiveId 'search' `
            -Fallback $fallbackObjectives.search
        $storyInvestigation = Resolve-DpQuestObjectivePresentation `
            -JournalObjectives $objectives -ObjectiveId 'investigation' `
            -Fallback $fallbackObjectives.investigation
        $storyTarget = Resolve-DpQuestObjectivePresentation `
            -JournalObjectives $objectives -ObjectiveId 'target' `
            -Fallback $fallbackObjectives.target
        $storyCleanup = Resolve-DpQuestObjectivePresentation `
            -JournalObjectives $objectives -ObjectiveId 'cleanup' `
            -Fallback $fallbackObjectives.cleanup
        $initialState = @($story.journalStates | Where-Object {
            [int]$_.code -eq 0
        })
        if ($initialState.Count -ne 1) {
            throw "Case '$caseCode' requires one initial evidence state."
        }
        $resetPort = 'Set' + [string]$initialState[0].state_name
        $storySearchEdges = @(& $gateEdges $baseSearchStateEdges `
            $caseActiveState "${casePrefix}Search")
        $storyRevealEdges = @(& $gateEdges $baseSearchRevealEdges `
            $caseActiveState "${casePrefix}SearchReveal")
        $storyTargetEdges = @(& $gateEdges $baseTargetStateEdges `
            $caseActiveState "${casePrefix}Target")
        $storyCleanupEdges = @(& $gateEdges $baseCleanupEdges `
            $caseActiveState "${casePrefix}Cleanup")
        $storyEvidenceDone = @(& $gateEdges @(
            '          <Edge From="revealTagTrigger.OnAdded" To="SetDone" />'
        ) $caseActiveState "${casePrefix}EvidenceDone")
        $storyCleanupResults = @(& $gateEdges @(
            '          <Edge From="witnessDetectedTrigger.OnAdded" To="SetWitnessed" />',
            '          <Edge From="cleanResultTrigger.OnAdded" To="SetClean" />',
            '          <Edge From="controlledResultTrigger.OnAdded" To="SetControlled" />',
            '          <Edge From="noisyResultTrigger.OnAdded" To="SetNoisy" />',
            '          <Edge From="externalResultTrigger.OnAdded" To="SetExternal" />'
        ) $caseActiveState "${casePrefix}CleanupResult")

        $additionalStoryNodes.Add(@"
        <State Name="${casePrefix}SearchProgress" TypeT="$searchType">
          <Edge From="satisfactionTrigger.OnRemoved" To="SetNone" />
          <Edge From="questProgress.OnActive" To="SetNone" />
$($storySearchEdges -join "`n")
$($storyRevealEdges -join "`n")
        </State>
        <$searchObjective Name="${casePrefix}SearchVisual">
          <Edge From="${casePrefix}SearchProgress.State" To="Progress" />
        </$searchObjective>
        <State Name="${casePrefix}EvidenceProgress" TypeT="$evidenceProgressType">
          <Edge From="satisfactionTrigger.OnRemoved" To="$resetPort" />
$([string]$story.evidenceStateEdges)
$($storyEvidenceDone -join "`n")
        </State>
        <$evidenceObjective Name="${casePrefix}EvidenceVisual">
          <Edge From="${casePrefix}EvidenceProgress.State" To="Progress" />
        </$evidenceObjective>
        <State Name="${casePrefix}TargetProgress" TypeT="$targetType">
          <Edge From="satisfactionTrigger.OnRemoved" To="SetNone" />
          <Edge From="questProgress.OnActive" To="SetNone" />
$($storyTargetEdges -join "`n")
        </State>
        <$targetObjective Name="${casePrefix}TargetVisual">
          <Edge From="${casePrefix}TargetProgress.State" To="Progress" />
        </$targetObjective>
        <State Name="${casePrefix}CleanupProgress" TypeT="$cleanupType">
          <Edge From="satisfactionTrigger.OnRemoved" To="SetNone" />
          <Edge From="questProgress.OnActive" To="SetNone" />
$($storyCleanupEdges -join "`n")
$($storyCleanupResults -join "`n")
        </State>
        <$cleanupObjective Name="${casePrefix}CleanupVisual">
          <Edge From="${casePrefix}CleanupProgress.State" To="Progress" />
        </$cleanupObjective>
"@.TrimEnd())

        $additionalStoryTypes.Add(@"
        <Type TypeName="$searchType">
          <StateTypeEnumeration Name="None" ObjectiveValueType="None" />
$($searchTypeEnumerations -join "`n")
          <StateTypeEnumeration Name="Done" ObjectiveValueType="Completed" />
        </Type>
        <Type TypeName="$evidenceProgressType">
$([string]$story.evidenceType)
          <StateTypeEnumeration Name="Done" ObjectiveValueType="Completed" />
        </Type>
        <Type TypeName="$targetType">
          <StateTypeEnumeration Name="None" ObjectiveValueType="None" />
$($targetTypeEnumerations -join "`n")
          <StateTypeEnumeration Name="Done" ObjectiveValueType="Completed" />
        </Type>
        <Type TypeName="$cleanupType">
          <StateTypeEnumeration Name="None" ObjectiveValueType="None" />
          <StateTypeEnumeration Name="Active" ObjectiveValueType="Started" />
          <StateTypeEnumeration Name="Witnessed" ObjectiveValueType="Started" />
          <StateTypeEnumeration Name="Clean" ObjectiveValueType="Completed" />
          <StateTypeEnumeration Name="Controlled" ObjectiveValueType="Completed" />
          <StateTypeEnumeration Name="Noisy" ObjectiveValueType="Completed" />
          <StateTypeEnumeration Name="External" ObjectiveValueType="Completed" />
        </Type>
"@.TrimEnd())

        $storySearchLogs = ($searchLogs -join "`n").Replace(
            [string]$searchPresentation.states.active.key,
            [string]$storySearch.states.active.key
        ).Replace(
            (ConvertTo-XmlText ([string]$searchPresentation.states.active.fallback)),
            (ConvertTo-XmlText ([string]$storySearch.states.active.fallback))
        )
        $storyTargetLogs = ($logs -join "`n").Replace(
            [string]$targetPresentation.states.active.key,
            [string]$storyTarget.states.active.key
        ).Replace(
            (ConvertTo-XmlText ([string]$targetPresentation.states.active.fallback)),
            (ConvertTo-XmlText ([string]$storyTarget.states.active.fallback))
        )
        $additionalStoryObjectives.Add(@"
        <Objective TypeT="$searchType" Name="$searchObjective">
          <LocalizedName StringName="$($storySearch.nameKey)" Text="$(ConvertTo-XmlText ([string]$storySearch.fallbackName))">
            <Localization Text="$(ConvertTo-XmlText ([string]$storySearch.fallbackName))" Language="WHS" />
          </LocalizedName>
          <Logs>
            <EnumLog Type="None" Name="None" />
$storySearchLogs
            <EnumLog Type="Completed" Name="Done" />
          </Logs>
        </Objective>
        <Objective TypeT="$targetType" Name="$targetObjective">
          <LocalizedName StringName="$($storyTarget.nameKey)" Text="$(ConvertTo-XmlText ([string]$storyTarget.fallbackName))">
            <Localization Text="$(ConvertTo-XmlText ([string]$storyTarget.fallbackName))" Language="WHS" />
          </LocalizedName>
          <Logs>
            <EnumLog Type="None" Name="None" />
$storyTargetLogs
            <EnumLog Type="Completed" Name="Done">
              <Log StringName="$($storyTarget.states.done.key)" Text="$(ConvertTo-XmlText ([string]$storyTarget.states.done.fallback))">
                <Localization Text="$(ConvertTo-XmlText ([string]$storyTarget.states.done.fallback))" Language="WHS" />
              </Log>
            </EnumLog>
          </Logs>
        </Objective>
        <Objective TypeT="$evidenceProgressType" Name="$evidenceObjective">
          <LocalizedName StringName="$($storyInvestigation.nameKey)" Text="$(ConvertTo-XmlText ([string]$storyInvestigation.fallbackName))">
            <Localization Text="$(ConvertTo-XmlText ([string]$storyInvestigation.fallbackName))" Language="WHS" />
          </LocalizedName>
          <Logs>
$([string]$story.evidenceLogs)
            <EnumLog Type="Completed" Name="Done" />
          </Logs>
        </Objective>
        <Objective TypeT="$cleanupType" Name="$cleanupObjective">
          <LocalizedName StringName="$($storyCleanup.nameKey)" Text="$(ConvertTo-XmlText ([string]$storyCleanup.fallbackName))">
            <Localization Text="$(ConvertTo-XmlText ([string]$storyCleanup.fallbackName))" Language="WHS" />
          </LocalizedName>
          <Logs>
            <EnumLog Type="None" Name="None" />
            <EnumLog Type="Started" Name="Active" IsTracked="true"><Log StringName="$($storyCleanup.states.active.key)" Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.active.fallback))"><Localization Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.active.fallback))" Language="WHS" /></Log></EnumLog>
            <EnumLog Type="Started" Name="Witnessed" IsTracked="true"><Log StringName="$($storyCleanup.states.witnessed.key)" Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.witnessed.fallback))"><Localization Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.witnessed.fallback))" Language="WHS" /></Log></EnumLog>
            <EnumLog Type="Completed" Name="Clean"><Log StringName="$($storyCleanup.states.clean.key)" Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.clean.fallback))"><Localization Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.clean.fallback))" Language="WHS" /></Log></EnumLog>
            <EnumLog Type="Completed" Name="Controlled"><Log StringName="$($storyCleanup.states.controlled.key)" Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.controlled.fallback))"><Localization Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.controlled.fallback))" Language="WHS" /></Log></EnumLog>
            <EnumLog Type="Completed" Name="Noisy"><Log StringName="$($storyCleanup.states.noisy.key)" Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.noisy.fallback))"><Localization Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.noisy.fallback))" Language="WHS" /></Log></EnumLog>
            <EnumLog Type="Completed" Name="External"><Log StringName="$($storyCleanup.states.external.key)" Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.external.fallback))"><Localization Text="$(ConvertTo-XmlText ([string]$storyCleanup.states.external.fallback))" Language="WHS" /></Log></EnumLog>
          </Logs>
        </Objective>
"@.TrimEnd())
    }

    $replacements = [ordered]@{
        '{{DP_QUEST_NAME}}' = $QuestName
        '{{DP_REGION_ID}}' = $RegionId
        '{{DP_SEARCH_PROGRESS_TYPE}}' = $SearchProgressTypeName
        '{{DP_EVIDENCE_PROGRESS_TYPE}}' = $EvidenceProgressTypeName
        '{{DP_CLEANUP_PROGRESS_TYPE}}' = $CleanupProgressTypeName
        '{{DP_EVIDENCE_RESET_PORT}}' = $evidenceResetPort
        '{{DP_SELECTED_TARGET_TYPE}}' = $SelectedTargetTypeName
        '{{DP_TARGET_PROGRESS_TYPE}}' = $TargetProgressTypeName
        '{{DP_REQUEST_CONTEXT}}' = $RequestContext
        '{{DP_TARGET_DEATH_CONTEXT}}' = $TargetDeathContext
        '{{DP_RUMOR_DIALOG_DEFINITION}}' = $rumorDialogDefinition.TrimEnd()
        '{{DP_CONFESSION_PROBE_DEFINITION}}' = $confessionProbeDefinition
        '{{DP_RUMOR_DIALOG_NODES}}' = $rumorDialogNodes.TrimEnd()
        '{{DP_WITNESS_NODES}}' = $witnessNodes.TrimEnd()
        '{{DP_OVERHEARD_NODES}}' = $overheardNodes.TrimEnd()
        '{{DP_EVIDENCE_STATE_NODES}}' = $evidenceStateNodes.TrimEnd()
        '{{DP_CONFESSION_PROBE_NODES}}' = $confessionProbeNodes.TrimEnd()
        '{{DP_QUEST_ITEM_PLACEMENT_NODES}}' = $questItemPlacementNodes.TrimEnd()
        '{{DP_GUIDANCE_NODES}}' = $guidanceNodes.TrimEnd()
        '{{DP_EVIDENCE_STATE_EDGES}}' = $evidenceStateEdges.TrimEnd()
        '{{DP_EVIDENCE_TYPE_ENUMS}}' = $evidenceType.TrimEnd()
        '{{DP_EVIDENCE_LOGS}}' = $evidenceLogs.TrimEnd()
        '{{DP_EVIDENCE_WITNESS_EDGE}}' = $evidenceWitnessEdge
        '{{DP_WITNESS_OBJECTIVE_NODES}}' = $witnessObjectiveNodes.TrimEnd()
        '{{DP_WITNESS_TYPE}}' = $witnessType.TrimEnd()
        '{{DP_GUIDANCE_TYPES}}' = $guidanceTypes.TrimEnd()
        '{{DP_WITNESS_OBJECTIVE}}' = $witnessObjective.TrimEnd()
        '{{DP_GUIDANCE_OBJECTIVES}}' = $guidanceObjectives.TrimEnd()
        '{{DP_SEARCH_OBJECTIVE_NAME}}' = $SearchObjectiveName
        '{{DP_EVIDENCE_OBJECTIVE_NAME}}' = $EvidenceObjectiveName
        '{{DP_TARGET_OBJECTIVE_NAME}}' = $TargetObjectiveName
        '{{DP_CLEANUP_OBJECTIVE_NAME}}' = $CleanupObjectiveName
        '{{DP_SEARCH_NAME_KEY}}' = [string]$searchPresentation.nameKey
        '{{DP_SEARCH_NAME_TEXT}}' = ConvertTo-XmlText `
            ([string]$searchPresentation.fallbackName)
        '{{DP_INVESTIGATION_NAME_KEY}}' = `
            [string]$investigationPresentation.nameKey
        '{{DP_INVESTIGATION_NAME_TEXT}}' = ConvertTo-XmlText `
            ([string]$investigationPresentation.fallbackName)
        '{{DP_TARGET_NAME_KEY}}' = [string]$targetPresentation.nameKey
        '{{DP_TARGET_NAME_TEXT}}' = ConvertTo-XmlText `
            ([string]$targetPresentation.fallbackName)
        '{{DP_TARGET_DONE_KEY}}' = [string]$targetPresentation.states.done.key
        '{{DP_TARGET_DONE_TEXT}}' = ConvertTo-XmlText `
            ([string]$targetPresentation.states.done.fallback)
        '{{DP_CLEANUP_NAME_KEY}}' = [string]$cleanupPresentation.nameKey
        '{{DP_CLEANUP_NAME_TEXT}}' = ConvertTo-XmlText `
            ([string]$cleanupPresentation.fallbackName)
        '{{DP_CLEANUP_ACTIVE_KEY}}' = `
            [string]$cleanupPresentation.states.active.key
        '{{DP_CLEANUP_ACTIVE_TEXT}}' = ConvertTo-XmlText `
            ([string]$cleanupPresentation.states.active.fallback)
        '{{DP_CLEANUP_WITNESSED_KEY}}' = `
            [string]$cleanupPresentation.states.witnessed.key
        '{{DP_CLEANUP_WITNESSED_TEXT}}' = ConvertTo-XmlText `
            ([string]$cleanupPresentation.states.witnessed.fallback)
        '{{DP_CLEANUP_CLEAN_KEY}}' = `
            [string]$cleanupPresentation.states.clean.key
        '{{DP_CLEANUP_CLEAN_TEXT}}' = ConvertTo-XmlText `
            ([string]$cleanupPresentation.states.clean.fallback)
        '{{DP_CLEANUP_CONTROLLED_KEY}}' = `
            [string]$cleanupPresentation.states.controlled.key
        '{{DP_CLEANUP_CONTROLLED_TEXT}}' = ConvertTo-XmlText `
            ([string]$cleanupPresentation.states.controlled.fallback)
        '{{DP_CLEANUP_NOISY_KEY}}' = `
            [string]$cleanupPresentation.states.noisy.key
        '{{DP_CLEANUP_NOISY_TEXT}}' = ConvertTo-XmlText `
            ([string]$cleanupPresentation.states.noisy.fallback)
        '{{DP_CLEANUP_EXTERNAL_KEY}}' = `
            [string]$cleanupPresentation.states.external.key
        '{{DP_CLEANUP_EXTERNAL_TEXT}}' = ConvertTo-XmlText `
            ([string]$cleanupPresentation.states.external.fallback)
        '{{DP_QUEST_DESCRIPTION_KEY}}' = $QuestDescriptionKey
        '{{DP_TARGET_POOL_GUIDS}}' = (@($Candidates.guid) -join ' ')
        '{{DP_SEARCH_TYPE_ENUMS}}' = $searchTypeEnumerations -join "`n"
        '{{DP_SEARCH_STATE_EDGES}}' = $searchStateEdges -join "`n"
        '{{DP_SEARCH_AREA_ASSETS}}' = $searchAreaAssets -join "`n"
        '{{DP_QUEST_ITEM_PLACEMENT_ASSETS}}' =
            $questItemPlacementAssets.TrimEnd()
        '{{DP_GUIDANCE_ASSETS}}' = $guidanceAssets.TrimEnd()
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
        '{{DP_CASE_PRESENTATION_GATE_NODES}}' =
            $casePresentationGateNodes -join "`n"
        '{{DP_EVIDENCE_DONE_EDGE}}' = $primaryEvidenceDoneEdge -join "`n"
        '{{DP_CLEANUP_RESULT_EDGES}}' =
            $primaryCleanupResultEdges -join "`n"
        '{{DP_ADDITIONAL_STORY_NODES}}' =
            $additionalStoryNodes -join "`n"
        '{{DP_ADDITIONAL_STORY_TYPES}}' =
            $additionalStoryTypes -join "`n"
        '{{DP_ADDITIONAL_STORY_OBJECTIVES}}' =
            $additionalStoryObjectives -join "`n"
        '{{DP_TARGET_ASSETS}}' = $assets -join "`n"
        '{{DP_OVERHEARD_ASSETS}}' = $overheardAssets.TrimEnd()
        '{{DP_CONFESSION_PROBE_ASSETS}}' = $confessionProbeAssets.TrimEnd()
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
    if ($null -ne $NativeWiring) {
        $dialogSourceRoot = Join-Path (
            Split-Path -Parent (
                Split-Path -Parent (
                    Split-Path -Parent (
                        Split-Path -Parent $OutputPath
                    )
                )
            )
        ) (
            'darkpassengertest\' + $RegionId + '\' +
            [string]$NativeWiring.dialogFolder
        )
        $dialogOutputRoot = Join-Path (Split-Path -Parent $OutputPath) `
            ([string]$NativeWiring.dialogFolder)
        foreach ($fileName in @($NativeWiring.dialogueFiles)) {
            $dialogSourcePath = Join-Path $dialogSourceRoot ([string]$fileName)
            if (-not (Test-Path -LiteralPath $dialogSourcePath)) {
                throw "Compiled dialogue not found: $dialogSourcePath"
            }
            Write-Utf8NoBom `
                -LiteralPath (Join-Path $dialogOutputRoot ([string]$fileName)) `
                -Content ([System.IO.File]::ReadAllText($dialogSourcePath))
        }
    }
    if ($RegionId -eq 'trosecko') {
        $probeDialogOutputRoot = Join-Path (Split-Path -Parent $OutputPath) `
            'dark_within_t'
        Write-Utf8NoBom `
            -LiteralPath (Join-Path $probeDialogOutputRoot 'pose_probe_male.xml') `
            -Content ([System.IO.File]::ReadAllText(
                $PoseProbeDialogSourcePath
            ))
    }
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
if (-not (Test-Path -LiteralPath $NativeWiringPath)) {
    throw "Compiled native wiring not found: $NativeWiringPath"
}

$catalog = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
if ($catalog.schemaVersion -ne 2) {
    throw "Unsupported candidate catalogue schemaVersion '$($catalog.schemaVersion)'."
}
$areaManifest = Get-Content -Raw -LiteralPath $AreaManifestPath | ConvertFrom-Json
$nativeWiringManifest = Get-Content -Raw -LiteralPath $NativeWiringPath |
    ConvertFrom-Json -Depth 100
if ([int]$nativeWiringManifest.schemaVersion -ne 1) {
    throw "Unsupported native wiring schemaVersion '$($nativeWiringManifest.schemaVersion)'."
}
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
        searchProgressType = 'DP_SearchProgress'
        evidenceProgressType = 'DP_KutnohorskoEvidenceProgress'
        cleanupProgressType = 'DP_KutnohorskoCleanupProgress'
        selectedTargetType = 'DP_SelectedTarget'
        targetProgressType = 'DP_TargetProgress'
        searchObjective = 'dark_within_objk'
        evidenceObjective = 'dark_within_evidencek'
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
        searchProgressType = 'DP_TroseckoSearchProgress'
        evidenceProgressType = 'DP_TroseckoEvidenceProgress'
        cleanupProgressType = 'DP_TroseckoCleanupProgress'
        selectedTargetType = 'DP_TroseckoSelectedTarget'
        targetProgressType = 'DP_TroseckoTargetProgress'
        searchObjective = 'dark_within_objt'
        evidenceObjective = 'dark_within_evidencet'
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
    $regionalNativeWiring = @(
        $nativeWiringManifest.regions |
            Where-Object { $_.region -eq $specification.region }
    )
    if ($regionalNativeWiring.Count -gt 1) {
        throw "Region '$($specification.region)' has multiple native case wirings."
    }
    New-RegionalQuest `
        -Candidates $regionalCandidates `
        -SearchAreas $regionalSearchAreas `
        -RegionId $specification.region `
        -QuestName $specification.quest `
        -SearchProgressTypeName $specification.searchProgressType `
        -EvidenceProgressTypeName $specification.evidenceProgressType `
        -CleanupProgressTypeName $specification.cleanupProgressType `
        -SelectedTargetTypeName $specification.selectedTargetType `
        -TargetProgressTypeName $specification.targetProgressType `
        -SearchObjectiveName $specification.searchObjective `
        -EvidenceObjectiveName $specification.evidenceObjective `
        -TargetObjectiveName $specification.targetObjective `
        -CleanupObjectiveName $specification.cleanupObjective `
        -QuestDescriptionKey $specification.descriptionKey `
        -RequestContext $specification.requestContext `
        -TargetDeathContext $specification.targetDeathContext `
        -OutputPath $specification.output `
        -Template $template `
        -PoseProbeDialogSourcePath $PoseProbeDialogSourcePath `
        -NativeWiring $(
            if ($regionalNativeWiring.Count -eq 1) {
                $regionalNativeWiring[0]
            }
            else { $null }
        )
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
