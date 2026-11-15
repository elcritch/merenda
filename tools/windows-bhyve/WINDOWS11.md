# Windows 11 bhyve test guest

`win11.py` creates a separate Windows 11 Enterprise evaluation guest named
`merenda-win11`. It uses the ISO in `.local/windows-11-enterprise-26h2-x64-en-us.iso`,
a new 80 GiB sparse disk, 4 GiB of RAM, and a software TPM 2.0 provided by the
FreeBSD `swtpm` package. The TPM state is stored in `/vm/merenda-win11/tpm`;
keep it with the VM's disk and UEFI variables. The guest uses `172.31.0.21`
and a VNC console on `127.0.0.1:5902`. Network setup depends on the existing
`public` vm-bhyve switch and host NAT described in README.md.

The `prepare` command copies the prior Windows 11 Administrator password from
`../windows-virtualbox/.local/windows11-credentials.json` into the private
`.local/windows11/credentials.json`. The new local administrator is `Merenda`,
using that same password. Keep both files private. OpenSSH is optional on
this image; the guest setup configures RDP even if the capability is missing.

```sh
python3 win11.py download  # verifies the pinned Microsoft evaluation ISO
python3 win11.py prepare
sudo python3 win11.py create
sudo python3 win11.py install
sudo python3 win11.py status
sudo python3 win11.py stop
sudo python3 win11.py start
```

For installation, tunnel the console with `ssh -L 5902:127.0.0.1:5902 HOST`,
connect a VNC viewer to `127.0.0.1:5902`, and press a key at the initial DVD
prompt. Don't press a key on subsequent guest reboots. After guest networking
and RDP are ready, tunnel `ssh -L 13389:172.31.0.21:3389 HOST` and connect an
RDP client to `127.0.0.1:13389` as `Merenda` using the existing password.
TPM and Secure Boot compatibility, unattended installation, and RDP availability
must be verified on the running guest.

## Radeon passthrough

The only host GPU is the Radeon 780M at `199/0/0`, with HDMI audio at
`199/0/1`. Windows has to take exclusive ownership; the host cannot use that GPU
at the same time. AMD lists Windows 11 for the 8745HS/780M, but neither this
model's bhyve passthrough nor its Windows driver in that setup is validated.
The FreeBSD `amdgpu` driver is the host display driver; bhyve PCI passthrough
requires `ppt` to claim the GPU instead. See [GPU.md](GPU.md) for prerequisites,
recovery steps and troubleshooting. Do not reserve the GPU without confirmed
remote host access. This host requires AMD-Vi and a reboot to reserve the
functions, which will interrupt host sessions and take away the local display.

After reserving the devices and rebooting, check that AMD-Vi is enabled and
both functions are attached to `ppt`, then:

```sh
sudo python3 win11.py stop
python3 win11.py gpu-check
sudo python3 win11.py gpu-enable
sudo python3 win11.py start
```

Install the AMD Windows driver in the guest and test the actual graphics API;
the bhyve VNC framebuffer itself provides no 3D acceleration. GPU initialization,
IOMMU isolation, firmware and reset behavior are not yet established for this
integrated GPU. To undo VM passthrough use `gpu-disable` while stopped, and to
return the GPU to the host remove its loader reservations and reboot.
