$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifestPath = Join-Path $PSScriptRoot '..\CaseKit.psd1'
$caseRoot = Join-Path $repoRoot 'content\migration\legacy-cases'
$bindingPath = Join-Path $repoRoot `
    'content\migration\legacy-case-settlement-bindings.json'

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
    $deck = Read-CaseKitAuthoringDeck `
        -LegacyCaseRoot $caseRoot `
        -LegacyBindingPath $bindingPath

    Add-Result ([int]$deck.schemaVersion -eq 1) `
        'legacy deck uses CaseKit schema version 1'
    Add-Result ($deck.sourceFormat -eq 'legacy-case-spec-v2') `
        'legacy deck records its adapter format'
    Add-Result (
        (@($deck.cases | ForEach-Object { $_.case.id }) -join ',') -eq
            'convenient_accident,missing_traveler'
    ) 'legacy cases are sorted by stable code and id'
    Add-Result (
        (@($deck.settlements | ForEach-Object {
            "$($_.region)/$($_.settlement)"
        }) -join ',') -eq 'kutnohorsko/pritoky,trosecko/zelejov'
    ) 'legacy settlement bindings are sorted deterministically'
}
catch {
    Add-Result $false "legacy deck loads: $($_.Exception.Message)"
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
