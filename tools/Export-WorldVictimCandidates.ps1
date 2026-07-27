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

$records = [System.Collections.Generic.List[object]]::new()

$regionSources = @(
    [ordered]@{ gameRegion = 'kutnohorsko'; objectsPath = $KuttenbergObjectsPath }
    [ordered]@{ gameRegion = 'trosecko'; objectsPath = $TroskyObjectsPath }
)

foreach ($regionSource in $regionSources) {
    [xml]$objects = Get-Content -Raw -LiteralPath $regionSource.objectsPath
    foreach ($entity in $objects.SelectNodes('//Entity[@EntityClass="NPC"]')) {
        $entityName = [string]$entity.Name
        $soul = $soulsByName[$entityName]
        if ($null -eq $soul) {
            continue
        }

        $linkNames = @($entity.EntityLinks.Link | ForEach-Object { [string]$_.Name })
        $homeLink = @($linkNames | Where-Object { $_ -like '_!home*' }).Count -gt 0
        $workLink = @($linkNames | Where-Object { $_ -like '_@villager_work*' }).Count -gt 0
        $layer = [string]$entity.EditorLayer
        $settlementHint = $null
        if ($layer -match '^Main/[^/_]+_([^/]+)/') {
            $settlementHint = $Matches[1]
        }

        $positionParts = @(
            ([string]$entity.Pos).Split(',') |
                ForEach-Object {
                    [double]::Parse($_, [System.Globalization.CultureInfo]::InvariantCulture)
                }
        )

        $records.Add([ordered]@{
            gameRegion = [string]$regionSource.gameRegion
            settlementHint = $settlementHint
            entityName = $entityName
            entityGuid = [string]$entity.EntityGuid
            soulGuid = [string]$soul.soul_id
            factionName = [string]$soul.faction_name
            characterName = [string]$soul.character_name
            position = [ordered]@{
                x = $positionParts[0]
                y = $positionParts[1]
                z = $positionParts[2]
            }
            editorLayer = $layer
            hasHomeLink = $homeLink
            hasVillagerWorkLink = $workLink
            permanentResidentEvidence = ($homeLink -and $workLink)
            source = [ordered]@{
                objects = [string]$regionSource.objectsPath
                souls = $SoulTablePath
            }
        })
    }
}

$document = [ordered]@{
    schemaVersion = 1
    candidates = @($records | Sort-Object gameRegion, entityName)
}
$json = $document | ConvertTo-Json -Depth 8
Write-Utf8NoBom -LiteralPath $OutputPath -Content ($json + "`n")
Write-Host "Exported $($records.Count) joined NPC records across both regions."
