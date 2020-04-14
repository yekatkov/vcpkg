# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#

Param(
    [Parameter(Mandatory = $false)][string]$Triplet,
    [Parameter(Mandatory = $false)][string]$BaselineFile
)

if (-not (Test-Path -Path $BaselineFile)) {
    Write-Error "Unable to find baseline file $BaselineFile"
}

#read in the file, strip out comments and blank lines and spaces
$baselineListRaw = Get-Content -Path $BaselineFile `
    | Where-Object { -not ($_ -match "\s*#") } `
    | Where-Object { -not ( $_ -match "^\s*$") } `
    | ForEach-Object { $_ -replace "\s" }

###############################################################
# This script is running at the beginning of the CI test, so do a little extra
# checking so things can fail early.

#verify everything has a valid value
$missingValues = $baselineListRaw | Where-Object { -not ($_ -match "=\w") }

if ($missingValues) {
    Write-Error "The following are missing values: $missingValues"
}

$invalidValues = $baselineListRaw `
    | Where-Object { -not ($_ -match "=(skip|pass|fail|ignore)$") }

if ($invalidValues) {
    Write-Error "The following have invalid values: $invalidValues"
}

$baselineForTriplet = $baselineListRaw `
    | Where-Object { $_ -match ":$Triplet=" }

# Verify there are no duplicates (redefinitions are not allowed)
$file_map = @{ }
foreach ($port in $baselineForTriplet | ForEach-Object { $_ -replace ":.*$" }) {
    if ($null -ne $file_map[$port]) {
        Write-Error `
            "$($port):$($Triplet) has multiple definitions in $baselineFile"
    }
    $file_map[$port] = $true
}

# Format the skip list for the command line
$skip_list = $baselineForTriplet `
    | Where-Object { $_ -match "=skip$" } `
    | ForEach-Object { $_ -replace ":.*$" }
[string]::Join(",", $skip_list)
