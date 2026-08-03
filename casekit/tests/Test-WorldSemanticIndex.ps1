$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $caseKitRoot 'CaseKit.psd1'
$worldPath = Join-Path $PSScriptRoot 'fixtures\world\actors.json'
$victimPath = Join-Path $PSScriptRoot 'fixtures\world\victim-catalog.json'

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

try {
    $index = New-CaseKitWorldIndex `
        -RawWorldPath $worldPath `
        -VictimCatalogPath $victimPath

    Add-Result ([int]$index.schemaVersion -eq 1) `
        'world index uses schema version 1'
    Add-Result (@($index.entities).Count -eq 4) `
        'world index contains actors and containers'
    Add-Result (
        @($index.settlements).Count -eq 2 -and
        $index.settlements[0].settlement -eq 'pritoky' -and
        [int]$index.settlements[0].actorCount -eq 2 -and
        [int]$index.settlements[0].containerCount -eq 0 -and
        $index.settlements[1].settlement -eq 'zelejov' -and
        [int]$index.settlements[1].actorCount -eq 1 -and
        [int]$index.settlements[1].containerCount -eq 1
    ) 'world index summarizes every settlement independently'
    Add-Result (
        (@($index.entities | ForEach-Object {
            "$($_.region)/$($_.settlement)/$($_.kind)/$($_.entityName)"
        }) -join ',') -eq (
            'kutnohorsko/pritoky/actor/test_story_actor,' +
            'kutnohorsko/pritoky/actor/test_worker,' +
            'trosecko/zelejov/actor/test_innkeeper,' +
            'trosecko/zelejov/container/stash[Chest.test]'
        )
    ) 'world entities have deterministic semantic ordering'

    $innkeeper = $index.entities | Where-Object entityName -eq 'test_innkeeper'
    Add-Result (
        $innkeeper.kind -eq 'actor' -and
        $innkeeper.identityMode -eq 'unresolved' -and
        'person.identity_review_required' -in @($innkeeper.capabilities) -and
        'person.named' -notin @($innkeeper.capabilities) -and
        'role.innkeeper' -in @($innkeeper.capabilities) -and
        'role.tavern_worker' -in @($innkeeper.capabilities) -and
        'place.inn' -in @($innkeeper.capabilities) -and
        @($innkeeper.homeLinks).Count -eq 1 -and
        @($innkeeper.workLinks).Count -eq 1
    ) 'localized innkeeper stays identity-unresolved until reviewed'

    $worker = $index.entities | Where-Object entityName -eq 'test_worker'
    Add-Result (
        $worker.identityMode -eq 'anonymous' -and
        $worker.policyFlags -is [array] -and
        'victim.eligible' -in @($worker.policyFlags) -and
        'person.killable' -in @($worker.capabilities) -and
        'interaction.dialogue' -notin @($worker.capabilities)
    ) 'generic eligible actor stays anonymous, killable and interaction-unreviewed'

    $storyActor = $index.entities |
        Where-Object entityName -eq 'test_story_actor'
    Add-Result (
        'story.critical' -in @($storyActor.policyFlags) -and
        'victim.review_required' -in @($storyActor.policyFlags) -and
        'person.killable' -notin @($storyActor.capabilities)
    ) 'story-critical actor is never inferred as killable'

    $container = $index.entities |
        Where-Object entityName -eq 'stash[Chest.test]'
    Add-Result (
        $container.kind -eq 'container' -and
        'container.stash' -in @($container.capabilities) -and
        'place.inn' -in @($container.capabilities) -and
        'container.evidence' -notin @($container.capabilities)
    ) 'stash is indexed without assuming evidence suitability'

    $jsonA = $index | ConvertTo-Json -Depth 12
    $jsonB = (New-CaseKitWorldIndex `
        -RawWorldPath $worldPath `
        -VictimCatalogPath $victimPath) | ConvertTo-Json -Depth 12
    Add-Result ($jsonA -ceq $jsonB) `
        'world index generation is byte-deterministic in memory'

    $splitSourcePath = Join-Path ([System.IO.Path]::GetTempPath()) `
        'casekit-world-split-source.json'
    $splitSource = Get-Content -Raw -LiteralPath $worldPath | ConvertFrom-Json
    $splitSource | Add-Member `
        -NotePropertyName actors `
        -NotePropertyValue @($splitSource.candidates) `
        -Force
    $splitSource.candidates = @(
        $splitSource.candidates | Where-Object entityName -eq 'test_worker'
    )
    [System.IO.File]::WriteAllText(
        $splitSourcePath,
        (($splitSource | ConvertTo-Json -Depth 12) + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
    try {
        $splitIndex = New-CaseKitWorldIndex `
            -RawWorldPath $splitSourcePath `
            -VictimCatalogPath $victimPath
        Add-Result (
            @($splitIndex.entities | Where-Object kind -eq 'actor').Count -eq 3
        ) 'world adapter prefers additive actors over legacy victim source'
    }
    finally {
        Remove-Item `
            -LiteralPath $splitSourcePath `
            -Force `
            -ErrorAction SilentlyContinue
    }

    $duplicatePath = Join-Path ([System.IO.Path]::GetTempPath()) `
        'casekit-world-duplicate.json'
    $duplicate = Get-Content -Raw -LiteralPath $worldPath | ConvertFrom-Json
    $duplicate.candidates[1].entityGuid = `
        [string]$duplicate.candidates[0].entityGuid
    [System.IO.File]::WriteAllText(
        $duplicatePath,
        (($duplicate | ConvertTo-Json -Depth 12) + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
    try {
        New-CaseKitWorldIndex `
            -RawWorldPath $duplicatePath `
            -VictimCatalogPath $victimPath | Out-Null
        Add-Result $false 'duplicate entity GUID is rejected'
    }
    catch {
        Add-Result (
            $_.Exception.Message -like '*Duplicate entity GUID*'
        ) 'duplicate entity GUID is rejected'
    }
    finally {
        Remove-Item -LiteralPath $duplicatePath -Force -ErrorAction SilentlyContinue
    }
}
catch {
    Add-Result $false "world index builds: $($_.Exception.Message)"
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
