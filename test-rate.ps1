#!/usr/bin/env pwsh

param(
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [ValidateSet("OAuth2", "mTLS")]
    [string]$AuthenticationType = "OAuth2",

    [switch]$SkipCertificateCheck
)

. (Join-Path $PSScriptRoot "lib/api.ps1")
. (Join-Path $PSScriptRoot "lib/config.ps1")
. (Join-Path $PSScriptRoot "lib/env.ps1")
. (Join-Path $PSScriptRoot "lib/json.ps1")
. (Join-Path $PSScriptRoot "lib/stats.ps1")

function Start-RateTestExecution {
    param(
        [Parameter(Mandatory)][int]$ExecutionNumber,
        [Parameter(Mandatory)][string]$ApiLibraryPath,
        [Parameter(Mandatory)][string]$RequestMethod,
        [Parameter(Mandatory)][string]$RequestEndpoint,
        [Parameter(Mandatory)][hashtable]$RequestHeaders,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$RequestBody,
        [AllowNull()][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory)][bool]$SkipCertificateCheck,
        [Parameter(Mandatory)][int]$ThrottleLimit
    )

    return Start-ThreadJob `
        -Name "rate-test-$ExecutionNumber" `
        -ThrottleLimit $ThrottleLimit `
        -ScriptBlock {
            param($LibraryPath, $Number, $Method, $Endpoint, $Headers, $Body, $ClientCertificate, $SkipCertificateValidation)

            try {
                . $LibraryPath

                $apiResponse = Invoke-ApiRequest `
                    -Method $Method `
                    -Endpoint $Endpoint `
                    -Headers $Headers `
                    -Body $Body `
                    -Certificate $ClientCertificate `
                    -SkipCertificateCheck $SkipCertificateValidation

                [pscustomobject]@{
                    ExecutionNumber      = $Number
                    Succeeded            = $true
                    DurationMilliseconds = $apiResponse.DurationMilliseconds
                }
            } catch {
                [pscustomobject]@{
                    ExecutionNumber      = $Number
                    Succeeded            = $false
                    DurationMilliseconds = $null
                }
            }
        } `
        -ArgumentList $ApiLibraryPath, $ExecutionNumber, $RequestMethod, $RequestEndpoint, $RequestHeaders, $RequestBody, $Certificate, $SkipCertificateCheck
}

function Start-RateScheduledExecutions {
    param(
        [Parameter(Mandatory)][string]$ApiLibraryPath,
        [Parameter(Mandatory)][string]$RequestMethod,
        [Parameter(Mandatory)][string]$RequestEndpoint,
        [Parameter(Mandatory)][hashtable]$RequestHeaders,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$RequestBody,
        [AllowNull()][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory)][bool]$SkipCertificateCheck,
        [Parameter(Mandatory)][int]$RequestsPerSecond,
        [Parameter(Mandatory)][int]$DurationSeconds
    )

    $jobs = @()
    $totalRequests = $RequestsPerSecond * $DurationSeconds
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    for ($executionNumber = 1; $executionNumber -le $totalRequests; $executionNumber++) {
        $scheduledAt = [TimeSpan]::FromSeconds(
            ($executionNumber - 1) / $RequestsPerSecond
        )
        $delay = $scheduledAt - $stopwatch.Elapsed
        if ($delay.TotalMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([Math]::Ceiling($delay.TotalMilliseconds))
        }

        if ($stopwatch.Elapsed.TotalSeconds -ge $DurationSeconds) {
            break
        }

        $jobs += Start-RateTestExecution `
            -ExecutionNumber $executionNumber `
            -ApiLibraryPath $ApiLibraryPath `
            -RequestMethod $RequestMethod `
            -RequestEndpoint $RequestEndpoint `
            -RequestHeaders $RequestHeaders `
            -RequestBody $RequestBody `
            -Certificate $Certificate `
            -SkipCertificateCheck $SkipCertificateCheck `
            -ThrottleLimit $totalRequests
    }

    $stopwatch.Stop()
    return $jobs
}

function Wait-RateTestExecutions {
    param([Parameter(Mandatory)][System.Management.Automation.Job[]]$Jobs)

    if ($Jobs.Count -eq 0) {
        return @{ Total = 0; Succeeded = 0; Failed = 0; Durations = @() }
    }

    Write-Host ("Waiting for {0} execution(s) to finish." -f $Jobs.Count)
    $Jobs | Wait-Job | Out-Null

    $results = @($Jobs | Receive-Job)
    $succeeded = @($results | Where-Object Succeeded).Count

    return @{
        Total     = $Jobs.Count
        Succeeded = $succeeded
        Failed    = $Jobs.Count - $succeeded
        Durations = @(
            $results |
                Where-Object Succeeded |
                ForEach-Object DurationMilliseconds
        )
    }
}

function Main {
    param(
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][ValidateSet("OAuth2", "mTLS")][string]$AuthenticationType,
        [Parameter(Mandatory)][bool]$SkipCertificateValidation
    )

    $environmentFile = Join-Path $PSScriptRoot ".env"
    $apiLibraryPath = Join-Path $PSScriptRoot "lib/api.ps1"
    $configuration = Import-JsonFile -Path $ConfigurationPath
    $jobs = @()

    Import-EnvironmentFile -Path $environmentFile
    Assert-RequiredEnvironmentVariables `
        -EnvironmentFile $environmentFile `
        -Names @("APIM_SUBSCRIPTION_KEY")

    $requestsPerSecond = Get-JsonPositiveInteger `
        -Configuration $configuration `
        -Path "rate.requestsPerSecond"
    $durationSeconds = Get-JsonPositiveInteger `
        -Configuration $configuration `
        -Path "rate.durationSeconds"
    $percentiles = @(Get-JsonIntegerList `
        -Configuration $configuration `
        -Path "rate.percentiles" `
        -Minimum 1 `
        -Maximum 100)

    $authentication = Get-ApiAuthenticationConfiguration `
        -AuthenticationType $AuthenticationType `
        -EnvironmentFile $environmentFile
    $request = Get-JsonRequestConfiguration `
        -Configuration $configuration
    Add-AuthorizationBearerTokenHeader `
        -Headers $request.Headers `
        -AccessToken $authentication.AccessToken

    Write-Host (
        "Running at {0} request(s) per second for {1} second(s)." -f
        $requestsPerSecond,
        $durationSeconds
    )

    try {
        $jobs = @(Start-RateScheduledExecutions `
            -ApiLibraryPath $apiLibraryPath `
            -RequestMethod $request.Method `
            -RequestEndpoint $request.Endpoint `
            -RequestHeaders $request.Headers `
            -RequestBody $request.Body `
            -Certificate $authentication.Certificate `
            -SkipCertificateCheck $SkipCertificateValidation `
            -RequestsPerSecond $requestsPerSecond `
            -DurationSeconds $durationSeconds)

        $summary = Wait-RateTestExecutions -Jobs $jobs
        Write-Host (
            "Finished: {0} total, {1} succeeded, {2} failed." -f
            $summary.Total,
            $summary.Succeeded,
            $summary.Failed
        )
        Write-DurationStatistics `
            -Durations $summary.Durations `
            -Percentiles $percentiles

        if ($summary.Failed -gt 0) {
            exit 1
        }
    } finally {
        $jobs | Where-Object State -EQ "Running" | Stop-Job
        $jobs | Remove-Job -Force
    }
}

$resolvedConfigPath = Resolve-ConfigurationPath `
    -ConfigPath $ConfigPath `
    -TestsDirectory (Join-Path $PSScriptRoot "tests") `
    -BasePath $PSScriptRoot

Main `
    -ConfigurationPath $resolvedConfigPath `
    -AuthenticationType $AuthenticationType `
    -SkipCertificateValidation $SkipCertificateCheck.IsPresent