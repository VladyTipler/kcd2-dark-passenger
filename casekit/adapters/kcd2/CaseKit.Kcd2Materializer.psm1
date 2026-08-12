Set-StrictMode -Version Latest

function Get-CaseKitMaterializerProperty {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $null
    }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Copy-CaseKitMaterializerValue {
    param([Parameter(Mandatory)]$Value)

    return ($Value | ConvertTo-Json -Depth 100) |
        ConvertFrom-Json -Depth 100
}

function ConvertTo-CaseKitCompiledTrophyDefinition {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Variant
    )

    $definition = Get-CaseKitMaterializerProperty `
        -Value $Story -Name 'trophyDefinition'
    if ($null -eq $definition) { return $null }

    $descriptionAsset = [string](Get-CaseKitMaterializerProperty `
        -Value $definition -Name 'descriptionAsset')
    $description = [ordered]@{}
    foreach ($language in @('ru', 'en')) {
        $languageAssets = $Variant.renderedAssets.PSObject.Properties[
            $language
        ].Value
        $asset = Get-CaseKitMaterializerProperty `
            -Value $languageAssets -Name $descriptionAsset
        if ([string]::IsNullOrWhiteSpace([string]$asset)) {
            throw "Variant '$($Variant.variantId)' trophy description " +
                "asset '$descriptionAsset' is unavailable for $language."
        }
        $description[$language] = [string]$asset
    }
    return [pscustomobject][ordered]@{
        preset = [string](Get-CaseKitMaterializerProperty `
            -Value $definition -Name 'preset')
        item = Copy-CaseKitMaterializerValue -Value (
            Get-CaseKitMaterializerProperty -Value $definition -Name 'item'
        )
        description = [pscustomobject]$description
    }
}

function New-CaseKitMaterializerMap {
    param(
        [Parameter(Mandatory)][object[]]$Values,
        [Parameter(Mandatory)][scriptblock]$KeySelector,
        [Parameter(Mandatory)][string]$Kind
    )

    $map = [ordered]@{}
    foreach ($value in $Values) {
        $key = [string](& $KeySelector $value)
        if ([string]::IsNullOrWhiteSpace($key)) {
            throw "$Kind has no stable key."
        }
        if ($map.Contains($key)) {
            throw "$Kind '$key' is duplicated."
        }
        $map[$key] = $value
    }
    return $map
}

function Get-CaseKitStableIdentityMaps {
    param([Parameter(Mandatory)]$StableIdRegistry)

    if ([int]$StableIdRegistry.schemaVersion -ne 1) {
        throw 'Stable ID registry schemaVersion must be 1.'
    }

    $storyMap = New-CaseKitMaterializerMap `
        -Values @($StableIdRegistry.stories) `
        -KeySelector { param($entry) [string]$entry.storyId } `
        -Kind 'Stable story identity'
    $caseCodes = [System.Collections.Generic.HashSet[int]]::new()
    $caseIds = [System.Collections.Generic.HashSet[string]]::new()
    $evidenceCodes = [System.Collections.Generic.HashSet[int]]::new()
    $evidenceIds = [System.Collections.Generic.HashSet[string]]::new()
    $evidenceMaps = [ordered]@{}
    foreach ($storyId in $storyMap.Keys) {
        $entry = $storyMap[$storyId]
        $caseId = [string]$entry.caseId
        if ([string]::IsNullOrWhiteSpace($caseId)) {
            throw "Stable case ID for '$storyId' is required."
        }
        if (-not $caseIds.Add($caseId)) {
            throw "Stable case ID '$caseId' is duplicated."
        }
        $caseCode = [int]$entry.caseCode
        if ($caseCode -le 0) {
            throw "Stable case code for '$storyId' must be positive."
        }
        if (-not $caseCodes.Add($caseCode)) {
            throw "Stable case code '$caseCode' is duplicated."
        }
        if ([double]$entry.weight -le 0) {
            throw "Stable case weight for '$storyId' must be positive."
        }

        $evidenceMap = [ordered]@{}
        foreach ($evidence in @($entry.evidence)) {
            $qualifiedId = "$([string]$evidence.threadId)/" +
                [string]$evidence.stepId
            if ($qualifiedId -eq '/') {
                throw "Stable evidence identity for '$storyId' has no key."
            }
            if ($evidenceMap.Contains($qualifiedId)) {
                throw "Stable evidence identity '$storyId/$qualifiedId' " +
                    'is duplicated.'
            }
            $code = [int]$evidence.code
            $legacyId = [string]$evidence.legacyId
            if ([string]::IsNullOrWhiteSpace($legacyId)) {
                throw "Stable evidence ID for '$storyId/$qualifiedId' " +
                    'is required.'
            }
            if (-not $evidenceIds.Add($legacyId)) {
                throw "Stable evidence ID '$legacyId' is duplicated."
            }
            if ($code -le 0) {
                throw "Stable evidence code for '$storyId/$qualifiedId' " +
                    'must be positive.'
            }
            if (-not $evidenceCodes.Add($code)) {
                throw "Stable evidence code '$code' is duplicated."
            }
            $evidenceMap[$qualifiedId] = $evidence
        }
        $evidenceMaps[$storyId] = $evidenceMap
    }

    return [pscustomobject][ordered]@{
        stories = $storyMap
        evidence = $evidenceMaps
    }
}

function ConvertTo-CaseKitCompiledEvidence {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Deck,
        [Parameter(Mandatory)]$StableEvidenceMap
    )

    $archetypeMap = New-CaseKitMaterializerMap `
        -Values @($Deck.archetypes) `
        -KeySelector { param($entry) [string]$entry.id } `
        -Kind 'InvestigationArchetype'
    $moduleMap = New-CaseKitMaterializerMap `
        -Values @($Deck.evidenceModules) `
        -KeySelector { param($entry) [string]$entry.id } `
        -Kind 'EvidenceModule'
    $usedStableIds = [System.Collections.Generic.HashSet[string]]::new()
    $compiled = [System.Collections.Generic.List[object]]::new()

    foreach ($thread in @($Story.threads)) {
        $threadId = [string]$thread.id
        $archetypeId = [string]$thread.archetypeId
        if (-not $archetypeMap.Contains($archetypeId)) {
            throw "Story '$($Story.id)' references unknown archetype " +
                "'$archetypeId'."
        }
        $archetype = $archetypeMap[$archetypeId]
        foreach ($step in @($thread.steps)) {
            $stepId = [string]$step.id
            $qualifiedId = "$threadId/$stepId"
            if (-not $StableEvidenceMap.Contains($qualifiedId)) {
                throw "Missing stable evidence code for '$($Story.id)/" +
                    "$qualifiedId'."
            }
            $null = $usedStableIds.Add($qualifiedId)
            $moduleId = [string]$step.action.evidenceModule
            if (-not $moduleMap.Contains($moduleId)) {
                throw "Story '$($Story.id)' references unknown evidence " +
                    "module '$moduleId'."
            }
            $rule = $archetype.evidenceRules.PSObject.Properties[$moduleId]
            if ($null -eq $rule) {
                throw "Archetype '$archetypeId' has no confidence rule for " +
                    "'$moduleId'."
            }
            $compiled.Add([pscustomobject][ordered]@{
                id = $stepId
                qualifiedId = $qualifiedId
                legacyId = [string]$StableEvidenceMap[$qualifiedId].legacyId
                code = [int]$StableEvidenceMap[$qualifiedId].code
                threadId = $threadId
                archetypeId = $archetypeId
                kind = [string]$step.kind
                evidenceModule = $moduleId
                confidence = [int]$rule.Value.confidence
                item = if ($null -ne (
                    Get-CaseKitMaterializerProperty `
                        -Value $step.action -Name 'item'
                )) {
                    Copy-CaseKitMaterializerValue -Value (
                        Get-CaseKitMaterializerProperty `
                            -Value $step.action -Name 'item'
                    )
                }
                else { $null }
                placement = if ($null -ne (
                    Get-CaseKitMaterializerProperty `
                        -Value $step.action -Name 'placement'
                )) {
                    Copy-CaseKitMaterializerValue -Value (
                        Get-CaseKitMaterializerProperty `
                            -Value $step.action -Name 'placement'
                    )
                }
                else { $null }
                bindings = Copy-CaseKitMaterializerValue `
                    -Value $step.action.bindings
                requiresFacts = @($step.requiresFacts | ForEach-Object {
                    [string]$_
                })
                presentations = @(Copy-CaseKitMaterializerValue `
                    -Value @($step.presentations))
                result = Copy-CaseKitMaterializerValue -Value $step.result
            })
        }
    }

    foreach ($stableId in $StableEvidenceMap.Keys) {
        if (-not $usedStableIds.Contains([string]$stableId)) {
            throw "Stable evidence identity '$($Story.id)/$stableId' does " +
                'not match an authored step.'
        }
    }
    return $compiled.ToArray()
}

function ConvertTo-CaseKitCompiledOverheardScenes {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$StableEvidenceMap
    )

    $scenes = [System.Collections.Generic.List[object]]::new()
    foreach ($thread in @($Story.threads)) {
        foreach ($step in @($thread.steps)) {
            if ([string]$step.action.evidenceModule -ne
                'overheard-dialogue') {
                continue
            }
            $qualifiedId = "$([string]$thread.id)/$([string]$step.id)"
            if (-not $StableEvidenceMap.Contains($qualifiedId)) {
                throw "Missing stable evidence code for '$($Story.id)/" +
                    "$qualifiedId'."
            }
            $scenes.Add([pscustomobject][ordered]@{
                qualifiedId = $qualifiedId
                evidenceId = [string]$StableEvidenceMap[$qualifiedId].legacyId
                threadId = [string]$thread.id
                stepId = [string]$step.id
                activation = Copy-CaseKitMaterializerValue `
                    -Value $step.action.activation
                bindingSlots = [pscustomobject][ordered]@{
                    speakerA = [string]$step.action.bindings.speakerA
                    speakerB = [string]$step.action.bindings.speakerB
                }
            })
        }
    }
    return $scenes.ToArray()
}

function Resolve-CaseKitCompiledOverheardScenes {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Scenes,
        [Parameter(Mandatory)]$Variant
    )

    return @($Scenes | ForEach-Object {
        $scene = $_
        $speakerAProperty = $Variant.bindings.PSObject.Properties[
            [string]$scene.bindingSlots.speakerA
        ]
        $speakerBProperty = $Variant.bindings.PSObject.Properties[
            [string]$scene.bindingSlots.speakerB
        ]
        if ($null -eq $speakerAProperty -or
            $null -eq $speakerBProperty -or
            $null -eq $speakerAProperty.Value -or
            $null -eq $speakerBProperty.Value) {
            return
        }
        [pscustomobject][ordered]@{
            qualifiedId = [string]$scene.qualifiedId
            evidenceId = [string]$scene.evidenceId
            activation = Copy-CaseKitMaterializerValue `
                -Value $scene.activation
            speakers = [pscustomobject][ordered]@{
                speakerA = Copy-CaseKitMaterializerValue `
                    -Value $speakerAProperty.Value
                speakerB = Copy-CaseKitMaterializerValue `
                    -Value $speakerBProperty.Value
            }
        }
    })
}

function ConvertTo-CaseKitCompiledDefinitions {
    param(
        [Parameter(Mandatory)]$Deck,
        [Parameter(Mandatory)]$CompatibilityReport,
        [Parameter(Mandatory)]$StableIdRegistry
    )

    if ([int]$Deck.schemaVersion -ne 2 -or
        [string]$Deck.sourceFormat -ne 'casekit-authoring-v2') {
        throw 'Compiled definitions require a normalized CaseKit v2 deck.'
    }
    if ([int]$CompatibilityReport.schemaVersion -ne 1 -or
        [string]$CompatibilityReport.sourceFormat -ne
            'casekit-compatibility-v1') {
        throw 'Compiled definitions require a CaseKit compatibility report.'
    }

    $identities = Get-CaseKitStableIdentityMaps `
        -StableIdRegistry $StableIdRegistry
    $storyMap = New-CaseKitMaterializerMap -Values @($Deck.stories) `
        -KeySelector { param($entry) [string]$entry.id } -Kind 'StoryPack'
    $accepted = @($CompatibilityReport.accepted | Sort-Object `
        storyId, compositionId, region, settlement, rank, variantId)
    $acceptedStoryIds = @($accepted | ForEach-Object {
        [string]$_.storyId
    } | Sort-Object -Unique)
    $compiledStories = [System.Collections.Generic.List[object]]::new()

    foreach ($storyId in $acceptedStoryIds) {
        if (-not $storyMap.Contains($storyId)) {
            throw "Compatibility report references unknown StoryPack " +
                "'$storyId'."
        }
        if (-not $identities.stories.Contains($storyId)) {
            throw "Missing stable case identity for '$storyId'."
        }
        $story = $storyMap[$storyId]
        $stableStory = $identities.stories[$storyId]
        $storyJournal = Get-CaseKitMaterializerProperty `
            -Value $story -Name 'journal'
        $overheardScenes = @(ConvertTo-CaseKitCompiledOverheardScenes `
            -Story $story `
            -StableEvidenceMap $identities.evidence[$storyId])
        $compiledStories.Add([pscustomobject][ordered]@{
            schemaVersion = 1
            storyId = $storyId
            caseId = [string]$stableStory.caseId
            caseCode = [int]$stableStory.caseCode
            weight = [double]$stableStory.weight
            archetypeIds = @($story.archetypes | ForEach-Object {
                [string]$_
            })
            truth = Copy-CaseKitMaterializerValue -Value $story.truth
            facts = @(Copy-CaseKitMaterializerValue -Value @($story.facts))
            reveal = Copy-CaseKitMaterializerValue -Value $story.reveal
            journal = if ($null -eq $storyJournal) { $null } else {
                Copy-CaseKitMaterializerValue -Value $storyJournal
            }
            threads = @(Copy-CaseKitMaterializerValue `
                -Value @($story.threads))
            evidence = @(ConvertTo-CaseKitCompiledEvidence -Story $story `
                -Deck $Deck `
                -StableEvidenceMap $identities.evidence[$storyId])
            overheardScenes = $overheardScenes
            dialogues = @(Copy-CaseKitMaterializerValue `
                -Value @($story.dialogues))
            documents = @(Copy-CaseKitMaterializerValue `
                -Value @($story.documents))
            localization = [pscustomobject][ordered]@{
                ru = Copy-CaseKitMaterializerValue -Value $story.assets.ru
                en = Copy-CaseKitMaterializerValue -Value $story.assets.en
            }
        })
    }

    $compiledVariants = @($accepted | ForEach-Object {
        $variant = $_
        $story = $storyMap[[string]$variant.storyId]
        if (-not $identities.stories.Contains([string]$variant.storyId)) {
            throw "Missing stable case identity for '$($variant.storyId)'."
        }
        [pscustomobject][ordered]@{
            schemaVersion = 1
            variantId = [string]$variant.variantId
            storyId = [string]$variant.storyId
            caseId = [string]$identities.stories[
                [string]$variant.storyId
            ].caseId
            caseCode = [int]$identities.stories[
                [string]$variant.storyId
            ].caseCode
            compositionId = [string]$variant.compositionId
            archetypeIds = @($variant.archetypeIds | ForEach-Object {
                [string]$_
            })
            region = [string]$variant.region
            settlement = [string]$variant.settlement
            rank = [int]$variant.rank
            bindingSeed = [string]$variant.bindingSeed
            bindings = Copy-CaseKitMaterializerValue `
                -Value $variant.bindings
            evidencePlacements = @(Copy-CaseKitMaterializerValue `
                -Value @($variant.evidencePlacements))
            guidanceBindings = @(Copy-CaseKitMaterializerValue `
                -Value @($variant.guidanceBindings))
            overheardScenes = @(Resolve-CaseKitCompiledOverheardScenes `
                -Scenes @(ConvertTo-CaseKitCompiledOverheardScenes `
                    -Story $story `
                    -StableEvidenceMap $identities.evidence[
                        [string]$variant.storyId
                    ]) `
                -Variant $variant)
            renderedAssets = Copy-CaseKitMaterializerValue `
                -Value $variant.renderedAssets
            trophyDefinition =
                ConvertTo-CaseKitCompiledTrophyDefinition `
                    -Story $story -Variant $variant
        }
    })

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        sourceFormat = 'casekit-compiled-definitions-v1'
        stories = $compiledStories.ToArray()
        variants = $compiledVariants
    }
}

Export-ModuleMember -Function 'ConvertTo-CaseKitCompiledDefinitions'
