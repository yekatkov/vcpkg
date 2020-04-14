# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Triplet,
    [AllowEmptyString()][string]$OnlyIncludePorts = "",
    [AllowEmptyString()][string]$ExcludePorts = "",
    [AllowEmptyString()][string]$AdditionalVcpkgFlags = ""
)

Set-StrictMode -Version Latest

$scriptsDir = Split-Path -parent $script:MyInvocation.MyCommand.Definition

function Get-FileRecursivelyUp() {
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $true)][string]$startingDir,
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory = $true)][string]$filename
    )

    $currentDir = $startingDir

    while ($currentDir.Length -gt 0 -and -not (Test-Path "$currentDir\$filename")) {
        Write-Verbose "Examining $currentDir for $filename"
        $currentDir = Split-Path $currentDir -Parent
    }

    Write-Verbose "Examining $currentDir for $filename - Found"
    return $currentDir
}

function Remove-VcpkgItem([Parameter(Mandatory = $true)][string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) {
        return
    }

    if (Test-Path $Path) {
        # Remove-Item -Recurse occasionally fails. This is a workaround
        if ((Get-Item $Path) -is [System.IO.DirectoryInfo]) {
            Remove-Item $Path -Force -Recurse -ErrorAction SilentlyContinue
            for ($i = 0; $i -le 60 -and (Test-Path $Path); $i++) { # ~180s max wait time
                Start-Sleep -m (100 * $i)
                Remove-Item $Path -Force -Recurse -ErrorAction SilentlyContinue
            }

            if (Test-Path $Path) {
                Write-Error "$Path was unable to be fully deleted."
                throw;
            }
        }
        else {
            Remove-Item $Path -Force
        }
    }
}

$vcpkgRootDir = Get-FileRecursivelyUp $scriptsDir .vcpkg-root

Write-Output "Bootstrapping vcpkg ..."
& "$vcpkgRootDir\bootstrap-vcpkg.bat" -Verbose
if (!$?) { throw "bootstrap failed" }
Write-Output "Bootstrapping vcpkg ... done."

$ciXmlPath = "$vcpkgRootDir\test-full-ci.xml"
$consoleOuputPath = "$vcpkgRootDir\console-out.txt"
Remove-VcpkgItem $ciXmlPath

$env:VCPKG_FEATURE_FLAGS = "binarycaching"

if (![string]::IsNullOrEmpty($OnlyIncludePorts)) {
    ./vcpkg install --triplet $Triplet $OnlyIncludePorts $AdditionalVcpkgFlags `
        "--x-xunit=$ciXmlPath" | Tee-Object -FilePath "$consoleOuputPath"
}
else {
    $exclusions = ""
    if (![string]::IsNullOrEmpty($ExcludePorts)) {
        $exclusions = "--exclude=$ExcludePorts"
    }

    if ( $Triplet -notmatch "x86-windows" -and $Triplet -notmatch "x64-windows" ) {
        # WORKAROUND: the x86-windows flavors of these are needed for all
        # cross-compilation, but they are not auto-installed.
        # Install them so the CI succeeds
        ./vcpkg install "protobuf:x86-windows" "boost-build:x86-windows" "sqlite3:x86-windows"
        if (-not $?) { throw "Failed to install protobuf & boost-build & sqlite3" }
    }

    # Turn all error messages into strings for output in the CI system.
    # This is needed due to the way the public Azure DevOps turns error output to pipeline errors,
    # even when told to ignore error output.
    ./vcpkg ci $Triplet $AdditionalVcpkgFlags "--x-xunit=$ciXmlPath" $exclusions 2>&1 `
    | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ }
    }

    # Phasing out the console output (it is already saved in DevOps) Create a dummy file for now.
    "" | Out-File -FilePath "$consoleOuputPath"
}

Write-Output "CI test is complete"
