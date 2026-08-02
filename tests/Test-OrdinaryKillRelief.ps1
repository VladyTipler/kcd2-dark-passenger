param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$hungerPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dphunger.lua'
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$questTemplatePath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'
$observerRootPath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest.xml'
$kuttenbergObserverPath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko.xml'
$troskyObserverPath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\trosecko.xml'
$scriptContextPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml'
$generatorPath = Join-Path $repoRoot `
    'tools\Generate-VictimArtifacts.ps1'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

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

$hunger = Get-Content -Raw -LiteralPath $hungerPath
$runtime = Get-Content -Raw -LiteralPath $runtimePath
$questTemplate = Get-Content -Raw -LiteralPath $questTemplatePath
$generator = Get-Content -Raw -LiteralPath $generatorPath
$observerRoot = if (Test-Path -LiteralPath $observerRootPath) {
    Get-Content -Raw -LiteralPath $observerRootPath
} else {
    ''
}
$kuttenbergObserver = if (Test-Path -LiteralPath $kuttenbergObserverPath) {
    Get-Content -Raw -LiteralPath $kuttenbergObserverPath
} else {
    ''
}
$troskyObserver = if (Test-Path -LiteralPath $troskyObserverPath) {
    Get-Content -Raw -LiteralPath $troskyObserverPath
} else {
    ''
}
$scriptContexts = Get-Content -Raw -LiteralPath $scriptContextPath

foreach ($token in @(
    'function DarkPassengerHunger.ReliefTransition(',
    'function DarkPassengerHunger.RelieveFromOrdinaryKill(',
    'reason = "not_hungry"',
    'current = 50',
    'DarkPassengerHunger.RELIEF_HUNGER'
)) {
    Add-Result ($hunger.Contains($token)) "hunger runtime contains $token"
}

$transitionStart = $hunger.IndexOf(
    'function DarkPassengerHunger.ReliefTransition('
)
$reliefStart = $hunger.IndexOf(
    'function DarkPassengerHunger.RelieveFromOrdinaryKill('
)
$transitionBody = if (
    $transitionStart -ge 0 -and $reliefStart -gt $transitionStart
) {
    $hunger.Substring($transitionStart, $reliefStart - $transitionStart)
} else {
    ''
}

Add-Result (
    $transitionBody.Contains('value <= DarkPassengerHunger.RELIEF_HUNGER')
) 'pure transition preserves hunger at and below 50'
Add-Result (
    $transitionBody.Contains('previous = value') -and
    $transitionBody.Contains('current = value')
) 'no-op transition preserves its exact hunger value'

$reliefEnd = $hunger.IndexOf(
    'function DarkPassengerHunger.Status(',
    [Math]::Max(0, $reliefStart)
)
$reliefBody = if (
    $reliefStart -ge 0 -and $reliefEnd -gt $reliefStart
) {
    $hunger.Substring($reliefStart, $reliefEnd - $reliefStart)
} else {
    ''
}

Add-Result (
    $reliefBody.Contains('DarkPassengerHunger.Get()') -and
    $reliefBody.Contains('DarkPassengerHunger.ReliefTransition(')
) 'ordinary relief reads current hunger before deciding'
Add-Result (
    $reliefBody.Contains('if not transition.accepted then')
) 'ordinary relief exits before writes on the no-op path'
Add-Result (
    -not $reliefBody.Contains('DarkPassengerHunger.ResetNow(')
) 'ordinary relief does not use the full satisfaction reset'

foreach ($token in @(
    'function DarkPassengerHunger.RunReliefSelfTest()',
    'assertTransition(40, false, 40)',
    'assertTransition(50, false, 50)',
    'assertTransition(60, true, 50)',
    'assertTransition(100, true, 50)'
)) {
    Add-Result ($hunger.Contains($token)) "relief self-test contains $token"
}

Add-Result (
    -not $questTemplate.Contains('ordinaryHumanKillTrigger') -and
    -not $questTemplate.Contains('{{DP_ORDINARY_KILL_CONTEXT}}')
) 'regional quest template does not own the global kill observer'
Add-Result (
    -not $generator.Contains('OrdinaryKillContext') -and
    -not $generator.Contains('ordinaryKillContext')
) 'victim generator does not configure the global kill observer'

foreach ($token in @(
    '<Project Name="darkpassengertest">',
    '<Definition File="darkpassengertest/kutnohorsko.xml" />',
    '<Definition File="darkpassengertest/trosecko.xml" />',
    '<kutnohorsko Name="kutnohorsko"',
    '<trosecko Name="trosecko"'
)) {
    Add-Result ($observerRoot.Contains($token)) `
        "standalone observer root contains $token"
}

foreach ($observerSpec in @(
    @{ Name = 'kutnohorsko'; Text = $kuttenbergObserver },
    @{ Name = 'trosecko'; Text = $troskyObserver }
)) {
    foreach ($token in @(
        "<Level Name=`"$($observerSpec.Name)`"",
        '<Edge From="OnWake" To="SetRunning" />',
        '<Function Name="getHumanKillCount" MethodName="wh::rpgmodule::GetStatistic" DeclaringType="wh::rpgmodule">',
        '<Constant Name="Statistic" Value="HumansKilled" />',
        '<Function Name="nextHumanKillThresholdValue" MethodName="wh::conceptmodule::math::AddFloat" DeclaringType="wh::conceptmodule::math">',
        '<Edge From="getHumanKillCount.Value" To="A" />',
        '<Function Name="nextHumanKillThresholdDouble" MethodName="math::conversion::ToDouble(float)" DeclaringType="math::conversion">',
        '<Edge From="nextHumanKillThresholdValue.float" To="float" />',
        '<State Name="nextHumanKillThreshold" TypeT="double">',
        '<Edge From="nextHumanKillThresholdDouble.double" To="Value" />',
        '<StatisticTrigger Name="ordinaryHumanKillTrigger">',
        '<Constant Name="Statistic" Value="HumansKilled" />',
        '<Edge From="nextHumanKillThreshold.State" To="Threshold" />',
        '<State Name="ordinaryHumanKillPulse" TypeT="bool">',
        '<SetEntityContext Name="ordinaryHumanKillRequest">',
        '<Constant Name="Context" Value="dp_ordinary_human_kill" />',
        '<SoulAsset Name="player" SharedSoulGuids="4c2dcffb-dea1-6263-72d7-b39f4db2d8b5" />'
    )) {
        Add-Result ($observerSpec.Text.Contains($token)) `
            "$($observerSpec.Name) observer contains $token"
    }
}

Add-Result (
    $scriptContexts.Contains(
        '<ScriptContextDatabaseNode Name="dp_ordinary_human_kill" Class="Entity" />'
    )
) 'script-context table registers the global ordinary-kill pulse'

foreach ($token in @(
    'DarkPassengerQuestBridge.KILL_CONTEXT = "dp_ordinary_human_kill"',
    'DarkPassengerQuestBridge.lastKillState',
    'function DarkPassengerTest.OnOrdinaryHumanKillObserved(',
    'DarkPassengerHunger.RelieveFromOrdinaryKill()'
)) {
    Add-Result ($runtime.Contains($token)) "kill adapter contains $token"
}

Add-Result (
    -not $runtime.Contains('killContext = "dp_ordinary_kill_kutnohorsko"') -and
    -not $runtime.Contains('killContext = "dp_ordinary_kill_trosecko"')
) 'Lua polls one global kill pulse instead of regional duplicates'

Add-Result (
    -not $runtime.Contains('SPNotifyPlayerKill') -and
    -not $runtime.Contains('InstallPlayerKillHook')
) 'runtime does not depend on the outgoing SPNotifyPlayerKill binding'

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    if (Test-Path -LiteralPath $compiler) {
        foreach ($path in @($hungerPath, $runtimePath)) {
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
