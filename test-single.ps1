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

function Main {
    param(
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][ValidateSet("OAuth2", "mTLS")][string]$AuthenticationType,
        [Parameter(Mandatory)][bool]$SkipCertificateValidation
    )

    $envFile = Join-Path $PSScriptRoot ".env"
    $configuration = Import-JsonFile -Path $ConfigurationPath

    Import-EnvironmentFile -Path $envFile
    Assert-RequiredEnvironmentVariables `
        -EnvironmentFile $envFile `
        -Names @("APIM_SUBSCRIPTION_KEY")

    $authentication = Get-ApiAuthenticationConfiguration `
        -AuthenticationType $AuthenticationType `
        -EnvironmentFile $envFile
    $request = Get-JsonRequestConfiguration `
        -Configuration $configuration
    Add-AuthorizationBearerTokenHeader `
        -Headers $request.Headers `
        -AccessToken $authentication.AccessToken

    Write-RequestDetails `
        -Method $request.Method `
        -Endpoint $request.Endpoint `
        -Headers $request.Headers `
        -Body $request.Body

    $apiResponse = Invoke-ApiRequest `
        -Method $request.Method `
        -Endpoint $request.Endpoint `
        -Headers $request.Headers `
        -Body $request.Body `
        -Certificate $authentication.Certificate `
        -SkipCertificateCheck $SkipCertificateValidation

    Write-ResponseDetails `
        -ApiResponse $apiResponse
}

$resolvedConfigPath = Resolve-ConfigurationPath `
    -ConfigPath $ConfigPath `
    -TestsDirectory (Join-Path $PSScriptRoot "tests") `
    -BasePath $PSScriptRoot

Main `
    -ConfigurationPath $resolvedConfigPath `
    -AuthenticationType $AuthenticationType `
    -SkipCertificateValidation $SkipCertificateCheck.IsPresent