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
$generatedRoot = Join-Path $repoRoot 'build\generated'

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

function Has-NoUtf8Bom([string]$LiteralPath) {
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    return $bytes.Length -lt 3 -or -not (
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    )
}

& $buildScript -SkipPackaging -DevGameRoot $DevGameRoot
Add-Result ($?) 'real build accepts two compiled cases'

$questPath = Join-Path $stageRoot `
    'Data\Quests\Final\Barbora\trosecko\dark_within_t.xml'
$dialogRoot = Join-Path $stageRoot `
    'Data\Quests\darkpassengertest\trosecko\dark_within_t'
$rumorPath = Join-Path $dialogRoot `
    'innkeeper_missing_traveler_dialog_t.xml'
$witnessPath = Join-Path $dialogRoot `
    'stablehand_missing_traveler_dialog_t.xml'
$overheardPath = Join-Path $dialogRoot `
    'overheard_missing_traveler_dialog_t.xml'
$stormPath = Join-Path $stageRoot `
    'Data\Libs\Storm\roles\quests\darkpassengertest.xml'
$contextPath = Join-Path $stageRoot `
    'Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml'
$itemPath = Join-Path $stageRoot `
    'Data\Libs\Tables\item\item__darkpassengertest.xml'
$buffTagPath = Join-Path $stageRoot `
    'Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
$buffPath = Join-Path $stageRoot `
    'Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
$catalogPath = Join-Path $stageRoot `
    'Data\Scripts\mods\generated\dp_case_catalog.lua'
$runtimePath = Join-Path $stageRoot `
    'Data\Scripts\mods\darkpassengertest.lua'
$englishPath = Join-Path $generatedRoot `
    'localization\English\text__darkpassengertest.xml'
$russianPath = Join-Path $generatedRoot `
    'localization\Russian\text__darkpassengertest.xml'

foreach ($path in @(
    $questPath,
    $rumorPath,
    $witnessPath,
    $overheardPath,
    $stormPath,
    $contextPath,
    $itemPath,
    $buffTagPath,
    $buffPath,
    $catalogPath,
    $runtimePath,
    $englishPath,
    $russianPath
)) {
    Add-Result (Test-Path -LiteralPath $path -PathType Leaf) `
        "generated artifact exists: $path"
}

$quest = Read-OptionalText $questPath
$rumor = Read-OptionalText $rumorPath
$witness = Read-OptionalText $witnessPath
$overheard = Read-OptionalText $overheardPath
$storm = Read-OptionalText $stormPath
$contexts = Read-OptionalText $contextPath
$items = Read-OptionalText $itemPath
$buffTags = Read-OptionalText $buffTagPath
$buffs = Read-OptionalText $buffPath
$catalog = Read-OptionalText $catalogPath
$runtime = Read-OptionalText $runtimePath
$english = Read-OptionalText $englishPath
$russian = Read-OptionalText $russianPath

Add-Result (
    $quest.Contains(
        '<Definition File="dark_within_t/innkeeper_missing_traveler_dialog_t.xml" />'
    ) -and
    $quest.Contains(
        '<Definition File="dark_within_t/stablehand_missing_traveler_dialog_t.xml" />'
    ) -and
    $quest.Contains(
        '<Definition File="dark_within_t/overheard_missing_traveler_dialog_t.xml" />'
    ) -and
    $quest.Contains('<innkeeper_missing_traveler_dialog_t Name="innkeeperRumorDialog">') -and
    $quest.Contains('<stablehand_missing_traveler_dialog_t Name="tavernWitnessDialog">')
) 'universal Trosky quest consumes both generated dialogues'
Add-Result (
    $quest.Contains('dp_rumor_heard_trosecko') -and
    $quest.Contains('dp_witness_heard_trosecko') -and
    $quest.Contains('Name="Directions2102_2103"') -and
    $quest.Contains('Name="Directions2102"') -and
    $quest.Contains('Name="Directions2103"') -and
    -not $quest.Contains('Name="witnessVisual"') -and
    -not $quest.Contains('TypeT="DP_WitnessProgress"')
) 'universal Trosky graph carries one finite umbrella evidence objective'
Add-Result (
    $quest.Contains('Value="37"') -and
    $quest.Contains('Value="40"') -and
    $quest.Contains('dp_case_2001_directions_2102_2103')
) 'quest graph consumes deterministic Lua presentation signals'

Add-Result (
    $rumor.Contains('Role="DP_INNKEEPER_RUMOR"') -and
    $rumor.Contains('StringName="dp_mt_rumor_prompt"') -and
    $rumor.Contains('StringName="dp_mt_rumor_innkeeper_matej"') -and
    $rumor.Contains('<Port Name="variant_unread_ledger" Direction="In" Type="bool">') -and
    $rumor.Contains('<Port Name="variant_ledger_discovered" Direction="In" Type="bool">') -and
    $rumor.Contains(
        'EntryCondition="Port(''available'') AND Port(''variant_unread_ledger'')"'
    ) -and
    $rumor.Contains(
        'EntryCondition="Port(''available'') AND Port(''variant_ledger_discovered'')"'
    ) -and
    $rumor.Contains('StringName="dp_mt_rumor_found_henry_hand"') -and
    ([regex]::Matches($rumor, '<Port Name="heard" />')).Count -eq 2
) 'generated innkeeper dialogue compiles both variants into one reward port'
Add-Result (
    $quest.Contains('Value="69"') -and
    $quest.Contains('Value="70"') -and
    $quest.Contains('Name="rumorVariant0Trigger"') -and
    $quest.Contains('Name="rumorVariant1Trigger"') -and
    $quest.Contains('To="variant_unread_ledger"') -and
    $quest.Contains('To="variant_ledger_discovered"')
) 'universal quest projects compiled variant signals into FaderDialog ports'
Add-Result (
    $witness.Contains('Role="DP_TAVERN_WITNESS"') -and
    $witness.Contains('StringName="dp_mt_witness_prompt"') -and
    $witness.Contains('StringName="dp_mt_witness_bretislav_point"')
) 'generated witness dialogue uses semantic role and authored keys'
Add-Result (
    $overheard.Contains('<Dialogue Type="ingame"') -and
    $overheard.Contains('Initiator="NonPlayer"') -and
    $overheard.Contains('<Port Name="clue_spoken" />')
) 'generated overheard evidence uses the native ingame dialogue boundary'

Add-Result (
    $storm.Contains('<hasName name="tzel_vavrinec" />') -and
    $storm.Contains('<addRole name="DP_INNKEEPER_RUMOR" />') -and
    $storm.Contains('<hasName name="tzel_bretislav" />') -and
    $storm.Contains('<addRole name="DP_TAVERN_WITNESS" />')
) 'Storm binds the exact Zhelejov actors to generic dialogue roles'
Add-Result (
    $contexts.Contains(
        '<ScriptContextDatabaseNode Name="dp_rumor_heard_trosecko" Class="Entity" />'
    ) -and
    $contexts.Contains(
        '<ScriptContextDatabaseNode Name="dp_witness_heard_trosecko" Class="Entity" />'
    ) -and
    $contexts.Contains(
        '<ScriptContextDatabaseNode Name="dp_overheard_clue_spoken_trosecko" Class="Entity" />'
    )
) 'generated ScriptContext table exposes all Trosky evidence bridges'
Add-Result (
    $items.Contains('Id="d5833fd4-f7bf-4957-86f5-d661db38bcf3"') -and
    $items.Contains('Name="dp_matej_guest_ledger"') -and
    $items.Contains('UIName="dp_mt_ledger_name"') -and
    $items.Contains('UIInfo="dp_mt_ledger_info"') -and
    $items.Contains('<DocumentContent Parts="dp_mt_ledger_content" />')
) 'generated item table contains Matej ledger document'

foreach ($localization in @(
    @{ Language = 'English'; Text = $english },
    @{ Language = 'Russian'; Text = $russian }
)) {
    Add-Result (
        $localization.Text.Contains('<Cell>dp_mt_rumor_prompt</Cell>') -and
        $localization.Text.Contains(
            '<Cell>dp_mt_rumor_prompt_ledger_found</Cell>'
        ) -and
        $localization.Text.Contains(
            '<Cell>dp_mt_rumor_found_innkeeper_boguslav</Cell>'
        ) -and
        $localization.Text.Contains('<Cell>dp_mt_witness_prompt</Cell>') -and
        $localization.Text.Contains('<Cell>dp_mt_ledger_content</Cell>') -and
        $localization.Text.Contains('&lt;p&gt;') -and
        $localization.Text.Contains(
            '<Cell>dp_case_2001_directions_2102_2103</Cell>'
        )
    ) "$($localization.Language) generated localization contains all content families"
}
Add-Result (
    $russian.Contains('Вырванный лист гостевой книги') -and
    $english.Contains('Torn Guest-Ledger Page')
) 'Russian and English document copy is authored independently'
Add-Result (
    $russian.Contains('Расспросить Богуслава о коне Матея') -and
    $russian.Contains('Расспросить батрака Богуслава') -and
    -not $russian.Contains('Бретислав') -and
    -not $russian.Contains('Расспросить конюха') -and
    $english.Contains('Question the farmhand Bretislav')
) 'generated localization preserves native witness identity by language'

Add-Result (
    $catalog.Contains('id = "missing_traveler"') -and
    $catalog.Contains('entityName = "tzel_vavrinec"') -and
    $catalog.Contains('entityName = "tzel_bretislav"') -and
    $catalog.Contains('documentGuid = "d5833fd4-f7bf-4957-86f5-d661db38bcf3"')
) 'runtime catalog carries the same concrete binding identity'
Add-Result (
    $catalog.Contains('name = "Богуслав"') -and
    $catalog.Contains('occupation = "батрак"') -and
    $catalog.Contains('name = "Bretislav"') -and
    $catalog.Contains('occupation = "farmhand"')
) 'runtime catalog carries localized witness identity metadata'
Add-Result (
    $catalog.Contains('direction_code = 1') -and
    $catalog.Contains('direction_code = 2') -and
    $catalog.Contains('journal_states') -and
    $catalog.Contains('state_name = "Directions2102_2103"') -and
    $catalog.Contains('signal_tag = 40')
) 'runtime catalog and quest share finite journal-state identity'
Add-Result (
    $catalog.Contains('dialogue_variants') -and
    $catalog.Contains('evidence_id = "zelejov_innkeeper_missing_traveler"') -and
    $catalog.Contains('id = "unread_ledger"') -and
    $catalog.Contains('id = "ledger_discovered"') -and
    $catalog.Contains('all_discovered_codes = {') -and
    $catalog.Contains('signal_tag = 69') -and
    $catalog.Contains('signal_tag = 70')
) 'runtime catalog carries finite dialogue-variant selectors'
Add-Result (
    $buffTags.Contains('buff_ai_tag_id="37" buff_ai_tag_name="dp_lead_state_0"') -and
    $buffTags.Contains('buff_ai_tag_id="40" buff_ai_tag_name="dp_lead_state_3"') -and
    $buffs.Contains('buff_name="dp_lead_state_0"') -and
    $buffs.Contains('buff_name="dp_lead_state_3"')
) 'build generates hidden persistent lead-state signal buffs'
Add-Result (
    $buffTags.Contains(
        'buff_ai_tag_id="69" buff_ai_tag_name="dp_dialogue_variant_0"'
    ) -and
    $buffTags.Contains(
        'buff_ai_tag_id="70" buff_ai_tag_name="dp_dialogue_variant_1"'
    ) -and
    $buffs.Contains('buff_name="dp_dialogue_variant_0"') -and
    $buffs.Contains('buff_name="dp_dialogue_variant_1"')
) 'build generates hidden persistent dialogue-variant signal buffs'
Add-Result (
    $runtime -match (
        '(?s)region = "trosecko".*?' +
        'rumorContext = "dp_rumor_heard_trosecko".*?' +
        'witnessContext = "dp_witness_heard_trosecko"'
    )
) 'Lua quest bridge consumes Trosky rumor and witness contexts'

$troskyQuestFiles = @(Get-ChildItem -LiteralPath (Split-Path -Parent $questPath) `
    -Filter 'dark_within*.xml' -File)
Add-Result (
    $troskyQuestFiles.Count -eq 1 -and
    $troskyQuestFiles[0].Name -eq 'dark_within_t.xml'
) 'Missing Traveler reuses one universal Trosky quest container'

foreach ($path in @(
    $rumorPath,
    $witnessPath,
    $stormPath,
    $contextPath,
    $itemPath,
    $buffTagPath,
    $buffPath,
    $catalogPath,
    $runtimePath,
    $englishPath,
    $russianPath
)) {
    Add-Result (Has-NoUtf8Bom $path) `
        "generated artifact has no UTF-8 BOM: $(Split-Path -Leaf $path)"
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
