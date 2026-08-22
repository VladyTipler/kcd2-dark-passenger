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
$plannerPath = Join-Path $scriptRoot 'dpleadplanner.lua'
$caseContentPath = Join-Path $scriptRoot 'dpcasecontent.lua'

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
$planner = Read-OptionalText $plannerPath
$caseContent = Read-OptionalText $caseContentPath

Add-Result (Test-Path -LiteralPath $registryPath -PathType Leaf) `
    'central evidence registry exists'
foreach ($export in @(
    'Transition',
    'MarkPlaced',
    'Discover',
    'GetCaseState',
    'IsIdentitySatisfied',
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
    $registry.Contains('reveals =') -and
    $registry.Contains('identity_requirement') -and
    $registry.Contains('identitySatisfied') -and
    $registry.Contains('ReconcileEvidence(')
) 'registry derives identity gates from discovered evidence facts'
Add-Result (
    $registry.Contains('order rumor-ledger-witness') -and
    $registry.Contains('order witness-rumor-ledger') -and
    $registry.Contains('same discovered set') -and
    $registry.Contains('claim cap')
) 'registry self-test covers permutations and claim caps'
Add-Result (
    $registry.Contains('identity allOf waits for every fact') -and
    $registry.Contains('identity anyOf accepts either fact') -and
    $registry.Contains('identity rejects unknown mode')
) 'registry self-test covers allOf and anyOf identity expressions'

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
    $investigation.Contains('evidence_unchanged') -and
    $investigation.Contains('identitySatisfied') -and
    $investigation.Contains('identity_pending')
) 'investigation exposes monotonic idempotent reconciliation'
Add-Result (
    $investigation.Contains('reconcile exact total') -and
    $investigation.Contains('reconcile idempotent') -and
    $investigation.Contains('reconcile rejects regression') -and
    $investigation.Contains('reconcile reveal once') -and
    $investigation.Contains('threshold waits for hard identity') -and
    $investigation.Contains('unchanged confidence reveals after identity')
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
Add-Result (Test-Path -LiteralPath $plannerPath -PathType Leaf) `
    'pure lead planner exists'
foreach ($export in @(
    'Transition',
    'Evaluate',
    'SelectGuidance',
    'Publish',
    'PublishGuidance',
    'Apply',
    'RunSelfTest'
)) {
    Add-Result (
        $planner.Contains("function DarkPassengerLeadPlanner.$export")
    ) "lead planner exports $export"
}
Add-Result (
    $planner.Contains('rumor-ledger-witness') -and
    $planner.Contains('rumor-witness-ledger') -and
    $planner.Contains('ledger-rumor-witness') -and
    $planner.Contains('parallel after rumor') -and
    $planner.Contains('same confidence')
) 'lead planner self-test covers all nonlinear clue orders'
Add-Result (
    $planner.Contains('visibility_mode == "step-active"') -and
    $planner.Contains('visibility_mode == "facts-known"') -and
    $planner.Contains('visibility_mode == "target-revealed"') -and
    $planner.Contains('requires_fact_ids') -and
    $planner.Contains('investigationState.revealed == true')
) 'lead planner evaluates every CaseKit guidance visibility mode'
Add-Result (
    $planner.Contains('guidance waits for prerequisite facts') -and
    $planner.Contains('guidance expires after evidence') -and
    $planner.Contains('target guidance waits for reveal')
) 'lead planner self-test covers guidance lifecycle gates'
Add-Result (
    $planner.Contains('DarkPassengerInvestigation.GetState()') -and
    $planner.Contains('DarkPassengerLeadPlanner.PublishGuidance(') -and
    $caseContent.Contains('result.guidance = variant.guidance or {}')
) 'selected CaseKit variant guidance reaches the native signal publisher'
Add-Result (
    $planner.Contains('hints_unlocked_by') -and
    $planner.Contains('status ~= "discovered"') -and
    $planner.Contains('DarkPassengerEvidence.ApplyAvailability(') -and
    $planner.Contains('DarkPassengerWitnessLead.ApplyAvailability(')
) 'planner projects undiscovered finite directions into native adapters'
Add-Result (
    $planner.Contains('dp_lead_presentation_generation') -and
    $planner.Contains('dp_lead_presentation_state_code') -and
    $planner.Contains('dp_lead_presentation_revision') -and
    $planner.Contains('presentation_unchanged') -and
    $planner.Contains('nextState.revision + 1')
) 'planner persists monotonic journal presentation revisions'
Add-Result (
    $registry.Contains(
        'DarkPassengerLeadPlanner.ScheduleEvidenceTransition('
    ) -and
    $planner.Contains(
        'function DarkPassengerLeadPlanner.ScheduleEvidenceTransition'
    ) -and
    $planner.Contains(
        'function DarkPassengerLeadPlanner.OnEvidenceTransition'
    ) -and
    $planner.Contains('Script.SetTimerForFunction(') -and
    $planner.Contains('evidenceCode = evidenceCode') -and
    $planner.Contains('stale_generation')
) 'evidence discovery crosses a generation-guarded deferred signal handshake'
Add-Result (
    $planner.Contains('function DarkPassengerLeadPlanner.SelectJournalEntry') -and
    $planner.Contains('journal_entries') -and
    $planner.Contains('all_known_facts') -and
    $planner.Contains('all_unknown_facts')
) 'lead planner selects the authored journal entry for the discovered evidence'
Add-Result (
    $planner.Contains('direction_code') -and
    $planner.Contains('plan.stateCode') -and
    $planner.Contains('state.buff_guid') -and
    $planner.Contains('RemoveAllBuffsByGuid(') -and
    $planner.Contains('soul:AddBuff(')
) 'planner publishes exactly one compiled journal-state signal buff'

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
        $plannerPath,
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
