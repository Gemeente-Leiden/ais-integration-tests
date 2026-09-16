function Get-BasicAuthentication {
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret
    )

    $basicAuthBytes = [System.Text.Encoding]::UTF8.GetBytes("$ClientId`:$ClientSecret")
    return [System.Convert]::ToBase64String($basicAuthBytes)
}

function Get-OAuthAccessToken {
    param(
        [Parameter(Mandatory)][string]$TokenUrl,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$BasicAuthentication
    )

    $tokenHeaders = @{
        "Content-Type" = "application/x-www-form-urlencoded"
        "Authorization" = "Basic $BasicAuthentication"
    }
    $tokenBody = @{
        grant_type = "client_credentials"
        scope      = $Scope
    }

    $tokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri $TokenUrl `
        -Headers $tokenHeaders `
        -Body $tokenBody
    $accessToken = $tokenResponse.access_token

    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        throw "No access token found in OAuth2 response."
    }

    return $accessToken
}

function Get-MtlsClientCertificate {
    param(
        [Parameter(Mandatory)][string]$CertificatePath,
        [AllowNull()][AllowEmptyString()][string]$CertificatePassword
    )

    if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
        throw "Missing mTLS certificate file: $CertificatePath"
    }

    try {
        if ([string]::IsNullOrEmpty($CertificatePassword)) {
            return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath)
        }

        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath, $CertificatePassword)
    } catch {
        throw "Could not load mTLS certificate file: $CertificatePath"
    }
}

function Get-OAuthAuthenticationConfiguration {
    Assert-RequiredEnvironmentVariables `
        -Names @(
            "OAUTH2_CLIENT_ID",
            "OAUTH2_CLIENT_SECRET",
            "OAUTH2_SCOPE",
            "OAUTH2_TOKEN_URL"
        )

    $basicAuthentication = Get-BasicAuthentication `
        -ClientId $env:OAUTH2_CLIENT_ID `
        -ClientSecret $env:OAUTH2_CLIENT_SECRET

    return Get-OAuthAccessToken `
        -TokenUrl $env:OAUTH2_TOKEN_URL `
        -Scope $env:OAUTH2_SCOPE `
        -BasicAuthentication $basicAuthentication
}

function Get-MtlsAuthenticationConfiguration {
    Assert-RequiredEnvironmentVariables `
        -Names @("MTLS_CERTIFICATE_PATH")

    return Get-MtlsClientCertificate `
        -CertificatePath $env:MTLS_CERTIFICATE_PATH `
        -CertificatePassword $env:MTLS_CERTIFICATE_PASSWORD
}

function Get-ApiAuthenticationConfiguration {
    param([Parameter(Mandatory)][ValidateSet("OAuth2", "mTLS")][string]$AuthenticationType)

    $authentication = @{
        AccessToken = $null
        Certificate = $null
    }

    switch ($AuthenticationType) {
        "OAuth2" {
            $authentication.AccessToken = Get-OAuthAuthenticationConfiguration
        }
        "mTLS" {
            $authentication.Certificate = Get-MtlsAuthenticationConfiguration
        }
    }

    return $authentication
}

function Add-AuthorizationBearerTokenHeader {
    param(
        [Parameter(Mandatory)][hashtable]$Headers,
        [AllowNull()][AllowEmptyString()][string]$AccessToken
    )

    if (-not [string]::IsNullOrWhiteSpace($AccessToken)) {
        $Headers["Authorization"] = "Bearer $AccessToken"
    }
}

function Write-RequestDetails {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Body
    )

    Write-Host ""
    Write-Host "Request:"
    Write-Host ("Method: {0}" -f $Method)
    Write-Host ("Uri: {0}" -f $Endpoint)
    Write-Host "Request headers:"
    $Headers.GetEnumerator() |
        Sort-Object Key |
        ForEach-Object { Write-Host ("{0}: {1}" -f $_.Key, $_.Value) }
    Write-Host "Request body:"
    Write-Host $(if ($null -ne $Body) { $Body } else { "(none)" })
    Write-Host ""
}

function Invoke-ApiRequest {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Body,
        [AllowNull()][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [bool]$SkipCertificateCheck = $false
    )

    $apiResponseHeaders = $null
    $apiStatusCode = $null
    $requestParameters = @{
        Method                  = $Method
        Uri                     = $Endpoint
        Headers                 = $Headers
        ResponseHeadersVariable = "apiResponseHeaders"
        StatusCodeVariable      = "apiStatusCode"
        SkipHttpErrorCheck      = $true
    }
    if ($SkipCertificateCheck) {
        $requestParameters.SkipCertificateCheck = $true
    }
    if ($null -ne $Certificate) {
        $requestParameters.Certificate = $Certificate
    }
    if ($null -ne $Body) {
        $requestParameters.Body = $Body
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-RestMethod @requestParameters
    } finally {
        $stopwatch.Stop()
    }

    return @{
        StatusCode           = $apiStatusCode
        Headers              = $apiResponseHeaders
        Body                 = $response
        DurationMilliseconds = $stopwatch.Elapsed.TotalMilliseconds
    }
}

function Write-ResponseDetails {
    param([Parameter(Mandatory)][hashtable]$ApiResponse)

    Write-Host ("Response status: {0}" -f $ApiResponse.StatusCode)
    Write-Host "Response headers:"
    if ($null -ne $ApiResponse.Headers) {
        $ApiResponse.Headers.GetEnumerator() |
            Sort-Object Key |
            ForEach-Object {
                $headerValue = if ($_.Value -is [System.Collections.IEnumerable] -and -not ($_.Value -is [string])) {
                    ($_.Value | ForEach-Object { "$_" }) -join ", "
                } else {
                    "$($_.Value)"
                }

                Write-Host ("{0}: {1}" -f $_.Key, $headerValue)
            }
    } else {
        Write-Host "(no response headers captured)"
    }

    Write-Host "Response body:"
    if ($null -ne $ApiResponse.Body) {
        $ApiResponse.Body | ConvertTo-Json -Depth 20
    } else {
        Write-Host "null"
    }
    Write-Host ""

    Write-Host ("Duration: {0:N2} ms" -f $ApiResponse.DurationMilliseconds)
    Write-Host ""
}