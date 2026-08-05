param(
    [string]$CaseVariantRoot,
    [string]$CaseRoot,
    [string]$BindingPath,
    [string]$LocalizationRoot,
    [string]$BuildRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$compiledDefinitionsPath = $null
if (-not [string]::IsNullOrWhiteSpace($CaseVariantRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($CaseRoot) -or
        -not [string]::IsNullOrWhiteSpace($BindingPath)) {
        throw 'CaseVariantRoot cannot be combined with CaseRoot or BindingPath.'
    }
    $manifestPath = Join-Path $CaseVariantRoot 'casekit-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "CaseVariantRoot manifest not found: $manifestPath"
    }
    $manifest = [System.IO.File]::ReadAllText($manifestPath) |
        ConvertFrom-Json -Depth 100
    if ([int]$manifest.schemaVersion -ne 1 -or
        [string]$manifest.sourceFormat -ne
            'casekit-kcd2-compiler-input-v1') {
        throw "Unsupported CaseVariantRoot contract: $manifestPath"
    }
    $CaseRoot = Join-Path $CaseVariantRoot ([string]$manifest.caseRoot)
    $BindingPath = Join-Path $CaseVariantRoot ([string]$manifest.bindingFile)
    if (-not [string]::IsNullOrWhiteSpace(
        [string]$manifest.compiledDefinitionsFile
    )) {
        $compiledDefinitionsPath = Join-Path $CaseVariantRoot `
            ([string]$manifest.compiledDefinitionsFile)
    }
}
else {
    if ([string]::IsNullOrWhiteSpace($CaseRoot) -or
        [string]::IsNullOrWhiteSpace($BindingPath)) {
        throw 'Pass CaseVariantRoot or both CaseRoot and BindingPath.'
    }
}
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    $BuildRoot = Join-Path $repoRoot 'build'
}
if ([string]::IsNullOrWhiteSpace($LocalizationRoot)) {
    $LocalizationRoot = Join-Path $repoRoot 'localization'
}

$modulePath = Join-Path $PSScriptRoot 'CaseSpecCompiler.psm1'
Import-Module $modulePath -Force

$cases = @(Get-DpValidatedCaseSpecs `
    -CaseRoot $CaseRoot `
    -BindingPath $BindingPath)
$bindings = Read-DpCaseSettlementBindings -LiteralPath $BindingPath

$catalogPath = Join-Path $BuildRoot `
    'mod\Data\Scripts\mods\generated\dp_case_catalog.lua'
$variantCatalogPath = Join-Path $BuildRoot `
    'mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'
$questItemPlacementCatalogPath = Join-Path $BuildRoot `
    'mod\Data\Scripts\mods\generated\dp_quest_item_placement_catalog.lua'
$questItemCatalogPath = Join-Path $BuildRoot `
    'mod\Data\Scripts\mods\generated\dp_quest_item_catalog.lua'
$reportPath = Join-Path $BuildRoot `
    'generated\cases\case-compatibility.json'
$nativeManifestPath = Join-Path $BuildRoot `
    'generated\cases\native-wiring.json'
$generatedLocalizationRoot = Join-Path $BuildRoot `
    'generated\localization'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

foreach ($parent in @(
    (Split-Path -Parent $catalogPath),
    (Split-Path -Parent $reportPath),
    (Split-Path -Parent $nativeManifestPath),
    (Join-Path $generatedLocalizationRoot 'English'),
    (Join-Path $generatedLocalizationRoot 'Russian')
)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$catalog = ConvertTo-DpCaseCatalogLua `
    -CaseSpecs $cases `
    -Bindings $bindings
$compiledDefinitions = if (
    -not [string]::IsNullOrWhiteSpace($compiledDefinitionsPath) -and
    (Test-Path -LiteralPath $compiledDefinitionsPath -PathType Leaf)
) {
    [System.IO.File]::ReadAllText($compiledDefinitionsPath) |
        ConvertFrom-Json -Depth 100
}
else {
    [pscustomobject]@{ stories = @(); variants = @() }
}
$candidateConfigPath = Join-Path $repoRoot 'config\victim-candidates.json'
$candidateConfig = [System.IO.File]::ReadAllText($candidateConfigPath) |
    ConvertFrom-Json -Depth 100
$questItemPlacementSignals = @(Get-DpQuestItemPlacementSignals `
    -CaseSpecs $cases `
    -Bindings $bindings `
    -CompiledDefinitions $compiledDefinitions)
$variantCatalog = ConvertTo-DpCaseVariantCatalogLua `
    -CompiledDefinitions $compiledDefinitions `
    -CaseSpecs $cases `
    -Candidates @($candidateConfig.candidates) `
    -Bindings $bindings `
    -QuestItemPlacementSignals $questItemPlacementSignals
$questItemPlacementCatalog = ConvertTo-DpQuestItemPlacementCatalogLua `
    -Signals $questItemPlacementSignals
$baseQuestItemCatalog = if (
    Test-Path -LiteralPath $questItemCatalogPath -PathType Leaf
) {
    [System.IO.File]::ReadAllText($questItemCatalogPath)
}
else { '' }
$questItemCatalog = Merge-DpQuestItemCatalogLua `
    -BaseCatalog $baseQuestItemCatalog `
    -Signals $questItemPlacementSignals
$report = ConvertTo-DpCaseCompatibilityReport -CaseSpecs $cases
$reportJson = ($report | ConvertTo-Json -Depth 100) + "`n"
$nativeRegions = [System.Collections.Generic.List[object]]::new()
foreach ($case in $cases) {
    $binding = @($bindings.settlements | Where-Object {
        [string]$_.region -eq [string]$case.constraints.region -and
        [string]$_.settlement -eq [string]$case.constraints.settlement
    })[0]
    $wiring = ConvertTo-DpNativeRegionWiring `
        -CaseSpec $case `
        -Binding $binding
    $nativeRegions.Add($wiring)

    $dialogRoot = Join-Path $BuildRoot (
        'mod\Data\Quests\darkpassengertest\' +
        [string]$wiring.region + '\' + [string]$wiring.dialogFolder
    )
    New-Item -ItemType Directory -Path $dialogRoot -Force | Out-Null
    foreach ($dialogue in @($wiring.dialogues)) {
        [System.IO.File]::WriteAllText(
            (Join-Path $dialogRoot ([string]$dialogue.fileName)),
            [string]$dialogue.xml,
            $utf8NoBom
        )
    }
}
$nativeManifest = [ordered]@{
    schemaVersion = 1
    regions = @($nativeRegions | ForEach-Object {
        [ordered]@{
            caseId = $_.caseId
            region = $_.region
            settlement = $_.settlement
            questName = $_.questName
            dialogFolder = $_.dialogFolder
            dialogDefinitions = $_.dialogDefinitions
            rumorNodes = $_.rumorNodes
            witnessNodes = $_.witnessNodes
            overheardNodes = $_.overheardNodes
            overheardAssets = $_.overheardAssets
            evidenceStateNodes = $_.evidenceStateNodes
            evidenceStateEdges = $_.evidenceStateEdges
            evidenceType = $_.evidenceType
            evidenceLogs = $_.evidenceLogs
            journalStates = $_.journalStates
            evidenceWitnessEdge = $_.evidenceWitnessEdge
            witnessObjectiveNodes = $_.witnessObjectiveNodes
            witnessType = $_.witnessType
            witnessObjective = $_.witnessObjective
            questItemPlacementNodes =
                ConvertTo-DpQuestItemPlacementNodesXml `
                    -Signals $questItemPlacementSignals `
                    -Region ([string]$_.region)
            questItemPlacementAssets =
                ConvertTo-DpQuestItemPlacementAssetsXml `
                    -Signals $questItemPlacementSignals `
                    -Region ([string]$_.region)
            dialogueFiles = @($_.dialogues.fileName)
        }
    })
}
$nativeManifestJson = ($nativeManifest | ConvertTo-Json -Depth 100) + "`n"

foreach ($language in @(
    @{ Folder = 'English'; Code = 'en' },
    @{ Folder = 'Russian'; Code = 'ru' }
)) {
    $baseLocalizationPath = Join-Path $LocalizationRoot `
        "$($language.Folder)\text__darkpassengertest.xml"
    $localizationOutputPath = Join-Path $generatedLocalizationRoot `
        "$($language.Folder)\text__darkpassengertest.xml"
    $localizationXml = ConvertTo-DpLocalizationXml `
        -BaseLiteralPath $baseLocalizationPath `
        -CaseSpecs $cases `
        -Language $language.Code `
        -CompiledDefinitions $compiledDefinitions
    [System.IO.File]::WriteAllText(
        $localizationOutputPath,
        $localizationXml,
        $utf8NoBom
    )
}

$stageTransforms = @(
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Storm\roles\quests\darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpStormRoleXml `
                -BaseXml $xml `
                -CaseSpecs $cases `
                -Bindings $bindings
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\role__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpDialogueRoleTableXml `
                -BaseXml $xml `
                -CaseSpecs $cases `
                -Bindings $bindings
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\ai\ScriptContext__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpScriptContextXml `
                -BaseXml $xml `
                -CaseSpecs $cases `
                -Signals $questItemPlacementSignals
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\item\item__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpItemTableXml `
                -BaseXml $xml `
                -CaseSpecs $cases `
                -Bindings $bindings `
                -CompiledDefinitions $compiledDefinitions
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpLeadStateTagXml `
                -BaseXml $xml `
                -CaseSpecs $cases
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpLeadStateBuffXml `
                -BaseXml $xml `
                -CaseSpecs $cases
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpDialogueVariantTagXml `
                -BaseXml $xml `
                -CaseSpecs $cases
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpDialogueVariantBuffXml `
                -BaseXml $xml `
                -CaseSpecs $cases
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpOverheardTagXml `
                -BaseXml $xml `
                -CaseSpecs $cases
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpOverheardBuffXml `
                -BaseXml $xml `
                -CaseSpecs $cases
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpQuestItemPlacementTagXml `
                -BaseXml $xml `
                -Signals $questItemPlacementSignals
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpQuestItemPlacementBuffXml `
                -BaseXml $xml `
                -Signals $questItemPlacementSignals
        }
    }
)
foreach ($stageTransform in $stageTransforms) {
    $path = [string]$stageTransform.Path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }
    $baseXml = [System.IO.File]::ReadAllText($path)
    $compiledXml = & $stageTransform.Transform $baseXml
    [System.IO.File]::WriteAllText($path, $compiledXml, $utf8NoBom)
}

[System.IO.File]::WriteAllText($catalogPath, $catalog, $utf8NoBom)
[System.IO.File]::WriteAllText(
    $variantCatalogPath,
    $variantCatalog,
    $utf8NoBom
)
[System.IO.File]::WriteAllText(
    $questItemPlacementCatalogPath,
    $questItemPlacementCatalog,
    $utf8NoBom
)
[System.IO.File]::WriteAllText(
    $questItemCatalogPath,
    $questItemCatalog,
    $utf8NoBom
)
[System.IO.File]::WriteAllText($reportPath, $reportJson, $utf8NoBom)
[System.IO.File]::WriteAllText(
    $nativeManifestPath,
    $nativeManifestJson,
    $utf8NoBom
)

Write-Host "Compiled $($cases.Count) CaseSpec(s)."
Write-Host "Runtime catalog: $catalogPath"
Write-Host "Runtime variant catalog: $variantCatalogPath"
Write-Host "Quest-item placement catalog: $questItemPlacementCatalogPath"
Write-Host "Quest-item protection catalog: $questItemCatalogPath"
Write-Host "Compatibility report: $reportPath"
Write-Host "Native wiring: $nativeManifestPath"
Write-Host "Generated localization: $generatedLocalizationRoot"
