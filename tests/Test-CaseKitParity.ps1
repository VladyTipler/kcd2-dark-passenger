$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$caseKitCli = Join-Path $repoRoot 'casekit\cli\Compile-CaseKit.ps1'
$legacyCompiler = Join-Path $repoRoot 'tools\Compile-CaseSpecs.ps1'
$caseRoot = Join-Path $repoRoot 'content\migration\legacy-cases'
$bindingPath = Join-Path $repoRoot `
    'content\migration\legacy-case-settlement-bindings.json'
$archetypeRoot = Join-Path $repoRoot 'content\archetypes'
$storyRoot = Join-Path $repoRoot 'content\stories'
$evidenceModuleRoot = Join-Path $repoRoot 'content\evidence-modules'
$worldIndexPath = Join-Path $repoRoot 'config\world-semantic-index.json'
$settlementCatalogPath = Join-Path $repoRoot `
    'config\settlement-investigation-areas.json'
$settlementProfileRoot = Join-Path $repoRoot 'config\settlements'
$stableIdRegistryPath = Join-Path $repoRoot 'config\casekit-stable-ids.json'
$kcd2AdapterPath = Join-Path $repoRoot 'config\casekit-kcd2-native.json'
$localizationRoot = Join-Path $repoRoot 'localization'
$sourceLibsRoot = Join-Path $repoRoot 'src\Data\Libs'
$buildScriptPath = Join-Path $repoRoot 'tools\Build-Mod.ps1'

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

function New-ParityBuildRoot {
    param(
        [Parameter(Mandatory)][string]$Parent,
        [Parameter(Mandatory)][string]$Name
    )

    $root = Join-Path $Parent $Name
    $libs = Join-Path $root 'mod\Data\Libs'
    [System.IO.Directory]::CreateDirectory(
        (Split-Path -Parent $libs)
    ) | Out-Null
    Copy-Item -LiteralPath $sourceLibsRoot -Destination $libs -Recurse
    return $root
}

function Get-ParityFiles {
    param([Parameter(Mandatory)][string]$Root)

    $rootPath = [System.IO.Path]::GetFullPath($Root)
    return @(Get-ChildItem -LiteralPath $rootPath -Recurse -File |
        Sort-Object FullName | ForEach-Object {
            [pscustomobject]@{
                relativePath = $_.FullName.Substring(
                    $rootPath.Length
                ).TrimStart('\')
                hash = (Get-FileHash -LiteralPath $_.FullName `
                    -Algorithm SHA256).Hash
            }
        })
}

function Get-NormalizedNativeParityFiles {
    param([Parameter(Mandatory)][string]$Root)

    $rootPath = [System.IO.Path]::GetFullPath($Root)
    $runtimeVariantCatalog =
        'mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'
    $caseKitEnrichmentFiles = @(
        'generated\cases\native-wiring.json'
        'mod\Data\Libs\Tables\rpg\buff__darkpassengertest.xml'
        'mod\Data\Libs\Tables\rpg\buff_ai_tag__darkpassengertest.xml'
        'mod\Data\Scripts\mods\generated\dp_quest_item_catalog.lua'
        'mod\Data\Scripts\mods\generated\dp_quest_item_placement_catalog.lua'
    )
    return @(Get-ChildItem -LiteralPath $rootPath -Recurse -File |
        Sort-Object FullName | ForEach-Object {
            $relativePath = $_.FullName.Substring(
                $rootPath.Length
            ).TrimStart('\')
            if ($relativePath -eq $runtimeVariantCatalog) { return }
            if ($relativePath -in $caseKitEnrichmentFiles) { return }
            $text = [System.IO.File]::ReadAllText($_.FullName)
            if ($relativePath -eq
                'mod\Data\Libs\Tables\item\item__darkpassengertest.xml') {
                $text = [regex]::Replace(
                    $text,
                    '(?m)^\s*<MiscItem\b[^>]*\bName="dp_trophy_[^"]+"\s*/>\r?\n',
                    ''
                )
            }
            elseif ($relativePath -like
                'generated\localization\*\text__darkpassengertest.xml') {
                $text = [regex]::Replace(
                    $text,
                    '(?m)^\s*<Row><Cell>dp_trophy_[^<]+</Cell>.*?</Row>\r?\n',
                    ''
                )
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
            $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
            [pscustomobject]@{
                relativePath = $relativePath
                hash = [System.Convert]::ToHexString($hash)
            }
        })
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    "dark-passenger-casekit-parity-$([guid]::NewGuid())"
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

try {
    $variantRoot = Join-Path $tempRoot 'variants'
    & $caseKitCli -LegacyCaseRoot $caseRoot `
        -LegacyBindingPath $bindingPath -OutputRoot $variantRoot

    Add-Result (
        (Test-Path -LiteralPath (Join-Path $variantRoot `
            'cases\convenient-accident.case.json') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $variantRoot `
            'cases\missing-traveler.case.json') -PathType Leaf)
    ) 'CaseKit CLI writes both finite compiler variants'

    $manifest = [System.IO.File]::ReadAllText(
        (Join-Path $variantRoot 'casekit-manifest.json')
    ) | ConvertFrom-Json -Depth 100
    Add-Result (
        $manifest.sourceFormat -eq 'casekit-kcd2-compiler-input-v1' -and
        (@($manifest.caseIds) -join ',') -eq
            'convenient_accident,missing_traveler'
    ) 'variant root declares its compiler-input contract'

    $legacyBuild = New-ParityBuildRoot -Parent $tempRoot -Name 'legacy-build'
    $variantBuild = New-ParityBuildRoot -Parent $tempRoot -Name 'variant-build'

    & $legacyCompiler -CaseRoot $caseRoot -BindingPath $bindingPath `
        -LocalizationRoot $localizationRoot -BuildRoot $legacyBuild
    & $legacyCompiler -CaseVariantRoot $variantRoot `
        -LocalizationRoot $localizationRoot -BuildRoot $variantBuild

    $legacyFiles = @(Get-ParityFiles -Root $legacyBuild)
    $variantFiles = @(Get-ParityFiles -Root $variantBuild)
    Add-Result (
        (@($legacyFiles.relativePath) -join "`n") -ceq
        (@($variantFiles.relativePath) -join "`n")
    ) 'legacy and CaseKit paths emit the same artifact set'
    Add-Result (
        ($legacyFiles | ConvertTo-Json -Compress) -ceq
        ($variantFiles | ConvertTo-Json -Compress)
    ) 'legacy and CaseKit paths emit byte-identical native artifacts'

    $variantCases = @(Get-ChildItem -LiteralPath `
        (Join-Path $variantRoot 'cases') -Filter '*.case.json' -File |
        ForEach-Object {
            [System.IO.File]::ReadAllText($_.FullName) |
                ConvertFrom-Json -Depth 100
        } | Sort-Object code)
    Add-Result (
        (@($variantCases.code) -join ',') -eq '1001,2001' -and
        (@($variantCases.evidence.code) -join ',') -eq
            '1101,1102,1103,2101,2102,2103,2104'
    ) 'save-sensitive case and evidence codes remain unchanged'

    $buildScript = [System.IO.File]::ReadAllText($buildScriptPath)
    Add-Result (
        $buildScript.Contains('casekit\cli\Compile-CaseKit.ps1') -and
        $buildScript.Contains('& $caseKitCompilerPath') -and
        $buildScript.Contains('-ArchetypeRoot $archetypeRoot') -and
        $buildScript.Contains('-StoryRoot $storyRoot') -and
        $buildScript.Contains('-EvidenceModuleRoot $evidenceModuleRoot') -and
        $buildScript.Contains('-WorldIndexPath $worldIndexPath') -and
        $buildScript.Contains('-SettlementCatalogPath $settlementCatalogPath') -and
        $buildScript.Contains('-SettlementProfileRoot $settlementProfileRoot') -and
        $buildScript.Contains('-StableIdRegistryPath $stableIdRegistryPath') -and
        $buildScript.Contains('-Kcd2AdapterPath $kcd2AdapterPath') -and
        $buildScript.Contains('-CaseVariantRoot $caseVariantRoot') -and
        -not $buildScript.Contains('-LegacyCaseRoot') -and
        -not $buildScript.Contains('-LegacyBindingPath')
    ) 'Build-Mod routes native generation from authored CaseKit sources'

    $legacyCompilerScript = [System.IO.File]::ReadAllText($legacyCompiler)
    Add-Result (
        -not $legacyCompilerScript.Contains("'content\cases'") -and
        -not $legacyCompilerScript.Contains(
            "'config\case-settlement-bindings.json'"
        )
    ) 'native compiler has no implicit legacy source fallback'

    $authoredRoot = Join-Path $tempRoot 'authored-variants'
    & $caseKitCli -ArchetypeRoot $archetypeRoot `
        -StoryRoot $storyRoot `
        -EvidenceModuleRoot $evidenceModuleRoot `
        -WorldIndexPath $worldIndexPath `
        -SettlementCatalogPath $settlementCatalogPath `
        -SettlementProfileRoot $settlementProfileRoot `
        -StableIdRegistryPath $stableIdRegistryPath `
        -Kcd2AdapterPath $kcd2AdapterPath `
        -MaxVariantsPerCombination 1 `
        -OutputRoot $authoredRoot

    $authoredManifest = [System.IO.File]::ReadAllText(
        (Join-Path $authoredRoot 'casekit-manifest.json')
    ) | ConvertFrom-Json -Depth 100
    Add-Result (
        $authoredManifest.sourceFormat -eq
            'casekit-kcd2-compiler-input-v1' -and
        (@($authoredManifest.caseIds) -join ',') -eq
            'convenient_accident,missing_traveler'
    ) 'authored StoryPacks materialize the native compiler-input contract'

    $authoredBuild = New-ParityBuildRoot -Parent $tempRoot `
        -Name 'authored-build'
    & $legacyCompiler -CaseVariantRoot $authoredRoot `
        -LocalizationRoot $localizationRoot -BuildRoot $authoredBuild
    $authoredFiles = @(Get-ParityFiles -Root $authoredBuild)
    $runtimeVariantCatalog =
        'mod\Data\Scripts\mods\generated\dp_case_variant_catalog.lua'
    $legacyNativeFiles = @(
        Get-NormalizedNativeParityFiles -Root $legacyBuild
    )
    $authoredNativeFiles = @(
        Get-NormalizedNativeParityFiles -Root $authoredBuild
    )
    $legacyNativePaths = @($legacyNativeFiles.relativePath)
    $authoredNativePaths = @($authoredNativeFiles.relativePath)
    Add-Result (
        @($legacyNativePaths | Where-Object {
            $_ -notin $authoredNativePaths
        }).Count -eq 0
    ) 'authored StoryPacks preserve every legacy native artifact path'
    $authoredVariantCatalogPath = Join-Path $authoredBuild `
        $runtimeVariantCatalog
    $authoredVariantCatalog = [System.IO.File]::ReadAllText(
        $authoredVariantCatalogPath
    )
    Add-Result (
        $authoredVariantCatalog.Contains('variant_id =') -and
        $authoredVariantCatalog.Contains('native_ready = true')
    ) 'authored StoryPacks additionally emit finite runtime variants'
    $authoredItemText = [System.IO.File]::ReadAllText((Join-Path `
        $authoredBuild `
        'mod\Data\Libs\Tables\item\item__darkpassengertest.xml'))
    Add-Result (
        @([regex]::Matches(
            $authoredItemText,
            '<MiscItem\b[^>]*\bName="dp_trophy_bloodied_feather"'
        )).Count -eq 1
    ) 'authored StoryPacks add one shared CaseKit trophy item class'
}
catch {
    Add-Result $false "CaseKit parity run: $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
