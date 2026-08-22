$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $repoRoot 'tools\voice\Build-DpPhonemeExtractor.ps1'
$extractor = Join-Path $repoRoot 'tools\voice\Extract-DpPhonemes.ps1'
$fsqBuilder = Join-Path $repoRoot 'tools\voice\Convert-DpPhonemesToFsq.ps1'
$pluginRoot =
    'H:\SteamLibrary\steamapps\common\KCD2Mod\Editor\Plugins\LipSync\Annosoft'
$wavePath =
    'H:\KCD2Mod\_work\voice-cloning\dark-passenger-omni-pilot-2026-08-15\' +
    'generated\missing-traveler-innkeeper-dialogue\' +
    'aals_dp_mt_rumor_innkeeper_left.wav'
$text =
    'He did not disappear. He left before dawn. At least, that is what the guest ledger says.'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "dark-passenger-phonemes-$([guid]::NewGuid())"
$exePath = Join-Path $tempRoot 'dp-phonemes.exe'
$jsonPath = Join-Path $tempRoot 'phonemes.json'
$fsqPath = Join-Path $tempRoot 'aals_dp_mt_rumor_innkeeper_left.fsq'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([bool]$Condition, [string]$Label)

    $script:checks++
    if ($Condition) {
        Write-Host "PASS: $Label"
        return
    }
    $script:failures.Add($Label)
    Write-Host "FAIL: $Label"
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Add-Result (
        Test-Path -LiteralPath $builder -PathType Leaf
    ) 'x86 phoneme extractor builder exists'
    Add-Result (
        Test-Path -LiteralPath $extractor -PathType Leaf
    ) 'phoneme extraction wrapper exists'
    Add-Result (
        Test-Path -LiteralPath $fsqBuilder -PathType Leaf
    ) 'FSQ builder exists'

    if (
        (Test-Path -LiteralPath $builder -PathType Leaf) -and
        (Test-Path -LiteralPath $extractor -PathType Leaf)
    ) {
        & $builder -OutputPath $exePath
        & $extractor `
            -ToolPath $exePath `
            -PluginRoot $pluginRoot `
            -WavePath $wavePath `
            -Text $text `
            -OutputPath $jsonPath
        if (Test-Path -LiteralPath $fsqBuilder -PathType Leaf) {
            & $fsqBuilder `
                -PhonemeJsonPath $jsonPath `
                -OutputPath $fsqPath
        }
    }

    Add-Result (
        Test-Path -LiteralPath $exePath -PathType Leaf
    ) 'builder emits a 32-bit extractor executable'
    Add-Result (
        Test-Path -LiteralPath $jsonPath -PathType Leaf
    ) 'Annosoft extraction emits JSON'

    if (Test-Path -LiteralPath $jsonPath -PathType Leaf) {
        $result = [System.IO.File]::ReadAllText($jsonPath) |
            ConvertFrom-Json -Depth 20
        $phonemes = @($result.phonemes)
        Add-Result (
            [string]$result.text -eq $text -and
            $phonemes.Count -ge 5
        ) 'real WAV and transcript produce a non-empty phoneme timeline'
        Add-Result (
            @($phonemes | Where-Object {
                [int]$_.startMs -lt 0 -or
                [int]$_.endMs -le [int]$_.startMs -or
                [string]::IsNullOrWhiteSpace([string]$_.phoneme)
            }).Count -eq 0
        ) 'phoneme intervals are valid'
        Add-Result (
            @($phonemes | Sort-Object startMs).Count -eq $phonemes.Count -and
            [int]$phonemes[-1].endMs -gt 1000
        ) 'phoneme timeline spans the voiced sentence'
    }

    Add-Result (
        Test-Path -LiteralPath $fsqPath -PathType Leaf
    ) 'phoneme timeline converts to a facial sequence'
    if (Test-Path -LiteralPath $fsqPath -PathType Leaf) {
        [xml]$fsq = [System.IO.File]::ReadAllText($fsqPath)
        $root = $fsq.FacialSequence
        $sentenceNode = $fsq.SelectSingleNode('/FacialSequence/Sentence')
        $phonemePayload = [string]$fsq.SelectSingleNode(
            '/FacialSequence/Sentence/Phonemes'
        ).InnerText
        Add-Result (
            [double]$root.GetAttribute('EndTime') -gt 6.5 -and
            [string]$sentenceNode.GetAttribute('Text') -eq $text -and
            @($fsq.SelectNodes('/FacialSequence/Sentence/Words/Word')).Count -ge 10 -and
            $phonemePayload -match '^\d+:\d+:[A-Za-z_]+(,|$)'
        ) 'FSQ matches the CryEngine facial-sequence phoneme schema'
        Add-Result (
            $phonemePayload -notmatch '\s' -and
            @($phonemePayload.Split(',')).Count -ge 5
        ) 'FSQ contains a compact ordered phoneme timeline'
        $enginePhonemes = @(
            '-', '!', '&', ',', '.', '?', '_',
            'aa', 'ae', 'ah', 'ao', 'aw', 'ax', 'ay', 'b', 'ch', 'd',
            'dh', 'eh', 'er', 'ey', 'f', 'g', 'h', 'ih', 'iy', 'jh',
            'k', 'l', 'm', 'n', 'ng', 'ow', 'oy', 'p', 'r', 's', 'sh',
            't', 'th', 'uh', 'uw', 'v', 'w', 'y', 'z', 'zh'
        )
        $emittedPhonemes = @($phonemePayload.Split(',') | ForEach-Object {
            ($_ -split ':')[-1]
        })
        Add-Result (
            @($emittedPhonemes | Where-Object {
                $_ -notin $enginePhonemes
            }).Count -eq 0
        ) 'FSQ normalizes recognizer symbols to CryEngine facial effectors'
        Add-Result (
            '_' -in $emittedPhonemes -and
            'iy' -in $emittedPhonemes -and
            'jh' -in $emittedPhonemes
        ) 'FSQ maps silence, vowels, and the J sound to engine symbols'
    }
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

if ($script:failures.Count -gt 0) {
    throw "$($script:failures.Count) of $($script:checks) checks failed: " +
        ($script:failures -join '; ')
}

Write-Host "All $($script:checks) Annosoft phoneme checks passed."
