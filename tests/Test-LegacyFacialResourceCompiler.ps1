$ErrorActionPreference = 'Stop'

$inspectorProject =
    'H:\KCD2Mod\_work\facial-inspector\facial-inspector.csproj'
$sourceDba =
    'H:\KCD2Mod\_work\retail-facials-2026-08-16\dba-control\' +
    'Animations\humans\facials\dialog\trosecko\poi_trosecko_aals_o.dba'
$sourceHead =
    'H:\KCD2Mod\_work\retail-facials-2026-08-16\female-head-control\' +
    'Objects\characters\humans\female\head\barbora\barbora_head.chr'
$rcExe = 'H:\SteamLibrary\steamapps\common\KCD2Mod\Tools\rc\rc.exe'
$rcJob = 'H:\SteamLibrary\steamapps\common\KCD2Mod\Tools\rc\RCJob_WH.xml'
$moddingRoot = 'H:\SteamLibrary\steamapps\common\KCD2Mod'
$pilotRoot = 'H:\KCD2Mod\_work\native-lipsync-pilot'
$animationName =
    'aals_o_di_hospodska_zijou_prav_gypl'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "dark-passenger-legacy-facial-$([guid]::NewGuid())"
$dataRoot = Join-Path $tempRoot 'Data'
$relativeAnimation =
    'Animations\humans\facials\dialog\trosecko\dark_within_t\' +
    'aals_dp_mt_rumor_innkeeper_left.i_caf'
$animationPath = Join-Path $dataRoot $relativeAnimation
$animationSettingsSource = Join-Path $pilotRoot (
    'Data\Animations\humans\facials\dialog\trosecko\dark_within_t\' +
    'aals_dp_mt_rumor_innkeeper_left.animsettings'
)
$outputRoot = Join-Path $tempRoot 'OutRC\PC'
$tempPrefix = $tempRoot

function Get-ControllerVersions {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ([System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'CrCh') {
        throw "Unexpected CAF signature: $Path"
    }
    $chunkCount = [System.BitConverter]::ToUInt32($bytes, 8)
    $chunkTableOffset = [System.BitConverter]::ToInt32($bytes, 12)
    $versions = [System.Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt $chunkCount; $index++) {
        $entryOffset = $chunkTableOffset + ($index * 16)
        $type = [System.BitConverter]::ToUInt16($bytes, $entryOffset)
        if ($type -eq 0x100D) {
            $versions.Add(
                [System.BitConverter]::ToUInt16($bytes, $entryOffset + 2)
            )
        }
    }
    return @($versions)
}

try {
    foreach ($required in @(
        $inspectorProject,
        $sourceDba,
        $sourceHead,
        $rcExe,
        $rcJob,
        (Join-Path $pilotRoot 'Data\Animations\DBATableFacials.json'),
        (Join-Path $pilotRoot 'Data\Animations\SkeletonList.xml'),
        $animationSettingsSource,
        (Join-Path $pilotRoot `
            'Data\Objects\characters\humans\female\skeleton\female.chr')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required facial-pipeline input is missing: $required"
        }
    }

    New-Item -ItemType Directory -Path (
        Split-Path -Parent $animationPath
    ) -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $dataRoot 'Animations'
    ) -Force | Out-Null
    New-Item -ItemType Directory -Path (
        Join-Path $dataRoot 'Objects\characters\humans\female\skeleton'
    ) -Force | Out-Null

    Copy-Item -LiteralPath (
        Join-Path $pilotRoot 'Data\Animations\DBATableFacials.json'
    ) -Destination (Join-Path $dataRoot 'Animations\DBATableFacials.json')
    Copy-Item -LiteralPath (
        Join-Path $pilotRoot 'Data\Animations\SkeletonList.xml'
    ) -Destination (Join-Path $dataRoot 'Animations\SkeletonList.xml')
    Copy-Item -LiteralPath (
        $animationSettingsSource
    ) -Destination (
        [System.IO.Path]::ChangeExtension($animationPath, '.animsettings')
    )
    Copy-Item -LiteralPath (
        Join-Path $pilotRoot `
            'Data\Objects\characters\humans\female\skeleton\female.chr'
    ) -Destination (Join-Path $dataRoot `
        'Objects\characters\humans\female\skeleton\female.chr')

    powershell -NoProfile -Command (
        "dotnet run --configuration Release --project `"$inspectorProject`" " +
        "-- `"$sourceDba`" `"$sourceHead`" `"$animationName`" " +
        "--export `"$animationPath`""
    ) | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Facial exporter failed with exit code $LASTEXITCODE."
    }

    $controllerVersions = @(Get-ControllerVersions -Path $animationPath)
    if (
        $controllerVersions.Count -eq 0 -or
        @($controllerVersions | Where-Object { $_ -ne 0x0827 }).Count -gt 0
    ) {
        $actual = @($controllerVersions | ForEach-Object {
            '0x{0:X4}' -f $_
        }) -join ', '
        throw "Exporter must emit only legacy uncompressed 0x0827 controllers; got $actual."
    }

    Push-Location -LiteralPath $moddingRoot
    try {
        & $rcExe `
            "/job=$rcJob" `
            '/jobtarget=FacialAnimations' `
            '/p=PC' `
            "/InputPath=$tempRoot" `
            "/OutputPath=$outputRoot" `
            "/TempPrefixPath=$tempPrefix" `
            '/Language=english' `
            '/verbose=0' `
            '/refresh=1' `
            '/unattended=1' | Out-Host
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Facial Resource Compiler failed with exit code $LASTEXITCODE."
    }

    $facialPak = Join-Path $outputRoot 'Data\Facials\Facials_english.pak'
    if (-not (Test-Path -LiteralPath $facialPak -PathType Leaf)) {
        throw "Resource Compiler did not emit Facials_english.pak: $facialPak"
    }
    $pakEntries = @(& 7z.exe l -ba $facialPak)
    if (@($pakEntries | Where-Object {
        $_ -match 'Animations\\FacialAnimations\.img\s*$'
    }).Count -ne 1) {
        throw 'Compiled facial PAK does not contain Animations/FacialAnimations.img.'
    }
    if (@($pakEntries | Where-Object {
        $_ -match (
            'Animations\\humans\\facials\\dialog\\trosecko\\' +
            'darkpassenger\\darkpassenger_trosecko\.dba\s*$'
        )
    }).Count -ne 1) {
        throw (
            'Compiled facial PAK does not contain the isolated Dark Passenger DBA. ' +
            'Entries: ' + ($pakEntries -join '; ')
        )
    }
    if (@($pakEntries | Where-Object {
        $_ -match 'Animations\\humans\\facials\\dialog\\trosecko\\trosecko\.dba\s*$'
    }).Count -ne 0) {
        throw 'Compiled facial PAK must not replace the vanilla Trosecko DBA.'
    }

    Write-Host 'PASS: legacy facial animation crosses the official Resource Compiler boundary.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
        $requiredPrefix = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::GetTempPath()
        )
        if (-not $resolvedTemp.StartsWith(
            $requiredPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Refusing to clean unexpected test path: $resolvedTemp"
        }
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
