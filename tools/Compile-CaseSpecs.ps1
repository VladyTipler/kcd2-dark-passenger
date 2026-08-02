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
$nativeManifestPath = Join-Path $BuildRoot `
    'generated\cases\native-wiring.json'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($parent in @(
    (Split-Path -Parent $catalogPath),
    (Split-Path -Parent $reportPath),
    (Split-Path -Parent $nativeManifestPath)
)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$catalog = ConvertTo-DpCaseCatalogLua `
    -CaseSpecs $cases `
    -Bindings $bindings
$report = ConvertTo-DpCaseCompatibilityReport -CaseSpecs $cases
$reportJson = ($report | ConvertTo-Json -Depth 100) + "`n"
$nativeRegions = [System.Collections.Generic.List[object]]::new()
foreach ($case in $cases) {
    $binding = @($bindings.settlements | Where-Object {
        [string]$_.region -eq [string]$case.constraints.region -and
        [string]$_.settlement -eq [string]$case.constraints.settlement
    })[0]
    $wiring = ConvertTo-DpNativeRegionWiring `
        -CaseSpec $case `
        -Binding $binding
    $nativeRegions.Add($wiring)

    $dialogRoot = Join-Path $BuildRoot (
        'mod\Data\Quests\darkpassengertest\' +
        [string]$wiring.region + '\' + [string]$wiring.dialogFolder
    )
    New-Item -ItemType Directory -Path $dialogRoot -Force | Out-Null
    foreach ($dialogue in @($wiring.dialogues)) {
        [System.IO.File]::WriteAllText(
            (Join-Path $dialogRoot ([string]$dialogue.fileName)),
            [string]$dialogue.xml,
            $utf8NoBom
        )
    }
}
$nativeManifest = [ordered]@{
    schemaVersion = 1
    regions = @($nativeRegions | ForEach-Object {
        [ordered]@{
            caseId = $_.caseId
            region = $_.region
            settlement = $_.settlement
            questName = $_.questName
            dialogFolder = $_.dialogFolder
            dialogDefinitions = $_.dialogDefinitions
            rumorNodes = $_.rumorNodes
            witnessNodes = $_.witnessNodes
            evidenceWitnessEdge = $_.evidenceWitnessEdge
            witnessObjectiveNodes = $_.witnessObjectiveNodes
            witnessType = $_.witnessType
            witnessObjective = $_.witnessObjective
            dialogueFiles = @($_.dialogues.fileName)
        }
    })
}
$nativeManifestJson = ($nativeManifest | ConvertTo-Json -Depth 100) + "`n"

[System.IO.File]::WriteAllText($catalogPath, $catalog, $utf8NoBom)
[System.IO.File]::WriteAllText($reportPath, $reportJson, $utf8NoBom)
[System.IO.File]::WriteAllText(
    $nativeManifestPath,
    $nativeManifestJson,
    $utf8NoBom
)

Write-Host "Compiled $($cases.Count) CaseSpec(s)."
Write-Host "Runtime catalog: $catalogPath"
Write-Host "Compatibility report: $reportPath"
Write-Host "Native wiring: $nativeManifestPath"
