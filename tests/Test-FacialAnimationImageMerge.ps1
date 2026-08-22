$ErrorActionPreference = 'Stop'

$merger =
    'H:\KCD2Mod\DarkPassenger\tools\voice\' +
    'Merge-DpFacialAnimationImage.ps1'
$baseImage =
    'H:\KCD2Mod\_work\retail-facials-2026-08-16\part0\' +
    'Animations\FacialAnimations.img'
$extensionPak =
    'H:\KCD2Mod\_work\native-lipsync-pilot\OutRC-0827\PC\' +
    'Data\Facials\Facials_english.pak'
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$customPath =
    'animations/humans/facials/dialog/trosecko/dark_within_t/' +
    'aals_dp_mt_rumor_innkeeper_left.caf'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "dark-passenger-facial-merge-$([guid]::NewGuid())"
$extensionRoot = Join-Path $tempRoot 'extension'
$extensionImage = Join-Path $extensionRoot `
    'Animations\FacialAnimations.img'
$outputImage = Join-Path $tempRoot 'merged\FacialAnimations.img'

function Read-ImageIndex {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ([System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'CrCh') {
            throw "Unexpected facial image signature: $Path"
        }
        $version = $reader.ReadUInt32()
        $count = $reader.ReadUInt32()
        $tableOffset = $reader.ReadUInt32()
        if ($version -ne 0x746 -or $tableOffset -ne 16) {
            throw (
                'Unsupported facial image header: ' +
                "version=0x$($version.ToString('X')) table=$tableOffset"
            )
        }

        $entries = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $count; $index++) {
            $stream.Position = $tableOffset + ($index * 16)
            $type = $reader.ReadUInt16()
            $chunkVersion = $reader.ReadUInt16()
            $id = $reader.ReadUInt32()
            $size = $reader.ReadUInt32()
            $offset = $reader.ReadUInt32()
            if ($type -ne 0x3007 -or $chunkVersion -ne 0x0971) {
                throw (
                    'Unexpected facial image chunk: ' +
                    "type=0x$($type.ToString('X4')) " +
                    "version=0x$($chunkVersion.ToString('X4'))"
                )
            }
            if (($offset + $size) -gt $stream.Length -or $size -lt 5) {
                throw "Facial image chunk $index points outside $Path."
            }
            $stream.Position = $offset + 4
            $pathBytes = $reader.ReadBytes([Math]::Min(256, $size - 4))
            $zero = [Array]::IndexOf($pathBytes, [byte]0)
            if ($zero -lt 0) {
                $zero = $pathBytes.Length
            }
            $animationPath = [System.Text.Encoding]::ASCII.GetString(
                $pathBytes,
                0,
                $zero
            )
            $entries.Add([pscustomobject]@{
                Id = $id
                Size = $size
                Offset = $offset
                Path = $animationPath
            })
        }

        return [pscustomobject]@{
            Count = [int]$count
            Entries = @($entries)
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

try {
    foreach ($required in @($merger, $baseImage, $extensionPak, $sevenZip)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required merge input is missing: $required"
        }
    }

    New-Item -ItemType Directory -Path $extensionRoot -Force | Out-Null
    & $sevenZip x -y "-o$extensionRoot" $extensionPak `
        'Animations\FacialAnimations.img' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip extraction failed with exit code $LASTEXITCODE."
    }

    & $merger `
        -BaseImage $baseImage `
        -ExtensionImage $extensionImage `
        -OutputImage $outputImage
    if ($LASTEXITCODE -ne 0) {
        throw "Facial image merger failed with exit code $LASTEXITCODE."
    }

    $base = Read-ImageIndex -Path $baseImage
    $extension = Read-ImageIndex -Path $extensionImage
    $merged = Read-ImageIndex -Path $outputImage

    $expectedCount = $base.Count + $extension.Count
    if ($merged.Count -ne $expectedCount) {
        throw (
            "Merged chunk count is $($merged.Count); expected $expectedCount."
        )
    }
    if ($merged.Entries[0].Path -ne $base.Entries[0].Path) {
        throw 'The first vanilla facial registry entry changed during merge.'
    }
    if (
        $merged.Entries[$base.Count - 1].Path -ne
        $base.Entries[$base.Count - 1].Path
    ) {
        throw 'The last vanilla facial registry entry changed during merge.'
    }
    $customEntries = @($merged.Entries | Where-Object {
        $_.Path -eq $customPath
    })
    if ($customEntries.Count -ne 1) {
        throw (
            "Custom facial path occurs $($customEntries.Count) times; expected 1."
        )
    }
    if ($customEntries[0].Id -le $base.Entries[-1].Id) {
        throw 'Custom facial chunk did not receive a fresh ID after vanilla entries.'
    }

    Write-Host (
        "PASS: merged facial registry preserves $($base.Count) vanilla " +
        "entries and appends $($extension.Count) custom entry."
    )
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
