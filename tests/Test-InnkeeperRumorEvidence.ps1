param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $repoRoot 'src\Data\Scripts\mods'
$interactionPath = Join-Path $scriptRoot 'dpinteractions.lua'
$evidencePath = Join-Path $scriptRoot 'dpevidence.lua'
$registryPath = Join-Path $scriptRoot 'dpevidenceregistry.lua'
$burialPath = Join-Path $scriptRoot 'dpburial.lua'
$runtimePath = Join-Path $scriptRoot 'darkpassengertest.lua'
$investigationPath = Join-Path $scriptRoot 'dpinvestigation.lua'
$plannerPath = Join-Path $scriptRoot 'dpleadplanner.lua'
$tagPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
$buffPath = Join-Path $repoRoot `
    'src\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
$questTemplatePath = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'
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

$interaction = Read-OptionalText $interactionPath
$evidence = Read-OptionalText $evidencePath
$registry = Read-OptionalText $registryPath
$burial = Read-OptionalText $burialPath
$runtime = Read-OptionalText $runtimePath
$investigation = Read-OptionalText $investigationPath
$planner = Read-OptionalText $plannerPath
$tags = Read-OptionalText $tagPath
$buffs = Read-OptionalText $buffPath
$questTemplate = Read-OptionalText $questTemplatePath
$english = Read-OptionalText $englishPath
$russian = Read-OptionalText $russianPath

Add-Result (Test-Path -LiteralPath $interactionPath) `
    'shared contextual-action registry exists'
foreach ($export in 'RegisterProvider', 'Dispatch', 'InstallActionHook', 'RunSelfTest') {
    Add-Result ($interaction.Contains("function DarkPassengerInteractions.$export")) `
        "interaction registry exports $export"
}
Add-Result (
    $interaction.Contains('local actionClassNames = { "NPC", "NPC_Female", "NPC_NAI" }') -and
    $interaction.Contains('classTable.GetActions = wrapper') -and
    $interaction.Contains('DarkPassengerInteractions._classHooks')
) 'one registry owns all live NPC action class wrappers'
Add-Result (
    $interaction.Contains('DarkPassengerInteractions.providers[name] = provider') -and
    $interaction.Contains('DarkPassengerInteractions._providerOrder')
) 'provider registration replaces named behavior without stacking'

Add-Result (
    $burial.Contains('DarkPassengerInteractions.RegisterProvider(') -and
    $burial.Contains('"burial"') -and
    -not $burial.Contains('classTable.GetActions = wrapper')
) 'burial delegates action hooking to the shared registry'

Add-Result (Test-Path -LiteralPath $evidencePath) `
    'innkeeper rumor evidence module exists'
foreach ($export in
    'Transition',
    'IsEligible',
    'OnInvestigationOpened',
    'Restore',
    'AddRumorAction',
    'OnAskRumors',
    'Status',
    'RunSelfTest'
) {
    Add-Result ($evidence.Contains("function DarkPassengerEvidence.$export")) `
        "evidence module exports $export"
}
foreach ($token in
    'DarkPassengerCaseEvidence.ResolveActive("innkeeper")',
    'resolved.binding.entityName',
    'context.expectedRegion',
    'context.expectedSettlement',
    'dp_evidence_schema_version',
    'dp_evidence_awarded_generation',
    'dp_evidence_signal_dispatched',
    'DarkPassengerCaseContent.GetSelected('
) {
    Add-Result ($evidence.Contains($token)) "evidence contract contains $token"
}
Add-Result (
    $evidence -match '(?s)EvidenceRegistry\.Discover\(.*?generation.*?selectedRumor.code.*?\).*?DispatchJournalSignal' -and
    -not $evidence.Contains('DarkPassengerInvestigation.AddEvidence(')
) 'registry discovery is persisted before the journal signal is dispatched'
Add-Result (
    $registry.Contains(
        'DarkPassengerLeadPlanner.ScheduleEvidenceTransition('
    ) -and
    $planner.Contains('function DarkPassengerLeadPlanner.Evaluate')
) 'registry owns deferred reevaluation after rumor discovery'
Add-Result (
    $evidence.Contains('Game.ShowNotification(selectedRumor.notification)') -and
    $evidence.Contains('DarkPassengerInteractions.RegisterProvider(')
) 'rumor copy resolves in Lua at action time through the shared registry'
Add-Result (
    $evidence.Contains('DEBUG_ACTION_ENABLED = false') -and
    $evidence.Contains('if not DarkPassengerEvidence.DEBUG_ACTION_ENABLED')
) 'innkeeper short-F canary action is disabled in production'

Add-Result (
    $investigation.Contains('function DarkPassengerInvestigation.GetState') -and
    $investigation.Contains('function DarkPassengerInvestigation.GetCandidate') -and
    $investigation.Contains('DarkPassengerEvidence.OnInvestigationOpened(') -and
    $investigation.Contains('DarkPassengerEvidence.Restore(')
) 'investigation exposes state and notifies evidence lifecycle'

$interactionReload = 'Script.ReloadScript("Scripts/mods/dpinteractions.lua")'
$evidenceReload = 'Script.ReloadScript("Scripts/mods/dpevidence.lua")'
$plannerReload = 'Script.ReloadScript("Scripts/mods/dpleadplanner.lua")'
$burialReload = 'Script.ReloadScript("Scripts/mods/dpburial.lua")'
$interactionIndex = $runtime.IndexOf($interactionReload)
$evidenceIndex = $runtime.IndexOf($evidenceReload)
$burialIndex = $runtime.IndexOf($burialReload)
Add-Result (
    $interactionIndex -ge 0 -and
    $runtime.IndexOf($plannerReload) -ge 0 -and
    $runtime.IndexOf($plannerReload) -lt $evidenceIndex -and
    $evidenceIndex -gt $interactionIndex -and
    $burialIndex -gt $interactionIndex
) 'runtime loads registry before both interaction providers'

[xml]$tagXml = $tags
[xml]$buffXml = $buffs
$leadTag = @($tagXml.database.buff_ai_tags.buff_ai_tag) |
    Where-Object { $_.buff_ai_tag_id -eq '31' }
$leadBuff = @($buffXml.database.buffs.buff) |
    Where-Object { $_.buff_name -eq 'dp_evidence_first_lead' }
Add-Result (
    @($leadTag).Count -eq 1 -and
    $leadTag.buff_ai_tag_name -eq 'dp_evidence_first_lead'
) 'tag 31 is reserved for the generic first-lead signal'
Add-Result (
    @($leadBuff).Count -eq 1 -and
    $leadBuff.buff_ai_tag_id -eq '31' -and
    $leadBuff.buff_id -eq '6e532a34-ce2b-47ae-9427-c67a4a1b94b1' -and
    $leadBuff.buff_ui_visibility_id -eq '0' -and
    $leadBuff.is_persistent -eq 'true'
) 'hidden persistent first-lead buff carries tag 31'

foreach ($fragment in
    '<Constant Name="A" Value="31" />',
    '<BuffTagTrigger Name="firstLeadTrigger">',
    '<State Name="evidenceProgress" TypeT="{{DP_EVIDENCE_PROGRESS_TYPE}}">',
    '{{DP_EVIDENCE_STATE_NODES}}',
    '{{DP_EVIDENCE_STATE_EDGES}}',
    '{{DP_EVIDENCE_RESET_PORT}}',
    '<Type TypeName="{{DP_EVIDENCE_PROGRESS_TYPE}}">',
    '<Objective TypeT="{{DP_EVIDENCE_PROGRESS_TYPE}}" Name="{{DP_EVIDENCE_OBJECTIVE_NAME}}">',
    '{{DP_CLEANUP_PROGRESS_TYPE}}',
    '{{DP_EVIDENCE_TYPE_ENUMS}}',
    '{{DP_EVIDENCE_LOGS}}'
) {
    Add-Result ($questTemplate.Contains($fragment)) `
        "quest template contains generated evidence-state contract: $fragment"
}
Add-Result (
    -not $questTemplate.Contains('<Edge From="firstLeadTrigger.OnAdded" To="SetFirstLead" />')
) 'quest template no longer hardcodes one linear first-lead transition'
Add-Result (
    $questTemplate.Contains('{{DP_EVIDENCE_DONE_EDGE}}')
) 'victim reveal completes evidence gathering without replacing area tracking'

foreach ($key in
    'dp_evidence_ask_rumors',
    'dark_within_evidence_name',
    'dark_within_evidence_first_lead'
) {
    Add-Result (
        $english.Contains("<Cell>$key</Cell>") -and
        $russian.Contains("<Cell>$key</Cell>")
    ) "localization parity contains $key"
}

if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
    $compiler = Join-Path $DevGameRoot 'Bin\Win64SharedPrivate\LuaCompiler.exe'
    Add-Result (Test-Path -LiteralPath $compiler) 'LuaCompiler is available'
    if ((Test-Path -LiteralPath $compiler) -and
        (Test-Path -LiteralPath $interactionPath) -and
        (Test-Path -LiteralPath $evidencePath)) {
        & $compiler -p $interactionPath *> $null
        $interactionExit = $LASTEXITCODE
        & $compiler -p $evidencePath *> $null
        $evidenceExit = $LASTEXITCODE
        Add-Result (
            $interactionExit -eq 0 -and $evidenceExit -eq 0
        ) 'new Lua modules pass LuaCompiler'
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
