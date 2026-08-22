Set-StrictMode -Version Latest

function Get-CaseKitKcd2Property {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $Value) { return $DefaultValue }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Copy-CaseKitKcd2Value {
    param([Parameter(Mandatory)]$Value)

    return ($Value | ConvertTo-Json -Depth 100) |
        ConvertFrom-Json -Depth 100
}

function ConvertTo-CaseKitKcd2GuidancePresentation {
    param(
        [Parameter(Mandatory)]$GuidanceBinding,
        $CompiledStory,
        $Localization,
        $GeneratedKeyOrigins
    )

    $qualifiedId = [string]$GuidanceBinding.qualifiedId
    $aliasSuffix = $qualifiedId -replace '[^A-Za-z0-9_]', '_'
    $fallback = [string](Get-CaseKitKcd2Property `
        -Value $GuidanceBinding -Name 'fallback' `
        -DefaultValue 'journal-direction')
    $visibility = Get-CaseKitKcd2Property `
        -Value $GuidanceBinding -Name 'visibility' `
        -DefaultValue ([pscustomobject]@{
            mode = 'step-active'
            requiresFacts = @()
        })
    $lifetime = [string](Get-CaseKitKcd2Property `
        -Value $GuidanceBinding -Name 'lifetime' -DefaultValue 'step')
    $binding = Get-CaseKitKcd2Property `
        -Value $GuidanceBinding -Name 'binding'
    $areaSelection = [string](Get-CaseKitKcd2Property `
        -Value $GuidanceBinding -Name 'areaSelection' -DefaultValue '')
    $anchorBindings = @(Get-CaseKitKcd2Property `
        -Value $GuidanceBinding -Name 'anchorBindings' -DefaultValue @())
    $objectivePresentation = Get-CaseKitKcd2Property `
        -Value $GuidanceBinding -Name 'objective'
    $nativeObjective = if ($null -eq $objectivePresentation) { $null } else {
        if ($null -eq $CompiledStory -or $null -eq $Localization) {
            throw "GuidanceTarget '$qualifiedId' objective requires compiled " +
                'story localization context.'
        }
        ConvertTo-CaseKitKcd2ObjectivePresentation `
            -CompiledStory $CompiledStory `
            -Presentation $objectivePresentation `
            -Localization $Localization `
            -GeneratedKeyOrigins $GeneratedKeyOrigins
    }
    $assetKind = $null
    $catalogKey = ''
    if ($null -ne $binding) {
        $targetKind = [string]$GuidanceBinding.targetKind
        $precision = [string]$GuidanceBinding.precision
        if ($targetKind -eq 'actor' -and
            $precision -in @('exact', 'point') -and
            -not [string]::IsNullOrWhiteSpace(
                [string](Get-CaseKitKcd2Property `
                    -Value $binding -Name 'soulGuid' -DefaultValue '')
            )) {
            $assetKind = 'SoulAsset'
        }
        elseif ($targetKind -eq 'entity' -and
            $precision -in @('exact', 'point')) {
            $assetKind = 'InteractionTriggerAsset'
        }
        elseif ($targetKind -eq 'place' -and $precision -eq 'point' -and
            [string]$binding.kind -ne 'settlement') {
            $assetKind = 'InteractionTriggerAsset'
        }
        elseif ($targetKind -in @('place', 'area') -and
            $precision -eq 'area' -and
            [string]$binding.kind -eq 'settlement') {
            $assetKind = 'TriggerAreaAsset'
            $catalogKey = '{0}/{1}' -f `
                [string]$binding.region,
                [string]$binding.settlement
        }
    }

    if ($null -eq $assetKind) {
        if ($fallback -eq 'reject-variant') {
            throw "KCD2 cannot materialize GuidanceTarget '$qualifiedId'."
        }
        $fallbackResult = [ordered]@{
            qualifiedId = $qualifiedId
            mode = 'journal-direction'
            alias = ''
            assetKind = $null
            catalogKey = ''
            binding = $binding
            areaSelection = $areaSelection
            anchorBindings = Copy-CaseKitKcd2Value -Value $anchorBindings
            visibility = Copy-CaseKitKcd2Value -Value $visibility
            lifetime = $lifetime
        }
        if ($null -ne $nativeObjective) {
            $fallbackResult.objective = $nativeObjective
        }
        return [pscustomobject]$fallbackResult
    }

    $nativeResult = [ordered]@{
        qualifiedId = $qualifiedId
        mode = 'native-marker'
        alias = "DpGuidance_$aliasSuffix"
        assetKind = $assetKind
        catalogKey = $catalogKey
        binding = Copy-CaseKitKcd2Value -Value $binding
        areaSelection = $areaSelection
        anchorBindings = Copy-CaseKitKcd2Value -Value $anchorBindings
        visibility = Copy-CaseKitKcd2Value -Value $visibility
        lifetime = $lifetime
    }
    if ($null -ne $nativeObjective) {
        $nativeResult.objective = $nativeObjective
    }
    return [pscustomobject]$nativeResult
}

function New-CaseKitKcd2Map {
    param(
        [Parameter(Mandatory)][object[]]$Values,
        [Parameter(Mandatory)][scriptblock]$KeySelector,
        [Parameter(Mandatory)][string]$Kind
    )

    $map = [ordered]@{}
    foreach ($value in $Values) {
        $key = [string](& $KeySelector $value)
        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "$Kind has no key."
        }
        if ($map.Contains($key)) {
            throw "$Kind '$key' is duplicated."
        }
        $map[$key] = $value
    }
    return $map
}

function Read-CaseKitKcd2Adapter {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "KCD2 adapter metadata not found: $LiteralPath"
    }
    $adapter = [System.IO.File]::ReadAllText($LiteralPath) |
        ConvertFrom-Json -Depth 100
    if ([int]$adapter.schemaVersion -ne 2) {
        throw 'KCD2 adapter metadata schemaVersion must be 2.'
    }
    $nativeRegions = Get-CaseKitKcd2Property -Value $adapter `
        -Name 'nativeRegions'
    if ($null -eq $nativeRegions -or
        @($nativeRegions.PSObject.Properties).Count -lt 1) {
        throw 'KCD2 adapter metadata requires nativeRegions.'
    }
    foreach ($property in $nativeRegions.PSObject.Properties) {
        $definition = $property.Value
        if ([string]::IsNullOrWhiteSpace([string]$definition.questName) -or
            [string]::IsNullOrWhiteSpace([string]$definition.dialogFolder)) {
            throw "KCD2 native region '$($property.Name)' is incomplete."
        }
    }
    $null = New-CaseKitKcd2Map -Values @($adapter.stories) `
        -KeySelector { param($entry) [string]$entry.storyId } `
        -Kind 'KCD2 story adapter'
    return $adapter
}

function Get-CaseKitKcd2NativeKey {
    param(
        [Parameter(Mandatory)]$StoryAdapter,
        [Parameter(Mandatory)][string]$Asset
    )

    $property = $StoryAdapter.localizationKeys.PSObject.Properties[$Asset]
    if ($null -eq $property -or
        [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        throw "Story '$($StoryAdapter.storyId)' has no native key for " +
            "asset '$Asset'."
    }
    return [string]$property.Value
}

function Get-CaseKitKcd2GeneratedNativeKey {
    param(
        [Parameter(Mandatory)]$CompiledStory,
        [Parameter(Mandatory)][string]$Asset
    )

    $suffix = $Asset.ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $suffix = $suffix.Trim('_')
    if ([string]::IsNullOrWhiteSpace($suffix)) {
        throw "Story '$($CompiledStory.storyId)' cannot generate a native " +
            "localization key for asset '$Asset'."
    }
    return 'dp_case_{0}_{1}' -f [int]$CompiledStory.caseCode, $suffix
}

function Add-CaseKitKcd2LocalizationValue {
    param(
        [Parameter(Mandatory)]$Localization,
        [Parameter(Mandatory)]$KeyOrigins,
        [Parameter(Mandatory)][ValidateSet('ru', 'en')][string]$Language,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$Source
    )

    if ($KeyOrigins.Contains($Key) -and
        [string]$KeyOrigins[$Key] -ne $Source) {
        throw "Generated localization key '$Key' collides between assets " +
            "'$([string]$KeyOrigins[$Key])' and '$Source'."
    }
    if ($Localization[$Language].Contains($Key)) {
        if ([string]$Localization[$Language][$Key] -ne $Value) {
            throw "Localization key '$Key' has conflicting $Language text."
        }
    }
    else {
        $Localization[$Language][$Key] = $Value
    }
    $KeyOrigins[$Key] = $Source
}

function ConvertTo-CaseKitKcd2ObjectivePresentation {
    param(
        [Parameter(Mandatory)]$CompiledStory,
        [Parameter(Mandatory)]$Presentation,
        [Parameter(Mandatory)]$Localization,
        $GeneratedKeyOrigins
    )

    if ($null -eq $GeneratedKeyOrigins) {
        $GeneratedKeyOrigins = [ordered]@{}
    }

    $nameAsset = [string](Get-CaseKitKcd2Property `
        -Value $Presentation -Name 'nameAsset')
    $nameKey = Get-CaseKitKcd2GeneratedNativeKey `
        -CompiledStory $CompiledStory -Asset $nameAsset
    foreach ($language in @('ru', 'en')) {
        Add-CaseKitKcd2LocalizationValue `
            -Localization $Localization `
            -KeyOrigins $GeneratedKeyOrigins `
            -Language $language -Key $nameKey -Source $nameAsset `
            -Value (Get-CaseKitKcd2AssetValue `
                -CompiledStory $CompiledStory -Language $language `
                -Asset $nameAsset)
    }

    $nativeStates = [ordered]@{}
    $states = Get-CaseKitKcd2Property `
        -Value $Presentation -Name 'states'
    if ($null -ne $states) {
        foreach ($state in $states.PSObject.Properties) {
            $asset = [string]$state.Value
            $key = Get-CaseKitKcd2GeneratedNativeKey `
                -CompiledStory $CompiledStory -Asset $asset
            foreach ($language in @('ru', 'en')) {
                Add-CaseKitKcd2LocalizationValue `
                    -Localization $Localization `
                    -KeyOrigins $GeneratedKeyOrigins `
                    -Language $language -Key $key -Source $asset `
                    -Value (Get-CaseKitKcd2AssetValue `
                        -CompiledStory $CompiledStory -Language $language `
                        -Asset $asset)
            }
            $nativeStates[[string]$state.Name] = [pscustomobject][ordered]@{
                key = $key
                fallback = Get-CaseKitKcd2AssetValue `
                    -CompiledStory $CompiledStory -Language en -Asset $asset
            }
        }
    }

    return [pscustomobject][ordered]@{
        nameKey = $nameKey
        fallbackName = Get-CaseKitKcd2AssetValue `
            -CompiledStory $CompiledStory -Language en -Asset $nameAsset
        states = [pscustomobject]$nativeStates
    }
}

function Get-CaseKitKcd2AssetValue {
    param(
        [Parameter(Mandatory)]$CompiledStory,
        [Parameter(Mandatory)][ValidateSet('ru', 'en')][string]$Language,
        [Parameter(Mandatory)][string]$Asset
    )

    $localized = $CompiledStory.localization.PSObject.Properties[$Language]
    $property = $localized.Value.PSObject.Properties[$Asset]
    if ($null -eq $property) {
        throw "Story '$($CompiledStory.storyId)' is missing $Language asset " +
            "'$Asset'."
    }
    return [string]$property.Value
}

function ConvertTo-CaseKitKcd2Responses {
    param(
        [Parameter(Mandatory)]$Variant,
        [Parameter(Mandatory)]$DialogueAdapter,
        [Parameter(Mandatory)]$StoryAdapter
    )

    return @($Variant.turns | ForEach-Object {
        $roleProperty = $DialogueAdapter.speakerRoles.PSObject.Properties[
            [string]$_.speaker
        ]
        if ($null -eq $roleProperty) {
            throw "Dialogue '$($DialogueAdapter.dialogueId)' has no native " +
                "role for speaker '$($_.speaker)'."
        }
        [pscustomobject][ordered]@{
            role = [string]$roleProperty.Value
            key = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
                -Asset ([string]$_.asset)
        }
    })
}

function ConvertTo-CaseKitKcd2EvidenceIds {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$QualifiedIds,
        [Parameter(Mandatory)]$EvidenceMap
    )

    return @($QualifiedIds | ForEach-Object {
        $qualifiedId = [string]$_
        if (-not $EvidenceMap.Contains($qualifiedId)) {
            throw "Unknown evidence reference '$qualifiedId'."
        }
        [string]$EvidenceMap[$qualifiedId].legacyId
    })
}

function ConvertTo-CaseKitKcd2Dialogue {
    param(
        [Parameter(Mandatory)]$DialogueAdapter,
        [Parameter(Mandatory)]$CompiledStory,
        [Parameter(Mandatory)]$StoryAdapter,
        [Parameter(Mandatory)]$EvidenceMap,
        [Parameter(Mandatory)]$DialogueMap
    )

    $dialogueId = [string]$DialogueAdapter.dialogueId
    if (-not $DialogueMap.Contains($dialogueId)) {
        throw "Story '$($CompiledStory.storyId)' has no dialogue '$dialogueId'."
    }
    $definition = $DialogueMap[$dialogueId]
    $variants = @($definition.variants)
    if ($variants.Count -eq 0) {
        throw "Dialogue '$dialogueId' has no variants."
    }
    $native = [ordered]@{
        kind = [string]$DialogueAdapter.kind
    }
    $media = Get-CaseKitKcd2Property -Value $definition -Name 'media'
    if ($null -ne $media) {
        $native.media = Copy-CaseKitKcd2Value -Value $media
    }
    $evidenceQualifiedId = [string](Get-CaseKitKcd2Property `
        -Value $DialogueAdapter -Name 'evidenceQualifiedId' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($evidenceQualifiedId)) {
        $native.evidenceId = [string](@(ConvertTo-CaseKitKcd2EvidenceIds `
            -QualifiedIds @($evidenceQualifiedId) `
            -EvidenceMap $EvidenceMap)[0])
    }
    $native.graphName = [string]$DialogueAdapter.graphName
    $native.fileName = [string]$DialogueAdapter.fileName
    $native.rootKey = Get-CaseKitKcd2NativeKey `
        -StoryAdapter $StoryAdapter -Asset ([string]$DialogueAdapter.rootAsset)
    $native.sequenceName = [string]$DialogueAdapter.sequenceName
    $native.promptKey = Get-CaseKitKcd2NativeKey `
        -StoryAdapter $StoryAdapter -Asset ([string]$variants[0].promptAsset)
    $native.availableLabel = [string]$DialogueAdapter.availableLabel
    $native.heardLabel = [string]$DialogueAdapter.heardLabel

    if ([bool](Get-CaseKitKcd2Property -Value $DialogueAdapter `
        -Name 'emitVariants' -DefaultValue $false)) {
        $conditions = $DialogueAdapter.variantConditions
        $native.variants = @($variants | ForEach-Object {
            $conditionProperty = $conditions.PSObject.Properties[[string]$_.id]
            if ($null -eq $conditionProperty) {
                throw "Dialogue '$dialogueId' has no native condition for " +
                    "variant '$($_.id)'."
            }
            $condition = $conditionProperty.Value
            [pscustomobject][ordered]@{
                id = ([string]$_.id).Replace('-', '_')
                when = [pscustomobject][ordered]@{
                    allDiscovered = @(ConvertTo-CaseKitKcd2EvidenceIds `
                        -QualifiedIds @($condition.allDiscovered) `
                        -EvidenceMap $EvidenceMap)
                    allUndiscovered = @(ConvertTo-CaseKitKcd2EvidenceIds `
                        -QualifiedIds @($condition.allUndiscovered) `
                        -EvidenceMap $EvidenceMap)
                }
                promptKey = Get-CaseKitKcd2NativeKey `
                    -StoryAdapter $StoryAdapter `
                    -Asset ([string]$_.promptAsset)
                responses = @(ConvertTo-CaseKitKcd2Responses `
                    -Variant $_ -DialogueAdapter $DialogueAdapter `
                    -StoryAdapter $StoryAdapter)
            }
        })
    }
    else {
        $native.responses = @(ConvertTo-CaseKitKcd2Responses `
            -Variant $variants[0] -DialogueAdapter $DialogueAdapter `
            -StoryAdapter $StoryAdapter)
    }
    return [pscustomobject]$native
}

function ConvertTo-CaseKitKcd2Evidence {
    param(
        [Parameter(Mandatory)]$CompiledEvidence,
        [Parameter(Mandatory)]$CompiledStory,
        [Parameter(Mandatory)]$EvidenceAdapter,
        [Parameter(Mandatory)]$StoryAdapter,
        [Parameter(Mandatory)]$EvidenceMap,
        [Parameter(Mandatory)]$Localization,
        [Parameter(Mandatory)]$GeneratedKeyOrigins,
        $ResolvedPlacement
    )

    $native = [ordered]@{
        id = [string]$CompiledEvidence.legacyId
        code = [int]$CompiledEvidence.code
        kind = [string]$EvidenceAdapter.kind
        role = [string]$EvidenceAdapter.role
    }
    foreach ($propertyName in @('purpose', 'sourceStance')) {
        $value = [string](Get-CaseKitKcd2Property `
            -Value $EvidenceAdapter -Name $propertyName -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $native[$propertyName] = $value
        }
    }
    $native.confidence = [int]$CompiledEvidence.confidence
    $native.placement = [string]$EvidenceAdapter.placement
    if ($null -ne $ResolvedPlacement) {
        $native.destination = Copy-CaseKitKcd2Value `
            -Value $ResolvedPlacement
    }
    $native.discoverableWithoutHint = [bool]$EvidenceAdapter.discoverableWithoutHint
    $native.hintsUnlockedBy = @(ConvertTo-CaseKitKcd2EvidenceIds `
        -QualifiedIds @($EvidenceAdapter.hintsUnlockedBy) `
        -EvidenceMap $EvidenceMap)
    $native.reveals = @($CompiledEvidence.result.revealsFacts)
    $native.journalEntries = @($CompiledEvidence.presentations | ForEach-Object {
        $presentation = $_
        $content = Get-CaseKitKcd2Property `
            -Value $presentation -Name 'content'
        $journalAsset = [string](Get-CaseKitKcd2Property `
            -Value $content -Name 'journal' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($journalAsset)) {
            throw "Evidence '$($CompiledEvidence.qualifiedId)' presentation " +
                "'$($presentation.id)' requires content.journal."
        }
        $journalKey = Get-CaseKitKcd2GeneratedNativeKey `
            -CompiledStory $CompiledStory -Asset $journalAsset
        foreach ($language in @('ru', 'en')) {
            Add-CaseKitKcd2LocalizationValue `
                -Localization $Localization `
                -KeyOrigins $GeneratedKeyOrigins `
                -Language $language -Key $journalKey -Source $journalAsset `
                -Value (Get-CaseKitKcd2AssetValue `
                    -CompiledStory $CompiledStory -Language $language `
                    -Asset $journalAsset)
        }
        [pscustomobject][ordered]@{
            id = [string]$presentation.id
            allKnownFacts = @($presentation.when.allKnown)
            allUnknownFacts = @($presentation.when.allUnknown)
            key = $journalKey
            fallback = Get-CaseKitKcd2AssetValue `
                -CompiledStory $CompiledStory -Language en `
                -Asset $journalAsset
        }
    })

    $promptAsset = [string](Get-CaseKitKcd2Property `
        -Value $EvidenceAdapter -Name 'promptAsset' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($promptAsset)) {
        $native.promptKey = Get-CaseKitKcd2NativeKey `
            -StoryAdapter $StoryAdapter -Asset $promptAsset
    }
    $reaction = [string](Get-CaseKitKcd2Property `
        -Value $EvidenceAdapter -Name 'reaction' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($reaction)) {
        $native.reaction = $reaction
    }
    $directionAsset = [string](Get-CaseKitKcd2Property `
        -Value $EvidenceAdapter -Name 'directionAsset' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($directionAsset)) {
        $native.direction = [pscustomobject][ordered]@{
            key = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
                -Asset $directionAsset
        }
    }
    $item = Get-CaseKitKcd2Property -Value $EvidenceAdapter -Name 'item'
    if ($null -ne $item) {
        $semantics = Get-CaseKitKcd2Property `
            -Value $CompiledEvidence -Name 'item'
        if ($null -eq $semantics) {
            throw "Evidence '$($CompiledEvidence.qualifiedId)' has a native " +
                'item but no authored item semantics.'
        }
        $native.item = [pscustomobject][ordered]@{
            guid = [string](Get-CaseKitKcd2Property `
                -Value $item -Name 'guid' -DefaultValue '')
            name = [string]$item.name
            classification = [string]$semantics.classification
            retention = [string]$semantics.retention
            nameKey = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
                -Asset ([string]$item.nameAsset)
            infoKey = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
                -Asset ([string]$item.infoAsset)
            contentKey = Get-CaseKitKcd2NativeKey `
                -StoryAdapter $StoryAdapter -Asset ([string]$item.contentAsset)
        }
    }
    return [pscustomobject]$native
}

function ConvertTo-CaseKitKcd2CaseSpec {
    param(
        [Parameter(Mandatory)]$CompiledStory,
        [Parameter(Mandatory)]$Variant,
        [Parameter(Mandatory)]$StoryAdapter
    )

    $evidenceMap = New-CaseKitKcd2Map -Values @($CompiledStory.evidence) `
        -KeySelector { param($entry) [string]$entry.qualifiedId } `
        -Kind 'Compiled evidence'
    $evidenceAdapterMap = New-CaseKitKcd2Map `
        -Values @($StoryAdapter.evidence) `
        -KeySelector { param($entry) [string]$entry.qualifiedId } `
        -Kind 'KCD2 evidence adapter'
    $placementMap = New-CaseKitKcd2Map `
        -Values @($Variant.evidencePlacements) `
        -KeySelector { param($entry) [string]$entry.qualifiedId } `
        -Kind 'Resolved evidence placement'
    $dialogueMap = New-CaseKitKcd2Map -Values @($CompiledStory.dialogues) `
        -KeySelector { param($entry) [string]$entry.id } `
        -Kind 'Compiled dialogue'

    $native = [ordered]@{
        questName = [string]$StoryAdapter.native.questName
        dialogFolder = [string]$StoryAdapter.native.dialogFolder
        signals = Copy-CaseKitKcd2Value -Value $StoryAdapter.native.signals
        contexts = Copy-CaseKitKcd2Value -Value $StoryAdapter.native.contexts
    }
    $localization = [ordered]@{
        ru = [ordered]@{}
        en = [ordered]@{}
    }
    $localizationKeyOrigins = [ordered]@{}
    $journal = Get-CaseKitKcd2Property `
        -Value $CompiledStory -Name 'journal'
    if ($null -ne $journal) {
        $journalObjectives = Get-CaseKitKcd2Property `
            -Value $journal -Name 'objectives'
        $nativeObjectives = [ordered]@{}
        foreach ($objective in $journalObjectives.PSObject.Properties) {
            if ($null -eq $objective.Value) { continue }
            $nativeObjectives[[string]$objective.Name] =
                ConvertTo-CaseKitKcd2ObjectivePresentation `
                    -CompiledStory $CompiledStory `
                    -Presentation $objective.Value `
                    -Localization $localization `
                    -GeneratedKeyOrigins $localizationKeyOrigins
        }
        $native.journal = [pscustomobject][ordered]@{
            objectives = [pscustomobject]$nativeObjectives
        }
    }
    $guidanceBindings = @(Get-CaseKitKcd2Property `
        -Value $Variant -Name 'guidanceBindings' -DefaultValue @())
    if ($guidanceBindings.Count -gt 0) {
        $native.guidance = @($guidanceBindings | ForEach-Object {
            ConvertTo-CaseKitKcd2GuidancePresentation `
                -GuidanceBinding $_ -CompiledStory $CompiledStory `
                -Localization $localization `
                -GeneratedKeyOrigins $localizationKeyOrigins
        })
    }
    $timedAreaActions = @(Get-CaseKitKcd2Property `
        -Value $CompiledStory -Name 'timedAreaActions' -DefaultValue @())
    if ($timedAreaActions.Count -gt 0) {
        $native.timedAreaActions = Copy-CaseKitKcd2Value `
            -Value $timedAreaActions
    }
    $native.dialogues = @($StoryAdapter.native.dialogues | ForEach-Object {
        ConvertTo-CaseKitKcd2Dialogue -DialogueAdapter $_ `
            -CompiledStory $CompiledStory -StoryAdapter $StoryAdapter `
            -EvidenceMap $evidenceMap -DialogueMap $dialogueMap
    })
    $objective = $StoryAdapter.native.witnessObjective
    $fallbackDoneAsset = [string](Get-CaseKitKcd2Property `
        -Value $objective -Name 'fallbackDoneAsset' `
        -DefaultValue ([string]$objective.doneAsset))
    $native.witnessObjective = [pscustomobject][ordered]@{
        assetName = [string]$objective.assetName
        nameKey = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
            -Asset ([string]$objective.nameAsset)
        activeKey = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
            -Asset ([string]$objective.activeAsset)
        doneKey = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
            -Asset ([string]$objective.doneAsset)
        fallbackName = Get-CaseKitKcd2AssetValue `
            -CompiledStory $CompiledStory -Language en `
            -Asset ([string]$objective.nameAsset)
        fallbackActive = Get-CaseKitKcd2AssetValue `
            -CompiledStory $CompiledStory -Language en `
            -Asset ([string]$objective.activeAsset)
        fallbackDone = Get-CaseKitKcd2AssetValue `
            -CompiledStory $CompiledStory -Language en `
            -Asset $fallbackDoneAsset
    }

    $evidence = @($CompiledStory.evidence | ForEach-Object {
        if (-not $evidenceAdapterMap.Contains([string]$_.qualifiedId)) {
            throw "Story '$($CompiledStory.storyId)' has no KCD2 adapter for " +
                "evidence '$($_.qualifiedId)'."
        }
        ConvertTo-CaseKitKcd2Evidence -CompiledEvidence $_ `
            -CompiledStory $CompiledStory `
            -EvidenceAdapter $evidenceAdapterMap[[string]$_.qualifiedId] `
            -StoryAdapter $StoryAdapter -EvidenceMap $evidenceMap `
            -Localization $localization `
            -GeneratedKeyOrigins $localizationKeyOrigins `
            -ResolvedPlacement $(if (
                $placementMap.Contains([string]$_.qualifiedId)
            ) { $placementMap[[string]$_.qualifiedId] } else { $null })
    })
    $localizationAssets = [System.Collections.Generic.List[string]]::new()
    $seenLocalizationAssets =
        [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
    foreach ($asset in @($StoryAdapter.emitLocalizationAssets)) {
        if ($seenLocalizationAssets.Add([string]$asset)) {
            $localizationAssets.Add([string]$asset)
        }
    }
    foreach ($dialogueAdapter in @($StoryAdapter.native.dialogues)) {
        $dialogueId = [string]$dialogueAdapter.dialogueId
        if (-not $dialogueMap.Contains($dialogueId)) { continue }
        foreach ($asset in @($dialogueMap[$dialogueId].localizationKeys)) {
            if ($seenLocalizationAssets.Add([string]$asset)) {
                $localizationAssets.Add([string]$asset)
            }
        }
    }
    foreach ($asset in $localizationAssets) {
        $nativeKey = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
            -Asset ([string]$asset)
        foreach ($language in @('ru', 'en')) {
            Add-CaseKitKcd2LocalizationValue `
                -Localization $localization `
                -KeyOrigins $localizationKeyOrigins `
                -Language $language -Key $nativeKey -Source ([string]$asset) `
                -Value (Get-CaseKitKcd2AssetValue `
                    -CompiledStory $CompiledStory -Language $language `
                    -Asset ([string]$asset))
        }
    }

    $caseWeight = if (
        [double]$CompiledStory.weight -eq
        [Math]::Truncate([double]$CompiledStory.weight)
    ) {
        [int]$CompiledStory.weight
    }
    else {
        [double]$CompiledStory.weight
    }
    return [pscustomobject][ordered]@{
        schemaVersion = 2
        id = [string]$CompiledStory.caseId
        code = [int]$CompiledStory.caseCode
        weight = $caseWeight
        constraints = [pscustomobject][ordered]@{
            region = [string]$Variant.region
            settlement = [string]$Variant.settlement
        }
        targetPolicy = Copy-CaseKitKcd2Value -Value $StoryAdapter.targetPolicy
        crimeProfile = Copy-CaseKitKcd2Value -Value $StoryAdapter.crimeProfile
        revealThreshold = [int]$CompiledStory.reveal.confidence
        identityRequirement = Copy-CaseKitKcd2Value `
            -Value $CompiledStory.reveal.identityRequirement
        native = [pscustomobject]$native
        evidence = $evidence
        text = [pscustomobject][ordered]@{
            ru = [pscustomobject][ordered]@{
                title = Get-CaseKitKcd2AssetValue -CompiledStory $CompiledStory `
                    -Language ru -Asset 'case.title'
                description = Get-CaseKitKcd2AssetValue `
                    -CompiledStory $CompiledStory -Language ru `
                    -Asset 'case.description'
            }
            en = [pscustomobject][ordered]@{
                title = Get-CaseKitKcd2AssetValue -CompiledStory $CompiledStory `
                    -Language en -Asset 'case.title'
                description = Get-CaseKitKcd2AssetValue `
                    -CompiledStory $CompiledStory -Language en `
                    -Asset 'case.description'
            }
        }
        localization = [pscustomobject]$localization
    }
}

function Get-CaseKitKcd2SemanticDialogueRole {
    param(
        [Parameter(Mandatory)]$Adapter,
        [Parameter(Mandatory)][string]$SemanticRole
    )

    $map = Get-CaseKitKcd2Property -Value $Adapter `
        -Name 'semanticDialogueRoles'
    if ($null -ne $map) {
        $property = $map.PSObject.Properties[$SemanticRole]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace(
            [string]$property.Value
        )) {
            return [string]$property.Value
        }
    }
    $fallback = [ordered]@{
        innkeeper = 'DP_INNKEEPER_RUMOR'
        witness = 'DP_TAVERN_WITNESS'
    }
    if (-not $fallback.Contains($SemanticRole)) {
        throw "Unknown semantic dialogue role '$SemanticRole'."
    }
    return [string]$fallback[$SemanticRole]
}

function Get-CaseKitKcd2ActorDialogueRoleName {
    param([Parameter(Mandatory)][string]$EntityName)

    $normalized = $EntityName.Trim().ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(
        "darkpassenger-dialogue-actor|$normalized"
    )
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return 'DP_ACTOR_' +
        [System.Convert]::ToHexString($hash).Substring(0, 24)
}

function Get-CaseKitKcd2ActorDialogueRoleId {
    param([Parameter(Mandatory)][string]$EntityName)

    $normalized = $EntityName.Trim().ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(
        "darkpassenger-dialogue-role-id|$normalized"
    )
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $hex = [System.Convert]::ToHexString($hash).ToLowerInvariant().Substring(0, 32)
    return '{0}-{1}-{2}-{3}-{4}' -f `
        $hex.Substring(0, 8),
        $hex.Substring(8, 4),
        $hex.Substring(12, 4),
        $hex.Substring(16, 4),
        $hex.Substring(20, 12)
}

function Get-CaseKitKcd2SlotDialogueRoleName {
    param(
        [Parameter(Mandatory)][int]$CaseCode,
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$Settlement,
        [Parameter(Mandatory)][string]$SemanticRole
    )

    $seed = @(
        $CaseCode,
        $Region.Trim().ToLowerInvariant(),
        $Settlement.Trim().ToLowerInvariant(),
        $SemanticRole.Trim().ToLowerInvariant()
    ) -join '|'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(
        "darkpassenger-dialogue-slot|$seed"
    )
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return 'DP_SLOT_' +
        [System.Convert]::ToHexString($hash).Substring(0, 24)
}

function Get-CaseKitKcd2SlotDialogueRoleId {
    param([Parameter(Mandatory)][string]$RoleName)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes(
        'darkpassenger-dialogue-slot-role-id|' +
        $RoleName.Trim().ToLowerInvariant()
    )
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $hex = [System.Convert]::ToHexString($hash).ToLowerInvariant().Substring(0, 32)
    return '{0}-{1}-{2}-{3}-{4}' -f `
        $hex.Substring(0, 8),
        $hex.Substring(8, 4),
        $hex.Substring(12, 4),
        $hex.Substring(16, 4),
        $hex.Substring(20, 12)
}

function Get-CaseKitKcd2EvidenceItemGuid {
    param(
        [Parameter(Mandatory)]$StoryAdapter,
        [Parameter(Mandatory)][string]$QualifiedId
    )

    $evidence = @($StoryAdapter.evidence | Where-Object {
        [string]$_.qualifiedId -eq $QualifiedId
    })
    if ($evidence.Count -ne 1) { return '' }
    $item = Get-CaseKitKcd2Property -Value $evidence[0] -Name 'item'
    if ($null -eq $item) { return '' }
    return [string](Get-CaseKitKcd2Property `
        -Value $item -Name 'guid' -DefaultValue '')
}

function Get-CaseKitKcd2NativeBindingSignature {
    param([Parameter(Mandatory)]$Variant)

    return ([ordered]@{
        rumorSource = [string]$Variant.bindings.rumorSource.entityName
        witness = [string]$Variant.bindings.witness.entityName
        evidenceContainer =
            [string]$Variant.bindings.evidenceContainer.entityGuid
    } | ConvertTo-Json -Depth 20 -Compress)
}

function ConvertTo-CaseKitKcd2SettlementBinding {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$StoryAdapter,
        [Parameter(Mandatory)]$Adapter,
        [Parameter(Mandatory)][object[]]$Variants,
        [object[]]$EligibleActorPools = @(),
        $SettlementProfile
    )

    $variant = @($Variants | Sort-Object rank, variantId)[0]
    $nativeSignature = Get-CaseKitKcd2NativeBindingSignature `
        -Variant $variant
    $coveredVariants = @($Variants | Where-Object {
        (Get-CaseKitKcd2NativeBindingSignature -Variant $_) -ceq
            $nativeSignature
    } | Sort-Object variantId)
    $roles = [ordered]@{}
    $rumorSource = $variant.bindings.rumorSource
    if ($null -ne $rumorSource) {
        $roles.innkeeper = [pscustomobject][ordered]@{
            entityName = [string]$rumorSource.entityName
            dialogueRole = Get-CaseKitKcd2SemanticDialogueRole `
                -Adapter $Adapter -SemanticRole 'innkeeper'
        }
    }
    $witness = $variant.bindings.witness
    if ($null -ne $witness) {
        $roles.witness = [pscustomobject][ordered]@{
            entityName = [string]$witness.entityName
            dialogueRole = Get-CaseKitKcd2SemanticDialogueRole `
                -Adapter $Adapter -SemanticRole 'witness'
        }
    }

    $documentEvidence = @($StoryAdapter.evidence | Where-Object {
        [string]$_.kind -eq 'document'
    })
    if ($documentEvidence.Count -gt 0 -and
        $null -ne $variant.bindings.evidenceContainer) {
        $qualifiedId = [string]$documentEvidence[0].qualifiedId
        $documentGuid = Get-CaseKitKcd2EvidenceItemGuid `
            -StoryAdapter $StoryAdapter -QualifiedId $qualifiedId
        if ([string]::IsNullOrWhiteSpace($documentGuid)) {
            throw "Story '$($Story.storyId)' document '$qualifiedId' has no item guid."
        }
        $roles.document = [pscustomobject][ordered]@{
            containerGuid = [string]$variant.bindings.evidenceContainer.entityGuid
            documentGuid = $documentGuid
        }
    }

    if ($null -ne $SettlementProfile -and
        $null -ne $SettlementProfile.PSObject.Properties['native'] -and
        $null -ne $SettlementProfile.native.PSObject.Properties['roles']) {
        foreach ($property in $SettlementProfile.native.roles.PSObject.Properties) {
            if (-not $roles.Contains($property.Name)) {
                $roles[$property.Name] = $property.Value
                continue
            }
            $resolvedRole = $roles[$property.Name]
            foreach ($metadata in $property.Value.PSObject.Properties) {
                if ($null -ne $resolvedRole.PSObject.Properties[$metadata.Name]) {
                    continue
                }
                $resolvedRole | Add-Member `
                    -NotePropertyName $metadata.Name `
                    -NotePropertyValue $metadata.Value
            }
        }
    }

    $slotDialogueRoles = [ordered]@{}
    foreach ($semanticRole in 'innkeeper', 'witness') {
        $slotDialogueRoles[$semanticRole] =
            Get-CaseKitKcd2SlotDialogueRoleName `
                -CaseCode ([int]$Story.caseCode) `
                -Region ([string]$variant.region) `
                -Settlement ([string]$variant.settlement) `
                -SemanticRole $semanticRole
        if (-not $roles.Contains($semanticRole)) { continue }
        $roleBinding = $roles[$semanticRole]
        $entityName = [string]$roleBinding.entityName
        if ([string]::IsNullOrWhiteSpace($entityName)) { continue }
        $roleBinding.dialogueRole = $slotDialogueRoles[$semanticRole]
    }
    $actorPools = [ordered]@{}
    $slotRoleMap = [ordered]@{
        rumorSource = 'innkeeper'
        witness = 'witness'
        target = 'target'
    }
    foreach ($slotName in $slotRoleMap.Keys) {
        $semanticRole = [string]$slotRoleMap[$slotName]
        $candidates = [System.Collections.Generic.List[object]]::new()
        $knownEntities = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($pool in @($EligibleActorPools | Where-Object {
            [string]$_.slotName -ceq [string]$slotName
        })) {
            foreach ($candidate in @($pool.candidates | Sort-Object `
                candidateOrder, entityName)) {
                $entityName = [string]$candidate.entityName
                if ([string]::IsNullOrWhiteSpace($entityName) -or
                    -not $knownEntities.Add($entityName)) { continue }
                $candidates.Add([pscustomobject][ordered]@{
                    candidateOrder = [int]$candidate.candidateOrder
                    entityName = $entityName
                    entityGuid = [string]$candidate.entityGuid
                    soulGuid = [string]$candidate.soulGuid
                    dialogueRole = $slotDialogueRoles[$semanticRole]
                })
            }
        }
        if ($candidates.Count -gt 0) {
            $actorPools[$semanticRole] = $candidates.ToArray()
        }
    }
    return [pscustomobject][ordered]@{
        caseCode = [int]$Story.caseCode
        storyId = [string]$Story.storyId
        region = [string]$variant.region
        settlement = [string]$variant.settlement
        nativeVariantIds = @($coveredVariants |
            ForEach-Object { [string]$_.variantId })
        roles = [pscustomobject]$roles
        actorPools = [pscustomobject]$actorPools
    }
}

function ConvertTo-CaseKitKcd2BackendInput {
    param(
        [Parameter(Mandatory)]$CompiledDefinitions,
        [Parameter(Mandatory)]$Adapter,
        [object[]]$SettlementProfiles = @()
    )

    if ([string]$CompiledDefinitions.sourceFormat -ne
        'casekit-compiled-definitions-v1') {
        throw 'KCD2 backend requires compiled CaseKit definitions.'
    }
    $storyMap = New-CaseKitKcd2Map `
        -Values @($CompiledDefinitions.stories) `
        -KeySelector { param($entry) [string]$entry.storyId } `
        -Kind 'Compiled StoryPack'
    $adapterMap = New-CaseKitKcd2Map -Values @($Adapter.stories) `
        -KeySelector { param($entry) [string]$entry.storyId } `
        -Kind 'KCD2 story adapter'
    $caseSpecs = [System.Collections.Generic.List[object]]::new()
    $settlementBindings = [System.Collections.Generic.List[object]]::new()
    $profileMap = @{}
    foreach ($profile in @($SettlementProfiles)) {
        $key = "$([string]$profile.region)/$([string]$profile.settlement)"
        $profileMap[$key] = $profile
    }
    foreach ($story in @($CompiledDefinitions.stories | Sort-Object caseCode)) {
        $storyId = [string]$story.storyId
        if (-not $adapterMap.Contains($storyId)) {
            throw "Compiled StoryPack '$storyId' has no KCD2 adapter."
        }
        $storyAdapter = $adapterMap[$storyId]
        $migrationAnchor = Get-CaseKitKcd2Property `
            -Value $storyAdapter -Name 'migrationAnchor'
        $anchorRegion = [string](Get-CaseKitKcd2Property `
            -Value $migrationAnchor -Name 'region' -DefaultValue '')
        $anchorSettlement = [string](Get-CaseKitKcd2Property `
            -Value $migrationAnchor -Name 'settlement' -DefaultValue '')
        $variants = @($CompiledDefinitions.variants | Where-Object {
            $_.storyId -eq $storyId
        } | Sort-Object rank, variantId)
        if ($variants.Count -lt 1) {
            throw "Story '$storyId' has no compiled variant."
        }
        $anchor = @($variants | Where-Object {
            [string]$_.region -eq $anchorRegion -and
            [string]$_.settlement -eq $anchorSettlement
        } | Sort-Object rank, variantId)[0]
        if ($null -eq $anchor) { $anchor = $variants[0] }
        $caseSpec = ConvertTo-CaseKitKcd2CaseSpec `
            -CompiledStory $story -Variant $anchor `
            -StoryAdapter $storyAdapter
        $supportedRegions = @($variants.region | Sort-Object -Unique)
        $regionalShells = [ordered]@{}
        foreach ($supportedRegion in $supportedRegions) {
            $regionProperty = $Adapter.nativeRegions.PSObject.Properties[
                [string]$supportedRegion
            ]
            if ($null -eq $regionProperty) {
                throw "Story '$storyId' compiled for unsupported native " +
                    "region '$supportedRegion'."
            }
            $regionalShells[[string]$supportedRegion] =
                Copy-CaseKitKcd2Value -Value $regionProperty.Value
        }
        $caseSpec.constraints | Add-Member -NotePropertyName regions `
            -NotePropertyValue $supportedRegions -Force
        $caseSpec.native | Add-Member -NotePropertyName regions `
            -NotePropertyValue ([pscustomobject]$regionalShells) -Force
        $caseSpecs.Add($caseSpec)
        foreach ($group in @($variants | Group-Object region, settlement |
            Sort-Object Name)) {
            $groupVariants = @($group.Group | Sort-Object rank, variantId)
            $region = [string]$groupVariants[0].region
            $settlement = [string]$groupVariants[0].settlement
            $profileKey = "$region/$settlement"
            $profile = if ($profileMap.ContainsKey($profileKey)) {
                $profileMap[$profileKey]
            }
            else { $null }
            $settlementBindings.Add((ConvertTo-CaseKitKcd2SettlementBinding `
                -Story $story -StoryAdapter $storyAdapter `
                -Adapter $Adapter -Variants $groupVariants `
                -EligibleActorPools @($CompiledDefinitions.eligibleActorPools |
                    Where-Object {
                        [string]$_.storyId -ceq $storyId -and
                        [string]$_.region -ceq $region -and
                        [string]$_.settlement -ceq $settlement
                    }) `
                -SettlementProfile $profile))
        }
    }

    $dialogueRoleDefinitions = [System.Collections.Generic.List[object]]::new()
    $roleNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($definition in @($Adapter.dialogueRoles)) {
        $copy = Copy-CaseKitKcd2Value -Value $definition
        if ($roleNames.Add([string]$copy.name)) {
            $dialogueRoleDefinitions.Add($copy)
        }
    }
    foreach ($binding in $settlementBindings) {
        $actorBindings = [System.Collections.Generic.List[object]]::new()
        foreach ($semanticRole in 'innkeeper', 'witness') {
            $property = $binding.roles.PSObject.Properties[$semanticRole]
            if ($null -ne $property) { $actorBindings.Add($property.Value) }
        }
        foreach ($pool in @($binding.actorPools.PSObject.Properties)) {
            foreach ($candidate in @($pool.Value)) {
                $actorBindings.Add($candidate)
            }
        }
        foreach ($actorBinding in $actorBindings) {
            $entityName = [string]$actorBinding.entityName
            $roleName = [string]$actorBinding.dialogueRole
            if ([string]::IsNullOrWhiteSpace($entityName) -or
                [string]::IsNullOrWhiteSpace($roleName) -or
                -not $roleNames.Add($roleName)) {
                continue
            }
            $dialogueRoleDefinitions.Add([pscustomobject][ordered]@{
                name = $roleName
                roleId = Get-CaseKitKcd2SlotDialogueRoleId -RoleName $roleName
                metaRole = 'NPC'
            })
        }
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        caseSpecs = $caseSpecs.ToArray()
        bindings = [pscustomobject][ordered]@{
            schemaVersion = 1
            dialogueRoles = $dialogueRoleDefinitions.ToArray()
            settlements = $settlementBindings.ToArray()
        }
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-CaseKitKcd2BackendInput',
    'ConvertTo-CaseKitKcd2GuidancePresentation',
    'Read-CaseKitKcd2Adapter'
)
