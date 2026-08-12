$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generatorPath = Join-Path $repoRoot `
    'tools\Generate-SettlementAreaBindings.ps1'
$fixtureRoot = Join-Path $repoRoot 'build\test-quest-item-stash-bindings'
$levelRoot = Join-Path $fixtureRoot 'levels'
$luaPath = Join-Path $fixtureRoot 'dp_investigation_area_catalog.lua'
$bindingPath = Join-Path $fixtureRoot 'case-settlement-bindings.json'

if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}
[System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
[System.IO.File]::WriteAllText(
    $bindingPath,
    (@{
        schemaVersion = 1
        settlements = @(@{
            caseCode = 2001
            storyId = 'missing-traveler'
            region = 'trosecko'
            settlement = 'troskovice'
            nativeVariantIds = @('missing-traveler-troskovice-1')
            roles = @{
                document = @{
                    containerGuid = '042bf770-1c46-03bf'
                    documentGuid = 'd5833fd4-f7bf-4957-86f5-d661db38bcf3'
                }
            }
        })
    } | ConvertTo-Json -Depth 20) + "`n",
    [System.Text.UTF8Encoding]::new($false)
)

& $generatorPath `
    -OutputRoot $levelRoot `
    -LuaOutputPath $luaPath `
    -SettlementBindingsPath $bindingPath `
    -SettlementProfileRoot (Join-Path $repoRoot 'config\settlements')

$expectations = @(
    [pscustomobject]@{
        region = 'kutnohorsko'
        target = '277db45d-28ac-0286'
        alias = 'DP_EvidenceStash_kutnohorsko_pritoky'
    }
    [pscustomobject]@{
        region = 'trosecko'
        target = 'aaf89994-e94b-0309'
        alias = 'DP_EvidenceStash_trosecko_zelejov'
    }
    [pscustomobject]@{
        region = 'trosecko'
        target = '042bf770-1c46-03bf'
        alias = 'DP_EvidenceStash_trosecko_troskovice'
    }
)

$failures = [System.Collections.Generic.List[string]]::new()
foreach ($expectation in $expectations) {
    $path = Join-Path $levelRoot "$($expectation.region)\waitinglinks.xml"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("missing waitinglinks for $($expectation.region)")
        continue
    }
    $xml = [xml][System.IO.File]::ReadAllText($path)
    $matches = @(
        $xml.StaticLinksInfo.WaitingLinks.WaitingLink |
            Where-Object {
                [string]$_.TargetId -eq $expectation.target -and
                [string]$_.LinkDefinition -eq
                    "asset['$($expectation.alias)']"
            }
    )
    if ($matches.Count -ne 1) {
        $failures.Add(
            "missing unique stash link for $($expectation.region)"
        )
    }
}

if ($failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($failures.Count)/$($expectations.Count))"
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($expectations.Count) generated stash links)"
