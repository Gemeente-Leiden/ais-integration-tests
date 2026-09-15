#!/usr/bin/env pwsh

param(
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath,

    [switch]$SkipCertificateCheck
)

. (Join-Path $PSScriptRoot "lib/api.ps1")
. (Join-Path $PSScriptRoot "lib/config.ps1")
. (Join-Path $PSScriptRoot "lib/env.ps1")
. (Join-Path $PSScriptRoot "lib/json.ps1")

function Main {
    param(
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [Parameter(Mandatory)][bool]$SkipCertificateValidation
    )

    $envFile = Join-Path $PSScriptRoot ".env"
    $configuration = Import-JsonFile -Path $ConfigurationPath

    Import-EnvironmentFile -Path $envFile
    Assert-RequiredEnvironmentVariables `
        -EnvironmentFile $envFile `
        -Names @(
            "OAUTH2_CLIENT_ID",
            "OAUTH2_CLIENT_SECRET",
            "OAUTH2_SCOPE",
            "OAUTH2_TOKEN_URL",
            "APIM_SUBSCRIPTION_KEY"
        )

    $BasicAuthentication = Get-BasicAuthentication `
        -ClientId $env:OAUTH2_CLIENT_ID `
        -ClientSecret $env:OAUTH2_CLIENT_SECRET
    $accessToken = Get-OAuthAccessToken `
        -TokenUrl $env:OAUTH2_TOKEN_URL `
        -Scope $env:OAUTH2_SCOPE `
        -BasicAuthentication $BasicAuthentication
    $request = Get-JsonRequestConfiguration `
        -Configuration $configuration `
        -AccessToken $accessToken

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
    -SkipCertificateValidation $SkipCertificateCheck.IsPresent