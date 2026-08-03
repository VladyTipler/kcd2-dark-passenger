param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$casePath = Join-Path $repoRoot 'content\cases\missing-traveler.case.json'
$bindingPath = Join-Path $repoRoot 'config\case-settlement-bindings.json'
$modulePath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'

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

Add-Result (Test-Path -LiteralPath $casePath -PathType Leaf) `
    'Missing Traveler CaseSpec exists'

if (Test-Path -LiteralPath $casePath -PathType Leaf) {
    Import-Module $modulePath -Force
    $case = Read-DpCaseSpec -LiteralPath $casePath
    $bindings = Read-DpCaseSettlementBindings -LiteralPath $bindingPath
    $binding = @($bindings.settlements | Where-Object {
        $_.region -eq 'trosecko' -and $_.settlement -eq 'zelejov'
    })[0]
    $errors = @(Get-DpCaseSpecValidationErrors `
        -CaseSpec $case `
        -Bindings $bindings `
        -SourceName (Split-Path -Leaf $casePath))

    Add-Result ($errors.Count -eq 0) 'Missing Traveler validates'
    Add-Result (
        $case.id -eq 'missing_traveler' -and [int]$case.code -eq 2001
    ) 'case has stable identity and numeric code'
    Add-Result ([int]$case.schemaVersion -eq 2) `
        'case uses nonlinear evidence schema version 2'
    Add-Result (
        $case.constraints.region -eq 'trosecko' -and
        $case.constraints.settlement -eq 'zelejov'
    ) 'case is eligible only in Zhelejov'
    Add-Result (
        $case.targetPolicy.sex -eq 'male' -and
        $case.targetPolicy.allowStoryCharacters -eq $false -and
        $case.targetPolicy.requireKillable -eq $true -and
        $case.targetPolicy.requireAlive -eq $true
    ) 'target policy requires a living killable non-story man'
    Add-Result (
        $case.crimeProfile.innocentVictim -eq 'matej' -and
        $case.crimeProfile.method -eq 'robbery_murder' -and
        $case.crimeProfile.coverStory -eq 'forged_departure'
    ) 'crime profile encodes Matej robbery and forged departure'
    Add-Result (
        $binding.roles.witness.identity.ru.name -eq 'Богуслав' -and
        $binding.roles.witness.identity.ru.occupation -eq 'батрак' -and
        $binding.roles.witness.identity.en.name -eq 'Bretislav' -and
        $binding.roles.witness.identity.en.occupation -eq 'farmhand'
    ) 'witness binding preserves localized native identity'

    $steps = @($case.evidence)
    Add-Result (
        $steps.Count -eq 3 -and
        $steps[0].id -eq 'zelejov_innkeeper_missing_traveler' -and
        $steps[1].id -eq 'matej_guest_ledger' -and
        $steps[2].id -eq 'zelejov_stablehand_witness'
    ) 'evidence chain preserves rumor document witness order'
    Add-Result (
        ([int]$steps[0].confidence -eq 20) -and
        ([int]$steps[1].confidence -eq 30) -and
        ([int]$steps[2].confidence -eq 20) -and
        ([int]$case.revealThreshold -eq 70)
    ) 'confidence reaches reveal at 20 plus 30 plus 20'
    Add-Result (
        $steps[0].placement -eq 'on_event' -and
        $steps[0].discoverableWithoutHint -eq $true -and
        @($steps[0].hintsUnlockedBy).Count -eq 0 -and
        $steps[1].placement -eq 'case_start' -and
        $steps[1].discoverableWithoutHint -eq $true -and
        @($steps[1].hintsUnlockedBy) -contains $steps[0].id -and
        $steps[2].placement -eq 'on_event' -and
        $steps[2].discoverableWithoutHint -eq $false -and
        @($steps[2].hintsUnlockedBy) -contains $steps[0].id -and
        @($steps[2].hintsUnlockedBy) -notcontains $steps[1].id
    ) 'ledger and stablehand become parallel leads after the rumor'
    Add-Result (
        @($steps[0].reveals) -contains 'matej_horse_returned' -and
        @($steps[1].reveals) -contains 'forged_departure' -and
        @($steps[2].reveals) -contains 'suspect_identified'
    ) 'evidence sources reveal authored case facts'

    $document = $steps[1]
    Add-Result (
        $document.kind -eq 'document' -and
        $document.role -eq 'document' -and
        $document.item.name -eq 'dp_matej_guest_ledger' -and
        $document.item.nameKey -eq 'dp_mt_ledger_name' -and
        $document.item.infoKey -eq 'dp_mt_ledger_info' -and
        $document.item.contentKey -eq 'dp_mt_ledger_content' -and
        $document.reaction -eq 'vanilla_neutral'
    ) 'document declares generated item and voiced Henry reaction'

    $ruKeys = @($case.localization.ru.PSObject.Properties.Name | Sort-Object)
    $enKeys = @($case.localization.en.PSObject.Properties.Name | Sort-Object)
    Add-Result (
        $ruKeys.Count -ge 25 -and
        ($ruKeys -join "`n") -eq ($enKeys -join "`n")
    ) 'Russian and English localization keys have exact parity'
    Add-Result (
        @($case.localization.ru.PSObject.Properties | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.Value)
        }).Count -eq 0 -and
        @($case.localization.en.PSObject.Properties | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.Value)
        }).Count -eq 0
    ) 'all bilingual authored strings are non-empty'

    Add-Result (
        $case.localization.ru.dp_mt_witness_objective_active -eq (
            'Лаврентий сказал, что конь Матея вернулся без всадника. ' +
            'Батрак Богуслав мог видеть, кто привёл его обратно.'
        ) -and
        $case.localization.en.dp_mt_witness_objective_active -eq (
            "Lavrentiy said Matej's horse returned without its rider. " +
            'The farmhand Bretislav may have seen who brought it back.'
        )
    ) 'farmhand direction cites the riderless horse fact'
    Add-Result (
        $case.localization.ru.dp_mt_witness_prompt.Contains('Богуслава') -and
        $case.localization.ru.dp_mt_witness_objective_name -eq `
            'Расспросить батрака Богуслава' -and
        $case.localization.ru.dp_mt_witness_objective_done.Contains(
            'Богуслав видел'
        ) -and
        $case.localization.en.dp_mt_witness_prompt.Contains('Bretislav') -and
        $case.localization.en.dp_mt_witness_objective_name -eq `
            'Question the farmhand Bretislav'
    ) 'visible witness copy uses localized name and actual occupation'
    Add-Result (
        -not $case.localization.ru.dp_mt_witness_objective_active.Contains(
            'Записка Матея'
        ) -and
        -not $case.localization.en.dp_mt_witness_objective_active.Contains(
            "Matej's note"
        )
    ) 'stablehand direction does not invent a clue from the note'

    $referencedKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($dialogue in @($case.native.dialogues)) {
        $referencedKeys.Add([string]$dialogue.rootKey)
        $referencedKeys.Add([string]$dialogue.promptKey)
        foreach ($response in @($dialogue.responses)) {
            $referencedKeys.Add([string]$response.key)
        }
    }
    foreach ($key in @(
        $case.native.witnessObjective.nameKey,
        $case.native.witnessObjective.activeKey,
        $case.native.witnessObjective.doneKey,
        $document.item.nameKey,
        $document.item.infoKey,
        $document.item.contentKey
    )) {
        $referencedKeys.Add([string]$key)
    }
    Add-Result (
        @($referencedKeys | Select-Object -Unique | Where-Object {
            $_ -notin $ruKeys -or $_ -notin $enKeys
        }).Count -eq 0
    ) 'every native and document key has RU and EN text'

    Add-Result (
        $case.native.questName -eq 'dark_within_t' -and
        $case.native.contexts.rumorHeard -eq `
            'dp_rumor_heard_trosecko' -and
        $case.native.contexts.witnessHeard -eq `
            'dp_witness_heard_trosecko'
    ) 'case targets the universal Trosky quest and contexts'
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
