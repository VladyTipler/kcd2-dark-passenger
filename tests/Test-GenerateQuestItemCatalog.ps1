$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$generatorPath = Join-Path $repoRoot 'tools\Generate-QuestItemCatalog.ps1'
$tempRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) ('dp-quest-items-' + [guid]::NewGuid().ToString('N'))
$inputRoot = Join-Path $tempRoot 'input'
$additionalRoot = Join-Path $tempRoot 'additional'
$outputPath = Join-Path $tempRoot 'dp_quest_item_catalog.lua'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

try {
    New-Item -ItemType Directory -Path $inputRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $additionalRoot -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $inputRoot 'item.xml'),
        @'
<?xml version="1.0" encoding="utf-8"?>
<Table>
  <Rows>
    <MiscItem IsQuestItem="true" Id="BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB" Name="quest_b" />
    <MiscItem IsQuestItem="false" Id="CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC" Name="ordinary" />
  </Rows>
</Table>
'@,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $inputRoot 'item__extra.xml'),
        @'
<?xml version="1.0" encoding="utf-8"?>
<Table>
  <Rows>
    <Document IsQuestItem="true" Id="AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA" Name="quest_a" />
    <Document IsQuestItem="true" Id="BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB" Name="duplicate" />
  </Rows>
</Table>
'@,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        (Join-Path $additionalRoot 'item__mod.xml'),
        @'
<?xml version="1.0" encoding="utf-8"?>
<Table>
  <Rows>
    <Document IsQuestItem="true" Id="DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD" Name="mod_quest_item" />
  </Rows>
</Table>
'@,
        [System.Text.UTF8Encoding]::new($false)
    )

    Assert-True (Test-Path -LiteralPath $generatorPath) 'generator exists'
    if (Test-Path -LiteralPath $generatorPath) {
        & pwsh -NoProfile -File $generatorPath `
            -InputDirectory $inputRoot `
            -AdditionalInputDirectory $additionalRoot `
            -OutputPath $outputPath *> $null
        Assert-True ($LASTEXITCODE -eq 0) 'generator exits successfully'
    }

    $firstText = if (Test-Path -LiteralPath $outputPath) {
        Get-Content -Raw -LiteralPath $outputPath
    }
    else {
        ''
    }
    Assert-True (
        $firstText.Contains(
            '["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"] = true'
        )
    ) 'first quest item is emitted'
    Assert-True (
        $firstText.Contains(
            '["bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"] = true'
        )
    ) 'second quest item is emitted once'
    Assert-True (
        -not $firstText.Contains(
            'cccccccc-cccc-cccc-cccc-cccccccccccc'
        )
    ) 'ordinary item is excluded'
    Assert-True (
        $firstText.Contains(
            '["dddddddd-dddd-dddd-dddd-dddddddddddd"] = true'
        )
    ) 'additional mod quest item is emitted'
    Assert-True (
        ([regex]::Matches($firstText, '= true')).Count -eq 3
    ) 'quest item GUIDs are merged and deduplicated'
    Assert-True (
        $firstText.IndexOf('aaaaaaaa-aaaa') -lt
        $firstText.IndexOf('bbbbbbbb-bbbb')
    ) 'catalog output is sorted'

    if (Test-Path -LiteralPath $generatorPath) {
        $firstHash = if (Test-Path -LiteralPath $outputPath) {
            (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
        }
        else {
            ''
        }
        & pwsh -NoProfile -File $generatorPath `
            -InputDirectory $inputRoot `
            -AdditionalInputDirectory $additionalRoot `
            -OutputPath $outputPath *> $null
        $secondHash = if (Test-Path -LiteralPath $outputPath) {
            (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
        }
        else {
            ''
        }
        Assert-True (
            -not [string]::IsNullOrWhiteSpace($firstHash) -and
            $firstHash -eq $secondHash
        ) 'catalog generation is deterministic'
    }
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($tempRoot)
    $tempPrefix = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::GetTempPath()
    )
    if (
        $resolved.StartsWith(
            $tempPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -and
        (Test-Path -LiteralPath $resolved)
    ) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "FAIL: $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'RESULT: PASS (8 checks)' -ForegroundColor Green
