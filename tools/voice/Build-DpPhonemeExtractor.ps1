param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sourcePath = Join-Path $repoRoot 'tools\voice\DpPhonemeExtractor.cpp'
$vsWhere =
    'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Phoneme extractor source is missing: $sourcePath"
}
if (-not (Test-Path -LiteralPath $vsWhere -PathType Leaf)) {
    throw "Visual Studio locator is missing: $vsWhere"
}

$installationPath = & $vsWhere `
    -latest `
    -products '*' `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if ([string]::IsNullOrWhiteSpace($installationPath)) {
    throw 'Visual C++ x86 build tools are not installed.'
}

$devCmd = Join-Path $installationPath 'Common7\Tools\VsDevCmd.bat'
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$objectPath = Join-Path $outputDirectory 'DpPhonemeExtractor.obj'

$arguments = @(
    '/d',
    '/s',
    '/c',
    ('""{0}" -no_logo -arch=x86 -host_arch=x64 >nul && ' +
        'cl.exe /nologo /EHsc /O2 /MT /std:c++17 {1} ' +
        '/Fo:{3} /Fe:{2}"') -f $devCmd, $sourcePath, $OutputPath,
            $objectPath
)
& $env:ComSpec @arguments
if ($LASTEXITCODE -ne 0) {
    throw "x86 phoneme extractor build failed: exit $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "Compiler did not emit phoneme extractor: $OutputPath"
}
