# GPU acceleration

The [VirtualBox experiment](../windows-virtualbox/README.md) tested sharing the
host GPU. The FreeBSD 7.2.20 packages failed the Windows acceleration check;
they do not provide a working Merenda GPU path on this host.
Its Windows OpenGL path requires validation on this FreeBSD host. CPU rendering
with Mesa LLVMpipe/Lavapipe is another API testing option, but does not satisfy
Merenda's hardware graphics requirement.

bhyve's VNC framebuffer provides a display for installation and recovery. It
does **not** provide a virtual 3D accelerator. For hardware graphics, dedicate
a physical GPU to Windows using PCI passthrough, then install a compatible
Windows vendor driver. Merenda rendering must be checked in the actual session
where the application runs; a working VNC or RDP connection is not proof of
OpenGL/Direct3D acceleration.

## This host

Inventory on 2026-10-10: FreeBSD 15.1-RELEASE-p1, Ryzen 7 8745HS, 16 GiB RAM.

| Device | Host PCI location | Driver / purpose |
| --- | --- | --- |
| Radeon 780M / HawkPoint1 | `199/0/0` | `vgapci0` with `amdgpu`, host desktop |
| Radeon HDMI/DP audio | `199/0/1` | `hdac0` |
| AMD IOMMU | `0/0/2` | present; `hw.vmm.amdvi.enable=0` |

There is only one GPU. Passing the 780M through removes it from the FreeBSD
desktop. Keeping the desktop requires a separate GPU that can be reserved for
Windows. This setup initially keeps GPU passthrough disabled.

The 780M is an integrated GPU and its VBIOS, reset behavior, memory mappings,
and driver compatibility need hardware validation. Do not assume the steps
below guarantee it will work. Server's 180-day evaluation is convenient, but
consumer Radeon drivers may support Windows 10/11 rather than Server. Check the
GPU vendor's actual supported OS list. If the driver excludes Server, use
[Windows 11 Enterprise's 90-day evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise)
with a separately prepared Windows 11 installation and TPM/firmware setup;
the included answer file is specifically for Server, and does not implement
Windows 11 requirement bypasses.

## Reserve a dedicated GPU

1. Identify the GPU and its audio functions with `sudo vm passthru` and
   `pciconf -lv`. Enable SVM and IOMMU/AMD-Vi in motherboard firmware. On Intel,
   enable VT-x and VT-d. Confirm SSH access before reserving a host display GPU.
2. Merge the following settings into `/boot/loader.conf.local`, substituting
   the actual GPU functions. Keep any existing `pptdevs` reservations. Loading
   `vmm` at boot is necessary for `ppt` to claim devices before native drivers.

   ```conf
   vmm_load="YES"
   hw.vmm.amdvi.enable="1"
   # Example ONLY for dedicating this host's Radeon 780M and HDMI audio:
   pptdevs="199/0/0 199/0/1"
   ```

   `hw.vmm.amdvi.enable` applies to AMD hosts. Do not reserve the neighboring
   PSP, USB controllers, or storage controllers just because they share a bus.
   Host boot/display reservations and PCI isolation must be checked on the
   actual machine. The scripts do not detach drivers or edit loader settings.
3. Reboot the host when ready. Check:

   ```sh
   sysctl hw.vmm.amdvi.enable
   sudo vm passthru
   pciconf -l pci0:199:0:0
   pciconf -l pci0:199:0:1
   ```

   The selected functions must attach to **ppt**, with `READY` shown as `Yes`.
   On this AMD host the IOMMU setting must be `1`. If they remain attached to
   host drivers, resolve boot reservations first.

## Attach to Windows

Copy `config.example.json` to `config.json`, and set the chosen functions:

```json
{
  "gpu_devices": ["199/0/0", "199/0/1"],
  "gpu_rom": ""
}
```

Settings in `config.json` override defaults, so the file can contain just those
two keys. Leave the list empty until hardware is reserved. For a different GPU,
use its actual addresses. Then:

```sh
sudo python3 lab.py stop
python3 lab.py gpu-check
sudo python3 lab.py gpu-enable
sudo python3 lab.py start
```

The helper requires `ppt`, checks AMD-Vi, wires guest memory using `-S`, groups
GPU/audio functions into the same guest PCI slot, and can supply a VBIOS via
`passthru0_options="rom=/absolute/path/to/gpu.rom"`. Use a ROM from the exact
device if needed; the helper does not extract firmware. Current edk2-bhyve is
required for GPU ROM initialization. See the
[FreeBSD Foundation's GPU passthrough article](https://freebsdfoundation.org/wp-content/uploads/2023/05/a66452da2b483e5e92bde6533b7236c4d11382eb-1-1.pdf)
for why AMD GPUs may need the VBIOS.

In Windows, install a vendor-supported driver, reboot, then run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\MerendaLab\VerifyGpu.ps1 -RequireHardware
```

Check Device Manager for a healthy vendor adapter, inspect
`C:\MerendaLab\dxdiag.txt`, and run a Merenda graphical example. The script checks
driver enumeration; it does not prove a particular rendering API is accelerated.
Use a monitor attached to the passed GPU for the initial rendering check. The
guest allows hardware adapters in RDP through `bEnumerateHWBeforeSW`; application
and driver support still determine what gets accelerated. VNC continues to show
the emulated framebuffer and may not show the GPU's desktop.

Code 12 (resources), Code 43 (driver/device initialization), a black screen, or
failure on the second VM boot require device-specific investigation. Check
firmware/ROM, PCI BAR allocation, IOMMU initialization, and GPU reset behavior.
A host reboot may be necessary when a GPU cannot reset cleanly. If resource
allocation fails, inspect firmware settings such as Above 4G Decoding and
Resizable BAR rather than applying an unrelated GPU's settings blindly.

## Undo

```sh
sudo python3 lab.py stop
sudo python3 lab.py gpu-disable
sudo python3 lab.py start
```

This removes passthrough from the VM. To return the device to the host, remove
only its entries from `pptdevs` and reboot. If a saved `@clean` baseline includes
GPU passthrough, resetting also restores those VM settings; create the baseline
for the hardware arrangement you intend to reuse.

References: [ppt(4)](https://man.freebsd.org/cgi/man.cgi?query=ppt&sektion=4),
[vmm(4)](https://man.freebsd.org/cgi/man.cgi?query=vmm&sektion=4),
[bhyve(8)](https://man.freebsd.org/cgi/man.cgi?query=bhyve&sektion=8),
[vm-bhyve passthrough configuration](https://github.com/churchers/vm-bhyve/blob/master/sample-templates/config.sample).
