$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$caseRuntimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcasecontent.lua'
$belongingsPath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpbelongings.lua'
$bridgePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\darkpassengertest.lua'
$lifecyclePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpcaselifecycle.lua'
$variantCatalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'

Import-Module $compilerPath -Force

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

$caseSpecs = @(
    [pscustomobject]@{
        code = 2001
        id = 'missing_traveler'
        constraints = [pscustomobject]@{
            region = 'trosecko'
            settlement = 'zelejov'
        }
        native = [pscustomobject]@{
            contexts = [pscustomobject]@{
                rumorHeard = ''
                witnessHeard = ''
            }
        }
        evidence = @(
            [pscustomobject]@{
                id = 'torn_guest_ledger'
                kind = 'document'
                role = 'document'
                item = [pscustomobject]@{
                    classification = 'quest'
                    retention = 'case'
                }
            }
        )
    }
)
$bindings = [pscustomobject]@{
    settlements = @(
        [pscustomobject]@{
            region = 'trosecko'
            settlement = 'zelejov'
            roles = [pscustomobject]@{
                document = [pscustomobject]@{
                    documentGuid = 'd5833fd4-f7bf-4957-86f5-d661db38bcf3'
                    containerGuid = 'aaf89994-e94b-0309'
                }
            }
        }
    )
}
$signals = @(Get-DpQuestItemPlacementSignals `
    -CaseSpecs $caseSpecs `
    -Bindings $bindings `
    -CompiledDefinitions ([pscustomobject]@{ variants = @() }))
$documentSignal = @($signals | Where-Object {
    [string]$_.item_guid -eq 'd5833fd4-f7bf-4957-86f5-d661db38bcf3'
})[0]
$nodes = ConvertTo-DpQuestItemPlacementNodesXml `
    -Signals $signals `
    -Region 'trosecko'
$catalog = ConvertTo-DpQuestItemPlacementCatalogLua -Signals $signals
$contexts = ConvertTo-DpScriptContextXml `
    -BaseXml '<database><ScriptContexts version="1"></ScriptContexts></database>' `
    -CaseSpecs $caseSpecs `
    -Signals $signals

Add-Result (
    $null -ne $documentSignal -and
    [bool]$documentSignal.is_readable_document -and
    -not [string]::IsNullOrWhiteSpace([string]$documentSignal.read_context)
) 'document quest item owns a stable native read signal'
foreach ($token in @(
    '<UseBookTrigger Name="questDocumentReadTrigger',
    '<Constant Name="Book" Value="d5833fd4-f7bf-4957-86f5-d661db38bcf3" />',
    '.OnLastPageTurned" To="SetTrue"',
    '<SetEntityContext Name="questDocumentReadRequest',
    [string]$documentSignal.read_context
)) {
    Add-Result ($nodes.Contains($token)) "native read graph contains $token"
}
Add-Result (
    $contexts.Contains(
        "Name=`"$([string]$documentSignal.read_context)`" Class=`"Entity`""
    )
) 'document read ScriptContext is registered'
Add-Result (
    $catalog.Contains('item_guid =') -and
    $catalog.Contains('read_context =')
) 'Lua placement catalog exposes document identity and read context'

$caseRuntime = [System.IO.File]::ReadAllText($caseRuntimePath)
foreach ($token in @(
    'CASE_REPLAY_COOLDOWN_GENERATIONS',
    'function DarkPassengerCaseContent.ReadReplayHistory',
    'function DarkPassengerCaseContent.GetStoryReplayWeight',
    'unplayed',
    'immediate_repeat',
    'PersistStoryPlayed('
)) {
    Add-Result ($caseRuntime.Contains($token)) `
        "case runtime contains replay contract $token"
}

$belongings = [System.IO.File]::ReadAllText($belongingsPath)
Add-Result (
    $belongings.Contains(
        'function DarkPassengerBelongings.OnDocumentRead('
    ) -and
    -not $belongings.Contains('Minigame.WasBookOpened(')
) 'evidence advances from a per-read native event, not global book history'

$bridge = [System.IO.File]::ReadAllText($bridgePath)
Add-Result (
    $bridge.Contains('lastDocumentReadStates') -and
    $bridge.Contains('entry.read_context') -and
    $bridge.Contains('DarkPassengerBelongings.OnDocumentRead(')
) 'quest bridge forwards document read rising edges into generation state'

$lifecycle = if (Test-Path -LiteralPath $lifecyclePath -PathType Leaf) {
    [System.IO.File]::ReadAllText($lifecyclePath)
} else { '' }
$variantCatalog = if (
    Test-Path -LiteralPath $variantCatalogPath -PathType Leaf
) {
    [System.IO.File]::ReadAllText($variantCatalogPath)
} else { '' }
Add-Result (
    $variantCatalog.Contains('cleanup_manifest = {') -and
    $variantCatalog.Contains(
        'destination_entity_name = "stash[Chest/'
    ) -and
    $variantCatalog.Contains(
        'destination_entity_guid = "277db45d-28ac-0286"'
    ) -and
    $lifecycle.Contains('item.destination_entity_name') -and
    $lifecycle.Contains('destination.inventory')
) 'compiled world-container ownership crosses into runtime cleanup'
Add-Result (
    $variantCatalog.Contains('retention = "case"') -and
    $variantCatalog.Contains('retention = "permanent"') -and
    $lifecycle.Contains('if retention == "case" then')
) 'runtime cleanup consumes generated retention without deleting trophies'
Add-Result (
    $bridge.Contains('DarkPassengerCaseLifecycle.ClearCaseArtifacts(') -and
    $lifecycle.Contains('DarkPassengerCaseLifecycle.PrepareCaseGeneration')
) 'replacement target crosses the generated lifecycle cleanup barrier'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
