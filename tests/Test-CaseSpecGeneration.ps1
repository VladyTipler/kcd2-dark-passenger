param(
    [string]$DevGameRoot = $env:KCD2_DEV_ROOT
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerPath = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$modulePath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$caseRoot = Join-Path $repoRoot 'content\cases'
$bindingPath = Join-Path $repoRoot 'config\case-settlement-bindings.json'
$testRoot = Join-Path $repoRoot (
    'build\tests\case-spec-generation-' + [guid]::NewGuid().ToString('N')
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

function Get-Hash([string]$LiteralPath) {
    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash
}

try {
    Add-Result (Test-Path -LiteralPath $compilerPath) `
        'CaseSpec compiler entry point exists'
    if (-not (Test-Path -LiteralPath $compilerPath)) {
        throw 'compiler entry point missing'
    }

    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    & $compilerPath `
        -CaseRoot $caseRoot `
        -BindingPath $bindingPath `
        -BuildRoot $testRoot
    Add-Result ($?) 'CaseSpec compiler exits successfully'

    $catalogPath = Join-Path $testRoot `
        'mod\Data\Scripts\mods\generated\dp_case_catalog.lua'
    $reportPath = Join-Path $testRoot `
        'generated\cases\case-compatibility.json'
    $englishPath = Join-Path $testRoot `
        'generated\localization\English\text__darkpassengertest.xml'
    $russianPath = Join-Path $testRoot `
        'generated\localization\Russian\text__darkpassengertest.xml'
    Add-Result (Test-Path -LiteralPath $catalogPath) `
        'compiler emits Lua runtime catalog'
    Add-Result (Test-Path -LiteralPath $reportPath) `
        'compiler emits compatibility report'
    Add-Result (Test-Path -LiteralPath $englishPath) `
        'compiler emits English localization'
    Add-Result (Test-Path -LiteralPath $russianPath) `
        'compiler emits Russian localization'

    $catalog = if (Test-Path -LiteralPath $catalogPath) {
        [System.IO.File]::ReadAllText($catalogPath)
    }
    else { '' }
    $report = if (Test-Path -LiteralPath $reportPath) {
        [System.IO.File]::ReadAllText($reportPath) | ConvertFrom-Json -Depth 100
    }
    else { $null }

    foreach ($token in @(
        'DarkPassengerCaseCatalog = {}',
        'DarkPassengerCaseCatalogOrder = {',
        'DarkPassengerCaseCatalogByCode = {}',
        'id = "convenient_accident"',
        'code = 1001',
        'region = "kutnohorsko"',
        'settlement = "pritoky"',
        'id = "pritoky_innkeeper_strong_suspicion"',
        'id = "vojtech_belongings"',
        'id = "tavern_witness"',
        'entityName = "kpri_innkeeper"',
        'containerGuid = "277db45d-28ac-0286"',
        'id = "missing_traveler"',
        'code = 2001',
        'region = "trosecko"',
        'settlement = "zelejov"',
        'id = "zelejov_innkeeper_missing_traveler"',
        'id = "matej_guest_ledger"',
        'placement = "case_start"',
        'discoverable_without_hint = true',
        'hints_unlocked_by = {',
        '"zelejov_innkeeper_missing_traveler"',
        'reveals = {',
        '"forged_departure"',
        'id = "zelejov_stablehand_witness"',
        'entityName = "tzel_vavrinec"',
        'containerGuid = "aaf89994-e94b-0309"',
        'documentGuid = "d5833fd4-f7bf-4957-86f5-d661db38bcf3"'
    )) {
        Add-Result ($catalog.Contains($token)) "Lua catalog contains $token"
    }
    Add-Result (
        $catalog.IndexOf('id = "pritoky_innkeeper_strong_suspicion"') -lt
        $catalog.IndexOf('id = "vojtech_belongings"') -and
        $catalog.IndexOf('id = "vojtech_belongings"') -lt
        $catalog.IndexOf('id = "tavern_witness"')
    ) 'Lua catalog preserves evidence order'
    Add-Result (-not $catalog.Contains('next_lead =')) `
        'Lua catalog has no obsolete linear next-lead chain'

    Add-Result (
        $null -ne $report -and
        [int]$report.schemaVersion -eq 1 -and
        @($report.cases).Count -eq 2
    ) 'compatibility report has stable schema and case count'
    Add-Result (
        $report.cases[0].id -eq 'convenient_accident' -and
        [int]$report.cases[0].code -eq 1001 -and
        $report.cases[0].bindingKey -eq 'kutnohorsko/pritoky'
    ) 'compatibility report identifies case and binding'
    Add-Result (
        (@($report.cases[0].evidenceIds) -join ',') -eq
        'pritoky_innkeeper_strong_suspicion,vojtech_belongings,tavern_witness'
    ) 'compatibility report preserves evidence IDs'
    Add-Result (
        $report.cases[1].id -eq 'missing_traveler' -and
        [int]$report.cases[1].code -eq 2001 -and
        $report.cases[1].bindingKey -eq 'trosecko/zelejov' -and
        (@($report.cases[1].evidenceIds) -join ',') -eq
        'zelejov_innkeeper_missing_traveler,matej_guest_ledger,zelejov_stablehand_witness'
    ) 'compatibility report identifies Missing Traveler contract'

    Import-Module $modulePath -Force
    Add-Result (
        (ConvertTo-DpLuaString 'quote " slash \ newline' ) -eq
        '"quote \" slash \\ newline"'
    ) 'Lua strings escape quotes and backslashes'

    if (-not [string]::IsNullOrWhiteSpace($DevGameRoot)) {
        $luaCompiler = Join-Path $DevGameRoot `
            'Bin\Win64SharedPrivate\LuaCompiler.exe'
        Add-Result (Test-Path -LiteralPath $luaCompiler) `
            'LuaCompiler is available'
        if (Test-Path -LiteralPath $luaCompiler) {
            & $luaCompiler -p $catalogPath *> $null
            Add-Result ($LASTEXITCODE -eq 0) `
                'LuaCompiler parses generated catalog'
        }
    }

    $firstCatalogHash = Get-Hash $catalogPath
    $firstReportHash = Get-Hash $reportPath
    $firstEnglishHash = Get-Hash $englishPath
    $firstRussianHash = Get-Hash $russianPath
    & $compilerPath `
        -CaseRoot $caseRoot `
        -BindingPath $bindingPath `
        -BuildRoot $testRoot
    Add-Result (
        $firstCatalogHash -eq (Get-Hash $catalogPath) -and
        $firstReportHash -eq (Get-Hash $reportPath) -and
        $firstEnglishHash -eq (Get-Hash $englishPath) -and
        $firstRussianHash -eq (Get-Hash $russianPath)
    ) 'repeated compilation is byte-identical'

    foreach ($path in $catalogPath, $reportPath, $englishPath, $russianPath) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        Add-Result (
            $bytes.Length -lt 3 -or
            -not ($bytes[0] -eq 0xEF -and
                $bytes[1] -eq 0xBB -and
                $bytes[2] -eq 0xBF)
        ) "generated file has no UTF-8 BOM: $(Split-Path -Leaf $path)"
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedRepoBuild = [System.IO.Path]::GetFullPath(
            (Join-Path $repoRoot 'build')
        ) + [System.IO.Path]::DirectorySeparatorChar
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if (-not $resolvedTestRoot.StartsWith(
            $resolvedRepoBuild,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Refusing to remove test path outside build: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
