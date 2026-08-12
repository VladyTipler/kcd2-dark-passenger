$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
Import-Module $modulePath -Force

$casePath = Join-Path $repoRoot `
    'content\migration\legacy-cases\missing-traveler.case.json'
$bindingPath = Join-Path $repoRoot `
    'content\migration\legacy-case-settlement-bindings.json'
$case = [System.IO.File]::ReadAllText($casePath) |
    ConvertFrom-Json -Depth 100
$bindings = Read-DpCaseSettlementBindings -LiteralPath $bindingPath
$binding = @($bindings.settlements | Where-Object {
    $_.region -eq 'trosecko' -and $_.settlement -eq 'zelejov'
})[0]

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

function Copy-TestValue($Value) {
    return $Value | ConvertTo-Json -Depth 100 |
        ConvertFrom-Json -Depth 100
}

function New-TestScene(
    [string]$Id,
    [string]$Mode,
    [int]$Tag,
    [string]$Graph,
    [string]$FileName,
    [string]$Alias,
    [string]$Context
) {
    $scene = Copy-TestValue @($case.native.overheardScenes)[0]
    $scene.id = $Id
    $scene.qualifiedId = "courtyard-gossip/$Id"
    $scene.activation = [pscustomobject]@{ mode = $Mode }
    $pair = @($binding.roles.overheard.pairs)[0]
    $scene.speakers = [pscustomobject]@{
        speakerA = Copy-TestValue @($pair.speakers | Where-Object {
            $_.role -eq 'speakerA'
        })[0]
        speakerB = Copy-TestValue @($pair.speakers | Where-Object {
            $_.role -eq 'speakerB'
        })[0]
    }
    $scene.availableTag = $Tag
    $scene.graphName = $Graph
    $scene.fileName = $FileName
    $scene.decisionAlias = $Alias
    $scene.sequenceName = $Id
    $scene.context = $Context
    return $scene
}

$proximity = New-TestScene -Id 'proximity_probe' -Mode 'proximity' `
    -Tag 71 -Graph 'overheard_proximity_probe_dialog_t' `
    -FileName 'overheard_proximity_probe_dialog_t.xml' `
    -Alias 'darkPassenger_proximityProbe' `
    -Context 'dp_overheard_proximity_probe'
$interaction = New-TestScene -Id 'interaction_probe' -Mode 'interaction' `
    -Tag 72 -Graph 'overheard_interaction_probe_dialog_t' `
    -FileName 'overheard_interaction_probe_dialog_t.xml' `
    -Alias 'darkPassenger_interactionProbe' `
    -Context 'dp_overheard_interaction_probe'
$case.native.PSObject.Properties.Remove('overheard')
$case.native.PSObject.Properties.Remove('overheardScenes')
$case.native | Add-Member -NotePropertyName overheardScenes `
    -NotePropertyValue @($proximity, $interaction)

$errors = @(Get-DpCaseSpecValidationErrors -CaseSpec $case `
    -Bindings $bindings -SourceName 'interactive-overheard-probe.json')
Add-Result ($errors.Count -eq 0) `
    "multi-scene CaseSpec validates: $($errors -join '; ')"

$wiring = ConvertTo-DpNativeRegionWiring -CaseSpec $case -Binding $binding
$overheardDialogues = @($wiring.dialogues | Where-Object {
    $_.fileName -like '*overheard_*_probe_dialog_t.xml'
})
Add-Result (
    $overheardDialogues.Count -eq 4 -and
    @($overheardDialogues.fileName | Sort-Object -Unique).Count -eq 4
) 'compiler isolates one XML dialogue per overheard speaker pair'
Add-Result (
    $wiring.overheardNodes.Contains('overheard_proximity_probe_dialog_t') -and
    $wiring.overheardNodes.Contains('overheard_interaction_probe_dialog_t') -and
    $wiring.overheardNodes.Contains('Value="71"') -and
    $wiring.overheardNodes.Contains('Value="72"') -and
    $wiring.overheardNodes.Contains('overheardScene_proximity_probe') -and
    $wiring.overheardNodes.Contains('overheardScene_interaction_probe')
) 'quest wiring keeps scene signals and node names distinct'
Add-Result (
    ([regex]::Matches(
        $wiring.overheardNodes,
        '<Constant Name="context" Value="speech_readyForSwitchDialog" />'
    )).Count -eq 4 -and
    ([regex]::Matches(
        $wiring.overheardNodes,
        '<Asset Name="playerinarea" Alias="land" />'
    )).Count -eq 4 -and
    ([regex]::Matches(
        $wiring.overheardNodes,
        '<Constant Name="maxscheduledpriority" Value="-1" />'
    )).Count -eq 4 -and
    -not $wiring.overheardNodes.Contains(
        '<Constant Name="context" Value="-" />'
    )
) 'NPC-to-NPC scenes use the native switchdialog scheduler contract'
foreach ($dialogue in $overheardDialogues) {
    try {
        [void][xml]$dialogue.xml
        Add-Result $true "$($dialogue.fileName) is well-formed XML"
    }
    catch {
        Add-Result $false "$($dialogue.fileName) is well-formed XML"
    }
}

$tagBase = "<root>`n`t<buff_ai_tags>`n`t</buff_ai_tags>`n</root>"
$buffBase = "<root>`n`t<buffs>`n`t</buffs>`n</root>"
$tagXml = ConvertTo-DpOverheardTagXml -BaseXml $tagBase -CaseSpecs @($case)
$buffXml = ConvertTo-DpOverheardBuffXml -BaseXml $buffBase -CaseSpecs @($case)
Add-Result (
    $tagXml.Contains('buff_ai_tag_id="71"') -and
    $tagXml.Contains('buff_ai_tag_id="72"') -and
    $tagXml.Contains('dp_overheard_proximity_probe_available') -and
    $tagXml.Contains('dp_overheard_interaction_probe_available')
) 'compiler registers one deterministic tag per scene'
Add-Result (
    $buffXml.Contains('buff_ai_tag_id="71"') -and
    $buffXml.Contains('buff_ai_tag_id="72"') -and
    ([regex]::Matches($buffXml, 'is_persistent="true"')).Count -eq 2
) 'compiler registers one persistent signal buff per scene'

$catalog = ConvertTo-DpCaseCatalogLua -CaseSpecs @($case) -Bindings $bindings
Add-Result (
    $catalog.Contains('overheard_scenes = {') -and
    $catalog.Contains('id = "proximity_probe"') -and
    $catalog.Contains('activation_mode = "proximity"') -and
    $catalog.Contains('id = "interaction_probe"') -and
    $catalog.Contains('activation_mode = "interaction"')
) 'runtime catalog receives both activation modes'
Add-Result (
    $catalog.Contains('id = "inn_yard_primary"') -and
    $catalog.Contains('id = "inn_yard_fallback"')
) 'runtime catalog preserves ordered fallback speaker pairs'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host "RESULT: PASS ($($script:checks) checks)"
