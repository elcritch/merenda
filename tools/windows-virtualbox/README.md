# Windows 11 testing with VirtualBox

The helper creates `merenda-win11-vbox` from Microsoft's English x64 Windows 11
Enterprise evaluation ISO. It uses a new 80 GiB dynamic VDI, UEFI Secure Boot,
a virtual TPM 2.0, two CPUs, 4 GiB RAM, VBoxSVGA, and 256 MiB VRAM. The VM has its own
Administrator credentials in `.local/windows11-credentials.json`. The ISO and
credentials are ignored by Git.

Microsoft's evaluation lasts **90 days**. The download is verified against the
[Microsoft SHA-256 value](https://support.microsoft.com/en-us/servicing/os/windows/docs/2026/09/verify-the-authenticity-of-a-windows-11-enterprise-evaluation-iso-file)
for the 26H2 English x64 evaluation. If Microsoft changes the ISO, update the
configured URL, file name, and digest together; a recorded local hash alone is
not independent verification. Use the evaluation under the license terms
provided with the media. Restoring a snapshot does not extend the evaluation.

## Host prerequisites

The FreeBSD host needs `virtualbox-ose-72`, its matching
`virtualbox-ose-kmod-72`, and a desktop user in `vboxusers`. The headless console
uses the VirtualBox VNC extension included by this host's package.

[Oracle warns against running competing hypervisors](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/Introduction.html).
On this AMD host, stop all bhyve guests and unload `vmm` before starting
VirtualBox, even if no bhyve guests are running. The helper checks this. For the
existing `docker1` guest:

```sh
sudo vm stop docker1
sudo vm list
# Wait for docker1 to be Stopped and /vm/docker1/run.lock to disappear.
sudo kldunload vmm
sudo kldload vboxdrv
```

Do not force module unloading. While VirtualBox runs, avoid all `vm` commands,
including `vm list`, because they can reload `vmm`. Use `VBoxManage list
runningvms` and `kldstat` instead.

## Create and install

From this directory, as the desktop user:

```sh
python3 lab.py download
python3 lab.py prepare
python3 lab.py create
python3 lab.py start --headless
```

`download` checks Microsoft's digest. `prepare` verifies the matching Guest
Additions against Oracle's SHA256SUMS and makes the bootstrap ISO. `create`
refuses to overwrite an existing VM or directory, creates a fresh disk, and
configures VirtualBox's unattended Windows installer. The generated answer files
contain the guest password; the VM directory is private to the desktop user.
Windows Setup accepts the evaluation EULA and formats **disk 0 of the new VM**.

The bootstrap configures RDP, configures OpenSSH if its server capability is
already installed, installs Guest Additions, and reboots. Windows 11 does not
always include OpenSSH Server; if absent, setup records
`C:\MerendaLab\ssh-setup-incomplete.txt` and continues with RDP. Install the
Windows OpenSSH Server optional capability and run `EnableSsh.ps1` to enable
SSH. Other setup logs are under `C:\MerendaLab`. Check the console if
installation needs attention. To start with a local X11 console instead, use
`python3 lab.py start`.

## Access

These ports are bound only to the FreeBSD host's loopback interface:

| Service | Host address | Guest address |
| --- | --- | --- |
| Windows RDP | `127.0.0.1:13389` | `10.0.2.15:3389` |
| Windows SSH | `127.0.0.1:2222` | `10.0.2.15:22` |
| VirtualBox VNC console | `127.0.0.1:15900` | VM console |

To access them from another computer, tunnel through the host:

```sh
ssh -N -L 13389:127.0.0.1:13389 -L 2222:127.0.0.1:2222 \
  -L 15900:127.0.0.1:15900 elcritch@freebsdxx
```

Use a VNC viewer for the installation console, or RDP after Windows has been
configured. Sign in as `Administrator` using `.local/windows11-credentials.json`.
Once OpenSSH Server is installed, configure it in an elevated guest PowerShell:

```powershell
& C:\MerendaLab\EnableSsh.ps1 -PublicKey (Get-Content C:\MerendaLab\HostKey.pub -Raw).Trim() -HostAddress 10.0.2.2
```

For SSH, verify the new Windows host fingerprint through the guest console;
use a separate known-hosts file because a different Windows VM previously used
port 2222:

```sh
ssh -p 2222 -i ../windows-bhyve/.local/id_ed25519 \
  -o UserKnownHostsFile=.local/known_hosts_windows11 Administrator@127.0.0.1
```

The `screenshot`, `secure`, `password`, `run`, `bootstrap`, and `probe` commands
can inspect or control the guest console. `status` reports the VM state and host
listeners; a listening forwarded port does not prove the guest service is ready.

After testing, shut Windows down and restore bhyve:

```sh
python3 lab.py stop
VBoxManage list runningvms
sudo kldunload vboxdrv
sudo kldload vmm
sudo vm start docker1
```

`baseline` creates a stopped `clean` snapshot, and `reset --discard` restores it
and discards guest changes. Saved sessions must be shut down explicitly. Keep
the VM directory and its `Snapshots/` together.

## Graphics limitations

3D is disabled by default. On 2026-10-10, this host's VirtualBox 7.2.20 packages
were tested with a Windows Server guest and Oracle Guest Additions 7.2.20. The
host Radeon 780M reported accelerated OpenGL 4.6, but the default 3D guest path
showed a black desktop and `VERR_NOT_IMPLEMENTED`; the legacy path fell back to
display-only mode and failed to create an OpenGL 3.3 context. Details are in
`.local/validation.txt` and `.local/opengl-report.json`. This is a host backend
limitation observed in those tests; Windows 11 needs its own verification.

VirtualBox documents Windows guest OpenGL and Direct3D support through
[Guest Additions](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/guestadditions.html).
A working host renderer does not establish that the guest's rendering path is
accelerated. Run the OpenGL probe in the **VirtualBox console session**; RDP or
SSH can use a different rendering path. A supported Linux VirtualBox host or a
bhyve guest with a dedicated GPU passed through are possible alternatives.

Run the host-side helper tests without mutating VMs:

```sh
python3 -m unittest discover -s . -p test_lab.py
```
