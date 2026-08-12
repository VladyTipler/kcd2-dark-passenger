$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScriptPath = Join-Path $repoRoot 'tools\Build-Mod.ps1'
$compilerScriptPath = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$backendPath = Join-Path $repoRoot `
    'casekit\adapters\kcd2\CaseKit.Kcd2Backend.psm1'
$caseRuntimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcasecontent.lua'
$snapshotPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcasesnapshot.lua'
$targetRuntimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$variantCatalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'
$compatibilityReportPath = Join-Path $repoRoot `
    'build\generated\casekit\compiler-input\compatibility-report.json'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Read-OptionalText {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return '' }
    return [System.IO.File]::ReadAllText($LiteralPath)
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

$buildScript = Read-OptionalText $buildScriptPath
$compilerScript = Read-OptionalText $compilerScriptPath
$backend = Read-OptionalText $backendPath
$caseRuntime = Read-OptionalText $caseRuntimePath
$snapshot = Read-OptionalText $snapshotPath
$targetRuntime = Read-OptionalText $targetRuntimePath
$variantCatalog = Read-OptionalText $variantCatalogPath
$compatibilityReport = if (
    Test-Path -LiteralPath $compatibilityReportPath -PathType Leaf
) {
    Get-Content -Raw -LiteralPath $compatibilityReportPath |
        ConvertFrom-Json -Depth 100
} else { $null }

Add-Result (
    $buildScript -match '-MaxVariantsPerCombination\s+([2-9]|[1-9][0-9]+)'
) 'production build keeps more than one finite binding per story and settlement'
Add-Result (
    $backend.Contains('Sort-Object rank, variantId') -and
    $backend.Contains('$variants[0]')
) 'native parity backend deterministically chooses rank-one presentation assets'
Add-Result (
    $compilerScript.Contains('compiledDefinitionsFile') -and
    $compilerScript.Contains('dp_case_variant_catalog.lua')
) 'native compiler emits a dedicated runtime variant catalog'
Add-Result (Test-Path -LiteralPath $variantCatalogPath -PathType Leaf) `
    'generated runtime variant catalog exists'
Add-Result (
    $null -ne $compatibilityReport -and
    @(
        $compatibilityReport.accepted |
            Where-Object {
                $_.region -eq 'trosecko' -and
                $_.settlement -eq 'zelejov'
            } |
            Group-Object storyId |
            Where-Object {
                @($_.Group.bindings.target.entityName |
                    Sort-Object -Unique).Count -lt 8
            }
    ).Count -eq 0
) 'every Zhelejov StoryPack compiles eight distinct target actors'

foreach ($token in @(
    'DarkPassengerCaseVariantCatalog',
    'DarkPassengerCaseVariantCatalogOrder',
    'DarkPassengerCaseVariantCatalogByCode',
    'variant_id =',
    'variant_code =',
    'binding_code =',
    'native_ready = true',
    'anti_repeat_key =',
    'target_slot =',
    'bindings =',
    'dialogue_role =',
    'scenes ='
)) {
    Add-Result ($variantCatalog.Contains($token)) `
        "variant catalog contains $token"
}
Add-Result (
    $caseRuntime.Contains(
        'result.dialogueRole = semantic.dialogue_role'
    )
) 'runtime overlays the selected settlement dialogue role'

foreach ($token in @(
    'SCHEMA_VERSION = 3',
    'dp_case_content_variant_code',
    'dp_case_content_previous_variant_code',
    'function DarkPassengerCaseContent.IsSettlementSupported',
    'function DarkPassengerCaseContent.SelectVariant',
    'function DarkPassengerCaseContent.FindCompatibleVariant',
    'function DarkPassengerCaseContent.PrepareVariant',
    'native_ready',
    'anti_repeat_key',
    'candidateBySlot',
    'reason = "restored"'
)) {
    Add-Result ($caseRuntime.Contains($token)) `
        "case selector contains $token"
}
Add-Result (
    $caseRuntime.Contains(
        'firstVariant = DarkPassengerCaseContent.SelectVariant('
    ) -and
    $caseRuntime.Contains(
        'secondVariant = DarkPassengerCaseContent.SelectVariant('
    ) -and
    $caseRuntime.Contains('"variant selection"') -and
    $caseRuntime.Contains('"variant anti-repeat"')
) 'runtime self-test exercises finite selection and target anti-repeat'
Add-Result (
    $caseRuntime.Contains(
        'DarkPassengerCaseContent.FindCompatibleVariant(current, context, nil)'
    ) -and
    $caseRuntime.Contains('PersistState(migratedState)') -and
    $caseRuntime.Contains('"migrated_variant"') -and
    $caseRuntime.Contains('"variant migration"')
) 'missing generated variants migrate within the same case and target'

$selectMatch = [regex]::Match(
    $targetRuntime,
    '(?ms)^function DarkPassengerTarget\.Select\(gameRegion, settlement\).*?^end$'
)
Add-Result (
    $selectMatch.Success -and
    $selectMatch.Value.Contains('DarkPassengerCaseContent.PrepareVariant(') -and
    $selectMatch.Value.IndexOf('DarkPassengerCaseContent.PrepareVariant(') -lt
        $selectMatch.Value.IndexOf(':AddBuff(')
) 'variant and concrete bindings are persisted before target presentation'
Add-Result (
    $targetRuntime.Contains('IsSettlementSupported(') -and
    $targetRuntime.Contains('IsLivingCandidate(') -and
    $targetRuntime.Contains('IsPolicyCandidate(')
) 'selection filters unsupported settlements and invalid live targets'

foreach ($token in @(
    'SCHEMA_VERSION = 2',
    'dp_case_snapshot_variant_code',
    'dp_case_snapshot_binding_code',
    'variantId =',
    'caseInstance =',
    'bindings =',
    'legacy_v1',
    'targetSlot'
)) {
    Add-Result ($snapshot.Contains($token)) `
        "case snapshot contains $token"
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
