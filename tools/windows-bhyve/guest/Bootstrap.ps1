$ErrorActionPreference = 'Stop'
$Lab = 'C:\MerendaLab'
New-Item -ItemType Directory -Force $Lab | Out-Null
Copy-Item "$PSScriptRoot\*" $Lab -Recurse -Force
Copy-Item "$PSScriptRoot\..\network.json" $Lab -Force
& "$Lab\PrepareGuest.ps1"
