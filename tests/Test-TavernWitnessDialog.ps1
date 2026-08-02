param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dialogPath = Join-Path $repoRoot `
    'build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k\tavern_witness_dialog_k.xml'
$generatedQuestPath = Join-Path $repoRoot `
    'build\mod\Data\Quests\Final\Barbora\kutnohorsko\dark_within_k.xml'
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpwitnesslead.lua'
$initPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$belongingsPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpbelongings.lua'
$stormRolesPath = Join-Path $repoRoot `
    'src\Data\Libs\Storm\roles\quests\darkpassengertest.xml'
$roleTablePath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\role__darkpassengertest.xml'
$contextPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml'
$buffTagPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
$buffPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
$templatePath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'
$generatorPath = Join-Path $repoRoot 'tools\Generate-VictimArtifacts.ps1'
$englishPath = Join-Path $repoRoot `
    'localization\English\text__darkpassengertest.xml'
$russianPath = Join-Path $repoRoot `
    'localization\Russian\text__darkpassengertest.xml'

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

$dialog = Read-OptionalText $dialogPath
$generatedQuest = Read-OptionalText $generatedQuestPath
$runtime = Read-OptionalText $runtimePath
$init = Read-OptionalText $initPath
$belongings = Read-OptionalText $belongingsPath
$stormRoles = Read-OptionalText $stormRolesPath
$roles = Read-OptionalText $roleTablePath
$contexts = Read-OptionalText $contextPath
$buffTags = Read-OptionalText $buffTagPath
$buffs = Read-OptionalText $buffPath
$template = Read-OptionalText $templatePath
$generator = Read-OptionalText $generatorPath
$english = Read-OptionalText $englishPath
$russian = Read-OptionalText $russianPath

Add-Result (Test-Path -LiteralPath $runtimePath) `
    'reusable tavern-witness runtime exists'
Add-Result (Test-Path -LiteralPath $dialogPath) `
    'native tavern-witness FaderDialog exists'

Add-Result (
    $stormRoles.Contains('<hasName name="kpri_woman_10" />') -and
    $stormRoles.Contains('<addRole name="DP_TAVERN_WITNESS" />')
) 'Storm assigns the canary role only to the Pritoky inn worker'
Add-Result (
    $roles.Contains('role_id="5fa9523d-330b-42a1-8b04-1fd7fe5fb84b"') -and
    $roles.Contains('role_name="DP_TAVERN_WITNESS"') -and
    $roles.Contains('metarole_name="NPC"')
) 'tavern-witness NPC role is registered'

Add-Result (
    $buffTags.Contains(
        'buff_ai_tag_id="36" buff_ai_tag_name="dp_tavern_witness_available"'
    )
) 'tag 36 is reserved for tavern-witness availability'
Add-Result (
    $buffs.Contains(
        'buff_id="a823ebb8-f3e3-4437-b885-9fafea591858"'
    ) -and
    $buffs.Contains('buff_name="dp_tavern_witness_available"') -and
    $buffs.Contains('buff_ai_tag_id="36"') -and
    $buffs.Contains('buff_ui_visibility_id="0"')
) 'hidden persistent buff carries tavern-witness availability'
Add-Result (
    $contexts.Contains(
        'Name="dp_witness_heard_kutnohorsko" Class="Entity"'
    )
) 'witness completion ScriptContext is registered'

foreach ($fragment in
    '<FaderDialog Name="tavern_witness_dialog_k">',
    '<Port Name="available" Direction="In" Type="bool">',
    '<Port Name="heard" Direction="Out" Type="trigger">',
    '<Sequence EndType="EndDialogue" EntryCondition="Port(''available'')"',
    '<UiPrompt StringName="dp_witness_ask_vojtech"',
    '<Port Name="heard" />',
    'Role="HENRY"',
    'Role="DP_TAVERN_WITNESS"'
) {
    Add-Result ($dialog.Contains($fragment)) `
        "witness FaderDialog contains $fragment"
}
Add-Result (
    -not $dialog.Contains('<Audio') -and
    -not $dialog.Contains('<Sound')
) 'witness dialogue has no custom audio dependency'

$dialogKeys = @(
    'dp_witness_henry_working',
    'dp_witness_maid_many_nights',
    'dp_witness_henry_letter',
    'dp_witness_maid_fool',
    'dp_witness_henry_dead',
    'dp_witness_maid_stream',
    'dp_witness_henry_heard',
    'dp_witness_maid_threat',
    'dp_witness_henry_who',
    'dp_witness_maid_name',
    'dp_witness_henry_where',
    'dp_witness_maid_location'
)
foreach ($key in $dialogKeys) {
    Add-Result ($dialog.Contains("StringName=`"$key`"")) `
        "witness dialogue uses authored line $key"
}

$localizedKeys = @(
    'dp_witness_dialog_root',
    'dp_witness_ask_vojtech',
    'dark_within_witness_name',
    'dark_within_witness_active',
    'dark_within_witness_done'
) + $dialogKeys
foreach ($key in $localizedKeys) {
    Add-Result (
        $english.Contains("<Cell>$key</Cell>") -and
        $russian.Contains("<Cell>$key</Cell>")
    ) "witness localization parity contains $key"
}
Add-Result (
    $russian.Contains('У воды ноги скользят даже у трезвых') -and
    $russian.Contains('мы никогда не разговаривали')
) 'Russian localization contains the approved threat and closing line'
Add-Result (
    $english.Contains('Even sober men lose their footing by the water') -and
    $english.Contains('we never spoke')
) 'English localization contains the approved threat and closing line'

foreach ($token in
    'SCHEMA_VERSION',
    'DarkPassengerCaseEvidence.ResolveActive("witness")',
    'resolved.evidence.id',
    'resolved.evidence.confidence',
    'AVAILABLE_BUFF_GUID = "a823ebb8-f3e3-4437-b885-9fafea591858"',
    'function DarkPassengerWitnessLead.Transition',
    'function DarkPassengerWitnessLead.Start',
    'function DarkPassengerWitnessLead.Restore',
    'function DarkPassengerWitnessLead.OnDialogueCompleted',
    'DarkPassengerInvestigation.AddEvidence('
) {
    Add-Result ($runtime.Contains($token)) `
        "witness runtime contains $token"
}
Add-Result (
    $runtime.Contains('availableGeneration') -and
    $runtime.Contains('awardedGeneration') -and
    $runtime.Contains('already_awarded')
) 'witness runtime persists generation-scoped one-shot state'

$leadReload = 'Script.ReloadScript("Scripts/mods/dpwitnesslead.lua")'
$belongingsReload = 'Script.ReloadScript("Scripts/mods/dpbelongings.lua")'
Add-Result (
    $init.IndexOf($leadReload) -ge 0 -and
    $init.IndexOf($leadReload) -lt $init.IndexOf($belongingsReload)
) 'mod init loads witness lead before the document producer'
Add-Result (
    $belongings.Contains('DarkPassengerWitnessLead.Start(') -and
    $belongings.Contains('DarkPassengerWitnessLead.Restore(')
) 'accepted and restored document reads drive witness availability'
Add-Result (
    $init.Contains('witnessContext = "dp_witness_heard_kutnohorsko"') -and
    $init.Contains('DarkPassengerWitnessLead.OnDialogueCompleted(')
) 'quest bridge forwards witness ScriptContext to the Lua ledger'

foreach ($placeholder in
    '{{DP_WITNESS_NODES}}',
    '{{DP_EVIDENCE_WITNESS_EDGE}}',
    '{{DP_WITNESS_OBJECTIVE_NODES}}',
    '{{DP_WITNESS_TYPE}}',
    '{{DP_WITNESS_OBJECTIVE}}'
) {
    Add-Result ($template.Contains($placeholder)) `
        "quest template exposes witness slot $placeholder"
    Add-Result ($generator.Contains($placeholder)) `
        "quest generator resolves witness slot $placeholder"
}
foreach ($fragment in
    'tavern_witness_dialog_k.xml',
    '<Constant Name="A" Value="36" />',
    '<BuffTagTrigger Name="witnessAvailableTrigger">',
    '<tavern_witness_dialog_k Name="tavernWitnessDialog">',
    '<Constant Name="Context" Value="dp_witness_heard_kutnohorsko" />',
    'TypeT="DP_WitnessProgress"',
    'StringName="dark_within_witness_name"'
) {
    Add-Result ($generatedQuest.Contains($fragment)) `
        "generated quest contains witness boundary: $fragment"
}

foreach ($xmlPath in
    $dialogPath,
    $stormRolesPath,
    $roleTablePath,
    $contextPath,
    $buffTagPath,
    $buffPath,
    $englishPath,
    $russianPath
) {
    if (Test-Path -LiteralPath $xmlPath) {
        try {
            [xml](Get-Content -Raw -LiteralPath $xmlPath) | Out-Null
            Add-Result $true "XML parses: $(Split-Path -Leaf $xmlPath)"
        }
        catch {
            Add-Result $false "XML parses: $(Split-Path -Leaf $xmlPath)"
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot `
        'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    if ((Test-Path -LiteralPath $compiler) -and
        (Test-Path -LiteralPath $runtimePath)) {
        & $compiler -p $runtimePath *> $null
        Add-Result ($LASTEXITCODE -eq 0) `
            'tavern-witness runtime passes LuaCompiler'
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
