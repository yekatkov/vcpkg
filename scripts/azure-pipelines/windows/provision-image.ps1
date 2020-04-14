# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#
# Sets up a machine in preparation to become a build machine image, optionally switching to
# AdminUser first.
param(
  [string]$AdminUserPassword = $null,
  [string]$StorageAccountName = $null,
  [string]$StorageAccountKey = $null
)

Function Get-TempFilePath {
  Param(
    [String]$Extension
  )

  if ([String]::IsNullOrWhiteSpace($Extension)) {
    throw 'Missing Extension'
  }

  $tempPath = [System.IO.Path]::GetTempPath()
  $tempName = [System.IO.Path]::GetRandomFileName() + '.' + $Extension
  return Join-Path $tempPath $tempName
}

if (-not [string]::IsNullOrEmpty($AdminUserPassword)) {
  Write-Output "AdminUser password supplied; switching to AdminUser"
  $PsExecPath = Get-TempFilePath -Extension 'exe'
  Write-Output "Downloading psexec to $PsExecPath"
  & curl.exe -L -o $PsExecPath -s -S https://live.sysinternals.com/PsExec64.exe
  $PsExecArgs = @(
    '-u',
    'AdminUser',
    '-p',
    $AdminUserPassword,
    '-accepteula',
    '-h',
    'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
    '-ExecutionPolicy',
    'Unrestricted',
    '-File',
    $PSCommandPath
  )

  if (-Not ([string]::IsNullOrWhiteSpace($StorageAccountName))) {
    $PsExecArgs += '-StorageAccountName'
    $PsExecArgs += $StorageAccountName
  }

  if (-Not ([string]::IsNullOrWhiteSpace($StorageAccountKey))) {
    $PsExecArgs += '-StorageAccountKey'
    $PsExecArgs += $StorageAccountKey
  }

  Write-Output "Executing $PsExecPath " + @PsExecArgs

  $proc = Start-Process -FilePath $PsExecPath -ArgumentList $PsExecArgs -Wait -PassThru
  Write-Output 'Cleaning up...'
  Remove-Item $PsExecPath
  exit $proc.ExitCode
}

$Workloads = @(
  'Microsoft.VisualStudio.Workload.NativeDesktop',
  'Microsoft.VisualStudio.Workload.Universal',
  'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
  'Microsoft.VisualStudio.Component.VC.Tools.ARM',
  'Microsoft.VisualStudio.Component.VC.Tools.ARM64',
  'Microsoft.VisualStudio.Component.VC.ATL',
  'Microsoft.VisualStudio.Component.VC.ATLMFC',
  'Microsoft.VisualStudio.Component.VC.v141.x86.x64.Spectre',
  'Microsoft.VisualStudio.Component.Windows10SDK.18362',
  'Microsoft.Net.Component.4.8.SDK',
  'Microsoft.Component.NetFX.Native'
)

$VisualStudioBootstrapperUrl = 'https://aka.ms/vs/16/release/vs_community.exe'
$MpiUrl = 'https://download.microsoft.com/download/A/E/0/AE002626-9D9D-448D-8197-1EA510E297CE/msmpisetup.exe'

$CudaUrl = 'https://developer.download.nvidia.com/compute/cuda/10.1/Prod/local_installers/cuda_10.1.243_426.00_win10.exe'
$CudaFeatures = 'nvcc_10.1 cuobjdump_10.1 nvprune_10.1 cupti_10.1 gpu_library_advisor_10.1 memcheck_10.1 ' + `
  'nvdisasm_10.1 nvprof_10.1 visual_profiler_10.1 visual_studio_integration_10.1 cublas_10.1 cublas_dev_10.1 ' + `
  'cudart_10.1 cufft_10.1 cufft_dev_10.1 curand_10.1 curand_dev_10.1 cusolver_10.1 cusolver_dev_10.1 cusparse_10.1 ' + `
  'cusparse_dev_10.1 nvgraph_10.1 nvgraph_dev_10.1 npp_10.1 npp_dev_10.1 nvrtc_10.1 nvrtc_dev_10.1 nvml_dev_10.1 ' + `
  'occupancy_calculator_10.1 fortran_examples_10.1'

$BinSkimUrl = 'https://www.nuget.org/api/v2/package/Microsoft.CodeAnalysis.BinSkim/1.6.0'

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Function PrintMsiExitCodeMessage {
  Param(
    $ExitCode
  )

  if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {
    Write-Output "Installation successful! Exited with $ExitCode."
  }
  else {
    Write-Output "Installation failed! Exited with $ExitCode."
    exit $ExitCode
  }
}

Function InstallVisualStudio {
  Param(
    [String[]]$Workloads,
    [String]$BootstrapperUrl,
    [String]$InstallPath = $null,
    [String]$Nickname = $null
  )

  try {
    Write-Output 'Downloading Visual Studio...'
    [string]$bootstrapperExe = Get-TempFilePath -Extension 'exe'
    curl.exe -L -o $bootstrapperExe -s -S $BootstrapperUrl
    Write-Output "Installing Visual Studio..."
    $args = @('/c', $bootstrapperExe, '--quiet', '--norestart', '--wait', '--nocache')
    foreach ($workload in $Workloads) {
      $args += '--add'
      $args += $workload
    }

    if (-not ([String]::IsNullOrWhiteSpace($InstallPath))) {
      $args += '--installpath'
      $args += $InstallPath
    }

    if (-not ([String]::IsNullOrWhiteSpace($Nickname))) {
      $args += '--nickname'
      $args += $Nickname
    }

    $proc = Start-Process -FilePath cmd.exe -ArgumentList $args -Wait -PassThru
    PrintMsiExitCodeMessage $proc.ExitCode
  }
  catch {
    Write-Output 'Failed to install Visual Studio!'
    Write-Output $_.Exception.Message
    exit 1
  }
}

Function InstallMSI {
  Param(
    [String]$Name,
    [String]$Url
  )

  try {
    Write-Output "Downloading $Name..."
    [string]$msiPath = Get-TempFilePath -Extension 'msi'
    curl.exe -L -o $msiPath -s -S $Url
    Write-Output "Installing $Name..."
    $args = @('/i', $msiPath, '/norestart', '/quiet', '/qn')
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
    PrintMsiExitCodeMessage $proc.ExitCode
  }
  catch {
    Write-Output "Failed to install $Name!"
    Write-Output $_.Exception.Message
    exit -1
  }
}

Function InstallZip {
  Param(
    [String]$Name,
    [String]$Url,
    [String]$Dir
  )

  try {
    Write-Output "Downloading $Name..."
    [string]$zipPath = Get-TempFilePath -Extension 'zip'
    curl.exe -L -o $zipPath -s -S $Url
    Write-Output "Installing $Name..."
    Expand-Archive -Path $zipPath -DestinationPath $Dir -Force
  }
  catch {
    Write-Output "Failed to install $Name!"
    Write-Output $_.Exception.Message
    exit -1
  }
}

Function InstallMpi {
  Param(
    [String]$Url
  )

  try {
    Write-Output 'Downloading MPI...'
    [string]$installerPath = Get-TempFilePath -Extension 'exe'
    curl.exe -L -o $installerPath -s -S $Url
    Write-Output 'Installing MPI...'
    $proc = Start-Process -FilePath $installerPath -ArgumentList @('-force', '-unattend') -Wait -PassThru
    $exitCode = $proc.ExitCode
    if ($exitCode -eq 0) {
      Write-Output 'Installation successful!'
    }
    else {
      Write-Output "Installation failed! Exited with $exitCode."
      exit $exitCode
    }
  }
  catch {
    Write-Output "Failed to install MPI!"
    Write-Output $_.Exception.Message
    exit -1
  }
}

Function InstallCuda {
  Param(
    [String]$Url,
    [String]$Features
  )

  try {
    Write-Output 'Downloading CUDA...'
    [string]$installerPath = Get-TempFilePath -Extension 'exe'
    curl.exe -L -o $installerPath -s -S $Url
    Write-Output 'Installing CUDA...'
    $proc = Start-Process -FilePath $installerPath -ArgumentList @('-s ' + $Features) -Wait -PassThru
    $exitCode = $proc.ExitCode
    if ($exitCode -eq 0) {
      Write-Output 'Installation successful!'
    }
    else {
      Write-Output "Installation failed! Exited with $exitCode."
      exit $exitCode
    }
  }
  catch {
    Write-Output "Failed to install CUDA!"
    Write-Output $_.Exception.Message
    exit -1
  }
}

Function New-PhysicalDisk {
  Param(
    [int]$DiskNumber,
    [string]$Letter,
    [string]$Label
  )

  if ($Letter.Length -ne 1) {
    throw "Bad drive letter $Letter, expected only one letter. (Did you accidentially add a : ?)"
  }

  try {
    Write-Output "Attempting to online physical disk $DiskNumber"
    [string]$diskpartScriptPath = Get-TempFilePath -Extension 'txt'
    [string]$diskpartScriptContent =
    "SELECT DISK $DiskNumber`r`n" +
    "ONLINE DISK`r`n"

    Write-Output "Writing diskpart script to $diskpartScriptPath with content:"
    Write-Output $diskpartScriptContent
    Set-Content -Path $diskpartScriptPath -Value $diskpartScriptContent
    Write-Output 'Invoking DISKPART...'
    & diskpart.exe /s $diskpartScriptPath

    Write-Output "Provisioning physical disk $DiskNumber as drive $Letter"
    [string]$diskpartScriptContent =
    "SELECT DISK $DiskNumber`r`n" +
    "ATTRIBUTES DISK CLEAR READONLY`r`n" +
    "CREATE PARTITION PRIMARY`r`n" +
    "FORMAT FS=NTFS LABEL=`"$Label`" QUICK`r`n" +
    "ASSIGN LETTER=$Letter`r`n"
    Write-Output "Writing diskpart script to $diskpartScriptPath with content:"
    Write-Output $diskpartScriptContent
    Set-Content -Path $diskpartScriptPath -Value $diskpartScriptContent
    Write-Output 'Invoking DISKPART...'
    & diskpart.exe /s $diskpartScriptPath
  }
  catch {
    Write-Output "Failed to provision physical disk $DiskNumber as drive $Letter!"
    Write-Output $_.Exception.Message
    exit -1
  }
}

Write-Output "AdminUser password not supplied; assuming already running as AdminUser"

New-PhysicalDisk -DiskNumber 2 -Letter 'E' -Label 'install disk'

Write-Host 'Disabling pagefile...'
wmic computersystem set AutomaticManagedPagefile=False
wmic pagefileset delete

Write-Host 'Configuring AntiVirus exclusions...'
Add-MPPreference -ExclusionPath C:\
Add-MPPreference -ExclusionPath D:\
Add-MPPreference -ExclusionPath E:\
Add-MPPreference -ExclusionProcess ninja.exe
Add-MPPreference -ExclusionProcess clang-cl.exe
Add-MPPreference -ExclusionProcess cl.exe
Add-MPPreference -ExclusionProcess link.exe
Add-MPPreference -ExclusionProcess python.exe

InstallVisualStudio -Workloads $Workloads -BootstrapperUrl $VisualStudioBootstrapperUrl -Nickname 'Stable'
InstallMpi -Url $MpiUrl
InstallCuda -Url $CudaUrl -Features $CudaFeatures
InstallZip -Url $BinSkimUrl -Name 'BinSkim' -Dir 'C:\BinSkim'
if (-Not ([string]::IsNullOrWhiteSpace($StorageAccountName))) {
  Write-Output 'Storing storage account name to environment'
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
    -Name StorageAccountName `
    -Value $StorageAccountName
}
if (-Not ([string]::IsNullOrWhiteSpace($StorageAccountKey))) {
  Write-Output 'Storing storage account key to environment'
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
    -Name StorageAccountKey `
    -Value $StorageAccountKey
}
