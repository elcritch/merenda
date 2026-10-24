$ErrorActionPreference = 'Stop'
$Lab = 'C:\MerendaLab'
Start-Transcript -Path "$Lab\setup.log" -Append
try {
  $Config = Get-Content "$Lab\network.json" -Raw | ConvertFrom-Json
  $Adapter = Get-NetAdapter | Where-Object HardwareInterface | Select-Object -First 1
  if (!$Adapter) { throw 'No network adapter found. Check the emulated E1000 driver in Device Manager.' }
  Set-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -Dhcp Disabled
  Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object IPAddress -ne $Config.ip |
    Remove-NetIPAddress -Confirm:$false
  Get-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false
  if (!(Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -IPAddress $Config.ip -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceIndex $Adapter.ifIndex -IPAddress $Config.ip `
      -PrefixLength $Config.prefix -DefaultGateway $Config.gateway | Out-Null
  } else {
    New-NetRoute -InterfaceIndex $Adapter.ifIndex -DestinationPrefix '0.0.0.0/0' `
      -NextHop $Config.gateway | Out-Null
  }
  Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ServerAddresses $Config.dns

  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
    -Name UserAuthentication -Value 1
  # Host access through the private NAT bridge; leave the other Windows firewall rules enabled.
  Get-NetFirewallRule -Name MerendaLab-RDP -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -Name MerendaLab-RDP -DisplayName 'Merenda Lab RDP from host' `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3389 `
    -RemoteAddress $Config.gateway -Profile Any | Out-Null
  Set-Service TermService -StartupType Automatic
  Start-Service TermService

  & "$Lab\EnableSsh.ps1" -PublicKey (Get-Content "$Lab\HostKey.pub" -Raw).Trim() -HostAddress $Config.gateway

  New-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled `
    -Value 1 -PropertyType DWord -Force | Out-Null
  # Allow installed hardware adapters to render RDP sessions after GPU passthrough is configured.
  $GraphicsPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
  New-Item $GraphicsPolicy -Force | Out-Null
  New-ItemProperty $GraphicsPolicy -Name bEnumerateHWBeforeSW -Value 1 -PropertyType DWord -Force | Out-Null

  'Network and RDP configured. Activate the evaluation online with cscript C:\Windows\System32\slmgr.vbs /ato.' |
    Set-Content "$Lab\setup-complete.txt"
} finally {
  Stop-Transcript
}
