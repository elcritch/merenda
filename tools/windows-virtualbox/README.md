# Windows graphics testing with VirtualBox

VirtualBox **7.2.20**, Windows Server 2025 Standard Evaluation with Desktop
Experience, two CPUs, 4 GiB RAM, an 80 GiB dynamic VDI, **VBoxSVGA**, **256 MiB
VRAM**. **GPU acceleration failed with the FreeBSD packages on this host.**
The saved baseline has 3D disabled and is usable for ordinary Windows testing.
It does not meet Merenda's GPU requirement. The Windows disk was converted from
the stopped [bhyve clean baseline](../windows-bhyve/README.md), preserving its
Administrator credentials and SSH key. The original disk and snapshot remain
available. The converted VDI currently occupies about 16 GiB.

## Current state

Tested on **2026-10-10**: host packages installed, Windows disk converted,
Windows booted, SSH/RDP configured, and matching Oracle Guest Additions
**7.2.20** installed after verifying Oracle's HTTPS SHA256SUMS. Windows was
reactivated successfully as a 180-day evaluation. The host Radeon
780M reports accelerated OpenGL 4.6 with Mesa 26.2.2. Merenda requests an
OpenGL **3.3** context by default.

The console GPU checks failed:

| Configuration | Observed result |
| --- | --- |
| VBoxSVGA, 3D enabled, default VGPU10 | Black desktop; host log reports `VERR_NOT_IMPLEMENTED` creating the output target. |
| VBoxSVGA, 3D enabled, legacy VGPU10 disabled | Desktop works; Windows driver reports `3D is NOT supported by the host, falling back to display-only mode`. |
| OpenGL console probe on the legacy path | `wglCreateContext failed for format 7`; no working OpenGL 3.3 context. |

The host backend reports the real Radeon renderer and OpenGL 4.6, but that
does not establish a working Windows guest driver. Diagnostic excerpts and
the probe result are saved privately in `.local/validation.txt` and
`.local/opengl-report.json`. The VM is powered off with a stopped `clean`
snapshot; `docker1` is restored under bhyve.

The tested package combination cannot provide Merenda's GPU acceleration.
A different host backend, such as a supported Linux VirtualBox host, needs a
fresh console graphics test. bhyve GPU passthrough requires a dedicated GPU
or taking the host's only GPU away from its desktop.

## Exclusive host virtualization

[Oracle warns against concurrent competing hypervisors](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/Introduction.html).
On this AMD host, bhyve enables SVM when `vmm` loads. Unload it before starting
VirtualBox, even if every bhyve guest is stopped. This helper refuses to start
while `vmm` is loaded; it does not stop unrelated VMs or change autostart.

While VirtualBox runs, avoid **all `vm` commands, including `vm list`**:
vm-bhyve can automatically reload `vmm` even for a status query. Use
`VBoxManage list runningvms` to inspect VirtualBox and `kldstat` for modules.

During an agreed Docker downtime window:

```sh
sudo vm stop docker1
sudo vm list
# Wait for docker1 to show Stopped and for its /vm/docker1/run.lock to disappear.
sudo kldunload vmm
sudo kldload vboxdrv
```

Do not force module unloading. A busy module means something still owns it.
The installed kernel module is specifically built for FreeBSD **15.1**.
The desktop user has been added to `vboxusers`; an existing desktop session
needs a new login to pick up membership. With passwordless sudo on this host,
you can refresh the child process's groups without logging out:

```sh
sudo -u elcritch python3 tools/windows-virtualbox/lab.py start
```

The helper starts the GUI directly on the existing X11 desktop, using
`DISPLAY=:0`, its runtime directory, and the login manager's Xauthority file.
These paths are configurable. This avoids a stale display environment in a
VBoxSVC process started earlier over SSH. Run the Windows
graphics tests in the **VirtualBox console session**; RDP or SSH may select a
different rendering path or a noninteractive desktop.

After testing, shut Windows down, confirm that VirtualBox has no running VMs,
and restore bhyve:

```sh
python3 tools/windows-virtualbox/lab.py stop
VBoxManage list runningvms
sudo kldunload vboxdrv
sudo kldload vmm
sudo vm start docker1
```

Switch the modules again before the next VirtualBox test. No boot configuration
was changed, so the existing bhyve setup retains its normal startup behavior.

## First Windows boot

From this directory, check the GUI or take a screenshot:

```sh
python3 lab.py screenshot
python3 lab.py secure
# Check the console is showing the Administrator password prompt before typing.
python3 lab.py password
```

`password` reads the ignored bhyve credentials file without printing the secret
or putting its plaintext in a command-line argument. After the desktop appears,
open Run and check that its input box is visible before typing the command:

```sh
python3 lab.py run
python3 lab.py screenshot
# Check the Run dialog, then:
python3 lab.py bootstrap
```

This runs the bootstrap from the ISO labeled `MERENDA_VBOX`, sets the guest
address to `10.0.2.15`, enables SSH/RDP from the NAT gateway, installs matching
Windows Guest Additions silently, and reboots. Logs are in
`C:\MerendaLab\setup.log` and `virtualbox-setup.log`. If a certificate or driver
prompt appears, inspect and complete it in the console. After reboot, sign in
again, then open Run and check its dialog before typing the probe command:

```sh
python3 lab.py run
python3 lab.py screenshot
python3 lab.py probe
```

The console probe creates a real **OpenGL 3.3 core context**, renders and reads
back a framebuffer color, records vendor/renderer/version, and rejects known
software renderers. Its result is `C:\MerendaLab\opengl-report.json`. Also check
the host backend's renderer in the VM's `Logs/VBox.log`, then run a Merenda GUI
example. Both the guest API and the host Radeon rendering path must work.

If the imported UEFI guest opens an EFI shell instead of Windows, enter
`FS0:\EFI\Microsoft\Boot\bootmgfw.efi`; repair its firmware boot entry before
saving the baseline. The raw disk conversion does not copy bhyve's UEFI variables.

## Access

VirtualBox uses its own NAT network. Host port forwards bind **only loopback**:

| Access | Host address | Guest address |
| --- | --- | --- |
| SSH | `127.0.0.1:2222` | `10.0.2.15:22` |
| RDP | `127.0.0.1:13389` | `10.0.2.15:3389` |

```sh
ssh -p 2222 -i ../windows-bhyve/.local/id_ed25519 \
  -o UserKnownHostsFile=.local/known_hosts Administrator@127.0.0.1
```

Check the host fingerprint through the guest console before accepting it. For
access from another machine, forward these host loopback ports over SSH. The
cloned Windows SSH host keys are initially the same as the bhyve baseline.
RDP uses `Administrator` and `../windows-bhyve/.local/credentials.json`.

Recheck Windows activation after changing virtual hardware:

```powershell
cscript.exe C:\Windows\System32\slmgr.vbs /ato
cscript.exe C:\Windows\System32\slmgr.vbs /dlv
```

This remains Microsoft's **180-day evaluation**, under the terms supplied with
the media. Cloning or restoring snapshots does not grant a new license period.

## Reproduce or reset

The packages used on this FreeBSD 15.1 host:

```sh
sudo pkg install virtualbox-ose-72 virtualbox-ose-kmod-72
sudo pw groupmod vboxusers -m elcritch
```

Copy `config.example.json` to `config.json` for another user/host, and adjust
the VM directory, source baseline, credentials/key, and X11 paths. As the desktop
user, from this directory, prepare the matching Guest Additions and bootstrap:

```sh
python3 lab.py prepare
```

Convert a **stopped, consistent** Windows disk or its read-only ZFS baseline.
Choose a new destination; conversion must not overwrite an existing VM disk:

```sh
mkdir -p '/home/elcritch/VirtualBox VMs/merenda-win-vbox'
chmod 700 '/home/elcritch/VirtualBox VMs/merenda-win-vbox'
sudo VBoxManage convertfromraw \
  /vm/merenda-win-test/.zfs/snapshot/clean/disk0.img \
  '/home/elcritch/VirtualBox VMs/merenda-win-vbox/windows.vdi' \
  --format VDI --variant Standard
sudo chown elcritch:elcritch '/home/elcritch/VirtualBox VMs/merenda-win-vbox/windows.vdi'
python3 lab.py create
```

After Guest Additions and activation, save a stopped baseline. The baseline
on this host has **3D disabled**, following the failed graphics checks above:

```sh
python3 lab.py stop
VBoxManage modifyvm merenda-win-vbox --accelerate-3d off
VBoxManage setextradata merenda-win-vbox VBoxInternal/Devices/vga/0/Config/VMSVGA10
python3 lab.py baseline
python3 lab.py start
```

`baseline` ejects the bootstrap and Guest Additions media and takes a stopped
VirtualBox snapshot named `clean`. To discard test changes:

```sh
python3 lab.py stop
python3 lab.py reset --discard
python3 lab.py start
```

The helper verifies an ownership marker and exact VM configuration path before
mutating an existing VM. Saved running sessions are not treated as stopped disk
baselines. Keep the entire VirtualBox VM directory and its `Snapshots/` together.

Host safety checks, without starting/stopping any VM:

```sh
python3 -m unittest discover -s . -p test_lab.py
```

## Graphics limits

VirtualBox documents Windows guest OpenGL **4.1** and Direct3D support through
[Guest Additions](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/guestadditions.html).
The FreeBSD port enables parts of the 3D backend, but the tested Windows guest
path failed here. Upstream's
[OpenGL output-target implementation](https://github.com/VirtualBox/virtualbox/blob/master/src/VBox/Devices/Graphics/DevVGA-SVGA3d-ogl.cpp)
has Linux-specific implementations and `VERR_NOT_IMPLEMENTED` stubs for other
hosts, consistent with the observed failure. Guest Vulkan acceleration is not
documented as supported.
Do not replace a failed hardware path with CPU Mesa and call it GPU support.

For reproducing the two failed paths, stop the VM before changing its settings:

```sh
VBoxManage modifyvm merenda-win-vbox --accelerate-3d on
# Default VGPU10 path (remove any override):
VBoxManage setextradata merenda-win-vbox VBoxInternal/Devices/vga/0/Config/VMSVGA10
# Or select the legacy path:
VBoxManage setextradata merenda-win-vbox VBoxInternal/Devices/vga/0/Config/VMSVGA10 0
```

The `create` command enables 3D for a fresh experiment; `reset --discard`
restores this host's saved 2D configuration. Graphics verification remains a
separate required step before using the VM for Merenda GUI tests.

For Merenda development tools and Atlas commands, see the
[Windows test instructions](../windows-bhyve/README.md#run-merenda-tests).
