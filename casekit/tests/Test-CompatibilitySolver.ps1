$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $caseKitRoot 'CaseKit.psd1'
$solverPath = Join-Path $caseKitRoot 'core\CaseKit.Compatibility.psm1'
$authoringRoot = Join-Path $PSScriptRoot 'fixtures\authoring\v2'
$worldPath = Join-Path $PSScriptRoot `
    'fixtures\compatibility\world-index.json'

Import-Module $manifestPath -Force

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([bool]$Condition, [string]$Label)

    $script:checks++
    if ($Condition) {
        Write-Host "PASS: $Label"
        return
    }
    $script:failures.Add($Label)
    Write-Host "FAIL: $Label"
}

function Copy-TestValue($Value) {
    return $Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
}

function Select-TestWorld {
    param(
        [Parameter(Mandatory)]$World,
        [Parameter(Mandatory)][string[]]$SettlementIds
    )

    $copy = Copy-TestValue $World
    $copy.settlements = @($copy.settlements | Where-Object {
        $SettlementIds -contains [string]$_.settlement
    })
    $copy.entities = @($copy.entities | Where-Object {
        $SettlementIds -contains [string]$_.settlement
    })
    return $copy
}

if (-not (Test-Path -LiteralPath $solverPath -PathType Leaf)) {
    Add-Result $false 'compatibility solver module exists'
}
else {
    Import-Module $solverPath -Force
    Add-Result $true 'compatibility solver module exists'

    $deck = Read-CaseKitAuthoringDeck `
        -ArchetypeRoot (Join-Path $authoringRoot 'archetypes') `
        -StoryRoot (Join-Path $authoringRoot 'stories') `
        -EvidenceModuleRoot (Join-Path $authoringRoot 'evidence-modules')
    $world = Get-Content -Raw -LiteralPath $worldPath |
        ConvertFrom-Json -Depth 100

    try {
        $report = Resolve-CaseKitCompatibility -Deck $deck `
            -WorldIndex $world -MaxVariantsPerCombination 2
        Add-Result (@($report.accepted).Count -eq 2) `
            'solver applies the per-combination variant cap'
        $testvillePools = @($report.eligibleActorPools | Where-Object {
            [string]$_.storyId -eq 'composed-case-probe' -and
            [string]$_.region -eq 'trosecko' -and
            [string]$_.settlement -eq 'testville'
        })
        $rumorSourcePool = @($testvillePools | Where-Object {
            [string]$_.slotName -eq 'rumorSource'
        })[0]
        $witnessPool = @($testvillePools | Where-Object {
            [string]$_.slotName -eq 'witness'
        })[0]
        Add-Result (
            @($rumorSourcePool.candidates).Count -eq 2 -and
            @($witnessPool.candidates).Count -eq 4 -and
            @($rumorSourcePool.candidates | ForEach-Object {
                [string]$_.entityName
            } | Sort-Object) -join ',' -eq
                'conflicting_innkeeper_target,safe_innkeeper'
        ) 'eligible actor pools survive a smaller concrete variant cap'
        Add-Result (
            @($report.rejected | Where-Object {
                $_.settlement -eq 'bareford' -and
                @($_.reasons) -contains (
                    "required capability role.innkeeper not found for " +
                    "slot rumorSource"
                )
            }).Count -eq 1
        ) 'incompatible settlement is reported without failing the build'
        Add-Result (
            @($report.accepted[0].archetypeIds).Count -eq 2
        ) 'accepted variant preserves composed InvestigationArchetypes'
        Add-Result (
            $report.accepted[0].bindings.target.entityName -eq
                'preferred_farmhand'
        ) 'authored preference ranks before identity quality and GUID'
        Add-Result (
            @(
                $report.accepted.bindings.target.entityName |
                    Sort-Object -Unique
            ).Count -eq 2
        ) 'variant cap prioritizes distinct eligible targets'
        Add-Result (
            @($report.accepted | Where-Object {
                $_.bindings.target.entityGuid -eq
                    $_.bindings.rumorSource.entityGuid
            }).Count -eq 0
        ) 'one actor cannot fill conflicting source and target slots'
        Add-Result (
            @($report.accepted | Where-Object {
                $_.bindings.target.entityName -in @(
                    'story_critical_target', 'dead_target'
                )
            }).Count -eq 0
        ) 'story-critical and dead actors are excluded as targets'
        Add-Result (
            @($report.accepted.variantId | Sort-Object -Unique).Count -eq 2
        ) 'accepted variants receive stable unique IDs'
        Add-Result (
            -not (Get-Command Resolve-CaseKitCompatibility).
                Parameters.ContainsKey('StoryRegionMap')
        ) 'native adapter cannot impose a hidden StoryPack region policy'
        Add-Result (
            @($report.accepted | Where-Object {
                ($_.renderedAssets.ru.Values -join '') -match '\{\{' -or
                ($_.renderedAssets.en.Values -join '') -match '\{\{'
            }).Count -eq 0
        ) 'both languages render against concrete semantic bindings'

        $repeat = Resolve-CaseKitCompatibility -Deck $deck `
            -WorldIndex $world -MaxVariantsPerCombination 2
        Add-Result (
            ($report | ConvertTo-Json -Depth 100 -Compress) -ceq
            ($repeat | ConvertTo-Json -Depth 100 -Compress)
        ) 'compatibility report is byte-deterministic in memory'

        $wide = Resolve-CaseKitCompatibility -Deck $deck `
            -WorldIndex $world -MaxVariantsPerCombination 32
        $targetNames = @($wide.accepted.bindings.target.entityName |
            Sort-Object -Unique)
        Add-Result (
            'preferred_farmhand' -in $targetNames -and
            'anonymous_farmhand' -in $targetNames
        ) 'settlement can materialize multiple eligible anonymous farmhands'
        Add-Result (
            @($wide.accepted | Where-Object {
                $_.bindings.target.entityGuid -eq
                    $_.bindings.rumorSource.entityGuid -or
                $_.bindings.target.entityGuid -eq
                    $_.bindings.witness.entityGuid -or
                $_.bindings.rumorSource.entityGuid -eq
                    $_.bindings.witness.entityGuid
            }).Count -eq 0
        ) 'conflict prevention holds across the wider binding matrix'

        $optionalAnchorDeck = Copy-TestValue $deck
        $optionalAnchorDeck.archetypes[0].slots | Add-Member `
            -NotePropertyName optionalAreaAnchor `
            -NotePropertyValue ([pscustomobject]@{
                entityType = 'actor'
                required = $false
                capabilities = @('role.optional_area_anchor')
                identityModes = @('named', 'titled', 'anonymous')
                templateFields = @('displayLabel', 'directionLabel', 'name')
            }) -Force
        $localAreaGuidance = @(
            $optionalAnchorDeck.stories[0].threads.steps |
                ForEach-Object { @($_) } |
                ForEach-Object { @($_.guidance) } |
                Where-Object { $_.id -eq 'settlement-search' }
        )[0]
        $localAreaGuidance.target | Add-Member `
            -NotePropertyName areaSelection `
            -NotePropertyValue 'smallest-common' -Force
        $localAreaGuidance.target | Add-Member `
            -NotePropertyName anchorSlots `
            -NotePropertyValue @('rumorSource', 'optionalAreaAnchor') -Force
        $optionalAnchorWorld = Copy-TestValue $world
        $optionalAnchorReport = Resolve-CaseKitCompatibility `
            -Deck $optionalAnchorDeck -WorldIndex $optionalAnchorWorld `
            -MaxVariantsPerCombination 32
        $fallbackGuidance = @(
            $optionalAnchorReport.accepted[0].guidanceBindings |
                Where-Object {
                    $_.qualifiedId -eq
                        'paper-trail/ask-innkeeper/settlement-search'
                }
        )[0]
        Add-Result (
            @($optionalAnchorReport.accepted).Count -gt 0 -and
            $null -ne $fallbackGuidance -and
            $null -eq $fallbackGuidance.binding -and
            @($fallbackGuidance.anchorBindings).Count -eq 1
        ) 'journal fallback keeps a variant when an optional area anchor is absent'

        $rejectAnchorDeck = Copy-TestValue $optionalAnchorDeck
        $rejectGuidance = @(
            $rejectAnchorDeck.stories[0].threads.steps |
                ForEach-Object { @($_) } |
                ForEach-Object { @($_.guidance) } |
                Where-Object { $_.id -eq 'settlement-search' }
        )[0]
        $rejectGuidance.fallback = 'reject-variant'
        try {
            Resolve-CaseKitCompatibility -Deck $rejectAnchorDeck `
                -WorldIndex $optionalAnchorWorld `
                -MaxVariantsPerCombination 32 | Out-Null
            Add-Result $false `
                'reject fallback drops a variant when an optional area anchor is absent'
        }
        catch {
            Add-Result (
                $_.Exception.Message -like
                    "*active StoryPack 'composed-case-probe' has no playable variant*"
            ) 'reject fallback drops a variant when an optional area anchor is absent'
        }

        $personalDeck = Copy-TestValue $deck
        $personalStep = @($personalDeck.stories[0].threads.steps |
            ForEach-Object { @($_) } | Where-Object {
                $_.action.evidenceModule -eq 'document-in-container'
            })[0]
        $personalStep.action.placement = [pscustomobject]@{
            mode = 'actor-container'
            actor = 'rumorSource'
        }
        $personalWorld = Copy-TestValue $world
        $personalChest = $personalWorld.entities | Where-Object {
            $_.entityName -eq 'evidence_chest'
        }
        $personalChest | Add-Member -NotePropertyName relations `
            -NotePropertyValue @([pscustomobject]@{
                type = 'personal-container-of'
                targetEntityName = 'safe_innkeeper'
            }) -Force
        $shopChest = Copy-TestValue $personalChest
        $shopChest.entityName = 'shop_evidence_chest'
        $shopChest.entityGuid = '10000000-0000-0000-0000-000000000011'
        $shopChest.capabilities = @(
            @($shopChest.capabilities) + @('container.shop', 'container.trade')
        )
        $shopChest | Add-Member -NotePropertyName authoredPreference `
            -NotePropertyValue 1000 -Force
        $personalWorld.entities = @($personalWorld.entities) + @($shopChest)
        $personalReport = Resolve-CaseKitCompatibility `
            -Deck $personalDeck -WorldIndex $personalWorld `
            -MaxVariantsPerCombination 32
        $personalVariants = @($personalReport.accepted | Where-Object {
            $_.settlement -eq 'testville'
        })
        Add-Result (
            $personalVariants.Count -gt 0 -and
            @($personalVariants | Where-Object {
                $_.bindings.rumorSource.entityName -ne 'safe_innkeeper' -or
                $_.bindings.evidenceContainer.entityName -ne 'evidence_chest'
            }).Count -eq 0
        ) 'actor-container requires an explicit personal-container relation'
        Add-Result (
            @($personalReport.accepted | Where-Object {
                $_.bindings.evidenceContainer.entityName -eq
                    'shop_evidence_chest'
            }).Count -eq 0
        ) 'trade storage is rejected even when marked as personal'
        $resolvedPlacement = if (
            $personalVariants.Count -gt 0 -and
            $null -ne $personalVariants[0].PSObject.Properties[
                'evidencePlacements'
            ] -and
            @($personalVariants[0].evidencePlacements).Count -gt 0
        ) { $personalVariants[0].evidencePlacements[0] } else { $null }
        Add-Result (
            $null -ne $resolvedPlacement -and
            $resolvedPlacement.mode -eq
                'actor-container' -and
            $resolvedPlacement.actorSlot -eq
                'rumorSource' -and
            $resolvedPlacement.containerSlot -eq
                'evidenceContainer'
        ) 'accepted variant preserves its resolved placement contract'

        $homeDeck = Copy-TestValue $personalDeck
        $homeStep = @($homeDeck.stories[0].threads.steps |
            ForEach-Object { @($_) } | Where-Object {
                $_.action.evidenceModule -eq 'document-in-container'
            })[0]
        $homeStep.action.placement.mode = 'actor-home-container'
        $homeWorld = Copy-TestValue $world
        $homeChest = $homeWorld.entities | Where-Object {
            $_.entityName -eq 'evidence_chest'
        }
        $homeChest | Add-Member -NotePropertyName relations `
            -NotePropertyValue @([pscustomobject]@{
                type = 'home-container-of'
                targetEntityName = 'safe_innkeeper'
            }) -Force
        $homeReport = Resolve-CaseKitCompatibility `
            -Deck $homeDeck -WorldIndex $homeWorld `
            -MaxVariantsPerCombination 32
        Add-Result (
            @($homeReport.accepted | Where-Object {
                $_.settlement -eq 'testville' -and
                $_.bindings.rumorSource.entityName -eq 'safe_innkeeper'
            }).Count -gt 0
        ) 'actor-home-container requires an explicit home-container relation'
    }
    catch {
        foreach ($label in @(
            'solver applies the per-combination variant cap',
            'eligible actor pools survive a smaller concrete variant cap',
            'incompatible settlement is reported without failing the build',
            'accepted variant preserves composed InvestigationArchetypes',
            'authored preference ranks before identity quality and GUID',
            'variant cap prioritizes distinct eligible targets',
            'one actor cannot fill conflicting source and target slots',
            'story-critical and dead actors are excluded as targets',
            'accepted variants receive stable unique IDs',
            'both languages render against concrete semantic bindings',
            'compatibility report is byte-deterministic in memory',
            'settlement can materialize multiple eligible anonymous farmhands',
            'conflict prevention holds across the wider binding matrix',
            'actor-container requires an explicit personal-container relation',
            'trade storage is rejected even when marked as personal',
            'accepted variant preserves its resolved placement contract',
            'actor-home-container requires an explicit home-container relation'
        )) {
            Add-Result $false "$label ($($_.Exception.Message))"
        }
    }

    $bareWorld = Select-TestWorld -World $world `
        -SettlementIds @('bareford')
    try {
        Resolve-CaseKitCompatibility -Deck $deck `
            -WorldIndex $bareWorld -MaxVariantsPerCombination 2 | Out-Null
        Add-Result $false 'active StoryPack with zero variants fails the build'
    }
    catch {
        Add-Result (
            $_.Exception.Message -like
                "*active StoryPack 'composed-case-probe' has no playable variant*"
        ) 'active StoryPack with zero variants fails the build'
    }

    $draftDeck = Copy-TestValue $deck
    $draftDeck.stories[0].status = 'draft'
    try {
        $draftReport = Resolve-CaseKitCompatibility -Deck $draftDeck `
            -WorldIndex $bareWorld -MaxVariantsPerCombination 2
        Add-Result (@($draftReport.accepted).Count -eq 0) `
            'draft StoryPack may have zero variants and is not packaged'
    }
    catch {
        Add-Result $false (
            'draft StoryPack may have zero variants and is not packaged ' +
            "($($_.Exception.Message))"
        )
    }

    $coverageDeck = Copy-TestValue $deck
    $coverageDeck.stories[0] | Add-Member -NotePropertyName coverage `
        -NotePropertyValue ([pscustomobject]@{
            requiredRegions = @('trosecko', 'kutnohorsko')
            minimumPerRegion = 1
        }) -Force
    try {
        Resolve-CaseKitCompatibility -Deck $coverageDeck `
            -WorldIndex $world -MaxVariantsPerCombination 2 | Out-Null
        Add-Result $false 'StoryPack explicit regional coverage is enforced'
    }
    catch {
        Add-Result (
            $_.Exception.Message -like
                "*composed-case-probe*coverage for region 'kutnohorsko'*"
        ) 'StoryPack explicit regional coverage is enforced'
    }

    try {
        Resolve-CaseKitCompatibility -Deck $deck -WorldIndex $world `
            -MaxVariantsPerCombination 2 `
            -DeckCoverage ([pscustomobject]@{
                minimumPlayableCasesPerRegion = [pscustomobject]@{
                    trosecko = 1
                    kutnohorsko = 1
                }
            }) | Out-Null
        Add-Result $false 'deck-level regional case minimum is enforced'
    }
    catch {
        Add-Result (
            $_.Exception.Message -like
                "*deck coverage for region 'kutnohorsko'*"
        ) 'deck-level regional case minimum is enforced'
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
