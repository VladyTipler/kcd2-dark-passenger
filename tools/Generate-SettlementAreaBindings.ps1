[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\settlement-investigation-areas.json'),
    [string]$AreaInventoryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\generated\vanilla-trigger-areas.json'),
    [string]$SettlementProfileRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\settlements'),
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Data\Levels'),
    [string]$LuaOutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Data\Scripts\mods\generated\dp_investigation_area_catalog.lua'),
    [string]$CompiledDefinitionsPath,
    [string]$SettlementBindingsPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$compilerModulePath = Join-Path $PSScriptRoot 'CaseSpecCompiler.psm1'
Import-Module $compilerModulePath -Force

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

function Escape-LuaString {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Format-LuaNumber {
    param([Parameter(Mandatory)]$Value)

    return ([double]$Value).ToString(
        'R',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Convert-AreaToLuaLines {
    param(
        [Parameter(Mandatory)]$Area,
        [Parameter(Mandatory)][string]$Indent
    )

    if (
        [string]::IsNullOrWhiteSpace([string]$Area.name) -or
        [string]::IsNullOrWhiteSpace([string]$Area.guid) -or
        [string]::IsNullOrWhiteSpace([string]$Area.entityId) -or
        $null -eq $Area.bounds -or
        @($Area.polygon).Count -lt 3
    ) {
        throw "TriggerArea '$([string]$Area.region)/$([string]$Area.guid)' lacks runtime catalog metadata."
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("$Indent{")
    $lines.Add(
        "$Indent    name = `"$(Escape-LuaString ([string]$Area.name))`","
    )
    $lines.Add(
        "$Indent    guid = `"$(Escape-LuaString ([string]$Area.guid))`","
    )
    $lines.Add(
        "$Indent    fullGuid = `"$(Escape-LuaString ([string]$Area.fullGuid))`","
    )
    $lines.Add(
        "$Indent    entityId = $([int64]$Area.entityId),"
    )
    $lines.Add(
        "$Indent    editorLayer = `"$(Escape-LuaString ([string]$Area.editorLayer))`","
    )
    $lines.Add(
        "$Indent    label = `"$(Escape-LuaString ([string]$Area.label))`","
    )
    $lines.Add(
        "$Indent    height = $(Format-LuaNumber $Area.height),"
    )
    $lines.Add(
        "$Indent    surfaceArea = $(Format-LuaNumber $Area.surfaceArea),"
    )
    $lines.Add("$Indent    bounds = {")
    $lines.Add(
        "$Indent        minX = $(Format-LuaNumber $Area.bounds.minX),"
    )
    $lines.Add(
        "$Indent        minY = $(Format-LuaNumber $Area.bounds.minY),"
    )
    $lines.Add(
        "$Indent        maxX = $(Format-LuaNumber $Area.bounds.maxX),"
    )
    $lines.Add(
        "$Indent        maxY = $(Format-LuaNumber $Area.bounds.maxY),"
    )
    $lines.Add("$Indent    },")
    $lines.Add("$Indent    polygon = {")
    foreach ($point in @($Area.polygon)) {
        $lines.Add(
            "$Indent        { x = $(Format-LuaNumber $point.x), y = $(Format-LuaNumber $point.y) },"
        )
    }
    $lines.Add("$Indent    },")
    $lines.Add("$Indent},")
    return $lines.ToArray()
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Settlement investigation area manifest not found: $ManifestPath"
}
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) {
    throw "Unsupported settlement area manifest schemaVersion '$($manifest.schemaVersion)'."
}
if (-not (Test-Path -LiteralPath $AreaInventoryPath -PathType Leaf)) {
    throw "Vanilla TriggerArea inventory not found: $AreaInventoryPath"
}
$areaInventory =
    Get-Content -Raw -LiteralPath $AreaInventoryPath |
    ConvertFrom-Json
if ($areaInventory.schemaVersion -ne 1) {
    throw "Unsupported TriggerArea inventory schemaVersion '$($areaInventory.schemaVersion)'."
}
$guidanceSignals = @()
if (-not [string]::IsNullOrWhiteSpace($CompiledDefinitionsPath)) {
    if (-not (Test-Path -LiteralPath $CompiledDefinitionsPath -PathType Leaf)) {
        throw "Compiled CaseKit definitions not found: $CompiledDefinitionsPath"
    }
    $compiledDefinitions = [System.IO.File]::ReadAllText(
        $CompiledDefinitionsPath
    ) | ConvertFrom-Json -Depth 100
    $guidanceSignals = @(Get-DpGuidanceSignals `
        -CompiledDefinitions $compiledDefinitions `
        -AreaManifest $manifest `
        -AreaInventory $areaInventory `
        -StartSignalTag 1)
}
$areasByRegionAndGuid = @{}
foreach ($area in @($areaInventory.areas)) {
    $areaKey = '{0}|{1}' -f [string]$area.region, [string]$area.guid
    if ($areasByRegionAndGuid.ContainsKey($areaKey)) {
        throw "Duplicate TriggerArea inventory identity '$areaKey'."
    }
    $areasByRegionAndGuid[$areaKey] = $area
}

if (-not (Test-Path -LiteralPath $SettlementProfileRoot -PathType Container)) {
    throw "Settlement profile root not found: $SettlementProfileRoot"
}
$evidenceStashesByRegion = @{}
$evidenceStashTargets = @{}
function Add-EvidenceStash {
    param(
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$Settlement,
        [Parameter(Mandatory)][string]$ContainerGuid,
        [Parameter(Mandatory)][string]$Source,
        [switch]$Override
    )

    if ($ContainerGuid -notmatch
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}$') {
        throw "$Source has invalid evidence container GUID '$ContainerGuid'."
    }
    $alias = Get-DpEvidenceStashAlias `
        -Region $Region -Settlement $Settlement
    if ($evidenceStashTargets.ContainsKey($alias)) {
        if ([string]$evidenceStashTargets[$alias] -ne $ContainerGuid) {
            if ($Override) {
                $existing = @($evidenceStashesByRegion[$Region] |
                    Where-Object { [string]$_.alias -eq $alias })[0]
                if ($null -eq $existing) {
                    throw "Evidence stash alias '$alias' has no stored binding."
                }
                $existing.containerGuid = $ContainerGuid
                $evidenceStashTargets[$alias] = $ContainerGuid
                return
            }
            throw (
                "Evidence stash alias '$alias' resolves to multiple containers: " +
                "'$($evidenceStashTargets[$alias])' and '$ContainerGuid'."
            )
        }
        return
    }
    $evidenceStashTargets[$alias] = $ContainerGuid
    if (-not $evidenceStashesByRegion.ContainsKey($Region)) {
        $evidenceStashesByRegion[$Region] =
            [System.Collections.Generic.List[object]]::new()
    }
    $evidenceStashesByRegion[$Region].Add([pscustomobject]@{
        settlement = $Settlement
        containerGuid = $ContainerGuid
        alias = $alias
    })
}
foreach ($profileFile in @(
    Get-ChildItem -LiteralPath $SettlementProfileRoot -File -Filter '*.json' |
        Sort-Object FullName
)) {
    $profile = [System.IO.File]::ReadAllText($profileFile.FullName) |
        ConvertFrom-Json -Depth 100
    $documentRole = if (
        $null -ne $profile.PSObject.Properties['native'] -and
        $null -ne $profile.native.PSObject.Properties['roles'] -and
        $null -ne $profile.native.roles.PSObject.Properties['document']
    ) { $profile.native.roles.document } else { $null }
    if ($null -eq $documentRole) { continue }
    $region = [string]$profile.region
    $settlement = [string]$profile.settlement
    $containerGuid = [string]$documentRole.containerGuid
    Add-EvidenceStash -Region $region -Settlement $settlement `
        -ContainerGuid $containerGuid `
        -Source "Settlement profile '$($profileFile.Name)'"
}

if (-not [string]::IsNullOrWhiteSpace($SettlementBindingsPath)) {
    if (-not (Test-Path -LiteralPath $SettlementBindingsPath -PathType Leaf)) {
        throw "Case settlement bindings not found: $SettlementBindingsPath"
    }
    $caseBindings = Read-DpCaseSettlementBindings `
        -LiteralPath $SettlementBindingsPath
    foreach ($binding in @($caseBindings.settlements)) {
        $document = $binding.roles.PSObject.Properties['document']
        if ($null -eq $document) { continue }
        Add-EvidenceStash `
            -Region ([string]$binding.region) `
            -Settlement ([string]$binding.settlement) `
            -ContainerGuid ([string]$document.Value.containerGuid) `
            -Source "Case binding '$([int]$binding.caseCode)/$([string]$binding.settlement)'" `
            -Override
    }
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
        confessionDialogueHolderName = 'DP_ConfessionDialogueHolder_Trosecko'
        confessionDialogueHolderEntityId = '1831843'
        confessionDialogueHolderGuid = 'cd93a0b2-762f-4d22'
        confessionDialogueHolderAlias = 'confessionProbeDialogueHolder'
        confessionLyingSpotName = 'DP_ConfessionLyingSpot_Trosecko'
        confessionLyingSpotEntityId = '1831844'
        confessionLyingSpotGuid = '8f827fee-38a5-41db'
        confessionLyingSpotAlias = 'confessionProbeLyingSpot'
        confessionLyingTargetEntityId = '2268'
        confessionLyingTargetEntityGuid = 'fd4604bf-062f-4cf7'
        confessionCameras = @(
            [pscustomobject]@{ name = 'targetCloseup'; entityId = '1831845'; guid = '50df1113-ed8f-4845'; type = 'Closeup'; context = '1'; fov = '0.383972' }
            [pscustomobject]@{ name = 'targetCloseShot'; entityId = '1831846'; guid = 'dc816990-06f3-4036'; type = 'CloseShot'; context = '1'; fov = '0.418879' }
            [pscustomobject]@{ name = 'targetMedium'; entityId = '1831847'; guid = '9d3ae907-8eea-47d2'; type = 'Medium'; context = '1'; fov = '0.383972' }
            [pscustomobject]@{ name = 'playerCloseup'; entityId = '1831848'; guid = 'b1e60d2c-7930-4c86'; type = 'Closeup'; context = '0'; fov = '0.383972' }
            [pscustomobject]@{ name = 'playerCloseShot'; entityId = '1831849'; guid = '454d309c-d364-4f1d'; type = 'CloseShot'; context = '0'; fov = '0.418879' }
            [pscustomobject]@{ name = 'playerMedium'; entityId = '1831850'; guid = 'f8c192db-9392-4871'; type = 'Medium'; context = '0'; fov = '0.418879' }
        )
    }
)

$manifestRegionIds = @($manifest.regions | ForEach-Object { [string]$_.id })
if (
    $manifestRegionIds.Count -ne $regionSpecifications.Count -or
    @($regionSpecifications.region | Where-Object { $_ -notin $manifestRegionIds }).Count -gt 0
) {
    throw 'Settlement area manifest must contain exactly the Kuttenberg and Trosky regions.'
}

$luaRegionLines = [System.Collections.Generic.List[string]]::new()
$totalCatalogAreas = 0
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
    $luaSettlementLines = [System.Collections.Generic.List[string]]::new()

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
    $hasConfessionDialogueHolder =
        $specification.PSObject.Properties.Name -contains
            'confessionDialogueHolderGuid'
    if ($hasConfessionDialogueHolder) {
        $confessionDefinition =
            "asset['$($specification.confessionDialogueHolderAlias)']"
        [void]$linkSignatures.Add(
            "$($specification.questHolderGuid)|$($specification.confessionDialogueHolderGuid)|$confessionDefinition"
        )
        $waitingLinkLines.Add(
            "    <WaitingLink SourceId=`"$($specification.questHolderGuid)`" TargetId=`"$($specification.confessionDialogueHolderGuid)`">"
        )
        $waitingLinkLines.Add(
            "      <LinkDefinition>asset[&apos;$($specification.confessionDialogueHolderAlias)&apos;]</LinkDefinition>"
        )
        $waitingLinkLines.Add('    </WaitingLink>')
        $lyingSpotDefinition =
            "asset['$($specification.confessionLyingSpotAlias)']"
        [void]$linkSignatures.Add(
            "$($specification.questHolderGuid)|$($specification.confessionLyingSpotGuid)|$lyingSpotDefinition"
        )
        $waitingLinkLines.Add(
            "    <WaitingLink SourceId=`"$($specification.questHolderGuid)`" TargetId=`"$($specification.confessionLyingSpotGuid)`">"
        )
        $waitingLinkLines.Add(
            "      <LinkDefinition>asset[&apos;$($specification.confessionLyingSpotAlias)&apos;]</LinkDefinition>"
        )
        $waitingLinkLines.Add('    </WaitingLink>')
        [void]$linkSignatures.Add(
            "$($specification.confessionLyingSpotGuid)|$($specification.confessionDialogueHolderGuid)|dialogueHolder"
        )
        $waitingLinkLines.Add(
            "    <WaitingLink SourceId=`"$($specification.confessionLyingSpotGuid)`" TargetId=`"$($specification.confessionDialogueHolderGuid)`">"
        )
        $waitingLinkLines.Add(
            '      <LinkDefinition>dialogueHolder</LinkDefinition>'
        )
        $waitingLinkLines.Add('    </WaitingLink>')
        foreach ($camera in $specification.confessionCameras) {
            [void]$linkSignatures.Add(
                "$($specification.confessionDialogueHolderGuid)|$($camera.guid)|cameraOverride"
            )
            $waitingLinkLines.Add(
                "    <WaitingLink SourceId=`"$($specification.confessionDialogueHolderGuid)`" TargetId=`"$($camera.guid)`">"
            )
            $waitingLinkLines.Add(
                '      <LinkDefinition>cameraOverride</LinkDefinition>'
            )
            $waitingLinkLines.Add('    </WaitingLink>')
        }
    }
    foreach ($stash in @(
        if ($evidenceStashesByRegion.ContainsKey($specification.region)) {
            $evidenceStashesByRegion[$specification.region] |
                Sort-Object settlement, containerGuid
        }
    )) {
        $definition = "asset['$([string]$stash.alias)']"
        $signature =
            "$($specification.questHolderGuid)|" +
            "$([string]$stash.containerGuid)|$definition"
        if (-not $linkSignatures.Add($signature)) {
            throw "Duplicate evidence stash link '$signature'."
        }
        $waitingLinkLines.Add(
            "    <WaitingLink SourceId=`"$($specification.questHolderGuid)`" TargetId=`"$([string]$stash.containerGuid)`">"
        )
        $waitingLinkLines.Add(
            "      <LinkDefinition>asset[&apos;$([string]$stash.alias)&apos;]</LinkDefinition>"
        )
        $waitingLinkLines.Add('    </WaitingLink>')
    }
    foreach ($guidanceLink in @(Get-DpGuidanceWaitingLinks `
        -Signals $guidanceSignals `
        -Region ([string]$specification.region) `
        -QuestHolderGuid ([string]$specification.questHolderGuid))) {
        $signature =
            "$([string]$guidanceLink.sourceGuid)|" +
            "$([string]$guidanceLink.targetGuid)|" +
            [string]$guidanceLink.linkDefinition
        if (-not $linkSignatures.Add($signature)) {
            throw "Duplicate guidance link '$signature'."
        }
        $encodedDefinition = ([string]$guidanceLink.linkDefinition).Replace(
            "'",
            '&apos;'
        )
        $waitingLinkLines.Add(
            "    <WaitingLink SourceId=`"$([string]$guidanceLink.sourceGuid)`" TargetId=`"$([string]$guidanceLink.targetGuid)`">"
        )
        $waitingLinkLines.Add(
            "      <LinkDefinition>$encodedDefinition</LinkDefinition>"
        )
        $waitingLinkLines.Add('    </WaitingLink>')
    }
    foreach ($settlement in $settlements) {
        $alias = [string]$settlement.alias
        if ($alias -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Settlement '$($specification.region)/$($settlement.id)' has invalid alias '$alias'."
        }
        $legacyAliases = @(
            if (
                $settlement.PSObject.Properties.Name -contains 'legacyAliases'
            ) {
                $settlement.legacyAliases |
                    ForEach-Object { [string]$_ }
            }
        )
        foreach ($legacyAlias in $legacyAliases) {
            if (
                $legacyAlias -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or
                $legacyAlias -eq $alias
            ) {
                throw "Settlement '$($specification.region)/$($settlement.id)' has invalid legacy alias '$legacyAlias'."
            }
        }
        if (@($legacyAliases | Sort-Object -Unique).Count -ne $legacyAliases.Count) {
            throw "Settlement '$($specification.region)/$($settlement.id)' has duplicate legacy aliases."
        }
        $areaGuids = @($settlement.areaGuids | ForEach-Object { [string]$_ })
        if ($areaGuids.Count -eq 0) {
            throw "Settlement '$($specification.region)/$($settlement.id)' has no selected TriggerArea."
        }
        $settlementId = [string]$settlement.id
        $catalogKey = "$($specification.region)/$settlementId"
        $luaSettlementLines.Add("                [`"$(Escape-LuaString $settlementId)`"] = {")
        $luaSettlementLines.Add(
            "                    key = `"$(Escape-LuaString $catalogKey)`","
        )
        $luaSettlementLines.Add(
            "                    region = `"$(Escape-LuaString $specification.region)`","
        )
        $luaSettlementLines.Add(
            "                    settlement = `"$(Escape-LuaString $settlementId)`","
        )
        $luaSettlementLines.Add(
            "                    alias = `"$(Escape-LuaString $alias)`","
        )
        $luaSettlementLines.Add('                    legacyAliases = {')
        foreach ($legacyAlias in $legacyAliases) {
            $luaSettlementLines.Add(
                "                        `"$(Escape-LuaString $legacyAlias)`","
            )
        }
        $luaSettlementLines.Add('                    },')
        $luaSettlementLines.Add('                    areas = {')
        foreach ($areaGuid in $areaGuids) {
            if ($areaGuid -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}$') {
                throw "Settlement '$($specification.region)/$($settlement.id)' has invalid short GUID '$areaGuid'."
            }
            $inventoryKey = "$($specification.region)|$areaGuid"
            if (-not $areasByRegionAndGuid.ContainsKey($inventoryKey)) {
                throw "Selected TriggerArea '$inventoryKey' is absent from the normalized inventory."
            }
            foreach (
                $luaAreaLine in Convert-AreaToLuaLines `
                    -Area $areasByRegionAndGuid[$inventoryKey] `
                    -Indent '                        '
            ) {
                $luaSettlementLines.Add($luaAreaLine)
            }
            $totalCatalogAreas++
            foreach ($linkAlias in @($alias) + $legacyAliases) {
                $definition = "asset['$linkAlias']"
                $signature =
                    "$($specification.questHolderGuid)|$areaGuid|$definition"
                if (-not $linkSignatures.Add($signature)) {
                    throw "Duplicate settlement area link '$signature'."
                }
                $waitingLinkLines.Add(
                    "    <WaitingLink SourceId=`"$($specification.questHolderGuid)`" TargetId=`"$areaGuid`">"
                )
                $waitingLinkLines.Add(
                    "      <LinkDefinition>asset[&apos;$linkAlias&apos;]</LinkDefinition>"
                )
                $waitingLinkLines.Add('    </WaitingLink>')
            }
        }
        $luaSettlementLines.Add('                    },')
        $luaSettlementLines.Add('                },')
    }

    $luaRegionLines.Add("        [`"$(Escape-LuaString $specification.region)`"] = {")
    $luaRegionLines.Add(
        "            levelHolderName = `"$(Escape-LuaString $specification.region)`","
    )
    $luaRegionLines.Add(
        "            questHolderName = `"$(Escape-LuaString $specification.questHolderName)`","
    )
    $luaRegionLines.Add('            settlements = {')
    foreach ($luaSettlementLine in $luaSettlementLines) {
        $luaRegionLines.Add($luaSettlementLine)
    }
    $luaRegionLines.Add('            },')
    $luaRegionLines.Add('        },')

    $confessionDialogueHolderLines = @()
    $confessionLyingSpotLines = @()
    $confessionCameraLines = @()
    if ($hasConfessionDialogueHolder) {
        $confessionDialogueHolderLines = @(
            "  <Entity Name=`"$($specification.confessionDialogueHolderName)`""
            "          Pos=`"$($specification.position)`""
            '          EntityClass="DialogueHolder"'
            "          EntityId=`"$($specification.confessionDialogueHolderEntityId)`""
            "          EntityGuid=`"$($specification.confessionDialogueHolderGuid)`""
            '          CastShadowMinSpec="1"'
            '          EditorLayer="Main/_quest/activity/darkpassengertest/static">'
            '    <EntityLinks />'
            '    <Properties bSaved_by_game="0" />'
            '  </Entity>'
        )
        $confessionLyingSpotLines = @(
            "  <Entity Prefab=`"1`" Name=`"$($specification.confessionLyingSpotName)`""
            "          Pos=`"$($specification.position)`""
            '          EntityClass="SO_LyingHarmed"'
            "          EntityId=`"$($specification.confessionLyingSpotEntityId)`""
            "          EntityGuid=`"$($specification.confessionLyingSpotGuid)`""
            '          CastShadowMinSpec="1"'
            '          EditorLayer="Main/_quest/activity/darkpassengertest/static">'
            '    <EntityLinks>'
            "      <Link TargetId=`"$($specification.confessionLyingTargetEntityId)`" TargetGuid=`"$($specification.confessionLyingTargetEntityGuid)`" Name=`"_,harmedOne|,!priv,use`" />"
            '    </EntityLinks>'
            '    <Properties soclass_SmartObjectHelpers="lyingInjured_lowBed"'
            '                guidSmartObjectType="fac19edd-46e9-4dd5-914f-72502c70af07"'
            '                bSaved_by_game="0">'
            '      <LyingHarmed esLyingHarmedPose="male_lyingWounded_04" />'
            '    </Properties>'
            '    <BBoxProxy BBoxMin="1e+15,1e+15,1e+15"'
            '               BBoxMax="-1e+15,-1e+15,-1e+15" />'
            '  </Entity>'
        )
        $cameraLines = [System.Collections.Generic.List[string]]::new()
        foreach ($camera in $specification.confessionCameras) {
            $cameraLines.Add(
                "  <Entity Prefab=`"1`" Name=`"DP_ConfessionCameraRig_$($camera.name)`""
            )
            $cameraLines.Add("          Pos=`"$($specification.position)`"")
            $cameraLines.Add('          Rotate="1,0,0,0"')
            $cameraLines.Add('          EntityClass="CameraSource"')
            $cameraLines.Add("          EntityId=`"$($camera.entityId)`"")
            $cameraLines.Add("          EntityGuid=`"$($camera.guid)`"")
            $cameraLines.Add('          CastShadowMinSpec="1"')
            $cameraLines.Add('          EditorLayer="Main/_quest/activity/darkpassengertest/static">')
            $cameraLines.Add('    <Properties bSaved_by_game="0">')
            $cameraLines.Add(
                "      <DialogueCamera esDialogueCameraOverrideType=`"$($camera.type)`" iDialogueContextId=`"$($camera.context)`" />"
            )
            $cameraLines.Add('    </Properties>')
            $cameraLines.Add(
                "    <CameraProxy Fov=`"$($camera.fov)`" NearZ=`"0.25`" FarZ=`"1024`" DofEnable=`"1`" FocusDistance=`"2`" FocusRange=`"4`" BlurAmount=`"1`" />"
            )
            $cameraLines.Add('  </Entity>')
        }
        $confessionCameraLines = $cameraLines.ToArray()
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
        $confessionDialogueHolderLines
        $confessionLyingSpotLines
        $confessionCameraLines
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

$luaCatalog = @(
    '-- Generated from settlement-investigation-areas.json and vanilla-trigger-areas.json.'
    '-- Do not edit by hand.'
    'DarkPassengerInvestigationAreaCatalog = {'
    '    schemaVersion = 1,'
    '    regions = {'
    $luaRegionLines
    '    },'
    '}'
    ''
) -join "`n"
Write-TextFile `
    -LiteralPath $LuaOutputPath `
    -Content $luaCatalog `
    -Encoding ([System.Text.UTF8Encoding]::new($false))
Write-Host (
    'Generated investigation area Lua catalog: ' +
    "settlements=$(@($manifest.regions.settlements).Count) areas=$totalCatalogAreas"
)
