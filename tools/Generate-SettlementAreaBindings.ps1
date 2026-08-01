[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\settlement-investigation-areas.json'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Data\Levels')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-TextFile {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][System.Text.Encoding]$Encoding
    )

    $directory = Split-Path -Parent $LiteralPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($LiteralPath, $Content, $Encoding)
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Settlement investigation area manifest not found: $ManifestPath"
}
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
    throw "Unsupported settlement area manifest schemaVersion '$($manifest.schemaVersion)'."
}

$regionSpecifications = @(
    [pscustomobject]@{
        region = 'kutnohorsko'
        levelHolderGuid = '10702dff-9271-4a74'
        questHolderName = 'dark_within_k'
        questHolderGuid = 'f4a73e20-28c5-4bd2'
        questHolderEntityId = '1831841'
        smartEntityGuid = 'a125563a-5dfe-428f-9581-d218e82b849f'
        position = '2298.979,1694.99,101.3639'
    }
    [pscustomobject]@{
        region = 'trosecko'
        levelHolderGuid = '30277b74-1c65-41e9'
        questHolderName = 'dark_within_t'
        questHolderGuid = 'a13d9e5c-7b42-4f61'
        questHolderEntityId = '1831842'
        smartEntityGuid = 'd4a6f10b-f8cd-4d4d-9a6c-fbc186429bca'
        position = '1740.031,1957.591,127.1535'
    }
)

$manifestRegionIds = @($manifest.regions | ForEach-Object { [string]$_.id })
if (
    $manifestRegionIds.Count -ne $regionSpecifications.Count -or
    @($regionSpecifications.region | Where-Object { $_ -notin $manifestRegionIds }).Count -gt 0
) {
    throw 'Settlement area manifest must contain exactly the Kuttenberg and Trosky regions.'
}

foreach ($specification in $regionSpecifications) {
    $manifestRegion = @(
        $manifest.regions |
            Where-Object id -eq $specification.region
    )
    if ($manifestRegion.Count -ne 1) {
        throw "Expected one manifest region '$($specification.region)'."
    }
    $settlements = @($manifestRegion[0].settlements | Sort-Object id)
    if ($settlements.Count -eq 0) {
        throw "Manifest region '$($specification.region)' has no settlement areas."
    }

    $waitingLinkLines = [System.Collections.Generic.List[string]]::new()
    $waitingLinkLines.Add(
        "    <WaitingLink SourceId=`"$($specification.levelHolderGuid)`" TargetId=`"$($specification.questHolderGuid)`">"
    )
    $waitingLinkLines.Add('      <LinkDefinition>module</LinkDefinition>')
    $waitingLinkLines.Add('    </WaitingLink>')
    $linkSignatures = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    [void]$linkSignatures.Add(
        "$($specification.levelHolderGuid)|$($specification.questHolderGuid)|module"
    )

    foreach ($settlement in $settlements) {
        $alias = [string]$settlement.alias
        if ($alias -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Settlement '$($specification.region)/$($settlement.id)' has invalid alias '$alias'."
        }
        $areaGuids = @($settlement.areaGuids | ForEach-Object { [string]$_ })
        if ($areaGuids.Count -eq 0) {
            throw "Settlement '$($specification.region)/$($settlement.id)' has no selected TriggerArea."
        }
        foreach ($areaGuid in $areaGuids) {
            if ($areaGuid -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}$') {
                throw "Settlement '$($specification.region)/$($settlement.id)' has invalid short GUID '$areaGuid'."
            }
            $definition = "asset['$alias']"
            $signature =
                "$($specification.questHolderGuid)|$areaGuid|$definition"
            if (-not $linkSignatures.Add($signature)) {
                throw "Duplicate settlement area link '$signature'."
            }
            $waitingLinkLines.Add(
                "    <WaitingLink SourceId=`"$($specification.questHolderGuid)`" TargetId=`"$areaGuid`">"
            )
            $waitingLinkLines.Add(
                "      <LinkDefinition>asset[&apos;$alias&apos;]</LinkDefinition>"
            )
            $waitingLinkLines.Add('    </WaitingLink>')
        }
    }

    $missionObjects = @(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<Objects>'
        "  <Entity Name=`"$($specification.questHolderName)`""
        "          Pos=`"$($specification.position)`""
        '          EntityClass="SmartObjectHolder"'
        "          EntityId=`"$($specification.questHolderEntityId)`""
        "          EntityGuid=`"$($specification.questHolderGuid)`""
        '          CastShadowMinSpec="1"'
        '          EditorLayer="Main/_quest/activity/darkpassengertest/static">'
        '    <EntityLinks />'
        '    <Properties bSaved_by_game="0"'
        "                guidSmartObjectType=`"$($specification.smartEntityGuid)`" />"
        '    <BBoxProxy BBoxMin="1e+15,1e+15,1e+15"'
        '               BBoxMax="-1e+15,-1e+15,-1e+15" />'
        '  </Entity>'
        '</Objects>'
        ''
    ) -join "`n"
    $waitingLinks = @(
        '<?xml version="1.0" encoding="us-ascii"?>'
        '<StaticLinksInfo version="1">'
        '  <WaitingLinks>'
        $waitingLinkLines
        '  </WaitingLinks>'
        '  <StreamableTargets />'
        '</StaticLinksInfo>'
        ''
    ) -join "`n"

    $regionOutputRoot = Join-Path $OutputRoot $specification.region
    Write-TextFile `
        -LiteralPath (Join-Path $regionOutputRoot 'objects_mission0.patch.xml') `
        -Content $missionObjects `
        -Encoding ([System.Text.UTF8Encoding]::new($false))
    Write-TextFile `
        -LiteralPath (Join-Path $regionOutputRoot 'waitinglinks.xml') `
        -Content $waitingLinks `
        -Encoding ([System.Text.Encoding]::ASCII)

    Write-Host (
        "Generated $($specification.region) bindings: " +
        "settlements=$($settlements.Count) links=$($linkSignatures.Count)"
    )
}
