$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$lifecyclePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcaselifecycle.lua'
$mainPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$evidencePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpevidence.lua'
$hungerPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dphunger.lua'
$sceneDirectorPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcasescenedirector.lua'

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

$lifecycle = Read-OptionalText $lifecyclePath
$main = Read-OptionalText $mainPath
$evidence = Read-OptionalText $evidencePath
$hunger = Read-OptionalText $hungerPath
$sceneDirector = Read-OptionalText $sceneDirectorPath

Add-Result (Test-Path -LiteralPath $lifecyclePath -PathType Leaf) `
    'case lifecycle runtime exists'

foreach ($function in @(
    'ResolveManifest',
    'ClearCaseArtifacts',
    'PrepareCaseGeneration',
    'ActivatePreparedGeneration',
    'Reconcile',
    'RunSelfTest'
)) {
    Add-Result (
        $lifecycle.Contains("function DarkPassengerCaseLifecycle.$function")
    ) "lifecycle exports $function"
}

foreach ($token in @(
    'manifest.schema_version',
    'retention == "case"',
    'inventory.DeleteItemOfClass',
    'RemoveAllBuffsByGuid',
    'clearedGeneration',
    'preparedGeneration',
    'Script.SetTimerForFunction',
    'DarkPassengerLeadPlanner.Apply('
)) {
    Add-Result ($lifecycle.Contains($token)) "lifecycle contains $token"
}

Add-Result (
    $main.Contains(
        'Script.ReloadScript("Scripts/mods/dpcaselifecycle.lua")'
    ) -and
    $main.IndexOf('dpcaselifecycle.lua') -lt
        $main.IndexOf('dpevidence.lua')
) 'lifecycle loads before evidence presentation'
Add-Result (
    $main.Contains('DarkPassengerCaseLifecycle.ClearCaseArtifacts(')
) 'target replacement clears the prior generated case'
Add-Result (
    $evidence.Contains('DarkPassengerCaseLifecycle.PrepareCaseGeneration(')
) 'evidence open uses the cleanup activation barrier'
Add-Result (
    $hunger.Contains('DarkPassengerCaseLifecycle.ClearCaseArtifacts(')
) 'resolved hunt clears case-retained artifacts'
Add-Result (
    -not $sceneDirector.Contains('DarkPassengerLeadPlanner.Apply(generation)')
) 'SceneDirector cannot publish lead buffs before lifecycle cleanup barrier'
Add-Result (
    $lifecycle.Contains('ACTIVATION_DELAY_MS = 2000')
) 'lifecycle waits beyond the native one-second quest activation timer'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
