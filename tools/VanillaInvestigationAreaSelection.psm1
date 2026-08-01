Set-StrictMode -Version Latest

$script:AreaGeometryValidationCache = @{}

$geometryModule = Join-Path $PSScriptRoot 'InvestigationAreaGeometry.psm1'
if (-not (Test-Path -LiteralPath $geometryModule -PathType Leaf)) {
    throw "Investigation geometry module not found: $geometryModule"
}
Import-Module $geometryModule

function ConvertFrom-InvariantVector {
    param(
        [AllowNull()][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][double[]]$Default,
        [Parameter(Mandatory)][int]$Length
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @($Default)
    }
    $parts = @($Value.Split(','))
    if ($parts.Count -lt $Length) {
        throw "Vector '$Value' must contain at least $Length values."
    }
    return @(
        for ($index = 0; $index -lt $Length; $index++) {
            [double]::Parse(
                $parts[$index],
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
    )
}

function ConvertTo-VanillaAreaPolygon {
    param([Parameter(Mandatory)]$AreaObject)

    $pointsNode = $AreaObject.SelectSingleNode('Points')
    if ($null -eq $pointsNode) {
        return @()
    }

    $position = @(
        ConvertFrom-InvariantVector `
            -Value ([string]$AreaObject.GetAttribute('Pos')) `
            -Default @(0.0, 0.0, 0.0) `
            -Length 3
    )
    $scale = @(
        ConvertFrom-InvariantVector `
            -Value ([string]$AreaObject.GetAttribute('Scale')) `
            -Default @(1.0, 1.0, 1.0) `
            -Length 3
    )
    $rotation = @(
        ConvertFrom-InvariantVector `
            -Value ([string]$AreaObject.GetAttribute('Rotate')) `
            -Default @(1.0, 0.0, 0.0, 0.0) `
            -Length 4
    )

    $w = [double]$rotation[0]
    $x = [double]$rotation[1]
    $y = [double]$rotation[2]
    $z = [double]$rotation[3]
    $yaw = [math]::Atan2(
        2.0 * ($w * $z + $x * $y),
        1.0 - 2.0 * ($y * $y + $z * $z)
    )
    $cosYaw = [math]::Cos($yaw)
    $sinYaw = [math]::Sin($yaw)

    return @(
        foreach ($point in @($pointsNode.Point)) {
            $local = @(
                ConvertFrom-InvariantVector `
                    -Value ([string]$point.GetAttribute('Pos')) `
                    -Default @(0.0, 0.0, 0.0) `
                    -Length 3
            )
            $scaledX = [double]$local[0] * [double]$scale[0]
            $scaledY = [double]$local[1] * [double]$scale[1]
            [pscustomobject]@{
                x = [double]$position[0] +
                    $scaledX * $cosYaw - $scaledY * $sinYaw
                y = [double]$position[1] +
                    $scaledX * $sinYaw + $scaledY * $cosYaw
            }
        }
    )
}

function Get-PolygonBounds {
    param([Parameter(Mandatory)][object[]]$Polygon)

    if ($Polygon.Count -eq 0) {
        throw 'Polygon bounds require at least one point.'
    }
    return [pscustomobject]@{
        minX = [double](
            $Polygon | Measure-Object -Property x -Minimum
        ).Minimum
        minY = [double](
            $Polygon | Measure-Object -Property y -Minimum
        ).Minimum
        maxX = [double](
            $Polygon | Measure-Object -Property x -Maximum
        ).Maximum
        maxY = [double](
            $Polygon | Measure-Object -Property y -Maximum
        ).Maximum
    }
}

function Get-PolygonSurfaceArea {
    param([Parameter(Mandatory)][object[]]$Polygon)

    return [math]::Abs((Get-PolygonSignedArea -Polygon $Polygon))
}

function Test-VanillaAreaGeometry {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Polygon,
        [switch]$SkipSelfIntersection
    )

    if ($Polygon.Count -lt 3) {
        return [pscustomobject]@{ valid = $false; reason = 'too_few_points' }
    }
    foreach ($point in $Polygon) {
        $x = [double]$point.x
        $y = [double]$point.y
        if (
            [double]::IsNaN($x) -or [double]::IsInfinity($x) -or
            [double]::IsNaN($y) -or [double]::IsInfinity($y)
        ) {
            return [pscustomobject]@{ valid = $false; reason = 'non_finite' }
        }
    }
    if (
        -not $SkipSelfIntersection -and
        (Test-PolygonSelfIntersection -Polygon $Polygon)
    ) {
        return [pscustomobject]@{
            valid = $false
            reason = 'self_intersection'
        }
    }
    if ((Get-PolygonSurfaceArea -Polygon $Polygon) -le 0.0000001) {
        return [pscustomobject]@{ valid = $false; reason = 'zero_area' }
    }
    return [pscustomobject]@{ valid = $true; reason = $null }
}

function Get-OptionalPropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function Get-AreaSemanticClassification {
    param([Parameter(Mandatory)]$Area)

    $name = [string](Get-OptionalPropertyValue $Area 'name' '')
    $label = [string](Get-OptionalPropertyValue $Area 'label' '')
    $editorLayer = [string](
        Get-OptionalPropertyValue $Area 'editorLayer' ''
    )
    $semanticText = "$name $label $editorLayer"
    $technicalPatterns = @(
        '(?i)(^|[^a-z])(audio|sound|music|ambience|stealth|vision|weather|navigation|streaming)([^a-z]|$)',
        '(?i)birdsTakeoff',
        '(?i)crime_punishment',
        '(?i)^WH_TriggerArea\d+\[',
        '(?i)^trigger\['
    )
    foreach ($pattern in $technicalPatterns) {
        if ($semanticText -match $pattern) {
            return [pscustomobject]@{
                allowed = $false
                category = 'technical'
                stability = 0
                reason = "technical_pattern:$pattern"
            }
        }
    }

    if ($semanticText -match '(?i)publicEnemiesRepulsionZone') {
        return [pscustomobject]@{
            allowed = $true
            category = 'primary'
            stability = 3
            reason = 'public_enemies_zone'
        }
    }

    $stableTerritoryPattern =
        '(?i)(village|town|city|inn|tavern|camp|farm|mill|house|district|fortress|castle|monastery|grave|cemetery|executioner)'
    if ($semanticText -match $stableTerritoryPattern) {
        return [pscustomobject]@{
            allowed = $true
            category = 'supplemental'
            stability = 2
            reason = 'stable_territory'
        }
    }

    return [pscustomobject]@{
        allowed = $true
        category = 'supplemental'
        stability = 1
        reason = 'generic_territory'
    }
}

function Get-AnchorPoint {
    param([Parameter(Mandatory)]$Anchor)

    $position = Get-OptionalPropertyValue $Anchor 'position' $null
    if ($null -ne $position) {
        return $position
    }
    return $Anchor
}

function Get-AnchorId {
    param(
        [Parameter(Mandatory)]$Anchor,
        [Parameter(Mandatory)][int]$Index
    )

    foreach ($propertyName in @('id', 'entityName', 'alias', 'guid')) {
        $value = [string](
            Get-OptionalPropertyValue $Anchor $propertyName ''
        )
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
    return "anchor-$Index"
}

function Test-AreaContainsPoint {
    param(
        [Parameter(Mandatory)]$Area,
        [Parameter(Mandatory)]$Point
    )

    $bounds = Get-OptionalPropertyValue $Area 'bounds' $null
    if ($null -eq $bounds) {
        $bounds = Get-PolygonBounds -Polygon @($Area.polygon)
    }
    if (
        [double]$Point.x -lt [double]$bounds.minX -or
        [double]$Point.x -gt [double]$bounds.maxX -or
        [double]$Point.y -lt [double]$bounds.minY -or
        [double]$Point.y -gt [double]$bounds.maxY
    ) {
        return $false
    }
    return Test-PointInPolygon -Point $Point -Polygon @($Area.polygon)
}

function Get-AreaCenterDistance {
    param(
        [Parameter(Mandatory)]$Area,
        [Parameter(Mandatory)]$Settlement
    )

    $polygon = @($Area.polygon)
    $centerX = [double](
        $polygon | Measure-Object -Property x -Average
    ).Average
    $centerY = [double](
        $polygon | Measure-Object -Property y -Average
    ).Average
    $settlementCenter = Get-OptionalPropertyValue `
        $Settlement `
        'center' `
        $null
    if ($null -eq $settlementCenter) {
        return 0.0
    }
    $dx = $centerX - [double]$settlementCenter.x
    $dy = $centerY - [double]$settlementCenter.y
    return [math]::Sqrt($dx * $dx + $dy * $dy)
}

function Get-InvestigationAreaScore {
    param(
        [Parameter(Mandatory)]$Area,
        [Parameter(Mandatory)][object[]]$UncoveredAnchors,
        [Parameter(Mandatory)]$Settlement
    )

    $classification = Get-AreaSemanticClassification -Area $Area
    $covered = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $UncoveredAnchors.Count; $index++) {
        $anchor = $UncoveredAnchors[$index]
        if (Test-AreaContainsPoint `
            -Area $Area `
            -Point (Get-AnchorPoint $anchor)) {
            $covered.Add((Get-AnchorId $anchor $index))
        }
    }
    $surfaceArea = Get-OptionalPropertyValue $Area 'surfaceArea' $null
    if ($null -eq $surfaceArea) {
        $surfaceArea = Get-PolygonSurfaceArea -Polygon @($Area.polygon)
    }

    return [pscustomobject]@{
        guid = [string]$Area.guid
        newCoverage = $covered.Count
        coveredAnchorIds = @($covered)
        semanticStability = [int]$classification.stability
        excessSurface = [double]$surfaceArea
        centerDistance = Get-AreaCenterDistance `
            -Area $Area `
            -Settlement $Settlement
    }
}

function Get-AreaGeometryValidation {
    param([Parameter(Mandatory)]$Area)

    $guid = [string](Get-OptionalPropertyValue $Area 'guid' '')
    if (
        -not [string]::IsNullOrWhiteSpace($guid) -and
        $script:AreaGeometryValidationCache.ContainsKey(
            $guid.ToLowerInvariant()
        )
    ) {
        return $script:AreaGeometryValidationCache[$guid.ToLowerInvariant()]
    }
    $validation = Test-VanillaAreaGeometry -Polygon @($Area.polygon)
    if (-not [string]::IsNullOrWhiteSpace($guid)) {
        $script:AreaGeometryValidationCache[$guid.ToLowerInvariant()] =
            $validation
    }
    return $validation
}

function Select-SettlementInvestigationAreas {
    param(
        [Parameter(Mandatory)]$Settlement,
        [Parameter(Mandatory)][object[]]$Areas,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Anchors,
        [AllowNull()]$Override = $null,
        [AllowNull()][hashtable]$CoverageByGuid = $null
    )

    $region = [string]$Settlement.gameRegion
    $settlementId = [string]$Settlement.id
    $denyGuids = @(
        Get-OptionalPropertyValue $Override 'denyGuids' @()
    )
    $forceIncludeGuids = @(
        Get-OptionalPropertyValue $Override 'forceIncludeGuids' @()
    )
    $forcedPrimaryGuid = [string](
        Get-OptionalPropertyValue $Override 'primaryGuid' ''
    )
    $forcedGuids = @($forceIncludeGuids)
    if (-not [string]::IsNullOrWhiteSpace($forcedPrimaryGuid)) {
        $forcedGuids += $forcedPrimaryGuid
    }
    $conflicts = @(
        $forcedGuids |
            Where-Object { $denyGuids -contains $_ } |
            Sort-Object -Unique
    )
    if ($conflicts.Count -gt 0) {
        throw (
            'Investigation area GUID is both forced and denied: {0}' -f
                ($conflicts -join ', ')
        )
    }

    $eligibleAreas = [Collections.Generic.List[object]]::new()
    $eligibleByGuid = @{}
    foreach ($area in @($Areas)) {
        if ([string]$area.region -ne $region) {
            continue
        }
        $classification = Get-AreaSemanticClassification -Area $area
        if (-not $classification.allowed) {
            continue
        }
        $guid = [string]$area.guid
        $entry = [pscustomobject]@{
            area = $area
            classification = $classification
        }
        $eligibleAreas.Add($entry)
        $eligibleByGuid[$guid.ToLowerInvariant()] = $entry
    }

    foreach ($guid in $forcedGuids) {
        $normalizedGuid = ([string]$guid).ToLowerInvariant()
        if (-not $eligibleByGuid.ContainsKey($normalizedGuid)) {
            throw "Forced investigation area is unavailable or unsafe: $guid"
        }
        $validation = Get-AreaGeometryValidation `
            -Area $eligibleByGuid[$normalizedGuid].area
        if (-not $validation.valid) {
            throw (
                'Forced investigation area has invalid geometry: {0} ({1})' -f
                    $guid,
                    $validation.reason
            )
        }
    }

    $primaryEntry = $null
    if (-not [string]::IsNullOrWhiteSpace($forcedPrimaryGuid)) {
        $primaryEntry = $eligibleByGuid[$forcedPrimaryGuid.ToLowerInvariant()]
    }
    else {
        $primaryOptions = @(
            $eligibleAreas |
                Where-Object {
                    $_.classification.category -eq 'primary' -and
                    -not ($denyGuids -contains [string]$_.area.guid)
                } |
                Sort-Object `
                    @{ Expression = {
                        $semanticText = '{0} {1}' -f
                            $_.area.name,
                            $_.area.editorLayer
                        if ($semanticText -match [regex]::Escape($settlementId)) {
                            0
                        }
                        else {
                            1
                        }
                    } },
                    @{ Expression = {
                        if (
                            $null -ne $Settlement.center -and
                            (Test-AreaContainsPoint `
                                -Area $_.area `
                                -Point $Settlement.center)
                        ) { 0 } else { 1 }
                    } },
                    @{ Expression = {
                        Get-AreaCenterDistance `
                            -Area $_.area `
                            -Settlement $Settlement
                    } },
                    @{ Expression = { [string]$_.area.guid } }
        )
        foreach ($primaryOption in $primaryOptions) {
            $validation = Get-AreaGeometryValidation `
                -Area $primaryOption.area
            if ($validation.valid) {
                $primaryEntry = $primaryOption
                break
            }
        }
    }
    if ($null -eq $primaryEntry) {
        throw "No safe primary investigation area for $region/$settlementId."
    }

    $selected = [Collections.Generic.List[object]]::new()
    $selectedGuids = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $rejectedGeometryGuids = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $selected.Add($primaryEntry.area)
    $null = $selectedGuids.Add([string]$primaryEntry.area.guid)
    foreach ($guid in $forceIncludeGuids) {
        $entry = $eligibleByGuid[([string]$guid).ToLowerInvariant()]
        if ($selectedGuids.Add([string]$entry.area.guid)) {
            $selected.Add($entry.area)
        }
    }

    while ($true) {
        $uncovered = [Collections.Generic.List[object]]::new()
        for ($anchorIndex = 0; $anchorIndex -lt $Anchors.Count; $anchorIndex++) {
            $anchor = $Anchors[$anchorIndex]
            $covered = $false
            foreach ($area in $selected) {
                if (Test-AreaContainsPoint `
                    -Area $area `
                    -Point (Get-AnchorPoint $anchor)) {
                    $covered = $true
                    break
                }
            }
            if (-not $covered) {
                $uncovered.Add($anchor)
            }
        }
        if ($uncovered.Count -eq 0) {
            break
        }

        $ranked = @(
            $uncoveredIdSet = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            for ($index = 0; $index -lt $uncovered.Count; $index++) {
                $null = $uncoveredIdSet.Add(
                    (Get-AnchorId $uncovered[$index] $index)
                )
            }
            foreach ($entry in $eligibleAreas) {
                $guid = [string]$entry.area.guid
                if (
                    $selectedGuids.Contains($guid) -or
                    $rejectedGeometryGuids.Contains($guid) -or
                    $denyGuids -contains $guid
                ) {
                    continue
                }
                $normalizedGuid = $guid.ToLowerInvariant()
                if (
                    $null -ne $CoverageByGuid -and
                    $CoverageByGuid.ContainsKey($normalizedGuid)
                ) {
                    $newCoverage = @(
                        $CoverageByGuid[$normalizedGuid] |
                            Where-Object { $uncoveredIdSet.Contains([string]$_) }
                    )
                    $surfaceArea = Get-OptionalPropertyValue `
                        $entry.area `
                        'surfaceArea' `
                        $null
                    if ($null -eq $surfaceArea) {
                        $surfaceArea = Get-PolygonSurfaceArea `
                            -Polygon @($entry.area.polygon)
                    }
                    $score = [pscustomobject]@{
                        guid = $guid
                        newCoverage = $newCoverage.Count
                        coveredAnchorIds = $newCoverage
                        semanticStability =
                            [int]$entry.classification.stability
                        excessSurface = [double]$surfaceArea
                        centerDistance = Get-AreaCenterDistance `
                            -Area $entry.area `
                            -Settlement $Settlement
                    }
                }
                else {
                    $score = Get-InvestigationAreaScore `
                        -Area $entry.area `
                        -UncoveredAnchors @($uncovered) `
                        -Settlement $Settlement
                }
                if ($score.newCoverage -gt 0) {
                    [pscustomobject]@{
                        area = $entry.area
                        score = $score
                    }
                }
            }
        )
        $ranked = @(
            $ranked |
                Sort-Object `
                    @{ Expression = { -[int]$_.score.newCoverage } },
                    @{ Expression = {
                        -[int]$_.score.semanticStability
                    } },
                    @{ Expression = { [double]$_.score.excessSurface } },
                    @{ Expression = { [double]$_.score.centerDistance } },
                    @{ Expression = { [string]$_.score.guid } }
        )
        $winner = $null
        foreach ($rankedEntry in $ranked) {
            $validation = Get-AreaGeometryValidation `
                -Area $rankedEntry.area
            if ($validation.valid) {
                $winner = $rankedEntry.area
                break
            }
            $null = $rejectedGeometryGuids.Add(
                [string]$rankedEntry.area.guid
            )
        }
        if ($null -eq $winner) {
            $uncoveredIds = [Collections.Generic.List[string]]::new()
            for ($index = 0; $index -lt $uncovered.Count; $index++) {
                $uncoveredIds.Add((Get-AnchorId $uncovered[$index] $index))
            }
            throw (
                'Uncovered investigation anchors for {0}/{1}: {2}' -f
                    $region,
                    $settlementId,
                    ($uncoveredIds -join ', ')
            )
        }
        $selected.Add($winner)
        $null = $selectedGuids.Add([string]$winner.guid)
    }

    return [pscustomobject]@{
        gameRegion = $region
        settlement = $settlementId
        primaryGuid = [string]$primaryEntry.area.guid
        areaGuids = @($selected | ForEach-Object { [string]$_.guid })
        areas = @($selected)
        anchorCount = $Anchors.Count
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-VanillaAreaPolygon',
    'Get-PolygonBounds',
    'Get-PolygonSurfaceArea',
    'Test-VanillaAreaGeometry',
    'Get-AreaSemanticClassification',
    'Get-InvestigationAreaScore',
    'Select-SettlementInvestigationAreas'
)
