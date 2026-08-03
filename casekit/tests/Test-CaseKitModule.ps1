$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $caseKitRoot 'CaseKit.psd1'

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

Add-Result (Test-Path -LiteralPath $manifestPath -PathType Leaf) `
    'CaseKit module manifest exists'

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    Import-Module $manifestPath -Force
    $expected = @(
        'ConvertTo-CaseKitBackendInput',
        'Read-CaseKitAuthoringDeck',
        'Resolve-CaseKitVariants'
    ) | Sort-Object
    $actual = @(Get-Command -Module CaseKit |
        Select-Object -ExpandProperty Name |
        Sort-Object)
    Add-Result (
        (@(Compare-Object $expected $actual).Count -eq 0)
    ) 'CaseKit exports only the stable facade'
}
else {
    Add-Result $false 'CaseKit exports only the stable facade'
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
