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

$persistedLookupIndex = $restoreMatch.Value.IndexOf(
    'local persistedCandidate ='
)
$runtimeLookupIndex = $restoreMatch.Value.IndexOf(
    'local runtimeCandidate ='
)
$persistedBindIndex = $restoreMatch.Value.IndexOf(
    'BindRecoveredTarget(persistedCandidate, persistedEntity)'
)
$persistedGuardIndex = $restoreMatch.Value.IndexOf(
    'if IsRecoveredTargetBound(persistedCandidate, persistedEntity) then'
)
if ($persistedLookupIndex -lt 0 -or $runtimeLookupIndex -lt 0 -or
    $persistedBindIndex -lt 0 -or $persistedGuardIndex -lt 0 -or
    $persistedLookupIndex -gt $runtimeLookupIndex -or
    $persistedBindIndex -gt $runtimeLookupIndex -or
    $persistedGuardIndex -gt $persistedBindIndex) {
    throw (
        'Save restore must prefer the persisted slot, but an already bound ' +
        'persisted target must return before BindRecoveredTarget side effects.'
    )
}

'PASS: persisted target identity wins and repeated restore is side-effect free.'

$guardIndex = $restoreMatch.Value.IndexOf(
    'if IsRecoveredTargetBound(runtimeCandidate, runtimeEntity) then'
)
$buffGuardIndex = $restoreMatch.Value.IndexOf(
    'if HasTargetBuff(runtimeEntity) then'
)
$bindIndex = $restoreMatch.Value.IndexOf(
    'BindRecoveredTarget(runtimeCandidate, runtimeEntity)'
)
if ($guardIndex -lt 0 -or $buffGuardIndex -lt 0 -or
    $bindIndex -lt 0 -or $guardIndex -gt $buffGuardIndex -or
    $guardIndex -gt $bindIndex) {
    throw (
        'Already synchronized runtime target must return before transient ' +
        'buff checks and BindRecoveredTarget side effects.'
    )
}

'PASS: repeated target restore is side-effect free.'

$boundMatch = [regex]::Match(
    $runtimeText,
    '(?ms)^local function IsRecoveredTargetBound\(candidate, entity\).*?^end$'
)
if (-not $boundMatch.Success) {
    throw 'IsRecoveredTargetBound function not found.'
}
if (-not (
    $runtimeText.Contains('local function EntityIdsEqual(left, right)') -and
    $boundMatch.Value.Contains(
        'EntityIdsEqual(DarkPassengerTarget.targetEntityId, entity.id)'
    ) -and
    $boundMatch.Value.Contains(
        'EntityIdsEqual(investigationEntity.id, entity.id)'
    ) -and
    -not $boundMatch.Value.Contains(
        'DarkPassengerTarget.targetEntityId == entity.id'
    ) -and
    -not $boundMatch.Value.Contains(
        'DarkPassengerInvestigation.entity == entity'
    )
)) {
    throw (
        'Every recovered-target identity check must compare stable entity IDs, ' +
        'not transient Lua wrappers.'
    )
}

'PASS: recovered target identity uses stable entity IDs.'

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
