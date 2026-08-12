param(
    [switch]$Live,
    [string]$RconPassword
)

$ErrorActionPreference = 'Stop'

$modulePath = 'H:\KCD2Mod\DarkPassenger\tools\KCD2-LiveBridge.ps1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Bridge module is missing: $modulePath"
}

. $modulePath

function Assert-Equal {
    param(
        [Parameter(Mandatory=$true)]$Actual,
        [Parameter(Mandatory=$true)]$Expected,
        [Parameter(Mandatory=$true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

Assert-Equal `
    (Get-KCD2RconAuthHash -Challenge '123' -Password 'password') `
    '261e346166b0024c912d6d213bfb85ac' `
    'RCON challenge hash mismatch.'

$command = '#System.LogAlways("A&B<C>")'
$request = New-KCD2XmlRpcRequest -MethodName $command
if (-not $request.Contains(
    '<methodName>#System.LogAlways("A&amp;B&lt;C&gt;")</methodName>'
)) {
    throw "XML-RPC command was not escaped: $request"
}

$config = Get-KCD2LiveBridgeConfig
Assert-Equal $config.DevRestHost 'localhost' 'Dev REST must use its accepted host.'
Assert-Equal $config.DevRestPort 1403 'Unexpected dev REST port.'
Assert-Equal $config.RetailRconHost '127.0.0.1' 'Retail RCON must use loopback.'
Assert-Equal $config.RetailRconPort 1404 'Unexpected retail RCON port.'

$oldPassword = $env:KCD2_RCON_PASSWORD
try {
    $env:KCD2_RCON_PASSWORD = 'from-env'
    Assert-Equal `
        (Resolve-KCD2RconPassword) `
        'from-env' `
        'Environment password was not used.'
    Assert-Equal `
        (Resolve-KCD2RconPassword -Password 'explicit') `
        'explicit' `
        'Explicit password must override the environment.'
} finally {
    $env:KCD2_RCON_PASSWORD = $oldPassword
}

$missingPasswordRejected = $false
try {
    $env:KCD2_RCON_PASSWORD = $null
    Resolve-KCD2RconPassword | Out-Null
} catch {
    $missingPasswordRejected = $_.Exception.Message.Contains(
        'Retail RCON password is missing'
    )
} finally {
    $env:KCD2_RCON_PASSWORD = $oldPassword
}
if (-not $missingPasswordRejected) {
    throw 'Missing retail RCON password must fail closed.'
}

foreach ($functionName in @(
    'Send-KCD2Command',
    'Reload-DarkPassenger',
    'Reload-Case',
    'Reload-All',
    'Install-KCD2LocalRconFirewallRule'
)) {
    if (-not (Get-Command $functionName -CommandType Function -ErrorAction SilentlyContinue)) {
        throw "Expected bridge function is missing: $functionName"
    }
}

'PASS: offline KCD2 live bridge contract.'

if ($Live) {
    $canary = 'DP_RCON_TEST_' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $liveCommand = '#System.LogAlways("[{0}] live retail bridge OK")' -f $canary
    $result = Send-KCD2Command `
        -Command $liveCommand `
        -Mode RetailRcon `
        -RconPassword $RconPassword `
        -PassThru

    if (-not $result.Success -or -not $result.Output.Contains($canary)) {
        throw "Live retail boundary failed: $($result | Out-String)"
    }

    "PASS: live retail XML-RPC boundary ($canary)."
}
