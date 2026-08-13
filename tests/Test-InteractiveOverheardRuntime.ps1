param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpoverheardevidence.lua'
$bridgePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$ruPath = Join-Path $repoRoot `
    'localization\Russian\text__darkpassengertest.xml'
$enPath = Join-Path $repoRoot `
    'localization\English\text__darkpassengertest.xml'

$runtime = [System.IO.File]::ReadAllText($runtimePath)
$bridge = [System.IO.File]::ReadAllText($bridgePath)
$ru = [System.IO.File]::ReadAllText($ruPath)
$en = [System.IO.File]::ReadAllText($enPath)
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

foreach ($export in @(
    'NormalizePairs',
    'NormalizeScenes',
    'GetContextRequests',
    'GetInteractiveSceneForEntity',
    'CanStartInteraction',
    'StartInteraction',
    'AddListenAction'
)) {
    Add-Result (
        $runtime.Contains(
            "function DarkPassengerOverheardEvidence.$export"
        )
    ) "overheard runtime exports $export"
}

Add-Result (
    $runtime.Contains('local function ScenePairs(scene)') -and
    $runtime.Contains('NormalizePairs(scene.pairs)') -and
    $runtime.Contains('ipairs(ScenePairs(scene))')
) 'runtime accepts legacy scalar pair and canonical pair arrays'
Add-Result (
    $runtime.Contains('function DarkPassengerOverheardEvidence.NormalizeScenes(scenes)') -and
    $runtime.Contains('if scenes.id ~= nil then return { scenes } end') -and
    $runtime.Contains('DarkPassengerOverheardEvidence.NormalizeScenes(')
) 'runtime accepts a scalar generated scene and canonical scene arrays'

Add-Result (
    $runtime.Contains('activation_mode == "interaction"') -and
    $runtime.Contains('activation_mode == "proximity"') -and
    $runtime.Contains('DarkPassengerInteractions.RegisterProvider(') -and
    $runtime.Contains('"interactive_overheard"') -and
    $runtime.Contains(':hint("@dp_overheard_listen_action")') -and
    $runtime.Contains(':hintType(AHT_RELEASE)')
) 'interaction provider exposes release action only for interactive scenes'

foreach ($reason in @(
    'stale_generation',
    'already_discovered',
    'target_collision',
    'speaker_missing',
    'speaker_dead',
    'player_in_combat',
    'dialogue_active',
    'out_of_range'
)) {
    Add-Result ($runtime.Contains('"' + $reason + '"')) `
        "runtime defines rejection reason $reason"
}

Add-Result (
    $runtime.Contains('AddPairSignal(pair, scene.buff_guid)') -and
    $runtime.Contains('RemoveAllSignals(scene)') -and
    $runtime.Contains('IsDiscovered(generation, scene.evidence_code)')
) 'interaction starts through the scene-specific signal and one-shot evidence'
Add-Result (
    $runtime.Contains('for _, scene in ipairs(OverheardScenes(') -and
    $runtime.Contains('if scene.activation_mode == "proximity" then')
) 'automatic availability is restricted to proximity scenes'
Add-Result (
    $bridge.Contains('GetContextRequests(request.region)') -and
    $bridge.Contains('OnClueSpoken(request.region, contextRequest.sceneId)')
) 'quest bridge polls every compiled scene context by scene id'
Add-Result (
    $ru.Contains('<Cell>dp_overheard_listen_action</Cell><Cell>Прислушаться</Cell>') -and
    $en.Contains('<Cell>dp_overheard_listen_action</Cell><Cell>Listen in</Cell>')
) 'listen action is localized in Russian and English'

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot 'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler -PathType Leaf) `
        'LuaCompiler is available'
    if (Test-Path -LiteralPath $compiler -PathType Leaf) {
        foreach ($path in @($runtimePath, $bridgePath)) {
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
