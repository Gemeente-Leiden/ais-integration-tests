function Resolve-EnvironmentFilePath {
    param([Parameter(Mandatory)][string]$ConfigurationPath)

    $configurationDirectory = [System.IO.DirectoryInfo]::new(
        [System.IO.Path]::GetDirectoryName(
            [System.IO.Path]::GetFullPath($ConfigurationPath)
        )
    )

    $currentDirectory = $configurationDirectory
    while ($null -ne $currentDirectory) {
        $candidatePath = Join-Path $currentDirectory.FullName ".env"
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return $candidatePath
        }

        $currentDirectory = $currentDirectory.Parent
    }
}

function Import-EnvironmentFile {
    param([AllowNull()][AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

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
    param([Parameter(Mandatory)][string[]]$Names)

    foreach ($variableName in $Names) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variableName))) {
            throw "Missing required environment variable: $variableName"
        }
    }
}