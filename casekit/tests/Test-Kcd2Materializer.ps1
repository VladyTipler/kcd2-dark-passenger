$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $caseKitRoot 'CaseKit.psd1'
$compatibilityModulePath = Join-Path $caseKitRoot `
    'core\CaseKit.Compatibility.psm1'
$materializerModulePath = Join-Path $caseKitRoot `
    'adapters\kcd2\CaseKit.Kcd2Materializer.psm1'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\authoring\v2'
$worldPath = Join-Path $PSScriptRoot `
    'fixtures\compatibility\world-index.json'
$stableIdPath = Join-Path $PSScriptRoot `
    'fixtures\materializer\stable-ids.json'

Import-Module $manifestPath -Force
Import-Module $compatibilityModulePath -Force
Import-Module $materializerModulePath -Force

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

function Add-ThrowsLike {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Label
    )

    try {
        & $Action
        Add-Result $false $Label
    }
    catch {
        Add-Result ($_.Exception.Message -like $Pattern) $Label
    }
}

function Copy-JsonValue {
    param([Parameter(Mandatory)]$Value)

    return ($Value | ConvertTo-Json -Depth 100) |
        ConvertFrom-Json -Depth 100
}

$deck = Read-CaseKitAuthoringDeck `
    -ArchetypeRoot (Join-Path $fixtureRoot 'archetypes') `
    -StoryRoot (Join-Path $fixtureRoot 'stories') `
    -EvidenceModuleRoot (Join-Path $fixtureRoot 'evidence-modules')
$world = [System.IO.File]::ReadAllText($worldPath) |
    ConvertFrom-Json -Depth 100
$report = Resolve-CaseKitCompatibility -Deck $deck -WorldIndex $world `
    -MaxVariantsPerCombination 2
$stableIds = [System.IO.File]::ReadAllText($stableIdPath) |
    ConvertFrom-Json -Depth 100

$compiled = ConvertTo-CaseKitCompiledDefinitions -Deck $deck `
    -CompatibilityReport $report -StableIdRegistry $stableIds

Add-Result (
    $compiled.sourceFormat -eq 'casekit-compiled-definitions-v1'
) 'materializer emits the compiled-definition boundary'
Add-Result (
    @($compiled.stories).Count -eq 1 -and
    @($compiled.variants).Count -eq 2
) 'shared story data is emitted once for two concrete variants'
Add-Result (
    @($compiled.eligibleActorPools).Count -gt 0 -and
    @($compiled.eligibleActorPools | Where-Object {
        [string]$_.storyId -eq 'composed-case-probe' -and
        [string]$_.settlement -eq 'testville' -and
        [string]$_.slotName -eq 'rumorSource' -and
        @($_.candidates).Count -eq 2
    }).Count -eq 1
) 'materializer preserves the full eligible actor pool outside variants'

$story = $compiled.stories[0]
Add-Result (
    $story.caseId -eq 'composed_case_probe' -and
    [int]$story.caseCode -eq 9001 -and
    [double]$story.weight -eq 1
) 'stable case identity comes from the separate registry'
Add-Result (
    (@($story.evidence | ForEach-Object { [int]$_.code }) -join ',') -eq
        '9101,9102,9103,9104'
) 'stable evidence codes follow deterministic thread order'
Add-Result (
    (@($story.evidence.legacyId) -join ',') -eq
        'probe_innkeeper,probe_letter,probe_witness,probe_area_listening'
) 'stable runtime evidence IDs come from the separate registry'
$physicalEvidence = @($story.evidence | Where-Object {
    $_.qualifiedId -eq 'paper-trail/read-letter'
})[0]
Add-Result (
    $physicalEvidence.item.classification -eq 'quest' -and
    $physicalEvidence.item.retention -eq 'case'
) 'materializer preserves physical-item classification and retention'
Add-Result (
    $physicalEvidence.placement.mode -eq 'world-container'
) 'materializer preserves authored evidence placement policy'
Add-Result (
    (@($story.evidence | ForEach-Object { [int]$_.confidence }) -join ',') -eq
        '20,30,25,10'
) 'evidence confidence is materialized from composed archetypes'
Add-Result (
    @($story.timedAreaActions).Count -eq 1 -and
    $story.timedAreaActions[0].qualifiedId -eq
        'courtyard-gossip/listen-for-rumors' -and
    $story.timedAreaActions[0].activation.mode -eq 'timed-area-action'
) 'materializer emits one finite timed area action'
Add-Result (
    @($story.dialogues).Count -eq 3 -and
    @($story.documents).Count -eq 1
) 'dialogue and document definitions remain shared assets'
Add-Result (
    $story.reveal.confidence -eq 70 -and
    @($story.reveal.identityRequirement.allOf) -contains 'target_identified' -and
    $null -eq $story.reveal.PSObject.Properties['requiredFacts']
) 'compiled story preserves the authored reveal contract'
Add-Result (
    $story.journal.objectives.search.nameAsset -eq 'objective.search.name' -and
    $story.journal.objectives.cleanup.states.external -eq
        'objective.cleanup.external'
) 'materializer preserves StoryPack lifecycle objective presentation'

$variant = @($compiled.variants | Where-Object rank -eq 1)[0]
Add-Result (
    $variant.caseCode -eq 9001 -and
    $variant.region -eq 'trosecko' -and
    $variant.settlement -eq 'testville' -and
    $variant.bindings.target.entityName -eq 'preferred_farmhand'
) 'variant carries stable case identity and concrete world bindings'
$resolvedDestination = if (
    $null -ne $variant.PSObject.Properties['evidencePlacements'] -and
    @($variant.evidencePlacements).Count -eq 1
) { $variant.evidencePlacements[0] } else { $null }
Add-Result (
    $null -ne $resolvedDestination -and
    $resolvedDestination.qualifiedId -eq
        'paper-trail/read-letter' -and
    $resolvedDestination.containerEntityName -eq
        'evidence_chest'
) 'variant carries a concrete resolved evidence destination'
Add-Result (
    $variant.renderedAssets.en.'direction.paper' -eq
        'Question the Testville innkeeper or search the records.'
) 'variant carries rendered localized assets'
Add-Result (
    @($variant.guidanceBindings).Count -eq 7 -and
    @($variant.guidanceBindings | Where-Object {
        $_.qualifiedId -eq 'paper-trail/ask-innkeeper/settlement-search' -and
        $_.targetKind -eq 'area' -and $_.binding.kind -eq 'settlement'
    }).Count -eq 1 -and
    @($variant.guidanceBindings | Where-Object {
        $_.qualifiedId -eq 'witness-web/question-witness/find-witness' -and
        $_.binding.entityName -eq $variant.bindings.witness.entityName -and
        $_.binding.soulGuid -eq $variant.bindings.witness.soulGuid
    }).Count -eq 1
) 'variant resolves semantic GuidanceTargets to concrete bindings'
Add-Result (
    @($variant.guidanceBindings | Where-Object {
        $_.qualifiedId -eq 'paper-trail/ask-innkeeper/settlement-search' -and
        $_.objective.nameAsset -eq 'objective.guidance.search.name' -and
        $_.objective.states.active -eq 'objective.guidance.search.active'
    }).Count -eq 1
) 'materializer preserves guidance objective presentation beside its binding'
Add-Result (
    @($variant.timedAreaActions).Count -eq 1 -and
    $variant.timedAreaActions[0].qualifiedId -eq
        'courtyard-gossip/listen-for-rumors'
) 'variant carries the timed area action without speaker bindings'

$sharedJson = $story | ConvertTo-Json -Depth 100 -Compress
Add-Result (
    $sharedJson -notmatch 'entityGuid|soulGuid|cameraGuid|worldPosition'
) 'shared StoryPack materialization contains no native world identifiers'

$compiledAgain = ConvertTo-CaseKitCompiledDefinitions -Deck $deck `
    -CompatibilityReport $report -StableIdRegistry $stableIds
Add-Result (
    ($compiled | ConvertTo-Json -Depth 100 -Compress) -ceq
    ($compiledAgain | ConvertTo-Json -Depth 100 -Compress)
) 'compiled definitions are byte-deterministic in memory'

$missingEvidenceIds = Copy-JsonValue $stableIds
$missingEvidenceIds.stories[0].evidence = @(
    $missingEvidenceIds.stories[0].evidence | Where-Object {
        $_.stepId -ne 'question-witness'
    }
)
Add-ThrowsLike -Pattern (
    "*stable evidence code for 'composed-case-probe/" +
    "witness-web/question-witness'*"
) -Label 'missing stable evidence identity is rejected' -Action {
    ConvertTo-CaseKitCompiledDefinitions -Deck $deck `
        -CompatibilityReport $report `
        -StableIdRegistry $missingEvidenceIds | Out-Null
}

$duplicateIds = Copy-JsonValue $stableIds
$duplicateIds.stories[0].evidence[1].code = 9101
Add-ThrowsLike -Pattern "*stable evidence code '9101' is duplicated*" `
    -Label 'duplicate stable evidence identity is rejected' -Action {
        ConvertTo-CaseKitCompiledDefinitions -Deck $deck `
            -CompatibilityReport $report `
            -StableIdRegistry $duplicateIds | Out-Null
    }

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
