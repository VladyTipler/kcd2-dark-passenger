$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'tools\LevelRegistryMerge.psm1'
$buildScriptPath = Join-Path $repoRoot 'tools\Build-Mod.ps1'
$script:checks = 0
$script:failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [bool]$Condition,
        [string]$Message
    )

    $script:checks++
    if ($Condition) {
        Write-Host "PASS: $Message"
        return
    }

    $script:failures.Add($Message)
    Write-Host "FAIL: $Message"
}

Add-Result (Test-Path -LiteralPath $modulePath) 'level registry merge module exists'
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    exit 1
}

Import-Module $modulePath -Force
Add-Result (
    $null -ne (Get-Command Merge-LevelMissionObjects -ErrorAction SilentlyContinue)
) 'module exports Merge-LevelMissionObjects'

$buildScriptText = [System.IO.File]::ReadAllText($buildScriptPath)
Add-Result (
    $buildScriptText.Contains('Import-Module $levelRegistryMergeModulePath -Force') -and
    $buildScriptText.Contains('$objectsMissionText = Merge-LevelMissionObjects') -and
    -not $buildScriptText.Contains('$sourceMatches = @(')
) 'Build-Mod uses the batch merger instead of the per-link full-file scan'

$baseObjects = @'
<?xml version="1.0" encoding="us-ascii"?>
<Objects>
  <Entity Name="level_holder" EntityId="100" EntityGuid="level-guid">
    <EntityLinks />
  </Entity>
  <Entity Name="area_one" EntityId="201" EntityGuid="area-one-guid">
    <EntityLinks />
  </Entity>
  <Entity Name="unrelated" EntityId="300" EntityGuid="unrelated-guid">
    <EntityLinks><Link TargetId="301" Name="keep_me" /></EntityLinks>
  </Entity>
  <Entity Name="area_two" EntityId="202" EntityGuid="area-two-guid">
    <EntityLinks />
  </Entity>
</Objects>
'@
$missionObjectBlock = @'
<Entity Name="quest_holder" EntityId="500" EntityGuid="quest-guid">
  <EntityLinks />
</Entity>
'@
$waitingLinks = @(
    [pscustomobject]@{
        SourceId = 'level-guid'
        TargetId = 'quest-guid'
        LinkDefinition = 'module'
    }
    [pscustomobject]@{
        SourceId = 'quest-guid'
        TargetId = 'area-one-guid'
        LinkDefinition = "asset['DP_SearchArea_One']"
    }
    [pscustomobject]@{
        SourceId = 'quest-guid'
        TargetId = 'area-two-guid'
        LinkDefinition = "asset['DP_SearchArea_Two']"
    }
)
$baseBefore = $baseObjects
$patchBefore = $missionObjectBlock

$merged = Merge-LevelMissionObjects `
    -BaseObjectsText $baseObjects `
    -MissionObjectBlock $missionObjectBlock `
    -WaitingLinks $waitingLinks `
    -Region 'fixture'
$mergedAgain = Merge-LevelMissionObjects `
    -BaseObjectsText $baseObjects `
    -MissionObjectBlock $missionObjectBlock `
    -WaitingLinks $waitingLinks `
    -Region 'fixture'

Add-Result ($merged -ceq $mergedAgain) 'batch merge is byte-for-byte deterministic'

Add-Result (
    ([regex]::Matches($merged, 'EntityGuid="quest-guid"')).Count -eq 1
) 'quest holder is inserted exactly once'
Add-Result (
    $merged.Contains(
        '<Link TargetId="500" TargetGuid="00000000-0000-0000" Name="module" />'
    )
) 'module link resolves the quest holder entity id'
Add-Result (
    $merged.Contains(
        '<Link TargetId="201" TargetGuid="00000000-0000-0000" Name="asset[''DP_SearchArea_One'']" />'
    ) -and
    $merged.Contains(
        '<Link TargetId="202" TargetGuid="00000000-0000-0000" Name="asset[''DP_SearchArea_Two'']" />'
    )
) 'all links sharing one source are inserted with resolved target ids'
Add-Result (
    $merged.Contains('<Link TargetId="301" Name="keep_me" />') -and
    ([regex]::Matches($merged, 'EntityGuid="unrelated-guid"')).Count -eq 1
) 'unrelated entity content is preserved'
Add-Result (
    $baseObjects -ceq $baseBefore -and
    $missionObjectBlock -ceq $patchBefore
) 'merge does not mutate input strings'

$xmlValid = $true
try {
    $null = [xml]$merged
}
catch {
    $xmlValid = $false
}
Add-Result $xmlValid 'merged registry remains valid XML'

$missingTargetRejected = $false
try {
    $null = Merge-LevelMissionObjects `
        -BaseObjectsText $baseObjects `
        -MissionObjectBlock $missionObjectBlock `
        -WaitingLinks @(
            [pscustomobject]@{
                SourceId = 'quest-guid'
                TargetId = 'missing-guid'
                LinkDefinition = "asset['Missing']"
            }
        ) `
        -Region 'fixture'
}
catch {
    $missingTargetRejected =
        $_.Exception.Message.Contains('missing-guid')
}
Add-Result $missingTargetRejected 'missing source or target GUID fails closed'

if ($script:failures.Count -gt 0) {
    Write-Host "RESULT: FAIL ($($script:failures.Count)/$($script:checks))"
    $script:failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "RESULT: PASS ($($script:checks) checks)"
