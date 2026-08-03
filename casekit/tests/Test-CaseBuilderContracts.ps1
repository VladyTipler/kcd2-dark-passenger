$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $caseKitRoot 'CaseKit.psd1'
$templateModulePath = Join-Path $caseKitRoot `
    'core\CaseKit.Templates.psm1'
$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\authoring\valid'

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
        Add-Result ($_.Exception.Message -like $Pattern) $Label
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

$validPaths = New-TestDeckCopy -Name 'valid'
try {
    $deck = Read-TestDeck -Paths $validPaths
    Add-Result ([int]$deck.schemaVersion -eq 1) `
        'authored deck uses schema version 1'
    Add-Result ($deck.sourceFormat -eq 'casekit-authoring-v1') `
        'authored deck records its source format'
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
}
catch {
    Add-Result $false (
        "production authoring deck loads: $($_.Exception.Message)"
    )
    Add-Result $false 'production deck contains the first coherent StoryPack'
    Add-Result $false 'production StoryPack has a reachable reveal route'
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
