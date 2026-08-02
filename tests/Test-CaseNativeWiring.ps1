param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$caseRoot = Join-Path $repoRoot 'content\cases'
$casePath = Join-Path $caseRoot 'convenient-accident.case.json'
$bindingPath = Join-Path $repoRoot 'config\case-settlement-bindings.json'
$goldenDialogRoot = Join-Path $repoRoot `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k'
$testRoot = Join-Path $repoRoot (
    'build\tests\case-native-wiring-' + [guid]::NewGuid().ToString('N')
)

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

function Get-CanonicalXml([string]$LiteralPath) {
    if (-not (Test-Path -LiteralPath $LiteralPath)) { return '' }
    [xml]$document = [System.IO.File]::ReadAllText($LiteralPath)
    return $document.OuterXml
}

try {
    $case = Get-Content -Raw -LiteralPath $casePath |
        ConvertFrom-Json -Depth 100
    Add-Result ($null -ne $case.native) `
        'CaseSpec declares native wiring'
    Add-Result (@($case.native.dialogues).Count -eq 2) `
        'CaseSpec declares opener and witness dialogues'

    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    & $compilerPath `
        -CaseRoot $caseRoot `
        -BindingPath $bindingPath `
        -BuildRoot $testRoot

    $manifestPath = Join-Path $testRoot `
        'generated\cases\native-wiring.json'
    $generatedDialogRoot = Join-Path $testRoot `
        'mod\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k'
    Add-Result (Test-Path -LiteralPath $manifestPath) `
        'compiler emits native wiring manifest'

    $manifest = if (Test-Path -LiteralPath $manifestPath) {
        Get-Content -Raw -LiteralPath $manifestPath |
            ConvertFrom-Json -Depth 100
    }
    else { $null }
    $region = @($manifest.regions | Where-Object region -eq 'kutnohorsko')
    $regionRecord = if ($region.Count -eq 1) { $region[0] } else { $null }
    Add-Result ($region.Count -eq 1) `
        'native manifest contains one Kuttenberg wiring record'
    Add-Result (
        $null -ne $regionRecord -and
        $regionRecord.questName -eq 'dark_within_k' -and
        ([string]$regionRecord.dialogDefinitions).Contains(
            'innkeeper_rumor_dialog_k.xml'
        ) -and
        ([string]$regionRecord.dialogDefinitions).Contains(
            'tavern_witness_dialog_k.xml'
        )
    ) 'native manifest declares both dialogue definitions'
    Add-Result (
        $null -ne $regionRecord -and
        ([string]$regionRecord.rumorNodes).Contains('Value="32"') -and
        ([string]$regionRecord.rumorNodes).Contains(
            'dp_rumor_heard_kutnohorsko'
        ) -and
        ([string]$regionRecord.witnessNodes).Contains('Value="36"') -and
        ([string]$regionRecord.witnessNodes).Contains(
            'dp_witness_heard_kutnohorsko'
        )
    ) 'native manifest preserves live signal tags and contexts'
    Add-Result (
        $null -ne $regionRecord -and
        ([string]$regionRecord.witnessObjective).Contains(
            'dark_within_witness_name'
        ) -and
        ([string]$regionRecord.witnessObjective).Contains(
            'dark_within_witness_active'
        ) -and
        ([string]$regionRecord.witnessObjective).Contains(
            'dark_within_witness_done'
        )
    ) 'native manifest preserves witness objective contract'

    foreach ($fileName in @(
        'innkeeper_rumor_dialog_k.xml',
        'tavern_witness_dialog_k.xml'
    )) {
        $goldenPath = Join-Path $goldenDialogRoot $fileName
        $generatedPath = Join-Path $generatedDialogRoot $fileName
        Add-Result (Test-Path -LiteralPath $generatedPath) `
            "compiler emits $fileName"
        Add-Result (
            (Get-CanonicalXml $generatedPath) -eq
            (Get-CanonicalXml $goldenPath)
        ) "$fileName is semantically identical to live-proven XML"
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedBuild = [System.IO.Path]::GetFullPath(
            (Join-Path $repoRoot 'build')
        ) + [System.IO.Path]::DirectorySeparatorChar
        $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
        if (-not $resolvedTest.StartsWith(
            $resolvedBuild,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Refusing to remove test path outside build: $resolvedTest"
        }
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
