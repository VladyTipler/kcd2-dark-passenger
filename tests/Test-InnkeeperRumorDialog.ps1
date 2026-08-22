param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$dialogPath = Join-Path $repoRoot `
    'build\mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k\innkeeper_rumor_dialog_k.xml'
$generatedQuestPath = Join-Path $repoRoot `
    'build\mod\Data\Quests\Final\Barbora\kutnohorsko\dark_within_k.xml'
$missingTravelerDialogPath = Join-Path $repoRoot `
    'build\mod\Data\Quests\darkpassengertest\trosecko\dark_within_t\dpcase2001_trosecko_troskovice_innkeeper_missing_traveler_dialog_t.xml'
$missingTravelerQuestPath = Join-Path $repoRoot `
    'build\mod\Data\Quests\Final\Barbora\trosecko\dark_within_t.xml'
$questTemplatePath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'
$generatorPath = Join-Path $repoRoot 'tools\Generate-VictimArtifacts.ps1'
$stormIndexPath = Join-Path $repoRoot `
    'src\Data\Libs\Storm\storm__darkpassengertest.xml'
$stormRolesPath = Join-Path $repoRoot `
    'src\Data\Libs\Storm\roles\quests\darkpassengertest.xml'
$roleTablePath = Join-Path $repoRoot `
    'build\mod\Data\Libs\Tables\rpg\role__darkpassengertest.xml'
$contextPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml'
$buffTagPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
$buffPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$evidencePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpevidence.lua'
$plannerPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpleadplanner.lua'
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
$missingTravelerDialog = Read-OptionalText $missingTravelerDialogPath
$missingTravelerQuest = Read-OptionalText $missingTravelerQuestPath
$questTemplate = Read-OptionalText $questTemplatePath
$generator = Read-OptionalText $generatorPath
$stormIndex = Read-OptionalText $stormIndexPath
$stormRoles = Read-OptionalText $stormRolesPath
$roles = Read-OptionalText $roleTablePath
$contexts = Read-OptionalText $contextPath
$buffTags = Read-OptionalText $buffTagPath
$buffs = Read-OptionalText $buffPath
$runtime = Read-OptionalText $runtimePath
$evidence = Read-OptionalText $evidencePath
$planner = Read-OptionalText $plannerPath
$english = Read-OptionalText $englishPath
$russian = Read-OptionalText $russianPath

foreach ($path in $dialogPath, $stormIndexPath, $stormRolesPath, $roleTablePath) {
    Add-Result (Test-Path -LiteralPath $path) `
        "native dialogue asset exists: $(Split-Path -Leaf $path)"
}

Add-Result (
    $stormIndex.Contains('roles\quests\darkpassengertest.xml') -and
    $stormRoles.Contains('<hasName name="kpri_innkeeper" />') -and
    $stormRoles.Contains('<addRole name="DP_INNKEEPER_RUMOR" />')
) 'Storm assigns only the Pritoky innkeeper to the custom dialogue role'
Add-Result (
    $roles.Contains('role_name="DP_ACTOR_A33CABA8146814E9E07126F9"') -and
    $roles.Contains('metarole_name="NPC"')
) 'generated Troskovice innkeeper role is registered as an NPC role'

foreach ($fragment in
    '<FaderDialog Name="innkeeper_rumor_dialog_k">',
    '<Port Name="available" Direction="In" Type="bool">',
    '<Port Name="heard" Direction="Out" Type="trigger">',
    '<Sequence EndType="EndDialogue" EntryCondition="Port(''available'')"',
    '<UiPrompt StringName="dp_evidence_ask_unease"',
    '<Port Name="heard" />',
    'Role="HENRY"',
    'Role="DP_INNKEEPER_RUMOR"'
) {
    Add-Result ($dialog.Contains($fragment)) `
        "FaderDialog contains $fragment"
}

$dialogLineKeys = @(
    'dp_rumor_henry_unease',
    'dp_rumor_innkeeper_fear',
    'dp_rumor_henry_why',
    'dp_rumor_innkeeper_vojtech',
    'dp_rumor_henry_threat',
    'dp_rumor_innkeeper_refusal',
    'dp_rumor_henry_what_to_seek',
    'dp_rumor_innkeeper_belongings'
)
foreach ($key in $dialogLineKeys) {
    Add-Result ($dialog.Contains("StringName=`"$key`"")) `
        "dialogue uses authored line $key"
}

foreach ($fragment in
    '{{DP_RUMOR_DIALOG_DEFINITION}}',
    '{{DP_RUMOR_DIALOG_NODES}}'
) {
    Add-Result ($questTemplate.Contains($fragment)) `
        "quest template exposes regional dialogue slot $fragment"
    Add-Result ($generator.Contains("'$fragment'")) `
        "quest generator resolves regional dialogue slot $fragment"
}
Add-Result (
    $generator.Contains('NativeWiringPath') -and
    $generator.Contains('NativeWiring.dialogueFiles') -and
    -not $generator.Contains('KuttenbergRumorDialogSourcePath')
) 'quest generator consumes compiled native dialogue wiring'

foreach ($fragment in
    '<Constant Name="A" Value="32" />',
    '<BuffTagTrigger Name="case1001_rumorAvailableTrigger">',
    '<dpcase1001_kutnohorsko_pritoky_innkeeper_rumor_dialog_k Name="case1001_pritokyInnkeeperRumorDialog">',
    '<Edge From="case1001_pritokyRumorAvailable.State" To="available" />',
    '<SetEntityContext Name="case1001_rumorDialogueRequest">',
    '<Constant Name="Context" Value="dp_rumor_heard_kutnohorsko" />'
) {
    Add-Result (
        $generatedQuest.Contains($fragment)
    ) "quest graph contains native rumor boundary: $fragment"
}

Add-Result (
    $contexts.Contains('Name="dp_rumor_heard_kutnohorsko" Class="Entity"')
) 'dialogue completion ScriptContext is registered'
Add-Result (
    $buffTags.Contains(
        'buff_ai_tag_id="32" buff_ai_tag_name="dp_evidence_rumor_available"'
    )
) 'tag 32 is reserved for native rumor availability'
Add-Result (
    $buffs.Contains('buff_name="dp_evidence_rumor_available"') -and
    $buffs.Contains('buff_ai_tag_id="32"') -and
    $buffs.Contains('buff_ui_visibility_id="0"')
) 'hidden persistent buff carries native rumor availability'

Add-Result (
    $runtime.Contains('rumorContext = "dp_rumor_heard_kutnohorsko"') -and
    $runtime.Contains('DarkPassengerEvidence.OnRumorCompleted(')
) 'existing polling bridge forwards the dialogue rising edge to evidence'
Add-Result (
    $evidence.Contains('function DarkPassengerEvidence.OnRumorCompleted') -and
    $evidence.Contains('RUMOR_AVAILABLE_BUFF_GUID') -and
    $evidence.Contains('DEBUG_ACTION_ENABLED = false')
) 'evidence owns idempotent completion with the canary fallback disabled'
Add-Result (
    $missingTravelerDialog.Contains('variant_unread_ledger') -and
    $missingTravelerDialog.Contains('variant_ledger_discovered') -and
    $missingTravelerDialog.Contains('dp_mt_rumor_found_henry_hand') -and
    $missingTravelerDialog.Contains('dp_mt_rumor_found_innkeeper_boguslav') -and
    ([regex]::Matches(
        $missingTravelerDialog,
        '<Port Name="heard" />'
    )).Count -eq 2
) 'early-ledger and ordinary copy converge on one native completion port'
Add-Result (
    $missingTravelerQuest.Contains('rumorVariant0Trigger') -and
    $missingTravelerQuest.Contains('rumorVariant1Trigger') -and
    $planner.Contains('function DarkPassengerLeadPlanner.SelectDialogueVariants') -and
    $planner.Contains('function DarkPassengerLeadPlanner.PublishDialogueVariants') -and
    $planner.Contains('all_discovered_codes') -and
    $planner.Contains('all_undiscovered_codes')
) 'Lua selects a compiled dialogue variant and the graph only renders it'

foreach ($key in @('dp_evidence_dialog_root', 'dp_evidence_ask_unease') +
    $dialogLineKeys) {
    Add-Result (
        $english.Contains("<Cell>$key</Cell>") -and
        $russian.Contains("<Cell>$key</Cell>")
    ) "dialogue localization parity contains $key"
}

foreach ($xmlPath in
    $dialogPath,
    $stormIndexPath,
    $stormRolesPath,
    $roleTablePath,
    $contextPath,
    $buffTagPath,
    $buffPath
) {
    if (Test-Path -LiteralPath $xmlPath) {
        try {
            [xml](Get-Content -Raw -LiteralPath $xmlPath) | Out-Null
            Add-Result $true "XML parses: $(Split-Path -Leaf $xmlPath)"
        } catch {
            Add-Result $false "XML parses: $(Split-Path -Leaf $xmlPath)"
        }
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
