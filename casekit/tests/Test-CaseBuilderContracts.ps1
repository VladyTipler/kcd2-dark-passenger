$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $caseKitRoot 'CaseKit.psd1'
$templateModulePath = Join-Path $caseKitRoot `
    'core\CaseKit.Templates.psm1'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\authoring\valid'
$fixtureV2Root = Join-Path $PSScriptRoot 'fixtures\authoring\v2'

Import-Module $manifestPath -Force
Import-Module $templateModulePath -Force

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
        $matches = $_.Exception.Message -like $Pattern
        if (-not $matches) {
            Write-Host "EXPECTED: $Pattern"
            Write-Host "ACTUAL: $($_.Exception.Message)"
        }
        Add-Result $matches $Label
    }
}

function Read-TestJson {
    param([Parameter(Mandatory)][string]$LiteralPath)

    return [System.IO.File]::ReadAllText($LiteralPath) |
        ConvertFrom-Json -AsHashtable -Depth 100
}

function Write-TestJson {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText(
        $LiteralPath,
        $json,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function New-TestDeckCopy {
    param([Parameter(Mandatory)][string]$Name)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) `
        "dark-passenger-casekit-$Name-$([guid]::NewGuid())"
    $archetypeRoot = Join-Path $root 'archetypes'
    $storyRoot = Join-Path $root 'stories'
    $evidenceRoot = Join-Path $root 'evidence-modules'
    [System.IO.Directory]::CreateDirectory($archetypeRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($storyRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null
    Copy-Item -LiteralPath (Join-Path $fixtureRoot `
        'archetypes\paper-trail-witness.archetype.json') `
        -Destination $archetypeRoot
    Copy-Item -LiteralPath (Join-Path $fixtureRoot `
        'stories\missing-traveler.story.json') `
        -Destination $storyRoot
    Copy-Item -LiteralPath (Join-Path $fixtureRoot `
        'evidence-modules\core.evidence.json') `
        -Destination $evidenceRoot

    return [pscustomobject]@{
        root = $root
        archetypeRoot = $archetypeRoot
        storyRoot = $storyRoot
        evidenceRoot = $evidenceRoot
        archetypePath = Join-Path $archetypeRoot `
            'paper-trail-witness.archetype.json'
        storyPath = Join-Path $storyRoot 'missing-traveler.story.json'
    }
}

function Read-TestDeck {
    param([Parameter(Mandatory)]$Paths)

    return Read-CaseKitAuthoringDeck `
        -ArchetypeRoot $Paths.archetypeRoot `
        -StoryRoot $Paths.storyRoot `
        -EvidenceModuleRoot $Paths.evidenceRoot
}

function New-ProductionDeckCopy {
    param([Parameter(Mandatory)][string]$Name)

    $repoRoot = Split-Path -Parent $caseKitRoot
    $root = Join-Path ([System.IO.Path]::GetTempPath()) `
        "dark-passenger-production-deck-$Name-$([guid]::NewGuid())"
    foreach ($folder in @('archetypes', 'stories', 'evidence-modules')) {
        $destination = Join-Path $root $folder
        [System.IO.Directory]::CreateDirectory($destination) | Out-Null
        Copy-Item -Path (Join-Path $repoRoot "content\$folder\*") `
            -Destination $destination -Recurse
    }
    return [pscustomobject]@{
        root = $root
        archetypeRoot = Join-Path $root 'archetypes'
        storyRoot = Join-Path $root 'stories'
        evidenceRoot = Join-Path $root 'evidence-modules'
        missingTravelerThreadsPath = Join-Path $root `
            'stories\missing-traveler\threads.json'
    }
}

function New-TestDeckV2Copy {
    param([Parameter(Mandatory)][string]$Name)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) `
        "dark-passenger-casekit-v2-$Name-$([guid]::NewGuid())"
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    Copy-Item -Path (Join-Path $fixtureV2Root '*') `
        -Destination $root -Recurse
    $storyPackageRoot = Join-Path $root `
        'stories\composed-case-probe'
    return [pscustomobject]@{
        root = $root
        archetypeRoot = Join-Path $root 'archetypes'
        storyRoot = Join-Path $root 'stories'
        evidenceRoot = Join-Path $root 'evidence-modules'
        storyPackageRoot = $storyPackageRoot
        casePath = Join-Path $storyPackageRoot 'case.json'
        threadsPath = Join-Path $storyPackageRoot 'threads.json'
        ruPath = Join-Path $storyPackageRoot 'localization\ru.json'
        enPath = Join-Path $storyPackageRoot 'localization\en.json'
        confessionPath = Join-Path $storyPackageRoot `
            'dialogues\confession.json'
    }
}

$validPaths = New-TestDeckCopy -Name 'valid'
try {
    $deck = Read-TestDeck -Paths $validPaths
    Add-Result ([int]$deck.schemaVersion -eq 2) `
        'schema v1 input normalizes to authored deck schema version 2'
    Add-Result ($deck.sourceFormat -eq 'casekit-authoring-v2') `
        'schema v1 input emits the normalized v2 source format'
    Add-Result (
        @($deck.sourceSchemaVersions) -contains 1
    ) 'normalized deck records schema v1 migration input'
    Add-Result (@($deck.archetypes).Count -eq 1) `
        'authored deck loads one archetype'
    Add-Result (@($deck.stories).Count -eq 1) `
        'authored deck loads one coherent StoryPack'
    Add-Result (@($deck.evidenceModules).Count -eq 4) `
        'authored deck loads reusable evidence modules'
    Add-Result (@($deck.stories[0].threads).Count -eq 3) `
        'StoryPack contains several investigation threads'
    Add-Result (
        @($deck.stories[0].threads[0].steps[0].presentations).Count -eq 2
    ) 'out-of-order clue discovery has conditional presentation'
    Add-Result ([int]$deck.validation.maximumReachableConfidence -eq 85) `
        'authoring validation computes reachable confidence'
}
finally {
    Remove-Item -LiteralPath $validPaths.root -Recurse -Force
}

$validV2Paths = New-TestDeckV2Copy -Name 'valid'
try {
    try {
        $deckV2 = Read-TestDeck -Paths $validV2Paths
        $storyV2 = @($deckV2.stories | Where-Object {
            $_.id -eq 'composed-case-probe'
        })[0]
        Add-Result ([int]$deckV2.schemaVersion -eq 2) `
            'v2 package emits authored deck schema version 2'
        Add-Result ($deckV2.sourceFormat -eq 'casekit-authoring-v2') `
            'v2 package records normalized source format'
        Add-Result (
            @($deckV2.sourceSchemaVersions) -contains 2
        ) 'normalized deck records schema v2 input'
        Add-Result (
            @($storyV2.archetypeCompositions[0].archetypeIds).Count -eq 2
        ) 'StoryPack composes several InvestigationArchetypes'
        Add-Result (@($storyV2.threads).Count -eq 3) `
            'v2 StoryPack loads threads.json'
        Add-Result (@($storyV2.dialogues).Count -eq 3) `
            'v2 StoryPack loads dialogue scene definitions'
        Add-Result (@($storyV2.documents).Count -eq 1) `
            'v2 StoryPack loads document definitions'
        $documentStep = @($storyV2.threads.steps | ForEach-Object {
            @($_)
        } | Where-Object {
            $_.action.evidenceModule -eq 'document-in-container'
        })[0]
        Add-Result (
            $documentStep.action.item.classification -eq 'quest' -and
            $documentStep.action.item.retention -eq 'case'
        ) 'v2 StoryPack preserves explicit physical-item semantics'
        Add-Result (
            $documentStep.action.placement.mode -eq 'world-container'
        ) 'v2 StoryPack preserves explicit evidence placement semantics'
        $sourceStep = @($storyV2.threads.steps | ForEach-Object {
            @($_)
        } | Where-Object { $_.id -eq 'ask-innkeeper' })[0]
        $witnessStep = @($storyV2.threads.steps | ForEach-Object {
            @($_)
        } | Where-Object { $_.id -eq 'question-witness' })[0]
        Add-Result (
            @($sourceStep.guidance).Count -eq 2 -and
            $sourceStep.guidance[0].target.kind -eq 'area' -and
            $sourceStep.guidance[0].visibility.mode -eq 'step-active' -and
            $sourceStep.guidance[0].lifetime -eq 'step' -and
            $sourceStep.guidance[0].fallback -eq 'journal-direction'
        ) 'v2 StoryPack normalizes semantic GuidanceTarget defaults'
        Add-Result (
            $storyV2.journal.objectives.investigation.nameAsset -eq
                'objective.investigation.name' -and
            $storyV2.journal.objectives.cleanup.states.witnessed -eq
                'objective.cleanup.witnessed' -and
            $sourceStep.guidance[0].objective.nameAsset -eq
                'objective.guidance.search.name' -and
            $sourceStep.guidance[0].objective.states.active -eq
                'objective.guidance.search.active'
        ) 'v2 StoryPack preserves reusable objective presentation assets'
        Add-Result (
            @($storyV2.storyIdentities).Count -eq 1 -and
            [string]$storyV2.storyIdentities[0].id -eq 'culprit' -and
            [string]$storyV2.storyIdentities[0].bindingSlot -eq 'target' -and
            [string]$storyV2.storyIdentities[0].revealFact -eq
                'target_identified' -and
            [string]$storyV2.storyIdentities[0].localized.ru.name -eq
                'Микулаш' -and
            [string]$storyV2.storyIdentities[0].localized.en.name -eq
                'Mikulas'
        ) 'v2 StoryPack preserves one fixed authored story identity'
        Add-Result (
            $witnessStep.guidance[1].target.slot -eq 'target' -and
            $witnessStep.guidance[1].visibility.mode -eq 'target-revealed' -and
            $witnessStep.guidance[1].lifetime -eq 'case'
        ) 'v2 StoryPack preserves gated target guidance'
        Add-Result (
            @($storyV2.dialogues.scenePreset) -contains `
                'lying-interrogation'
        ) 'v2 StoryPack preserves semantic scene presets'
        $voicedDialogue = @($storyV2.dialogues | Where-Object {
            [string]$_.id -eq 'innkeeper'
        })[0]
        Add-Result (
            [string]$voicedDialogue.media.voice -eq 'native' -and
            [bool]$voicedDialogue.media.lipSync
        ) 'v2 StoryPack preserves native dialogue media intent'
        $validationV2 = @($deckV2.validation.stories | Where-Object {
            $_.storyId -eq 'composed-case-probe'
        })[0]
        Add-Result (
            [int]$validationV2.maximumReachableConfidence -eq 85
        ) 'composed archetypes contribute reachable confidence'
        Add-Result (
            $validationV2.requiredHardFactsSatisfied -eq $true
        ) 'reveal route reaches the required hard identity fact'
        $deckV2Repeat = Read-TestDeck -Paths $validV2Paths
        Add-Result (
            ($deckV2 | ConvertTo-Json -Depth 100 -Compress) -eq
            ($deckV2Repeat | ConvertTo-Json -Depth 100 -Compress)
        ) 'v2 StoryPack normalization is byte-deterministic in memory'
    }
    catch {
        foreach ($label in @(
            'v2 package emits authored deck schema version 2',
            'v2 package records normalized source format',
            'normalized deck records schema v2 input',
            'StoryPack composes several InvestigationArchetypes',
            'v2 StoryPack loads threads.json',
            'v2 StoryPack loads dialogue scene definitions',
            'v2 StoryPack loads document definitions',
            'v2 StoryPack preserves explicit physical-item semantics',
            'v2 StoryPack preserves explicit evidence placement semantics',
            'v2 StoryPack normalizes semantic GuidanceTarget defaults',
            'v2 StoryPack preserves reusable objective presentation assets',
            'v2 StoryPack preserves one fixed authored story identity',
            'v2 StoryPack preserves gated target guidance',
            'v2 StoryPack preserves semantic scene presets',
            'v2 StoryPack preserves native dialogue media intent',
            'composed archetypes contribute reachable confidence',
            'reveal route reaches the required hard identity fact',
            'v2 StoryPack normalization is byte-deterministic in memory'
        )) {
            Add-Result $false "$label ($($_.Exception.Message))"
        }
    }
}
finally {
    Remove-Item -LiteralPath $validV2Paths.root -Recurse -Force
}

$nullObjectivePaths = New-TestDeckV2Copy -Name 'null-objective-override'
try {
    $case = Read-TestJson -LiteralPath $nullObjectivePaths.casePath
    $case.journal.objectives.investigation = $null
    Write-TestJson -LiteralPath $nullObjectivePaths.casePath -Value $case
    $nullObjectiveDeck = Read-TestDeck -Paths $nullObjectivePaths
    $nullObjectiveStory = @($nullObjectiveDeck.stories | Where-Object {
        $_.id -eq 'composed-case-probe'
    })[0]
    Add-Result (
        $null -eq $nullObjectiveStory.journal.objectives.investigation
    ) 'v2 StoryPack accepts a null lifecycle objective as no override'
}
finally {
    Remove-Item -LiteralPath $nullObjectivePaths.root -Recurse -Force
}

$legacyRevealPaths = New-TestDeckV2Copy -Name 'legacy-reveal-normalization'
try {
    $legacyRevealDeck = Read-TestDeck -Paths $legacyRevealPaths
    $legacyRevealStory = @($legacyRevealDeck.stories | Where-Object {
        $_.id -eq 'composed-case-probe'
    })[0]
    Add-Result (
        @($legacyRevealStory.reveal.identityRequirement.allOf).Count -eq 1 -and
        $legacyRevealStory.reveal.identityRequirement.allOf[0] -eq
            'target_identified' -and
        $null -eq $legacyRevealStory.reveal.PSObject.Properties['requiredFacts']
    ) 'legacy requiredFacts normalizes to identityRequirement.allOf'
}
catch {
    Add-Result $false (
        'legacy requiredFacts normalizes to identityRequirement.allOf ' +
        "($($_.Exception.Message))"
    )
}
finally {
    Remove-Item -LiteralPath $legacyRevealPaths.root -Recurse -Force
}

$anyIdentityPaths = New-TestDeckV2Copy -Name 'any-identity'
try {
    $case = Read-TestJson -LiteralPath $anyIdentityPaths.casePath
    $case.facts += @(
        [ordered]@{
            id = 'letter_identifies_target'
            category = 'identity'
            hardIdentity = $true
        },
        [ordered]@{
            id = 'forest_witness_identifies_target'
            category = 'identity'
            hardIdentity = $true
        }
    )
    $case.reveal.Remove('requiredFacts')
    $case.reveal.identityRequirement = [ordered]@{
        anyOf = @(
            'target_identified',
            'letter_identifies_target',
            'forest_witness_identifies_target'
        )
    }
    Write-TestJson -LiteralPath $anyIdentityPaths.casePath -Value $case

    $threads = Read-TestJson -LiteralPath $anyIdentityPaths.threadsPath
    $threads.threads[1].steps[0].result.revealsFacts += @(
        'letter_identifies_target',
        'forest_witness_identifies_target'
    )
    Write-TestJson -LiteralPath $anyIdentityPaths.threadsPath -Value $threads

    $anyIdentityDeck = Read-TestDeck -Paths $anyIdentityPaths
    $anyIdentityStory = @($anyIdentityDeck.stories | Where-Object {
        $_.id -eq 'composed-case-probe'
    })[0]
    $anyIdentityValidation = @($anyIdentityDeck.validation.stories |
        Where-Object { $_.storyId -eq 'composed-case-probe' })[0]
    Add-Result (
        @($anyIdentityStory.reveal.identityRequirement.anyOf).Count -eq 3 -and
        $anyIdentityValidation.identityRequirementMode -eq 'anyOf' -and
        @($anyIdentityValidation.reachableIdentityFacts).Count -eq 3
    ) 'identityRequirement.anyOf preserves all reachable hard identity routes'
}
catch {
    Add-Result $false (
        'identityRequirement.anyOf preserves all reachable hard identity ' +
        "routes ($($_.Exception.Message))"
    )
}
finally {
    Remove-Item -LiteralPath $anyIdentityPaths.root -Recurse -Force
}

$invalidIdentityCases = @(
    [pscustomobject]@{
        name = 'identity-both-formats'
        pattern = "*defines both 'requiredFacts' and 'identityRequirement'*case.json*"
        label = 'v2 loader rejects ambiguous reveal identity formats'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.reveal.identityRequirement = [ordered]@{
                anyOf = @('target_identified')
            }
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'identity-empty-any-of'
        pattern = "*identityRequirement.anyOf must contain at least one fact*case.json*"
        label = 'v2 loader rejects an empty identity alternative set'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.reveal.Remove('requiredFacts')
            $case.reveal.identityRequirement = [ordered]@{ anyOf = @() }
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'identity-non-hard-alternative'
        pattern = "*identity fact 'letter_links_target' is not a hard identity fact*case.json*"
        label = 'v2 loader rejects a non-hard identity alternative'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.reveal.Remove('requiredFacts')
            $case.reveal.identityRequirement = [ordered]@{
                anyOf = @('target_identified', 'letter_links_target')
            }
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'identity-unreachable-alternative'
        pattern = "*cannot reach identity alternative 'unreachable_identity'*case.json*"
        label = 'v2 loader rejects an unreachable identity alternative'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.facts += @([ordered]@{
                id = 'unreachable_identity'
                category = 'identity'
                hardIdentity = $true
            })
            $case.reveal.Remove('requiredFacts')
            $case.reveal.identityRequirement = [ordered]@{
                anyOf = @('target_identified', 'unreachable_identity')
            }
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    }
)

foreach ($invalidIdentityCase in $invalidIdentityCases) {
    $paths = New-TestDeckV2Copy -Name $invalidIdentityCase.name
    try {
        & $invalidIdentityCase.mutate $paths
        Add-ThrowsLike -Pattern $invalidIdentityCase.pattern `
            -Label $invalidIdentityCase.label -Action {
                Read-TestDeck -Paths $paths
            }
    }
    finally {
        Remove-Item -LiteralPath $paths.root -Recurse -Force
    }
}

$invalidV2Cases = @(
    [pscustomobject]@{
        name = 'duplicate-story-identity-id'
        pattern = "*Duplicate story identity 'culprit'*case.json*"
        label = 'v2 loader rejects duplicate story identity ids'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.storyIdentities = @(
                $case.storyIdentities[0],
                $case.storyIdentities[0]
            )
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'duplicate-story-identity-slot'
        pattern = "*Story identities 'culprit' and 'accomplice' both bind slot 'target'*case.json*"
        label = 'v2 loader rejects multiple identities for one binding slot'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $second = $case.storyIdentities[0].Clone()
            $second.id = 'accomplice'
            $case.storyIdentities = @($case.storyIdentities[0], $second)
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'unknown-story-identity-slot'
        pattern = "*Story identity 'culprit' references unknown binding slot 'merchant'*case.json*"
        label = 'v2 loader rejects unknown story identity binding slots'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.storyIdentities[0].bindingSlot = 'merchant'
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'unknown-story-identity-fact'
        pattern = "*Story identity 'culprit' references unknown reveal fact 'missing_identity'*case.json*"
        label = 'v2 loader rejects unknown story identity reveal facts'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.storyIdentities[0].revealFact = 'missing_identity'
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'soft-story-identity-fact'
        pattern = "*Story identity 'culprit' reveal fact 'letter_links_target' is not a hard identity fact*case.json*"
        label = 'v2 loader requires a hard story identity reveal fact'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.storyIdentities[0].revealFact = 'letter_links_target'
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'missing-story-identity-language'
        pattern = "*Story identity 'culprit' is missing 'en' localization*case.json*"
        label = 'v2 loader requires bilingual story identities'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.storyIdentities[0].localized.Remove('en')
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    },
    [pscustomobject]@{
        name = 'guidance-unknown-slot'
        pattern = "*GuidanceTarget 'paper-trail/ask-innkeeper/find-source' references unknown slot 'missingActor'*threads.json*"
        label = 'v2 loader rejects GuidanceTarget with unknown slot'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[0].guidance[1].target.slot = `
                'missingActor'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'guidance-kind-mismatch'
        pattern = "*GuidanceTarget 'paper-trail/ask-innkeeper/find-source' kind 'area' is incompatible with slot 'rumorSource' entity type 'actor'*threads.json*"
        label = 'v2 loader rejects incompatible GuidanceTarget kind'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[0].guidance[1].target.kind = 'area'
            $threads.threads[0].steps[0].guidance[1].precision = 'area'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'guidance-precision-mismatch'
        pattern = "*GuidanceTarget 'paper-trail/read-letter/find-container' precision 'area' is incompatible with kind 'entity'*threads.json*"
        label = 'v2 loader rejects incompatible GuidanceTarget precision'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].guidance[0].precision = 'area'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'guidance-target-leak'
        pattern = "*GuidanceTarget 'witness-web/question-witness/revealed-target' exposes an exact victim before target-revealed visibility*threads.json*"
        label = 'v2 loader rejects exact target marker that leaks identity'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[1].steps[0].guidance[1].visibility.mode = `
                'step-active'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'guidance-facts-empty'
        pattern = "*GuidanceTarget 'paper-trail/ask-innkeeper/find-source' facts-known visibility requires at least one fact*threads.json*"
        label = 'v2 loader rejects empty facts-known GuidanceTarget'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[0].guidance[1].visibility = `
                [ordered]@{ mode = 'facts-known'; requiresFacts = @() }
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'guidance-objective-missing-asset'
        pattern = "*GuidanceTarget 'paper-trail/ask-innkeeper/settlement-search' objective state 'active' references missing asset 'objective.guidance.search.missing'*threads.json*"
        label = 'v2 loader rejects missing guidance objective assets'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[0].guidance[0].objective.states.active =
                'objective.guidance.search.missing'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'guidance-objective-duplicates-investigation-asset'
        pattern = "*GuidanceTarget 'paper-trail/ask-innkeeper/settlement-search' objective duplicates lifecycle investigation objective asset 'objective.investigation.name'*threads.json*"
        label = 'v2 loader rejects guidance objective reusing broad investigation asset'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[0].guidance[0].objective.nameAsset =
                'objective.investigation.name'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'guidance-objective-duplicates-investigation-text'
        pattern = "*GuidanceTarget 'paper-trail/ask-innkeeper/settlement-search' objective duplicates lifecycle investigation objective localized text*threads.json*"
        label = 'v2 loader rejects guidance objective matching broad investigation text'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $russian = Read-TestJson -LiteralPath $paths.ruPath
            $english = Read-TestJson -LiteralPath $paths.enPath
            $investigationAsset =
                $case.journal.objectives.investigation.nameAsset
            $guidanceAsset =
                $threads.threads[0].steps[0].guidance[0].objective.nameAsset
            $russian[$guidanceAsset] = $russian[$investigationAsset]
            $english[$guidanceAsset] = $english[$investigationAsset]
            Write-TestJson -LiteralPath $paths.ruPath -Value $russian
            Write-TestJson -LiteralPath $paths.enPath -Value $english
        }
    },
    [pscustomobject]@{
        name = 'guidance-objective-duplicates-investigation-english-text'
        pattern = "*GuidanceTarget 'paper-trail/ask-innkeeper/settlement-search' objective duplicates lifecycle investigation objective localized text (English)*threads.json*"
        label = 'v2 loader rejects English-only guidance objective text collision'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $english = Read-TestJson -LiteralPath $paths.enPath
            $investigationAsset =
                $case.journal.objectives.investigation.nameAsset
            $guidanceAsset =
                $threads.threads[0].steps[0].guidance[0].objective.nameAsset
            $english[$guidanceAsset] = $english[$investigationAsset]
            Write-TestJson -LiteralPath $paths.enPath -Value $english
        }
    },
    [pscustomobject]@{
        name = 'missing-placement'
        pattern = "*Step 'paper-trail/read-letter' physical item requires explicit placement*threads.json*"
        label = 'v2 loader rejects physical evidence without placement'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].action.Remove('placement')
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'unknown-placement-mode'
        pattern = "*Step 'paper-trail/read-letter' uses unknown placement mode 'shop-container'*threads.json*"
        label = 'v2 loader rejects unknown evidence placement modes'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].action.placement.mode = `
                'shop-container'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'missing-placement-actor'
        pattern = "*Step 'paper-trail/read-letter' placement mode 'actor-container' requires actor slot*threads.json*"
        label = 'v2 loader rejects actor placement without actor slot'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].action.placement.mode = `
                'actor-container'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'unknown-placement-actor'
        pattern = "*Step 'paper-trail/read-letter' placement references unknown actor slot 'merchant'*threads.json*"
        label = 'v2 loader rejects unknown placement actor slot'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].action.placement = [ordered]@{
                mode = 'actor-home-container'
                actor = 'merchant'
            }
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'non-actor-placement-slot'
        pattern = "*Step 'paper-trail/read-letter' placement slot 'evidenceContainer' is not an actor*threads.json*"
        label = 'v2 loader rejects non-actor placement slot'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].action.placement = [ordered]@{
                mode = 'actor-inventory'
                actor = 'evidenceContainer'
            }
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'missing-item-classification'
        pattern = "*Step 'paper-trail/read-letter' physical item requires explicit classification*threads.json*"
        label = 'v2 loader rejects physical evidence without classification'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].action.Remove('item')
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'unknown-item-classification'
        pattern = "*Step 'paper-trail/read-letter' uses unknown item classification 'souvenir'*threads.json*"
        label = 'v2 loader rejects unknown physical-item classification'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].action.item.classification = 'souvenir'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'unknown-item-retention'
        pattern = "*Step 'paper-trail/read-letter' uses unknown item retention 'temporary'*threads.json*"
        label = 'v2 loader rejects unknown physical-item retention'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].action.item.retention = 'temporary'
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'missing-english-localization'
        pattern = "*missing English localization key 'journal.rumor'*en.json*"
        label = 'v2 loader rejects RU/EN localization drift with source path'
        mutate = {
            param($paths)
            $english = Read-TestJson -LiteralPath $paths.enPath
            $english.Remove('journal.rumor')
            Write-TestJson -LiteralPath $paths.enPath -Value $english
        }
    },
    [pscustomobject]@{
        name = 'unknown-scene-preset'
        pattern = "*unknown scene preset 'cinematic-freecam'*confession.json*"
        label = 'v2 loader rejects unknown semantic scene presets'
        mutate = {
            param($paths)
            $dialogue = Read-TestJson -LiteralPath $paths.confessionPath
            $dialogue.scenePreset = 'cinematic-freecam'
            Write-TestJson -LiteralPath $paths.confessionPath -Value $dialogue
        }
    },
    [pscustomobject]@{
        name = 'invalid-dialogue-media'
        pattern = "*Dialogue 'innkeeper' uses unsupported voice mode 'generic'*innkeeper.json*"
        label = 'v2 loader rejects unsupported dialogue voice fallbacks'
        mutate = {
            param($paths)
            $dialoguePath = Join-Path (Split-Path -Parent $paths.confessionPath) `
                'innkeeper.json'
            $dialogue = Read-TestJson -LiteralPath $dialoguePath
            $dialogue.media = [ordered]@{
                voice = 'generic'
                lipSync = $true
            }
            Write-TestJson -LiteralPath $dialoguePath -Value $dialogue
        }
    },
    [pscustomobject]@{
        name = 'native-camera-guid'
        pattern = "*forbidden native field 'cameraGuid'*confession.json*"
        label = 'v2 loader rejects native camera GUIDs in StoryPack content'
        mutate = {
            param($paths)
            $dialogue = Read-TestJson -LiteralPath $paths.confessionPath
            $dialogue.cameraGuid = '00000000-0000-0000-0000-000000000001'
            Write-TestJson -LiteralPath $paths.confessionPath -Value $dialogue
        }
    },
    [pscustomobject]@{
        name = 'disconnected-thread'
        pattern = "*thread 'witness-web' is disconnected*threads.json*"
        label = 'v2 loader rejects a disconnected investigation thread'
        mutate = {
            param($paths)
            $threads = Read-TestJson -LiteralPath $paths.threadsPath
            $threads.threads[0].steps[1].result.unlockThreadIds = @()
            $threads.threads[1].lead.requiresFacts = @()
            $threads.threads[1].steps[0].requiresFacts = @()
            Write-TestJson -LiteralPath $paths.threadsPath -Value $threads
        }
    },
    [pscustomobject]@{
        name = 'non-hard-reveal-fact'
        pattern = "*required reveal fact 'target_identified' is not a hard identity fact*case.json*"
        label = 'v2 loader requires a hard identity reveal fact'
        mutate = {
            param($paths)
            $case = Read-TestJson -LiteralPath $paths.casePath
            $case.facts[2].hardIdentity = $false
            Write-TestJson -LiteralPath $paths.casePath -Value $case
        }
    }
)

foreach ($invalidV2Case in $invalidV2Cases) {
    $paths = New-TestDeckV2Copy -Name $invalidV2Case.name
    try {
        & $invalidV2Case.mutate $paths
        Add-ThrowsLike -Pattern $invalidV2Case.pattern `
            -Label $invalidV2Case.label -Action {
                Read-TestDeck -Paths $paths
            }
    }
    finally {
        Remove-Item -LiteralPath $paths.root -Recurse -Force
    }
}

$rendered = Expand-CaseKitTemplate `
    -Text 'Question {{witness.directionLabel}} in {{settlement.displayName}}.' `
    -Bindings @{
        witness = [pscustomobject]@{
            identityMode = 'anonymous'
            directionLabel = 'the farmhand at the inn'
        }
        settlement = [pscustomobject]@{
            displayName = 'Zhelejov'
        }
    }
Add-Result (
    $rendered -eq 'Question the farmhand at the inn in Zhelejov.'
) 'typed templates render semantic binding fields'

Add-ThrowsLike -Pattern "*Unknown template slot 'stranger'*" `
    -Label 'template rendering rejects an unknown slot' -Action {
        Expand-CaseKitTemplate -Text '{{stranger.displayLabel}}' `
            -Bindings @{}
    }
Add-ThrowsLike -Pattern "*Anonymous binding 'witness' has no name*" `
    -Label 'template rendering rejects anonymous actor name' -Action {
        Expand-CaseKitTemplate -Text '{{witness.name}}' -Bindings @{
            witness = [pscustomobject]@{
                identityMode = 'anonymous'
                name = ''
            }
        }
    }

$invalidCases = @(
    [pscustomobject]@{
        name = 'unknown-slot'
        pattern = "*Unknown template slot 'stranger'*"
        label = 'loader rejects unknown template slots'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.assets.ru['journal.rumor'] = `
                'Ask {{stranger.displayLabel}}.'
            $story.assets.en['journal.rumor'] = `
                'Ask {{stranger.displayLabel}}.'
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    },
    [pscustomobject]@{
        name = 'anonymous-name'
        pattern = "*may resolve to anonymous and cannot use field 'name'*"
        label = 'loader rejects anonymous actor name templates'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.assets.ru['journal.witness'] = 'Question {{witness.name}}.'
            $story.assets.en['journal.witness'] = 'Question {{witness.name}}.'
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    },
    [pscustomobject]@{
        name = 'missing-english'
        pattern = "*missing English asset key 'journal.rumor'*"
        label = 'loader rejects missing English assets'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.assets.en.Remove('journal.rumor')
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    },
    [pscustomobject]@{
        name = 'unknown-module'
        pattern = "*Unknown evidence module 'missing-module'*"
        label = 'loader rejects unknown evidence modules'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.threads[0].steps[0].action.evidenceModule = `
                'missing-module'
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    },
    [pscustomobject]@{
        name = 'unknown-fact'
        pattern = "*references unknown fact 'invented_fact'*"
        label = 'loader rejects unknown result facts'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.threads[0].steps[0].result.revealsFacts[0] = `
                'invented_fact'
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    },
    [pscustomobject]@{
        name = 'dangling-thread'
        pattern = "*unlocks unknown thread 'missing-thread'*"
        label = 'loader rejects dangling next-thread references'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.threads[0].steps[0].result.unlockThreadIds = `
                @('missing-thread')
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    },
    [pscustomobject]@{
        name = 'unreachable-threshold'
        pattern = '*maximum reachable confidence 85 is below reveal threshold 90*'
        label = 'loader rejects unreachable reveal threshold'
        mutate = {
            param($paths)
            $archetype = Read-TestJson -LiteralPath $paths.archetypePath
            $archetype.revealThreshold = 90
            Write-TestJson -LiteralPath $paths.archetypePath -Value $archetype
        }
    },
    [pscustomobject]@{
        name = 'step-kind-mismatch'
        pattern = "*requires step kind 'lead', got 'search'*"
        label = 'loader rejects evidence step kind mismatches'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.threads[0].steps[0].kind = 'search'
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    },
    [pscustomobject]@{
        name = 'unreachable-step'
        pattern = "*contains unreachable step 'read-ledger'*"
        label = 'loader rejects structurally unreachable evidence steps'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.threads[0].entryStepIds = @('ask-innkeeper')
            $story.threads[0].steps[0].result.nextStepIds = @()
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    },
    [pscustomobject]@{
        name = 'missing-out-of-order-presentation'
        pattern = '*multiple entry steps but has no conditional presentation*'
        label = 'loader requires authored out-of-order presentation'
        mutate = {
            param($paths)
            $story = Read-TestJson -LiteralPath $paths.storyPath
            $story.threads[0].steps[0].presentations = @(
                $story.threads[0].steps[0].presentations[0]
            )
            Write-TestJson -LiteralPath $paths.storyPath -Value $story
        }
    }
)

foreach ($invalidCase in $invalidCases) {
    $paths = New-TestDeckCopy -Name $invalidCase.name
    try {
        & $invalidCase.mutate $paths
        Add-ThrowsLike -Pattern $invalidCase.pattern `
            -Label $invalidCase.label -Action {
                Read-TestDeck -Paths $paths
            }
    }
    finally {
        Remove-Item -LiteralPath $paths.root -Recurse -Force
    }
}

$repoRoot = Split-Path -Parent $caseKitRoot
try {
    $productionDeck = Read-CaseKitAuthoringDeck `
        -ArchetypeRoot (Join-Path $repoRoot 'content\archetypes') `
        -StoryRoot (Join-Path $repoRoot 'content\stories') `
        -EvidenceModuleRoot (Join-Path $repoRoot `
            'content\evidence-modules')
    Add-Result (
        @($productionDeck.archetypes | ForEach-Object { $_.id }) `
            -contains 'paper-trail-witness'
    ) 'production deck contains the first CaseArchetype'
    Add-Result (
        @($productionDeck.stories | ForEach-Object { $_.id }) `
            -contains 'missing-traveler'
    ) 'production deck contains the first coherent StoryPack'
    Add-Result (
        [int]$productionDeck.validation.maximumReachableConfidence -ge 70
    ) 'production StoryPack has a reachable reveal route'
    $missingTraveler = @($productionDeck.stories | Where-Object {
        $_.id -eq 'missing-traveler'
    })[0]
    $timedAreaSteps = @($missingTraveler.threads.steps | ForEach-Object {
        @($_)
    } | Where-Object {
        $_.action.evidenceModule -eq 'timed-area-listening'
    })
    Add-Result (
        $timedAreaSteps.Count -eq 1 -and
        $timedAreaSteps[0].action.activation.mode -eq 'timed-area-action' -and
        $timedAreaSteps[0].action.activation.availableFromHour -eq 10 -and
        $timedAreaSteps[0].action.activation.availableUntilHour -eq 22 -and
        $timedAreaSteps[0].action.activation.durationHours -eq 2 -and
        @($timedAreaSteps[0].guidance).Count -eq 1 -and
        $timedAreaSteps[0].guidance[0].target.kind -eq 'area' -and
        $timedAreaSteps[0].guidance[0].target.slot -eq 'settlement' -and
        $timedAreaSteps[0].guidance[0].target.areaSelection -eq
            'smallest-common' -and
        (@($timedAreaSteps[0].guidance[0].target.anchorSlots) -join ',') -eq
            'rumorSource,witness' -and
        $timedAreaSteps[0].guidance[0].visibility.mode -eq 'step-active' -and
        $timedAreaSteps[0].guidance[0].lifetime -eq 'step'
    ) 'production timed action targets one local inn area'
}
catch {
    Add-Result $false (
        "production authoring deck loads: $($_.Exception.Message)"
    )
    Add-Result $false 'production deck contains the first coherent StoryPack'
    Add-Result $false 'production StoryPack has a reachable reveal route'
    Add-Result $false `
        'production timed action targets one local inn area'
}

foreach ($activationCase in @(
    [pscustomobject]@{
        name = 'missing-timed-area-activation'
        pattern = '*requires explicit activation mode*'
        label = 'v2 loader rejects timed area step without activation mode'
        mutate = {
            param($threads)
            $thread = @($threads.threads | Where-Object {
                @($_.steps.action.evidenceModule) -contains `
                    'timed-area-listening'
            })[0]
            $stepIndex = 0
            while ($thread.steps[$stepIndex].action.evidenceModule -ne
                'timed-area-listening') {
                $stepIndex++
            }
            $thread.steps[$stepIndex].action = [ordered]@{
                evidenceModule = 'timed-area-listening'
                bindings = $thread.steps[$stepIndex].action.bindings
            }
        }
    },
    [pscustomobject]@{
        name = 'unknown-timed-area-activation'
        pattern = "*unsupported timed area activation mode 'manual'*"
        label = 'v2 loader rejects unknown timed area activation mode'
        mutate = {
            param($threads)
            $step = @($threads.threads.steps | ForEach-Object { @($_) } |
                Where-Object {
                    $_.action.evidenceModule -eq 'timed-area-listening'
                })[0]
            $step.action.activation = @{
                mode = 'manual'
            }
        }
    }
)) {
    $paths = New-ProductionDeckCopy -Name $activationCase.name
    try {
        $threads = Read-TestJson `
            -LiteralPath $paths.missingTravelerThreadsPath
        & $activationCase.mutate $threads
        Write-TestJson -LiteralPath $paths.missingTravelerThreadsPath `
            -Value $threads
        Add-ThrowsLike -Pattern $activationCase.pattern `
            -Label $activationCase.label -Action {
                Read-TestDeck -Paths $paths
            }
    }
    finally {
        Remove-Item -LiteralPath $paths.root -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
