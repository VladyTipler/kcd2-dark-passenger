param(
    [Parameter(Mandatory)]
    [string]$PolicyPath,

    [Parameter(Mandatory)]
    [string]$VictimCatalogPath,

    [Parameter(Mandatory)]
    [string]$GeneratedRoot,

    [Parameter(Mandatory)]
    [string]$StageRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$geometryModule = Join-Path $PSScriptRoot 'InvestigationAreaGeometry.psm1'
if (-not (Test-Path -LiteralPath $geometryModule -PathType Leaf)) {
    throw "Investigation area geometry module not found: $geometryModule"
}
Import-Module $geometryModule -Force

function Read-JsonDocument {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "$Label not found: $LiteralPath"
    }
    try {
        return Get-Content -LiteralPath $LiteralPath -Raw |
            ConvertFrom-Json -Depth 100
    }
    catch {
        throw "$Label is not valid JSON: $($_.Exception.Message)"
    }
}

function Get-OptionalValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $DefaultValue
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }
    return $property.Value
}

function Assert-FiniteCoordinate {
    param([double]$Value, [string]$Label)

    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
        throw "$Label must be finite."
    }
}

$policy = Read-JsonDocument -LiteralPath $PolicyPath -Label 'Area policy'
$victimCatalog = Read-JsonDocument `
    -LiteralPath $VictimCatalogPath `
    -Label 'Victim catalogue'

if ([int]$policy.schemaVersion -ne 1) {
    throw "Unsupported investigation area policy schema: $($policy.schemaVersion)"
}
if ([int]$victimCatalog.schemaVersion -ne 2) {
    throw "Unsupported victim catalogue schema: $($victimCatalog.schemaVersion)"
}
if (@($policy.areas).Count -eq 0) {
    throw 'Investigation area policy must contain at least one area.'
}

$seenAreaKeys = @{}
$generatedAreas = foreach ($area in @($policy.areas)) {
    foreach (
        $requiredName in @(
            'id',
            'gameRegion',
            'settlement',
            'alias',
            'entityName',
            'identitySeed',
            'smartAreaTemplateGuid'
        )
    ) {
        $required = $area.PSObject.Properties[$requiredName]
        if (
            $null -eq $required -or
            [string]::IsNullOrWhiteSpace([string]$required.Value)
        ) {
            throw "Investigation area is missing required field '$requiredName'."
        }
    }

    $areaKey = "$($area.gameRegion)|$($area.settlement)|$($area.id)"
    if ($seenAreaKeys.ContainsKey($areaKey)) {
        throw "Duplicate investigation area policy key: $areaKey"
    }
    $seenAreaKeys[$areaKey] = $true

    $paddingMeters = [double](
        Get-OptionalValue `
            -Object $area `
            -Name 'paddingMeters' `
            -DefaultValue $policy.defaults.paddingMeters
    )
    $minVertices = [int](
        Get-OptionalValue `
            -Object $area `
            -Name 'minVertices' `
            -DefaultValue $policy.defaults.minVertices
    )
    $maxVertices = [int](
        Get-OptionalValue `
            -Object $area `
            -Name 'maxVertices' `
            -DefaultValue $policy.defaults.maxVertices
    )
    $irregularityMeters = [double](
        Get-OptionalValue `
            -Object $area `
            -Name 'irregularityMeters' `
            -DefaultValue $policy.defaults.irregularityMeters
    )
    if ($paddingMeters -lt 0 -or $irregularityMeters -lt 0) {
        throw "Investigation area '$areaKey' has a negative geometry distance."
    }
    if ($minVertices -lt 3 -or $maxVertices -lt $minVertices) {
        throw "Investigation area '$areaKey' has an invalid vertex range."
    }

    $residents = @(
        $victimCatalog.candidates |
            Where-Object {
                $_.enabled -eq $true -and
                $_.gameRegion -eq $area.gameRegion -and
                $_.settlement -eq $area.settlement
            } |
            Sort-Object slot
    )
    if ($residents.Count -eq 0) {
        throw "Investigation area '$areaKey' has no enabled resident anchors."
    }

    $anchorsByCoordinate = [ordered]@{}
    foreach ($resident in $residents) {
        $x = [double]$resident.position.x
        $y = [double]$resident.position.y
        $z = [double]$resident.position.z
        Assert-FiniteCoordinate $x "Resident $($resident.slot) x"
        Assert-FiniteCoordinate $y "Resident $($resident.slot) y"
        Assert-FiniteCoordinate $z "Resident $($resident.slot) z"
        $coordinateKey = '{0:R}|{1:R}' -f $x, $y
        if (-not $anchorsByCoordinate.Contains($coordinateKey)) {
            $anchorsByCoordinate[$coordinateKey] = [ordered]@{
                id = "candidate-$($resident.slot)"
                kind = 'resident'
                sourceSlot = [int]$resident.slot
                x = $x
                y = $y
                z = $z
            }
        }
    }

    foreach ($poi in @(Get-OptionalValue $area 'poiAnchors' @())) {
        if ([string]::IsNullOrWhiteSpace([string]$poi.id)) {
            throw "Investigation area '$areaKey' contains a POI without an id."
        }
        $x = [double]$poi.x
        $y = [double]$poi.y
        $z = [double]$poi.z
        Assert-FiniteCoordinate $x "POI $($poi.id) x"
        Assert-FiniteCoordinate $y "POI $($poi.id) y"
        Assert-FiniteCoordinate $z "POI $($poi.id) z"
        $coordinateKey = '{0:R}|{1:R}' -f $x, $y
        if (-not $anchorsByCoordinate.Contains($coordinateKey)) {
            $anchorsByCoordinate[$coordinateKey] = [ordered]@{
                id = [string]$poi.id
                kind = 'poi'
                x = $x
                y = $y
                z = $z
            }
        }
    }

    $anchors = @(
        $anchorsByCoordinate.Values |
            Sort-Object kind, id
    )
    [ordered]@{
        id = [string]$area.id
        gameRegion = [string]$area.gameRegion
        settlement = [string]$area.settlement
        alias = [string]$area.alias
        entityName = [string]$area.entityName
        identitySeed = [string]$area.identitySeed
        smartAreaTemplateGuid = [string]$area.smartAreaTemplateGuid
        paddingMeters = $paddingMeters
        minVertices = $minVertices
        maxVertices = $maxVertices
        irregularityMeters = $irregularityMeters
        anchors = $anchors
    }
}

New-Item -ItemType Directory -Force -Path $GeneratedRoot, $StageRoot |
    Out-Null
$summary = [ordered]@{
    schemaVersion = 1
    areas = @($generatedAreas)
}
$summaryText = $summary | ConvertTo-Json -Depth 100
$summaryPath = Join-Path $GeneratedRoot 'anchors.json'
[IO.File]::WriteAllText(
    $summaryPath,
    $summaryText + "`n",
    [Text.UTF8Encoding]::new($false)
)

Write-Host (
    'Prepared investigation area anchors: ' +
    (($generatedAreas | ForEach-Object {
        "$($_.gameRegion)/$($_.settlement)=$($_.anchors.Count)"
    }) -join ', ')
)
