$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$caseCompiler = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$caseVariantRoot = Join-Path $repoRoot `
    'build\generated\casekit\compiler-input'
$voiceRegistryPath = Join-Path $repoRoot `
    'config\dialogue-voice-registry.json'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "dark-passenger-dialogue-voice-$([guid]::NewGuid())"
$buildRoot = Join-Path $tempRoot 'build'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()
function Add-Result([bool]$Condition, [string]$Label) {
    $script:checks++
    if ($Condition) {
        Write-Host "PASS: $Label"
    }
    else {
        $script:failures.Add($Label)
        Write-Host "FAIL: $Label"
    }
}

$registry = [System.IO.File]::ReadAllText($voiceRegistryPath) |
    ConvertFrom-Json -Depth 100
Add-Result (
    [int]$registry.schemaVersion -eq 1 -and
    @($registry.voiceProfiles).Count -eq 0 -and
    @($registry.dialogueAssignments).Count -eq 0
) 'authored registry contains no actor-specific pilot hardcode'

$unvoicedDialogueFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'content\stories') `
        -Recurse -File -Filter '*.json' |
        Where-Object { $_.Directory.Name -eq 'dialogues' } |
        Where-Object {
            $dialogueDefinition =
                [System.IO.File]::ReadAllText($_.FullName) |
                ConvertFrom-Json -Depth 100
            $null -eq $dialogueDefinition.media -or
                [string]$dialogueDefinition.media.voice -cne 'native' -or
                [bool]$dialogueDefinition.media.lipSync -ne $true
        }
)
Add-Result (
    $unvoicedDialogueFiles.Count -eq 0
) ('every shipped dialogue explicitly requests native voice and lip sync' +
    $(if ($unvoicedDialogueFiles.Count -gt 0) {
        ': ' + (@($unvoicedDialogueFiles.Name) -join ', ')
    } else { '' }))

try {
    $stagedRpgRoot = Join-Path $buildRoot `
        'mod\Data\Libs\Tables\rpg'
    $stagedStormRoot = Join-Path $buildRoot `
        'mod\Data\Libs\Storm\roles\quests'
    New-Item -ItemType Directory -Path $stagedRpgRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $stagedStormRoot -Force | Out-Null
    foreach ($fileName in @(
        'buff_ai_tag__darkpassengertest.xml',
        'buff__darkpassengertest.xml',
        'role__darkpassengertest.xml'
    )) {
        Copy-Item -LiteralPath (Join-Path $repoRoot `
            "src\Data\Libs\Tables\rpg\$fileName") `
            -Destination (Join-Path $stagedRpgRoot $fileName)
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot `
        'src\Data\Libs\Storm\roles\quests\darkpassengertest.xml') `
        -Destination (Join-Path $stagedStormRoot 'darkpassengertest.xml')

    & $caseCompiler `
        -CaseVariantRoot $caseVariantRoot `
        -LocalizationRoot (Join-Path $repoRoot 'localization') `
        -BuildRoot $buildRoot

    $mediaDemandsPath = Join-Path $buildRoot `
        'generated\voice\dialogue-media-demands.json'
    $mediaDemands = [System.IO.File]::ReadAllText($mediaDemandsPath) |
        ConvertFrom-Json -Depth 100
    $bindingContract = [System.IO.File]::ReadAllText((Join-Path `
        $caseVariantRoot 'case-settlement-bindings.json')) |
            ConvertFrom-Json -Depth 100
    $expectedActors = @($bindingContract.settlements | Where-Object {
        [int]$_.caseCode -eq 2001
    } | ForEach-Object { @($_.actorPools.innkeeper) } |
        ForEach-Object { [string]$_.entityName } | Sort-Object -Unique)
    $actualActors = @($mediaDemands.demands | Where-Object {
        [string]$_.storyId -eq 'missing_traveler' -and
        [string]$_.speakerRole -eq 'innkeeper'
    } | ForEach-Object { [string]$_.actor.entityName } |
        Sort-Object -Unique)
    Add-Result (
        @($mediaDemands.demands).Count -gt 16 -and
        ($actualActors -join ',') -ceq ($expectedActors -join ',')
    ) 'compiler emits media demands for every eligible selected actor'

    $graphName =
        'dpcase2001_trosecko_troskovice_' +
        'innkeeper_missing_traveler_dialog_t'
    $dialoguePath = Join-Path $buildRoot (
        'mod\Data\Quests\darkpassengertest\trosecko\dark_within_t\' +
        "$graphName.xml"
    )
    [xml]$dialogue = [System.IO.File]::ReadAllText($dialoguePath)
    $responses = @($dialogue.SelectNodes('//FaderDialog//Response'))
    Add-Result (
        @($dialogue.SelectNodes('//SelectedSoul')).Count -eq 0 -and
        $responses.Count -eq 16
    ) 'generic graph does not pin Beta or any other SelectedSoul'
    Add-Result (
        @($responses | Where-Object {
            -not [string]::IsNullOrWhiteSpace(
                $_.GetAttribute('ReferenceLength')
            )
        }).Count -eq 0
    ) 'first pass defers durations until generated media results exist'

    $voiceManifest = [System.IO.File]::ReadAllText((Join-Path $buildRoot `
        'generated\voice\dialogue-voice-manifest.json')) |
            ConvertFrom-Json -Depth 100
    $legacyJobs = [System.IO.File]::ReadAllText((Join-Path $buildRoot `
        'generated\voice\dialogue-media-jobs.json')) |
            ConvertFrom-Json -Depth 100
    Add-Result (
        @($voiceManifest.assets).Count -eq 0 -and
        @($voiceManifest.facialAssets).Count -eq 0 -and
        @($legacyJobs.jobs).Count -eq 0
    ) 'legacy 16-line pilot no longer produces build artifacts'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    throw "$($script:failures.Count) of $($script:checks) checks failed: " +
        ($script:failures -join '; ')
}
Write-Host "All $($script:checks) dynamic voice registry checks passed."
