param(
    [Parameter(Mandatory = $true)]
    [string]$PhonemeJsonPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$enginePhonemes = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal
)
@(
    '-', '!', '&', ',', '.', '?', '_',
    'aa', 'ae', 'ah', 'ao', 'aw', 'ax', 'ay', 'b', 'ch', 'd',
    'dh', 'eh', 'er', 'ey', 'f', 'g', 'h', 'ih', 'iy', 'jh',
    'k', 'l', 'm', 'n', 'ng', 'ow', 'oy', 'p', 'r', 's', 'sh',
    't', 'th', 'uh', 'uw', 'v', 'w', 'y', 'z', 'zh'
) | ForEach-Object {
    [void]$enginePhonemes.Add($_)
}

function ConvertTo-DpEnginePhoneme {
    param([Parameter(Mandatory = $true)][string]$Name)

    $normalized = $Name.ToLowerInvariant()
    switch ($normalized) {
        'x' { $normalized = '_' }
        'j' { $normalized = 'jh' }
    }
    if (-not $enginePhonemes.Contains($normalized)) {
        throw "Unsupported CryEngine phoneme emitted by recognizer: $Name"
    }
    return $normalized
}

if (-not (Test-Path -LiteralPath $PhonemeJsonPath -PathType Leaf)) {
    throw "Phoneme JSON is missing: $PhonemeJsonPath"
}

$timeline = [System.IO.File]::ReadAllText($PhonemeJsonPath) |
    ConvertFrom-Json -Depth 20
$phonemes = @($timeline.phonemes | Sort-Object startMs, endMs)
$words = @($timeline.words | Sort-Object startMs, endMs)
if ($phonemes.Count -eq 0) {
    throw 'Cannot build an FSQ from an empty phoneme timeline.'
}

$document = [System.Xml.XmlDocument]::new()
$declaration = $document.CreateXmlDeclaration('1.0', 'utf-8', $null)
$document.AppendChild($declaration) | Out-Null

$root = $document.CreateElement('FacialSequence')
$root.SetAttribute('StartTime', '0')
$lastEndMs = [int]($phonemes | Measure-Object endMs -Maximum).Maximum
$duration = ([double]$lastEndMs / 1000.0).ToString(
    '0.###',
    [System.Globalization.CultureInfo]::InvariantCulture
)
$root.SetAttribute('EndTime', $duration)
$document.AppendChild($root) | Out-Null

$sentence = $document.CreateElement('Sentence')
$sentence.SetAttribute('Text', [string]$timeline.text)
$root.AppendChild($sentence) | Out-Null

$wordsNode = $document.CreateElement('Words')
$sentence.AppendChild($wordsNode) | Out-Null
foreach ($word in $words) {
    $wordNode = $document.CreateElement('Word')
    $wordNode.SetAttribute('Word', [string]$word.word)
    $wordNode.SetAttribute('Start', [string][int]$word.startMs)
    $wordNode.SetAttribute('End', [string][int]$word.endMs)
    $wordsNode.AppendChild($wordNode) | Out-Null
}

$phonemesNode = $document.CreateElement('Phonemes')
$phonemesNode.InnerText = ($phonemes | ForEach-Object {
    '{0}:{1}:{2}' -f (
        [int]$_.startMs,
        [int]$_.endMs,
        (ConvertTo-DpEnginePhoneme -Name ([string]$_.phoneme))
    )
}) -join ','
$sentence.AppendChild($phonemesNode) | Out-Null

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Encoding = [System.Text.UTF8Encoding]::new($false)
$settings.Indent = $true
$settings.NewLineChars = "`r`n"
$writer = [System.Xml.XmlWriter]::Create($OutputPath, $settings)
try {
    $document.Save($writer)
}
finally {
    $writer.Dispose()
}
