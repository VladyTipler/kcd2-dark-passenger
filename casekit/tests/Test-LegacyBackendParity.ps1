$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifestPath = Join-Path $PSScriptRoot '..\CaseKit.psd1'
$caseRoot = Join-Path $repoRoot 'content\cases'
$bindingPath = Join-Path $repoRoot 'config\case-settlement-bindings.json'

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

function ConvertTo-ComparableJson($Value) {
    return $Value | ConvertTo-Json -Depth 100 -Compress
}

$legacyCases = @(Get-ChildItem -LiteralPath $caseRoot `
    -Filter '*.case.json' -File |
    ForEach-Object {
        [System.IO.File]::ReadAllText($_.FullName) |
            ConvertFrom-Json -Depth 100
    } |
    Sort-Object @{ Expression = { [int]$_.code } }, `
        @{ Expression = { [string]$_.id } })

$deck = Read-CaseKitAuthoringDeck `
    -LegacyCaseRoot $caseRoot `
    -LegacyBindingPath $bindingPath
$variants = @(Resolve-CaseKitVariants -Deck $deck)

try {
    $backend = ConvertTo-CaseKitBackendInput -Variants $variants
    Add-Result (
        (ConvertTo-ComparableJson $backend.caseSpecs) -eq
        (ConvertTo-ComparableJson $legacyCases)
    ) 'CaseKit round-trip preserves both legacy CaseSpecs exactly'
    Add-Result (
        (ConvertTo-ComparableJson $backend.bindings.settlements) -eq
        (ConvertTo-ComparableJson $deck.settlements)
    ) 'CaseKit round-trip preserves settlement bindings exactly'

    $second = ConvertTo-CaseKitBackendInput -Variants $variants
    Add-Result (
        (ConvertTo-ComparableJson $second) -eq
        (ConvertTo-ComparableJson $backend)
    ) 'CaseKit backend input is deterministic'
}
catch {
    Add-Result $false "legacy backend parity: $($_.Exception.Message)"
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
