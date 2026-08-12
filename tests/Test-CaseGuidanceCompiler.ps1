$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$caseKitRoot = Join-Path $repoRoot 'casekit'
$compilerModulePath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$fixtureRoot = Join-Path $caseKitRoot 'tests\fixtures\authoring\v2'
$worldPath = Join-Path $caseKitRoot `
    'tests\fixtures\compatibility\world-index.json'
$stableIdPath = Join-Path $caseKitRoot `
    'tests\fixtures\materializer\stable-ids.json'

Import-Module (Join-Path $caseKitRoot 'CaseKit.psd1') -Force
Import-Module (Join-Path $caseKitRoot `
    'core\CaseKit.Compatibility.psm1') -Force
Import-Module (Join-Path $caseKitRoot `
    'adapters\kcd2\CaseKit.Kcd2Materializer.psm1') -Force
Import-Module $compilerModulePath -Force

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

$deck = Read-CaseKitAuthoringDeck `
    -ArchetypeRoot (Join-Path $fixtureRoot 'archetypes') `
    -StoryRoot (Join-Path $fixtureRoot 'stories') `
    -EvidenceModuleRoot (Join-Path $fixtureRoot 'evidence-modules')
$world = [System.IO.File]::ReadAllText($worldPath) |
    ConvertFrom-Json -Depth 100
$compatibility = Resolve-CaseKitCompatibility -Deck $deck `
    -WorldIndex $world -MaxVariantsPerCombination 1
$stableIds = [System.IO.File]::ReadAllText($stableIdPath) |
    ConvertFrom-Json -Depth 100
$compiled = ConvertTo-CaseKitCompiledDefinitions -Deck $deck `
    -CompatibilityReport $compatibility -StableIdRegistry $stableIds
$areaManifest = [pscustomobject]@{
    schemaVersion = 1
    regions = @([pscustomobject]@{
        gameRegion = 'trosecko'
        settlements = @([pscustomobject]@{
            id = 'testville'
            gameRegion = 'trosecko'
            alias = 'DP_SearchArea_Trosecko_Testville'
        })
    })
}

$signals = @(Get-DpGuidanceSignals `
    -CompiledDefinitions $compiled `
    -AreaManifest $areaManifest `
    -StartSignalTag 200)

Add-Result ($signals.Count -eq 6) `
    'guidance compiler emits every native finite target'
Add-Result (
    (@($signals.signal_tag) -join ',') -eq '200,201,202,203,204,205' -and
    @($signals.alias | Sort-Object -Unique).Count -eq 6
) 'guidance compiler assigns deterministic unique signals and aliases'
Add-Result (
    @($signals | Where-Object {
        $_.asset_kind -eq 'SoulAsset' -and
        -not [string]::IsNullOrWhiteSpace([string]$_.shared_soul_guid)
    }).Count -eq 3
) 'actor guidance compiles from soul GUIDs'
Add-Result (
    @($signals | Where-Object {
        $_.asset_kind -eq 'InteractionTriggerAsset' -and
        -not [string]::IsNullOrWhiteSpace([string]$_.entity_guid)
    }).Count -eq 2
) 'entity and place guidance compile to linked interaction assets'
Add-Result (
    @($signals | Where-Object {
        $_.asset_kind -eq 'TriggerAreaAsset' -and
        $_.alias -eq 'DP_SearchArea_Trosecko_Testville'
    }).Count -eq 1
) 'settlement area guidance reuses the proven area alias'

$localCompiled = $compiled | ConvertTo-Json -Depth 100 |
    ConvertFrom-Json -Depth 100
$localVariant = @($localCompiled.variants | Sort-Object rank)[0]
$localGuidance = @($localVariant.guidanceBindings | Where-Object {
    $_.targetKind -eq 'area'
})[0]
$localGuidance | Add-Member -NotePropertyName areaSelection `
    -NotePropertyValue 'smallest-common' -Force
$anchorPositionA = [pscustomobject]@{ x = 100; y = 100; z = 0 }
$anchorPositionB = [pscustomobject]@{ x = 108; y = 104; z = 0 }
$localGuidance | Add-Member -NotePropertyName anchorBindings `
    -NotePropertyValue @(
        [pscustomobject]@{
            slot = 'gossipSourceA'
            entityName = [string]$localVariant.bindings.gossipSourceA.entityName
            position = $anchorPositionA
        }
        [pscustomobject]@{
            slot = 'gossipSourceB'
            entityName = [string]$localVariant.bindings.gossipSourceB.entityName
            position = $anchorPositionB
        }
    ) -Force
$anchorXs = @($localGuidance.anchorBindings.position.x | ForEach-Object {
    [double]$_
})
$anchorYs = @($localGuidance.anchorBindings.position.y | ForEach-Object {
    [double]$_
})
$minX = [double]($anchorXs | Measure-Object -Minimum).Minimum
$maxX = [double]($anchorXs | Measure-Object -Maximum).Maximum
$minY = [double]($anchorYs | Measure-Object -Minimum).Minimum
$maxY = [double]($anchorYs | Measure-Object -Maximum).Maximum
function New-GuidanceTestArea {
    param(
        [string]$Guid,
        [string]$Name,
        [string]$EditorLayer,
        [double]$Padding
    )

    $left = $minX - $Padding
    $right = $maxX + $Padding
    $bottom = $minY - $Padding
    $top = $maxY + $Padding
    return [pscustomobject]@{
        region = 'trosecko'
        guid = $Guid
        name = $Name
        editorLayer = $EditorLayer
        label = ''
        polygon = @(
            [pscustomobject]@{ x = $left; y = $bottom }
            [pscustomobject]@{ x = $right; y = $bottom }
            [pscustomobject]@{ x = $right; y = $top }
            [pscustomobject]@{ x = $left; y = $top }
        )
        bounds = [pscustomobject]@{
            minX = $left
            minY = $bottom
            maxX = $right
            maxY = $top
        }
        surfaceArea = ($right - $left) * ($top - $bottom)
    }
}
$localAreaGuid = 'bbbbbbbb-1111-2222'
$localAreaInventory = [pscustomobject]@{
    schemaVersion = 1
    areas = @(
        (New-GuidanceTestArea `
            -Guid 'aaaaaaaa-1111-2222' `
            -Name 'audio_scene_trigger' `
            -EditorLayer 'Main/testville/inn/audio' `
            -Padding 0.25),
        (New-GuidanceTestArea `
            -Guid $localAreaGuid `
            -Name 'testville_tavernExteriorInnArea_1' `
            -EditorLayer 'Main/testville/inn/_script/crime' `
            -Padding 2),
        (New-GuidanceTestArea `
            -Guid 'cccccccc-1111-2222' `
            -Name 'testville_publicEnemiesRepulsionZoneInnArea_1' `
            -EditorLayer 'Main/testville/inn/_script/crime_publicEnemiesRepulsionZone' `
            -Padding 100)
    )
}
$localSignals = @(Get-DpGuidanceSignals `
    -CompiledDefinitions $localCompiled `
    -AreaManifest $areaManifest `
    -AreaInventory $localAreaInventory `
    -StartSignalTag 300)
$localAreaSignal = @($localSignals | Where-Object {
    $_.qualified_id -eq [string]$localGuidance.qualifiedId
})[0]
Add-Result (
    $localAreaSignal.asset_kind -eq 'TriggerAreaAsset' -and
    $localAreaSignal.alias -match '^DP_Guidance_[0-9a-f]{16}$' -and
    $localAreaSignal.entity_guid -eq $localAreaGuid -and
    $localAreaSignal.area_selection -eq 'smallest-common'
) 'anchored area guidance selects one local vanilla area around every speaker'
$localWiring = ConvertTo-DpGuidanceNativeWiring `
    -Signals $localSignals -Region 'trosecko'
$localLinks = @(Get-DpGuidanceWaitingLinks `
    -Signals $localSignals `
    -Region 'trosecko' `
    -QuestHolderGuid 'aaaaaaaa-bbbb-cccc')
Add-Result (
    $localWiring.assets.Contains(
        "<TriggerAreaAsset Name=`"$($localAreaSignal.alias)`" />"
    ) -and
    @($localLinks | Where-Object {
        $_.targetGuid -eq $localAreaGuid -and
        $_.linkDefinition -eq "asset['$($localAreaSignal.alias)']"
    }).Count -eq 1
) 'local area guidance crosses the compiler and level waiting-link boundary'
Add-Result (
    @($signals | Where-Object {
        $_.step_evidence_code -eq 9101 -and
        $_.visibility_mode -eq 'step-active'
    }).Count -eq 2
) 'guidance retains its evidence and visibility contract'
$configuredSignal = @($signals | Where-Object {
    $_.qualified_id -eq 'paper-trail/ask-innkeeper/settlement-search'
})[0]
Add-Result (
    $configuredSignal.objective_name_key -eq
        'dp_case_9001_objective_guidance_search_name' -and
    $configuredSignal.objective_active_key -eq
        'dp_case_9001_objective_guidance_search_active' -and
    $configuredSignal.objective_name_text -eq 'Check the marked place' -and
    $configuredSignal.objective_active_text -eq
        'The marked place may hold the first lead.'
) 'guidance signal carries StoryPack-owned objective presentation'

$collisionCompiled = $compiled | ConvertTo-Json -Depth 100 |
    ConvertFrom-Json -Depth 100
$collisionStory = $collisionCompiled.stories[0]
foreach ($language in @('ru', 'en')) {
    $collisionStory.localization.$language | Add-Member `
        -NotePropertyName 'objective.a-b' `
        -NotePropertyValue 'First collision source' -Force
    $collisionStory.localization.$language | Add-Member `
        -NotePropertyName 'objective.a_b' `
        -NotePropertyValue 'Second collision source' -Force
}
$collisionGuidance = @(
    $collisionCompiled.variants[0].guidanceBindings | Where-Object {
        $null -ne $_.objective
    }
)[0]
$collisionGuidance.objective.nameAsset = 'objective.a-b'
$collisionGuidance.objective.states.active = 'objective.a_b'
$collisionRejected = $false
try {
    Get-DpGuidanceSignals `
        -CompiledDefinitions $collisionCompiled `
        -AreaManifest $areaManifest `
        -StartSignalTag 350 | Out-Null
}
catch {
    $collisionRejected = $_.Exception.Message -like
        "*collides between assets 'objective.a-b' and 'objective.a_b'*"
}
Add-Result $collisionRejected `
    'guidance compiler rejects deterministic localization-key collisions'

$nullObjectiveCompiled = $compiled | ConvertTo-Json -Depth 100 |
    ConvertFrom-Json -Depth 100
$nullObjectiveCompiled.stories[0].journal.objectives.investigation = $null
$nullObjectiveSignals = @()
$nullObjectiveError = ''
try {
    $nullObjectiveSignals = @(Get-DpGuidanceSignals `
        -CompiledDefinitions $nullObjectiveCompiled `
        -AreaManifest $areaManifest `
        -StartSignalTag 375)
}
catch {
    $nullObjectiveError = $_.Exception.Message
}
Add-Result (
    [string]::IsNullOrWhiteSpace($nullObjectiveError) -and
    $nullObjectiveSignals.Count -eq $signals.Count
) 'guidance compiler treats a null lifecycle override as universal fallback'

$fallbackCompiled = $compiled | ConvertTo-Json -Depth 100 |
    ConvertFrom-Json -Depth 100
$fallbackVariant = @($fallbackCompiled.variants | Sort-Object rank)[0]
$fallbackGuidance = @($fallbackVariant.guidanceBindings | Where-Object {
    $_.qualifiedId -eq 'paper-trail/ask-innkeeper/settlement-search'
})[0]
$fallbackGuidance.binding = $null
$fallbackGuidance.fallback = 'journal-direction'
$fallbackSignals = @(Get-DpGuidanceSignals `
    -CompiledDefinitions $fallbackCompiled `
    -AreaManifest $areaManifest `
    -StartSignalTag 400)
$fallbackSignal = @($fallbackSignals | Where-Object {
    $_.qualified_id -eq [string]$fallbackGuidance.qualifiedId
})[0]
Add-Result (
    $null -ne $fallbackSignal -and
    $fallbackSignal.asset_kind -eq '' -and
    $fallbackSignal.alias -eq '' -and
    $fallbackSignal.objective_authored -eq $true -and
    $fallbackSignal.objective_name_key -eq
        'dp_case_9001_objective_guidance_search_name' -and
    $fallbackSignal.objective_name_localization.ru -eq
        'Проверить отмеченное место' -and
    $fallbackSignal.objective_active_localization.en -eq
        'The marked place may hold the first lead.'
) 'journal fallback preserves authored objective and bilingual localization'

$fallbackWiringError = ''
try {
    $fallbackWiring = ConvertTo-DpGuidanceNativeWiring `
        -Signals $fallbackSignals -Region 'trosecko'
}
catch {
    $fallbackWiringError = $_.Exception.Message
    $fallbackWiring = [pscustomobject]@{
        nodes = ''
        types = ''
        assets = ''
        objectives = ''
    }
}
$fallbackObjectiveStart = $fallbackWiring.objectives.IndexOf(
    "Name=`"$([string]$fallbackSignal.objective_name)`""
)
$fallbackObjectiveXml = if ($fallbackObjectiveStart -lt 0) { '' } else {
    $fallbackObjectiveEnd = $fallbackWiring.objectives.IndexOf(
        '</Objective>',
        $fallbackObjectiveStart
    )
    $fallbackWiring.objectives.Substring(
        $fallbackObjectiveStart,
        $fallbackObjectiveEnd - $fallbackObjectiveStart
    )
}
Add-Result (
    [string]::IsNullOrWhiteSpace($fallbackWiringError) -and
    $fallbackWiring.nodes.Contains(
        "<Constant Name=`"A`" Value=`"$([int]$fallbackSignal.signal_tag)`" />"
    ) -and
    $fallbackObjectiveXml.Contains(
        'StringName="dp_case_9001_objective_guidance_search_active"'
    ) -and
    -not $fallbackObjectiveXml.Contains('Marker=') -and
    -not $fallbackWiring.assets.Contains('Name=""')
) 'journal fallback compiles a toggleable markerless native objective'

$fallbackLocalizationBasePath = Join-Path (
    [System.IO.Path]::GetTempPath()
) ('dark-passenger-guidance-localization-' + [guid]::NewGuid() + '.xml')
try {
    [System.IO.File]::WriteAllText(
        $fallbackLocalizationBasePath,
        "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n" +
            "<Table><Row><Cell>probe_base</Cell>" +
            "<Cell>Probe</Cell></Row></Table>`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    $fallbackLocalizationXml = ConvertTo-DpLocalizationXml `
        -BaseLiteralPath $fallbackLocalizationBasePath `
        -CaseSpecs @([pscustomobject]@{ code = 999; id = 'probe' }) `
        -Language ru `
        -CompiledDefinitions $fallbackCompiled `
        -GuidanceSignals $fallbackSignals
    Add-Result (
        $fallbackLocalizationXml.Contains(
            '<Cell>dp_case_9001_objective_guidance_search_name</Cell>'
        ) -and
        $fallbackLocalizationXml.Contains(
            '<Cell>Проверить отмеченное место</Cell>'
        ) -and
        $fallbackLocalizationXml.Contains(
            '<Cell>dp_case_9001_objective_guidance_search_active</Cell>'
        )
    ) 'journal fallback objective crosses the native localization boundary'
}
finally {
    if (Test-Path -LiteralPath $fallbackLocalizationBasePath) {
        Remove-Item -LiteralPath $fallbackLocalizationBasePath -Force
    }
}

$tagXml = ConvertTo-DpGuidanceTagXml -BaseXml @'
<database><buff_ai_tags>
</buff_ai_tags></database>
'@ -Signals $signals
$buffXml = ConvertTo-DpGuidanceBuffXml -BaseXml @'
<database><buffs>
</buffs></database>
'@ -Signals $signals
Add-Result (
    ([regex]::Matches($tagXml, '<buff_ai_tag ')).Count -eq 6 -and
    ([regex]::Matches($buffXml, '<buff ')).Count -eq 6 -and
    $buffXml.Contains('buff_ui_visibility_id="0"') -and
    $buffXml.Contains('is_persistent="false"')
) 'guidance signals cross into hidden transient RPG buff tables'

$runtimeCase = [pscustomobject]@{
    id = 'composed_case_probe'
    code = 9001
    constraints = [pscustomobject]@{
        region = 'trosecko'
        regions = @('trosecko')
        settlement = 'testville'
    }
    evidence = @($compiled.stories[0].evidence | ForEach-Object {
        [pscustomobject]@{
            id = [string]$_.qualifiedId
            code = [int]$_.code
            role = [string]$_.role
        }
    })
    native = [pscustomobject]@{
        dialogues = @()
        contexts = [pscustomobject]@{}
        regions = [pscustomobject]@{
            trosecko = [pscustomobject]@{
                questName = 'dark_within_t'
                dialogFolder = 'dark_within_t'
            }
        }
    }
}
$runtimeBindings = [pscustomobject]@{
    settlements = @([pscustomobject]@{
        caseCode = 9001
        region = 'trosecko'
        settlement = 'testville'
        nativeVariantIds = @($compiled.variants.variantId)
        roles = [pscustomobject]@{}
    })
}
$candidateSlot = 0
$runtimeCandidates = @($world.entities | Where-Object kind -eq 'actor' |
    ForEach-Object {
        $candidateSlot++
        [pscustomobject]@{
            entityName = [string]$_.entityName
            slot = $candidateSlot
        }
    })
$variantCatalog = ConvertTo-DpCaseVariantCatalogLua `
    -CompiledDefinitions $compiled `
    -CaseSpecs @($runtimeCase) `
    -Candidates $runtimeCandidates `
    -Bindings $runtimeBindings `
    -GuidanceSignals $signals
$variantCatalogRepeat = ConvertTo-DpCaseVariantCatalogLua `
    -CompiledDefinitions $compiled `
    -CaseSpecs @($runtimeCase) `
    -Candidates $runtimeCandidates `
    -Bindings $runtimeBindings `
    -GuidanceSignals $signals
Add-Result (
    $variantCatalog.Contains('guidance = {') -and
    @($signals | Where-Object {
        ([regex]::Matches(
            $variantCatalog,
            [regex]::Escape([string]$_.buff_guid)
        )).Count -ge 2
    }).Count -eq 6
) 'runtime variant catalog carries guidance and cleanup ownership'
Add-Result (
    $variantCatalog -match
        'DarkPassengerCaseVariantCatalogRevision = [1-9][0-9]*' -and
    $variantCatalogRepeat -eq $variantCatalog
) 'runtime catalog publishes a deterministic content revision'
$fallbackVariantCatalog = ConvertTo-DpCaseVariantCatalogLua `
    -CompiledDefinitions $fallbackCompiled `
    -CaseSpecs @($runtimeCase) `
    -Candidates $runtimeCandidates `
    -Bindings $runtimeBindings `
    -GuidanceSignals $fallbackSignals
Add-Result (
    $fallbackVariantCatalog.Contains(
        [string]$fallbackSignal.buff_guid
    ) -and
    $fallbackVariantCatalog.Contains(
        [string]$fallbackSignal.qualified_id
    )
) 'runtime catalog keeps the markerless objective visibility toggle'
Add-Result (
    [regex]::Match(
        $variantCatalog,
        'DarkPassengerCaseVariantCatalogRevision = ([1-9][0-9]*)'
    ).Groups[1].Value -ne
    [regex]::Match(
        $fallbackVariantCatalog,
        'DarkPassengerCaseVariantCatalogRevision = ([1-9][0-9]*)'
    ).Groups[1].Value
) 'runtime content revision changes when compiled presentation changes'

$wiring = ConvertTo-DpGuidanceNativeWiring `
    -Signals $signals -Region 'trosecko'
Add-Result (
    $wiring.nodes.Contains('BuffTagTrigger') -and
    $wiring.types.Contains('DP_GuidanceProgress_') -and
    $wiring.assets.Contains('<SoulAsset ') -and
    $wiring.assets.Contains('<InteractionTriggerAsset ') -and
    -not $wiring.assets.Contains('<TriggerAreaAsset ') -and
    $wiring.objectives.Contains('Marker="DP_SearchArea_Trosecko_Testville"') -and
    $wiring.objectives.Contains('IsTracked="true" Marker=')
) 'guidance compiler crosses into native Skald wiring without redeclaring areas'
$configuredObjectiveStart = $wiring.objectives.IndexOf(
    "Name=`"$($configuredSignal.objective_name)`""
)
$configuredObjectiveEnd = $wiring.objectives.IndexOf(
    '</Objective>',
    $configuredObjectiveStart
)
$configuredObjectiveXml = $wiring.objectives.Substring(
    $configuredObjectiveStart,
    $configuredObjectiveEnd - $configuredObjectiveStart
)
Add-Result (
    $configuredObjectiveXml.Contains(
        'StringName="dp_case_9001_objective_guidance_search_name"'
    ) -and
    $configuredObjectiveXml.Contains(
        'StringName="dp_case_9001_objective_guidance_search_active"'
    ) -and
    -not $configuredObjectiveXml.Contains(
        '<LocalizedName StringName="dark_within_evidence_name"'
    )
) 'native guidance objectives use concrete StoryPack copy instead of duplicated generic copy'

$links = @(Get-DpGuidanceWaitingLinks `
    -Signals $signals `
    -Region 'trosecko' `
    -QuestHolderGuid 'aaaaaaaa-bbbb-cccc')
Add-Result (
    $links.Count -eq 2 -and
    @($links | Where-Object {
        $_.targetGuid -eq '10000000-0000-0000-0000-000000000010' -and
        $_.linkDefinition -match "^asset\['DP_Guidance_[0-9a-f]{16}'\]$"
    }).Count -eq 2
) 'interaction guidance emits the required finite waiting links'

$second = @(Get-DpGuidanceSignals `
    -CompiledDefinitions $compiled `
    -AreaManifest $areaManifest `
    -StartSignalTag 200)
Add-Result (
    ($signals | ConvertTo-Json -Depth 100 -Compress) -ceq
    ($second | ConvertTo-Json -Depth 100 -Compress)
) 'guidance compilation is byte-deterministic in memory'

$compileScript = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1')
)
$questGenerator = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'tools\Generate-VictimArtifacts.ps1')
)
$questTemplate = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot `
        'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template')
)
$areaBindingGenerator = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'tools\Generate-SettlementAreaBindings.ps1')
)
$buildScript = [System.IO.File]::ReadAllText(
    (Join-Path $repoRoot 'tools\Build-Mod.ps1')
)
Add-Result (
    $compileScript.Contains('Get-DpGuidanceSignals') -and
    $compileScript.Contains('-GuidanceSignals $guidanceSignals') -and
    $compileScript.Contains('ConvertTo-DpGuidanceTagXml') -and
    $compileScript.Contains('ConvertTo-DpGuidanceBuffXml') -and
    $compileScript.Contains('guidanceNodes') -and
    $compileScript.Contains('guidanceObjectives')
) 'case compiler routes guidance through runtime, RPG, and native manifests'
Add-Result (
    $questTemplate.Contains('{{DP_GUIDANCE_NODES}}') -and
    $questTemplate.Contains('{{DP_GUIDANCE_TYPES}}') -and
    $questTemplate.Contains('{{DP_GUIDANCE_ASSETS}}') -and
    $questTemplate.Contains('{{DP_GUIDANCE_OBJECTIVES}}') -and
    $questGenerator.Contains("'{{DP_GUIDANCE_NODES}}'") -and
    $questGenerator.Contains("'{{DP_GUIDANCE_OBJECTIVES}}'")
) 'regional quest generator consumes every compiled guidance artifact'
Add-Result (
    $areaBindingGenerator.Contains('[string]$CompiledDefinitionsPath') -and
    $areaBindingGenerator.Contains('Get-DpGuidanceWaitingLinks') -and
    $buildScript.Contains('DP_Guidance_') -and
    $buildScript.IndexOf('& $caseKitCompilerPath') -lt
        $buildScript.IndexOf('& $areaBindingGeneratorPath') -and
    $buildScript.Contains('-CompiledDefinitionsPath')
) 'build compiles finite variants before emitting guidance waiting links'

$integrationRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'dark-passenger-guidance-' + [guid]::NewGuid().ToString('N')
)
try {
    $compiledPath = Join-Path $integrationRoot 'compiled-definitions.json'
    $levelRoot = Join-Path $integrationRoot 'levels'
    $luaPath = Join-Path $integrationRoot 'dp_investigation_area_catalog.lua'
    [System.IO.Directory]::CreateDirectory($integrationRoot) | Out-Null
    [System.IO.File]::WriteAllText(
        $compiledPath,
        ($compiled | ConvertTo-Json -Depth 100) + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    & (Join-Path $repoRoot 'tools\Generate-SettlementAreaBindings.ps1') `
        -CompiledDefinitionsPath $compiledPath `
        -OutputRoot $levelRoot `
        -LuaOutputPath $luaPath
    $waitingLinks = [System.IO.File]::ReadAllText(
        (Join-Path $levelRoot 'trosecko\waitinglinks.xml')
    )
    Add-Result (
        ([regex]::Matches(
            $waitingLinks,
            'asset\[&apos;DP_Guidance_[0-9a-f]{16}&apos;\]'
        )).Count -eq 2 -and
        ([regex]::Matches(
            $waitingLinks,
            'TargetId="10000000-0000-0000-0000-000000000010"'
        )).Count -eq 2
    ) 'settlement binding generator crosses compiled guidance into level XML'
}
finally {
    if (Test-Path -LiteralPath $integrationRoot) {
        Remove-Item -LiteralPath $integrationRoot -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
