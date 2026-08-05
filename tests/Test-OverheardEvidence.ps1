param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DevGameRoot)) {
    throw 'Set KCD2_DEV_ROOT or pass -DevGameRoot.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $repoRoot 'tools\Build-Mod.ps1'
$stageRoot = Join-Path $repoRoot 'build\mod'
$dialogPath = Join-Path $stageRoot (
    'Data\Quests\darkpassengertest\trosecko\dark_within_t\' +
    'overheard_missing_traveler_dialog_t.xml'
)
$questPath = Join-Path $stageRoot `
    'Data\Quests\Final\Barbora\trosecko\dark_within_t.xml'
$kutnoQuestPath = Join-Path $stageRoot `
    'Data\Quests\Final\Barbora\kutnohorsko\dark_within_k.xml'
$stormPath = Join-Path $stageRoot `
    'Data\Libs\Storm\roles\quests\darkpassengertest.xml'
$contextPath = Join-Path $stageRoot `
    'Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml'
$buffTagPath = Join-Path $stageRoot `
    'Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
$buffPath = Join-Path $stageRoot `
    'Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
$rolePath = Join-Path $stageRoot `
    'Data\Libs\Tables\rpg\role__darkpassengertest.xml'
$sourceRolePath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\role__darkpassengertest.xml'
$bindingPath = Join-Path $repoRoot `
    'content\migration\legacy-case-settlement-bindings.json'
$catalogPath = Join-Path $stageRoot `
    'Data\Scripts\mods\generated\dp_case_catalog.lua'
$runtimePath = Join-Path $stageRoot `
    'Data\Scripts\mods\dpoverheardevidence.lua'
$initPath = Join-Path $stageRoot `
    'Data\Scripts\mods\darkpassengertest.lua'

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

function Read-OptionalText([string]$LiteralPath) {
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return '' }
    return [System.IO.File]::ReadAllText($LiteralPath)
}

& $buildScript -SkipPackaging -DevGameRoot $DevGameRoot
Add-Result ($?) 'staging build compiles the overheard canary'

foreach ($path in @(
    $dialogPath,
    $questPath,
    $kutnoQuestPath,
    $stormPath,
    $contextPath,
    $buffTagPath,
    $buffPath,
    $rolePath,
    $catalogPath,
    $runtimePath,
    $initPath
)) {
    Add-Result (Test-Path -LiteralPath $path -PathType Leaf) `
        "overheard artifact exists: $path"
}

$dialog = Read-OptionalText $dialogPath
$quest = Read-OptionalText $questPath
$kutnoQuest = Read-OptionalText $kutnoQuestPath
$storm = Read-OptionalText $stormPath
$contexts = Read-OptionalText $contextPath
$buffTags = Read-OptionalText $buffTagPath
$buffs = Read-OptionalText $buffPath
$roles = Read-OptionalText $rolePath
$sourceRoles = Read-OptionalText $sourceRolePath
$bindings = Get-Content -LiteralPath $bindingPath -Raw | ConvertFrom-Json
$catalog = Read-OptionalText $catalogPath
$runtime = Read-OptionalText $runtimePath
$init = Read-OptionalText $initPath

Add-Result (
    $dialog.Contains('<Dialog Name="overheard_missing_traveler_dialog_t">') -and
    $dialog.Contains(
        '<Dialogue Type="ingame" TechnicalStatus="Enabled" Initiator="NonPlayer">'
    ) -and
    $dialog.Contains('<Decision Name="overheard_root" Priority="General"') -and
    -not $dialog.Contains('Priority="SideQuest"') -and
    $dialog.Contains('<Port Name="clue_spoken" Direction="Out" Type="trigger">') -and
    $dialog.Contains('<Port Name="clue_spoken" />') -and
    $dialog.Contains('Role="DP_OVERHEARD_SPEAKER_A"') -and
    $dialog.Contains('Role="DP_OVERHEARD_SPEAKER_B"')
) 'generated canary is a native two-NPC ingame dialogue'
Add-Result (
    $dialog.Contains('Alias="darkPassenger_missingTravelerOverheard"') -and
    $dialog.Contains('StringName="dp_mt_overheard_matej_argument"') -and
    $dialog.Contains('StringName="dp_mt_overheard_widow_money"') -and
    $dialog.Contains('StringName="dp_mt_overheard_gone_by_dawn"')
) 'ingame dialogue carries one authored exact-line clue sequence'

Add-Result (
    $quest.Contains(
        '<Definition File="dark_within_t/overheard_missing_traveler_dialog_t.xml" />'
    ) -and
    $quest.Contains('<overheard_missing_traveler_dialog_t Name="overheardEvidenceDialog"')
) 'universal quest consumes the generated overheard dialogue'
Add-Result (
    $quest.Contains('<switchdialog Name="overheardSwitchPrimary" Namespace="utils.speech">') -and
    $quest.Contains('<switchdialog Name="overheardSwitchFallback" Namespace="utils.speech">') -and
    ([regex]::Matches($quest, '<Constant Name="dialogtype" Value="Ingame" />')).Count -ge 2 -and
    ([regex]::Matches($quest, '<Constant Name="playerdistance" Value="15" />')).Count -ge 2 -and
    ([regex]::Matches($quest, '<Constant Name="alias" Value="darkPassenger_missingTravelerOverheard" />')).Count -ge 2
) 'native switchdialog schedulers use the compiled pair and hearing radius'
Add-Result (
    $quest.Contains('<Asset Name="A" Alias="DpOverheardZelejovPrimaryA" />') -and
    $quest.Contains('<Asset Name="B" Alias="DpOverheardZelejovPrimaryB" />') -and
    $quest.Contains('<Asset Name="A" Alias="DpOverheardZelejovFallbackA" />') -and
    $quest.Contains('<Asset Name="B" Alias="DpOverheardZelejovFallbackB" />') -and
    $quest.Contains('<SoulAsset Name="DpOverheardZelejovPrimaryA" SharedSoulGuids="5927ef47-3d33-4483-8316-ab3247f7aa4e" />') -and
    $quest.Contains('<SoulAsset Name="DpOverheardZelejovPrimaryB" SharedSoulGuids="4758bdb9-f854-38ef-1ea4-e8799614ceb7" />')
) 'quest embeds exact primary and finite fallback speaker assets'
Add-Result (
    $quest.Contains('<SetEntityContext Name="overheardClueRequest">') -and
    $quest.Contains('<Constant Name="Context" Value="dp_overheard_clue_spoken_trosecko" />') -and
    $quest.Contains('<Edge From="overheardEvidenceDialog.clue_spoken" To="SetTrue" />') -and
    $quest.Contains('<Timer Name="overheardCluePulse">') -and
    $quest.Contains('<Constant Name="Duration" Value="3s" />') -and
    $quest.Contains('<Constant Name="TimeType" Value="GameTime" />') -and
    -not $quest.Contains('<Constant Name="TimeType" Value="RealTime" />')
) 'clue completion reaches Lua through a repeatable ScriptContext pulse'
Add-Result (
    $quest.Contains(
        '<State Name="evidenceProgress" TypeT="DP_TroseckoEvidenceProgress">'
    ) -and
    $quest.Contains('<Type TypeName="DP_TroseckoEvidenceProgress">') -and
    $quest.Contains(
        '<Objective TypeT="DP_TroseckoEvidenceProgress" Name="dark_within_evidencet">'
    ) -and
    $quest.Contains(
        '<Edge From="satisfactionTrigger.OnRemoved" To="SetDirectionsNone" />'
    ) -and
    -not $quest.Contains('TypeT="DP_EvidenceProgress"')
) 'Trosky evidence enum is region-scoped and resets through a real enum port'
Add-Result (
    $kutnoQuest.Contains(
        '<State Name="evidenceProgress" TypeT="DP_KutnohorskoEvidenceProgress">'
    ) -and
    $kutnoQuest.Contains('<Type TypeName="DP_KutnohorskoEvidenceProgress">') -and
    $kutnoQuest.Contains(
        '<Objective TypeT="DP_KutnohorskoEvidenceProgress" Name="dark_within_evidencek">'
    ) -and
    $kutnoQuest.Contains(
        '<Edge From="satisfactionTrigger.OnRemoved" To="SetDirectionsNone" />'
    ) -and
    -not $kutnoQuest.Contains('TypeT="DP_EvidenceProgress"')
) 'Kuttenberg evidence enum is region-scoped and resets through a real enum port'
$regionalCustomTypes = @(
    @($quest, $kutnoQuest) | ForEach-Object {
        [regex]::Matches($_, '<Type TypeName="(DP_[^"]+)"') |
            ForEach-Object { $_.Groups[1].Value }
    }
)
$duplicateRegionalCustomTypes = @(
    $regionalCustomTypes |
        Group-Object |
        Where-Object { $_.Count -gt 1 }
)
Add-Result (
    $duplicateRegionalCustomTypes.Count -eq 0
) 'generated Barbora regions have no colliding custom TypeName values'
Add-Result (
    $quest.Contains('Name="overheardPrimaryAvailableTrigger"') -and
    $quest.Contains('Name="overheardFallbackAvailableTrigger"') -and
    $quest.Contains('<Constant Name="A" Value="71" />') -and
    $quest.Contains('From="overheardPrimaryAvailableTrigger.OnRemoved" To="SetFalse"') -and
    $quest.Contains('From="overheardFallbackAvailableTrigger.OnRemoved" To="SetFalse"')
) 'one hidden availability signal disables both schedulers after discovery'

foreach ($binding in @(
    @{ Name = 'tzel_man_12'; Role = 'DP_OVERHEARD_SPEAKER_A' },
    @{ Name = 'tzel_woman_9'; Role = 'DP_OVERHEARD_SPEAKER_B' },
    @{ Name = 'tzel_man_13'; Role = 'DP_OVERHEARD_SPEAKER_A' },
    @{ Name = 'tzel_woman_11'; Role = 'DP_OVERHEARD_SPEAKER_B' }
)) {
    Add-Result (
        $storm.Contains(('<hasName name="{0}" />' -f $binding.Name)) -and
        $storm.Contains(('<addRole name="{0}" />' -f $binding.Role))
    ) "Storm binds $($binding.Name) to $($binding.Role)"
}
Add-Result (
    $contexts.Contains(
        '<ScriptContextDatabaseNode Name="dp_overheard_clue_spoken_trosecko" Class="Entity" />'
    )
) 'overheard ScriptContext is registered'
Add-Result (
    -not $sourceRoles.Contains('role_name="DP_OVERHEARD_SPEAKER_A"') -and
    -not $sourceRoles.Contains('role_name="DP_OVERHEARD_SPEAKER_B"')
) 'overheard dialogue roles are not maintained in the static RPG table'
$overheardRoleDefinitions = @($bindings.dialogueRoles | Where-Object {
    [string]$_.name -in @(
        'DP_OVERHEARD_SPEAKER_A',
        'DP_OVERHEARD_SPEAKER_B'
    )
})
Add-Result (
    $overheardRoleDefinitions.Count -eq 2 -and
    @($overheardRoleDefinitions | Where-Object {
        $roles.Contains(('role_id="{0}"' -f [string]$_.roleId)) -and
        $roles.Contains(('role_name="{0}"' -f [string]$_.name))
    }).Count -eq 2
) 'compiler generates both registered overheard RPG roles from bindings'
Add-Result (
    $buffTags.Contains(
        'buff_ai_tag_id="71" buff_ai_tag_name="dp_overheard_available"'
    ) -and
    $buffs.Contains('buff_name="dp_overheard_available"') -and
    $buffs.Contains('is_persistent="true"')
) 'build registers the hidden persistent scheduler signal'
Add-Result (
    $catalog.Contains('id = "zelejov_inn_yard_whisper"') -and
    $catalog.Contains('code = 2104') -and
    $catalog.Contains('confidence = 15') -and
    $catalog.Contains('overheard = {') -and
    $catalog.Contains('hearing_distance = 15') -and
    $catalog.Contains('available_tag = 71') -and
    $catalog.Contains('entityName = "tzel_man_12"') -and
    $catalog.Contains('entityName = "tzel_woman_11"')
) 'runtime catalog carries evidence, pair fallbacks, and acceptance radius'

foreach ($export in @(
    'SelectPair',
    'Transition',
    'ApplyAvailability',
    'Restore',
    'OnClueSpoken',
    'RunSelfTest'
)) {
    Add-Result (
        $runtime.Contains("function DarkPassengerOverheardEvidence.$export")
    ) "overheard runtime exports $export"
}
Add-Result (
    $runtime.Contains('target_collision') -and
    $runtime.Contains('out_of_range') -and
    $runtime.Contains('stale_generation') -and
    $runtime.Contains('already_discovered') -and
    $runtime.Contains('DarkPassengerEvidenceRegistry.Discover(') -and
    $runtime.Contains('DarkPassengerLeadPlanner.Apply(')
) 'runtime enforces exact-generation one-shot distance acceptance'
Add-Result (
    $init.Contains(
        'Script.ReloadScript("Scripts/mods/dpoverheardevidence.lua")'
    ) -and
    $init.Contains('overheardContext = "dp_overheard_clue_spoken_trosecko"') -and
    $init.Contains('DarkPassengerOverheardEvidence.OnClueSpoken(') -and
    $init.Contains('lastOverheardStates')
) 'quest bridge polls the overheard ScriptContext rising edge'

if ((Test-Path -LiteralPath $dialogPath) -and
    -not [string]::IsNullOrWhiteSpace($dialog)) {
    try {
        [void][xml]$dialog
        Add-Result $true 'overheard dialogue is well-formed XML'
    }
    catch {
        Add-Result $false 'overheard dialogue is well-formed XML'
    }
}
else {
    Add-Result $false 'overheard dialogue is well-formed XML'
}

$compiler = Join-Path $DevGameRoot 'Bin\Win64SharedPrivate\LuaCompiler.exe'
Add-Result (Test-Path -LiteralPath $compiler -PathType Leaf) `
    'LuaCompiler is available'
foreach ($path in @($runtimePath, $initPath)) {
    if ((Test-Path -LiteralPath $compiler) -and
        (Test-Path -LiteralPath $path)) {
        & $compiler -p $path *> $null
        Add-Result ($LASTEXITCODE -eq 0) `
            "LuaCompiler accepts $(Split-Path -Leaf $path)"
    }
    else {
        Add-Result $false "LuaCompiler accepts $(Split-Path -Leaf $path)"
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
