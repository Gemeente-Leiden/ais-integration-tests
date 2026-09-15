function Resolve-ConfigurationPath {
    param(
        [AllowNull()][AllowEmptyString()][string]$ConfigPath,
        [Parameter(Mandatory)][string]$TestsDirectory,
        [Parameter(Mandatory)][string]$BasePath
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return $ConfigPath
    }

    if (-not (Test-Path -LiteralPath $TestsDirectory -PathType Container)) {
        throw "Missing tests directory: $TestsDirectory"
    }

    $configurationFiles = @(
        Get-ChildItem -LiteralPath $TestsDirectory -Recurse -File -Filter "*.json" |
            Sort-Object FullName
    )

    if ($configurationFiles.Count -eq 0) {
        throw "No JSON configuration files found in tests directory: $TestsDirectory"
    }

    Write-Host "Select a configuration file:"
    for ($index = 0; $index -lt $configurationFiles.Count; $index++) {
        $relativePath = [System.IO.Path]::GetRelativePath($BasePath, $configurationFiles[$index].FullName)
        Write-Host ("[{0}] {1}" -f ($index + 1), $relativePath)
    }

    do {
        $selection = Read-Host ("Enter a number between 1 and {0}" -f $configurationFiles.Count)
        $selectedIndex = 0
    } until (
        [int]::TryParse($selection, [ref]$selectedIndex) -and
        $selectedIndex -ge 1 -and
        $selectedIndex -le $configurationFiles.Count
    )

    return $configurationFiles[$selectedIndex - 1].FullName
}