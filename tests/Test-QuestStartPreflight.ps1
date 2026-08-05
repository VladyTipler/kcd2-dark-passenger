$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $root `
    'src\Data\Quests\darkpassengertest\kutnohorsko\dark_within_k.xml.template'
$generatorPath = Join-Path $root 'tools\Generate-VictimArtifacts.ps1'

$template = Get-Content -Raw -LiteralPath $templatePath
$generator = Get-Content -Raw -LiteralPath $generatorPath
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([bool]$Condition, [string]$Label)

    $checks.Add([pscustomobject]@{
        Condition = $Condition
        Label = $Label
    })
}

$targetTrigger = [regex]::Match(
    $template,
    '(?s)<BuffTagTrigger Name="targetTagTrigger">.*?</BuffTagTrigger>'
).Value
$startDelay = [regex]::Match(
    $template,
    '(?s)<Timer Name="removeResetDelay">.*?</Timer>'
).Value
$selectionState = [regex]::Match(
    $template,
    '(?s)<State Name="selectionRequestActive".*?</State>'
).Value

Add-Check (
    $targetTrigger.Contains(
        '<Edge From="watcherActive.State" To="IsActive" />'
    ) -and
    -not $targetTrigger.Contains(
        '<Edge From="questProgress.Active" To="IsActive" />'
    )
) 'target readiness is observed before quest presentation'

Add-Check (
    $startDelay.Contains(
        '<Edge From="targetTagTrigger.OnAdded" To="SetRunning" />'
    ) -and
    -not $startDelay.Contains('satisfactionTrigger.OnRemoved') -and
    -not $startDelay.Contains('coldStartQuestNotActive.True')
) 'quest activation waits for a selected living target'

Add-Check (
    $selectionState.Contains(
        '<Edge From="satisfactionTrigger.OnRemoved" To="SetTrue" />'
    ) -and
    $selectionState.Contains(
        '<Edge From="coldStartQuestNotActive.True" To="SetTrue" />'
    )
) 'selection preflight starts while the quest is still dormant'

Add-Check (
    $generator.Contains(
        '$detectionNodes.Add(''          <Edge From="questProgress.OnActive" To="SetRunning" />'')'
    )
) 'target validation is repeated after quest state reset'

$failed = @($checks | Where-Object { -not $_.Condition })
foreach ($check in $checks) {
    $status = if ($check.Condition) { 'PASS' } else { 'FAIL' }
    Write-Host "${status}: $($check.Label)"
}

if ($failed.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($failed.Count)/$($checks.Count))"
    exit 1
}

Write-Host "RESULT: PASS ($($checks.Count) checks)"
