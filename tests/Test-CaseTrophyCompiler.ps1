$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$authoringPath = Join-Path $repoRoot `
    'casekit\core\CaseKit.Authoring.psm1'
$materializerPath = Join-Path $repoRoot `
    'casekit\adapters\kcd2\CaseKit.Kcd2Materializer.psm1'
$compilerPath = Join-Path $repoRoot 'tools\CaseSpecCompiler.psm1'
$compileScriptPath = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$compiledPath = Join-Path $repoRoot `
    'build\generated\casekit\compiler-input\compiled-definitions.json'
$variantCatalogPath = Join-Path $repoRoot `
    'build\mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'
$itemTablePath = Join-Path $repoRoot `
    'build\mod\Data\Libs\Tables\item\item__darkpassengertest.xml'
$russianPath = Join-Path $repoRoot `
    'build\generated\localization\Russian\text__darkpassengertest.xml'
$englishPath = Join-Path $repoRoot `
    'build\generated\localization\English\text__darkpassengertest.xml'

$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Read-OptionalText {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return '' }
    return [System.IO.File]::ReadAllText($LiteralPath)
}

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

$authoring = Read-OptionalText $authoringPath
$materializer = Read-OptionalText $materializerPath
$compiler = Read-OptionalText $compilerPath
$compileScript = Read-OptionalText $compileScriptPath
$variantCatalog = Read-OptionalText $variantCatalogPath
$itemText = Read-OptionalText $itemTablePath
$russianText = Read-OptionalText $russianPath
$englishText = Read-OptionalText $englishPath
$compiled = if (Test-Path -LiteralPath $compiledPath -PathType Leaf) {
    [System.IO.File]::ReadAllText($compiledPath) |
        ConvertFrom-Json -Depth 100
}
else { $null }

$storyCases = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'content\stories') `
        -Recurse -Filter 'case.json' -File | Sort-Object FullName |
        ForEach-Object {
            [System.IO.File]::ReadAllText($_.FullName) |
                ConvertFrom-Json -Depth 100
        }
)
Add-Result (
    $storyCases.Count -gt 0 -and
    @($storyCases | Where-Object {
        $_.trophyDefinition.preset -ne 'bird-feather' -or
        $_.trophyDefinition.item.classification -ne 'loot' -or
        $_.trophyDefinition.item.retention -ne 'permanent' -or
        [double]$_.trophyDefinition.item.weight -ne 0
    }).Count -eq 0
) 'active StoryPacks declare a permanent weightless loot trophy'
Add-Result (
    $authoring.Contains('trophyDefinition') -and
    $authoring.Contains('classification') -and
    $authoring.Contains('retention') -and
    $authoring.Contains('weight')
) 'authoring validates and preserves optional TrophyDefinition semantics'
Add-Result (
    $materializer.Contains('trophyDefinition') -and
    $materializer.Contains('renderedAssets')
) 'materializer preserves authored TrophyDefinition metadata on each variant'
Add-Result (
    $compiler.Contains("'bird-feather'") -and
    $compiler.Contains('special_featherRed') -and
    $compiler.Contains('quill.cgf')
) 'native compiler owns the central bird-feather asset preset'
Add-Result (
    $compileScript.Contains('-CompiledDefinitions $compiledDefinitions')
) 'native table and localization transforms receive compiled variants'

$variants = if ($null -ne $compiled) { @($compiled.variants) } else { @() }
$trophies = @($variants | ForEach-Object { $_.trophyDefinition })
Add-Result (
    $variants.Count -gt 0 -and
    $trophies.Count -eq $variants.Count -and
    @($trophies | Where-Object { $null -eq $_ }).Count -eq 0
) 'every production CaseVariant carries one optional compiled trophy definition'
Add-Result (
    @($trophies | Where-Object {
        $_.preset -ne 'bird-feather' -or
        [string]::IsNullOrWhiteSpace([string]$_.description.ru) -or
        [string]::IsNullOrWhiteSpace([string]$_.description.en)
    }).Count -eq 0
) 'compiled trophy descriptions are rendered in Russian and English'

$catalogTrophies = @([regex]::Matches(
    $variantCatalog,
    '(?m)^\s*trophy\s*=\s*\{'
))
Add-Result (
    $variants.Count -gt 0 -and $catalogTrophies.Count -eq $variants.Count
) 'runtime catalog contains one native trophy record per concrete variant'
$catalogGuids = @([regex]::Matches(
    $variantCatalog,
    '(?ms)^\s*trophy\s*=\s*\{\r?\n' +
        '\s*preset\s*=.*?\r?\n' +
        '\s*item_guid\s*=\s*"(?<value>[0-9a-f-]{36})"'
) | ForEach-Object { $_.Groups['value'].Value })
Add-Result (
    $catalogGuids.Count -eq $variants.Count -and
    @($catalogGuids | Sort-Object -Unique).Count -eq 1
) 'all concrete variants reuse one shared bloodied-feather item class'

[xml]$itemXml = if ([string]::IsNullOrWhiteSpace($itemText)) {
    '<database><ItemClasses /></database>'
}
else { $itemText }
$itemRows = @($itemXml.database.ItemClasses.MiscItem | Where-Object {
    [string]$_.Name -like 'dp_trophy_*'
})
Add-Result (
    $itemRows.Count -eq 1 -and
    [string]$itemRows[0].Name -eq 'dp_trophy_bloodied_feather'
) 'item table contains one shared bloodied-feather item row'
Add-Result (
    $itemRows.Count -gt 0 -and
    @($itemRows | Where-Object {
        [string]$_.IsDivisible -ne 'true' -or
        [string]$_.IsQuestItem -ne 'false' -or
        [double]$_.Weight -ne 0 -or
        [string]$_.IconId -ne 'special_featherRed'
    }).Count -eq 0
) 'trophy row is a stackable permanent weightless loot collectible'

$nameKeys = @($itemRows | ForEach-Object { [string]$_.UIName })
$infoKeys = @($itemRows | ForEach-Object { [string]$_.UIInfo })
Add-Result (
    $itemRows.Count -gt 0 -and
    @($nameKeys | Where-Object {
        -not $russianText.Contains(
            "<Cell>$_</Cell><Cell>Трофей - Окровавленное перо</Cell>"
        ) -or
        -not $englishText.Contains(
            "<Cell>$_</Cell><Cell>Trophy - Bloodied Feather</Cell>"
        )
    }).Count -eq 0
) 'shared trophy uses the approved bilingual inventory label'
Add-Result (
    $itemRows.Count -gt 0 -and
    @($infoKeys | Where-Object {
        -not $russianText.Contains("<Cell>$_</Cell>") -or
        -not $englishText.Contains("<Cell>$_</Cell>")
    }).Count -eq 0 -and
    -not $russianText.Contains('{{target.') -and
    -not $englishText.Contains('{{target.')
) 'shared trophy has bilingual description text'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
