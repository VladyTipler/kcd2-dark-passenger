$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$deployScript = Join-Path $repoRoot 'tools\Deploy-DevLevelOverlay.ps1'
$fixtureRoot = Join-Path $repoRoot 'build\test-dev-level-overlay'
$fixtureBuild = Join-Path $fixtureRoot 'build'
$fixtureGame = Join-Path $fixtureRoot 'game'
$fixtureBackup = Join-Path $fixtureRoot 'backups'
$fixtureBuildLevel =
    Join-Path $fixtureBuild 'Data\Levels\kutnohorsko'
$fixtureGameLevel =
    Join-Path $fixtureGame 'Data\Levels\kutnohorsko'

if (Test-Path -LiteralPath $fixtureRoot) {
    $resolvedFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
    $resolvedBuild = [System.IO.Path]::GetFullPath(
        (Join-Path $repoRoot 'build')
    ) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedFixture.StartsWith(
        $resolvedBuild,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to replace fixture outside build root: $resolvedFixture"
    }
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path `
    $fixtureBuildLevel,
    $fixtureGameLevel,
    $fixtureBackup |
    Out-Null

$generatedObjects = @'
<?xml version="1.0" encoding="us-ascii"?>
<Objects>
  <Entity Name="kutnohorsko" EntityClass="LevelHolder" EntityId="1" EntityGuid="10702dff-9271-4a74">
    <EntityLinks><Link TargetId="1831841" TargetGuid="00000000-0000-0000" Name="module" /></EntityLinks>
  </Entity>
  <Entity Name="dark_within_k" EntityClass="SmartObjectHolder" EntityId="1831841" EntityGuid="f4a73e20-28c5-4bd2">
    <EntityLinks><Link TargetId="3" TargetGuid="00000000-0000-0000" Name="asset['DP_PritokySearchArea']" /></EntityLinks>
  </Entity>
</Objects>
'@
$generatedPath = Join-Path $fixtureBuildLevel 'objects_mission0.xml'
[System.IO.File]::WriteAllText(
    $generatedPath,
    $generatedObjects,
    [System.Text.Encoding]::ASCII
)
$generatedWaitingLinks = @'
<?xml version="1.0" encoding="us-ascii"?>
<StaticLinksInfo version="1">
  <WaitingLinks>
    <WaitingLink SourceId="vanilla-source" TargetId="vanilla-target">
      <LinkDefinition>vanilla</LinkDefinition>
    </WaitingLink>
    <WaitingLink SourceId="10702dff-9271-4a74" TargetId="f4a73e20-28c5-4bd2">
      <LinkDefinition>module</LinkDefinition>
    </WaitingLink>
    <WaitingLink SourceId="f4a73e20-28c5-4bd2" TargetId="d0fa0ece-6af5-19f6">
      <LinkDefinition>asset[&apos;DP_PritokySearchArea&apos;]</LinkDefinition>
    </WaitingLink>
  </WaitingLinks>
  <StreamableTargets />
</StaticLinksInfo>
'@
$generatedWaitingLinksPath =
    Join-Path $fixtureBuildLevel 'waitinglinks.xml'
[System.IO.File]::WriteAllText(
    $generatedWaitingLinksPath,
    $generatedWaitingLinks,
    [System.Text.Encoding]::ASCII
)
[System.IO.File]::WriteAllText(
    (Join-Path $fixtureGameLevel 'waitinglinks.xml'),
    '<stale />',
    [System.Text.Encoding]::ASCII
)
[System.IO.File]::WriteAllText(
    (Join-Path $fixtureGame 'user.cfg'),
    "sys_PakPriority = 0`r`n",
    [System.Text.Encoding]::ASCII
)

if (-not (Test-Path -LiteralPath $deployScript)) {
    throw "Missing dev level overlay deployer: $deployScript"
}

& $deployScript `
    -BuildRoot $fixtureBuild `
    -DevGameRoot $fixtureGame `
    -BackupRoot $fixtureBackup `
    -GameProcessName 'DarkPassengerOverlayTestNoProcess'

$deployedPath = Join-Path $fixtureGameLevel 'objects_mission0.xml'
$deployedWaitingLinksPath =
    Join-Path $fixtureGameLevel 'waitinglinks.xml'
if (-not (Test-Path -LiteralPath $deployedPath)) {
    throw 'Generated mission objects were not deployed as a loose dev file.'
}
if (
    (Get-FileHash -Algorithm SHA256 -LiteralPath $deployedPath).Hash -ne
    (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedPath).Hash
) {
    throw 'Deployed loose mission objects do not match the generated build.'
}
if (-not (Test-Path -LiteralPath $deployedWaitingLinksPath)) {
    throw 'Generated waitinglinks were not deployed as a loose dev file.'
}
if (
    (Get-FileHash -Algorithm SHA256 -LiteralPath $deployedWaitingLinksPath).Hash -ne
    (Get-FileHash -Algorithm SHA256 -LiteralPath $generatedWaitingLinksPath).Hash
) {
    throw 'Deployed loose waitinglinks do not match the generated build.'
}
$deployedText = [System.IO.File]::ReadAllText($deployedPath)
if (
    -not $deployedText.Contains('EntityGuid="10702dff-9271-4a74"') -or
    -not $deployedText.Contains(
        '<Link TargetId="1831841" TargetGuid="00000000-0000-0000" Name="module" />'
    ) -or
    $deployedText.Contains('EntityGuid="b8bf53a6-8c3a-41c9"') -or
    $deployedText.Contains('EntityGuid="c1d9358b-7f4e-4a26"')
) {
    throw 'Deployed loose mission objects do not attach the quest to Barbora Kuttenberg.'
}
$backedUpWaitingLinks = @(
    Get-ChildItem -LiteralPath $fixtureBackup -Recurse -File |
        Where-Object { $_.Name -eq 'waitinglinks.xml' }
)
if ($backedUpWaitingLinks.Count -ne 1) {
    throw 'Stale loose waitinglinks.xml was not preserved exactly once.'
}
if (
    [System.IO.File]::ReadAllText($backedUpWaitingLinks[0].FullName) -ne
    '<stale />'
) {
    throw 'Backup does not contain the replaced stale waitinglinks file.'
}

Write-Host 'RESULT: PASS (dev loose level overlay)'
