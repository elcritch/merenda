param([switch]$RequireHardware)
$ErrorActionPreference = 'Stop'
$Adapters = @(Get-CimInstance Win32_VideoController)
$Adapters | Format-Table Name, DriverVersion, Status, ConfigManagerErrorCode, PNPDeviceID -AutoSize
$Physical = @($Adapters | Where-Object {
  $_.PNPDeviceID -match '^PCI\\VEN_(1002|10DE|8086)&' -and
  $_.Name -notmatch 'Microsoft Basic|Remote Display' -and
  $_.ConfigManagerErrorCode -eq 0
})
$Report = 'C:\MerendaLab\dxdiag.txt'
Start-Process dxdiag.exe -ArgumentList '/whql:off', '/t', $Report -Wait
Write-Host "DirectX report: $Report"
Write-Host 'Check its Display Devices section and run the actual Merenda drawing example on the GPU display.'
Write-Host 'A working vendor driver is necessary; this check does not measure OpenGL or Direct3D rendering.'
if (!$Physical) {
  Write-Warning 'No healthy physical GPU with a vendor driver was found. VNC uses a software framebuffer.'
  if ($RequireHardware) { exit 1 }
}
