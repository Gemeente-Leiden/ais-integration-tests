function Get-Percentile {
    param(
        [Parameter(Mandatory)][double[]]$Values,
        [Parameter(Mandatory)][int]$Percentile
    )

    $sortedValues = @($Values | Sort-Object)
    $index = [Math]::Ceiling(($Percentile / 100) * $sortedValues.Count) - 1
    return $sortedValues[$index]
}

function Write-DurationStatistics {
    param(
        [Parameter(Mandatory)][double[]]$Durations,
        [Parameter(Mandatory)][int[]]$Percentiles
    )

    if ($Durations.Count -eq 0) {
        Write-Host "No successful request durations available."
        return
    }

    $average = ($Durations | Measure-Object -Average).Average
    Write-Host ("Average request duration: {0:N2} ms" -f $average)

    foreach ($percentile in $Percentiles) {
        $percentileDuration = Get-Percentile `
            -Values $Durations `
            -Percentile $percentile
        Write-Host (
            "P{0} request duration: {1:N2} ms" -f
            $percentile,
            $percentileDuration
        )
    }
}