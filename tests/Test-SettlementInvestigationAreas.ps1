$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$geometryModule = Join-Path $repoRoot 'tools\InvestigationAreaGeometry.psm1'
$selectionModule = Join-Path $repoRoot 'tools\VanillaInvestigationAreaSelection.psm1'

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

Write-Host "RESULT: PASS ($script:checks settlement area checks)"
