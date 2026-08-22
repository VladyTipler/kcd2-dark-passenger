Set-StrictMode -Version Latest

$script:Epsilon = 0.0000001

function ConvertTo-GeometryPoint {
    param([Parameter(Mandatory)]$Point)

    if ($null -eq $Point.x -or $null -eq $Point.y) {
        throw 'Investigation polygon point must contain x and y coordinates.'
    }

    $x = [double]$Point.x
    $y = [double]$Point.y
    if (
        [double]::IsNaN($x) -or [double]::IsInfinity($x) -or
        [double]::IsNaN($y) -or [double]::IsInfinity($y)
    ) {
        throw 'Investigation polygon coordinates must be finite.'
    }

    return [pscustomobject]@{ x = $x; y = $y }
}

function Get-CrossProduct {
    param($A, $B, $C)

    return (
        ([double]$B.x - [double]$A.x) *
        ([double]$C.y - [double]$A.y) -
        ([double]$B.y - [double]$A.y) *
        ([double]$C.x - [double]$A.x)
    )
}

function Test-PointOnSegment {
    param($Point, $Start, $End)

    if ([math]::Abs((Get-CrossProduct $Start $End $Point)) -gt $script:Epsilon) {
        return $false
    }

    return (
        [double]$Point.x -ge
            [math]::Min([double]$Start.x, [double]$End.x) - $script:Epsilon -and
        [double]$Point.x -le
            [math]::Max([double]$Start.x, [double]$End.x) + $script:Epsilon -and
        [double]$Point.y -ge
            [math]::Min([double]$Start.y, [double]$End.y) - $script:Epsilon -and
        [double]$Point.y -le
            [math]::Max([double]$Start.y, [double]$End.y) + $script:Epsilon
    )
}

function Test-SegmentsIntersect {
    param($A, $B, $C, $D)

    $abC = Get-CrossProduct $A $B $C
    $abD = Get-CrossProduct $A $B $D
    $cdA = Get-CrossProduct $C $D $A
    $cdB = Get-CrossProduct $C $D $B

    if (
        (($abC -gt $script:Epsilon -and $abD -lt -$script:Epsilon) -or
         ($abC -lt -$script:Epsilon -and $abD -gt $script:Epsilon)) -and
        (($cdA -gt $script:Epsilon -and $cdB -lt -$script:Epsilon) -or
         ($cdA -lt -$script:Epsilon -and $cdB -gt $script:Epsilon))
    ) {
        return $true
    }

    if (
        ([math]::Abs($abC) -le $script:Epsilon -and
            (Test-PointOnSegment $C $A $B)) -or
        ([math]::Abs($abD) -le $script:Epsilon -and
            (Test-PointOnSegment $D $A $B)) -or
        ([math]::Abs($cdA) -le $script:Epsilon -and
            (Test-PointOnSegment $A $C $D)) -or
        ([math]::Abs($cdB) -le $script:Epsilon -and
            (Test-PointOnSegment $B $C $D))
    ) {
        return $true
    }

    return $false
}

function Get-PolygonSignedArea {
    param([Parameter(Mandatory)][object[]]$Polygon)

    if ($Polygon.Count -lt 3) {
        return 0.0
    }

    $area = 0.0
    for ($index = 0; $index -lt $Polygon.Count; $index++) {
        $next = ($index + 1) % $Polygon.Count
        $area += (
            [double]$Polygon[$index].x * [double]$Polygon[$next].y -
            [double]$Polygon[$next].x * [double]$Polygon[$index].y
        )
    }
    return $area / 2.0
}

function Test-PointInPolygon {
    param(
        [Parameter(Mandatory)]$Point,
        [Parameter(Mandatory)][object[]]$Polygon
    )

    $candidate = ConvertTo-GeometryPoint $Point
    if ($Polygon.Count -lt 3) {
        return $false
    }

    $inside = $false
    for ($index = 0; $index -lt $Polygon.Count; $index++) {
        $next = ($index + 1) % $Polygon.Count
        $start = ConvertTo-GeometryPoint $Polygon[$index]
        $end = ConvertTo-GeometryPoint $Polygon[$next]

        if (Test-PointOnSegment $candidate $start $end) {
            return $true
        }

        $crossesY = (
            ([double]$start.y -gt [double]$candidate.y) -ne
            ([double]$end.y -gt [double]$candidate.y)
        )
        if ($crossesY) {
            $crossingX = (
                ([double]$end.x - [double]$start.x) *
                ([double]$candidate.y - [double]$start.y) /
                ([double]$end.y - [double]$start.y) +
                [double]$start.x
            )
            if ([double]$candidate.x -lt $crossingX) {
                $inside = -not $inside
            }
        }
    }

    return $inside
}

function Test-PolygonSelfIntersection {
    param([Parameter(Mandatory)][object[]]$Polygon)

    if ($Polygon.Count -lt 4) {
        return $false
    }

    for ($first = 0; $first -lt $Polygon.Count; $first++) {
        $firstNext = ($first + 1) % $Polygon.Count
        $a = ConvertTo-GeometryPoint $Polygon[$first]
        $b = ConvertTo-GeometryPoint $Polygon[$firstNext]

        for ($second = $first + 1; $second -lt $Polygon.Count; $second++) {
            $secondNext = ($second + 1) % $Polygon.Count
            if (
                $first -eq $second -or
                $firstNext -eq $second -or
                $secondNext -eq $first
            ) {
                continue
            }

            $c = ConvertTo-GeometryPoint $Polygon[$second]
            $d = ConvertTo-GeometryPoint $Polygon[$secondNext]
            if (Test-SegmentsIntersect $a $b $c $d) {
                return $true
            }
        }
    }

    return $false
}

function Get-ConvexHull {
    param([Parameter(Mandatory)][object[]]$Points)

    $unique = @{}
    foreach ($point in $Points) {
        $normalized = ConvertTo-GeometryPoint $point
        $key = '{0:R}|{1:R}' -f $normalized.x, $normalized.y
        if (-not $unique.ContainsKey($key)) {
            $unique[$key] = $normalized
        }
    }

    $sorted = @(
        $unique.Values |
            Sort-Object @{ Expression = { [double]$_.x } },
                        @{ Expression = { [double]$_.y } }
    )
    if ($sorted.Count -lt 3) {
        throw 'Convex hull requires at least three unique finite points.'
    }

    $lower = [Collections.Generic.List[object]]::new()
    foreach ($point in $sorted) {
        while (
            $lower.Count -ge 2 -and
            (Get-CrossProduct `
                $lower[$lower.Count - 2] `
                $lower[$lower.Count - 1] `
                $point) -le $script:Epsilon
        ) {
            $lower.RemoveAt($lower.Count - 1)
        }
        $lower.Add($point)
    }

    $upper = [Collections.Generic.List[object]]::new()
    for ($index = $sorted.Count - 1; $index -ge 0; $index--) {
        $point = $sorted[$index]
        while (
            $upper.Count -ge 2 -and
            (Get-CrossProduct `
                $upper[$upper.Count - 2] `
                $upper[$upper.Count - 1] `
                $point) -le $script:Epsilon
        ) {
            $upper.RemoveAt($upper.Count - 1)
        }
        $upper.Add($point)
    }

    $result = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $lower.Count - 1; $index++) {
        $result.Add($lower[$index])
    }
    for ($index = 0; $index -lt $upper.Count - 1; $index++) {
        $result.Add($upper[$index])
    }

    return @($result)
}

function Expand-Polygon {
    param(
        [Parameter(Mandatory)][object[]]$Polygon,
        [Parameter(Mandatory)][double]$PaddingMeters
    )

    if ($PaddingMeters -lt 0) {
        throw 'Investigation polygon padding cannot be negative.'
    }

    $points = @($Polygon | ForEach-Object { ConvertTo-GeometryPoint $_ })
    if ((Get-PolygonSignedArea -Polygon $points) -lt 0) {
        [array]::Reverse($points)
    }
    $centerX = ($points | Measure-Object -Property x -Average).Average
    $centerY = ($points | Measure-Object -Property y -Average).Average

    $expanded = foreach ($point in $points) {
        $dx = [double]$point.x - [double]$centerX
        $dy = [double]$point.y - [double]$centerY
        $distance = [math]::Sqrt($dx * $dx + $dy * $dy)
        if ($distance -le $script:Epsilon) {
            throw 'Investigation polygon vertex cannot equal its centroid.'
        }

        [pscustomobject]@{
            x = [double]$point.x + ($dx / $distance) * $PaddingMeters
            y = [double]$point.y + ($dy / $distance) * $PaddingMeters
        }
    }

    return @($expanded)
}

function Get-DeterministicFactor {
    param([string]$Seed, [int]$Index)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes("$Seed|$Index")
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    return 0.35 + ([double]$hash[0] / 255.0) * 0.65
}

function Add-DeterministicIrregularity {
    param(
        [Parameter(Mandatory)][object[]]$Polygon,
        [Parameter(Mandatory)][string]$Seed,
        [Parameter(Mandatory)][int]$MinVertices,
        [Parameter(Mandatory)][int]$MaxVertices,
        [Parameter(Mandatory)][double]$Amplitude
    )

    if ($MinVertices -lt 3 -or $MaxVertices -lt $MinVertices) {
        throw 'Investigation polygon vertex range is invalid.'
    }
    if ($Amplitude -lt 0) {
        throw 'Investigation polygon irregularity amplitude cannot be negative.'
    }

    $validated = @(
        Assert-InvestigationPolygon `
            -Polygon $Polygon `
            -MinVertices 3 `
            -MaxVertices $MaxVertices
    )
    $result = [Collections.Generic.List[object]]::new()
    foreach ($point in $validated) {
        $result.Add($point)
    }

    $insertIndex = 0
    while ($result.Count -lt $MinVertices) {
        $longestIndex = -1
        $longestLength = -1.0
        for ($index = 0; $index -lt $result.Count; $index++) {
            $next = ($index + 1) % $result.Count
            $dx = [double]$result[$next].x - [double]$result[$index].x
            $dy = [double]$result[$next].y - [double]$result[$index].y
            $length = [math]::Sqrt($dx * $dx + $dy * $dy)
            if ($length -gt $longestLength) {
                $longestLength = $length
                $longestIndex = $index
            }
        }

        $nextIndex = ($longestIndex + 1) % $result.Count
        $start = $result[$longestIndex]
        $end = $result[$nextIndex]
        $dx = [double]$end.x - [double]$start.x
        $dy = [double]$end.y - [double]$start.y
        $safeAmplitude = [math]::Min($Amplitude, $longestLength * 0.2)
        $offset = $safeAmplitude *
            (Get-DeterministicFactor -Seed $Seed -Index $insertIndex)
        $candidate = [pscustomobject]@{
            x = ([double]$start.x + [double]$end.x) / 2.0 +
                ($dy / $longestLength) * $offset
            y = ([double]$start.y + [double]$end.y) / 2.0 -
                ($dx / $longestLength) * $offset
        }

        if ($nextIndex -eq 0) {
            $result.Add($candidate)
        }
        else {
            $result.Insert($nextIndex, $candidate)
        }
        $insertIndex++
    }

    $final = @($result)
    if (Test-PolygonSelfIntersection -Polygon $final) {
        throw 'Deterministic irregularity produced a self-intersecting polygon.'
    }
    return $final
}

function Assert-InvestigationPolygon {
    param(
        [Parameter(Mandatory)][object[]]$Polygon,
        [Parameter(Mandatory)][int]$MinVertices,
        [Parameter(Mandatory)][int]$MaxVertices
    )

    if ($MinVertices -lt 3 -or $MaxVertices -lt $MinVertices) {
        throw 'Investigation polygon vertex range is invalid.'
    }

    $normalized = @($Polygon | ForEach-Object { ConvertTo-GeometryPoint $_ })
    if (
        $normalized.Count -lt $MinVertices -or
        $normalized.Count -gt $MaxVertices
    ) {
        throw "Investigation polygon must contain $MinVertices-$MaxVertices vertices."
    }

    $unique = @{}
    foreach ($point in $normalized) {
        $key = '{0:R}|{1:R}' -f $point.x, $point.y
        $unique[$key] = $true
    }
    if ($unique.Count -ne $normalized.Count) {
        throw 'Investigation polygon vertices must be unique.'
    }

    if (Test-PolygonSelfIntersection -Polygon $normalized) {
        throw 'Investigation polygon must not self-intersect.'
    }

    $area = Get-PolygonSignedArea -Polygon $normalized
    if ([math]::Abs($area) -le $script:Epsilon) {
        throw 'Investigation polygon must have a finite non-zero area.'
    }
    if ($area -lt 0) {
        [array]::Reverse($normalized)
    }

    return $normalized
}

Export-ModuleMember -Function @(
    'Get-PolygonSignedArea',
    'Test-PointInPolygon',
    'Test-PolygonSelfIntersection',
    'Get-ConvexHull',
    'Expand-Polygon',
    'Add-DeterministicIrregularity',
    'Assert-InvestigationPolygon'
)
