# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#

$ErrorActionPreference = 'Stop'
Write-Host 'Running sysprep'
& C:\Windows\system32\sysprep\sysprep.exe /oobe /generalize /shutdown
