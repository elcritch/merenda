param(
  [Parameter(Mandatory)][string]$PublicKey,
  [Parameter(Mandatory)][string]$HostAddress
)
$ErrorActionPreference = 'Stop'
if (!(Get-Service sshd -ErrorAction SilentlyContinue)) {
  throw 'OpenSSH Server is missing; Server 2025 includes it by default.'
}
$SshDirectory = "$env:ProgramData\ssh"
New-Item -ItemType Directory -Force $SshDirectory | Out-Null
$AuthorizedKeys = "$SshDirectory\administrators_authorized_keys"
$PublicKey | Set-Content $AuthorizedKeys -Encoding ascii
icacls.exe $AuthorizedKeys /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not restrict SSH authorized key permissions' }

# Starting once creates the default sshd_config and host keys.
Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue | Disable-NetFirewallRule
Get-NetFirewallRule -Name MerendaLab-SSH -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name MerendaLab-SSH -DisplayName 'Merenda Lab SSH from host' `
  -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress $HostAddress -Profile Any | Out-Null
Set-Service sshd -StartupType Automatic
Start-Service sshd
$ConfigFile = "$SshDirectory\sshd_config"
$ConfigText = Get-Content $ConfigFile -Raw
$ConfigText = $ConfigText -replace '(?m)^#?PasswordAuthentication\s+.*$', 'PasswordAuthentication no'
if ($ConfigText -notmatch '(?m)^PasswordAuthentication no\s*$') {
  $ConfigText = "PasswordAuthentication no`r`n" + $ConfigText
}
$ConfigText | Set-Content $ConfigFile -Encoding ascii
Restart-Service sshd
