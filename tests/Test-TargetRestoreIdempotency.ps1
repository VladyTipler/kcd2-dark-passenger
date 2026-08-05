$ErrorActionPreference = 'Stop'

$runtimePath =
    'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua'
$runtimeText = Get-Content -Raw -LiteralPath $runtimePath
$snapshotPath =
    'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\dpcasesnapshot.lua'
$snapshotText = Get-Content -Raw -LiteralPath $snapshotPath

$restoreMatch = [regex]::Match(
    $runtimeText,
    '(?ms)^function DarkPassengerTarget\.RestoreExisting\(gameRegion\).*?^end$'
)
if (-not $restoreMatch.Success) {
    throw 'RestoreExisting function not found.'
}

$guardIndex = $restoreMatch.Value.IndexOf(
    'if IsRecoveredTargetBound(runtimeCandidate, runtimeEntity) then'
)
$bindIndex = $restoreMatch.Value.IndexOf(
    'BindRecoveredTarget(runtimeCandidate, runtimeEntity)'
)
if ($guardIndex -lt 0 -or $bindIndex -lt 0 -or $guardIndex -gt $bindIndex) {
    throw (
        'Already synchronized runtime target must return before ' +
        'BindRecoveredTarget side effects.'
    )
}

'PASS: repeated target restore is side-effect free.'

foreach ($requiredToken in @(
    'function DarkPassengerTarget.BeginRestoreCycle(reason)',
    'function DarkPassengerTarget.ReapplyRestoredTargetPresentation(',
    'ScheduleRestoredTargetPresentationRearm(',
    'RemoveAllBuffsByGuid(',
    'DarkPassengerTarget.TARGET_BUFF_GUID',
    'DarkPassengerCaseLifecycle.PrepareCaseGeneration('
)) {
    if (-not $runtimeText.Contains($requiredToken)) {
        throw "Restored target presentation contract missing: $requiredToken"
    }
}

if (-not (
    ([regex]::Matches(
        $runtimeText,
        'DarkPassengerTarget\.BeginRestoreCycle\("player_(reload|init)"\)'
    )).Count -eq 2
)) {
    throw 'Every save-load lifecycle must arm exactly one target presentation rearm.'
}

'PASS: save restore rearms target and case presentation after graph load.'

if (-not (
    $snapshotText.Contains('function DarkPassengerCaseSnapshot.MigrateLegacyState') -and
    $snapshotText.Contains('state.targetSlot') -and
    $snapshotText.Contains('state.variantCode = 0') -and
    $snapshotText.Contains('they are never replaced during migration')
)) {
    throw 'Legacy 1001/2001 snapshot migration must preserve its target slot.'
}

'PASS: legacy case migration preserves the original target slot.'
