param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dptimedareaaction.lua'
$obsoleteRuntimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpoverheardevidence.lua'
$interactionPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpinteractions.lua'
$bridgePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$caseContentPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcasecontent.lua'
$storyPath = Join-Path $repoRoot `
    'content\stories\missing-traveler\threads.json'
$storyRuPath = Join-Path $repoRoot `
    'content\stories\missing-traveler\localization\ru.json'
$storyEnPath = Join-Path $repoRoot `
    'content\stories\missing-traveler\localization\en.json'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Add-Result([bool]$Condition, [string]$Label) {
    $script:checks++
    if ($Condition) {
        Write-Host "PASS: $Label"
        return
    }
    $script:failures.Add($Label)
    Write-Host "FAIL: $Label"
}

Add-Result (Test-Path -LiteralPath $runtimePath -PathType Leaf) `
    'timed-area runtime exists'
Add-Result (-not (Test-Path -LiteralPath $obsoleteRuntimePath)) `
    'obsolete NPC-pair overheard runtime is removed'

$runtime = if (Test-Path -LiteralPath $runtimePath) {
    [System.IO.File]::ReadAllText($runtimePath)
} else { '' }
$interaction = [System.IO.File]::ReadAllText($interactionPath)
$bridge = [System.IO.File]::ReadAllText($bridgePath)
$caseContent = [System.IO.File]::ReadAllText($caseContentPath)
$story = [System.IO.File]::ReadAllText($storyPath)
$storyRu = [System.IO.File]::ReadAllText($storyRuPath)
$storyEn = [System.IO.File]::ReadAllText($storyEnPath)

foreach ($export in @(
    'IsWithinWorkingHours',
    'GetActiveAction',
    'CanActivate',
    'OnActionEvent',
    'Start',
    'OnSkipTimeStep',
    'OnFailsafe',
    'Finish'
)) {
    Add-Result (
        $runtime.Contains("function DarkPassengerTimedAreaAction.$export")
    ) "timed-area runtime exports $export"
}

Add-Result (
    $story.Contains('"evidenceModule": "timed-area-listening"') -and
    $story.Contains('"mode": "timed-area-action"') -and
    $story.Contains('"availableFromHour": 10') -and
    $story.Contains('"availableUntilHour": 22') -and
    $story.Contains('"durationHours": 2')
) 'StoryPack owns the 10-22 two-hour area action contract'

Add-Result (
    $runtime.Contains('HasScriptContext(PlayerEntity(), action.area_context)') -and
    $runtime.Contains('activation ~= "release"') -and
    $runtime.Contains('actionName ~= "grab_body" and') -and
    $runtime.Contains('actionName ~= "butcher"')
) 'both native F actions require a positive compiled area context'
Add-Result (
    $runtime.Contains('InstallRawActionHook') -and
    $runtime.Contains('Player.OnAction') -and
    $runtime.Contains('_hookOwner') -and
    $runtime.Contains('owner.rawActionWrapper') -and
    $runtime.Contains('pcall(') -and
    $runtime.Contains('raw action failed:') -and
    $runtime.Contains('DarkPassengerTimedAreaAction.OnRawActionEvent(') -and
    -not $runtime.Contains('ActionMapManager.LoadFromXML') -and
    -not $runtime.Contains('dpTimedAreaActionProfile.xml')
) 'runtime observes F before vanilla GameRules filtering without action-map reload'
Add-Result (
    $runtime.Contains('InstallUsableTracker') -and
    $runtime.Contains('_currentUsableEntityId') -and
    $runtime.Contains('vanilla_f_action_available') -and
    $runtime.Contains('function DarkPassengerTimedAreaAction.PublishNativeAction') -and
    $runtime.Contains('Action():hint("@" .. action.prompt_key)') -and
    $runtime.Contains(':action("grab_body")') -and
    $runtime.Contains('AddInteractorAction(actions, false, nativeAction)') -and
    $runtime.Contains('actor.player:AddLuaActions(actions)') -and
    -not $runtime.Contains('actor.player:AddLuaActions({})') -and
    -not $runtime.Contains('Game.SendInfoText')
) 'native lower-right action never clears the shared player action list'
Add-Result (
    -not $runtime.Contains('_nativeActionSignature == signature')
) 'native action is republished after the HUD rebuilds contextual actions'
Add-Result (
    $runtime.Contains('function DarkPassengerTimedAreaAction.InstallHudActionHook') -and
    $runtime.Contains('function DarkPassengerTimedAreaAction.AugmentNativeActions') -and
    $runtime.Contains('player.AddLuaActions = wrapper') -and
    $runtime.Contains('DarkPassengerTimedAreaAction._vanillaFActionVisible') -and
    $runtime.Contains('entry.action == "grab_body"') -and
    $runtime.Contains('entry.action == "butcher"')
) 'native HUD rebuilds retain listening unless vanilla already owns F'
$canActivateBlock = [regex]::Match(
    $runtime,
    '(?s)function DarkPassengerTimedAreaAction\.CanActivate\(action\)(.*?)\nend'
).Groups[1].Value
Add-Result (
    -not $canActivateBlock.Contains('_currentUsableEntityId') -and
    $canActivateBlock.Contains('_vanillaFActionVisible')
) 'an unrelated usable target no longer hides the area action'
$usableTrackerBlock = [regex]::Match(
    $runtime,
    '(?s)function DarkPassengerTimedAreaAction\.HandleNewUsable\((.*?)\nend'
).Groups[1].Value
$clearNativeBlock = [regex]::Match(
    $runtime,
    '(?s)function DarkPassengerTimedAreaAction\.ClearNativeAction\(\)(.*?)\nend'
).Groups[1].Value
$publishNativeBlock = [regex]::Match(
    $runtime,
    '(?s)function DarkPassengerTimedAreaAction\.PublishNativeAction\(action\)(.*?)\nend'
).Groups[1].Value
Add-Result (
    $usableTrackerBlock.IndexOf('_currentUsableEntityId =') -lt
        $usableTrackerBlock.IndexOf('local result = original(') -and
    -not $usableTrackerBlock.Contains('_nativeActionPublished = false')
) 'usable tracker establishes the new target before vanilla rebuilds the HUD'
Add-Result (
    -not $runtime.Contains('_usableHookedRules') -and
    $runtime.Contains('function DarkPassengerTimedAreaAction.HandleNewUsable') -and
    $runtime.Contains('owner.usableWrapper') -and
    $runtime.Contains(
        'g_gameRules.OnNewUsable == owner.usableWrapper'
    ) -and
    $runtime.Contains(
        'DarkPassengerTimedAreaAction.HandleNewUsable('
    )
) 'usable tracker is a single hot-reload-safe trampoline'
Add-Result (
    $runtime.Contains('function DarkPassengerTimedAreaAction.RebuildCurrentVanillaActions') -and
    $clearNativeBlock.Contains('RebuildCurrentVanillaActions()') -and
    $publishNativeBlock.Contains('RebuildCurrentVanillaActions()') -and
    $clearNativeBlock.Contains(
        'if DarkPassengerTimedAreaAction._currentUsableEntityId ~= nil then'
    ) -and
    -not $publishNativeBlock.Contains(
        'if DarkPassengerTimedAreaAction._currentUsableEntityId ~= nil then'
    )
) 'zone exit only rebuilds an existing vanilla usable HUD'
Add-Result (
    $runtime.Contains(
        'DarkPassengerTimedAreaAction._nativeActionPublished = true'
    ) -and
    $runtime.Contains(
        'DarkPassengerTimedAreaAction._nativeActionPublished = false'
    )
) 'HUD merge tracks whether the listening action is actually visible'
Add-Result (
    $storyRu.Contains('"action.listen.prompt": "Прислушаться"') -and
    $storyEn.Contains('"action.listen.prompt": "Listen"') -and
    -not $storyRu.Contains('"action.listen.prompt": "[F]') -and
    -not $storyEn.Contains('"action.listen.prompt": "[F]')
) 'native action uses a short label and leaves key rendering to the HUD'
Add-Result (
    $runtime.Contains('Calendar.SetWorldTime(') -and
    $runtime.Contains('durationHours * 60 * 60') -and
    $runtime.Contains('"SkipTime", 1, "AddDialog"')
) 'accepted action uses the proven skip-time UI and authored duration'
Add-Result (
    $runtime.Contains('UIAction.HideElement("SkipTime", 1)') -and
    $runtime.Contains('UIAction.HideElement("Overlay", 1)') -and
    $runtime.Contains('UIAction.ShowElement("hud", 0)')
) 'skip-time presentation restores the proven vanilla HUD state'
Add-Result (
    $runtime.Contains('DarkPassengerTimedAreaAction.FAILSAFE_MS') -and
    $runtime.Contains('"DarkPassengerTimedAreaAction.OnFailsafe"')
) 'skip-time action has a presentation and save-lock failsafe'
Add-Result (
    $runtime.Contains('DarkPassengerEvidenceRegistry.Discover(') -and
    $runtime.Contains('source = "timed_area_action"') -and
    $runtime.Contains('already_discovered')
) 'completion awards the existing evidence exactly once'
Add-Result (
    $runtime.Contains('available_from_hour') -and
    $runtime.Contains('available_until_hour') -and
    $runtime.Contains('unavailable_key')
) 'working-hours denial is authored and does not advance the case'
Add-Result (
    $bridge.Contains('DarkPassengerTimedAreaAction.OnActionEvent(') -and
    $bridge.Contains('DarkPassengerTimedAreaAction.OnReload(') -and
    -not $bridge.Contains('DarkPassengerOverheardEvidence')
) 'player event bridge owns one reload-safe timed-area trampoline'
Add-Result (
    $caseContent.Contains('timed_area_actions') -and
    -not $caseContent.Contains('overheard_scenes')
) 'selected Case carries timed area actions without NPC scenes'
Add-Result (
    $runtime.Contains('selected.variant.timed_area_actions')
) 'timed-area runtime survives a partially restored CaseInstance'

$obsoleteTokens = @(
    'wh_player_InteractorDistance',
    'interactive_overheard',
    'DP_OVERHEARD_SPEAKER_A',
    'DP_OVERHEARD_SPEAKER_B',
    'StartInteractorDistancePolling',
    'AreSpeakersWithinDistance',
    'StageOverheard',
    'WatchOverheard'
)
$productionText = $runtime + "`n" + $interaction + "`n" + $bridge +
    "`n" + $caseContent
foreach ($token in $obsoleteTokens) {
    Add-Result (-not $productionText.Contains($token)) `
        "obsolete overheard token removed: $token"
}
Add-Result (
    -not $interaction.Contains('RegisterFilter') -and
    -not $interaction.Contains('_filterOrder')
) 'shared interactions no longer carry the listen-distance filter seam'

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler -PathType Leaf) `
        'LuaCompiler is available'
    if (Test-Path -LiteralPath $compiler -PathType Leaf) {
        foreach ($path in @($runtimePath, $bridgePath, $caseContentPath)) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            & $compiler $path 2>&1 | Out-Null
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
