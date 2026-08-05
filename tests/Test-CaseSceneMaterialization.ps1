$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sceneDirectorPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcasescenedirector.lua'
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$snapshotPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcasesnapshot.lua'
$posePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpposeprobe.lua'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Read-OptionalText {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return '' }
    return [System.IO.File]::ReadAllText($LiteralPath)
}

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

$director = Read-OptionalText $sceneDirectorPath
$runtime = Read-OptionalText $runtimePath
$snapshot = Read-OptionalText $snapshotPath
$pose = Read-OptionalText $posePath

Add-Result (Test-Path -LiteralPath $sceneDirectorPath -PathType Leaf) `
    'runtime SceneDirector exists'

foreach ($export in @(
    'BuildCaseInstance',
    'BuildSceneInstances',
    'Materialize',
    'Restore',
    'CanOfferInterrogation',
    'MarkInterrogationOffered',
    'RunSelfTest'
)) {
    Add-Result ($director.Contains("function DarkPassengerSceneDirector.$export")) `
        "SceneDirector exports $export"
}

foreach ($token in @(
    'caseInstance.variantId',
    'sceneDefinitions',
    'resolvedBindings',
    'compiledAssets',
    'DarkPassengerEvidenceSeeder.Seed(',
    'already_materialized',
    'streaming_deferred',
    'interrogationOffered'
)) {
    Add-Result ($director.Contains($token)) `
        "SceneDirector contract contains $token"
}

Add-Result (
    $runtime.Contains(
        'Script.ReloadScript("Scripts/mods/dpcasescenedirector.lua")'
    ) -and
    $runtime.IndexOf('dpcasesnapshot.lua') -lt
        $runtime.IndexOf('dpcasescenedirector.lua') -and
    $runtime.IndexOf('dpcasescenedirector.lua') -lt
        $runtime.IndexOf('dpevidenceseeder.lua')
) 'SceneDirector loads after snapshot and before presentation adapters'
Add-Result (
    -not $director.Contains('DarkPassengerLeadPlanner.Apply(')
) 'SceneDirector leaves presentation publishing to the lifecycle barrier'
Add-Result (
    $snapshot.Contains('DarkPassengerSceneDirector.BuildCaseInstance(') -and
    $snapshot.Contains('sceneInstances =')
) 'snapshot resolves one CaseInstance with bound SceneInstances'
Add-Result (
    $director.Contains('evidence.placement == "case_start"') -and
    $director.Contains('evidence.evidence_code')
) 'case-start evidence placement is driven only by compiled definitions'
Add-Result (
    $director.Contains(
        'local caseInstance = DarkPassengerSceneDirector.BuildCaseInstance(snapshot)'
    )
) 'materialization re-resolves live scene bindings on every retry'
Add-Result (
    $director.Contains('if not HasDeferredScenes(caseInstance) then') -and
    $director.IndexOf('if not HasDeferredScenes(caseInstance) then') -lt
        $director.IndexOf(
            'materializedGenerations[generation] = true'
        )
) 'streaming-deferred generations remain retryable'
Add-Result (
    $pose.Contains('DarkPassengerSceneDirector.CanOfferInterrogation(') -and
    $pose.Contains('DarkPassengerSceneDirector.MarkInterrogationOffered(') -and
    $pose.Contains('IsUnconscious(target)') -and
    $pose.Contains('HasCockerel(actor)')
) 'pre-execution interrogation is target-bound, unconscious, consumable and once per case'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
