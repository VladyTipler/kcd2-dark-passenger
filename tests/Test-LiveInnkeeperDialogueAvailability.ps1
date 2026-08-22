param(
    [string]$ApiRoot = 'http://127.0.0.1:1403/api',
    [int]$Generation = 1
)

$ErrorActionPreference = 'Stop'

. 'H:\KCD2Mod\dp-dev.ps1'

function Get-ApiXml {
    param([Parameter(Mandatory)][string]$Path)

    $body = & curl.exe --noproxy '*' --silent --show-error `
        "$ApiRoot/$Path"
    if ($LASTEXITCODE -ne 0) {
        throw "CryHttp request failed for '$Path'."
    }
    return [xml]($body -join "`n")
}

function Get-NamedNodeIndex {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    $xml = Get-ApiXml "${Path}?depth=1"
    $index = 0
    foreach ($node in $xml.DocumentElement.ChildNodes) {
        if ([string]$node.Name -eq $Name) { return $index }
        $index++
    }
    throw "Node '$Name' was not found below '$Path'."
}

function Get-StateValue {
    param([Parameter(Mandatory)][string]$NodePath)

    $xml = Get-ApiXml "${NodePath}?depth=2"
    $state = @($xml.DocumentElement.Ports.ChildNodes) |
        Where-Object { [string]$_.Name -eq 'State' } |
        Select-Object -First 1
    if ($null -eq $state) {
        throw "State output was not found at '$NodePath'."
    }
    return [string]$state.Value
}

function Invoke-TriggerPort {
    param(
        [Parameter(Mandatory)][string]$NodePath,
        [Parameter(Mandatory)][string]$PortName
    )

    $xml = Get-ApiXml "${NodePath}/Ports?depth=1"
    $index = 0
    foreach ($port in $xml.DocumentElement.ChildNodes) {
        if ([string]$port.Name -eq $PortName) {
            [void](Get-ApiXml "$NodePath/Ports/$index/Trigger")
            return
        }
        $index++
    }
    throw "Trigger port '$PortName' was not found at '$NodePath'."
}

$rootsPath = 'concept/ConceptManager/Roots'
$barbora = Get-NamedNodeIndex -Path $rootsPath -Name 'Barbora'
$levelsPath = "$rootsPath/$barbora/Nodes"
$trosecko = Get-NamedNodeIndex -Path $levelsPath -Name 'trosecko'
$questsPath = "$levelsPath/$trosecko/Nodes"
$quest = Get-NamedNodeIndex -Path $questsPath -Name 'dark_within_t'
$questNodesPath = "$questsPath/$quest/Nodes"
$availability = Get-NamedNodeIndex `
    -Path $questNodesPath `
    -Name 'rumorDialogueAvailable'
$availabilityPath = "$questNodesPath/$availability"

try {
    Send-KCD2Command (
        '#DarkPassengerEvidence.ApplyAvailability(' +
        $Generation + ',true)'
    ) | Out-Null
    Start-Sleep -Milliseconds 200

    Invoke-TriggerPort -NodePath $availabilityPath -PortName 'SetFalse'
    if ((Get-StateValue $availabilityPath) -ne 'false') {
        throw 'Precondition failed: availability graph state is not false.'
    }

    Send-KCD2Command (
        '#DarkPassengerEvidence.ApplyAvailability(' +
        $Generation + ',true)'
    ) | Out-Null
    Start-Sleep -Milliseconds 200

    if ((Get-StateValue $availabilityPath) -ne 'true') {
        throw (
            'Availability replay failed: a persistent buff did not emit a ' +
            'fresh OnAdded edge into the live quest graph.'
        )
    }

    Write-Output 'PASS: live dialogue availability replays into the quest graph.'
}
finally {
    Send-KCD2Command (
        '#DarkPassengerEvidence.ApplyAvailability(' +
        $Generation + ',false);' +
        'DarkPassengerEvidence.ApplyAvailability(' +
        $Generation + ',true)'
    ) | Out-Null
}
