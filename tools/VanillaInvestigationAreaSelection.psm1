Set-StrictMode -Version Latest

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

Export-ModuleMember -Function @(
    'ConvertTo-VanillaAreaPolygon',
    'Get-PolygonBounds',
    'Get-PolygonSurfaceArea',
    'Test-VanillaAreaGeometry'
)
