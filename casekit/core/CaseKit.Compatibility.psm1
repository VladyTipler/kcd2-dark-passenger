Set-StrictMode -Version Latest

$templateModulePath = Join-Path $PSScriptRoot 'CaseKit.Templates.psm1'
Import-Module $templateModulePath -Force
$identityModulePath = Join-Path $PSScriptRoot 'CaseKit.Identity.psm1'
Import-Module $identityModulePath -Force

$script:CaseKitForbiddenVictimFlags = @(
    'actor.dead_template',
    'actor.immortal',
    'quest.critical',
    'story.critical'
)

function Get-CaseKitCompatibilityProperty {
    param(
        $Value,
        [Parameter(Mandatory)][string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $Value) {
        return $DefaultValue
    }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }
    return $property.Value
}

function Get-CaseKitStableBindingHash {
    param([Parameter(Mandatory)][string]$Seed)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-CaseKitIdentityRank {
    param($Entity)

    switch ([string](Get-CaseKitCompatibilityProperty `
        -Value $Entity -Name 'identityMode' -DefaultValue '')) {
        'named' { return 3 }
        'titled' { return 2 }
        'anonymous' { return 1 }
        default { return 0 }
    }
}

function Get-CaseKitCandidateOrder {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Candidates
    )

    return @($Candidates | Sort-Object `
        @{ Expression = {
            [int](Get-CaseKitCompatibilityProperty `
                -Value $_ -Name 'authoredPreference' -DefaultValue 0)
        }; Descending = $true }, `
        @{ Expression = { Get-CaseKitIdentityRank -Entity $_ }; Descending = $true }, `
        @{ Expression = { [string]$_.entityGuid } }, `
        @{ Expression = { [string]$_.entityName } })
}

function Merge-CaseKitCompatibilitySlots {
    param(
        [Parameter(Mandatory)]$Deck,
        [Parameter(Mandatory)]$Composition,
        [Parameter(Mandatory)][string]$StoryId
    )

    $archetypes = [ordered]@{}
    foreach ($archetype in @($Deck.archetypes)) {
        $archetypes[[string]$archetype.id] = $archetype
    }
    $slots = [ordered]@{}
    foreach ($archetypeId in @($Composition.archetypeIds)) {
        if (-not $archetypes.Contains([string]$archetypeId)) {
            throw "Story '$StoryId' references unknown archetype " +
                "'$archetypeId'."
        }
        foreach ($slot in $archetypes[[string]$archetypeId].slots.PSObject.Properties) {
            if (-not $slots.Contains($slot.Name)) {
                $slots[$slot.Name] = $slot.Value
                continue
            }
            $existing = $slots[$slot.Name] | ConvertTo-Json -Depth 20 -Compress
            $candidate = $slot.Value | ConvertTo-Json -Depth 20 -Compress
            if ($existing -ne $candidate) {
                throw "Story '$StoryId' composes incompatible slot " +
                    "'$($slot.Name)'."
            }
        }
    }
    return $slots
}

function Test-CaseKitCapabilitySet {
    param(
        [Parameter(Mandatory)]$Entity,
        [Parameter(Mandatory)][object[]]$RequiredCapabilities
    )

    $available = @(
        @($Entity.capabilities) + @($Entity.policyFlags) |
            ForEach-Object { [string]$_ } |
            Sort-Object -Unique
    )
    foreach ($capability in $RequiredCapabilities) {
        if ($available -notcontains [string]$capability) {
            return $false
        }
    }
    return $true
}

function Test-CaseKitVictimPolicy {
    param(
        [Parameter(Mandatory)]$Entity,
        [Parameter(Mandatory)]$Slot
    )

    if (-not (Test-CaseKitVictimSlot -Slot $Slot)) {
        return $true
    }
    foreach ($flag in @($Entity.policyFlags)) {
        if ($script:CaseKitForbiddenVictimFlags -contains [string]$flag) {
            return $false
        }
    }
    return $true
}

function Test-CaseKitVictimSlot {
    param([Parameter(Mandatory)]$Slot)

    return (
        @($Slot.capabilities) -contains 'victim.eligible' -or
        @($Slot.capabilities) -contains 'person.killable'
    )
}

function Test-CaseKitContainerPolicy {
    param(
        [Parameter(Mandatory)]$Entity,
        [Parameter(Mandatory)]$Slot
    )

    if ([string]$Entity.kind -ne 'container' -or
        @($Slot.capabilities) -notcontains 'container.evidence') {
        return $true
    }
    $capabilities = @($Entity.capabilities)
    return (
        $capabilities -notcontains 'container.shop' -and
        $capabilities -notcontains 'container.trade'
    )
}

function Get-CaseKitSlotCandidates {
    param(
        [Parameter(Mandatory)]$Slot,
        [Parameter(Mandatory)][string]$SlotName,
        [Parameter(Mandatory)]$Settlement,
        [Parameter(Mandatory)][object[]]$Entities
    )

    $entityType = [string]$Slot.entityType
    if ($entityType -eq 'settlement') {
        return @([pscustomobject][ordered]@{
            kind = 'settlement'
            entityName = [string]$Settlement.settlement
            entityGuid = ''
            region = [string]$Settlement.region
            settlement = [string]$Settlement.settlement
            identityMode = 'not_applicable'
            localized = $Settlement.localized
            capabilities = @()
            policyFlags = @()
        })
    }

    $kind = if ($entityType -eq 'actor') { 'actor' } else { 'container' }
    $identityModes = @(Get-CaseKitCompatibilityProperty `
        -Value $Slot -Name 'identityModes' -DefaultValue @())
    $candidates = @($Entities | Where-Object {
        if ([string]$_.kind -ne $kind) {
            return $false
        }
        if (-not (Test-CaseKitCapabilitySet -Entity $_ `
            -RequiredCapabilities @($Slot.capabilities))) {
            return $false
        }
        if (-not (Test-CaseKitVictimPolicy -Entity $_ -Slot $Slot)) {
            return $false
        }
        if (-not (Test-CaseKitContainerPolicy -Entity $_ -Slot $Slot)) {
            return $false
        }
        if ($identityModes.Count -gt 0 -and
            $identityModes -notcontains [string]$_.identityMode) {
            return $false
        }
        return $true
    })
    return @(Get-CaseKitCandidateOrder -Candidates $candidates)
}

function Get-CaseKitStoryEvidencePlacements {
    param([Parameter(Mandatory)]$Story)

    $placements = [System.Collections.Generic.List[object]]::new()
    foreach ($thread in @($Story.threads)) {
        foreach ($step in @($thread.steps)) {
            $placement = Get-CaseKitCompatibilityProperty `
                -Value $step.action -Name 'placement'
            if ($null -eq $placement) { continue }
            $containerSlot = [string](Get-CaseKitCompatibilityProperty `
                -Value $step.action.bindings -Name 'container' `
                -DefaultValue '')
            $placements.Add([pscustomobject][ordered]@{
                qualifiedId = "$([string]$thread.id)/$([string]$step.id)"
                mode = [string]$placement.mode
                actorSlot = [string](Get-CaseKitCompatibilityProperty `
                    -Value $placement -Name 'actor' -DefaultValue '')
                containerSlot = $containerSlot
            })
        }
    }
    return $placements.ToArray()
}

function Test-CaseKitContainerRelation {
    param(
        [Parameter(Mandatory)]$Container,
        [Parameter(Mandatory)]$Actor,
        [Parameter(Mandatory)][string]$RelationType
    )

    return @(
        @(Get-CaseKitCompatibilityProperty `
            -Value $Container -Name 'relations' -DefaultValue @()) |
            Where-Object {
                $targetGuid = [string](Get-CaseKitCompatibilityProperty `
                    -Value $_ -Name 'targetEntityGuid' -DefaultValue '')
                [string]$_.type -eq $RelationType -and (
                    [string]$_.targetEntityName -eq
                        [string]$Actor.entityName -or
                    (
                        -not [string]::IsNullOrWhiteSpace($targetGuid) -and
                        $targetGuid -eq
                            [string]$Actor.entityGuid
                    )
                )
            }
    ).Count -gt 0
}

function Resolve-CaseKitEvidencePlacements {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Bindings
    )

    $resolved = [System.Collections.Generic.List[object]]::new()
    foreach ($placement in @(Get-CaseKitStoryEvidencePlacements -Story $Story)) {
        $actor = if ([string]::IsNullOrWhiteSpace($placement.actorSlot)) {
            $null
        }
        elseif ($Bindings.Contains($placement.actorSlot)) {
            $Bindings[$placement.actorSlot]
        }
        else {
            return [pscustomobject]@{ valid = $false; placements = @() }
        }
        $container = if (
            [string]::IsNullOrWhiteSpace($placement.containerSlot)
        ) { $null }
        elseif ($Bindings.Contains($placement.containerSlot)) {
            $Bindings[$placement.containerSlot]
        }
        else {
            return [pscustomobject]@{ valid = $false; placements = @() }
        }

        if ($null -ne $container -and -not (
            Test-CaseKitContainerPolicy -Entity $container `
                -Slot ([pscustomobject]@{
                    capabilities = @('container.evidence')
                })
        )) {
            return [pscustomobject]@{ valid = $false; placements = @() }
        }

        switch ($placement.mode) {
            'world-container' {
                if ($null -eq $container) {
                    return [pscustomobject]@{
                        valid = $false
                        placements = @()
                    }
                }
            }
            'actor-inventory' {
                if ($null -eq $actor) {
                    return [pscustomobject]@{
                        valid = $false
                        placements = @()
                    }
                }
            }
            'actor-container' {
                if ($null -eq $actor -or $null -eq $container -or -not (
                    Test-CaseKitContainerRelation -Container $container `
                        -Actor $actor -RelationType 'personal-container-of'
                )) {
                    return [pscustomobject]@{
                        valid = $false
                        placements = @()
                    }
                }
            }
            'actor-home-container' {
                if ($null -eq $actor -or $null -eq $container -or -not (
                    Test-CaseKitContainerRelation -Container $container `
                        -Actor $actor -RelationType 'home-container-of'
                )) {
                    return [pscustomobject]@{
                        valid = $false
                        placements = @()
                    }
                }
            }
            default {
                return [pscustomobject]@{
                    valid = $false
                    placements = @()
                }
            }
        }

        $resolved.Add([pscustomobject][ordered]@{
            qualifiedId = [string]$placement.qualifiedId
            mode = [string]$placement.mode
            actorSlot = [string]$placement.actorSlot
            actorEntityName = if ($null -eq $actor) { '' } else {
                [string]$actor.entityName
            }
            actorEntityGuid = if ($null -eq $actor) { '' } else {
                [string]$actor.entityGuid
            }
            containerSlot = [string]$placement.containerSlot
            containerEntityName = if ($null -eq $container) { '' } else {
                [string]$container.entityName
            }
            containerEntityGuid = if ($null -eq $container) { '' } else {
                [string]$container.entityGuid
            }
        })
    }
    return [pscustomobject]@{
        valid = $true
        placements = $resolved.ToArray()
    }
}

function Get-CaseKitMissingSlotReason {
    param(
        [Parameter(Mandatory)]$Slot,
        [Parameter(Mandatory)][string]$SlotName,
        [Parameter(Mandatory)][object[]]$Entities
    )

    $kind = if ([string]$Slot.entityType -eq 'actor') {
        'actor'
    }
    else {
        'container'
    }
    $kindMatches = @($Entities | Where-Object {
        [string]$_.kind -eq $kind
    })
    foreach ($capability in @($Slot.capabilities)) {
        $found = @($kindMatches | Where-Object {
            Test-CaseKitCapabilitySet -Entity $_ `
                -RequiredCapabilities @([string]$capability)
        }).Count -gt 0
        if (-not $found) {
            return "required capability $capability not found for slot $SlotName"
        }
    }
    if (Test-CaseKitVictimSlot -Slot $Slot) {
        return "no policy-safe living target found for slot $SlotName"
    }
    return "no entity satisfies required semantics for slot $SlotName"
}

function Get-CaseKitLocalizedBinding {
    param(
        [Parameter(Mandatory)]$Binding,
        [Parameter(Mandatory)][ValidateSet('ru', 'en')][string]$Language
    )

    if ([string]$Binding.kind -eq 'actor') {
        $identity = Resolve-CaseKitEntityIdentity `
            -Entity $Binding -Language $Language
        return [ordered]@{
            identityMode = [string]$Binding.identityMode
            name = [string]$identity.name
            displayLabel = [string]$identity.displayLabel
            directionLabel = [string]$identity.directionLabel
            occupation = [string]$identity.occupation
        }
    }
    if ([string]$Binding.kind -eq 'settlement') {
        $localized = $Binding.localized.PSObject.Properties[$Language]
        if ($null -eq $localized) {
            throw "Settlement '$($Binding.settlement)' has no $Language localization."
        }
        return [ordered]@{
            identityMode = 'not_applicable'
            displayName = [string]$localized.Value.displayName
        }
    }
    $presentation = Get-CaseKitCompatibilityProperty `
        -Value $Binding -Name 'presentation'
    $localizedPresentation = if ($null -eq $presentation) {
        $null
    }
    else {
        $presentation.localized.PSObject.Properties[$Language]
    }
    if ($null -eq $localizedPresentation) {
        throw "Container '$($Binding.entityName)' has no $Language presentation."
    }
    return [ordered]@{
        identityMode = 'not_applicable'
        locationHint = [string]$localizedPresentation.Value.locationHint
    }
}

function Expand-CaseKitVariantAssets {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Bindings
    )

    $result = [ordered]@{}
    foreach ($language in @('ru', 'en')) {
        $localizedBindings = [ordered]@{}
        foreach ($slot in $Bindings.Keys) {
            if ($null -eq $Bindings[$slot]) {
                continue
            }
            $localizedBindings[$slot] = Get-CaseKitLocalizedBinding `
                -Binding $Bindings[$slot] -Language $language
        }
        $assets = [ordered]@{}
        $sourceAssets = $Story.assets.PSObject.Properties[$language].Value
        foreach ($asset in $sourceAssets.PSObject.Properties) {
            $assets[$asset.Name] = Expand-CaseKitTemplate `
                -Text ([string]$asset.Value) -Bindings $localizedBindings
        }
        $result[$language] = $assets
    }
    return [pscustomobject]$result
}

function Get-CaseKitBindingSeed {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Composition,
        [Parameter(Mandatory)]$Settlement,
        [Parameter(Mandatory)]$Bindings
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add([string]$Story.id)
    $parts.Add([string]$Composition.id)
    $parts.Add([string]$Settlement.region)
    $parts.Add([string]$Settlement.settlement)
    foreach ($slot in $Bindings.Keys) {
        $binding = $Bindings[$slot]
        $identity = if ($null -eq $binding) {
            '<none>'
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$binding.entityGuid)) {
            [string]$binding.entityGuid
        }
        else {
            [string]$binding.entityName
        }
        $parts.Add("$slot=$identity")
    }
    return $parts -join '|'
}

function New-CaseKitCompatibilityVariant {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Composition,
        [Parameter(Mandatory)]$Settlement,
        [Parameter(Mandatory)]$Bindings,
        [Parameter(Mandatory)][AllowEmptyCollection()]
        [object[]]$EvidencePlacements,
        [Parameter(Mandatory)][int]$Rank
    )

    $seed = Get-CaseKitBindingSeed -Story $Story `
        -Composition $Composition -Settlement $Settlement -Bindings $Bindings
    $hash = Get-CaseKitStableBindingHash -Seed $seed
    $variantId = '{0}--{1}--{2}--{3}' -f `
        [string]$Story.id,
        [string]$Settlement.region,
        [string]$Settlement.settlement,
        $hash.Substring(0, 16)
    return [pscustomobject][ordered]@{
        schemaVersion = 2
        variantId = $variantId
        storyId = [string]$Story.id
        compositionId = [string]$Composition.id
        archetypeIds = @($Composition.archetypeIds | ForEach-Object {
            [string]$_
        })
        region = [string]$Settlement.region
        settlement = [string]$Settlement.settlement
        rank = $Rank
        bindingSeed = $seed
        bindings = [pscustomobject]$Bindings
        evidencePlacements = @($EvidencePlacements)
        renderedAssets = Expand-CaseKitVariantAssets `
            -Story $Story -Bindings $Bindings
    }
}

function Add-CaseKitBindingVariants {
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)]$Composition,
        [Parameter(Mandatory)]$Settlement,
        [Parameter(Mandatory)]$Slots,
        [Parameter(Mandatory)]$CandidateMap,
        [Parameter(Mandatory)][int]$Maximum,
        [Parameter(Mandatory)]$Output
    )

    $authoredSlotNames = @($Slots.Keys)
    $slotNames = @(
        @($authoredSlotNames | Where-Object {
            -not (Test-CaseKitVictimSlot -Slot $Slots[$_])
        })
        @($authoredSlotNames | Where-Object {
            Test-CaseKitVictimSlot -Slot $Slots[$_]
        })
    )
    $bindings = [ordered]@{}
    $usedGuids = [System.Collections.Generic.HashSet[string]]::new()
    function Add-BindingAt {
        param([int]$Index)

        if ($Output.Count -ge $Maximum) {
            return
        }
        if ($Index -ge $slotNames.Count) {
            $placementResolution = Resolve-CaseKitEvidencePlacements `
                -Story $Story -Bindings $bindings
            if (-not [bool]$placementResolution.valid) {
                return
            }
            $placements = @($placementResolution.placements)
            $Output.Add((New-CaseKitCompatibilityVariant `
                -Story $Story -Composition $Composition `
                -Settlement $Settlement -Bindings $bindings `
                -EvidencePlacements $placements `
                -Rank ($Output.Count + 1)))
            return
        }
        $slotName = [string]$slotNames[$Index]
        foreach ($candidate in @($CandidateMap[$slotName])) {
            if ($null -eq $candidate) {
                $bindings[$slotName] = $null
                Add-BindingAt -Index ($Index + 1)
                $bindings.Remove($slotName)
                continue
            }
            $guid = [string]$candidate.entityGuid
            if (-not [string]::IsNullOrWhiteSpace($guid) -and
                $usedGuids.Contains($guid)) {
                continue
            }
            $bindings[$slotName] = $candidate
            if (-not [string]::IsNullOrWhiteSpace($guid)) {
                $null = $usedGuids.Add($guid)
            }
            Add-BindingAt -Index ($Index + 1)
            if (-not [string]::IsNullOrWhiteSpace($guid)) {
                $null = $usedGuids.Remove($guid)
            }
            $bindings.Remove($slotName)
            if ($Output.Count -ge $Maximum) {
                return
            }
        }
    }
    Add-BindingAt -Index 0
}

function Resolve-CaseKitCompatibility {
    param(
        [Parameter(Mandatory)]$Deck,
        [Parameter(Mandatory)]$WorldIndex,
        [ValidateRange(1, 1024)][int]$MaxVariantsPerCombination = 8,
        $DeckCoverage
    )

    if ([int]$Deck.schemaVersion -ne 2) {
        throw "Compatibility solver requires normalized CaseKit schema 2."
    }
    if ([int]$WorldIndex.schemaVersion -ne 1) {
        throw "Compatibility solver requires world index schema 1."
    }

    $accepted = [System.Collections.Generic.List[object]]::new()
    $rejected = [System.Collections.Generic.List[object]]::new()
    foreach ($story in @($Deck.stories | Sort-Object id)) {
        if ([int]$story.sourceSchemaVersion -ne 2) {
            continue
        }
        if ([string]$story.status -eq 'draft') {
            continue
        }
        $storyAcceptedBefore = $accepted.Count
        foreach ($composition in @($story.archetypeCompositions | Sort-Object id)) {
            $slots = Merge-CaseKitCompatibilitySlots -Deck $Deck `
                -Composition $composition -StoryId ([string]$story.id)
            foreach ($settlement in @($WorldIndex.settlements | Sort-Object `
                region, settlement)) {
                $entities = @($WorldIndex.entities | Where-Object {
                    [string]$_.region -eq [string]$settlement.region -and
                    [string]$_.settlement -eq [string]$settlement.settlement
                })
                $candidateMap = [ordered]@{}
                $reasons = [System.Collections.Generic.List[string]]::new()
                foreach ($slotName in $slots.Keys) {
                    $slot = $slots[$slotName]
                    $candidates = @(Get-CaseKitSlotCandidates -Slot $slot `
                        -SlotName ([string]$slotName) `
                        -Settlement $settlement -Entities $entities)
                    if ($candidates.Count -eq 0 -and [bool]$slot.required) {
                        $reasons.Add((Get-CaseKitMissingSlotReason `
                            -Slot $slot -SlotName ([string]$slotName) `
                            -Entities $entities))
                    }
                    if (-not [bool]$slot.required) {
                        $candidates = @($candidates) + @($null)
                    }
                    $candidateMap[[string]$slotName] = $candidates
                }

                $combination = "$($composition.id)/$($story.id)/" +
                    "$($settlement.region)/$($settlement.settlement)"
                if ($reasons.Count -gt 0) {
                    $rejected.Add([pscustomobject][ordered]@{
                        combination = $combination
                        storyId = [string]$story.id
                        compositionId = [string]$composition.id
                        region = [string]$settlement.region
                        settlement = [string]$settlement.settlement
                        reasons = @($reasons | Sort-Object -Unique)
                    })
                    continue
                }

                $variants = [System.Collections.Generic.List[object]]::new()
                try {
                    Add-CaseKitBindingVariants -Story $story `
                        -Composition $composition -Settlement $settlement `
                        -Slots $slots -CandidateMap $candidateMap `
                        -Maximum $MaxVariantsPerCombination -Output $variants
                }
                catch {
                    $reasons.Add("binding render failed: $($_.Exception.Message)")
                }
                if ($variants.Count -eq 0) {
                    if ($reasons.Count -eq 0) {
                        $reasons.Add('no conflict-free binding exists')
                    }
                    $rejected.Add([pscustomobject][ordered]@{
                        combination = $combination
                        storyId = [string]$story.id
                        compositionId = [string]$composition.id
                        region = [string]$settlement.region
                        settlement = [string]$settlement.settlement
                        reasons = @($reasons | Sort-Object -Unique)
                    })
                    continue
                }
                foreach ($variant in $variants) {
                    $accepted.Add($variant)
                }
            }
        }

        $storyVariants = @($accepted.ToArray() | Where-Object {
            [string]$_.storyId -eq [string]$story.id
        })
        if ($accepted.Count -eq $storyAcceptedBefore -or
            $storyVariants.Count -eq 0) {
            throw "active StoryPack '$($story.id)' has no playable variant."
        }
        $coverage = Get-CaseKitCompatibilityProperty `
            -Value $story -Name 'coverage'
        if ($null -ne $coverage) {
            $minimum = [int](Get-CaseKitCompatibilityProperty `
                -Value $coverage -Name 'minimumPerRegion' -DefaultValue 1)
            foreach ($region in @($coverage.requiredRegions)) {
                $count = @($storyVariants | Where-Object {
                    [string]$_.region -eq [string]$region
                }).Count
                if ($count -lt $minimum) {
                    throw "StoryPack '$($story.id)' coverage for region " +
                        "'$region' requires $minimum variants; found $count."
                }
            }
        }
    }

    if ($null -ne $DeckCoverage) {
        $minimums = Get-CaseKitCompatibilityProperty `
            -Value $DeckCoverage -Name 'minimumPlayableCasesPerRegion'
        if ($null -ne $minimums) {
            foreach ($minimum in $minimums.PSObject.Properties) {
                $storyCount = @($accepted.ToArray() | Where-Object {
                    [string]$_.region -eq $minimum.Name
                } | ForEach-Object storyId | Sort-Object -Unique).Count
                if ($storyCount -lt [int]$minimum.Value) {
                    throw "deck coverage for region '$($minimum.Name)' " +
                        "requires $($minimum.Value) playable cases; found " +
                        "$storyCount."
                }
            }
        }
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        sourceFormat = 'casekit-compatibility-v1'
        maxVariantsPerCombination = $MaxVariantsPerCombination
        accepted = @($accepted.ToArray() | Sort-Object `
            storyId, compositionId, region, settlement, rank, variantId)
        rejected = @($rejected.ToArray() | Sort-Object `
            storyId, compositionId, region, settlement)
    }
}

Export-ModuleMember -Function 'Resolve-CaseKitCompatibility'
