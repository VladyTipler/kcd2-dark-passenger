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
$stormPath = Join-Path $stageRoot `
    'Data\Libs\Storm\roles\quests\darkpassengertest.xml'
$contextPath = Join-Path $stageRoot `
    'Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml'
$itemPath = Join-Path $stageRoot `
    'Data\Libs\Tables\item\item__darkpassengertest.xml'
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
    $stormPath,
    $contextPath,
    $itemPath,
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
$storm = Read-OptionalText $stormPath
$contexts = Read-OptionalText $contextPath
$items = Read-OptionalText $itemPath
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
    $quest.Contains('<innkeeper_missing_traveler_dialog_t Name="innkeeperRumorDialog">') -and
    $quest.Contains('<stablehand_missing_traveler_dialog_t Name="tavernWitnessDialog">')
) 'universal Trosky quest consumes both generated dialogues'
Add-Result (
    $quest.Contains('dp_rumor_heard_trosecko') -and
    $quest.Contains('dp_witness_heard_trosecko') -and
    $quest.Contains('<DarkWithinWitnessObjective_t Name="witnessVisual">') -and
    $quest.Contains('<Objective TypeT="DP_WitnessProgress" Name="DarkWithinWitnessObjective_t">')
) 'universal Trosky graph carries evidence contexts and witness objective'

Add-Result (
    $rumor.Contains('Role="DP_INNKEEPER_RUMOR"') -and
    $rumor.Contains('StringName="dp_mt_rumor_prompt"') -and
    $rumor.Contains('StringName="dp_mt_rumor_innkeeper_matej"')
) 'generated innkeeper dialogue uses semantic role and authored keys'
Add-Result (
    $witness.Contains('Role="DP_TAVERN_WITNESS"') -and
    $witness.Contains('StringName="dp_mt_witness_prompt"') -and
    $witness.Contains('StringName="dp_mt_witness_bretislav_point"')
) 'generated witness dialogue uses semantic role and authored keys'

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
    )
) 'generated ScriptContext table exposes both Trosky bridges'
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
        $localization.Text.Contains('<Cell>dp_mt_witness_prompt</Cell>') -and
        $localization.Text.Contains('<Cell>dp_mt_ledger_content</Cell>') -and
        $localization.Text.Contains('&lt;p&gt;')
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
