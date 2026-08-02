$ErrorActionPreference = 'Stop'

$runtimePath =
    'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua'
$runtimeText = Get-Content -Raw -LiteralPath $runtimePath

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
