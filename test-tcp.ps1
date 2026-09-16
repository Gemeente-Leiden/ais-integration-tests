#!/usr/bin/env pwsh

param(
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 10
)

. (Join-Path $PSScriptRoot "lib/config.ps1")
. (Join-Path $PSScriptRoot "lib/json.ps1")

function Get-TcpEndpoint {
    param([Parameter(Mandatory)][string]$Endpoint)

    $uri = $null
    if (-not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
        [string]::IsNullOrWhiteSpace($uri.DnsSafeHost)) {
        throw "request.endpoint must be an absolute URL with a host."
    }

    if ($uri.Port -lt 1 -or $uri.Port -gt 65535) {
        throw "request.endpoint must specify a valid TCP port."
    }

    return @{
        Host = $uri.DnsSafeHost
        Port = $uri.Port
    }
}

function Test-TcpConnection {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][int]$Timeout
    )

    $ErrorActionPreference = "Stop"
    $client = [System.Net.Sockets.TcpClient]::new()
    $cancellationTokenSource = [System.Threading.CancellationTokenSource]::new()
    $cancellationTokenSource.CancelAfter([TimeSpan]::FromSeconds($Timeout))
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $client.ConnectAsync(
            $HostName,
            $Port,
            $cancellationTokenSource.Token
        ).GetAwaiter().GetResult()
    } catch [System.OperationCanceledException] {
        throw "TCP connection timed out after $Timeout second(s)."
    } catch {
        throw "TCP connection failed: $($_.Exception.GetBaseException().Message)"
    } finally {
        $stopwatch.Stop()
        $cancellationTokenSource.Dispose()
        $client.Dispose()
    }

    return $stopwatch.Elapsed.TotalMilliseconds
}

function Main {
    param(
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][int]$ConnectionTimeoutSeconds
    )

    $configuration = Import-JsonFile `
        -Path $ConfigurationPath
    $endpoint = Get-TcpEndpoint `
        -Endpoint (Get-JsonString -Configuration $configuration -Path "request.endpoint")

    Write-Host ("Testing TCP connection to {0}:{1}." -f $endpoint.Host, $endpoint.Port)
    $durationMilliseconds = Test-TcpConnection `
        -HostName $endpoint.Host `
        -Port $endpoint.Port `
        -Timeout $ConnectionTimeoutSeconds
    Write-Host ("TCP connection succeeded in {0:N2} ms." -f $durationMilliseconds)
}

$resolvedConfigPath = Resolve-ConfigurationPath `
    -ConfigPath $ConfigPath `
    -TestsDirectory (Join-Path $PSScriptRoot "tests") `
    -BasePath $PSScriptRoot

Main `
    -ConfigurationPath $resolvedConfigPath `
    -ConnectionTimeoutSeconds $TimeoutSeconds