[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReferenceDataRoot,
    [Parameter(Mandatory)][string]$DevGameRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateSet('kutnohorsko', 'trosecko')]
    [string[]]$Regions = @('kutnohorsko', 'trosecko')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$selectionModule = Join-Path `
    $PSScriptRoot `
    'VanillaInvestigationAreaSelection.psm1'
if (-not (Test-Path -LiteralPath $selectionModule -PathType Leaf)) {
    throw "Vanilla area selection module not found: $selectionModule"
}
Import-Module $selectionModule

$regionConfig = @{
    kutnohorsko = @{
        missionFile = 'kutnohorsko\kut_objects_mission0.xml'
        levelName = 'kutnohorsko'
    }
    trosecko = @{
        missionFile = 'trosecko\tros_objects_mission0.xml'
        levelName = 'trosecko'
    }
}

function Get-TriggerAreaMissionRecords {
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$MissionPath
    )

    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.IgnoreComments = $true
    $settings.IgnoreWhitespace = $true
    $reader = [Xml.XmlReader]::Create($MissionPath, $settings)
    $records = [Collections.Generic.List[object]]::new()
    try {
        while ($reader.Read()) {
            if (
                $reader.NodeType -ne [Xml.XmlNodeType]::Element -or
                $reader.LocalName -ne 'Entity' -or
                $reader.GetAttribute('EntityClass') -ne 'TriggerArea'
            ) {
                continue
            }
            $records.Add([pscustomobject]@{
                region = $Region
                name = [string]$reader.GetAttribute('Name')
                guid = [string]$reader.GetAttribute('EntityGuid')
                entityId = [string]$reader.GetAttribute('EntityId')
                editorLayer = [string]$reader.GetAttribute('EditorLayer')
            })
        }
    }
    finally {
        $reader.Dispose()
    }
    return @($records)
}

function Get-GameRelativeLayerPath {
    param(
        [Parameter(Mandatory)][string]$LevelName,
        [Parameter(Mandatory)][string]$EditorLayer
    )

    $normalizedLayer = $EditorLayer.Replace('\', '/').Trim('/')
    return "Data/Levels/$LevelName/Layers/$normalizedLayer.lyr"
}

function Add-Rejection {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][string]$LayerPath,
        [AllowEmptyString()][string]$Detail = ''
    )

    $script:rejections.Add([pscustomobject][ordered]@{
        region = $Record.region
        name = $Record.name
        guid = $Record.guid
        entityId = $Record.entityId
        editorLayer = $Record.editorLayer
        layerPath = $LayerPath
        reason = $Reason
        detail = $Detail
    })
}

$areas = [Collections.Generic.List[object]]::new()
$script:rejections = [Collections.Generic.List[object]]::new()

foreach ($region in @($Regions | Sort-Object -Unique)) {
    $configuration = $regionConfig[$region]
    $missionPath = Join-Path `
        $ReferenceDataRoot `
        $configuration.missionFile
    if (-not (Test-Path -LiteralPath $missionPath -PathType Leaf)) {
        throw "Mission-object index not found: $missionPath"
    }

    $missionRecords = @(
        Get-TriggerAreaMissionRecords `
            -Region $region `
            -MissionPath $missionPath
    )
    $layerGroups = @($missionRecords | Group-Object -Property editorLayer)
    foreach ($layerGroup in $layerGroups) {
        $editorLayer = [string]$layerGroup.Name
        $relativeLayerPath = Get-GameRelativeLayerPath `
            -LevelName $configuration.levelName `
            -EditorLayer $editorLayer
        $absoluteLayerPath = Join-Path `
            $DevGameRoot `
            $relativeLayerPath.Replace('/', [IO.Path]::DirectorySeparatorChar)

        if (-not (Test-Path -LiteralPath $absoluteLayerPath -PathType Leaf)) {
            foreach ($record in @($layerGroup.Group)) {
                Add-Rejection `
                    -Record $record `
                    -Reason 'layer_missing' `
                    -LayerPath $relativeLayerPath
            }
            continue
        }

        $pending = @{}
        foreach ($record in @($layerGroup.Group)) {
            $key = '{0}|{1}' -f $record.name, $record.guid
            $pending[$key.ToLowerInvariant()] = $record
        }

        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.IgnoreComments = $true
        $settings.IgnoreWhitespace = $true
        try {
            $reader = [Xml.XmlReader]::Create($absoluteLayerPath, $settings)
            try {
                $null = $reader.Read()
                while (-not $reader.EOF) {
                    if (
                        $reader.NodeType -eq [Xml.XmlNodeType]::Element -and
                        $reader.LocalName -eq 'ObjectGUID'
                    ) {
                        $objectName = [string]$reader.GetAttribute('Name')
                        $fullGuid = [string]$reader.GetAttribute('Instance')
                        $shortGuid = if ($fullGuid.Length -ge 18) {
                            $fullGuid.Substring(0, 18)
                        }
                        else {
                            $fullGuid
                        }
                        $key = ('{0}|{1}' -f $objectName, $shortGuid).
                            ToLowerInvariant()
                        if ($pending.ContainsKey($key)) {
                            $record = $pending[$key]
                            Add-Rejection `
                                -Record $record `
                                -Reason `
                                    'prefab_instance_geometry_unavailable' `
                                -LayerPath $relativeLayerPath
                            $pending.Remove($key)
                            if ($pending.Count -eq 0) {
                                break
                            }
                        }
                        $reader.Skip()
                        continue
                    }
                    if (
                        $reader.NodeType -eq [Xml.XmlNodeType]::Element -and
                        $reader.LocalName -eq 'Object' -and
                        $reader.GetAttribute('EntityClass') -eq 'TriggerArea'
                    ) {
                        $objectName = [string]$reader.GetAttribute('Name')
                        $fullGuid = [string]$reader.GetAttribute('Id')
                        $shortGuid = if ($fullGuid.Length -ge 18) {
                            $fullGuid.Substring(0, 18)
                        }
                        else {
                            $fullGuid
                        }
                        $key = ('{0}|{1}' -f $objectName, $shortGuid).
                            ToLowerInvariant()
                        if ($pending.ContainsKey($key)) {
                            $record = $pending[$key]
                            $outerXml = $reader.ReadOuterXml()
                            try {
                                [xml]$objectDocument = $outerXml
                                $areaObject = $objectDocument.Object
                                $polygon = @(
                                    ConvertTo-VanillaAreaPolygon `
                                        -AreaObject $areaObject
                                )
                                $validation = Test-VanillaAreaGeometry `
                                    -Polygon $polygon `
                                    -SkipSelfIntersection
                                if (-not $validation.valid) {
                                    Add-Rejection `
                                        -Record $record `
                                        -Reason "geometry_$($validation.reason)" `
                                        -LayerPath $relativeLayerPath
                                }
                                else {
                                    $height = 0.0
                                    if (-not [string]::IsNullOrWhiteSpace(
                                        [string]$areaObject.GetAttribute(
                                            'Height'
                                        )
                                    )) {
                                        $height = [double]::Parse(
                                            [string]$areaObject.GetAttribute(
                                                'Height'
                                            ),
                                            [Globalization.CultureInfo]::
                                                InvariantCulture
                                        )
                                    }
                                    $label = ''
                                    $properties = $areaObject.SelectSingleNode(
                                        'Properties'
                                    )
                                    if ($null -ne $properties) {
                                        $label = [string]$properties.GetAttribute(
                                            'Label'
                                        )
                                    }
                                    $areas.Add([pscustomobject][ordered]@{
                                        region = $record.region
                                        name = $record.name
                                        guid = $record.guid
                                        fullGuid = $fullGuid
                                        entityId = $record.entityId
                                        editorLayer = $record.editorLayer
                                        layerPath = $relativeLayerPath
                                        label = $label
                                        height = $height
                                        polygon = $polygon
                                        bounds = Get-PolygonBounds `
                                            -Polygon $polygon
                                        surfaceArea = Get-PolygonSurfaceArea `
                                            -Polygon $polygon
                                    })
                                }
                            }
                            catch {
                                Add-Rejection `
                                    -Record $record `
                                    -Reason 'object_parse_error' `
                                    -LayerPath $relativeLayerPath `
                                    -Detail $_.Exception.Message
                            }
                            $pending.Remove($key)
                            if ($pending.Count -eq 0) {
                                break
                            }
                            continue
                        }
                        $reader.Skip()
                        continue
                    }
                    if (-not $reader.Read()) {
                        break
                    }
                }
            }
            finally {
                $reader.Dispose()
            }
        }
        catch {
            foreach ($record in @($pending.Values)) {
                Add-Rejection `
                    -Record $record `
                    -Reason 'layer_parse_error' `
                    -LayerPath $relativeLayerPath `
                    -Detail $_.Exception.Message
            }
            $pending.Clear()
        }

        foreach ($record in @($pending.Values)) {
            Add-Rejection `
                -Record $record `
                -Reason 'object_missing' `
                -LayerPath $relativeLayerPath
        }
    }
}

$catalog = [pscustomobject][ordered]@{
    schemaVersion = 1
    areas = @(
        $areas |
            Sort-Object region, guid, entityId
    )
    rejections = @(
        $script:rejections |
            Sort-Object region, guid, entityId, reason
    )
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$json = $catalog | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText(
    $OutputPath,
    $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)

Write-Host (
    'Exported vanilla TriggerAreas: areas={0} rejections={1}' -f
        @($catalog.areas).Count,
        @($catalog.rejections).Count
)
