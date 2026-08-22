$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$orchestrator = Join-Path $workspaceRoot `
    'DialogueMediaKit\tools\Build-Kcd2Media.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('dp-dialogue-media-orchestrator-' + [guid]::NewGuid().ToString('N'))
$checks = 0
$failures = [System.Collections.Generic.List[string]]::new()

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
    Add-Result (Test-Path -LiteralPath $orchestrator -PathType Leaf) `
        'reusable KCD2 media orchestrator exists'
    if (-not (Test-Path -LiteralPath $orchestrator -PathType Leaf)) {
        throw 'Dialogue media orchestrator is missing.'
    }

    $buildMod = [System.IO.File]::ReadAllText((Join-Path $repoRoot `
        'tools\Build-Mod.ps1'))
    Add-Result (
        $buildMod.Contains('Build-Kcd2Media.ps1') -and
        $buildMod.Contains('SkipDialogueMedia') -and
        $buildMod.Contains('DialogueMediaResolvedJobsPath') -and
        ([regex]::Matches($buildMod, '& \$caseCompilerPath').Count -ge 2)
    ) 'default mod build prepares media and recompiles graphs with measured durations'

    $generatedRoot = Join-Path $tempRoot 'generated'
    $outputRoot = Join-Path $tempRoot 'output'
    $resultsPath = Join-Path $outputRoot 'dialogue-media-results.json'
    $retailRoot = 'H:\SteamLibrary\steamapps\common\KingdomComeDeliverance2'
    $moddingRoot = 'H:\SteamLibrary\steamapps\common\KCD2Mod'

    & $orchestrator `
        -DemandsPath (Join-Path $repoRoot `
            'build\generated\voice\dialogue-media-demands.json') `
        -GeneratedRoot $generatedRoot `
        -OutputRoot $outputRoot `
        -ResultsPath $resultsPath `
        -TablesPak (Join-Path $retailRoot 'Data\Tables.pak') `
        -LocalizationRoot (Join-Path $retailRoot 'Localization') `
        -ModdingRoot $moddingRoot `
        -BaselineRoot (Join-Path $workspaceRoot `
            '_work\native-lipsync-pilot') `
        -BaseFacialImage (Join-Path $workspaceRoot `
            '_work\retail-facials-2026-08-16\part0\Animations\FacialAnimations.img') `
        -PhonemeExecutable (Join-Path $workspaceRoot `
            '_work\facial-pipeline-2026-08-16\bin\dp-phonemes.exe') `
        -PhonemePluginRoot (Join-Path $moddingRoot `
            'Editor\Plugins\LipSync\Annosoft') `
        -SettingsPath (Join-Path $workspaceRoot `
            'DialogueMediaKit\config\omnivoice-kcd2-english.json') `
        -CacheRoot (Join-Path $workspaceRoot `
            'DialogueMediaKit\.cache\dark-passenger-media') `
        -VoiceProfileRoot (Join-Path $workspaceRoot `
            'DialogueMediaKit\.cache\dark-passenger-voice-profiles')

    $jobs = Get-Content -LiteralPath (Join-Path $generatedRoot `
        'dialogue-media-jobs-resolved.json') -Raw | ConvertFrom-Json -Depth 100
    $catalog = Get-Content -LiteralPath (Join-Path $generatedRoot `
        'dialogue-voice-catalog.json') -Raw | ConvertFrom-Json -Depth 100
    $resolution = Get-Content -LiteralPath (Join-Path $generatedRoot `
        'dialogue-media-resolution.json') -Raw | ConvertFrom-Json -Depth 100
    $results = Get-Content -LiteralPath $resultsPath -Raw |
        ConvertFrom-Json -Depth 100

    Add-Result (@($jobs.jobs).Count -eq 420) `
        'all current eligible actor and line combinations become jobs'
    Add-Result (@($catalog.profiles).Count -eq 18) `
        'all distinct selected actor voices are discovered'
    Add-Result (@($resolution.excludedActors).Count -eq 0) `
        'current eligible pool has no unresolved voice fallback'
    Add-Result (
        $results.status -eq 'complete' -and
        @($results.jobs).Count -eq @($jobs.jobs).Count
    ) 'one command crosses actor resolution through complete media results'
    Add-Result (
        (Test-Path -LiteralPath ([string]$results.packages.voice.path) `
            -PathType Leaf) -and
        (Test-Path -LiteralPath ([string]$results.packages.facial.path) `
            -PathType Leaf)
    ) 'one command produces voice and native facial packages'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    throw "Dialogue media orchestrator failed $($failures.Count) of " +
        "$checks checks: $($failures -join '; ')"
}

Write-Host "All $checks dialogue media orchestrator checks passed."
