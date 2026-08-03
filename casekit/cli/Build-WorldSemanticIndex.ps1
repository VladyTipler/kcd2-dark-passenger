param(
    [Parameter(Mandatory)][string]$RawWorldPath,
    [string]$VictimCatalogPath,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$caseKitRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $caseKitRoot 'CaseKit.psd1'
Import-Module $manifestPath -Force

$index = New-CaseKitWorldIndex `
    -RawWorldPath $RawWorldPath `
    -VictimCatalogPath $VictimCatalogPath
$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
[System.IO.File]::WriteAllText(
    $OutputPath,
    (($index | ConvertTo-Json -Depth 12) + "`n"),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host (
    "Built semantic world index with $(@($index.entities).Count) entities " +
    "across $(@($index.regions).Count) regions."
)
