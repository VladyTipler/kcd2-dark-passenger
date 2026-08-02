$ErrorActionPreference = 'Stop'

$questRoot =
    'H:\KCD2Mod\DarkPassenger\build\mod\Data\Quests\Final\Barbora'
$kuttenbergPath = Join-Path $questRoot 'kutnohorsko\dark_within_k.xml'
$troskyPath = Join-Path $questRoot 'trosecko\dark_within_t.xml'
$sourceLevelRoot = 'H:\KCD2Mod\DarkPassenger\src\Data\Levels'
$kuttenbergLinksPath =
    Join-Path $sourceLevelRoot 'kutnohorsko\waitinglinks.xml'
$troskyLinksPath = Join-Path $sourceLevelRoot 'trosecko\waitinglinks.xml'
$areaManifestPath =
    'H:\KCD2Mod\DarkPassenger\config\settlement-investigation-areas.json'
$currentPritokyAlias = 'DP_SearchArea_Kutnohorsko_Pritoky'
$legacyPritokyAlias = 'DP_PritokySearchArea'

[xml]$kuttenberg = Get-Content -Raw -LiteralPath $kuttenbergPath
[xml]$trosky = Get-Content -Raw -LiteralPath $troskyPath
[xml]$kuttenbergLinks =
    Get-Content -Raw -LiteralPath $kuttenbergLinksPath
[xml]$troskyLinks = Get-Content -Raw -LiteralPath $troskyLinksPath
$areaManifest =
    Get-Content -Raw -LiteralPath $areaManifestPath |
    ConvertFrom-Json

$kuttenbergType = $kuttenberg.SelectSingleNode(
    '//Type[@TypeName="DP_SearchProgress"]'
)
$legacyState = $kuttenbergType.SelectSingleNode(
    './StateTypeEnumeration[@Name="Active"]'
)
if ($null -eq $legacyState -or $legacyState.ObjectiveValueType -ne 'Started') {
    throw 'Kuttenberg search progress must deserialize legacy Active saves.'
}

$legacyLog = $kuttenberg.SelectSingleNode(
    '//Objective[@Name="dark_within_objk"]/Logs/EnumLog[@Name="Active"]'
)
if (
    $null -eq $legacyLog -or
    $legacyLog.Marker -ne $legacyPritokyAlias -or
    $legacyLog.IsTracked -ne 'true'
) {
    throw 'Legacy Active saves must retain their serialized Pritoky marker alias.'
}

$legacyAsset = $kuttenberg.SelectSingleNode(
    "//TriggerAreaAsset[@Name='$legacyPritokyAlias']"
)
if ($null -eq $legacyAsset) {
    throw 'Kuttenberg quest must declare the legacy Pritoky marker asset.'
}

$pritokyManifest = @(
    $areaManifest.regions |
        Where-Object id -eq 'kutnohorsko' |
        ForEach-Object settlements |
        Where-Object id -eq 'pritoky'
)
if (
    $pritokyManifest.Count -ne 1 -or
    @($pritokyManifest[0].legacyAliases).Count -ne 1 -or
    [string]$pritokyManifest[0].legacyAliases[0] -ne $legacyPritokyAlias
) {
    throw 'Pritoky coverage manifest must own the one legacy marker alias.'
}

function Get-LinkTargets {
    param(
        [Parameter(Mandatory)][xml]$Document,
        [Parameter(Mandatory)][string]$Definition
    )

    return @(
        $Document.StaticLinksInfo.WaitingLinks.WaitingLink |
            Where-Object { [string]$_.LinkDefinition -eq $Definition } |
            ForEach-Object { [string]$_.TargetId } |
            Sort-Object
    )
}

$currentTargets = Get-LinkTargets `
    -Document $kuttenbergLinks `
    -Definition "asset['$currentPritokyAlias']"
$legacyTargets = Get-LinkTargets `
    -Document $kuttenbergLinks `
    -Definition "asset['$legacyPritokyAlias']"
if (
    $currentTargets.Count -ne 3 -or
    $legacyTargets.Count -ne $currentTargets.Count -or
    (Compare-Object $currentTargets $legacyTargets).Count -ne 0
) {
    throw 'Legacy and current Pritoky aliases must resolve the same three areas.'
}

$troskyLegacyTargets = Get-LinkTargets `
    -Document $troskyLinks `
    -Definition "asset['$legacyPritokyAlias']"
if ($troskyLegacyTargets.Count -ne 0) {
    throw 'Legacy Pritoky marker links must remain Kuttenberg-only.'
}

$troskyLegacyState = $trosky.SelectSingleNode(
    '//Type[@TypeName="DP_SearchProgress"]/' +
    'StateTypeEnumeration[@Name="Active"]'
)
if ($null -ne $troskyLegacyState) {
    throw 'Legacy Pritoky compatibility state must remain Kuttenberg-only.'
}

'PASS: legacy Pritoky search saves remain compatible.'
