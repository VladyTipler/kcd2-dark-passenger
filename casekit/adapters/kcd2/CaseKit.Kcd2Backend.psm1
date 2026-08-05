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
    if ([int]$adapter.schemaVersion -ne 1) {
        throw 'KCD2 adapter metadata schemaVersion must be 1.'
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

function ConvertTo-CaseKitKcd2Overheard {
    param(
        [Parameter(Mandatory)]$OverheardAdapter,
        [Parameter(Mandatory)]$StoryAdapter,
        [Parameter(Mandatory)]$EvidenceMap,
        [Parameter(Mandatory)]$DialogueMap
    )

    $dialogue = $DialogueMap[[string]$OverheardAdapter.dialogueId]
    if ($null -eq $dialogue) {
        throw "Overheard dialogue '$($OverheardAdapter.dialogueId)' not found."
    }
    return [pscustomobject][ordered]@{
        evidenceId = [string](@(ConvertTo-CaseKitKcd2EvidenceIds `
            -QualifiedIds @([string]$OverheardAdapter.evidenceQualifiedId) `
            -EvidenceMap $EvidenceMap)[0])
        graphName = [string]$OverheardAdapter.graphName
        fileName = [string]$OverheardAdapter.fileName
        rootKey = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
            -Asset ([string]$OverheardAdapter.rootAsset)
        decisionAlias = [string]$OverheardAdapter.decisionAlias
        sequenceName = [string]$OverheardAdapter.sequenceName
        cluePort = [string]$OverheardAdapter.cluePort
        clueLabel = [string]$OverheardAdapter.clueLabel
        hearingDistance = [int]$OverheardAdapter.hearingDistance
        repeatAfterSeconds = [int]$OverheardAdapter.repeatAfterSeconds
        availableTag = [int]$OverheardAdapter.availableTag
        context = [string]$OverheardAdapter.context
        responses = @(ConvertTo-CaseKitKcd2Responses `
            -Variant @($dialogue.variants)[0] `
            -DialogueAdapter $OverheardAdapter `
            -StoryAdapter $StoryAdapter)
    }
}

function ConvertTo-CaseKitKcd2Evidence {
    param(
        [Parameter(Mandatory)]$CompiledEvidence,
        [Parameter(Mandatory)]$EvidenceAdapter,
        [Parameter(Mandatory)]$StoryAdapter,
        [Parameter(Mandatory)]$EvidenceMap,
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
    $overheard = Get-CaseKitKcd2Property `
        -Value $StoryAdapter.native -Name 'overheard'
    if ($null -ne $overheard) {
        $native.overheard = ConvertTo-CaseKitKcd2Overheard `
            -OverheardAdapter $overheard -StoryAdapter $StoryAdapter `
            -EvidenceMap $evidenceMap -DialogueMap $dialogueMap
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
            -EvidenceAdapter $evidenceAdapterMap[[string]$_.qualifiedId] `
            -StoryAdapter $StoryAdapter -EvidenceMap $evidenceMap `
            -ResolvedPlacement $(if (
                $placementMap.Contains([string]$_.qualifiedId)
            ) { $placementMap[[string]$_.qualifiedId] } else { $null })
    })
    $localization = [ordered]@{
        ru = [ordered]@{}
        en = [ordered]@{}
    }
    foreach ($asset in @($StoryAdapter.emitLocalizationAssets)) {
        $nativeKey = Get-CaseKitKcd2NativeKey -StoryAdapter $StoryAdapter `
            -Asset ([string]$asset)
        foreach ($language in @('ru', 'en')) {
            $localization[$language][$nativeKey] = Get-CaseKitKcd2AssetValue `
                -CompiledStory $CompiledStory -Language $language `
                -Asset ([string]$asset)
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

function ConvertTo-CaseKitKcd2BackendInput {
    param(
        [Parameter(Mandatory)]$CompiledDefinitions,
        [Parameter(Mandatory)]$Adapter,
        [Parameter(Mandatory)][object[]]$SettlementProfiles
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
    $profileMap = New-CaseKitKcd2Map -Values $SettlementProfiles `
        -KeySelector {
            param($entry)
            "$([string]$entry.region)/$([string]$entry.settlement)"
        } -Kind 'Settlement profile'

    $caseSpecs = [System.Collections.Generic.List[object]]::new()
    $usedProfiles = [ordered]@{}
    foreach ($story in @($CompiledDefinitions.stories | Sort-Object caseCode)) {
        $storyId = [string]$story.storyId
        if (-not $adapterMap.Contains($storyId)) {
            throw "Compiled StoryPack '$storyId' has no KCD2 adapter."
        }
        $storyAdapter = $adapterMap[$storyId]
        $region = [string]$storyAdapter.legacyVariant.region
        $settlement = [string]$storyAdapter.legacyVariant.settlement
        $variants = @($CompiledDefinitions.variants | Where-Object {
            $_.storyId -eq $storyId -and $_.region -eq $region -and
            $_.settlement -eq $settlement
        } | Sort-Object rank, variantId)
        if ($variants.Count -lt 1) {
            throw "Story '$storyId' requires a migration variant " +
                "for '$region/$settlement'; found none."
        }
        $profileKey = "$region/$settlement"
        if (-not $profileMap.Contains($profileKey)) {
            throw "Story '$storyId' references missing profile '$profileKey'."
        }
        $profile = $profileMap[$profileKey]
        $nativeProfile = Get-CaseKitKcd2Property `
            -Value $profile -Name 'native'
        if ($null -eq $nativeProfile) {
            throw "Settlement profile '$profileKey' has no native bindings."
        }
        $usedProfiles[$profileKey] = $profile
        $caseSpecs.Add((ConvertTo-CaseKitKcd2CaseSpec `
            -CompiledStory $story -Variant $variants[0] `
            -StoryAdapter $storyAdapter))
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        caseSpecs = $caseSpecs.ToArray()
        bindings = [pscustomobject][ordered]@{
            schemaVersion = 1
            dialogueRoles = @(Copy-CaseKitKcd2Value `
                -Value @($Adapter.dialogueRoles))
            settlements = @($usedProfiles.Values | ForEach-Object {
                [pscustomobject][ordered]@{
                    region = [string]$_.region
                    settlement = [string]$_.settlement
                    roles = Copy-CaseKitKcd2Value -Value $_.native.roles
                }
            })
        }
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-CaseKitKcd2BackendInput',
    'Read-CaseKitKcd2Adapter'
)
