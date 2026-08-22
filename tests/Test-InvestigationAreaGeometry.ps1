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

$policyPath = Join-Path $repoRoot 'config\investigation-areas.json'
$victimCatalogPath = Join-Path $repoRoot 'config\victim-candidates.json'
$generatorPath = Join-Path $repoRoot 'tools\Generate-InvestigationAreas.ps1'

if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    throw "Investigation area policy not found: $policyPath"
}
if (-not (Test-Path -LiteralPath $generatorPath -PathType Leaf)) {
    throw "Investigation area generator not found: $generatorPath"
}

$policy = Get-Content -LiteralPath $policyPath -Raw |
    ConvertFrom-Json -Depth 100
Assert-True ($policy.schemaVersion -eq 1) 'area policy uses schema version 1'
Assert-True `
    (
        $policy.regions.Count -eq 1 -and
        $policy.regions[0].id -eq 'kutnohorsko' -and
        $policy.regions[0].levelHolderGuid -eq '10702dff-9271-4a74' -and
        $policy.regions[0].questHolderGuid -eq 'f4a73e20-28c5-4bd2'
    ) `
    'area policy owns the regional resolver contract'
Assert-True ($policy.areas.Count -eq 1) 'area policy contains one Pritoky pilot'
Assert-True `
    ($policy.defaults.paddingMeters -eq 100) `
    'area policy defaults to 100 metre padding'
Assert-True `
    (
        $policy.defaults.minVertices -eq 10 -and
        $policy.defaults.maxVertices -eq 20
    ) `
    'area policy uses the approved 10-20 vertex range'

$pritokyPolicy = $policy.areas[0]
Assert-True `
    (
        $pritokyPolicy.id -eq 'pritoky' -and
        $pritokyPolicy.gameRegion -eq 'kutnohorsko' -and
        $pritokyPolicy.settlement -eq 'pritoky'
    ) `
    'area policy identifies Kuttenberg Pritoky'
Assert-True `
    ($pritokyPolicy.alias -eq 'DP_PritokySearchArea') `
    'area policy preserves the proven quest alias'
Assert-True `
    ($pritokyPolicy.entityName -eq 'dp_pritoky_investigation_area') `
    'area policy owns a mod-specific world entity'
Assert-True `
    (
        $pritokyPolicy.identitySeed -eq
            'darkpassenger:kutnohorsko:pritoky:investigation-area:v1'
    ) `
    'area policy declares the stable identity seed'
Assert-True `
    (
        $pritokyPolicy.smartAreaTemplateGuid -eq
            'd9064870-2806-4032-8698-c09886772cf6'
    ) `
    'area policy uses the vanilla SmartAreaShape template'
Assert-True `
    (
        @($pritokyPolicy.poiAnchors).Count -eq 3 -and
        @($pritokyPolicy.poiAnchors.id) -contains 'village-core' -and
        @($pritokyPolicy.poiAnchors.id) -contains 'pritoky-inn' -and
        @($pritokyPolicy.poiAnchors.id) -contains 'deserter-camp'
    ) `
    'area policy includes village, inn, and deserter camp POIs'

$fixtureRoot = Join-Path $repoRoot 'build\test-investigation-area-policy'
$resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
$buildPrefix = [IO.Path]::GetFullPath((Join-Path $repoRoot 'build')) +
    [IO.Path]::DirectorySeparatorChar
if (-not $resolvedFixture.StartsWith(
    $buildPrefix,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to replace fixture outside build root: $resolvedFixture"
}
if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
$generatedRoot = Join-Path $fixtureRoot 'generated'
$stageRoot = Join-Path $fixtureRoot 'stage'
New-Item -ItemType Directory -Force -Path $generatedRoot, $stageRoot |
    Out-Null

& $generatorPath `
    -PolicyPath $policyPath `
    -VictimCatalogPath $victimCatalogPath `
    -GeneratedRoot $generatedRoot `
    -StageRoot $stageRoot

$anchorsPath = Join-Path $generatedRoot 'anchors.json'
Assert-True `
    (Test-Path -LiteralPath $anchorsPath -PathType Leaf) `
    'policy generator emits an anchor summary'
$anchorSummary = Get-Content -LiteralPath $anchorsPath -Raw |
    ConvertFrom-Json -Depth 100
Assert-True `
    ($anchorSummary.schemaVersion -eq 1) `
    'anchor summary preserves the policy schema'
Assert-True `
    ($anchorSummary.areas.Count -eq 1) `
    'anchor summary contains one generated area'

$pritokyAnchors = $anchorSummary.areas[0]
$residentAnchors = @(
    $pritokyAnchors.anchors | Where-Object { $_.kind -eq 'resident' }
)
$poiAnchors = @(
    $pritokyAnchors.anchors | Where-Object { $_.kind -eq 'poi' }
)
Assert-True `
    ($residentAnchors.Count -eq 37) `
    'generator joins all 37 enabled Pritoky residents without duplication'
Assert-True `
    ($poiAnchors.Count -eq 3) `
    'generator appends all three explicit Pritoky POIs'
$coordinateKeys = @(
    $pritokyAnchors.anchors |
        ForEach-Object {
            '{0:R}|{1:R}' -f [double]$_.x, [double]$_.y
        } |
        Sort-Object -Unique
)
Assert-True `
    ($coordinateKeys.Count -eq $pritokyAnchors.anchors.Count) `
    'generator removes duplicate anchor coordinates deterministically'
Assert-True `
    (
        $pritokyAnchors.paddingMeters -eq 100 -and
        $pritokyAnchors.minVertices -eq 10 -and
        $pritokyAnchors.maxVertices -eq 20
    ) `
    'generator applies effective default geometry settings'

$entityFragmentPath =
    Join-Path $generatedRoot 'kutnohorsko.entities.xml'
$manifestPath = Join-Path $generatedRoot 'manifest.json'
$waitingLinksPath =
    Join-Path $stageRoot 'Data\Levels\kutnohorsko\waitinglinks.xml'
$luaCatalogPath = Join-Path $stageRoot `
    'Data\Scripts\mods\generated\dp_investigation_area_catalog.lua'
Assert-True `
    (Test-Path -LiteralPath $entityFragmentPath -PathType Leaf) `
    'generator emits the Kuttenberg world-entity fragment'
Assert-True `
    (Test-Path -LiteralPath $manifestPath -PathType Leaf) `
    'generator emits the investigation area manifest'
Assert-True `
    (Test-Path -LiteralPath $waitingLinksPath -PathType Leaf) `
    'generator emits the area waiting-link patch'
Assert-True `
    (Test-Path -LiteralPath $luaCatalogPath -PathType Leaf) `
    'generator emits the runtime area catalogue'

$entityFragmentText = [IO.File]::ReadAllText($entityFragmentPath)
$entityFragment = [xml]$entityFragmentText
$entity = $entityFragment.Objects.Entity
Assert-True `
    (
        $null -ne $entity -and
        $entity.Name -eq 'dp_pritoky_investigation_area' -and
        $entity.EntityClass -eq 'SmartAreaShape'
    ) `
    'generated world fragment contains the mod-owned SmartAreaShape'
Assert-True `
    (
        $entity.Properties.guidSmartAreaTemplate -eq
            'd9064870-2806-4032-8698-c09886772cf6'
    ) `
    'generated SmartAreaShape uses the approved vanilla template'

$relativePoints = @($entity.Area.Points.Point)
Assert-True `
    ($relativePoints.Count -ge 10 -and $relativePoints.Count -le 20) `
    'generated SmartAreaShape respects the 10-20 vertex range'

$invariant = [Globalization.CultureInfo]::InvariantCulture
$originParts = @([string]$entity.Pos -split ',')
$originX = [double]::Parse($originParts[0], $invariant)
$originY = [double]::Parse($originParts[1], $invariant)
$worldPolygon = @(
    $relativePoints | ForEach-Object {
        $parts = @([string]$_.Pos -split ',')
        [pscustomobject]@{
            x = $originX + [double]::Parse($parts[0], $invariant)
            y = $originY + [double]::Parse($parts[1], $invariant)
        }
    }
)
Assert-True `
    (-not (Test-PolygonSelfIntersection -Polygon $worldPolygon)) `
    'generated SmartAreaShape polygon remains simple'
Assert-True `
    ((Get-PolygonSignedArea -Polygon $worldPolygon) -gt 0) `
    'generated SmartAreaShape polygon keeps counter-clockwise winding'

$outsideAnchors = @(
    $pritokyAnchors.anchors | Where-Object {
        -not (Test-PointInPolygon `
            -Point ([pscustomobject]@{
                x = [double]$_.x
                y = [double]$_.y
            }) `
            -Polygon $worldPolygon)
    }
)
Assert-True `
    ($outsideAnchors.Count -eq 0) `
    'generated SmartAreaShape contains all residents and required POIs'

$manifest = Get-Content -LiteralPath $manifestPath -Raw |
    ConvertFrom-Json -Depth 100
$manifestArea = $manifest.areas[0]
Assert-True `
    (
        $manifest.schemaVersion -eq 1 -and
        $manifest.areas.Count -eq 1
    ) `
    'generated manifest describes the one-area pilot'
Assert-True `
    (
        $manifestArea.entityGuid -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}$' -and
        $manifestArea.entityId -ge 1800000 -and
        $manifestArea.entityId -lt 1900000
    ) `
    'generated area identity is stable and KCD-shaped'
Assert-True `
    (
        $manifestArea.vertexCount -eq $worldPolygon.Count -and
        $manifestArea.anchorCount -eq 40 -and
        $manifestArea.residentAnchorCount -eq 37 -and
        $manifestArea.poiAnchorCount -eq 3
    ) `
    'generated manifest records polygon and anchor counts'

$waitingLinksText = [IO.File]::ReadAllText($waitingLinksPath)
$waitingLinks = [xml]$waitingLinksText
$waitingEntries = @(
    $waitingLinks.StaticLinksInfo.WaitingLinks.WaitingLink
)
Assert-True `
    ($waitingEntries.Count -eq 2) `
    'generated waiting-link patch contains the two-link resolver chain'
$areaWaitingLink = @(
    $waitingEntries | Where-Object {
        [string]$_.LinkDefinition -eq "asset['DP_PritokySearchArea']"
    }
)
Assert-True `
    (
        $areaWaitingLink.Count -eq 1 -and
        $areaWaitingLink[0].SourceId -eq 'f4a73e20-28c5-4bd2' -and
        $areaWaitingLink[0].TargetId -eq $manifestArea.entityGuid
    ) `
    'generated waiting link targets the generated Pritoky area GUID'

$luaCatalogText = [IO.File]::ReadAllText($luaCatalogPath)
Assert-True `
    (
        $luaCatalogText.Contains('DarkPassengerInvestigationAreaCatalog') -and
        $luaCatalogText.Contains('kutnohorsko') -and
        $luaCatalogText.Contains('pritoky') -and
        $luaCatalogText.Contains('DP_PritokySearchArea') -and
        $luaCatalogText.Contains('dp_pritoky_investigation_area') -and
        $luaCatalogText.Contains([string]$manifestArea.entityGuid)
    ) `
    'generated Lua catalogue mirrors the area manifest'

foreach (
    $path in @(
        $entityFragmentPath,
        $manifestPath,
        $waitingLinksPath,
        $luaCatalogPath
    )
) {
    $bytes = [IO.File]::ReadAllBytes($path)
    Assert-True `
        (-not (
            $bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
        )) `
        "generated output has no UTF-8 BOM: $([IO.Path]::GetFileName($path))"
}

$repeatFixtureRoot =
    Join-Path $repoRoot 'build\test-investigation-area-policy-repeat'
$resolvedRepeatFixture = [IO.Path]::GetFullPath($repeatFixtureRoot)
if (-not $resolvedRepeatFixture.StartsWith(
    $buildPrefix,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to replace fixture outside build root: $resolvedRepeatFixture"
}
if (Test-Path -LiteralPath $repeatFixtureRoot) {
    Remove-Item -LiteralPath $repeatFixtureRoot -Recurse -Force
}
$repeatGeneratedRoot = Join-Path $repeatFixtureRoot 'generated'
$repeatStageRoot = Join-Path $repeatFixtureRoot 'stage'
New-Item -ItemType Directory -Force `
    -Path $repeatGeneratedRoot, $repeatStageRoot |
    Out-Null
& $generatorPath `
    -PolicyPath $policyPath `
    -VictimCatalogPath $victimCatalogPath `
    -GeneratedRoot $repeatGeneratedRoot `
    -StageRoot $repeatStageRoot

$outputPairs = @(
    @(
        $entityFragmentPath,
        (Join-Path $repeatGeneratedRoot 'kutnohorsko.entities.xml')
    ),
    @(
        $manifestPath,
        (Join-Path $repeatGeneratedRoot 'manifest.json')
    ),
    @(
        $waitingLinksPath,
        (Join-Path $repeatStageRoot 'Data\Levels\kutnohorsko\waitinglinks.xml')
    ),
    @(
        $luaCatalogPath,
        (Join-Path $repeatStageRoot `
            'Data\Scripts\mods\generated\dp_investigation_area_catalog.lua')
    )
)
foreach ($pair in $outputPairs) {
    Assert-True `
        (
            (Get-FileHash -Algorithm SHA256 -LiteralPath $pair[0]).Hash -eq
            (Get-FileHash -Algorithm SHA256 -LiteralPath $pair[1]).Hash
        ) `
        "generated output is deterministic: $([IO.Path]::GetFileName($pair[0]))"
}

Write-Host "RESULT: PASS ($script:checks investigation area geometry checks)"
