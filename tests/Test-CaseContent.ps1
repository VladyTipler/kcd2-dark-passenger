param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot 'src\Data\Scripts\mods'
$runtimePath = Join-Path $scriptRoot 'darkpassengertest.lua'
$caseRuntimePath = Join-Path $scriptRoot 'dpcasecontent.lua'
$caseDefinitionPath = Join-Path $repoRoot `
    'content\migration\legacy-cases\convenient-accident.case.json'
$generatedCatalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_catalog.lua'
$generatedVariantCatalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'
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
$generatedCatalog = Read-OptionalText $generatedCatalogPath
$generatedVariantCatalog = Read-OptionalText $generatedVariantCatalogPath
$evidence = Read-OptionalText $evidencePath

Add-Result (Test-Path -LiteralPath $caseRuntimePath) `
    'persistent case-content runtime exists'
Add-Result (Test-Path -LiteralPath $caseDefinitionPath) `
    'convenient-accident CaseSpec exists'
Add-Result (Test-Path -LiteralPath $generatedCatalogPath) `
    'compiled case catalog exists'
Add-Result (Test-Path -LiteralPath $generatedVariantCatalogPath) `
    'compiled finite variant catalog exists'

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
    'dp_case_content_case_code',
    'dp_case_content_opener_code',
    'dp_case_content_variant_code',
    'PrepareVariant',
    'source_stance',
    'placement',
    'discoverable_without_hint',
    'hints_unlocked_by',
    'reveals'
) {
    Add-Result (
        $caseRuntime.Contains($token) -or
        $caseDefinition.Contains($token) -or
        $generatedCatalog.Contains($token) -or
        $generatedVariantCatalog.Contains($token)
    ) "case-content contract contains $token"
}

foreach ($token in
    'id = "convenient_accident"',
    'code = 1001',
    'id = "pritoky_innkeeper_strong_suspicion"',
    'code = 1101',
    'source_stance = "afraid"',
    'confidence = 20',
    'placement = "on_event"',
    'discoverable_without_hint = true',
    'region = "kutnohorsko"',
    'settlement = "pritoky"'
) {
    Add-Result ($generatedCatalog.Contains($token)) `
        "compiled canary content contains $token"
}
Add-Result (-not $generatedCatalog.Contains('next_lead =')) `
    'compiled content has no obsolete linear next-lead chain'

$contentReload =
    'Script.ReloadScript("Scripts/mods/generated/dp_case_catalog.lua")'
$variantReload =
    'Script.ReloadScript("Scripts/mods/generated/dp_case_variant_catalog.lua")'
$caseRuntimeReload =
    'Script.ReloadScript("Scripts/mods/dpcasecontent.lua")'
$evidenceReload = 'Script.ReloadScript("Scripts/mods/dpevidence.lua")'
$contentIndex = $runtime.IndexOf($contentReload)
$variantIndex = $runtime.IndexOf($variantReload)
$caseRuntimeIndex = $runtime.IndexOf($caseRuntimeReload)
$evidenceIndex = $runtime.IndexOf($evidenceReload)
Add-Result (
    $contentIndex -ge 0 -and
    $variantIndex -gt $contentIndex -and
    $caseRuntimeIndex -gt $variantIndex -and
    $evidenceIndex -gt $caseRuntimeIndex
) 'runtime loads domain content, reusable selector, then evidence consumer'

Add-Result (
    $evidence.Contains('DarkPassengerCaseContent.GetSelected(') -and
    $evidence.Contains('selectedRumor.code') -and
    $evidence.Contains('DarkPassengerEvidenceRegistry.Discover(')
) 'evidence consumes the persisted selected rumor contract'
Add-Result (-not $evidence.Contains('CONFIDENCE_REWARD = 30')) `
    'legacy hard-coded rumor reward is removed'

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    foreach ($path in @(
        $generatedCatalogPath,
        $generatedVariantCatalogPath,
        $caseRuntimePath,
        $evidencePath
    )) {
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
