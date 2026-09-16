function Import-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing JSON configuration file: $Path"
    }

    try {
        $configuration = Get-Content -LiteralPath $Path -Raw |
            ConvertFrom-Json -AsHashtable -ErrorAction Stop
    } catch {
        throw "Invalid JSON configuration file: $Path"
    }

    if ($configuration -isnot [System.Collections.IDictionary]) {
        throw "JSON configuration must contain an object: $Path"
    }

    return $configuration
}

function Get-JsonValue {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration,
        [Parameter(Mandatory)][string]$Path
    )

    $value = $Configuration
    foreach ($segment in $Path.Split(".")) {
        if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($segment)) {
            throw "Missing required JSON setting: $Path"
        }

        $value = $value[$segment]
    }

    if ($null -eq $value) {
        throw "Missing required JSON setting: $Path"
    }

    return $value
}

function Get-JsonString {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration,
        [Parameter(Mandatory)][string]$Path
    )

    $value = Get-JsonValue -Configuration $Configuration -Path $Path
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        throw "JSON setting must be a non-empty string: $Path"
    }

    return $value
}

function Get-JsonObject {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration,
        [Parameter(Mandatory)][string]$Path
    )

    $value = Get-JsonValue -Configuration $Configuration -Path $Path
    if ($value -isnot [System.Collections.IDictionary]) {
        throw "JSON setting must be an object: $Path"
    }

    return $value
}

function Get-JsonPositiveInteger {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration,
        [Parameter(Mandatory)][string]$Path
    )

    $value = Get-JsonValue -Configuration $Configuration -Path $Path
    $parsedValue = 0
    if (-not [int]::TryParse("$value", [ref]$parsedValue) -or $parsedValue -le 0) {
        throw "JSON setting must be a positive integer: $Path"
    }

    return $parsedValue
}

function Get-JsonIntegerList {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Minimum,
        [Parameter(Mandatory)][int]$Maximum
    )

    $value = Get-JsonValue -Configuration $Configuration -Path $Path
    if ($value -is [string] -or $value -isnot [System.Collections.IEnumerable]) {
        throw "JSON setting must be an array of integers: $Path"
    }

    $result = @($value | ForEach-Object {
        $parsedValue = 0
        if (-not [int]::TryParse("$_", [ref]$parsedValue) -or
            $parsedValue -lt $Minimum -or
            $parsedValue -gt $Maximum) {
            throw "JSON setting values must be integers between $Minimum and ${Maximum}: $Path"
        }

        $parsedValue
    })

    if ($result.Count -eq 0) {
        throw "JSON setting must contain at least one value: $Path"
    }

    return $result
}

function Resolve-JsonPlaceholders {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][object]$Value,
        [hashtable]$Variables = @{}
    )

    if ($Value -is [System.Collections.IDictionary]) {
        $resolvedObject = @{}
        foreach ($key in $Value.Keys) {
            $resolvedObject[$key] = Resolve-JsonPlaceholders `
                -Value $Value[$key] `
                -Variables $Variables
        }
        return $resolvedObject
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $resolvedArray = @($Value | ForEach-Object {
            Resolve-JsonPlaceholders -Value $_ -Variables $Variables
        })
        return ,$resolvedArray
    }

    if ($Value -isnot [string]) {
        return $Value
    }

    return [regex]::Replace($Value, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', {
        param($match)

        $name = $match.Groups[1].Value
        $replacement = if ($Variables.ContainsKey($name)) {
            $Variables[$name]
        } else {
            [Environment]::GetEnvironmentVariable($name)
        }

        if ([string]::IsNullOrWhiteSpace($replacement)) {
            throw "No value found for JSON placeholder: `$`${$name}"
        }

        return "$replacement"
    })
}

function ConvertTo-JsonText {
    param([Parameter(Mandatory)][AllowEmptyString()][object]$Value)

    return $Value | ConvertTo-Json -Depth 100 -Compress
}

function Get-JsonRequestConfiguration {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Configuration)

    $headers = Resolve-JsonPlaceholders `
        -Value (Get-JsonObject -Configuration $Configuration -Path "request.headers") `
        -Variables @{}
    $request = Get-JsonObject -Configuration $Configuration -Path "request"
    $body = $null

    if ($request.Contains("body") -and $null -ne $request["body"]) {
        $resolvedBody = Resolve-JsonPlaceholders `
            -Value $request["body"] `
            -Variables @{}
        $body = if ($resolvedBody -is [string]) {
            $resolvedBody
        } else {
            ConvertTo-JsonText -Value $resolvedBody
        }
    }

    return @{
        Endpoint = Get-JsonString -Configuration $Configuration -Path "request.endpoint"
        Method   = Get-JsonString -Configuration $Configuration -Path "request.method"
        Headers  = $headers
        Body     = $body
    }
}