$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'tools\InvestigationAreaGeometry.psm1'

if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Investigation area geometry module not found: $modulePath"
}

Import-Module $modulePath -Force

$script:checks = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

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

    Assert-True (
        [math]::Abs($Actual - $Expected) -le $Tolerance
    ) $Message
}

function Point {
    param([double]$X, [double]$Y)

    return [pscustomobject]@{ x = $X; y = $Y }
}

$square = @(
    (Point 0 0),
    (Point 10 0),
    (Point 10 10),
    (Point 0 10)
)

Assert-Near `
    (Get-PolygonSignedArea -Polygon $square) `
    100.0 `
    0.000001 `
    'counter-clockwise polygon has positive signed area'
Assert-True `
    (Test-PointInPolygon -Point (Point 5 5) -Polygon $square) `
    'point inside polygon is contained'
Assert-True `
    (Test-PointInPolygon -Point (Point 0 5) -Polygon $square) `
    'point on polygon edge is contained'
Assert-True `
    (-not (Test-PointInPolygon -Point (Point 15 5) -Polygon $square)) `
    'point outside polygon is rejected'
Assert-True `
    (-not (Test-PolygonSelfIntersection -Polygon $square)) `
    'simple polygon has no self-intersection'

$bowTie = @(
    (Point 0 0),
    (Point 10 10),
    (Point 0 10),
    (Point 10 0)
)
Assert-True `
    (Test-PolygonSelfIntersection -Polygon $bowTie) `
    'bow-tie polygon has a self-intersection'

$cloud = @(
    (Point 10 10),
    (Point 0 10),
    (Point 5 5),
    (Point 10 0),
    (Point 0 0),
    (Point 0 0)
)
$hull = @(Get-ConvexHull -Points $cloud)
Assert-True ($hull.Count -eq 4) 'convex hull removes interior and duplicate points'
Assert-True `
    ((Get-PolygonSignedArea -Polygon $hull) -gt 0) `
    'convex hull uses stable counter-clockwise winding'

$expanded = @(Expand-Polygon -Polygon $hull -PaddingMeters 2)
Assert-True ($expanded.Count -eq 4) 'polygon expansion preserves vertex count'
for ($index = 0; $index -lt $hull.Count; $index++) {
    $before = [math]::Sqrt(
        [math]::Pow([double]$hull[$index].x - 5.0, 2) +
        [math]::Pow([double]$hull[$index].y - 5.0, 2)
    )
    $after = [math]::Sqrt(
        [math]::Pow([double]$expanded[$index].x - 5.0, 2) +
        [math]::Pow([double]$expanded[$index].y - 5.0, 2)
    )
    Assert-Near $after ($before + 2.0) 0.000001 `
        "polygon expansion moves vertex $index outward by requested padding"
}

$irregularA = @(
    Add-DeterministicIrregularity `
        -Polygon $expanded `
        -Seed 'pritoky' `
        -MinVertices 10 `
        -MaxVertices 20 `
        -Amplitude 8
)
$irregularB = @(
    Add-DeterministicIrregularity `
        -Polygon $expanded `
        -Seed 'pritoky' `
        -MinVertices 10 `
        -MaxVertices 20 `
        -Amplitude 8
)
Assert-True `
    ($irregularA.Count -ge 10 -and $irregularA.Count -le 20) `
    'irregular polygon respects configured vertex range'
Assert-True `
    (-not (Test-PolygonSelfIntersection -Polygon $irregularA)) `
    'irregular polygon remains simple'
Assert-True `
    ((Get-PolygonSignedArea -Polygon $irregularA) -gt 0) `
    'irregular polygon keeps counter-clockwise winding'
Assert-True `
    ((ConvertTo-Json $irregularA -Depth 5 -Compress) -eq
        (ConvertTo-Json $irregularB -Depth 5 -Compress)) `
    'irregularity is deterministic for a settlement seed'

$validated = @(
    Assert-InvestigationPolygon `
        -Polygon $irregularA `
        -MinVertices 10 `
        -MaxVertices 20
)
Assert-True `
    ($validated.Count -eq $irregularA.Count) `
    'valid investigation polygon is returned unchanged'

$bowTieRejected = $false
try {
    $null = Assert-InvestigationPolygon `
        -Polygon $bowTie `
        -MinVertices 3 `
        -MaxVertices 20
}
catch {
    $bowTieRejected = $_.Exception.Message -match 'self-intersect'
}
Assert-True $bowTieRejected 'self-intersecting investigation polygon is rejected'

$nonFiniteRejected = $false
try {
    $null = Assert-InvestigationPolygon `
        -Polygon @((Point 0 0), (Point ([double]::NaN) 5), (Point 5 0)) `
        -MinVertices 3 `
        -MaxVertices 20
}
catch {
    $nonFiniteRejected = $_.Exception.Message -match 'finite'
}
Assert-True $nonFiniteRejected 'non-finite investigation coordinate is rejected'

Write-Host "RESULT: PASS ($script:checks investigation area geometry checks)"
