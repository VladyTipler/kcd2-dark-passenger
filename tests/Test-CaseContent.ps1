param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot 'src\Data\Scripts\mods'
$runtimePath = Join-Path $scriptRoot 'darkpassengertest.lua'
$caseRuntimePath = Join-Path $scriptRoot 'dpcasecontent.lua'
$caseDefinitionPath = Join-Path $scriptRoot `
    'content\dp_case_convenient_accident.lua'
$evidencePath = Join-Path $scriptRoot 'dpevidence.lua'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Read-OptionalText {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return '' }
    return Get-Content -Raw -LiteralPath $LiteralPath
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

$runtime = Read-OptionalText $runtimePath
$caseRuntime = Read-OptionalText $caseRuntimePath
$caseDefinition = Read-OptionalText $caseDefinitionPath
$evidence = Read-OptionalText $evidencePath

Add-Result (Test-Path -LiteralPath $caseRuntimePath) `
    'persistent case-content runtime exists'
Add-Result (Test-Path -LiteralPath $caseDefinitionPath) `
    'convenient-accident content definition exists'

foreach ($export in
    'Select',
    'Transition',
    'Resolve',
    'GetSelected',
    'OnInvestigationOpened',
    'Restore',
    'RunSelfTest'
) {
    Add-Result ($caseRuntime.Contains("function DarkPassengerCaseContent.$export")) `
        "case-content runtime exports $export"
}

foreach ($token in
    'dp_case_content_schema_version',
    'dp_case_content_generation',
    'dp_case_content_template_slot',
    'dp_case_content_rumor_slot',
    'selected once per investigation generation',
    'source_stance',
    'next_lead'
) {
    Add-Result (
        $caseRuntime.Contains($token) -or $caseDefinition.Contains($token)
    ) "case-content contract contains $token"
}

foreach ($token in
    'id = "convenient_accident"',
    'id = "pritoky_innkeeper_strong_suspicion"',
    'source_stance = "afraid"',
    'confidence = 20',
    'next_lead = "vojtech_belongings"',
    'region = "kutnohorsko"',
    'settlement = "pritoky"'
) {
    Add-Result ($caseDefinition.Contains($token)) `
        "canary content contains $token"
}

$contentReload =
    'Script.ReloadScript("Scripts/mods/content/dp_case_convenient_accident.lua")'
$caseRuntimeReload =
    'Script.ReloadScript("Scripts/mods/dpcasecontent.lua")'
$evidenceReload = 'Script.ReloadScript("Scripts/mods/dpevidence.lua")'
$contentIndex = $runtime.IndexOf($contentReload)
$caseRuntimeIndex = $runtime.IndexOf($caseRuntimeReload)
$evidenceIndex = $runtime.IndexOf($evidenceReload)
Add-Result (
    $contentIndex -ge 0 -and
    $caseRuntimeIndex -gt $contentIndex -and
    $evidenceIndex -gt $caseRuntimeIndex
) 'runtime loads domain content, reusable selector, then evidence consumer'

Add-Result (
    $evidence.Contains('DarkPassengerCaseContent.GetSelected(') -and
    $evidence.Contains('selectedRumor.confidence') -and
    $evidence.Contains('selectedRumor.id')
) 'evidence consumes the persisted selected rumor contract'
Add-Result (-not $evidence.Contains('CONFIDENCE_REWARD = 30')) `
    'legacy hard-coded rumor reward is removed'

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    foreach ($path in $caseDefinitionPath, $caseRuntimePath, $evidencePath) {
        if ((Test-Path -LiteralPath $compiler) -and
            (Test-Path -LiteralPath $path)) {
            & $compiler -p $path *> $null
            Add-Result ($LASTEXITCODE -eq 0) `
                "LuaCompiler parses $(Split-Path -Leaf $path)"
        }
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
