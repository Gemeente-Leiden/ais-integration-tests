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

function Write-RequestDetails {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][string]$Body
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
    Write-Host $Body
    Write-Host ""
}

function Invoke-ApiRequest {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][string]$Body
    )

    $apiResponseHeaders = $null
    $apiStatusCode = $null
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-RestMethod `
            -Method $Method `
            -Uri $Endpoint `
            -Headers $Headers `
            -Body $Body `
            -SkipCertificateCheck `
            -ResponseHeadersVariable apiResponseHeaders `
            -StatusCodeVariable apiStatusCode `
            -SkipHttpErrorCheck
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
}