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
$caseActivationSignals = @(Get-DpCaseActivationSignals -CaseSpecs $cases)
$questItemSignalStart = [Math]::Max(
    130,
    122 + $caseActivationSignals.Count
)
$questItemPlacementSignals = @(Get-DpQuestItemPlacementSignals `
    -CaseSpecs $cases `
    -Bindings $bindings `
    -CompiledDefinitions $compiledDefinitions `
    -StartSignalTag $questItemSignalStart)
$areaManifestPath = Join-Path $repoRoot `
    'config\settlement-investigation-areas.json'
$areaManifest = [System.IO.File]::ReadAllText($areaManifestPath) |
    ConvertFrom-Json -Depth 100
$areaInventoryPath = Join-Path $repoRoot `
    'build\generated\vanilla-trigger-areas.json'
$areaInventory = if (
    Test-Path -LiteralPath $areaInventoryPath -PathType Leaf
) {
    [System.IO.File]::ReadAllText($areaInventoryPath) |
        ConvertFrom-Json -Depth 100
}
else { $null }
$guidanceSignals = @(Get-DpGuidanceSignals `
    -CompiledDefinitions $compiledDefinitions `
    -AreaManifest $areaManifest `
    -AreaInventory $areaInventory `
    -StartSignalTag ($questItemSignalStart + $questItemPlacementSignals.Count))
$signalTagEntries = @(
    foreach ($signal in @(
        $caseActivationSignals +
        $questItemPlacementSignals +
        $guidanceSignals
    )) {
        $tag = if ($signal -is [System.Collections.IDictionary]) {
            $signal['signal_tag']
        }
        else { $signal.signal_tag }
        if ($null -eq $tag) {
            throw 'Generated native signal is missing signal_tag.'
        }
        [pscustomobject]@{ tag = [int]$tag }
    }
)
$duplicateSignalTag = @($signalTagEntries |
    Group-Object tag | Where-Object Count -gt 1) | Select-Object -First 1
if ($null -ne $duplicateSignalTag) {
    throw "Generated native signal tag '$($duplicateSignalTag.Name)' is duplicated."
}
$variantCatalog = ConvertTo-DpCaseVariantCatalogLua `
    -CompiledDefinitions $compiledDefinitions `
    -CaseSpecs $cases `
    -Candidates @($candidateConfig.candidates) `
    -Bindings $bindings `
    -QuestItemPlacementSignals $questItemPlacementSignals `
    -GuidanceSignals $guidanceSignals `
    -CaseActivationSignals $caseActivationSignals
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
$nativeModulesByRegion = @{}
foreach ($case in $cases) {
    $activationSignal = @($caseActivationSignals | Where-Object {
        [int]$_.case_code -eq [int]$case.code
    })[0]
    $nativeRegionNames = if (
        $null -ne $case.native.PSObject.Properties['regions']
    ) { @($case.native.regions.PSObject.Properties.Name) } else {
        @([string]$case.constraints.region)
    }
    foreach ($region in @($nativeRegionNames | Sort-Object -Unique)) {
        $scopedBindings = @(Get-DpScopedCaseSettlementBindings `
            -Bindings $bindings -CaseSpec $case -Region $region)
        if ($scopedBindings.Count -eq 0) { continue }
        $scopedBindings = @($scopedBindings | Sort-Object settlement |
            ForEach-Object {
                $binding = $_ | ConvertTo-Json -Depth 100 |
                    ConvertFrom-Json -Depth 100
                $targetSlots = @($candidateConfig.candidates | Where-Object {
                    [string]$_.gameRegion -eq [string]$binding.region -and
                    [string]$_.settlement -eq [string]$binding.settlement
                } | ForEach-Object { [int]$_.slot } | Sort-Object -Unique)
                $binding | Add-Member -NotePropertyName targetCandidateSlots `
                    -NotePropertyValue $targetSlots -Force
                $binding
            })
        $nativeRegion = if (
            $null -ne $case.native.PSObject.Properties['regions']
        ) { $case.native.regions.PSObject.Properties[$region].Value } else {
            $case.native
        }
        $module = ConvertTo-DpNativeRegionWiring `
            -CaseSpec $case `
            -Bindings $scopedBindings `
            -Region $region `
            -NativeRegion $nativeRegion `
            -CaseActivationSignal $activationSignal
        if (-not $nativeModulesByRegion.ContainsKey($region)) {
            $nativeModulesByRegion[$region] =
                [System.Collections.Generic.List[object]]::new()
        }
        $nativeModulesByRegion[$region].Add($module)
    }
}
$nativeRegions = @($nativeModulesByRegion.Keys | Sort-Object | ForEach-Object {
    ConvertTo-DpNativeRegionBundle `
        -Modules $nativeModulesByRegion[$_].ToArray()
})
foreach ($wiring in $nativeRegions) {
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
        $guidanceWiring = ConvertTo-DpGuidanceNativeWiring `
            -Signals $guidanceSignals `
            -Region ([string]$_.region)
        [ordered]@{
            caseIds = @($_.caseIds)
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
            journalObjectives = $_.journalObjectives
            storyModules = @($_.storyModules)
            caseActivationSignals = @($_.caseActivationSignals)
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
            guidanceNodes = $guidanceWiring.nodes
            guidanceTypes = $guidanceWiring.types
            guidanceAssets = $guidanceWiring.assets
            guidanceObjectives = $guidanceWiring.objectives
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
        -CompiledDefinitions $compiledDefinitions `
        -GuidanceSignals $guidanceSignals
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
            ConvertTo-DpCaseActivationTagXml `
                -BaseXml $xml `
                -Signals $caseActivationSignals
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpCaseActivationBuffXml `
                -BaseXml $xml `
                -Signals $caseActivationSignals
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
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpGuidanceTagXml `
                -BaseXml $xml `
                -Signals $guidanceSignals
        }
    },
    @{
        Path = Join-Path $BuildRoot `
            'mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
        Transform = {
            param($xml)
            ConvertTo-DpGuidanceBuffXml `
                -BaseXml $xml `
                -Signals $guidanceSignals
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
