param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$caseRoot = Join-Path $repoRoot 'content\migration\legacy-cases'
$casePath = Join-Path $caseRoot 'convenient-accident.case.json'
$bindingPath = Join-Path $repoRoot `
    'content\migration\legacy-case-settlement-bindings.json'
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

try {
    $case = Get-Content -Raw -LiteralPath $casePath |
        ConvertFrom-Json -Depth 100
    Add-Result ($null -ne $case.native) `
        'CaseSpec declares native wiring'
    Add-Result (@($case.native.dialogues).Count -eq 2) `
        'CaseSpec declares opener and witness dialogues'
    $directionEvidence = @($case.evidence | Where-Object role -ne 'innkeeper')
    Add-Result (
        $directionEvidence.Count -eq 2 -and
        @($directionEvidence | Where-Object {
            $null -eq $_.direction -or
            [string]::IsNullOrWhiteSpace([string]$_.direction.key)
        }).Count -eq 0
    ) 'every follow-up evidence source declares authored journal direction copy'

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
            'dpcase1001_kutnohorsko_pritoky_innkeeper_rumor_dialog_k.xml'
        ) -and
        ([string]$regionRecord.dialogDefinitions).Contains(
            'dpcase1001_kutnohorsko_pritoky_tavern_witness_dialog_k.xml'
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
        @($regionRecord.journalStates).Count -eq 3 -and
        ([string]$regionRecord.evidenceStateNodes).Contains('Value="37"') -and
        ([string]$regionRecord.evidenceStateNodes).Contains('Value="39"') -and
        ([string]$regionRecord.evidenceType).Contains('Evidence1102Default') -and
        ([string]$regionRecord.evidenceType).Contains('Evidence1103Default') -and
        ([string]$regionRecord.evidenceLogs).Contains(
            '<EnumLog Type="None" Name="DirectionsNone" />'
        ) -and
        ([string]$regionRecord.evidenceLogs).Contains(
            'Name="Evidence1102Default"'
        ) -and
        ([string]$regionRecord.evidenceLogs).Contains(
            'Name="Evidence1103Default"'
        )
    ) 'compiler emits one authored journal state per evidence presentation'
    Add-Result (
        [string]::IsNullOrWhiteSpace(
            [string]$regionRecord.witnessObjective
        ) -and
        [string]::IsNullOrWhiteSpace(
            [string]$regionRecord.witnessObjectiveNodes
        )
    ) 'separate witness objective is removed from generated wiring'

    $dialogueContracts = @(
        [pscustomobject]@{
            fileName =
                'dpcase1001_kutnohorsko_pritoky_innkeeper_rumor_dialog_k.xml'
            promptKey = 'dp_evidence_ask_unease'
            responseKey = 'dp_rumor_innkeeper_belongings'
        },
        [pscustomobject]@{
            fileName =
                'dpcase1001_kutnohorsko_pritoky_tavern_witness_dialog_k.xml'
            promptKey = 'dp_witness_ask_vojtech'
            responseKey = 'dp_witness_maid_location'
        }
    )
    foreach ($contract in $dialogueContracts) {
        $fileName = [string]$contract.fileName
        $generatedPath = Join-Path $generatedDialogRoot $fileName
        Add-Result (Test-Path -LiteralPath $generatedPath) `
            "compiler emits $fileName"
        $dialogueXml = if (Test-Path -LiteralPath $generatedPath) {
            [System.IO.File]::ReadAllText($generatedPath)
        }
        else { '' }
        $graphName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        Add-Result (
            $dialogueXml.Contains("<FaderDialog Name=`"$graphName`">") -and
            $dialogueXml.Contains(
                '<Port Name="actor_selected" Direction="In" Type="bool">'
            ) -and
            $dialogueXml.Contains(
                "StringName=`"$([string]$contract.promptKey)`""
            ) -and
            $dialogueXml.Contains(
                "StringName=`"$([string]$contract.responseKey)`""
            ) -and
            $dialogueXml.Contains(
                "EntryCondition=`"Port('available') AND " +
                "Port('actor_selected')`""
            )
        ) "$fileName keeps authored dialogue semantics and actor gating"
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
