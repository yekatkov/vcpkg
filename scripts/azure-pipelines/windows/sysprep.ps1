# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#

Write-Output 'Running sysprep'
& C:\Windows\system32\sysprep\sysprep.exe /oobe /generalize /shutdown
