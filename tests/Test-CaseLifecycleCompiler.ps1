$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$variantCatalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'

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

$compiler = [System.IO.File]::ReadAllText($compilerPath)
$catalog = if (Test-Path -LiteralPath $variantCatalogPath -PathType Leaf) {
    [System.IO.File]::ReadAllText($variantCatalogPath)
} else { '' }

Add-Result (
    $compiler.Contains('function Get-DpCaseCleanupManifest') -and
    $compiler.Contains('cleanup_manifest =')
) 'compiler owns a per-variant cleanup-manifest builder'

foreach ($token in @(
    'cleanup_manifest = {',
    'schema_version = 1',
    'evidence_codes = {',
    'availability_roles = {',
    'signal_buff_guids = {',
    'entity_contexts = {',
    'items = {',
    'scene_ids = {'
)) {
    Add-Result ($catalog.Contains($token)) "variant catalog contains $token"
}

Add-Result (
    $catalog.Contains('item_guid = "d5833fd4-f7bf-4957-86f5-d661db38bcf3"') -and
    $catalog.Contains('retention = "case"')
) 'Missing Traveler manifest owns removable ledger evidence'
Add-Result (
    $catalog.Contains('item_guid = "22f71f71-cc7c-0607-46b1-67e9925a3874"') -and
    $catalog.Contains('retention = "permanent"')
) 'variant manifest explicitly preserves the permanent trophy'

$nativeReadyCount = [regex]::Matches($catalog, 'native_ready = true').Count
$manifestCount = [regex]::Matches($catalog, 'cleanup_manifest = \{').Count
Add-Result (
    $nativeReadyCount -gt 0 -and $manifestCount -eq $nativeReadyCount
) 'every native-ready variant has exactly one cleanup manifest'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
