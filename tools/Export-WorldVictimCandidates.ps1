param(
    [string]$KuttenbergObjectsPath,
    [string]$TroskyObjectsPath,
    [string]$SoulTablePath,
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evidence\world-candidates.raw.json')
)

$ErrorActionPreference = 'Stop'

$referenceDataRoot = $env:KCD2_REFERENCE_DATA_ROOT
$devGameRoot = $env:KCD2_DEV_ROOT

if ([string]::IsNullOrWhiteSpace($KuttenbergObjectsPath)) {
    if ([string]::IsNullOrWhiteSpace($referenceDataRoot)) {
        throw 'Set KCD2_REFERENCE_DATA_ROOT or pass -KuttenbergObjectsPath.'
    }
    $KuttenbergObjectsPath = Join-Path $referenceDataRoot 'kutnohorsko\kut_objects_mission0.xml'
}
if ([string]::IsNullOrWhiteSpace($TroskyObjectsPath)) {
    if ([string]::IsNullOrWhiteSpace($referenceDataRoot)) {
        throw 'Set KCD2_REFERENCE_DATA_ROOT or pass -TroskyObjectsPath.'
    }
    $TroskyObjectsPath = Join-Path $referenceDataRoot 'trosecko\tros_objects_mission0.xml'
}
if ([string]::IsNullOrWhiteSpace($SoulTablePath)) {
    if ([string]::IsNullOrWhiteSpace($devGameRoot)) {
        throw 'Set KCD2_DEV_ROOT or pass -SoulTablePath.'
    }
    $SoulTablePath = Join-Path $devGameRoot 'Data\libs\CryHttp\xzar2\table-souls.json'
}

function Write-Utf8NoBom {
    param(
        [string]$LiteralPath,
        [string]$Content
    )

    $directory = Split-Path -Parent $LiteralPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $LiteralPath,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function ConvertTo-WorldPosition {
    param([Parameter(Mandatory)][string]$Position)

    $parts = @(
        $Position.Split(',') |
            ForEach-Object {
                [double]::Parse(
                    $_,
                    [System.Globalization.CultureInfo]::InvariantCulture
                )
            }
    )
    return [ordered]@{
        x = $parts[0]
        y = $parts[1]
        z = $parts[2]
    }
}

function Get-SettlementHint {
    param([string]$EditorLayer)

    if ($EditorLayer -match '^Main/[^/_]+_([^/]+)/') {
        return [string]$Matches[1]
    }
    return $null
}

function ConvertTo-WorldLink {
    param([Parameter(Mandatory)]$Link)

    return [ordered]@{
        name = [string]$Link.Name
        targetId = [string]$Link.TargetId
        targetGuid = [string]$Link.TargetGuid
    }
}

foreach ($path in @($KuttenbergObjectsPath, $TroskyObjectsPath, $SoulTablePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required source not found: $path"
    }
}

$soulTable = Get-Content -Raw -LiteralPath $SoulTablePath |
    ConvertFrom-Json -AsHashtable
$soulsByName = @{}
foreach ($soul in $soulTable.Values) {
    if ($soul.soul_name) {
        $soulsByName[[string]$soul.soul_name] = $soul
    }
}

$legacyCandidates = [System.Collections.Generic.List[object]]::new()
$actors = [System.Collections.Generic.List[object]]::new()
$containers = [System.Collections.Generic.List[object]]::new()

$regionSources = @(
    [ordered]@{ gameRegion = 'kutnohorsko'; objectsPath = $KuttenbergObjectsPath }
    [ordered]@{ gameRegion = 'trosecko'; objectsPath = $TroskyObjectsPath }
)

foreach ($regionSource in $regionSources) {
    [xml]$objects = Get-Content -Raw -LiteralPath $regionSource.objectsPath
    $shopStashTargetIds = [System.Collections.Generic.HashSet[string]]::new()
    $shopStashTargetGuids = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($link in $objects.SelectNodes('//Link[@Name="shopStash"]')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$link.TargetId)) {
            $null = $shopStashTargetIds.Add([string]$link.TargetId)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$link.TargetGuid)) {
            $null = $shopStashTargetGuids.Add([string]$link.TargetGuid)
        }
    }
    foreach ($entity in $objects.SelectNodes(
        '//Entity[starts-with(@EntityClass,"NPC")]'
    )) {
        $entityName = [string]$entity.Name
        $soul = $soulsByName[$entityName]
        if ($null -eq $soul) {
            continue
        }

        $links = @($entity.EntityLinks.Link)
        $homeLinks = @(
            $links |
                Where-Object {
                    $_.Name -eq 'home' -or $_.Name -like '_!home*'
                } |
                ForEach-Object { ConvertTo-WorldLink -Link $_ } |
                Sort-Object name, targetId, targetGuid
        )
        $workLinks = @(
            $links |
                Where-Object { $_.Name -match '^_@.*work' } |
                ForEach-Object { ConvertTo-WorldLink -Link $_ } |
                Sort-Object name, targetId, targetGuid
        )
        $linkNames = @($links | ForEach-Object { [string]$_.Name })
        $homeLink = @(
            $linkNames | Where-Object { $_ -like '_!home*' }
        ).Count -gt 0
        $workLink = @(
            $linkNames | Where-Object { $_ -like '_@villager_work*' }
        ).Count -gt 0
        $layer = [string]$entity.EditorLayer
        $settlementHint = Get-SettlementHint -EditorLayer $layer

        $record = [ordered]@{
            gameRegion = [string]$regionSource.gameRegion
            settlementHint = $settlementHint
            entityName = $entityName
            entityGuid = [string]$entity.EntityGuid
            soulGuid = [string]$soul.soul_id
            factionName = [string]$soul.faction_name
            characterName = [string]$soul.character_name
            position = ConvertTo-WorldPosition -Position ([string]$entity.Pos)
            editorLayer = $layer
            homeLinks = $homeLinks
            workLinks = $workLinks
            hasHomeLink = $homeLink
            hasVillagerWorkLink = $workLink
            permanentResidentEvidence = ($homeLink -and $workLink)
            source = [ordered]@{
                objects = [string]$regionSource.objectsPath
                souls = $SoulTablePath
            }
        }
        $actors.Add($record)
        if ([string]$entity.EntityClass -eq 'NPC') {
            $legacyCandidates.Add($record)
        }
    }

    foreach ($entity in $objects.SelectNodes('//Entity[@EntityClass="Stash"]')) {
        $layer = [string]$entity.EditorLayer
        $settlementHint = Get-SettlementHint -EditorLayer $layer
        if ([string]::IsNullOrWhiteSpace($settlementHint)) {
            continue
        }
        $containers.Add([ordered]@{
            gameRegion = [string]$regionSource.gameRegion
            settlementHint = $settlementHint
            entityName = [string]$entity.Name
            entityId = [string]$entity.EntityId
            entityGuid = [string]$entity.EntityGuid
            entityClass = [string]$entity.EntityClass
            shopStash = (
                $shopStashTargetIds.Contains([string]$entity.EntityId) -or
                $shopStashTargetGuids.Contains([string]$entity.EntityGuid)
            )
            position = ConvertTo-WorldPosition -Position ([string]$entity.Pos)
            editorLayer = $layer
            source = [ordered]@{
                objects = [string]$regionSource.objectsPath
            }
        })
    }
}

$document = [ordered]@{
    schemaVersion = 1
    candidates = @($legacyCandidates | Sort-Object gameRegion, entityName)
    actors = @($actors | Sort-Object gameRegion, entityName)
    containers = @(
        $containers | Sort-Object gameRegion, settlementHint, entityName, entityGuid
    )
}
$json = $document | ConvertTo-Json -Depth 8
Write-Utf8NoBom -LiteralPath $OutputPath -Content ($json + "`n")
Write-Host (
    "Exported $($actors.Count) joined actors, " +
    "$($legacyCandidates.Count) legacy victim-source records and " +
    "$($containers.Count) settlement stashes across both regions."
)
