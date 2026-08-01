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

function Format-InvariantNumber {
    param([double]$Value)

    return $Value.ToString(
        '0.######',
        [Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-StableAreaIdentity {
    param([Parameter(Mandatory)][string]$Seed)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Seed))
    }
    finally {
        $sha.Dispose()
    }
    $hex = [Convert]::ToHexString($hash).ToLowerInvariant()
    return [pscustomobject]@{
        entityGuid = '{0}-{1}-{2}' -f `
            $hex.Substring(0, 8), `
            $hex.Substring(8, 4), `
            $hex.Substring(12, 4)
        entityId = 1800000 + (
            [Convert]::ToInt32($hex.Substring(16, 6), 16) % 100000
        )
    }
}

function Escape-LuaString {
    param([string]$Value)

    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Text
    )

    $parent = Split-Path -Parent $LiteralPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    [IO.File]::WriteAllText(
        $LiteralPath,
        $Text,
        [Text.UTF8Encoding]::new($false)
    )
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

$regionContracts = @{}
foreach ($region in @($policy.regions)) {
    foreach (
        $requiredName in @(
            'id',
            'levelHolderName',
            'levelHolderGuid',
            'questHolderName',
            'questHolderGuid'
        )
    ) {
        $required = $region.PSObject.Properties[$requiredName]
        if (
            $null -eq $required -or
            [string]::IsNullOrWhiteSpace([string]$required.Value)
        ) {
            throw "Investigation area region is missing '$requiredName'."
        }
    }
    if ($regionContracts.ContainsKey([string]$region.id)) {
        throw "Duplicate investigation area region: $($region.id)"
    }
    $regionContracts[[string]$region.id] = $region
}
if ($regionContracts.Count -eq 0) {
    throw 'Investigation area policy must contain a regional resolver contract.'
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
    if (-not $regionContracts.ContainsKey([string]$area.gameRegion)) {
        throw "Investigation area '$areaKey' has no regional resolver contract."
    }

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

$seenEntityIds = @{}
$seenEntityGuids = @{}
$seenEntityNames = @{}
$seenAliases = @{}
$areaOutputs = foreach ($area in @($generatedAreas)) {
    $geometryPoints = @(
        $area.anchors | ForEach-Object {
            [pscustomobject]@{
                x = [double]$_.x
                y = [double]$_.y
            }
        }
    )
    $hull = @(Get-ConvexHull -Points $geometryPoints)
    $expanded = @(
        Expand-Polygon `
            -Polygon $hull `
            -PaddingMeters ([double]$area.paddingMeters)
    )
    $polygon = @(
        Add-DeterministicIrregularity `
            -Polygon $expanded `
            -Seed ([string]$area.identitySeed) `
            -MinVertices ([int]$area.minVertices) `
            -MaxVertices ([int]$area.maxVertices) `
            -Amplitude ([double]$area.irregularityMeters)
    )
    $polygon = @(
        Assert-InvestigationPolygon `
            -Polygon $polygon `
            -MinVertices ([int]$area.minVertices) `
            -MaxVertices ([int]$area.maxVertices)
    )

    $outsideAnchors = @(
        $area.anchors | Where-Object {
            -not (Test-PointInPolygon `
                -Point ([pscustomobject]@{
                    x = [double]$_.x
                    y = [double]$_.y
                }) `
                -Polygon $polygon)
        }
    )
    if ($outsideAnchors.Count -gt 0) {
        throw (
            "Investigation area '$($area.id)' excludes anchors: " +
            (($outsideAnchors | ForEach-Object { $_.id }) -join ', ')
        )
    }

    $identity = Get-StableAreaIdentity -Seed ([string]$area.identitySeed)
    foreach (
        $identityCheck in @(
            @($seenEntityIds, [string]$identity.entityId, 'EntityId'),
            @($seenEntityGuids, [string]$identity.entityGuid, 'EntityGuid'),
            @($seenEntityNames, [string]$area.entityName, 'entity name'),
            @($seenAliases, [string]$area.alias, 'area alias')
        )
    ) {
        if ($identityCheck[0].ContainsKey($identityCheck[1])) {
            throw "Duplicate investigation area $($identityCheck[2]): $($identityCheck[1])"
        }
        $identityCheck[0][$identityCheck[1]] = $true
    }

    $originX = [double](
        $polygon | ForEach-Object { [double]$_.x } |
            Measure-Object -Average
    ).Average
    $originY = [double](
        $polygon | ForEach-Object { [double]$_.y } |
            Measure-Object -Average
    ).Average
    $originZ = [double](
        $area.anchors | ForEach-Object { [double]$_.z } |
            Measure-Object -Average
    ).Average
    $localPointLines = @(
        $polygon | ForEach-Object {
            $localX = [double]$_.x - $originX
            $localY = [double]$_.y - $originY
            '        <Point Pos="{0},{1},-0.1" ObstructSound="0" />' -f `
                (Format-InvariantNumber $localX), `
                (Format-InvariantNumber $localY)
        }
    )
    $entityXml = @(
        '  <Entity Name="{0}" Pos="{1},{2},{3}" EntityClass="SmartAreaShape" EntityId="{4}" EntityGuid="{5}" CastShadowMinSpec="1" EditorLayer="Main/_quest/activity/darkpassengertest/static">' -f `
            [Security.SecurityElement]::Escape([string]$area.entityName), `
            (Format-InvariantNumber $originX), `
            (Format-InvariantNumber $originY), `
            (Format-InvariantNumber $originZ), `
            $identity.entityId, `
            $identity.entityGuid
        '    <Properties guidSmartAreaTemplate="{0}" bSaved_by_game="0" />' -f `
            [Security.SecurityElement]::Escape(
                [string]$area.smartAreaTemplateGuid
            )
        '    <Area Id="0" Group="0" Proximity="0" Priority="0" Height="500">'
        '      <Points>'
        $localPointLines
        '      </Points>'
        '      <Roof ObstructSound="0" />'
        '      <Floor ObstructSound="0" />'
        '    </Area>'
        '  </Entity>'
    ) -join "`r`n"

    $xs = @($polygon | ForEach-Object { [double]$_.x })
    $ys = @($polygon | ForEach-Object { [double]$_.y })
    [pscustomobject]@{
        id = [string]$area.id
        gameRegion = [string]$area.gameRegion
        settlement = [string]$area.settlement
        alias = [string]$area.alias
        entityName = [string]$area.entityName
        entityId = [int]$identity.entityId
        entityGuid = [string]$identity.entityGuid
        vertexCount = $polygon.Count
        anchorCount = $area.anchors.Count
        residentAnchorCount = @(
            $area.anchors | Where-Object { $_.kind -eq 'resident' }
        ).Count
        poiAnchorCount = @(
            $area.anchors | Where-Object { $_.kind -eq 'poi' }
        ).Count
        polygonArea = [math]::Abs((Get-PolygonSignedArea -Polygon $polygon))
        bounds = [ordered]@{
            minX = ($xs | Measure-Object -Minimum).Minimum
            maxX = ($xs | Measure-Object -Maximum).Maximum
            minY = ($ys | Measure-Object -Minimum).Minimum
            maxY = ($ys | Measure-Object -Maximum).Maximum
        }
        origin = [ordered]@{ x = $originX; y = $originY; z = $originZ }
        polygon = $polygon
        entityXml = $entityXml
    }
}

foreach (
    $regionGroup in @(
        $areaOutputs | Group-Object gameRegion | Sort-Object Name
    )
) {
    $regionId = [string]$regionGroup.Name
    $region = $regionContracts[$regionId]
    $orderedAreas = @($regionGroup.Group | Sort-Object id)
    $entityFragmentText = @(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<Objects>'
        ($orderedAreas | ForEach-Object { $_.entityXml })
        '</Objects>'
        ''
    ) -join "`r`n"
    Write-Utf8NoBom `
        -LiteralPath (Join-Path $GeneratedRoot "$regionId.entities.xml") `
        -Text $entityFragmentText

    $areaWaitingLinks = @(
        $orderedAreas | ForEach-Object {
            @(
                '    <WaitingLink SourceId="{0}" TargetId="{1}">' -f `
                    $region.questHolderGuid, $_.entityGuid
                '      <LinkDefinition>asset[&apos;{0}&apos;]</LinkDefinition>' -f `
                    [Security.SecurityElement]::Escape([string]$_.alias)
                '    </WaitingLink>'
            ) -join "`r`n"
        }
    )
    $waitingLinksText = @(
        '<?xml version="1.0" encoding="us-ascii"?>'
        '<StaticLinksInfo version="1">'
        '  <WaitingLinks>'
        ('    <WaitingLink SourceId="{0}" TargetId="{1}">' -f `
            $region.levelHolderGuid, $region.questHolderGuid)
        '      <LinkDefinition>module</LinkDefinition>'
        '    </WaitingLink>'
        $areaWaitingLinks
        '  </WaitingLinks>'
        '  <StreamableTargets />'
        '</StaticLinksInfo>'
        ''
    ) -join "`r`n"
    $waitingLinksPath = Join-Path $StageRoot `
        "Data\Levels\$regionId\waitinglinks.xml"
    Write-Utf8NoBom -LiteralPath $waitingLinksPath -Text $waitingLinksText
}

$manifestAreas = @(
    $areaOutputs | Sort-Object gameRegion, id | ForEach-Object {
        [ordered]@{
            id = $_.id
            gameRegion = $_.gameRegion
            settlement = $_.settlement
            alias = $_.alias
            entityName = $_.entityName
            entityId = $_.entityId
            entityGuid = $_.entityGuid
            vertexCount = $_.vertexCount
            anchorCount = $_.anchorCount
            residentAnchorCount = $_.residentAnchorCount
            poiAnchorCount = $_.poiAnchorCount
            polygonArea = $_.polygonArea
            bounds = $_.bounds
            origin = $_.origin
        }
    }
)
$manifest = [ordered]@{
    schemaVersion = 1
    areas = $manifestAreas
}
Write-Utf8NoBom `
    -LiteralPath (Join-Path $GeneratedRoot 'manifest.json') `
    -Text (($manifest | ConvertTo-Json -Depth 100) + "`n")

$luaLines = [Collections.Generic.List[string]]::new()
$luaLines.Add('DarkPassengerInvestigationAreaCatalog = {')
$luaLines.Add('    schemaVersion = 1,')
foreach (
    $regionGroup in @(
        $areaOutputs | Group-Object gameRegion | Sort-Object Name
    )
) {
    $regionId = [string]$regionGroup.Name
    $region = $regionContracts[$regionId]
    $luaLines.Add(
        '    ["{0}"] = {{' -f (Escape-LuaString $regionId)
    )
    $luaLines.Add(
        '        levelHolderName = "{0}",' -f
            (Escape-LuaString ([string]$region.levelHolderName))
    )
    $luaLines.Add(
        '        questHolderName = "{0}",' -f
            (Escape-LuaString ([string]$region.questHolderName))
    )
    foreach ($area in @($regionGroup.Group | Sort-Object id)) {
        $luaLines.Add(
            '        ["{0}"] = {{' -f (Escape-LuaString $area.id)
        )
        $luaLines.Add(
            '            alias = "{0}",' -f (Escape-LuaString $area.alias)
        )
        $luaLines.Add(
            '            entityName = "{0}",' -f
                (Escape-LuaString $area.entityName)
        )
        $luaLines.Add(
            '            entityGuid = "{0}",' -f
                (Escape-LuaString $area.entityGuid)
        )
        $luaLines.Add('        },')
    }
    $luaLines.Add('    },')
}
$luaLines.Add('}')
$luaLines.Add('')
$luaCatalogPath = Join-Path $StageRoot `
    'Data\Scripts\mods\generated\dp_investigation_area_catalog.lua'
Write-Utf8NoBom `
    -LiteralPath $luaCatalogPath `
    -Text ($luaLines -join "`r`n")

Write-Host (
    'Generated investigation areas: ' +
    (($generatedAreas | ForEach-Object {
        "$($_.gameRegion)/$($_.settlement) anchors=$($_.anchors.Count)"
    }) -join ', ')
)
