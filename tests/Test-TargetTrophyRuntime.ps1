$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$trophyPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dptrophy.lua'
$targetPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'

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

$trophy = Read-OptionalText $trophyPath
$target = Read-OptionalText $targetPath

Add-Result (Test-Path -LiteralPath $trophyPath -PathType Leaf) `
    'target trophy runtime exists'
foreach ($export in @(
    'Transition',
    'OnTargetDeath',
    'Restore',
    'Poll',
    'GetState',
    'CanBuryCorpse',
    'RunSelfTest'
)) {
    Add-Result ($trophy.Contains("function DarkPassengerTrophy.$export")) `
        "target trophy runtime exports $export"
}
foreach ($token in @(
    'pending',
    'placed',
    'collected',
    'dp_trophy_generation',
    'dp_trophy_variant_code',
    'inventory:FindItem(',
    'corpse.inventory:CreateItem(',
    'PlayerInventoryHas(',
    'DarkPassengerCaseSnapshot.Get(',
    'already_collected',
    'already_placed',
    'streaming_deferred'
)) {
    Add-Result ($trophy.Contains($token)) `
        "target trophy lifecycle contains $token"
}
Add-Result (
    -not $trophy.Contains('DarkPassengerQuestItemPlacement.Request(')
) 'ordinary trophy bypasses the native quest-item placement bridge'
Add-Result (
    $trophy.Contains('if state.status == STATUS_PLACED then') -and
    $trophy.Contains('return false, "already_placed"')
) 'placed state never creates a second trophy when inventories are unavailable'
Add-Result (
    $trophy.Contains('PlayerInventoryCount(trophy.item_guid) > state.playerBaseline') -and
    $trophy.Contains('InventoryHas(corpse.inventory, trophy.item_guid)')
) 'restore distinguishes a newly collected shared feather from old trophies'
Add-Result (
    $trophy.Contains('candidate.entityName') -and
    $trophy.Contains(
        'ResolveSnapshot(state ~= nil and state.generation or nil)'
    )
) 'corpse resolution falls back to the immutable case snapshot after streaming'
Add-Result (
    -not $trophy.Contains('WriteScalar(KEYS.corpseName') -and
    -not $trophy.Contains('corpseName = "dp_trophy_corpse_name"')
) 'trophy persistence writes only numeric values accepted by Variables.SetGlobal'
Add-Result (
    $trophy.Contains('local function ResolveExpectedCorpseName(state)') -and
    $trophy.Contains('local expectedCorpseName = ResolveExpectedCorpseName(state)') -and
    $trophy.Contains('return true, "target_identity_unavailable"') -and
    -not $trophy.Contains('return false, "target_identity_unavailable"')
) 'burial only blocks a positively identified target and fails open when target identity is unavailable'
Add-Result (
    $trophy.Contains('Script.SetTimerForFunction(') -and
    $trophy.Contains('DarkPassengerTrophy.Poll')
) 'placed trophy keeps a save-safe collection poll'
$pollMatch = [regex]::Match(
    $trophy,
    '(?ms)^function DarkPassengerTrophy\.Poll\(payload\).*?^end$'
)
Add-Result (
    $pollMatch.Success -and
    $pollMatch.Value.Contains('if reason == "stale_generation" then') -and
    $pollMatch.Value.IndexOf('if reason == "stale_generation" then') -lt
        $pollMatch.Value.IndexOf('Schedule(state)')
) 'stale trophy generation terminates polling instead of rescheduling'
$restoreMatch = [regex]::Match(
    $trophy,
    '(?ms)^function DarkPassengerTrophy\.Restore\(\).*?^end$'
)
Add-Result (
    $restoreMatch.Success -and
    $restoreMatch.Value.Contains('if reason == "stale_generation" then') -and
    $restoreMatch.Value.Contains(
        'DarkPassengerTrophy.timerSerial = DarkPassengerTrophy.timerSerial + 1'
    ) -and
    $restoreMatch.Value.IndexOf('if reason == "stale_generation" then') -lt
        $restoreMatch.Value.IndexOf('Schedule(state)')
) 'restore invalidates stale trophy timers without starting a new chain'
Add-Result (
    $target.Contains(
        'Script.ReloadScript("Scripts/mods/dptrophy.lua")'
    )
) 'target runtime loads trophy module'

$deathMatch = [regex]::Match(
    $target,
    '(?ms)^function DarkPassengerTarget\.OnTargetDeath' +
        '\(gameRegion, settlement, slot\).*?^end$'
)
Add-Result (
    $deathMatch.Success -and
    $deathMatch.Value.Contains('DarkPassengerTrophy.OnTargetDeath(') -and
    $deathMatch.Value.IndexOf('DarkPassengerTrophy.OnTargetDeath(') -lt
        $deathMatch.Value.IndexOf('DarkPassengerInvestigation.OnTargetDeath(') -and
    $deathMatch.Value.IndexOf('DarkPassengerTrophy.OnTargetDeath(') -lt
        $deathMatch.Value.IndexOf('DarkPassengerTarget.Clear()')
) 'target death places trophy on the resolved corpse before binding clear'
Add-Result (
    $deathMatch.Success -and
    -not $deathMatch.Value.Contains('return trophy')
) 'trophy placement cannot replace investigation or aftermath result semantics'
Add-Result (
    $target.Contains('DarkPassengerTrophy.Restore()')
) 'runtime restore resumes trophy collection reconciliation'
Add-Result (
    $trophy.Contains('function DarkPassengerTrophy.CanBuryCorpse(corpse)') -and
    $trophy.Contains('return false, "trophy_not_collected"') -and
    $trophy.Contains('nextState.status == STATUS_COLLECTED')
) 'trophy lifecycle blocks target burial until collection is reconciled'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
