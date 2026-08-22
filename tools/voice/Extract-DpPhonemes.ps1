param(
    [Parameter(Mandatory = $true)]
    [string]$ToolPath,

    [Parameter(Mandatory = $true)]
    [string]$PluginRoot,

    [Parameter(Mandatory = $true)]
    [string]$WavePath,

    [Parameter(Mandatory = $true)]
    [string]$Text,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

foreach ($path in @($ToolPath, $WavePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}
if (-not (Test-Path -LiteralPath $PluginRoot -PathType Container)) {
    throw "Annosoft plugin directory is missing: $PluginRoot"
}

$json = & $ToolPath $PluginRoot $WavePath $Text
if ($LASTEXITCODE -ne 0) {
    throw "Phoneme extraction failed: exit $LASTEXITCODE"
}

$parsed = $json | ConvertFrom-Json -Depth 20
if (@($parsed.phonemes).Count -eq 0) {
    throw 'Phoneme extraction returned an empty timeline.'
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
[System.IO.File]::WriteAllText(
    $OutputPath,
    ($parsed | ConvertTo-Json -Depth 20),
    [System.Text.UTF8Encoding]::new($false)
)
