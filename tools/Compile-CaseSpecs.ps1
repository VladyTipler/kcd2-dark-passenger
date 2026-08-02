param(
    [string]$CaseRoot,
    [string]$BindingPath,
    [string]$BuildRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CaseRoot)) {
    $CaseRoot = Join-Path $repoRoot 'content\cases'
}
if ([string]::IsNullOrWhiteSpace($BindingPath)) {
    $BindingPath = Join-Path $repoRoot 'config\case-settlement-bindings.json'
}
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    $BuildRoot = Join-Path $repoRoot 'build'
}

$modulePath = Join-Path $PSScriptRoot 'CaseSpecCompiler.psm1'
Import-Module $modulePath -Force

$cases = @(Get-DpValidatedCaseSpecs `
    -CaseRoot $CaseRoot `
    -BindingPath $BindingPath)
$bindings = Read-DpCaseSettlementBindings -LiteralPath $BindingPath

$catalogPath = Join-Path $BuildRoot `
    'mod\Data\Scripts\mods\generated\dp_case_catalog.lua'
$reportPath = Join-Path $BuildRoot `
    'generated\cases\case-compatibility.json'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($parent in @(
    (Split-Path -Parent $catalogPath),
    (Split-Path -Parent $reportPath)
)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$catalog = ConvertTo-DpCaseCatalogLua `
    -CaseSpecs $cases `
    -Bindings $bindings
$report = ConvertTo-DpCaseCompatibilityReport -CaseSpecs $cases
$reportJson = ($report | ConvertTo-Json -Depth 100) + "`n"

[System.IO.File]::WriteAllText($catalogPath, $catalog, $utf8NoBom)
[System.IO.File]::WriteAllText($reportPath, $reportJson, $utf8NoBom)

Write-Host "Compiled $($cases.Count) CaseSpec(s)."
Write-Host "Runtime catalog: $catalogPath"
Write-Host "Compatibility report: $reportPath"
