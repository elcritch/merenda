$ErrorActionPreference = 'Stop'
$Lab = 'C:\MerendaLab'
New-Item -ItemType Directory -Force $Lab | Out-Null
Copy-Item "$PSScriptRoot\*" $Lab -Recurse -Force
Copy-Item "$PSScriptRoot\..\network.json" $Lab -Force
Get-ChildItem $Lab -File -Recurse | ForEach-Object { $_.IsReadOnly = $false }
& "$Lab\PrepareGuest.ps1"
Start-Transcript -Path "$Lab\virtualbox-setup.log" -Append
try {
  $Installer = Get-Volume | Where-Object DriveLetter | ForEach-Object {
    "$($_.DriveLetter):\VBoxWindowsAdditions.exe"
  } | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (!$Installer) { throw 'Mount the matching Oracle Guest Additions ISO first' }
  $Process = Start-Process $Installer -ArgumentList '/S' -Wait -PassThru
  if ($Process.ExitCode -notin 0, 3010) { throw "Guest Additions failed: $($Process.ExitCode)" }
  'Guest Additions installed; reboot and run ProbeOpenGl.ps1 in the console session.' |
    Set-Content "$Lab\virtualbox-setup-complete.txt"
} finally {
  Stop-Transcript
}
shutdown.exe /r /t 10
