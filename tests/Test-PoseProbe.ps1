param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpposeprobe.lua'
$initPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$maleDialogPath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\pose_probe_male.xml'
$femaleDialogPath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\pose_probe_female.xml'
$kuttenbergLevelPath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko.xml'
$troskyLevelPath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\trosecko.xml'
$roleTablePath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\role__darkpassengertest.xml'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Read-OptionalText {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return '' }
    return Get-Content -Raw -LiteralPath $LiteralPath
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

$runtime = Read-OptionalText $runtimePath
$init = Read-OptionalText $initPath
$maleDialog = Read-OptionalText $maleDialogPath
$femaleDialog = Read-OptionalText $femaleDialogPath
$kuttenbergLevel = Read-OptionalText $kuttenbergLevelPath
$troskyLevel = Read-OptionalText $troskyLevelPath
$roleTable = Read-OptionalText $roleTablePath

Add-Result (Test-Path -LiteralPath $runtimePath) `
    'dev-only pose probe runtime exists'

foreach ($token in @(
    'DarkPassengerPoseProbe.PROFILES',
    'male = {',
    'female = {',
    'function DarkPassengerPoseProbe.SelectNearest(',
    'function DarkPassengerPoseProbe.Play(',
    'function DarkPassengerPoseProbe.Cycle(',
    'function DarkPassengerPoseProbe.Lock(',
    'function DarkPassengerPoseProbe.Unlock(',
    'restored selected control without active lock',
    'function DarkPassengerPoseProbe.PoseLockTick(',
    'function DarkPassengerPoseProbe.IdlePose(',
    'function DarkPassengerPoseProbe.Dialog(',
    'function DarkPassengerPoseProbe.Status(',
    'System.GetEntitiesInSphereByClass',
    'System.ExecuteCommand',
    'StartAnimation',
    'StartAnimation(0, animation, 0, 0.15, 1.0, true)',
    'rootMotion=false',
    'SetAnimationInput',
    'SetMovementControlledByAnimation',
    'SetMovementControlledByAnimation(true)',
    'AI.SetBehaviorTreeEvaluationEnabled',
    'AI.RequestToStopMovement',
    'AI.AbortAction',
    'AI.SetAnimationTag',
    'AI.ClearAnimationTag',
    'QueueAnimationState',
    'SetDefaultIdleAnimations(0)',
    'Script.SetTimer',
    'Script.KillTimer',
    'RequestDialog',
    'g_localActor.actor:RequestDialog',
    'dp_pose_select_name',
    'dp_pose_clear_dialogs',
    'dp_pose_force',
    'dp_pose_analyze',
    'AnalyzeRequest',
    'ForceDialog',
    'AddMetaRoleByName',
    'RemoveMetaRoleByName',
    'HasMetaRoleByName',
    'function DarkPassengerPoseProbe.StartConfession(',
    'CONFESSION_PROBE_BUFF_GUID',
    'wh_am_DebugPlayAnimation',
    'dp_pose_select',
    'dp_pose_play',
    'dp_pose_cycle',
    'dp_pose_lock',
    'dp_pose_unlock',
    'dp_pose_idle',
    'dp_pose_dialog',
    'dp_pose_confession',
    'dp_pose_input',
    'dp_pose_status'
)) {
    Add-Result ($runtime.Contains($token)) `
        "pose probe contains $token"
}

foreach ($removedInteractionToken in @(
    'companion_bond',
    'OnProbeAction'
)) {
    Add-Result (-not $runtime.Contains($removedInteractionToken)) `
        "pose probe removed temporary HUD action token $removedInteractionToken"
}

foreach ($animation in @(
    'dlg_male_wounded_listen_in',
    'quest_treating_wounded_s',
    'dlg_male_adjuration_loop_s',
    'dlg_female_simektereza_talk',
    'dlg_female_simektereza_listen',
    'healing_bed_typhus_female_solo_idle',
    'quest_femme_fatal_kill_loop_light_s'
)) {
    Add-Result ($runtime.Contains($animation)) `
        "pose probe includes animation candidate $animation"
}

Add-Result (
    $init.Contains(
        'Script.ReloadScript("Scripts/mods/dpposeprobe.lua")'
    )
) 'mod init loads the pose probe'

foreach ($dialog in @(
    @{ Label = 'male'; Text = $maleDialog },
    @{ Label = 'female'; Text = $femaleDialog }
)) {
    Add-Result (-not [string]::IsNullOrWhiteSpace($dialog.Text)) `
        "$($dialog.Label) probe dialog exists"
    foreach ($token in @(
        'dp_pose_probe_henry_check',
        'dp_pose_probe_victim_reply',
        'dp_pose_probe_henry_finish'
    )) {
        Add-Result ($dialog.Text.Contains($token)) `
            "$($dialog.Label) probe dialog contains $token"
    }
}

Add-Result (-not $maleDialog.Contains('Autoselect="true"')) `
    'male confession hub waits for player choice'
Add-Result ($maleDialog.Contains(
    'Mood="woundedLying"'
)) 'male confession uses the vanilla wounded-lying mood'
Add-Result (-not $maleDialog.Contains(
    'FragmentId="ADLG_LyingHarmed_In"'
)) 'male confession avoids the authored-smart-object-only lying transition'
Add-Result ($femaleDialog.Contains('Autoselect="true"')) `
    'female animation probe remains an automatic throwaway preview'
Add-Result ($femaleDialog.Contains('<AnimationCommand')) `
    'female animation probe keeps its explicit preview animation'

Add-Result ($maleDialog.Contains('Role="DP_CONFESSION_PROBE_MALE"')) `
    'male probe uses the mod-private confession role'
Add-Result ($femaleDialog.Contains('Role="RANENY_NA_ZEMI_ZENA"')) `
    'female probe uses the universal female wounded role'
Add-Result ($roleTable.Contains('role_name="RANENY_NA_ZEMI_MUZ"')) `
    'male wounded role is registered in RPG tables'
Add-Result ($roleTable.Contains('role_name="DP_CONFESSION_PROBE_MALE"')) `
    'mod-private confession role is registered in RPG tables'
Add-Result ($roleTable.Contains('role_name="RANENY_NA_ZEMI_ZENA"')) `
    'female wounded role is registered in RPG tables'

foreach ($level in @(
    @{ Label = 'Kuttenberg'; Text = $kuttenbergLevel },
    @{ Label = 'Trosky'; Text = $troskyLevel }
)) {
    Add-Result (
        -not $level.Text.Contains('Definition File="pose_probe_male.xml"') -and
        -not $level.Text.Contains('Definition File="pose_probe_female.xml"') -and
        -not $level.Text.Contains('<pose_probe_male ') -and
        -not $level.Text.Contains('<pose_probe_female ')
    ) "$($level.Label) level avoids unsafe standalone probe types"
}

foreach ($forbidden in @(
    'DarkPassengerCase',
    'DarkPassengerTarget',
    'DarkPassengerInvestigation'
)) {
    Add-Result (-not $runtime.Contains($forbidden)) `
        "pose probe is independent from $forbidden"
}

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    if ((Test-Path -LiteralPath $compiler) -and
        (Test-Path -LiteralPath $runtimePath)) {
        & $compiler -p $runtimePath *> $null
        Add-Result ($LASTEXITCODE -eq 0) `
            'pose probe passes LuaCompiler'
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
