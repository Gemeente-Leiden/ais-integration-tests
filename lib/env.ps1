function Import-EnvironmentFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing environment file: $Path"
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            return
        }

        $name, $value = $line -split "=", 2
        if ([string]::IsNullOrWhiteSpace($name) -or $null -eq $value) {
            throw "Invalid line in ${Path}: $_"
        }

        [Environment]::SetEnvironmentVariable(
            $name.Trim(),
            $value.Trim().Trim('"').Trim("'"),
            "Process"
        )
    }
}

function Assert-RequiredEnvironmentVariables {
    param(
        [Parameter(Mandatory)][string]$EnvironmentFile,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($variableName in $Names) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variableName))) {
            throw "Missing required variable in ${EnvironmentFile}: $variableName"
        }
    }
}