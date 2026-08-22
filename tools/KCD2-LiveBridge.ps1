# Local live-control bridge for Kingdom Come: Deliverance II.
# Dev build: REST console API on localhost:1403 (Host header is significant).
# Retail -DEVMODE: XML-RPC RCON on 127.0.0.1:1404.

function Get-KCD2LiveBridgeConfig {
    [pscustomobject]@{
        DevRestHost = 'localhost'
        DevRestPort = 1403
        RetailRconHost = '127.0.0.1'
        RetailRconPort = 1404
    }
}

function Resolve-KCD2RconPassword {
    param([string]$Password)

    if (-not [string]::IsNullOrWhiteSpace($Password)) {
        return $Password
    }
    if (-not [string]::IsNullOrWhiteSpace($env:KCD2_RCON_PASSWORD)) {
        return $env:KCD2_RCON_PASSWORD
    }

    throw (
        'Retail RCON password is missing. Set KCD2_RCON_PASSWORD or pass ' +
        '-RconPassword. Start the game with ' +
        '''-DEVMODE +http_startserver port:1404 pass:<password>''.'
    )
}

function Get-KCD2RconAuthHash {
    param(
        [Parameter(Mandatory=$true)][string]$Challenge,
        [Parameter(Mandatory=$true)][string]$Password
    )

    $payload = [Text.Encoding]::UTF8.GetBytes("$Challenge`:$Password")
    $md5 = [Security.Cryptography.MD5]::Create()
    try {
        return (($md5.ComputeHash($payload) | ForEach-Object {
            $_.ToString('x2')
        }) -join '')
    } finally {
        $md5.Dispose()
    }
}

function ConvertTo-KCD2XmlText {
    param([AllowEmptyString()][string]$Value)

    return $Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function New-KCD2XmlRpcRequest {
    param(
        [Parameter(Mandatory=$true)][string]$MethodName,
        [string]$StringParameter
    )

    $escapedMethod = ConvertTo-KCD2XmlText $MethodName
    if ($PSBoundParameters.ContainsKey('StringParameter')) {
        $escapedParameter = ConvertTo-KCD2XmlText $StringParameter
        $params = (
            '<params><param><value><string>' + $escapedParameter +
            '</string></value></param></params>'
        )
    } else {
        $params = '<params></params>'
    }

    return (
        '<methodCall><methodName>' + $escapedMethod + '</methodName>' +
        $params + '</methodCall>'
    )
}

function Get-KCD2XmlRpcString {
    param([Parameter(Mandatory=$true)][string]$Body)

    try {
        [xml]$xml = $Body
    } catch {
        throw "Invalid KCD2 XML-RPC response: $Body"
    }

    if ($null -ne $xml.methodResponse.fault) {
        throw "KCD2 XML-RPC fault: $($xml.methodResponse.fault.InnerText)"
    }

    $value = $xml.methodResponse.params.param.value
    if ($null -eq $value) {
        return ''
    }
    if ($null -ne $value.string) {
        return [string]$value.string
    }
    return [string]$value.InnerText
}

function New-KCD2HttpClient {
    param(
        [Parameter(Mandatory=$true)][string]$BaseAddress,
        [int]$TimeoutSeconds = 5
    )

    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $handler.MaxConnectionsPerServer = 1
    $client = [Net.Http.HttpClient]::new($handler)
    $client.BaseAddress = [Uri]$BaseAddress
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    return $client
}

function Invoke-KCD2XmlRpc {
    param(
        [Parameter(Mandatory=$true)][Net.Http.HttpClient]$Client,
        [Parameter(Mandatory=$true)][string]$Request
    )

    $content = [Net.Http.StringContent]::new(
        $Request,
        [Text.Encoding]::UTF8,
        'text/xml'
    )
    try {
        $response = $Client.PostAsync('rpc2', $content).GetAwaiter().GetResult()
        try {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                throw "KCD2 XML-RPC HTTP $([int]$response.StatusCode): $body"
            }
            return Get-KCD2XmlRpcString $body
        } finally {
            $response.Dispose()
        }
    } finally {
        $content.Dispose()
    }
}

function Test-KCD2DevRest {
    $config = Get-KCD2LiveBridgeConfig
    $client = New-KCD2HttpClient (
        "http://$($config.DevRestHost):$($config.DevRestPort)/"
    ) 1
    try {
        $response = $client.GetAsync('api?info').GetAwaiter().GetResult()
        try {
            return $response.IsSuccessStatusCode
        } finally {
            $response.Dispose()
        }
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Send-KCD2DevRestCommand {
    param([Parameter(Mandatory=$true)][string]$Command)

    $config = Get-KCD2LiveBridgeConfig
    $client = New-KCD2HttpClient (
        "http://$($config.DevRestHost):$($config.DevRestPort)/"
    )
    try {
        $encoded = [Uri]::EscapeDataString($Command)
        $response = $client.GetAsync(
            "api/System/Console/ExecuteString?command=$encoded"
        ).GetAwaiter().GetResult()
        try {
            $output = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            return [pscustomobject]@{
                Success = $response.IsSuccessStatusCode
                Mode = 'DevRest'
                StatusCode = [int]$response.StatusCode
                Command = $Command
                Output = $output
            }
        } finally {
            $response.Dispose()
        }
    } finally {
        $client.Dispose()
    }
}

function Send-KCD2RetailRconCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [string]$Password
    )

    $resolvedPassword = Resolve-KCD2RconPassword $Password
    $config = Get-KCD2LiveBridgeConfig
    $client = New-KCD2HttpClient (
        "http://$($config.RetailRconHost):$($config.RetailRconPort)/"
    )
    try {
        $challenge = Invoke-KCD2XmlRpc `
            -Client $client `
            -Request (New-KCD2XmlRpcRequest -MethodName 'challenge')
        $authHash = Get-KCD2RconAuthHash `
            -Challenge $challenge `
            -Password $resolvedPassword
        $authResult = Invoke-KCD2XmlRpc `
            -Client $client `
            -Request (New-KCD2XmlRpcRequest `
                -MethodName 'authenticate' `
                -StringParameter $authHash)

        if ($authResult -ne 'authorized') {
            throw "KCD2 retail RCON authorization failed: $authResult"
        }

        $output = Invoke-KCD2XmlRpc `
            -Client $client `
            -Request (New-KCD2XmlRpcRequest -MethodName $Command)
        return [pscustomobject]@{
            Success = $true
            Mode = 'RetailRcon'
            StatusCode = 200
            Command = $Command
            Output = $output
        }
    } finally {
        $client.Dispose()
    }
}

function Send-KCD2Command {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)][string]$Command,
        [ValidateSet('Auto', 'DevRest', 'RetailRcon')][string]$Mode = 'Auto',
        [string]$RconPassword,
        [switch]$PassThru
    )

    $selectedMode = $Mode
    if ($selectedMode -eq 'Auto') {
        if (Test-KCD2DevRest) {
            $selectedMode = 'DevRest'
        } else {
            $selectedMode = 'RetailRcon'
        }
    }

    if ($selectedMode -eq 'DevRest') {
        $result = Send-KCD2DevRestCommand $Command
    } else {
        $result = Send-KCD2RetailRconCommand `
            -Command $Command `
            -Password $RconPassword
    }

    if ($PassThru) {
        return $result
    }

    if ($result.Success) {
        "OK [$($result.Mode)] <- $Command"
        if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
            $result.Output
        }
    } else {
        "FAIL [$($result.Mode)] HTTP=$($result.StatusCode) <- $Command"
        if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
            $result.Output
        }
    }
}

function Reload-DarkPassenger {
    param(
        [ValidateSet('Auto', 'DevRest', 'RetailRcon')][string]$Mode = 'Auto',
        [string]$RconPassword
    )
    Send-KCD2Command `
        -Command 'lua_reload_script Scripts/mods/darkpassengertest.lua' `
        -Mode $Mode `
        -RconPassword $RconPassword
}

function Reload-Case {
    param(
        [ValidateSet('Auto', 'DevRest', 'RetailRcon')][string]$Mode = 'Auto',
        [string]$RconPassword
    )
    Send-KCD2Command `
        -Command 'lua_reload_script Scripts/Startup/case_state.lua' `
        -Mode $Mode `
        -RconPassword $RconPassword
}

function Reload-All {
    param(
        [ValidateSet('Auto', 'DevRest', 'RetailRcon')][string]$Mode = 'Auto',
        [string]$RconPassword
    )
    Reload-Case -Mode $Mode -RconPassword $RconPassword
    Reload-DarkPassenger -Mode $Mode -RconPassword $RconPassword
}

function Install-KCD2LocalRconFirewallRule {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$DisplayName = 'KCD2 local-only RCON 1404'
    )

    $existing = Get-NetFirewallRule `
        -DisplayName $DisplayName `
        -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        return $existing
    }

    if ($PSCmdlet.ShouldProcess(
        'Inbound TCP 1404',
        'Block non-loopback access to KCD2 RCON'
    )) {
        try {
            return New-NetFirewallRule `
                -DisplayName $DisplayName `
                -Direction Inbound `
                -Action Block `
                -Protocol TCP `
                -LocalPort 1404 `
                -Profile Any `
                -ErrorAction Stop
        } catch {
            throw (
                'Administrator rights are required once to install the ' +
                'local-only KCD2 RCON firewall rule. Original error: ' +
                $_.Exception.Message
            )
        }
    }
}
