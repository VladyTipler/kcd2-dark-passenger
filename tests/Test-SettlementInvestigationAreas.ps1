param(
    [string]$ReferenceDataRoot =
        'H:\KCD2Mod\_reference-mods\_extracted\AssetLinker\InternalData',
    [string]$DevGameRoot = 'H:\SteamLibrary\steamapps\common\KCD2Mod'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$geometryModule = Join-Path $repoRoot 'tools\InvestigationAreaGeometry.psm1'
$selectionModule = Join-Path $repoRoot 'tools\VanillaInvestigationAreaSelection.psm1'
$catalogExporter = Join-Path $repoRoot 'tools\Export-VanillaTriggerAreaCatalog.ps1'

if (-not (Test-Path -LiteralPath $geometryModule -PathType Leaf)) {
    throw "Investigation geometry module not found: $geometryModule"
}
if (-not (Test-Path -LiteralPath $selectionModule -PathType Leaf)) {
    throw "Vanilla area selection module not found: $selectionModule"
}

Import-Module $geometryModule -Force
Import-Module $selectionModule -Force

$script:checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)

    $script:checks++
    if (-not $Condition) {
        throw "FAIL: $Message"
    }
    Write-Host "PASS: $Message"
}

function Assert-Near {
    param(
        [double]$Actual,
        [double]$Expected,
        [double]$Tolerance,
        [string]$Message
    )

    Assert-True `
        ([math]::Abs($Actual - $Expected) -le $Tolerance) `
        $Message
}

function Assert-SequenceEqual {
    param(
        [object[]]$Actual,
        [object[]]$Expected,
        [string]$Message
    )

    $same = $Actual.Count -eq $Expected.Count
    if ($same) {
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            if ([string]$Actual[$index] -ne [string]$Expected[$index]) {
                $same = $false
                break
            }
        }
    }
    Assert-True $same $Message
}

function Assert-Throws {
    param(
        [scriptblock]$Action,
        [string]$ExpectedPattern,
        [string]$Message
    )

    $thrown = $false
    try {
        & $Action
    }
    catch {
        $thrown = $_.Exception.Message -match $ExpectedPattern
    }
    Assert-True $thrown $Message
}

function New-TestArea {
    param(
        [string]$Guid,
        [string]$Name,
        [string]$EditorLayer,
        [string]$Label,
        [double]$MinX,
        [double]$MinY,
        [double]$MaxX,
        [double]$MaxY
    )

    return [pscustomobject]@{
        region = 'test-region'
        guid = $Guid
        name = $Name
        editorLayer = $EditorLayer
        label = $Label
        polygon = @(
            [pscustomobject]@{ x = $MinX; y = $MinY }
            [pscustomobject]@{ x = $MaxX; y = $MinY }
            [pscustomobject]@{ x = $MaxX; y = $MaxY }
            [pscustomobject]@{ x = $MinX; y = $MaxY }
        )
        surfaceArea = ($MaxX - $MinX) * ($MaxY - $MinY)
    }
}

[xml]$transformedAreaXml = @'
<Object EntityClass="TriggerArea"
        Name="rotated_area"
        Pos="100,200,10"
        Rotate="0.7071067811865476,0,0,0.7071067811865475"
        Scale="2,3,1">
  <Points>
    <Point Pos="0,0,0" />
    <Point Pos="1,0,0" />
    <Point Pos="1,1,0" />
    <Point Pos="0,1,0" />
  </Points>
</Object>
'@

$transformed = @(
    ConvertTo-VanillaAreaPolygon -AreaObject $transformedAreaXml.Object
)
Assert-True ($transformed.Count -eq 4) `
    'polygon transform preserves the authored point count'
Assert-Near ([double]$transformed[0].x) 100.0 0.000001 `
    'polygon transform applies world X translation'
Assert-Near ([double]$transformed[0].y) 200.0 0.000001 `
    'polygon transform applies world Y translation'
Assert-Near ([double]$transformed[1].x) 100.0 0.000001 `
    'polygon transform applies quaternion Z rotation to scaled X'
Assert-Near ([double]$transformed[1].y) 202.0 0.000001 `
    'polygon transform applies non-uniform X scale before rotation'
Assert-Near ([double]$transformed[3].x) 97.0 0.000001 `
    'polygon transform applies non-uniform Y scale before rotation'
Assert-Near ([double]$transformed[3].y) 200.0 0.000001 `
    'polygon transform keeps rotated Y coordinate stable'

$bounds = Get-PolygonBounds -Polygon $transformed
Assert-Near ([double]$bounds.minX) 97.0 0.000001 `
    'polygon bounds expose minimum X'
Assert-Near ([double]$bounds.maxY) 202.0 0.000001 `
    'polygon bounds expose maximum Y'
Assert-Near `
    (Get-PolygonSurfaceArea -Polygon $transformed) `
    6.0 `
    0.000001 `
    'polygon surface area accounts for non-uniform scale'

$boundaryPoint = [pscustomobject]@{ x = 100.0; y = 201.0 }
Assert-True `
    (Test-PointInPolygon -Point $boundaryPoint -Polygon $transformed) `
    'point on a transformed polygon boundary is contained'

$validGeometry = Test-VanillaAreaGeometry -Polygon $transformed
Assert-True ($validGeometry.valid -eq $true) `
    'valid transformed polygon passes area validation'

$bowTie = @(
    [pscustomobject]@{ x = 0.0; y = 0.0 }
    [pscustomobject]@{ x = 10.0; y = 10.0 }
    [pscustomobject]@{ x = 0.0; y = 10.0 }
    [pscustomobject]@{ x = 10.0; y = 0.0 }
)
$invalidGeometry = Test-VanillaAreaGeometry -Polygon $bowTie
Assert-True ($invalidGeometry.valid -eq $false) `
    'self-intersecting vanilla polygon is rejected'
Assert-True ($invalidGeometry.reason -eq 'self_intersection') `
    'invalid vanilla polygon exposes a stable rejection reason'

$emptyGeometry = Test-VanillaAreaGeometry -Polygon @()
Assert-True ($emptyGeometry.valid -eq $false) `
    'empty vanilla polygon is rejected'
Assert-True ($emptyGeometry.reason -eq 'too_few_points') `
    'empty vanilla polygon exposes a geometry rejection reason'

[xml]$defaultTransformXml = @'
<Object EntityClass="TriggerArea" Pos="5,7,0">
  <Points>
    <Point Pos="0,0,0" />
    <Point Pos="2,0,0" />
    <Point Pos="0,2,0" />
  </Points>
</Object>
'@
$defaultTransform = @(
    ConvertTo-VanillaAreaPolygon `
        -AreaObject $defaultTransformXml.Object
)
Assert-Near ([double]$defaultTransform[1].x) 7.0 0.000001 `
    'missing Scale defaults to identity'
Assert-Near ([double]$defaultTransform[2].y) 9.0 0.000001 `
    'missing Rotate defaults to identity'

if (-not (Test-Path -LiteralPath $catalogExporter -PathType Leaf)) {
    throw "Vanilla TriggerArea catalog exporter not found: $catalogExporter"
}

$fixtureRoot = Join-Path $PSScriptRoot 'fixtures\investigation-areas'
$testRoot = Join-Path $repoRoot 'build\test-settlement-investigation-areas'
$referenceRoot = Join-Path $testRoot 'reference'
$devRoot = Join-Path $testRoot 'game'
$missionDirectory = Join-Path $referenceRoot 'kutnohorsko'
$layerDirectory = Join-Path `
    $devRoot `
    'Data\Levels\kutnohorsko\Layers\Main\fixture'
$catalogPath = Join-Path $testRoot 'vanilla-trigger-areas.json'

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $missionDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $layerDirectory -Force | Out-Null
Copy-Item `
    -LiteralPath (Join-Path $fixtureRoot 'objects_mission0.xml') `
    -Destination (Join-Path $missionDirectory 'kut_objects_mission0.xml')
Copy-Item `
    -LiteralPath (Join-Path $fixtureRoot 'settlement-area.lyr') `
    -Destination (Join-Path $layerDirectory 'settlement-area.lyr')

& $catalogExporter `
    -ReferenceDataRoot $referenceRoot `
    -DevGameRoot $devRoot `
    -OutputPath $catalogPath `
    -Regions @('kutnohorsko')

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
Assert-True ($catalog.schemaVersion -eq 1) `
    'TriggerArea catalog exposes schema version 1'
Assert-True (@($catalog.areas).Count -eq 1) `
    'catalog contains only successfully joined TriggerAreas'
Assert-True (@($catalog.rejections).Count -eq 2) `
    'catalog retains rejected TriggerAreas for diagnostics'

$fixtureArea = @($catalog.areas)[0]
Assert-True ($fixtureArea.region -eq 'kutnohorsko') `
    'catalog preserves the source region'
Assert-True ($fixtureArea.guid -eq '11111111-2222-3333') `
    'catalog preserves the compiled short GUID'
Assert-True (
    $fixtureArea.fullGuid -eq '11111111-2222-3333-4444-555555555555'
) 'catalog joins the full authored GUID by short prefix'
Assert-True ($fixtureArea.entityId -eq '101') `
    'catalog preserves the compiled EntityId'
Assert-True (
    $fixtureArea.editorLayer -eq 'Main/fixture/settlement-area'
) 'catalog preserves the routed EditorLayer'
Assert-True (
    $fixtureArea.layerPath -eq `
        'Data/Levels/kutnohorsko/Layers/Main/fixture/settlement-area.lyr'
) 'catalog emits a stable game-relative layer path'
Assert-True (
    $fixtureArea.label -eq 'fixture_publicEnemiesRepulsionZone'
) 'catalog extracts the authored TriggerArea label'
Assert-True ($fixtureArea.height -eq 12.0) `
    'catalog extracts the authored TriggerArea height'
Assert-Near ([double]$fixtureArea.polygon[2].x) 102.0 0.000001 `
    'catalog stores the transformed world polygon X coordinate'
Assert-Near ([double]$fixtureArea.polygon[2].y) 203.0 0.000001 `
    'catalog stores the transformed world polygon Y coordinate'
Assert-Near ([double]$fixtureArea.surfaceArea) 6.0 0.000001 `
    'catalog stores the transformed polygon surface area'

$missingLayer = @(
    $catalog.rejections | Where-Object reason -eq 'layer_missing'
)[0]
Assert-True ($missingLayer.guid -eq 'aaaaaaaa-bbbb-cccc') `
    'catalog diagnostics retain rejected TriggerArea identity'
Assert-True ($missingLayer.reason -eq 'layer_missing') `
    'catalog exposes a stable missing-layer rejection reason'

$prefabArea = @(
    $catalog.rejections |
        Where-Object reason -eq 'prefab_instance_geometry_unavailable'
)[0]
Assert-True ($prefabArea.guid -eq '22222222-3333-4444') `
    'catalog identifies prefab-backed TriggerAreas'
Assert-True (
    $prefabArea.reason -eq 'prefab_instance_geometry_unavailable'
) 'catalog explains why prefab TriggerArea geometry is unavailable'

$secondCatalogPath = Join-Path `
    $testRoot `
    'vanilla-trigger-areas-second.json'
& $catalogExporter `
    -ReferenceDataRoot $referenceRoot `
    -DevGameRoot $devRoot `
    -OutputPath $secondCatalogPath `
    -Regions @('kutnohorsko')
Assert-True (
    (Get-FileHash -LiteralPath $catalogPath -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $secondCatalogPath -Algorithm SHA256).Hash
) 'TriggerArea catalog output is byte-for-byte deterministic'

$overridePath = Join-Path `
    $repoRoot `
    'config\investigation-area-overrides.json'
if (-not (Test-Path -LiteralPath $overridePath -PathType Leaf)) {
    throw "Investigation area override policy not found: $overridePath"
}
$overridePolicy = Get-Content -LiteralPath $overridePath -Raw |
    ConvertFrom-Json
Assert-True ($overridePolicy.schemaVersion -eq 1) `
    'investigation area overrides expose schema version 1'

$technical = New-TestArea `
    -Guid '99999999-9999-9999' `
    -Name 'audio_sound_trigger' `
    -EditorLayer 'Main/alpha/audio' `
    -Label 'audio_area' `
    -MinX 10 -MinY 0 -MaxX 14 -MaxY 4
$technicalClass = Get-AreaSemanticClassification -Area $technical
Assert-True (-not $technicalClass.allowed) `
    'semantic filter rejects known technical TriggerAreas'
Assert-True ($technicalClass.category -eq 'technical') `
    'technical TriggerArea rejection is classified explicitly'

$punishmentArea = New-TestArea `
    -Guid '99999999-9999-9998' `
    -Name 'crime_punishment_testRegion_TA' `
    -EditorLayer 'Main/_script/_crime' `
    -Label 'crime_punishmentArea' `
    -MinX -1000 -MinY -1000 -MaxX 1000 -MaxY 1000
$punishmentClass = Get-AreaSemanticClassification -Area $punishmentArea
Assert-True (-not $punishmentClass.allowed) `
    'regional crime punishment zones are rejected as technical coverage'

$primary = New-TestArea `
    -Guid '10000000-0000-0000' `
    -Name 'alpha_publicEnemiesRepulsionZoneVillageArea_1' `
    -EditorLayer 'Main/alpha/village/_script/crime_publicEnemiesRepulsionZone' `
    -Label 'crime_publicEnemiesRepulsionZone' `
    -MinX 0 -MinY 0 -MaxX 10 -MaxY 10
$smallSupplement = New-TestArea `
    -Guid '20000000-0000-0000' `
    -Name 'alpha_outer_house_area' `
    -EditorLayer 'Main/alpha/outer_house' `
    -Label '' `
    -MinX 10 -MinY 0 -MaxX 14 -MaxY 4
$largeSupplement = New-TestArea `
    -Guid '30000000-0000-0000' `
    -Name 'alpha_outer_district_area' `
    -EditorLayer 'Main/alpha/outer_district' `
    -Label '' `
    -MinX 10 -MinY -10 -MaxX 30 -MaxY 20
$settlement = [pscustomobject]@{
    id = 'alpha'
    gameRegion = 'test-region'
    center = [pscustomobject]@{ x = 5.0; y = 5.0 }
}
$anchors = @(
    [pscustomobject]@{
        id = 'resident-core'
        position = [pscustomobject]@{ x = 2.0; y = 2.0 }
    }
    [pscustomobject]@{
        id = 'resident-outside'
        position = [pscustomobject]@{ x = 12.0; y = 2.0 }
    }
)

Assert-Throws `
    { Select-SettlementInvestigationAreas `
        -Settlement $settlement `
        -Areas @($primary) `
        -Anchors $anchors } `
    'Uncovered investigation anchors.*resident-outside' `
    'primary-only selection fails when a resident remains uncovered'

$hybrid = Select-SettlementInvestigationAreas `
    -Settlement $settlement `
    -Areas @($technical, $largeSupplement, $smallSupplement, $primary) `
    -Anchors $anchors
Assert-SequenceEqual `
    @($hybrid.areaGuids) `
    @('10000000-0000-0000', '20000000-0000-0000') `
    'hybrid selector chooses primary plus the smallest safe supplement'
Assert-True ($hybrid.primaryGuid -eq '10000000-0000-0000') `
    'same-settlement public-enemy zone becomes the primary area'
Assert-True (-not (@($hybrid.areaGuids) -contains $technical.guid)) `
    'hybrid selector never includes a technical all-hit area'

$sceneTechnical = New-TestArea `
    -Guid '41000000-0000-0000' `
    -Name 'audio_scene_trigger' `
    -EditorLayer 'Main/alpha/inn/audio' `
    -Label 'audio_area' `
    -MinX 1 -MinY 1 -MaxX 4 -MaxY 4
$sceneQuestArea = New-TestArea `
    -Guid '42000000-0000-0000' `
    -Name 'sidequest_scene_area' `
    -EditorLayer 'Main/_quest/side/static' `
    -Label '' `
    -MinX 1 -MinY 1 -MaxX 4 -MaxY 4
$sceneTavernArea = New-TestArea `
    -Guid '43000000-0000-0000' `
    -Name 'alpha_tavernExteriorInnArea_1' `
    -EditorLayer 'Main/alpha/inn/_script/crime' `
    -Label '' `
    -MinX 0 -MinY 0 -MaxX 6 -MaxY 6
$sceneBroadArea = New-TestArea `
    -Guid '44000000-0000-0000' `
    -Name 'alpha_publicEnemiesRepulsionZoneInnArea_1' `
    -EditorLayer 'Main/alpha/inn/_script/crime_publicEnemiesRepulsionZone' `
    -Label 'crime_publicEnemiesRepulsionZone' `
    -MinX -20 -MinY -20 -MaxX 20 -MaxY 20
$sceneAnchors = @(
    [pscustomobject]@{
        id = 'speaker-a'
        position = [pscustomobject]@{ x = 2.0; y = 2.0 }
    }
    [pscustomobject]@{
        id = 'speaker-b'
        position = [pscustomobject]@{ x = 3.0; y = 3.0 }
    }
)
$sceneArea = Select-CommonInvestigationArea `
    -Region 'test-region' `
    -Areas @(
        $sceneTechnical,
        $sceneQuestArea,
        $sceneTavernArea,
        $sceneBroadArea
    ) `
    -Anchors $sceneAnchors
Assert-True ($sceneArea.guid -eq $sceneTavernArea.guid) `
    'scene selector chooses the smallest stable area containing every speaker'
Assert-Throws `
    { Select-CommonInvestigationArea `
        -Region 'test-region' `
        -Areas @($sceneTavernArea) `
        -Anchors @(
            $sceneAnchors[0],
            [pscustomobject]@{
                id = 'speaker-outside'
                position = [pscustomobject]@{ x = 50.0; y = 50.0 }
            }
        ) } `
    'No safe common investigation area.*speaker-a, speaker-outside' `
    'scene selector rejects a pair without common vanilla coverage'

$forcedPrimary = New-TestArea `
    -Guid '05000000-0000-0000' `
    -Name 'alpha_publicEnemiesRepulsionZoneForcedArea_1' `
    -EditorLayer 'Main/other/_script/crime_publicEnemiesRepulsionZone' `
    -Label 'crime_publicEnemiesRepulsionZone' `
    -MinX 0 -MinY 0 -MaxX 10 -MaxY 10
$forcedExtra = New-TestArea `
    -Guid '40000000-0000-0000' `
    -Name 'alpha_evidence_territory' `
    -EditorLayer 'Main/alpha/evidence' `
    -Label '' `
    -MinX 40 -MinY 40 -MaxX 45 -MaxY 45
$manualOverride = [pscustomobject]@{
    primaryGuid = $forcedPrimary.guid
    forceIncludeGuids = @($forcedExtra.guid)
    denyGuids = @($smallSupplement.guid)
}
$manual = Select-SettlementInvestigationAreas `
    -Settlement $settlement `
    -Areas @(
        $primary,
        $forcedPrimary,
        $smallSupplement,
        $largeSupplement,
        $forcedExtra
    ) `
    -Anchors $anchors `
    -Override $manualOverride
Assert-True ($manual.primaryGuid -eq $forcedPrimary.guid) `
    'manual override can force the primary area'
Assert-True (@($manual.areaGuids) -contains $forcedExtra.guid) `
    'manual override can force an evidence territory'
Assert-True (-not (@($manual.areaGuids) -contains $smallSupplement.guid)) `
    'manual deny takes precedence over automatic scoring'
Assert-True (@($manual.areaGuids) -contains $largeSupplement.guid) `
    'selector replaces a denied supplement with the next safe area'

$tieA = New-TestArea `
    -Guid '21000000-0000-0000' `
    -Name 'alpha_tie_a' `
    -EditorLayer 'Main/alpha/tie' `
    -Label '' `
    -MinX 10 -MinY 0 -MaxX 14 -MaxY 4
$tieB = New-TestArea `
    -Guid '22000000-0000-0000' `
    -Name 'alpha_tie_b' `
    -EditorLayer 'Main/alpha/tie' `
    -Label '' `
    -MinX 10 -MinY 0 -MaxX 14 -MaxY 4
$tie = Select-SettlementInvestigationAreas `
    -Settlement $settlement `
    -Areas @($primary, $tieB, $tieA) `
    -Anchors $anchors
Assert-True (@($tie.areaGuids)[1] -eq $tieA.guid) `
    'equal-scoring supplemental areas use stable GUID tie-breaking'

$conflictingOverride = [pscustomobject]@{
    primaryGuid = $primary.guid
    forceIncludeGuids = @($smallSupplement.guid)
    denyGuids = @($smallSupplement.guid)
}
Assert-Throws `
    { Select-SettlementInvestigationAreas `
        -Settlement $settlement `
        -Areas @($primary, $smallSupplement) `
        -Anchors $anchors `
        -Override $conflictingOverride } `
    'both forced and denied' `
    'conflicting manual override fails instead of weakening deny precedence'

$pritokyFixture = Get-Content `
    -LiteralPath (Join-Path $fixtureRoot 'pritoky-golden.json') `
    -Raw |
    ConvertFrom-Json
$candidatePolicy = Get-Content `
    -LiteralPath (Join-Path $repoRoot 'config\victim-candidates.json') `
    -Raw |
    ConvertFrom-Json
$transientZizkaGuards = @(
    'tvez_zizkaGuardPOI_1',
    'tvez_zizkaGuardPOI_2',
    'tvez_zizkaGuardPOI_3'
)
Assert-True (
    @(
        $candidatePolicy.candidates |
            Where-Object enabled |
            Where-Object entityName -in $transientZizkaGuards
    ).Count -eq 0
) 'temporary Zizka POI guards are excluded from the permanent victim pool'
$unboundedTransientResidents = @(
    'kkut_extras_man_72',
    'kkut_extras_man_81',
    'kkut_extras_man_82',
    'kopa_man_39'
)
Assert-True (
    @(
        $candidatePolicy.candidates |
            Where-Object enabled |
            Where-Object entityName -in $unboundedTransientResidents
    ).Count -eq 0
) 'unproven outliers without stable authored territories are excluded'
Assert-True (
    @(
        $candidatePolicy.candidates |
            Where-Object enabled |
            Where-Object factionName -eq 'deadBodies'
    ).Count -eq 0
) 'deadBodies faction actors are excluded from the living victim pool'
$pritokySettlement = $candidatePolicy.settlements |
    Where-Object {
        $_.gameRegion -eq 'kutnohorsko' -and $_.id -eq 'pritoky'
    }
$pritokyAnchors = @(
    $candidatePolicy.candidates |
        Where-Object {
            $_.enabled -and
            $_.gameRegion -eq 'kutnohorsko' -and
            $_.settlement -eq 'pritoky'
        } |
        ForEach-Object {
            [pscustomobject]@{ id = $_.entityName; position = $_.position }
        }
)
$pritokyOverride = $overridePolicy.settlements |
    Where-Object {
        $_.gameRegion -eq 'kutnohorsko' -and
        $_.settlement -eq 'pritoky'
    }
$pritoky = Select-SettlementInvestigationAreas `
    -Settlement $pritokySettlement `
    -Areas @($pritokyFixture.areas) `
    -Anchors $pritokyAnchors `
    -Override $pritokyOverride
Assert-True ($pritokyAnchors.Count -eq 37) `
    'Pritoky golden uses all 37 enabled resident anchors'
Assert-SequenceEqual `
    @($pritoky.areaGuids) `
    @(
        'd0fa0ece-6af5-19f6',
        'd2fc29a3-6787-141c',
        '1b6b6d4e-905c-4f9e'
    ) `
    'Pritoky golden keeps the proven village, inn, and camp union'

$settlementGenerator = Join-Path `
    $repoRoot `
    'tools\Generate-SettlementInvestigationAreas.ps1'
if (-not (Test-Path -LiteralPath $settlementGenerator -PathType Leaf)) {
    throw "Settlement investigation area generator not found: $settlementGenerator"
}

$realCatalogPath = Join-Path `
    $repoRoot `
    'build\generated\vanilla-trigger-areas.json'
if (-not (Test-Path -LiteralPath $realCatalogPath -PathType Leaf)) {
    & $catalogExporter `
        -ReferenceDataRoot $ReferenceDataRoot `
        -DevGameRoot $DevGameRoot `
        -OutputPath $realCatalogPath
}
$generatedManifestPath = Join-Path `
    $testRoot `
    'settlement-investigation-areas.json'
$secondManifestPath = Join-Path `
    $testRoot `
    'settlement-investigation-areas-second.json'
$diagnosticPath = Join-Path `
    $testRoot `
    'settlement-investigation-areas-diagnostics.json'
$committedManifestPath = Join-Path `
    $repoRoot `
    'config\settlement-investigation-areas.json'

& $settlementGenerator `
    -TriggerAreaCatalogPath $realCatalogPath `
    -VictimCandidatesPath (Join-Path $repoRoot 'config\victim-candidates.json') `
    -OverridePath $overridePath `
    -OutputPath $generatedManifestPath `
    -DiagnosticsPath $diagnosticPath
& $settlementGenerator `
    -TriggerAreaCatalogPath $realCatalogPath `
    -VictimCandidatesPath (Join-Path $repoRoot 'config\victim-candidates.json') `
    -OverridePath $overridePath `
    -OutputPath $secondManifestPath `
    -DiagnosticsPath $diagnosticPath

$settlementManifest = Get-Content `
    -LiteralPath $generatedManifestPath `
    -Raw |
    ConvertFrom-Json
$realCatalog = Get-Content -LiteralPath $realCatalogPath -Raw |
    ConvertFrom-Json
$manifestSettlements = @(
    $settlementManifest.regions |
        ForEach-Object { $_.settlements }
)
$expectedSettlementGroups = @(
    $candidatePolicy.candidates |
        Where-Object enabled |
        Group-Object gameRegion, settlement
)
Assert-True ($settlementManifest.schemaVersion -eq 1) `
    'settlement investigation manifest exposes schema version 1'
Assert-True (
    $manifestSettlements.Count -eq $expectedSettlementGroups.Count
) 'every settlement with enabled candidates has generated coverage'
Assert-True (
    @($manifestSettlements.primaryGuid | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_)
    }).Count -eq 0
) 'every generated settlement has one primary area'

$aliases = @($manifestSettlements.alias)
Assert-True (
    @($aliases | Sort-Object -Unique).Count -eq $aliases.Count
) 'generated settlement area aliases are globally unique'

$catalogByGuid = @{}
foreach ($area in $realCatalog.areas) {
    $catalogByGuid[[string]$area.guid] = $area
}
foreach ($manifestSettlement in $manifestSettlements) {
    $missingAreaGuids = @(
        $manifestSettlement.areaGuids |
            Where-Object { -not $catalogByGuid.ContainsKey([string]$_) }
    )
    Assert-True ($missingAreaGuids.Count -eq 0) `
        "selected areas exist in inventory: $($manifestSettlement.gameRegion)/$($manifestSettlement.id)"
    $selectedAreas = @(
        $manifestSettlement.areaGuids |
            Where-Object { $catalogByGuid.ContainsKey([string]$_) } |
            ForEach-Object { $catalogByGuid[[string]$_] }
    )
    $enabledCandidates = @(
        $candidatePolicy.candidates |
            Where-Object {
                $_.enabled -and
                $_.gameRegion -eq $manifestSettlement.gameRegion -and
                $_.settlement -eq $manifestSettlement.id
            }
    )
    Assert-True (
        $enabledCandidates.Count -eq $manifestSettlement.candidateCount
    ) "manifest candidate count matches $($manifestSettlement.gameRegion)/$($manifestSettlement.id)"
    $uncoveredCandidates = @(
        foreach ($candidate in $enabledCandidates) {
        $covered = @(
            $selectedAreas |
                Where-Object {
                    Test-PointInPolygon `
                        -Point $candidate.position `
                        -Polygon @($_.polygon)
                }
        ).Count -gt 0
            if (-not $covered) {
                $candidate.entityName
            }
        }
    )
    Assert-True ($uncoveredCandidates.Count -eq 0) `
        "all enabled candidates are covered: $($manifestSettlement.gameRegion)/$($manifestSettlement.id)"
}

$generatedPritoky = $manifestSettlements |
    Where-Object {
        $_.gameRegion -eq 'kutnohorsko' -and $_.id -eq 'pritoky'
    }
Assert-SequenceEqual `
    @($generatedPritoky.areaGuids) `
    @(
        'd0fa0ece-6af5-19f6',
        'd2fc29a3-6787-141c',
        '1b6b6d4e-905c-4f9e'
    ) `
    'generated two-region manifest preserves the Pritoky golden union'
$prohibitedOversizedAreaGuids = @(
    '491aeb93-2150-49c8',
    'f71b1dae-91cd-47d1',
    '0f3c35a8-f720-4d85',
    'fe0963d5-55e9-42b8',
    'f8856700-76c7-40f6',
    'ab0e52c1-e5c1-4f14'
)
Assert-True (
    @(
        $manifestSettlements.areaGuids |
            Where-Object { $_ -in $prohibitedOversizedAreaGuids }
    ).Count -eq 0
) 'generated coverage excludes audited regional and oversized quest areas'
Assert-True (
    (Get-FileHash -LiteralPath $generatedManifestPath -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $secondManifestPath -Algorithm SHA256).Hash
) 'settlement investigation manifest is byte-for-byte deterministic'
Assert-True (Test-Path -LiteralPath $committedManifestPath -PathType Leaf) `
    'generated settlement investigation manifest is committed as config'
Assert-True (
    (Get-FileHash -LiteralPath $generatedManifestPath -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $committedManifestPath -Algorithm SHA256).Hash
) 'committed settlement investigation config matches fresh generation'

$coverageDiagnostics = Get-Content -LiteralPath $diagnosticPath -Raw |
    ConvertFrom-Json
Assert-True ($coverageDiagnostics.status -eq 'complete') `
    'coverage diagnostics report a complete two-region build'
Assert-True (@($coverageDiagnostics.failures).Count -eq 0) `
    'coverage diagnostics contain no unresolved settlement failures'

Write-Host "RESULT: PASS ($script:checks settlement area checks)"
