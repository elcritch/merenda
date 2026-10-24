# Disposable Windows test VM with bhyve

Windows Server 2025 **Standard Evaluation with Desktop Experience**, using
vm-bhyve, UEFI, a sparse 80 GiB disk, two vCPUs, and 4 GiB RAM. The scripts
download Microsoft's official English x64 ISO, generate an unattended answer
ISO, configure a private network, RDP and SSH, and support a stopped ZFS baseline
for repeatable tests. GPU passthrough is described in [GPU.md](GPU.md).

## Evaluation terms

[Microsoft's evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025)
expires after **180 days**. Activate online within **10 days** to avoid automatic
shutdown. Use the evaluation under the terms supplied with the media; it is not
a perpetual Windows license. These scripts do not bypass activation or extend
the evaluation period. Reverting a snapshot does not grant a new license period.

The answer file accepts the installation EULA and erases **disk 0 inside this
guest**. Index 2 selects Standard with Desktop Experience in the official Server
2025 evaluation ISO. If you replace the ISO, check its image indexes first using
`dism /Get-WimInfo /WimFile:D:\sources\install.wim` on Windows.

## Host prerequisites and defaults

Run on FreeBSD amd64 with hardware virtualization. Host Python **3.11+**, curl,
vm-bhyve, and edk2-bhyve are required. Install missing packages using FreeBSD's
package manager:

```sh
sudo pkg install vm-bhyve edk2-bhyve python312 curl
```

This folder is configured for the existing host:

| Setting | Value |
| --- | --- |
| VM name | `merenda-win-test` |
| Default vm-bhyve ZFS datastore | `zroot/vm`, mounted at `/vm` |
| Existing virtual switch | `public`, bridge `vm-public` |
| Host bridge / gateway | `172.31.0.1/24` |
| Windows static address | `172.31.0.20/24` |
| VNC on host | `127.0.0.1:5901` |
| RDP in guest | `172.31.0.20:3389`, allowed from `172.31.0.1` |
| SSH in guest | `172.31.0.20:22`, key authentication from `172.31.0.1` |

Provisioned and checked on **2026-10-10**: Windows is installed and activated,
SSH and RDP work, and the stopped baseline `merenda-win-test@clean` has been
saved. The VM boots without installation media. GPU passthrough is disabled;
the guest currently reports Microsoft Basic Display Adapter. Use `status` to
check its current state, or `start` to boot it after a host restart.

`vmm` and `nmdm` are already loaded. IPv4 forwarding and PF NAT for
`172.31.0.0/24` through `wlan0` already exist. The running `docker1` VM uses
8 GiB of this machine's 16 GiB RAM; budget memory before increasing this guest.
The scripts reuse the switch and datastore, and do not modify host networking,
boot configuration, or VM autostart settings.

On another host, first configure vm-bhyve's default ZFS datastore, a virtual
switch, IPv4 forwarding, and NAT or a wired uplink using the
[vm-bhyve documentation](https://github.com/churchers/vm-bhyve). A Wi-Fi station
usually needs routing/NAT rather than a bridge directly to its wireless uplink.
Copy `config.example.json` to `config.json` and adjust addresses, switch,
datastore, and resources. Reserve the static guest address outside any DHCP
pool; this host has no DHCP listener on `vm-public`.

## Create and install

From this directory:

```sh
sudo python3 lab.py check
python3 lab.py download
python3 lab.py prepare
sudo python3 lab.py create
sudo python3 lab.py install
```

The download is about 8 GB and resumes after interruption. Media, generated
passwords, and answer files stay in the ignored `.local/` directory. The download
uses HTTPS and records a SHA-256 digest. To verify against a trusted digest or
pin a previously verified image, set `iso_sha256` in `config.json`. A locally
recorded digest alone is not independent verification of the image.

Open a VNC viewer on **127.0.0.1:5901**. The VM waits for the initial connection.
Press a key when the Windows DVD asks; the rest of installation is unattended.
Do not press a key on subsequent boots. Allow about 10–30 minutes. To check
readiness, with an explicit deadline:

```sh
sudo python3 lab.py wait --timeout 1800
sudo python3 lab.py status
cat .local/credentials.json
```

Log in using `Administrator` and the generated password. If `.local/` was
created as root, read it with `sudo cat`. From another machine, tunnel through
the FreeBSD host:

```sh
ssh -N -L 5901:127.0.0.1:5901 -L 13389:172.31.0.20:3389 elcritch@freebsdxx
```

Connect VNC to `127.0.0.1:5901`, or RDP to `127.0.0.1:13389`. VNC is bound to
loopback; RDP requires Network Level Authentication and permits the host gateway
address. No incoming port is opened on the host's LAN interface.

For commands and file transfer from the FreeBSD host, use the generated SSH key:

```sh
ssh -i .local/id_ed25519 -o UserKnownHostsFile=.local/known_hosts Administrator@172.31.0.20
scp -i .local/id_ed25519 -o UserKnownHostsFile=.local/known_hosts test.zip Administrator@172.31.0.20:Downloads/
```

Check the initial host fingerprint through the guest console before accepting
it. The default SSH shell is Windows `cmd.exe`; run `powershell.exe` for
PowerShell. SSH password login is disabled. The key and the RDP password are
local ignored files; keep them with the VM setup. Server 2025 includes
[OpenSSH Server](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
and the guest script enables it with a firewall rule restricted to the host.

In an elevated Windows PowerShell, activate the evaluation and check its status:

```powershell
cscript.exe C:\Windows\System32\slmgr.vbs /ato
cscript.exe C:\Windows\System32\slmgr.vbs /dlv
powershell.exe -ExecutionPolicy Bypass -File C:\MerendaLab\VerifyGpu.ps1
```

Run Windows Update. The guest gets a full Windows desktop and normal RDP
administrative access; it is not configured as an RDS session host. AHCI storage
and E1000 networking use inbox Windows drivers. The guest scripts are copied to
`C:\MerendaLab`; networking/bootstrap logs are in `setup.log` there.

## Run Merenda tests

Install Nim, a C compiler, Git, Atlas, and atlas-run in Windows following the
[project setup instructions](../../README.md#install-and-run-merenda). In Git
Bash, from a checkout inside the guest:

```sh
atlas install -tuk
atlas-run tests --backend:ic
atlas-run tests --backend:ic --compile-only examples/all_compile.nim
nim ic -r examples/controls_showcase.nim
```

The VM setup installs the operating system and remote access. Compiler tools
and project dependencies are installed separately. Check [GPU.md](GPU.md)
before using graphical examples to assess hardware rendering.

## Baseline and recreation

After installation and activation, shut down cleanly and save the baseline:

```sh
sudo python3 lab.py stop
sudo python3 lab.py baseline
sudo python3 lab.py start
```

`baseline` detaches the answer ISO containing the generated password, disables
the VNC boot wait, and creates `merenda-win-test@clean`. Save it after adding GPU
drivers and testing tools if those should survive resets. The snapshot is disk
state only; GPU passthrough does not support saving a running Windows session.

To discard test changes and reuse the installation:

```sh
sudo python3 lab.py stop
sudo python3 lab.py reset --discard
sudo python3 lab.py start
```

To reinstall from the ISO:

```sh
sudo python3 lab.py stop
sudo python3 lab.py install --discard
```

Reinstallation clears this guest's disk image while keeping its capacity, and
resets UEFI boot variables so the installer DVD takes priority over an existing
Windows Boot Manager entry. Existing ZFS snapshots are preserved.

To remove and recreate only this VM:

```sh
sudo python3 lab.py stop
sudo python3 lab.py destroy --discard
sudo python3 lab.py create
sudo python3 lab.py install
```

Commands refuse to mutate a running VM or a VM without this folder's management
marker and matching ZFS dataset. Reset does not recursively delete newer
snapshots or dependent clones. Manage those explicitly if ZFS rejects a rollback.
The download and credentials survive VM destruction in `.local/`.

## Troubleshooting and verification

Inspect `/vm/merenda-win-test/vm-bhyve.log`, `bhyve.log` if present, and VNC.
If Windows reports an answer-file problem, check
`C:\Windows\Panther\setuperr.log` (or `X:\Windows\Panther` in setup).
If RDP or SSH stays unavailable, check `C:\MerendaLab\setup.log`, Device Manager's
network adapter, and the gateway/NAT settings. No ping response alone does not
mean Windows is down; Windows normally filters incoming ICMP.

Host-side safety tests (no VM starts, deletion, or network changes):

```sh
python3 -m unittest discover -s . -p test_lab.py
```

References: [FreeBSD bhyve handbook](https://docs.freebsd.org/en/books/handbook/virtualization/#virtualization-host-bhyve),
[Microsoft answer-file discovery](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview),
[specialize commands](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous).
