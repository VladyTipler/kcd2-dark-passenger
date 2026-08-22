$ErrorActionPreference = 'Stop'

$runtimePath =
    'H:\KCD2Mod\DarkPassenger\src\Data\Scripts\mods\darkpassengertest.lua'
$runtimeText = Get-Content -Raw -LiteralPath $runtimePath

foreach ($requiredText in @(
    'QUEST_SELECTION_SCHEMA_KEY',
    'QUEST_SELECTION_SCHEMA_VERSION',
    'ScheduleQuestSelectionMigration',
    'ReapplyTargetBuffForQuestMigration',
    'quest selection migration complete'
)) {
    if (-not $runtimeText.Contains($requiredText)) {
        throw "Legacy quest selection migration lacks '$requiredText'."
    }
}

foreach ($requiredPattern in @(
    'RemoveAllBuffsByGuid\(\s*DarkPassengerTarget\.TARGET_BUFF_GUID',
    'entity\.soul:AddBuff\(\s*DarkPassengerTarget\.TARGET_BUFF_GUID'
)) {
    if ($runtimeText -notmatch $requiredPattern) {
        throw "Legacy quest selection migration lacks '$requiredPattern'."
    }
}

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
$migrationIndex = $restoreMatch.Value.IndexOf(
    'ScheduleQuestSelectionMigration('
)
$returnIndex = $restoreMatch.Value.IndexOf('return true', $guardIndex)
if (
    $guardIndex -lt 0 -or
    $migrationIndex -lt $guardIndex -or
    $returnIndex -lt $migrationIndex
) {
    throw 'Synchronized legacy targets must schedule migration before returning.'
}

$selectMatch = [regex]::Match(
    $runtimeText,
    '(?ms)^function DarkPassengerTarget\.Select\(gameRegion, settlement\).*?^end$'
)
if (
    -not $selectMatch.Success -or
    -not $selectMatch.Value.Contains('MarkQuestSelectionSchemaCurrent()')
) {
    throw 'New target selections must opt out of legacy migration.'
}

'PASS: legacy target selection is re-signalled exactly once.'
