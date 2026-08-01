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

Write-Host "RESULT: PASS ($script:checks settlement area checks)"
