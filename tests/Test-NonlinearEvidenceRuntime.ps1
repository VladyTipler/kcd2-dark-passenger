param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot 'src\Data\Scripts\mods'
$registryPath = Join-Path $scriptRoot 'dpevidenceregistry.lua'
$investigationPath = Join-Path $scriptRoot 'dpinvestigation.lua'
$initPath = Join-Path $scriptRoot 'darkpassengertest.lua'
$snapshotPath = Join-Path $scriptRoot 'dpcasesnapshot.lua'
$seederPath = Join-Path $scriptRoot 'dpevidenceseeder.lua'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Read-OptionalText([string]$LiteralPath) {
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return '' }
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

$registry = Read-OptionalText $registryPath
$investigation = Read-OptionalText $investigationPath
$init = Read-OptionalText $initPath
$snapshot = Read-OptionalText $snapshotPath
$seeder = Read-OptionalText $seederPath

Add-Result (Test-Path -LiteralPath $registryPath -PathType Leaf) `
    'central evidence registry exists'
foreach ($export in @(
    'Transition',
    'MarkPlaced',
    'Discover',
    'GetCaseState',
    'Restore',
    'RunSelfTest'
)) {
    Add-Result (
        $registry.Contains(
            "function DarkPassengerEvidenceRegistry.$export"
        )
    ) "evidence registry exports $export"
}

foreach ($status in 'pending', 'placed', 'discovered') {
    Add-Result ($registry.Contains('"' + $status + '"')) `
        "evidence registry models $status state"
}
Add-Result (
    $registry.Contains('stale_generation') -and
    $registry.Contains('already_discovered') -and
    $registry.Contains('unknown_evidence')
) 'registry rejects stale, duplicate, and unknown discoveries'
Add-Result (
    $registry.Contains('CalculateConfidence') -and
    $registry.Contains('claim_id') -and
    $registry.Contains('claim_cap')
) 'registry derives confidence from discovered evidence and claim caps'
Add-Result (
    $registry.Contains('order rumor-ledger-witness') -and
    $registry.Contains('order witness-rumor-ledger') -and
    $registry.Contains('same discovered set') -and
    $registry.Contains('claim cap')
) 'registry self-test covers permutations and claim caps'

foreach ($key in @(
    'dp_evidence_registry_schema_version',
    'dp_evidence_registry_generation',
    'dp_evidence_registry_case_code',
    'dp_evidence_registry_status_'
)) {
    Add-Result ($registry.Contains($key)) "registry persists $key"
}
Add-Result (
    $registry.IndexOf('PersistState(nextState)') -ge 0 -and
    $registry.IndexOf('PersistState(nextState)') -lt
        $registry.IndexOf('ReconcileEvidence(')
) 'discovery persists before investigation reconciliation'

Add-Result (
    $investigation.Contains(
        'function DarkPassengerInvestigation.ReconcileEvidence'
    ) -and
    $investigation.Contains('eventType == "reconcile"') -and
    $investigation.Contains('non_monotonic_confidence') -and
    $investigation.Contains('evidence_unchanged')
) 'investigation exposes monotonic idempotent reconciliation'
Add-Result (
    $investigation.Contains('reconcile exact total') -and
    $investigation.Contains('reconcile idempotent') -and
    $investigation.Contains('reconcile rejects regression') -and
    $investigation.Contains('reconcile reveal once')
) 'investigation self-test covers reconciliation invariants'

$catalogIndex = $init.IndexOf(
    'Script.ReloadScript("Scripts/mods/generated/dp_case_catalog.lua")'
)
$investigationIndex = $init.IndexOf(
    'Script.ReloadScript("Scripts/mods/dpinvestigation.lua")'
)
$registryIndex = $init.IndexOf(
    'Script.ReloadScript("Scripts/mods/dpevidenceregistry.lua")'
)
$rumorIndex = $init.IndexOf(
    'Script.ReloadScript("Scripts/mods/dpevidence.lua")'
)
Add-Result (
    $catalogIndex -ge 0 -and
    $investigationIndex -ge 0 -and
    $registryIndex -gt $catalogIndex -and
    $registryIndex -gt $investigationIndex -and
    $rumorIndex -gt $registryIndex
) 'runtime loads catalog and investigation before registry and consumers'
Add-Result (
    $snapshot.Contains('targetSlot') -and
    $snapshot.Contains('caseCode') -and
    $snapshot.Contains('openerCode') -and
    $snapshot.Contains('bindings = caseTemplate.bindings')
) 'case snapshot restores the finite selected package without reroll'
Add-Result (
    $seeder.Contains('DarkPassengerCaseSnapshot.Restore(') -and
    $seeder.Contains('DarkPassengerEvidenceRegistry.MarkPlaced(') -and
    $seeder.Contains('placement == "case_start"')
) 'seeder projects snapshot case-start evidence into the registry'

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler -PathType Leaf) `
        'LuaCompiler is available'
    foreach ($path in @(
        $registryPath,
        $investigationPath,
        $snapshotPath,
        $seederPath,
        $initPath
    )) {
        if ((Test-Path -LiteralPath $compiler) -and
            (Test-Path -LiteralPath $path)) {
            & $compiler -p $path *> $null
            Add-Result ($LASTEXITCODE -eq 0) `
                "LuaCompiler accepts $(Split-Path -Leaf $path)"
        }
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
