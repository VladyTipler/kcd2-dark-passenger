Set-StrictMode -Version Latest

$templateModulePath = Join-Path $PSScriptRoot 'CaseKit.Templates.psm1'
Import-Module $templateModulePath -Force

$script:CaseKitScenePresets = @(
    'standing-conversation',
    'seated-tavern',
    'lying-interrogation'
)
$script:CaseKitTrophyPresets = @(
    'bird-feather'
)
$script:CaseKitItemClassifications = @(
    'quest',
    'loot'
)
$script:CaseKitItemRetentions = @(
    'case',
    'permanent'
)
$script:CaseKitEvidencePlacementModes = @(
    'world-container',
    'actor-inventory',
    'actor-container',
    'actor-home-container'
)
$script:CaseKitGuidanceKindEntityTypes = [ordered]@{
    actor = @('actor')
    entity = @('container')
    place = @('container', 'settlement')
    area = @('settlement')
}
$script:CaseKitGuidanceKindPrecisions = [ordered]@{
    actor = @('exact', 'point')
    entity = @('exact', 'point')
    place = @('point', 'area')
    area = @('area')
}
$script:CaseKitGuidanceVisibilityModes = @(
    'step-active',
    'facts-known',
    'target-revealed'
)
$script:CaseKitGuidanceLifetimes = @('step', 'case')
$script:CaseKitGuidanceFallbacks = @(
    'journal-direction',
    'reject-variant'
)
$script:CaseKitLifecycleObjectiveStates = [ordered]@{
    search = @('active')
    investigation = @()
    target = @('active', 'done')
    cleanup = @(
        'active',
        'witnessed',
        'clean',
        'controlled',
        'noisy',
        'external'
    )
}
$script:CaseKitForbiddenNativeFields = @(
    'animation',
    'animationName',
    'cameraGuid',
    'coordinates',
    'entityGuid',
    'guid',
    'modelPath',
    'soulGuid',
    'worldPosition'
)

function Read-CaseKitAuthoringJson {
    param([Parameter(Mandatory)][string]$LiteralPath)

    try {
        return [System.IO.File]::ReadAllText($LiteralPath) |
            ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Invalid CaseKit JSON in '$LiteralPath': $($_.Exception.Message)"
    }
}

function Get-CaseKitAuthoringFiles {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Filter
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) {
        throw "CaseKit authoring root not found: $LiteralPath"
    }
    return @(Get-ChildItem -LiteralPath $LiteralPath -Filter $Filter -File |
        Sort-Object FullName)
}

function Get-CaseKitProperty {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Name
    )

    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-CaseKitPropertyNames {
    param([Parameter(Mandatory)]$Value)

    return @($Value.PSObject.Properties.Name)
}

function New-CaseKitEntryMap {
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string]$Kind
    )

    $map = [ordered]@{}
    foreach ($entry in $Entries) {
        $id = [string]$entry.value.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw "$Kind in '$($entry.path)' has no id."
        }
        if ($map.Contains($id)) {
            throw "Duplicate $Kind id '$id' in '$($entry.path)'."
        }
        $map[$id] = $entry
    }
    return $map
}

function Assert-CaseKitFactsExist {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$FactIds,
        [Parameter(Mandatory)]$FactMap,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath
    )

    foreach ($factId in $FactIds) {
        if (-not $FactMap.Contains([string]$factId)) {
            throw "$Context references unknown fact '$factId' in '$SourcePath'."
        }
    }
}

function Assert-CaseKitAssetReference {
    param(
        [Parameter(Mandatory)][string]$AssetKey,
        [Parameter(Mandatory)]$AssetKeys,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath
    )

    if (-not $AssetKeys.Contains($AssetKey)) {
        throw "$Context references unknown asset '$AssetKey' in '$SourcePath'."
    }
}

function Assert-CaseKitObjectivePresentation {
    param(
        $Presentation,
        [Parameter(Mandatory)]$AssetKeys,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AllowedStates,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath,
        [switch]$RequireActiveState
    )

    if ($null -eq $Presentation) { return }

    $nameAsset = [string](Get-CaseKitProperty `
        -Value $Presentation -Name 'nameAsset')
    if ([string]::IsNullOrWhiteSpace($nameAsset)) {
        throw "$Context requires nameAsset in '$SourcePath'."
    }
    Assert-CaseKitAssetReference -AssetKey $nameAsset -AssetKeys $AssetKeys `
        -Context $Context -SourcePath $SourcePath

    $states = Get-CaseKitProperty -Value $Presentation -Name 'states'
    if ($RequireActiveState -and
        ($null -eq $states -or
            $null -eq $states.PSObject.Properties['active'])) {
        throw "$Context requires objective state 'active' in '$SourcePath'."
    }
    if ($null -eq $states) { return }

    foreach ($state in $states.PSObject.Properties) {
        if ($AllowedStates -notcontains [string]$state.Name) {
            throw "$Context uses unsupported objective state " +
                "'$($state.Name)' in '$SourcePath'."
        }
        $assetKey = [string]$state.Value
        if ([string]::IsNullOrWhiteSpace($assetKey) -or
            -not $AssetKeys.Contains($assetKey)) {
            throw "$Context objective state '$($state.Name)' references " +
                "missing asset '$assetKey' in '$SourcePath'."
        }
    }
}

function Assert-CaseKitLifecycleObjectivePresentations {
    param(
        $Journal,
        [Parameter(Mandatory)]$AssetKeys,
        [Parameter(Mandatory)][string]$SourcePath
    )

    if ($null -eq $Journal) { return }
    $objectives = Get-CaseKitProperty -Value $Journal -Name 'objectives'
    if ($null -eq $objectives) {
        throw "Story journal requires objectives in '$SourcePath'."
    }

    foreach ($objective in $objectives.PSObject.Properties) {
        $objectiveId = [string]$objective.Name
        if (-not $script:CaseKitLifecycleObjectiveStates.Contains($objectiveId)) {
            throw "Story journal uses unknown lifecycle objective " +
                "'$objectiveId' in '$SourcePath'."
        }
        Assert-CaseKitObjectivePresentation -Presentation $objective.Value `
            -AssetKeys $AssetKeys `
            -AllowedStates $script:CaseKitLifecycleObjectiveStates[$objectiveId] `
            -Context "Lifecycle objective '$objectiveId'" `
            -SourcePath $SourcePath
    }
}

function Get-CaseKitComparableLocalizedText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

function Assert-CaseKitGuidanceObjectiveDistinctFromInvestigation {
    param(
        $GuidanceObjective,
        $InvestigationObjective,
        [Parameter(Mandatory)]$RussianAssets,
        [Parameter(Mandatory)]$EnglishAssets,
        [Parameter(Mandatory)][string]$QualifiedId,
        [Parameter(Mandatory)][string]$SourcePath
    )

    if ($null -eq $GuidanceObjective -or
        $null -eq $InvestigationObjective) {
        return
    }
    $guidanceAsset = [string](Get-CaseKitProperty `
        -Value $GuidanceObjective -Name 'nameAsset')
    $investigationAsset = [string](Get-CaseKitProperty `
        -Value $InvestigationObjective -Name 'nameAsset')
    if ($guidanceAsset -eq $investigationAsset) {
        throw "GuidanceTarget '$QualifiedId' objective duplicates lifecycle " +
            "investigation objective asset '$guidanceAsset' in " +
            "'$SourcePath'."
    }

    foreach ($language in @(
        [pscustomobject]@{ name = 'Russian'; assets = $RussianAssets },
        [pscustomobject]@{ name = 'English'; assets = $EnglishAssets }
    )) {
        $guidanceText = Get-CaseKitComparableLocalizedText -Value (
            [string](Get-CaseKitProperty -Value $language.assets `
                -Name $guidanceAsset)
        )
        $investigationText = Get-CaseKitComparableLocalizedText -Value (
            [string](Get-CaseKitProperty -Value $language.assets `
                -Name $investigationAsset)
        )
        if (-not [string]::IsNullOrWhiteSpace($guidanceText) -and
            $guidanceText -eq $investigationText) {
            throw "GuidanceTarget '$QualifiedId' objective duplicates " +
                "lifecycle investigation objective localized text " +
                "($($language.name)) in '$SourcePath'."
        }
    }
}

function Get-CaseKitContentAssetKeys {
    param([Parameter(Mandatory)]$Content)

    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($property in $Content.PSObject.Properties) {
        if ($property.Value -is [string]) {
            $keys.Add([string]$property.Value)
            continue
        }
        foreach ($value in @($property.Value)) {
            $keys.Add([string]$value)
        }
    }
    return $keys.ToArray()
}

function Assert-CaseKitTemplateContract {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Archetype,
        [Parameter(Mandatory)][string]$SourcePath
    )

    foreach ($language in @('ru', 'en')) {
        $assets = Get-CaseKitProperty -Value $Story.assets -Name $language
        foreach ($asset in $assets.PSObject.Properties) {
            foreach ($token in @(Get-CaseKitTemplateTokens `
                -Text ([string]$asset.Value))) {
                $slotProperty = $Archetype.slots.PSObject.Properties[$token.slot]
                if ($null -eq $slotProperty) {
                    throw "Unknown template slot '$($token.slot)' in asset " +
                        "'$($asset.Name)' in '$SourcePath'."
                }
                $slot = $slotProperty.Value
                if (@($slot.templateFields) -notcontains $token.field) {
                    throw "Template field '$($token.slot).$($token.field)' is " +
                        "not declared in '$SourcePath'."
                }
                if ($token.field -eq 'name' -and
                    @($slot.identityModes) -contains 'anonymous') {
                    throw "Template slot '$($token.slot)' may resolve to " +
                        "anonymous and cannot use field 'name' in '$SourcePath'."
                }
            }
        }
    }
}

function Assert-CaseKitLanguageAssets {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $ruKeys = @(Get-CaseKitPropertyNames -Value $Story.assets.ru | Sort-Object)
    $enKeys = @(Get-CaseKitPropertyNames -Value $Story.assets.en | Sort-Object)
    foreach ($key in $ruKeys) {
        if ($enKeys -notcontains $key) {
            throw "Story '$($Story.id)' in '$SourcePath' is missing English " +
                "asset key '$key'."
        }
    }
    foreach ($key in $enKeys) {
        if ($ruKeys -notcontains $key) {
            throw "Story '$($Story.id)' in '$SourcePath' is missing Russian " +
                "asset key '$key'."
        }
    }
}

function Assert-CaseKitEvidenceModules {
    param([Parameter(Mandatory)]$ModuleMap)

    foreach ($entry in $ModuleMap.Values) {
        $module = $entry.value
        if ($module.confidence.mode -ne 'one_shot') {
            throw "Evidence module '$($module.id)' in '$($entry.path)' must " +
                "use one_shot confidence."
        }
        if ([int]$module.confidence.minimum -gt
            [int]$module.confidence.maximum) {
            throw "Evidence module '$($module.id)' in '$($entry.path)' has " +
                'an invalid confidence range.'
        }
    }
}

function Assert-CaseKitNoNativeAuthoringFields {
    param(
        [Parameter(Mandatory)][AllowNull()]$Value,
        [Parameter(Mandatory)][string]$SourcePath
    )

    if ($null -eq $Value) { return }
    if ($Value -is [string] -or $Value -is [ValueType]) {
        return
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ($script:CaseKitForbiddenNativeFields -icontains [string]$key) {
                throw "StoryPack contains forbidden native field '$key' in " +
                    "'$SourcePath'."
            }
            Assert-CaseKitNoNativeAuthoringFields -Value $Value[$key] `
                -SourcePath $SourcePath
        }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            Assert-CaseKitNoNativeAuthoringFields -Value $item `
                -SourcePath $SourcePath
        }
        return
    }
    foreach ($property in $Value.PSObject.Properties) {
        if ($script:CaseKitForbiddenNativeFields -icontains $property.Name) {
            throw "StoryPack contains forbidden native field " +
                "'$($property.Name)' in '$SourcePath'."
        }
        Assert-CaseKitNoNativeAuthoringFields -Value $property.Value `
            -SourcePath $SourcePath
    }
}

function Read-CaseKitDefinitionDirectory {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Kind
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) {
        throw "CaseKit v2 $Kind directory not found: $LiteralPath"
    }
    return @(Get-ChildItem -LiteralPath $LiteralPath -Filter '*.json' -File |
        Sort-Object FullName | ForEach-Object {
            $value = Read-CaseKitAuthoringJson -LiteralPath $_.FullName
            Assert-CaseKitNoNativeAuthoringFields -Value $value `
                -SourcePath $_.FullName
            [pscustomobject]@{
                path = $_.FullName
                value = $value
            }
        })
}

function Assert-CaseKitV2Localization {
    param(
        [Parameter(Mandatory)]$Russian,
        [Parameter(Mandatory)]$English,
        [Parameter(Mandatory)][string]$RussianPath,
        [Parameter(Mandatory)][string]$EnglishPath
    )

    $ruKeys = @(Get-CaseKitPropertyNames -Value $Russian | Sort-Object)
    $enKeys = @(Get-CaseKitPropertyNames -Value $English | Sort-Object)
    foreach ($key in $ruKeys) {
        if ($enKeys -notcontains $key) {
            throw "StoryPack is missing English localization key '$key' in " +
                "'$EnglishPath'."
        }
    }
    foreach ($key in $enKeys) {
        if ($ruKeys -notcontains $key) {
            throw "StoryPack is missing Russian localization key '$key' in " +
                "'$RussianPath'."
        }
    }
}

function Assert-CaseKitV2TrophyDefinition {
    param(
        [Parameter(Mandatory)]$Case,
        [Parameter(Mandatory)]$AssetKeys,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $definition = Get-CaseKitProperty `
        -Value $Case -Name 'trophyDefinition'
    if ($null -eq $definition) { return }

    $preset = [string](Get-CaseKitProperty `
        -Value $definition -Name 'preset')
    if ($script:CaseKitTrophyPresets -notcontains $preset) {
        throw "Story '$($Case.id)' uses unknown trophy preset '$preset' " +
            "in '$SourcePath'."
    }
    $descriptionAsset = [string](Get-CaseKitProperty `
        -Value $definition -Name 'descriptionAsset')
    Assert-CaseKitAssetReference -AssetKey $descriptionAsset `
        -AssetKeys $AssetKeys `
        -Context "Story '$($Case.id)' TrophyDefinition" `
        -SourcePath $SourcePath

    $item = Get-CaseKitProperty -Value $definition -Name 'item'
    if ($null -eq $item) {
        throw "Story '$($Case.id)' TrophyDefinition requires item semantics " +
            "in '$SourcePath'."
    }
    $classification = [string](Get-CaseKitProperty `
        -Value $item -Name 'classification')
    if ($classification -ne 'loot') {
        throw "Story '$($Case.id)' TrophyDefinition must use loot item " +
            "classification in '$SourcePath'."
    }
    $retention = [string](Get-CaseKitProperty `
        -Value $item -Name 'retention')
    if ($retention -ne 'permanent') {
        throw "Story '$($Case.id)' TrophyDefinition must use permanent " +
            "retention in '$SourcePath'."
    }
    $weight = Get-CaseKitProperty -Value $item -Name 'weight'
    if ($null -eq $weight -or [double]$weight -ne 0) {
        throw "Story '$($Case.id)' TrophyDefinition must have zero weight " +
            "in '$SourcePath'."
    }
}

function Assert-CaseKitV2PhysicalItem {
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)]$Module,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $physicalItem = Get-CaseKitProperty -Value $Module -Name 'physicalItem'
    if ($physicalItem -ne $true) { return }

    $item = Get-CaseKitProperty -Value $Step.action -Name 'item'
    $classification = if ($null -eq $item) { '' } else {
        [string](Get-CaseKitProperty -Value $item -Name 'classification')
    }
    if ([string]::IsNullOrWhiteSpace($classification)) {
        throw "$Context physical item requires explicit classification in " +
            "'$SourcePath'."
    }
    if ($script:CaseKitItemClassifications -notcontains $classification) {
        throw "$Context uses unknown item classification '$classification' " +
            "in '$SourcePath'."
    }
    $retention = [string](Get-CaseKitProperty `
        -Value $item -Name 'retention')
    if ($script:CaseKitItemRetentions -notcontains $retention) {
        throw "$Context uses unknown item retention '$retention' in " +
            "'$SourcePath'."
    }
}

function Assert-CaseKitV2EvidencePlacement {
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)]$Module,
        [Parameter(Mandatory)]$Slots,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $physicalItem = Get-CaseKitProperty -Value $Module -Name 'physicalItem'
    $placement = Get-CaseKitProperty -Value $Step.action -Name 'placement'
    if ($physicalItem -ne $true) {
        if ($null -ne $placement) {
            throw "$Context declares placement for non-physical evidence " +
                "in '$SourcePath'."
        }
        return
    }
    if ($null -eq $placement) {
        throw "$Context physical item requires explicit placement in " +
            "'$SourcePath'."
    }

    $mode = [string](Get-CaseKitProperty -Value $placement -Name 'mode')
    if ($script:CaseKitEvidencePlacementModes -notcontains $mode) {
        throw "$Context uses unknown placement mode '$mode' in " +
            "'$SourcePath'."
    }
    if ($mode -eq 'world-container') { return }

    $actorSlotName = [string](Get-CaseKitProperty `
        -Value $placement -Name 'actor')
    if ([string]::IsNullOrWhiteSpace($actorSlotName)) {
        throw "$Context placement mode '$mode' requires actor slot in " +
            "'$SourcePath'."
    }
    $actorSlot = $Slots.PSObject.Properties[$actorSlotName]
    if ($null -eq $actorSlot) {
        throw "$Context placement references unknown actor slot " +
            "'$actorSlotName' in '$SourcePath'."
    }
    if ([string]$actorSlot.Value.entityType -ne 'actor') {
        throw "$Context placement slot '$actorSlotName' is not an actor in " +
            "'$SourcePath'."
    }
}

function Assert-CaseKitV2GuidanceTargets {
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)]$Slots,
        [Parameter(Mandatory)]$FactMap,
        [Parameter(Mandatory)]$AssetKeys,
        $InvestigationObjective,
        [Parameter(Mandatory)]$RussianAssets,
        [Parameter(Mandatory)]$EnglishAssets,
        [Parameter(Mandatory)][string]$ThreadId,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $ids = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($guidanceTarget in @($Step.guidance)) {
        $id = [string](Get-CaseKitProperty `
            -Value $guidanceTarget -Name 'id')
        $qualifiedId = "$ThreadId/$([string]$Step.id)/$id"
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw "$Context contains a GuidanceTarget without id in " +
                "'$SourcePath'."
        }
        if (-not $ids.Add($id)) {
            throw "$Context contains duplicate GuidanceTarget '$id' in " +
                "'$SourcePath'."
        }

        $target = Get-CaseKitProperty `
            -Value $guidanceTarget -Name 'target'
        $kind = [string](Get-CaseKitProperty -Value $target -Name 'kind')
        if (-not $script:CaseKitGuidanceKindEntityTypes.Contains($kind)) {
            throw "GuidanceTarget '$qualifiedId' uses unknown kind '$kind' " +
                "in '$SourcePath'."
        }
        $slotName = [string](Get-CaseKitProperty `
            -Value $target -Name 'slot')
        $slot = $Slots.PSObject.Properties[$slotName]
        if ($null -eq $slot) {
            throw "GuidanceTarget '$qualifiedId' references unknown slot " +
                "'$slotName' in '$SourcePath'."
        }
        $entityType = [string]$slot.Value.entityType
        if (@($script:CaseKitGuidanceKindEntityTypes[$kind]) -notcontains
            $entityType) {
            throw "GuidanceTarget '$qualifiedId' kind '$kind' is " +
                "incompatible with slot '$slotName' entity type " +
                "'$entityType' in '$SourcePath'."
        }

        $precision = [string](Get-CaseKitProperty `
            -Value $guidanceTarget -Name 'precision')
        if (@($script:CaseKitGuidanceKindPrecisions[$kind]) -notcontains
            $precision) {
            throw "GuidanceTarget '$qualifiedId' precision '$precision' is " +
                "incompatible with kind '$kind' in '$SourcePath'."
        }

        $areaSelection = [string](Get-CaseKitProperty `
            -Value $target -Name 'areaSelection')
        $anchorSlotValues = Get-CaseKitProperty `
            -Value $target -Name 'anchorSlots'
        $anchorSlots = @($anchorSlotValues | Where-Object {
            $null -ne $_
        } | ForEach-Object { [string]$_ })
        if (-not [string]::IsNullOrWhiteSpace($areaSelection) -or
            $anchorSlots.Count -gt 0) {
            if ($kind -ne 'area' -or $precision -ne 'area') {
                throw "GuidanceTarget '$qualifiedId' local area selection " +
                    "requires kind 'area' and precision 'area' in " +
                    "'$SourcePath'."
            }
            if ($areaSelection -ne 'smallest-common') {
                throw "GuidanceTarget '$qualifiedId' uses unknown area " +
                    "selection '$areaSelection' in '$SourcePath'."
            }
            if ($anchorSlots.Count -eq 0) {
                throw "GuidanceTarget '$qualifiedId' smallest-common area " +
                    "selection requires anchorSlots in '$SourcePath'."
            }
            if (@($anchorSlots | Sort-Object -Unique).Count -ne
                $anchorSlots.Count) {
                throw "GuidanceTarget '$qualifiedId' contains duplicate " +
                    "anchorSlots in '$SourcePath'."
            }
            foreach ($anchorSlotName in $anchorSlots) {
                $anchorSlot = $Slots.PSObject.Properties[$anchorSlotName]
                if ($null -eq $anchorSlot) {
                    throw "GuidanceTarget '$qualifiedId' references unknown " +
                        "area anchor slot '$anchorSlotName' in '$SourcePath'."
                }
                if ([string]$anchorSlot.Value.entityType -ne 'actor') {
                    throw "GuidanceTarget '$qualifiedId' area anchor slot " +
                        "'$anchorSlotName' is not an actor in '$SourcePath'."
                }
            }
        }

        $visibility = $guidanceTarget.visibility
        $visibilityMode = [string]$visibility.mode
        if ($script:CaseKitGuidanceVisibilityModes -notcontains
            $visibilityMode) {
            throw "GuidanceTarget '$qualifiedId' uses unknown visibility " +
                "mode '$visibilityMode' in '$SourcePath'."
        }
        $visibilityFacts = @($visibility.requiresFacts)
        Assert-CaseKitFactsExist -FactIds $visibilityFacts `
            -FactMap $FactMap -Context "GuidanceTarget '$qualifiedId'" `
            -SourcePath $SourcePath
        if ($visibilityMode -eq 'facts-known' -and
            $visibilityFacts.Count -eq 0) {
            throw "GuidanceTarget '$qualifiedId' facts-known visibility " +
                "requires at least one fact in '$SourcePath'."
        }

        if ($precision -eq 'exact' -and
            @($slot.Value.capabilities) -contains 'victim.eligible' -and
            $visibilityMode -ne 'target-revealed') {
            throw "GuidanceTarget '$qualifiedId' exposes an exact victim " +
                "before target-revealed visibility in '$SourcePath'."
        }

        $lifetime = [string]$guidanceTarget.lifetime
        if ($script:CaseKitGuidanceLifetimes -notcontains $lifetime) {
            throw "GuidanceTarget '$qualifiedId' uses unknown lifetime " +
                "'$lifetime' in '$SourcePath'."
        }
        $fallback = [string]$guidanceTarget.fallback
        if ($script:CaseKitGuidanceFallbacks -notcontains $fallback) {
            throw "GuidanceTarget '$qualifiedId' uses unknown fallback " +
                "'$fallback' in '$SourcePath'."
        }

        $objective = Get-CaseKitProperty `
            -Value $guidanceTarget -Name 'objective'
        Assert-CaseKitObjectivePresentation -Presentation $objective `
            -AssetKeys $AssetKeys -AllowedStates @('active') `
            -Context "GuidanceTarget '$qualifiedId'" `
            -SourcePath $SourcePath -RequireActiveState
        Assert-CaseKitGuidanceObjectiveDistinctFromInvestigation `
            -GuidanceObjective $objective `
            -InvestigationObjective $InvestigationObjective `
            -RussianAssets $RussianAssets -EnglishAssets $EnglishAssets `
            -QualifiedId $qualifiedId -SourcePath $SourcePath
    }
}

function Assert-CaseKitV2DialogueMedia {
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $mediaProperty = $Definition.PSObject.Properties['media']
    if ($null -eq $mediaProperty) { return }
    $media = $mediaProperty.Value
    $voice = [string](Get-CaseKitProperty -Value $media -Name 'voice')
    if ($voice -cne 'native') {
        throw "Dialogue '$($Definition.id)' uses unsupported voice mode " +
            "'$voice' in '$SourcePath'."
    }
    $lipSyncProperty = $media.PSObject.Properties['lipSync']
    if ($null -eq $lipSyncProperty -or -not [bool]$lipSyncProperty.Value) {
        throw "Dialogue '$($Definition.id)' native voice requires lipSync " +
            "in '$SourcePath'."
    }
    $unknown = @($media.PSObject.Properties | Where-Object {
        $_.Name -notin @('voice', 'lipSync')
    } | Select-Object -First 1)
    if ($unknown.Count -gt 0) {
        throw "Dialogue '$($Definition.id)' uses unknown media field " +
            "'$($unknown[0].Name)' in '$SourcePath'."
    }
}

function Assert-CaseKitV2DefinitionAssets {
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)]$AssetKeys,
        [Parameter(Mandatory)][bool]$RequireScenePreset
    )

    foreach ($entry in $Entries) {
        $definition = $entry.value
        if ($RequireScenePreset) {
            $preset = [string](Get-CaseKitProperty `
                -Value $definition -Name 'scenePreset')
            if ($script:CaseKitScenePresets -notcontains $preset) {
                throw "Definition '$($definition.id)' uses unknown scene " +
                    "preset '$preset' in '$($entry.path)'."
            }
            Assert-CaseKitV2DialogueMedia -Definition $definition `
                -SourcePath $entry.path
        }
        foreach ($key in @($definition.localizationKeys)) {
            Assert-CaseKitAssetReference -AssetKey ([string]$key) `
                -AssetKeys $AssetKeys `
                -Context "Definition '$($definition.id)'" `
                -SourcePath $entry.path
        }
    }
}

function ConvertTo-CaseKitNormalizedReveal {
    param(
        [Parameter(Mandatory)]$Reveal,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $requiredFactsProperty = $Reveal.PSObject.Properties['requiredFacts']
    $identityProperty = $Reveal.PSObject.Properties['identityRequirement']
    if ($null -ne $requiredFactsProperty -and $null -ne $identityProperty) {
        throw "Story reveal defines both 'requiredFacts' and " +
            "'identityRequirement' in '$SourcePath'."
    }

    $mode = $null
    $factIds = @()
    if ($null -ne $requiredFactsProperty) {
        $mode = 'allOf'
        $factIds = @($requiredFactsProperty.Value)
    }
    elseif ($null -ne $identityProperty) {
        $identityRequirement = $identityProperty.Value
        $properties = @($identityRequirement.PSObject.Properties)
        $supported = @($properties | Where-Object {
            $_.Name -in @('allOf', 'anyOf')
        })
        $unknown = @($properties | Where-Object {
            $_.Name -notin @('allOf', 'anyOf')
        })
        if ($unknown.Count -gt 0) {
            throw "Story reveal uses unknown identity requirement " +
                "'$($unknown[0].Name)' in '$SourcePath'."
        }
        if ($supported.Count -ne 1) {
            throw 'Story reveal identityRequirement must define exactly one ' +
                "of 'allOf' or 'anyOf' in '$SourcePath'."
        }
        $mode = [string]$supported[0].Name
        $factIds = @($supported[0].Value)
    }
    else {
        throw "Story reveal requires 'identityRequirement' in '$SourcePath'."
    }

    if ($factIds.Count -eq 0) {
        throw "Story reveal identityRequirement.$mode must contain at least " +
            "one fact in '$SourcePath'."
    }
    $normalizedFactIds = @($factIds | ForEach-Object { [string]$_ })
    if (@($normalizedFactIds | Where-Object {
        [string]::IsNullOrWhiteSpace($_)
    }).Count -gt 0) {
        throw "Story reveal identityRequirement.$mode contains an empty fact " +
            "in '$SourcePath'."
    }
    if (@($normalizedFactIds | Sort-Object -Unique).Count -ne
        $normalizedFactIds.Count) {
        throw "Story reveal identityRequirement.$mode contains duplicate " +
            "facts in '$SourcePath'."
    }

    $identityRequirement = [ordered]@{}
    $identityRequirement[$mode] = $normalizedFactIds
    return [pscustomobject][ordered]@{
        confidence = [int]$Reveal.confidence
        identityRequirement = [pscustomobject]$identityRequirement
    }
}

function Get-CaseKitIdentityRequirement {
    param([Parameter(Mandatory)]$Reveal)

    $property = @($Reveal.identityRequirement.PSObject.Properties)[0]
    return [pscustomobject][ordered]@{
        mode = [string]$property.Name
        factIds = @($property.Value | ForEach-Object { [string]$_ })
    }
}

function ConvertTo-CaseKitNormalizedGuidanceTargets {
    param($GuidanceTargets)

    $normalized = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $GuidanceTargets) {
        return $normalized.ToArray()
    }
    foreach ($guidanceTarget in @($GuidanceTargets)) {
        $copy = ($guidanceTarget | ConvertTo-Json -Depth 100) |
            ConvertFrom-Json -Depth 100
        $visibility = Get-CaseKitProperty -Value $copy -Name 'visibility'
        if ($null -eq $visibility) {
            $visibility = [pscustomobject][ordered]@{
                mode = 'step-active'
                requiresFacts = @()
            }
            $copy | Add-Member -NotePropertyName visibility `
                -NotePropertyValue $visibility
        }
        else {
            if ([string]::IsNullOrWhiteSpace([string](
                Get-CaseKitProperty -Value $visibility -Name 'mode'
            ))) {
                $visibility | Add-Member -NotePropertyName mode `
                    -NotePropertyValue 'step-active' -Force
            }
            if ($null -eq $visibility.PSObject.Properties['requiresFacts']) {
                $visibility | Add-Member -NotePropertyName requiresFacts `
                    -NotePropertyValue @()
            }
        }
        if ($null -eq $copy.PSObject.Properties['lifetime']) {
            $copy | Add-Member -NotePropertyName lifetime `
                -NotePropertyValue 'step'
        }
        if ($null -eq $copy.PSObject.Properties['fallback']) {
            $copy | Add-Member -NotePropertyName fallback `
                -NotePropertyValue 'journal-direction'
        }
        $normalized.Add($copy)
    }
    return $normalized.ToArray()
}

function ConvertTo-CaseKitNormalizedThreads {
    param([Parameter(Mandatory)][object[]]$Threads)

    foreach ($thread in $Threads) {
        foreach ($step in @($thread.steps)) {
            $guidanceTargets = Get-CaseKitProperty `
                -Value $step -Name 'guidance'
            $step | Add-Member -NotePropertyName guidance `
                -NotePropertyValue @(
                    ConvertTo-CaseKitNormalizedGuidanceTargets `
                        -GuidanceTargets $guidanceTargets
                ) -Force
        }
    }
    return $Threads
}

function Assert-CaseKitV2StoryIdentities {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Slots,
        [Parameter(Mandatory)]$FactMap,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $identityIds = [ordered]@{}
    $identitySlots = [ordered]@{}
    foreach ($identity in @(Get-CaseKitProperty `
        -Value $Story -Name 'storyIdentities')) {
        if ($null -eq $identity) { continue }
        $identityId = [string](Get-CaseKitProperty `
            -Value $identity -Name 'id')
        if ([string]::IsNullOrWhiteSpace($identityId)) {
            throw "Story identity without id in '$SourcePath'."
        }
        if ($identityIds.Contains($identityId)) {
            throw "Duplicate story identity '$identityId' in '$SourcePath'."
        }
        $identityIds[$identityId] = $true

        $bindingSlot = [string](Get-CaseKitProperty `
            -Value $identity -Name 'bindingSlot')
        $slotProperty = $Slots.PSObject.Properties[$bindingSlot]
        if ([string]::IsNullOrWhiteSpace($bindingSlot) -or
            $null -eq $slotProperty) {
            throw "Story identity '$identityId' references unknown binding " +
                "slot '$bindingSlot' in '$SourcePath'."
        }
        if ([string]$slotProperty.Value.entityType -ne 'actor') {
            throw "Story identity '$identityId' binding slot " +
                "'$bindingSlot' is not an actor in '$SourcePath'."
        }
        if ($identitySlots.Contains($bindingSlot)) {
            throw "Story identities '$($identitySlots[$bindingSlot])' and " +
                "'$identityId' both bind slot '$bindingSlot' in " +
                "'$SourcePath'."
        }
        $identitySlots[$bindingSlot] = $identityId

        $revealFact = [string](Get-CaseKitProperty `
            -Value $identity -Name 'revealFact')
        if (-not $FactMap.Contains($revealFact)) {
            throw "Story identity '$identityId' references unknown reveal " +
                "fact '$revealFact' in '$SourcePath'."
        }
        if ((Get-CaseKitProperty -Value $FactMap[$revealFact] `
            -Name 'hardIdentity') -ne $true) {
            throw "Story identity '$identityId' reveal fact '$revealFact' " +
                "is not a hard identity fact in '$SourcePath'."
        }

        $localized = Get-CaseKitProperty `
            -Value $identity -Name 'localized'
        foreach ($language in @('ru', 'en')) {
            $languageProperty = if ($null -eq $localized) {
                $null
            }
            else {
                $localized.PSObject.Properties[$language]
            }
            if ($null -eq $languageProperty) {
                throw "Story identity '$identityId' is missing '$language' " +
                    "localization in '$SourcePath'."
            }
            $name = [string](Get-CaseKitProperty `
                -Value $languageProperty.Value -Name 'name')
            $displayTemplate = [string](Get-CaseKitProperty `
                -Value $languageProperty.Value -Name 'displayTemplate')
            if ([string]::IsNullOrWhiteSpace($name) -or
                [string]::IsNullOrWhiteSpace($displayTemplate)) {
                throw "Story identity '$identityId' has incomplete " +
                    "'$language' localization in '$SourcePath'."
            }
        }
    }
}

function Read-CaseKitV2StoryPackage {
    param([Parameter(Mandatory)][string]$CasePath)

    $packageRoot = Split-Path -Parent $CasePath
    $threadsPath = Join-Path $packageRoot 'threads.json'
    $russianPath = Join-Path $packageRoot 'localization\ru.json'
    $englishPath = Join-Path $packageRoot 'localization\en.json'
    foreach ($requiredPath in @($threadsPath, $russianPath, $englishPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "CaseKit v2 package file not found: $requiredPath"
        }
    }

    $case = Read-CaseKitAuthoringJson -LiteralPath $CasePath
    $threads = Read-CaseKitAuthoringJson -LiteralPath $threadsPath
    $russian = Read-CaseKitAuthoringJson -LiteralPath $russianPath
    $english = Read-CaseKitAuthoringJson -LiteralPath $englishPath
    foreach ($source in @(
        [pscustomobject]@{ value = $case; path = $CasePath },
        [pscustomobject]@{ value = $threads; path = $threadsPath }
    )) {
        Assert-CaseKitNoNativeAuthoringFields -Value $source.value `
            -SourcePath $source.path
    }
    if ([int]$case.schemaVersion -ne 2 -or
        [int]$threads.schemaVersion -ne 2) {
        throw "CaseKit v2 package requires schemaVersion 2 in '$CasePath'."
    }
    if ([string]$threads.storyId -ne [string]$case.id) {
        throw "threads.json storyId '$($threads.storyId)' does not match " +
            "'$($case.id)' in '$threadsPath'."
    }

    Assert-CaseKitV2Localization -Russian $russian -English $english `
        -RussianPath $russianPath -EnglishPath $englishPath
    Assert-CaseKitV2TrophyDefinition -Case $case `
        -AssetKeys $russian.PSObject.Properties.Name `
        -SourcePath $CasePath
    $reveal = ConvertTo-CaseKitNormalizedReveal -Reveal $case.reveal `
        -SourcePath $CasePath
    $dialogueEntries = @(Read-CaseKitDefinitionDirectory `
        -LiteralPath (Join-Path $packageRoot 'dialogues') -Kind 'dialogues')
    $documentEntries = @(Read-CaseKitDefinitionDirectory `
        -LiteralPath (Join-Path $packageRoot 'documents') -Kind 'documents')
    $null = New-CaseKitEntryMap -Entries $dialogueEntries `
        -Kind 'dialogue definition'
    $null = New-CaseKitEntryMap -Entries $documentEntries `
        -Kind 'document definition'
    $assetKeys = $russian.PSObject.Properties.Name
    Assert-CaseKitV2DefinitionAssets -Entries $dialogueEntries `
        -AssetKeys $assetKeys -RequireScenePreset $true
    Assert-CaseKitV2DefinitionAssets -Entries $documentEntries `
        -AssetKeys $assetKeys -RequireScenePreset $false

    return [pscustomobject][ordered]@{
        schemaVersion = 2
        id = [string]$case.id
        status = [string]$case.status
        archetypes = @($case.archetypes)
        truth = $case.truth
        facts = @($case.facts)
        reveal = $reveal
        storyIdentities = @(
            Get-CaseKitProperty -Value $case -Name 'storyIdentities'
        )
        journal = Get-CaseKitProperty -Value $case -Name 'journal'
        trophyDefinition = Get-CaseKitProperty `
            -Value $case -Name 'trophyDefinition'
        threads = @(ConvertTo-CaseKitNormalizedThreads `
            -Threads @($threads.threads))
        dialogues = @($dialogueEntries.value | Sort-Object id)
        documents = @($documentEntries.value | Sort-Object id)
        assets = [pscustomobject][ordered]@{
            ru = $russian
            en = $english
        }
        packageSources = [pscustomobject][ordered]@{
            case = $CasePath
            threads = $threadsPath
            russian = $russianPath
            english = $englishPath
        }
    }
}

function ConvertTo-CaseKitNormalizedStory {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)][int]$SourceSchemaVersion
    )

    $normalized = ($Story | ConvertTo-Json -Depth 100) |
        ConvertFrom-Json -Depth 100
    $archetypeCompositions = if ($SourceSchemaVersion -eq 1) {
        @($Story.compatibleArchetypes | ForEach-Object {
            [pscustomobject][ordered]@{
                id = "legacy-$([string]$_)"
                archetypeIds = @([string]$_)
            }
        })
    }
    else {
        @([pscustomobject][ordered]@{
            id = 'default'
            archetypeIds = @($Story.archetypes | ForEach-Object {
                [string]$_
            })
        })
    }
    $normalized | Add-Member -NotePropertyName schemaVersion `
        -NotePropertyValue 2 -Force
    $normalized | Add-Member -NotePropertyName sourceSchemaVersion `
        -NotePropertyValue $SourceSchemaVersion -Force
    $normalized | Add-Member -NotePropertyName archetypeCompositions `
        -NotePropertyValue $archetypeCompositions -Force
    if ($null -eq $normalized.PSObject.Properties['dialogues']) {
        $normalized | Add-Member -NotePropertyName dialogues `
            -NotePropertyValue @()
    }
    if ($null -eq $normalized.PSObject.Properties['documents']) {
        $normalized | Add-Member -NotePropertyName documents `
            -NotePropertyValue @()
    }
    if ($null -eq $normalized.PSObject.Properties['storyIdentities']) {
        $normalized | Add-Member -NotePropertyName storyIdentities `
            -NotePropertyValue @()
    }
    return $normalized
}

function Assert-CaseKitV2TimedAreaAction {
    param(
        [Parameter(Mandatory)]$Step,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][string]$SourcePath
    )

    if ([string]$Step.action.evidenceModule -ne 'timed-area-listening') {
        return
    }
    $activation = Get-CaseKitProperty `
        -Value $Step.action -Name 'activation'
    if ($null -eq $activation) {
        throw "$Context requires explicit activation mode for " +
            "timed-area-listening in '$SourcePath'."
    }
    $mode = [string](Get-CaseKitProperty `
        -Value $activation -Name 'mode')
    if ([string]::IsNullOrWhiteSpace($mode)) {
        throw "$Context requires explicit activation mode for " +
            "timed-area-listening in '$SourcePath'."
    }
    if ($mode -ne 'timed-area-action') {
        throw "$Context uses unsupported timed area activation mode " +
            "'$mode' in '$SourcePath'."
    }
    $fromValue = Get-CaseKitProperty -Value $activation `
        -Name 'availableFromHour'
    $untilValue = Get-CaseKitProperty -Value $activation `
        -Name 'availableUntilHour'
    $durationValue = Get-CaseKitProperty -Value $activation `
        -Name 'durationHours'
    $from = if ($null -eq $fromValue) { -1 } else { [int]$fromValue }
    $until = if ($null -eq $untilValue) { -1 } else { [int]$untilValue }
    $duration = if ($null -eq $durationValue) { 0 } else { [int]$durationValue }
    if ($from -lt 0 -or $from -gt 23 -or
        $until -lt 1 -or $until -gt 24 -or $from -ge $until) {
        throw "$Context has invalid timed area working hours " +
            "'$from..$until' in '$SourcePath'."
    }
    if ($duration -lt 1 -or $duration -gt 24) {
        throw "$Context has invalid timed area duration '$duration' in " +
            "'$SourcePath'."
    }
    $areaGuidance = @($Step.guidance | Where-Object {
        [string]$_.target.kind -eq 'area' -and
        [string]$_.precision -eq 'area'
    })
    if ($areaGuidance.Count -ne 1) {
        throw "$Context requires exactly one area GuidanceTarget in " +
            "'$SourcePath'."
    }
}

function Merge-CaseKitV2ArchetypeSlots {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$ArchetypeMap,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $slots = [ordered]@{}
    foreach ($archetypeId in @($Story.archetypes)) {
        if (-not $ArchetypeMap.Contains([string]$archetypeId)) {
            throw "Story '$($Story.id)' references unknown archetype " +
                "'$archetypeId' in '$SourcePath'."
        }
        $archetype = $ArchetypeMap[[string]$archetypeId].value
        foreach ($slot in $archetype.slots.PSObject.Properties) {
            if (-not $slots.Contains($slot.Name)) {
                $slots[$slot.Name] = $slot.Value
                continue
            }
            $existing = $slots[$slot.Name] | ConvertTo-Json -Depth 20 -Compress
            $candidate = $slot.Value | ConvertTo-Json -Depth 20 -Compress
            if ($existing -ne $candidate) {
                throw "Composed archetypes define incompatible slot " +
                    "'$($slot.Name)' in '$SourcePath'."
            }
        }
    }
    return [pscustomobject]$slots
}

function Get-CaseKitV2Reachability {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$ArchetypeMap
    )

    $knownFacts = [System.Collections.Generic.HashSet[string]]::new()
    $activeThreads = [System.Collections.Generic.HashSet[string]]::new()
    $unlockedThreads = [System.Collections.Generic.HashSet[string]]::new()
    $scoredSteps = [System.Collections.Generic.HashSet[string]]::new()
    $structuralSteps = [ordered]@{}
    foreach ($thread in @($Story.threads)) {
        $stepMap = [ordered]@{}
        foreach ($step in @($thread.steps)) {
            $stepMap[[string]$step.id] = $step
        }
        $reachable = [System.Collections.Generic.HashSet[string]]::new()
        $pending = [System.Collections.Generic.Queue[string]]::new()
        foreach ($entryStepId in @($thread.entryStepIds)) {
            $pending.Enqueue([string]$entryStepId)
        }
        while ($pending.Count -gt 0) {
            $stepId = $pending.Dequeue()
            if (-not $reachable.Add($stepId)) {
                continue
            }
            foreach ($nextStepId in @($stepMap[$stepId].result.nextStepIds)) {
                $pending.Enqueue([string]$nextStepId)
            }
        }
        $structuralSteps[[string]$thread.id] = $reachable
    }

    $total = 0
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($thread in @($Story.threads)) {
            $threadId = [string]$thread.id
            if (-not $activeThreads.Contains($threadId)) {
                $leadFacts = @($thread.lead.requiresFacts)
                $leadSatisfied = $true
                foreach ($factId in $leadFacts) {
                    if (-not $knownFacts.Contains([string]$factId)) {
                        $leadSatisfied = $false
                        break
                    }
                }
                $mode = [string]$thread.lead.mode
                $startsNaturally = $mode -in @('case_start', 'ambient')
                $startsFromFact = $mode -eq 'fact' -and $leadFacts.Count -gt 0
                if ($leadSatisfied -and (
                    $startsNaturally -or $startsFromFact -or
                    $unlockedThreads.Contains($threadId)
                )) {
                    $null = $activeThreads.Add($threadId)
                    $changed = $true
                }
            }
            if (-not $activeThreads.Contains($threadId)) {
                continue
            }

            $archetype = $ArchetypeMap[
                [string]$thread.archetypeId
            ].value
            foreach ($step in @($thread.steps)) {
                $stepId = [string]$step.id
                $stepKey = "$threadId/$stepId"
                if ($scoredSteps.Contains($stepKey) -or
                    -not $structuralSteps[$threadId].Contains($stepId)) {
                    continue
                }
                $requirements = @($thread.lead.requiresFacts) +
                    @($step.requiresFacts)
                $canRun = $true
                foreach ($factId in $requirements) {
                    if (-not $knownFacts.Contains([string]$factId)) {
                        $canRun = $false
                        break
                    }
                }
                if (-not $canRun) {
                    continue
                }
                $null = $scoredSteps.Add($stepKey)
                $rule = $archetype.evidenceRules.PSObject.Properties[
                    [string]$step.action.evidenceModule
                ]
                $total += [int]$rule.Value.confidence
                foreach ($factId in @($step.result.revealsFacts)) {
                    $null = $knownFacts.Add([string]$factId)
                }
                foreach ($unlockedId in @($step.result.unlockThreadIds)) {
                    $null = $unlockedThreads.Add([string]$unlockedId)
                }
                $changed = $true
            }
        }
    }

    return [pscustomobject][ordered]@{
        maximumReachableConfidence = $total
        knownFacts = @($knownFacts | Sort-Object)
        activeThreads = @($activeThreads | Sort-Object)
    }
}

function Assert-CaseKitV2StoryContract {
    param(
        [Parameter(Mandatory)]$StoryEntry,
        [Parameter(Mandatory)]$ArchetypeMap,
        [Parameter(Mandatory)]$ModuleMap
    )

    $story = $StoryEntry.value
    $casePath = [string]$story.packageSources.case
    $threadsPath = [string]$story.packageSources.threads
    $factMap = [ordered]@{}
    $journal = Get-CaseKitProperty -Value $story -Name 'journal'
    Assert-CaseKitLifecycleObjectivePresentations `
        -Journal $journal `
        -AssetKeys $story.assets.ru.PSObject.Properties.Name `
        -SourcePath $casePath
    $journalObjectives = if ($null -eq $journal) { $null } else {
        Get-CaseKitProperty -Value $journal -Name 'objectives'
    }
    $investigationObjective = if ($null -eq $journalObjectives) {
        $null
    }
    else {
        Get-CaseKitProperty -Value $journalObjectives -Name 'investigation'
    }
    foreach ($fact in @($story.facts)) {
        $factId = [string]$fact.id
        if ([string]::IsNullOrWhiteSpace($factId)) {
            throw "Story '$($story.id)' contains a fact without id in " +
                "'$casePath'."
        }
        if ($factMap.Contains($factId)) {
            throw "Duplicate fact '$factId' in '$casePath'."
        }
        $factMap[$factId] = $fact
    }
    $identityRequirement = Get-CaseKitIdentityRequirement `
        -Reveal $story.reveal
    Assert-CaseKitFactsExist -FactIds @($identityRequirement.factIds) `
        -FactMap $factMap -Context "Story '$($story.id)' reveal" `
        -SourcePath $casePath
    foreach ($factId in @($identityRequirement.factIds)) {
        $hardIdentity = Get-CaseKitProperty -Value $factMap[[string]$factId] `
            -Name 'hardIdentity'
        if ($hardIdentity -ne $true) {
            $factKind = if ($identityRequirement.mode -eq 'allOf') {
                'required reveal fact'
            }
            else {
                'identity fact'
            }
            throw "Story '$($story.id)' $factKind '$factId' is not a hard " +
                "identity fact in '$casePath'."
        }
    }

    $mergedSlots = Merge-CaseKitV2ArchetypeSlots -Story $story `
        -ArchetypeMap $ArchetypeMap -SourcePath $casePath
    Assert-CaseKitV2StoryIdentities -Story $story -Slots $mergedSlots `
        -FactMap $factMap -SourcePath $casePath
    $templateArchetype = [pscustomobject]@{ slots = $mergedSlots }
    Assert-CaseKitTemplateContract -Story $story `
        -Archetype $templateArchetype -SourcePath $casePath

    $threadMap = [ordered]@{}
    foreach ($thread in @($story.threads)) {
        $threadId = [string]$thread.id
        if ([string]::IsNullOrWhiteSpace($threadId)) {
            throw "Story '$($story.id)' contains a thread without id in " +
                "'$threadsPath'."
        }
        if ($threadMap.Contains($threadId)) {
            throw "Duplicate thread '$threadId' in '$threadsPath'."
        }
        $threadMap[$threadId] = $thread
    }

    $moduleCountsByArchetype = [ordered]@{}
    foreach ($archetypeId in @($story.archetypes)) {
        $moduleCountsByArchetype[[string]$archetypeId] = [ordered]@{}
    }
    foreach ($thread in @($story.threads)) {
        $threadId = [string]$thread.id
        $archetypeId = [string]$thread.archetypeId
        if (@($story.archetypes) -notcontains $archetypeId -or
            -not $ArchetypeMap.Contains($archetypeId)) {
            throw "Thread '$threadId' references uncomposed archetype " +
                "'$archetypeId' in '$threadsPath'."
        }
        $archetype = $ArchetypeMap[$archetypeId].value
        if (@($archetype.threadRules.allowedLeadModes) -notcontains
            [string]$thread.lead.mode) {
            throw "Thread '$threadId' uses unsupported lead mode " +
                "'$($thread.lead.mode)' in '$threadsPath'."
        }
        Assert-CaseKitFactsExist -FactIds @($thread.lead.requiresFacts) `
            -FactMap $factMap -Context "Thread '$threadId' lead" `
            -SourcePath $threadsPath
        Assert-CaseKitAssetReference `
            -AssetKey ([string]$thread.lead.directionAsset) `
            -AssetKeys $story.assets.ru.PSObject.Properties.Name `
            -Context "Thread '$threadId' lead" -SourcePath $threadsPath

        $stepMap = [ordered]@{}
        foreach ($step in @($thread.steps)) {
            $stepId = [string]$step.id
            if ($stepMap.Contains($stepId)) {
                throw "Duplicate step '$stepId' in thread '$threadId' in " +
                    "'$threadsPath'."
            }
            $stepMap[$stepId] = $step
        }
        foreach ($entryStepId in @($thread.entryStepIds)) {
            if (-not $stepMap.Contains([string]$entryStepId)) {
                throw "Thread '$threadId' has unknown entry step " +
                    "'$entryStepId' in '$threadsPath'."
            }
        }

        foreach ($step in @($thread.steps)) {
            $context = "Step '$threadId/$($step.id)'"
            if (@($archetype.threadRules.allowedStepKinds) -notcontains
                [string]$step.kind) {
                throw "$context uses unsupported kind '$($step.kind)' in " +
                    "'$threadsPath'."
            }
            $moduleId = [string]$step.action.evidenceModule
            if (-not $ModuleMap.Contains($moduleId)) {
                throw "Unknown evidence module '$moduleId' in $context in " +
                    "'$threadsPath'."
            }
            $rule = $archetype.evidenceRules.PSObject.Properties[$moduleId]
            if ($null -eq $rule) {
                throw "Archetype '$archetypeId' does not allow evidence " +
                    "module '$moduleId' in '$threadsPath'."
            }
            $module = $ModuleMap[$moduleId].value
            Assert-CaseKitV2TimedAreaAction -Step $step `
                -Context $context -SourcePath $threadsPath
            Assert-CaseKitV2PhysicalItem -Step $step -Module $module `
                -Context $context -SourcePath $threadsPath
            Assert-CaseKitV2EvidencePlacement -Step $step -Module $module `
                -Slots $mergedSlots -Context $context `
                -SourcePath $threadsPath
            Assert-CaseKitV2GuidanceTargets -Step $step `
                -Slots $mergedSlots -FactMap $factMap `
                -AssetKeys $story.assets.ru.PSObject.Properties.Name `
                -InvestigationObjective $investigationObjective `
                -RussianAssets $story.assets.ru `
                -EnglishAssets $story.assets.en `
                -ThreadId $threadId -Context $context `
                -SourcePath $threadsPath
            if ([string]$module.stepKind -ne [string]$step.kind) {
                throw "Evidence module '$moduleId' requires step kind " +
                    "'$($module.stepKind)', got '$($step.kind)' in $context " +
                    "in '$threadsPath'."
            }
            $confidence = [int]$rule.Value.confidence
            if ($confidence -lt [int]$module.confidence.minimum -or
                $confidence -gt [int]$module.confidence.maximum) {
                throw "Confidence $confidence for '$moduleId' is outside " +
                    "its allowed range in '$threadsPath'."
            }
            $counts = $moduleCountsByArchetype[$archetypeId]
            if (-not $counts.Contains($moduleId)) {
                $counts[$moduleId] = 0
            }
            $counts[$moduleId]++

            foreach ($port in $module.bindingPorts.PSObject.Properties) {
                $slotName = [string](Get-CaseKitProperty `
                    -Value $step.action.bindings -Name $port.Name)
                if ([string]::IsNullOrWhiteSpace($slotName)) {
                    throw "$context is missing binding port '$($port.Name)' " +
                        "in '$threadsPath'."
                }
                $slot = $mergedSlots.PSObject.Properties[$slotName]
                if ($null -eq $slot) {
                    throw "$context binds '$($port.Name)' to unknown slot " +
                        "'$slotName' in '$threadsPath'."
                }
                if ($slot.Value.entityType -ne $port.Value.entityType) {
                    throw "$context binds '$($port.Name)' to incompatible " +
                        "slot '$slotName' in '$threadsPath'."
                }
                foreach ($capability in @($port.Value.capabilities)) {
                    if (@($slot.Value.capabilities) -notcontains $capability) {
                        throw "Slot '$slotName' lacks capability '$capability' " +
                            "for $context in '$threadsPath'."
                    }
                }
            }

            Assert-CaseKitFactsExist -FactIds @($step.requiresFacts) `
                -FactMap $factMap -Context $context -SourcePath $threadsPath
            Assert-CaseKitFactsExist -FactIds @($step.result.revealsFacts) `
                -FactMap $factMap -Context "$context result" `
                -SourcePath $threadsPath
            foreach ($nextStepId in @($step.result.nextStepIds)) {
                if (-not $stepMap.Contains([string]$nextStepId)) {
                    throw "$context points to unknown step '$nextStepId' in " +
                        "'$threadsPath'."
                }
            }
            foreach ($nextThreadId in @($step.result.unlockThreadIds)) {
                if (-not $threadMap.Contains([string]$nextThreadId)) {
                    throw "$context unlocks unknown thread '$nextThreadId' " +
                        "in '$threadsPath'."
                }
            }
            foreach ($presentation in @($step.presentations)) {
                Assert-CaseKitFactsExist `
                    -FactIds @($presentation.when.allKnown) `
                    -FactMap $factMap `
                    -Context "$context presentation '$($presentation.id)'" `
                    -SourcePath $threadsPath
                Assert-CaseKitFactsExist `
                    -FactIds @($presentation.when.allUnknown) `
                    -FactMap $factMap `
                    -Context "$context presentation '$($presentation.id)'" `
                    -SourcePath $threadsPath
                foreach ($contentPort in @($module.requiredContent)) {
                    if ($null -eq $presentation.content.PSObject.Properties[
                        [string]$contentPort
                    ]) {
                        throw "$context presentation '$($presentation.id)' " +
                            "is missing content '$contentPort' in " +
                            "'$threadsPath'."
                    }
                }
                foreach ($assetKey in @(Get-CaseKitContentAssetKeys `
                    -Content $presentation.content)) {
                    Assert-CaseKitAssetReference -AssetKey $assetKey `
                        -AssetKeys $story.assets.ru.PSObject.Properties.Name `
                        -Context "$context presentation '$($presentation.id)'" `
                        -SourcePath $threadsPath
                }
            }
        }

        $reachableSteps = [System.Collections.Generic.HashSet[string]]::new()
        $pendingSteps = [System.Collections.Generic.Queue[string]]::new()
        foreach ($entryStepId in @($thread.entryStepIds)) {
            $pendingSteps.Enqueue([string]$entryStepId)
        }
        while ($pendingSteps.Count -gt 0) {
            $stepId = $pendingSteps.Dequeue()
            if (-not $reachableSteps.Add($stepId)) {
                continue
            }
            foreach ($nextStepId in @($stepMap[$stepId].result.nextStepIds)) {
                $pendingSteps.Enqueue([string]$nextStepId)
            }
        }
        foreach ($stepId in $stepMap.Keys) {
            if (-not $reachableSteps.Contains([string]$stepId)) {
                throw "Thread '$threadId' contains unreachable step " +
                    "'$stepId' in '$threadsPath'."
            }
        }
    }

    foreach ($archetypeId in @($story.archetypes)) {
        $archetype = $ArchetypeMap[[string]$archetypeId].value
        $threadCount = @($story.threads | Where-Object {
            [string]$_.archetypeId -eq [string]$archetypeId
        }).Count
        if ($threadCount -lt [int]$archetype.threadRules.minimum -or
            $threadCount -gt [int]$archetype.threadRules.maximum) {
            throw "Story '$($story.id)' uses archetype '$archetypeId' with " +
                "$threadCount threads outside the allowed range in " +
                "'$threadsPath'."
        }
        $counts = $moduleCountsByArchetype[[string]$archetypeId]
        foreach ($rule in $archetype.evidenceRules.PSObject.Properties) {
            $count = if ($counts.Contains($rule.Name)) {
                [int]$counts[$rule.Name]
            }
            else {
                0
            }
            if ($count -lt [int]$rule.Value.minimum -or
                $count -gt [int]$rule.Value.maximum) {
                throw "Story '$($story.id)' uses '$($rule.Name)' $count times " +
                    "outside archetype '$archetypeId' range in " +
                    "'$threadsPath'."
            }
        }
    }

    $reachability = Get-CaseKitV2Reachability -Story $story `
        -ArchetypeMap $ArchetypeMap
    foreach ($threadId in $threadMap.Keys) {
        if (@($reachability.activeThreads) -notcontains [string]$threadId) {
            throw "Story '$($story.id)' thread '$threadId' is disconnected " +
                "in '$threadsPath'."
        }
    }
    if ([int]$reachability.maximumReachableConfidence -lt
        [int]$story.reveal.confidence) {
        throw "Story '$($story.id)' maximum reachable confidence " +
            "$($reachability.maximumReachableConfidence) is below reveal " +
            "threshold $($story.reveal.confidence) in '$casePath'."
    }
    foreach ($factId in @($identityRequirement.factIds)) {
        if (@($reachability.knownFacts) -notcontains [string]$factId) {
            $factKind = if ($identityRequirement.mode -eq 'allOf') {
                'required reveal fact'
            }
            else {
                'identity alternative'
            }
            throw "Story '$($story.id)' cannot reach $factKind '$factId' " +
                "in '$casePath'."
        }
    }

    return [pscustomobject][ordered]@{
        storyId = [string]$story.id
        maximumReachableConfidence = [int](
            $reachability.maximumReachableConfidence
        )
        archetypes = @($story.archetypes)
        requiredHardFactsSatisfied = $true
        identityRequirementMode = [string]$identityRequirement.mode
        reachableIdentityFacts = @($identityRequirement.factIds)
    }
}

function Get-CaseKitReachableConfidence {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Archetype
    )

    $knownFacts = [System.Collections.Generic.HashSet[string]]::new()
    $scoredSteps = [System.Collections.Generic.HashSet[string]]::new()
    $changed = $true
    $total = 0
    while ($changed) {
        $changed = $false
        foreach ($thread in @($Story.threads)) {
            $leadFacts = @($thread.lead.requiresFacts)
            foreach ($step in @($thread.steps)) {
                $stepKey = "$($thread.id)/$($step.id)"
                if ($scoredSteps.Contains($stepKey)) {
                    continue
                }
                $requirements = @($leadFacts) + @($step.requiresFacts)
                $canRun = $true
                foreach ($factId in $requirements) {
                    if (-not $knownFacts.Contains([string]$factId)) {
                        $canRun = $false
                        break
                    }
                }
                if (-not $canRun) {
                    continue
                }
                $null = $scoredSteps.Add($stepKey)
                $rule = $Archetype.evidenceRules.PSObject.Properties[
                    [string]$step.action.evidenceModule
                ]
                $total += [int]$rule.Value.confidence
                foreach ($factId in @($step.result.revealsFacts)) {
                    $null = $knownFacts.Add([string]$factId)
                }
                $changed = $true
            }
        }
    }
    return $total
}

function Assert-CaseKitStoryContract {
    param(
        [Parameter(Mandatory)]$StoryEntry,
        [Parameter(Mandatory)]$ArchetypeMap,
        [Parameter(Mandatory)]$ModuleMap
    )

    $story = $StoryEntry.value
    $sourcePath = [string]$StoryEntry.path
    Assert-CaseKitLanguageAssets -Story $story -SourcePath $sourcePath

    $factMap = [ordered]@{}
    foreach ($fact in @($story.facts)) {
        if ($factMap.Contains([string]$fact.id)) {
            throw "Duplicate fact '$($fact.id)' in '$sourcePath'."
        }
        $factMap[[string]$fact.id] = $fact
    }
    $threadMap = [ordered]@{}
    foreach ($thread in @($story.threads)) {
        if ($threadMap.Contains([string]$thread.id)) {
            throw "Duplicate thread '$($thread.id)' in '$sourcePath'."
        }
        $threadMap[[string]$thread.id] = $thread
    }

    $maximumByArchetype = [ordered]@{}
    foreach ($archetypeId in @($story.compatibleArchetypes)) {
        if (-not $ArchetypeMap.Contains([string]$archetypeId)) {
            throw "Story '$($story.id)' references unknown archetype " +
                "'$archetypeId' in '$sourcePath'."
        }
        $archetype = $ArchetypeMap[[string]$archetypeId].value
        Assert-CaseKitTemplateContract -Story $story `
            -Archetype $archetype -SourcePath $sourcePath
        $threadCount = @($story.threads).Count
        if ($threadCount -lt [int]$archetype.threadRules.minimum -or
            $threadCount -gt [int]$archetype.threadRules.maximum) {
            throw "Story '$($story.id)' has $threadCount threads outside the " +
                "allowed range in '$sourcePath'."
        }

        $moduleCounts = [ordered]@{}
        foreach ($thread in @($story.threads)) {
            if (@($archetype.threadRules.allowedLeadModes) -notcontains
                [string]$thread.lead.mode) {
                throw "Thread '$($thread.id)' uses unsupported lead mode " +
                    "'$($thread.lead.mode)' in '$sourcePath'."
            }
            Assert-CaseKitFactsExist -FactIds @($thread.lead.requiresFacts) `
                -FactMap $factMap -Context "Thread '$($thread.id)' lead" `
                -SourcePath $sourcePath
            Assert-CaseKitAssetReference `
                -AssetKey ([string]$thread.lead.directionAsset) `
                -AssetKeys $story.assets.ru.PSObject.Properties.Name `
                -Context "Thread '$($thread.id)' lead" `
                -SourcePath $sourcePath

            $stepMap = [ordered]@{}
            foreach ($step in @($thread.steps)) {
                if ($stepMap.Contains([string]$step.id)) {
                    throw "Duplicate step '$($step.id)' in thread " +
                        "'$($thread.id)' in '$sourcePath'."
                }
                $stepMap[[string]$step.id] = $step
            }
            foreach ($entryStepId in @($thread.entryStepIds)) {
                if (-not $stepMap.Contains([string]$entryStepId)) {
                    throw "Thread '$($thread.id)' has unknown entry step " +
                        "'$entryStepId' in '$sourcePath'."
                }
            }
            if (@($thread.entryStepIds).Count -gt 1 -and
                [bool]$archetype.threadRules.allowOutOfOrder) {
                $hasConditionalPresentation = @($thread.steps |
                    Where-Object { @($_.presentations).Count -gt 1 }).Count -gt 0
                if (-not $hasConditionalPresentation) {
                    throw "Thread '$($thread.id)' declares multiple entry " +
                        "steps but has no conditional presentation in " +
                        "'$sourcePath'."
                }
            }

            foreach ($step in @($thread.steps)) {
                $context = "Step '$($thread.id)/$($step.id)'"
                if (@($archetype.threadRules.allowedStepKinds) -notcontains
                    [string]$step.kind) {
                    throw "$context uses unsupported kind '$($step.kind)' " +
                        "in '$sourcePath'."
                }
                $moduleId = [string]$step.action.evidenceModule
                if (-not $ModuleMap.Contains($moduleId)) {
                    throw "Unknown evidence module '$moduleId' in $context " +
                        "in '$sourcePath'."
                }
                $ruleProperty = $archetype.evidenceRules.PSObject.Properties[
                    $moduleId
                ]
                if ($null -eq $ruleProperty) {
                    throw "Archetype '$archetypeId' does not allow evidence " +
                        "module '$moduleId' in '$sourcePath'."
                }
                $module = $ModuleMap[$moduleId].value
                if ([string]$module.stepKind -ne [string]$step.kind) {
                    throw "Evidence module '$moduleId' requires step kind " +
                        "'$($module.stepKind)', got '$($step.kind)' in " +
                        "$context in '$sourcePath'."
                }
                $confidence = [int]$ruleProperty.Value.confidence
                if ($confidence -lt [int]$module.confidence.minimum -or
                    $confidence -gt [int]$module.confidence.maximum) {
                    throw "Confidence $confidence for '$moduleId' is outside " +
                        "its allowed range in '$sourcePath'."
                }
                if (-not $moduleCounts.Contains($moduleId)) {
                    $moduleCounts[$moduleId] = 0
                }
                $moduleCounts[$moduleId]++

                foreach ($port in $module.bindingPorts.PSObject.Properties) {
                    $slotName = Get-CaseKitProperty `
                        -Value $step.action.bindings -Name $port.Name
                    if ([string]::IsNullOrWhiteSpace([string]$slotName)) {
                        throw "$context is missing binding port '$($port.Name)' " +
                            "in '$sourcePath'."
                    }
                    $slotProperty = $archetype.slots.PSObject.Properties[
                        [string]$slotName
                    ]
                    if ($null -eq $slotProperty) {
                        throw "$context binds '$($port.Name)' to unknown slot " +
                            "'$slotName' in '$sourcePath'."
                    }
                    if ($slotProperty.Value.entityType -ne
                        $port.Value.entityType) {
                        throw "$context binds '$($port.Name)' to incompatible " +
                            "slot '$slotName' in '$sourcePath'."
                    }
                    foreach ($capability in @($port.Value.capabilities)) {
                        if (@($slotProperty.Value.capabilities) -notcontains
                            $capability) {
                            throw "Slot '$slotName' lacks capability " +
                                "'$capability' for $context in '$sourcePath'."
                        }
                    }
                }

                Assert-CaseKitFactsExist -FactIds @($step.requiresFacts) `
                    -FactMap $factMap -Context $context `
                    -SourcePath $sourcePath
                Assert-CaseKitFactsExist `
                    -FactIds @($step.result.revealsFacts) `
                    -FactMap $factMap -Context "$context result" `
                    -SourcePath $sourcePath
                foreach ($nextStepId in @($step.result.nextStepIds)) {
                    if (-not $stepMap.Contains([string]$nextStepId)) {
                        throw "$context points to unknown step '$nextStepId' " +
                            "in '$sourcePath'."
                    }
                }
                foreach ($nextThreadId in @(
                    $step.result.unlockThreadIds
                )) {
                    if (-not $threadMap.Contains([string]$nextThreadId)) {
                        throw "$context unlocks unknown thread " +
                            "'$nextThreadId' in '$sourcePath'."
                    }
                }
                foreach ($presentation in @($step.presentations)) {
                    Assert-CaseKitFactsExist `
                        -FactIds @($presentation.when.allKnown) `
                        -FactMap $factMap `
                        -Context "$context presentation '$($presentation.id)'" `
                        -SourcePath $sourcePath
                    Assert-CaseKitFactsExist `
                        -FactIds @($presentation.when.allUnknown) `
                        -FactMap $factMap `
                        -Context "$context presentation '$($presentation.id)'" `
                        -SourcePath $sourcePath
                    foreach ($contentPort in @($module.requiredContent)) {
                        if ($null -eq $presentation.content.PSObject.Properties[
                            [string]$contentPort
                        ]) {
                            throw "$context presentation '$($presentation.id)' " +
                                "is missing content '$contentPort' in " +
                                "'$sourcePath'."
                        }
                    }
                    foreach ($assetKey in @(Get-CaseKitContentAssetKeys `
                        -Content $presentation.content)) {
                        Assert-CaseKitAssetReference -AssetKey $assetKey `
                            -AssetKeys $story.assets.ru.PSObject.Properties.Name `
                            -Context "$context presentation '$($presentation.id)'" `
                            -SourcePath $sourcePath
                    }
                }
            }

            $reachableSteps = [System.Collections.Generic.HashSet[string]]::new()
            $pendingSteps = [System.Collections.Generic.Queue[string]]::new()
            foreach ($entryStepId in @($thread.entryStepIds)) {
                $pendingSteps.Enqueue([string]$entryStepId)
            }
            while ($pendingSteps.Count -gt 0) {
                $stepId = $pendingSteps.Dequeue()
                if (-not $reachableSteps.Add($stepId)) {
                    continue
                }
                foreach ($nextStepId in @(
                    $stepMap[$stepId].result.nextStepIds
                )) {
                    $pendingSteps.Enqueue([string]$nextStepId)
                }
            }
            foreach ($stepId in $stepMap.Keys) {
                if (-not $reachableSteps.Contains([string]$stepId)) {
                    throw "Thread '$($thread.id)' contains unreachable step " +
                        "'$stepId' in '$sourcePath'."
                }
            }
        }

        foreach ($ruleProperty in $archetype.evidenceRules.PSObject.Properties) {
            $count = if ($moduleCounts.Contains($ruleProperty.Name)) {
                [int]$moduleCounts[$ruleProperty.Name]
            }
            else {
                0
            }
            if ($count -lt [int]$ruleProperty.Value.minimum -or
                $count -gt [int]$ruleProperty.Value.maximum) {
                throw "Story '$($story.id)' uses '$($ruleProperty.Name)' " +
                    "$count times outside the allowed range in '$sourcePath'."
            }
        }

        $maximum = Get-CaseKitReachableConfidence `
            -Story $story -Archetype $archetype
        if ($maximum -lt [int]$archetype.revealThreshold) {
            throw "Story '$($story.id)' maximum reachable confidence " +
                "$maximum is below reveal threshold " +
                "$($archetype.revealThreshold) in '$sourcePath'."
        }
        $maximumByArchetype[$archetypeId] = $maximum
    }

    return [pscustomobject][ordered]@{
        storyId = [string]$story.id
        maximumReachableConfidence = [int](
            $maximumByArchetype.Values | Measure-Object -Maximum
        ).Maximum
        archetypes = [pscustomobject]$maximumByArchetype
    }
}

function Read-CaseKitAuthoredDeck {
    param(
        [Parameter(Mandatory)][string]$ArchetypeRoot,
        [Parameter(Mandatory)][string]$StoryRoot,
        [Parameter(Mandatory)][string]$EvidenceModuleRoot
    )

    $archetypeEntries = @(Get-CaseKitAuthoringFiles `
        -LiteralPath $ArchetypeRoot -Filter '*.archetype.json' |
        ForEach-Object {
            [pscustomobject]@{
                path = $_.FullName
                value = Read-CaseKitAuthoringJson -LiteralPath $_.FullName
            }
        })
    $storyEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-CaseKitAuthoringFiles `
        -LiteralPath $StoryRoot -Filter '*.story.json' |
        Sort-Object FullName)) {
        $storyEntries.Add([pscustomobject]@{
            path = $file.FullName
            value = Read-CaseKitAuthoringJson -LiteralPath $file.FullName
            sourceSchemaVersion = 1
        })
    }
    if (-not (Test-Path -LiteralPath $StoryRoot -PathType Container)) {
        throw "CaseKit authoring root not found: $StoryRoot"
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $StoryRoot `
        -Filter 'case.json' -File -Recurse | Sort-Object FullName)) {
        $storyEntries.Add([pscustomobject]@{
            path = $file.FullName
            value = Read-CaseKitV2StoryPackage -CasePath $file.FullName
            sourceSchemaVersion = 2
        })
    }
    $moduleEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-CaseKitAuthoringFiles `
        -LiteralPath $EvidenceModuleRoot -Filter '*.evidence.json')) {
        $registry = Read-CaseKitAuthoringJson -LiteralPath $file.FullName
        foreach ($module in @($registry.modules)) {
            $moduleEntries.Add([pscustomobject]@{
                path = $file.FullName
                value = $module
            })
        }
    }

    $archetypeMap = New-CaseKitEntryMap `
        -Entries $archetypeEntries -Kind 'archetype'
    $moduleMap = New-CaseKitEntryMap `
        -Entries $moduleEntries.ToArray() -Kind 'evidence module'
    $null = New-CaseKitEntryMap -Entries $storyEntries.ToArray() -Kind 'story'
    Assert-CaseKitEvidenceModules -ModuleMap $moduleMap

    $validation = @($storyEntries.ToArray() | ForEach-Object {
        if ([int]$_.sourceSchemaVersion -eq 2) {
            Assert-CaseKitV2StoryContract -StoryEntry $_ `
                -ArchetypeMap $archetypeMap -ModuleMap $moduleMap
        }
        else {
            Assert-CaseKitStoryContract -StoryEntry $_ `
                -ArchetypeMap $archetypeMap -ModuleMap $moduleMap
        }
    })
    $maximum = if ($validation.Count -gt 0) {
        [int]($validation | Measure-Object `
            -Property maximumReachableConfidence -Maximum).Maximum
    }
    else {
        0
    }

    $normalizedStories = @($storyEntries.ToArray() | ForEach-Object {
        ConvertTo-CaseKitNormalizedStory -Story $_.value `
            -SourceSchemaVersion ([int]$_.sourceSchemaVersion)
    } | Sort-Object id)
    $sourceSchemaVersions = @($storyEntries.ToArray() |
        ForEach-Object { [int]$_.sourceSchemaVersion } |
        Sort-Object -Unique)

    return [pscustomobject][ordered]@{
        schemaVersion = 2
        sourceFormat = 'casekit-authoring-v2'
        sourceSchemaVersions = $sourceSchemaVersions
        archetypes = @($archetypeEntries.value | Sort-Object id)
        stories = $normalizedStories
        evidenceModules = @($moduleEntries.value | Sort-Object id)
        validation = [pscustomobject][ordered]@{
            maximumReachableConfidence = $maximum
            stories = $validation
        }
    }
}

Export-ModuleMember -Function 'Read-CaseKitAuthoredDeck'
