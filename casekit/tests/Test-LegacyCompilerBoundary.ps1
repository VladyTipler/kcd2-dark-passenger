$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$caseKitManifest = Join-Path $PSScriptRoot '..\CaseKit.psd1'
$compilerModule = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$caseRoot = Join-Path $repoRoot 'content\cases'
$bindingPath = Join-Path $repoRoot 'config\case-settlement-bindings.json'

Import-Module $caseKitManifest -Force
Import-Module $compilerModule -Force

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

function ConvertTo-ComparableJson($Value) {
    return $Value | ConvertTo-Json -Depth 100 -Compress
}

$directCases = @(Get-DpValidatedCaseSpecs `
    -CaseRoot $caseRoot `
    -BindingPath $bindingPath)
$directBindings = Read-DpCaseSettlementBindings -LiteralPath $bindingPath

$deck = Read-CaseKitAuthoringDeck `
    -LegacyCaseRoot $caseRoot `
    -LegacyBindingPath $bindingPath
$variants = @(Resolve-CaseKitVariants -Deck $deck)
$adapted = ConvertTo-CaseKitBackendInput -Variants $variants

$directCatalog = ConvertTo-DpCaseCatalogLua `
    -CaseSpecs $directCases `
    -Bindings $directBindings
$adaptedCatalog = ConvertTo-DpCaseCatalogLua `
    -CaseSpecs $adapted.caseSpecs `
    -Bindings $adapted.bindings
Add-Result ($directCatalog -ceq $adaptedCatalog) `
    'existing compiler emits byte-identical Lua catalog through CaseKit'

$directReport = ConvertTo-DpCaseCompatibilityReport -CaseSpecs $directCases
$adaptedReport = ConvertTo-DpCaseCompatibilityReport `
    -CaseSpecs $adapted.caseSpecs
Add-Result (
    (ConvertTo-ComparableJson $directReport) -ceq
    (ConvertTo-ComparableJson $adaptedReport)
) 'existing compiler emits identical compatibility report through CaseKit'

$directWiring = [System.Collections.Generic.List[object]]::new()
$adaptedWiring = [System.Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $directCases.Count; $index++) {
    $directWiring.Add((ConvertTo-DpNativeRegionWiring `
        -CaseSpec $directCases[$index] `
        -Binding $directBindings.settlements[$index]))
    $adaptedWiring.Add((ConvertTo-DpNativeRegionWiring `
        -CaseSpec $adapted.caseSpecs[$index] `
        -Binding $adapted.bindings.settlements[$index]))
}
Add-Result (
    (ConvertTo-ComparableJson $directWiring) -ceq
    (ConvertTo-ComparableJson $adaptedWiring)
) 'existing compiler emits identical native wiring through CaseKit'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
