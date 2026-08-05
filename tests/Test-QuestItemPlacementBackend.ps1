$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$runtimePath = Join-Path $repoRoot `
    'src\Data\Scripts\mods\dpquestitemplacement.lua'
$compileScriptPath = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'

Import-Module $modulePath -Force

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
        constraints = [pscustomobject]@{
            region = 'kutnohorsko'
            settlement = 'pritoky'
        }
        evidence = @(
            [pscustomobject]@{
                id = 'quest_document'
                kind = 'document'
                role = 'document'
                item = [pscustomobject]@{
                    classification = 'quest'
                    retention = 'case'
                }
            },
            [pscustomobject]@{
                id = 'loot_weapon'
                item = [pscustomobject]@{
                    classification = 'loot'
                    retention = 'case'
                }
            }
        )
    }
)
$bindings = [pscustomobject]@{
    settlements = @(
        [pscustomobject]@{
            region = 'kutnohorsko'
            settlement = 'pritoky'
            roles = [pscustomobject]@{
                document = [pscustomobject]@{
                    documentGuid = '73762008-de9b-4c42-b509-235e63e60840'
                    containerGuid = '277db45d-28ac-0286'
                }
            }
        }
    )
}
$compiledDefinitions = [pscustomobject]@{
    variants = @(
        [pscustomobject]@{
            variantId = 'fixture.variant'
            trophyDefinition = [pscustomobject]@{
                preset = 'bird-feather'
                description = [pscustomobject]@{ ru = 'ru'; en = 'en' }
                item = [pscustomobject]@{
                    classification = 'quest'
                    retention = 'permanent'
                    weight = 0
                }
            }
        }
    )
}

$signals = @(Get-DpQuestItemPlacementSignals `
    -CaseSpecs $caseSpecs `
    -Bindings $bindings `
    -CompiledDefinitions $compiledDefinitions)

Add-Result ($signals.Count -eq 2) `
    'one signal is emitted per unique quest item and loot is excluded'
Add-Result (
    @($signals.item_guid) -contains '73762008-de9b-4c42-b509-235e63e60840'
) 'quest evidence document is included'
Add-Result (
    @($signals.item_guid) -notcontains 'loot_weapon'
) 'ordinary loot does not consume native quest-item graph nodes'
Add-Result (
    @($signals | Where-Object {
        $_.item_guid -eq '73762008-de9b-4c42-b509-235e63e60840' -and
        $_.backend -eq 'quest_effect_stash' -and
        @($_.stash_bindings).Count -eq 1 -and
        $_.stash_bindings[0].region -eq 'kutnohorsko' -and
        $_.stash_bindings[0].settlement -eq 'pritoky' -and
        $_.stash_bindings[0].container_guid -eq '277db45d-28ac-0286' -and
        $_.stash_bindings[0].stash_alias -eq
            'DP_EvidenceStash_kutnohorsko_pritoky'
    }).Count -eq 1
) 'quest document compiles to a concrete regional stash binding'
Add-Result (
    @($signals.signal_tag | Sort-Object -Unique).Count -eq $signals.Count -and
    (@($signals | ForEach-Object { [int]$_.signal_tag }) |
        Measure-Object -Minimum).Minimum -ge 130
) 'placement signals use unique reserved tags'

$highItemEvidence = @(
    1..130 | ForEach-Object {
        [pscustomobject]@{
            id = "high_id_probe_$_"
            item = [pscustomobject]@{
                guid = ('00000000-0000-0000-0000-{0:d12}' -f $_)
                classification = 'quest'
                retention = 'case'
            }
        }
    }
)
$highSignals = @(Get-DpQuestItemPlacementSignals `
    -CaseSpecs @([pscustomobject]@{
        constraints = [pscustomobject]@{
            region = 'kutnohorsko'
            settlement = 'pritoky'
        }
        evidence = $highItemEvidence
    }) `
    -Bindings $bindings `
    -CompiledDefinitions ([pscustomobject]@{ variants = @() }))
Add-Result (
    $highSignals.Count -eq 130 -and
    (@($highSignals | ForEach-Object { [int]$_.signal_tag }) |
        Measure-Object -Maximum).Maximum -gt 255
) 'compiler supports a synthetic quest-item signal set beyond id 255'

$baseTags = @'
<database><buff_ai_tags>
</buff_ai_tags></database>
'@
$baseBuffs = @'
<database><buffs>
</buffs></database>
'@
$tagXml = ConvertTo-DpQuestItemPlacementTagXml `
    -BaseXml $baseTags `
    -Signals $signals
$buffXml = ConvertTo-DpQuestItemPlacementBuffXml `
    -BaseXml $baseBuffs `
    -Signals $signals
$nodes = ConvertTo-DpQuestItemPlacementNodesXml `
    -Signals $signals `
    -Region 'kutnohorsko'
$assets = ConvertTo-DpQuestItemPlacementAssetsXml `
    -Signals $signals `
    -Region 'kutnohorsko'
$catalog = ConvertTo-DpQuestItemPlacementCatalogLua -Signals $signals
$baseQuestItemCatalog = @'
-- Generated from authoritative KCD2 item tables. Do not edit.
DarkPassengerQuestItemCatalog = {
    ["11111111-1111-1111-1111-111111111111"] = true,
}
'@
$mergedQuestItemCatalog = Merge-DpQuestItemCatalogLua `
    -BaseCatalog $baseQuestItemCatalog `
    -Signals $signals

Add-Result (
    ([regex]::Matches($tagXml, '<buff_ai_tag ')).Count -eq 2
) 'quest-item tags are generated once'
Add-Result (
    ([regex]::Matches($buffXml, '<buff ')).Count -eq 2 -and
    $buffXml.Contains('buff_ui_visibility_id="0"') -and
    $buffXml.Contains('is_persistent="false"')
) 'hidden transient request buffs are generated once'
Add-Result (
    ([regex]::Matches($nodes, '<AddQuestItem ')).Count -eq 1 -and
    $nodes.Contains(
        '<Constant Name="ItemClassGUID" Value="73762008-de9b-4c42-b509-235e63e60840" />'
    ) -and
    $nodes.Contains(
        '<Asset Name="BackupLocation" Alias="DP_EvidenceStash_kutnohorsko_pritoky" />'
    ) -and
    $nodes.Contains(
        '<Asset Name="StartingLocation" Alias="DP_EvidenceStash_kutnohorsko_pritoky" />'
    ) -and
    -not $nodes.Contains('<AddStashDefaultItem ') -and
    ([regex]::Matches($nodes, 'MethodName="CreateItems"')).Count -eq 1
) 'quest documents use AddQuestItem while non-stash items keep their backend'
Add-Result (
    $assets.Contains(
        '<StashAsset Name="DP_EvidenceStash_kutnohorsko_pritoky" />'
    ) -and
    ([regex]::Matches($assets, '<StashAsset ')).Count -eq 1
) 'regional quest assets declare every generated evidence stash alias once'
Add-Result (
    $catalog.Contains('DarkPassengerQuestItemPlacementCatalog') -and
    $catalog.Contains('73762008-de9b-4c42-b509-235e63e60840') -and
    $catalog.Contains('backend = "quest_effect_stash"')
) 'Lua placement catalog maps item classes to native request buffs'
Add-Result (
    $mergedQuestItemCatalog.Contains(
        '11111111-1111-1111-1111-111111111111'
    ) -and
    @($signals | Where-Object {
        $mergedQuestItemCatalog.Contains([string]$_.item_guid)
    }).Count -eq $signals.Count -and
    ([regex]::Matches($mergedQuestItemCatalog, '= true')).Count -eq 3
) 'burial quest-item catalog merges native generated item classes'

$runtime = if (Test-Path -LiteralPath $runtimePath) {
    [System.IO.File]::ReadAllText($runtimePath)
} else { '' }
Add-Result (Test-Path -LiteralPath $runtimePath -PathType Leaf) `
    'quest-item placement runtime exists'
Add-Result (
    $runtime.Contains('function DarkPassengerQuestItemPlacement.Request(') -and
    $runtime.Contains('MoveItemOfClass(') -and
    $runtime.Contains('soul:AddBuff(') -and
    $runtime.Contains('entry.backend == "quest_effect_stash"') -and
    -not $runtime.Contains('inventory:CreateItem(')
) 'Lua requests stash defaults without moving documents through player inventory'
Add-Result (
    $runtime.Contains('soul:RemoveAllBuffsByGuid(entry.buff_guid)') -and
    -not $runtime.Contains('soul:RemoveBuff(entry.buff_guid)')
) 'request cleanup removes transient buffs by definition guid'
$compileScript = [System.IO.File]::ReadAllText($compileScriptPath)
Add-Result (
    $compileScript.Contains('dp_quest_item_placement_catalog.lua') -and
    $compileScript.Contains('ConvertTo-DpQuestItemPlacementNodesXml') -and
    $compileScript.Contains('ConvertTo-DpQuestItemPlacementAssetsXml') -and
    $compileScript.Contains('questItemPlacementAssets') -and
    $compileScript.Contains('Merge-DpQuestItemCatalogLua')
) 'production compiler emits the generated placement catalog and graph nodes'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
