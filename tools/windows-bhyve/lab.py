#!/usr/bin/env python3
"""Disposable Windows Server evaluation guest on an existing vm-bhyve host."""

import argparse
import errno
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import socket
import stat
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


HERE = Path(__file__).resolve().parent
LOCAL = HERE / ".local"
ISO = LOCAL / "windows-server-2025.iso"
ANSWER = LOCAL / "answer.iso"
MARKER = "# Managed by merenda tools/windows-bhyve/lab.py"
NS = "urn:schemas-microsoft-com:unattend"
WCM = "http://schemas.microsoft.com/WMIConfig/2002/State"
ET.register_namespace("", NS)
ET.register_namespace("wcm", WCM)


def fail(message):
  raise RuntimeError(message)


def run(*args, capture=False, check=True):
  return subprocess.run(
    [str(arg) for arg in args], check=check, text=True,
    stdout=subprocess.PIPE if capture else None,
    stderr=subprocess.PIPE if capture else None,
  )


def settings():
  config = json.loads((HERE / "config.example.json").read_text())
  if (HERE / "config.json").exists():
    overrides = json.loads((HERE / "config.json").read_text())
    if overrides.keys() - config.keys():
      fail("Unknown config.json settings: " + str(overrides.keys() - config.keys()))
    config.update(overrides)
  for key in ("name", "switch"):
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,39}", config[key]):
      fail(f"Invalid {key}")
  if not re.fullmatch(r"[A-Za-z0-9-]{1,15}", config["computer_name"]):
    fail("computer_name must be at most 15 letters, digits, or hyphens")
  for key in ("memory", "disk_size"):
    if not re.fullmatch(r"[1-9][0-9]*[MG]", config[key]):
      fail(f"Invalid {key}; use a size such as 4G")
  for key in ("vm_dir", "gpu_rom"):
    value = config[key]
    if value and not re.fullmatch(r"/[A-Za-z0-9_./-]+", value):
      fail(f"{key} must be an absolute path without whitespace or shell characters")
  if not re.fullmatch(r"[A-Za-z0-9_/-]+", config["zfs_parent"]):
    fail("Invalid zfs_parent")
  for key in ("cpus", "image_index"):
    if type(config[key]) is not int or config[key] < 1:
      fail(f"{key} must be a positive integer")
  if type(config["vnc_port"]) is not int or not 1024 <= config["vnc_port"] <= 65535:
    fail("vnc_port must be between 1024 and 65535")
  network = ipaddress.IPv4Interface(f'{config["guest_ip"]}/{config["prefix_length"]}').network
  gateway = ipaddress.IPv4Address(config["gateway"])
  if gateway not in network or str(gateway) == config["guest_ip"]:
    fail("gateway must be a different address in the guest subnet")
  for address in config["dns"]:
    ipaddress.IPv4Address(address)
  if not config["dns"]:
    fail("At least one DNS address is required")
  devices = config["gpu_devices"]
  if len(devices) != len(set(devices)) or len(devices) > 8:
    fail("gpu_devices must contain at most eight unique PCI functions")
  for device in devices:
    if not re.fullmatch(r"[0-9]+/[0-9]+/[0-7]", device):
      fail("gpu_devices must use bus/slot/function, e.g. 199/0/0")
  if not config["iso_url"].startswith("https://"):
    fail("iso_url must use HTTPS")
  if config["iso_sha256"] and not re.fullmatch(r"[0-9a-fA-F]{64}", config["iso_sha256"]):
    fail("iso_sha256 must be a SHA-256 hex digest")
  return config


def host(root=False):
  if platform.system() != "FreeBSD" or platform.machine() != "amd64":
    fail("This setup requires a FreeBSD amd64 host")
  if root and os.geteuid() != 0:
    fail("Run this command with sudo python3 lab.py ...")
  for program in ("vm", "bhyve", "bhyvectl", "zfs", "makefs", "curl", "ssh-keygen"):
    if not shutil.which(program):
      fail(f"Missing {program}; see README.md for host prerequisites")


def private_dir():
  LOCAL.mkdir(mode=0o700, exist_ok=True)
  LOCAL.chmod(0o700)


def vm_path(config):
  return Path(config["vm_dir"]) / config["name"]


def vm_config(config):
  return vm_path(config) / (config["name"] + ".conf")


def managed(config):
  path = vm_config(config)
  if not path.exists() or MARKER not in path.read_text().splitlines():
    fail(f"Refusing to change an unmanaged VM: {path}")
  mount = run("zfs", "list", "-H", "-o", "mountpoint", dataset(config), capture=True).stdout.strip()
  if mount != str(vm_path(config)):
    fail(f"Unexpected dataset mountpoint: {mount}")
  return path


def dataset(config):
  return config["zfs_parent"] + "/" + config["name"]


def stopped(config):
  # vm-bhyve keeps the lock across bhyve restarts; /dev/vmm alone has a race.
  if (vm_path(config) / "run.lock").exists() or (Path("/dev/vmm") / config["name"]).exists():
    fail("The VM must be stopped first: python3 lab.py stop")


def port_open(address, port):
  try:
    with socket.create_connection((address, port), timeout=1):
      return True
  except OSError:
    return False


def port_bound(port):
  # Connecting to a waiting VNC console would start the VM and its DVD timer.
  with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
    try:
      probe.bind(("127.0.0.1", port))
    except OSError as error:
      if error.errno == errno.EADDRINUSE:
        return True
      raise
  return False


def download(config):
  private_dir()
  if not ISO.exists():
    partial = ISO.with_suffix(".iso.partial")
    run("curl", "--fail", "--location", "--continue-at", "-", "--retry", "3",
        "--connect-timeout", "20", "--proto", "=https", "--proto-redir", "=https",
        "--output", partial, config["iso_url"])
    partial.rename(ISO)
  if ISO.stat().st_size < 1024 ** 3:
    fail(f"{ISO} is too small to be Windows installation media")
  with ISO.open("rb") as stream:
    digest = hashlib.file_digest(stream, "sha256").hexdigest()
  if config["iso_sha256"] and digest.lower() != config["iso_sha256"].lower():
    fail("ISO SHA-256 mismatch; remove the cached ISO and check the download")
  (LOCAL / "windows-server-2025.iso.sha256").write_text(f"{digest}  {ISO.name}\n")
  print(f"ISO ready; SHA-256: {digest}")
  if not config["iso_sha256"]:
    print("Digest recorded locally. Set iso_sha256 to pin a trusted copy on future downloads.")


def add(parent, tag, value=None, **attrs):
  child = ET.SubElement(parent, f"{{{NS}}}{tag}", attrs)
  if value is not None:
    child.text = str(value)
  return child


def component(parent, name):
  return add(parent, "component", name=name, processorArchitecture="amd64",
             publicKeyToken="31bf3856ad364e35", language="neutral", versionScope="nonSxS")


def answer_xml(config, password):
  root = ET.Element(f"{{{NS}}}unattend")
  pe = add(root, "settings", **{"pass": "windowsPE"})
  intl = component(pe, "Microsoft-Windows-International-Core-WinPE")
  add(add(intl, "SetupUILanguage"), "UILanguage", "en-US")
  for name in ("InputLocale", "SystemLocale", "UILanguage", "UserLocale"):
    add(intl, name, "en-US")
  setup = component(pe, "Microsoft-Windows-Setup")
  disks = add(setup, "DiskConfiguration")
  disk = add(disks, "Disk", **{f"{{{WCM}}}action": "add"})
  add(disk, "DiskID", 0)
  add(disk, "WillWipeDisk", "true")
  partitions = add(disk, "CreatePartitions")
  for order, kind, size in ((1, "EFI", 260), (2, "MSR", 16), (3, "Primary", None)):
    part = add(partitions, "CreatePartition", **{f"{{{WCM}}}action": "add"})
    add(part, "Order", order)
    add(part, "Type", kind)
    add(part, "Size" if size else "Extend", size or "true")
  modify = add(disk, "ModifyPartitions")
  for order, partition_id, fmt, label, letter in ((1, 1, "FAT32", "System", None), (2, 3, "NTFS", "Windows", "C")):
    part = add(modify, "ModifyPartition", **{f"{{{WCM}}}action": "add"})
    add(part, "Order", order)
    add(part, "PartitionID", partition_id)
    add(part, "Format", fmt)
    add(part, "Label", label)
    if letter:
      add(part, "Letter", letter)
  add(disks, "WillShowUI", "OnError")
  image = add(add(setup, "ImageInstall"), "OSImage")
  metadata = add(add(image, "InstallFrom"), "MetaData", **{f"{{{WCM}}}action": "add"})
  add(metadata, "Key", "/IMAGE/INDEX")
  add(metadata, "Value", config["image_index"])
  target = add(image, "InstallTo")
  add(target, "DiskID", 0)
  add(target, "PartitionID", 3)
  add(image, "WillShowUI", "OnError")
  userdata = add(setup, "UserData")
  add(userdata, "AcceptEula", "true")
  add(userdata, "FullName", "Merenda evaluation lab")
  add(userdata, "Organization", "Merenda testing")

  specialize = add(root, "settings", **{"pass": "specialize"})
  shell = component(specialize, "Microsoft-Windows-Shell-Setup")
  add(shell, "ComputerName", config["computer_name"])
  add(shell, "TimeZone", "Mountain Standard Time")
  command = add(add(component(specialize, "Microsoft-Windows-Deployment"), "RunSynchronous"),
                "RunSynchronousCommand", **{f"{{{WCM}}}action": "add"})
  add(command, "Order", 1)
  add(command, "Description", "Configure Merenda test network and remote desktop")
  # RunSynchronousCommand/Path has a 259-character schema limit.
  script = "Get-Volume|? FileSystemLabel -eq MERENDA_SETUP|% {& ($_.DriveLetter+':\\guest\\Bootstrap.ps1')}"
  add(command, "Path", 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' + script + '"')

  oobe = add(root, "settings", **{"pass": "oobeSystem"})
  intl = component(oobe, "Microsoft-Windows-International-Core")
  for name in ("InputLocale", "SystemLocale", "UILanguage", "UserLocale"):
    add(intl, name, "en-US")
  shell = component(oobe, "Microsoft-Windows-Shell-Setup")
  password_node = add(add(shell, "UserAccounts"), "AdministratorPassword")
  add(password_node, "Value", password)
  add(password_node, "PlainText", "true")
  options = add(shell, "OOBE")
  add(options, "HideEULAPage", "true")
  add(options, "HideOnlineAccountScreens", "true")
  add(options, "HideWirelessSetupInOOBE", "true")
  add(options, "ProtectYourPC", 3)
  ET.indent(root, space="  ")
  return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def prepare(config):
  private_dir()
  key = LOCAL / "id_ed25519"
  if not key.exists():
    run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "merenda-windows-lab", "-f", key)
  secret = LOCAL / "credentials.json"
  if secret.exists():
    password = json.loads(secret.read_text())["password"]
  else:
    password = "Mw9!" + secrets.token_urlsafe(24)
    secret.write_text(json.dumps({"username": "Administrator", "password": password}, indent=2) + "\n")
    secret.chmod(0o600)
  media = LOCAL / "answer"
  if media.exists():
    shutil.rmtree(media)
  media.mkdir(exist_ok=True)
  (media / "Autounattend.xml").write_bytes(answer_xml(config, password))
  (media / "Autounattend.xml").chmod(0o600)
  shutil.copytree(HERE / "guest", media / "guest", dirs_exist_ok=True)
  shutil.copyfile(key.with_suffix(".pub"), media / "guest" / "HostKey.pub")
  (media / "network.json").write_text(json.dumps({
    "ip": config["guest_ip"], "prefix": config["prefix_length"],
    "gateway": config["gateway"], "dns": config["dns"],
  }))
  partial = ANSWER.with_suffix(".iso.partial")
  run("makefs", "-t", "cd9660", "-o", "isolevel=2", "-o", "rockridge", "-o", "label=MERENDA_SETUP", partial, media)
  partial.chmod(0o600)
  partial.replace(ANSWER)
  print(f"Answer ISO ready. Administrator credentials are in {secret}")


def template(config):
  return f'''{MARKER}
loader="uefi"
uefi_vars="yes"
cpu="{config['cpus']}"
cpu_sockets="1"
cpu_cores="{config['cpus']}"
cpu_threads="1"
memory="{config['memory']}"
utctime="no"
graphics="yes"
graphics_listen="127.0.0.1"
graphics_port="{config['vnc_port']}"
graphics_res="1280x720"
graphics_wait="auto"
xhci_mouse="yes"
ahci_device_limit="8"
network0_type="e1000"
network0_switch="{config['switch']}"
disk0_type="ahci-hd"
disk0_name="disk0.img"
disk0_size="{config['disk_size']}"
disk1_type="ahci-cd"
disk1_dev="custom"
disk1_name="{ANSWER}"
'''


def create(config):
  if vm_path(config).exists():
    fail(f"{vm_path(config)} already exists; refusing to replace it")
  if not ISO.exists() or not ANSWER.exists():
    fail("Run download and prepare first")
  mount = run("zfs", "list", "-H", "-o", "mountpoint", config["zfs_parent"], capture=True).stdout.strip()
  if mount != config["vm_dir"]:
    fail("zfs_parent does not mount at vm_dir")
  datastores = run("vm", "datastore", "list", capture=True).stdout.splitlines()
  if not any(line.split() == ["default", "zfs", config["vm_dir"], config["zfs_parent"]]
             for line in datastores[1:]):
    fail("vm_dir and zfs_parent must match the default vm-bhyve ZFS datastore")
  switches = run("vm", "switch", "list", capture=True).stdout.splitlines()
  if not any(line.split() and line.split()[0] == config["switch"] for line in switches[1:]):
    fail("The configured switch does not exist; see README.md")
  if port_bound(config["vnc_port"]):
    fail("The configured VNC port is already in use")
  source = Path(config["vm_dir"]) / ".templates" / (config["name"] + ".conf")
  if source.exists() and MARKER not in source.read_text().splitlines():
    fail(f"Refusing to overwrite another template: {source}")
  source.write_text(template(config))
  run("vm", "create", "-t", config["name"], config["name"])
  managed(config)
  run("zfs", "set", "primarycache=metadata", dataset(config))
  print(f"Created {config['name']}; run install next")


def start(config, install=False, discard=False):
  path = managed(config)
  stopped(config)
  if install:
    installed = vm_path(config) / "install-started"
    if installed.exists() and not discard:
      fail("Installation wipes the guest disk; repeat with --discard to reinstall")
    if not ISO.exists() or not ANSWER.exists():
      fail("Missing installation media")
    disk = vm_path(config) / "disk0.img"
    metadata = disk.lstat()
    text = path.read_text()
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or
        'disk0_name="disk0.img"' not in text.splitlines() or
        re.search(r'^disk0_dev="(?!file")[^"]+"', text, flags=re.M)):
      fail("Reinstallation requires this setup's regular disk0.img file")
    # Remove stale setup/upgrade state as well as partitions. Preserve capacity
    # and snapshots, and avoid following a symlink or truncating a shared file.
    with disk.open("wb") as stream:
      stream.truncate(metadata.st_size)
    # A previous Windows Boot Manager entry would take priority over the DVD.
    # vm-bhyve recreates the VARS file from its firmware template at next boot.
    (vm_path(config) / "uefi-vars.fd").unlink(missing_ok=True)
    text = re.sub(r"^disk1_.*\n", "", text, flags=re.M)
    text += f'\ndisk1_type="ahci-cd"\ndisk1_dev="custom"\ndisk1_name="{ANSWER}"\n'
    text = re.sub(r'^graphics_wait="[^"]*"', 'graphics_wait="auto"', text, flags=re.M)
    path.write_text(text)
    installed.touch()
    run("vm", "install", config["name"], ISO)
    print("Connect VNC to 127.0.0.1:" + str(config["vnc_port"]) +
          " and press a key at 'Press any key to boot from CD or DVD'.")
    print("Windows Setup then runs unattended. Do not press a key on later reboots.")
  else:
    # Wait is useful only for the first installer boot.
    text = re.sub(r'^graphics_wait="[^"]*"', 'graphics_wait="no"', path.read_text(), flags=re.M)
    path.write_text(text)
    run("vm", "start", config["name"])


def stop(config):
  managed(config)
  if not (vm_path(config) / "run.lock").exists() and not (Path("/dev/vmm") / config["name"]).exists():
    print("VM is already stopped")
    return
  run("vm", "stop", config["name"])
  deadline = time.monotonic() + 60
  while time.monotonic() < deadline:
    if not (vm_path(config) / "run.lock").exists() and not (Path("/dev/vmm") / config["name"]).exists():
      print("VM stopped")
      return
    time.sleep(0.25)
  fail("Guest did not stop within 60 seconds; check Windows before using vm poweroff")


def gpu_check(config):
  devices = run("pciconf", "-lv", capture=True).stdout
  for block in devices.split("\n"):
    if "class=0x03" in block:
      print(block)
  cpu = run("sysctl", "-n", "hw.model", capture=True).stdout.strip()
  if "AMD" in cpu:
    result = run("sysctl", "-n", "hw.vmm.amdvi.enable", capture=True, check=False)
    print("AMD IOMMU enabled: " + (result.stdout.strip() or "unknown"))
  print("Configured GPU functions: " + (" ".join(config["gpu_devices"]) or "none"))
  for bsf in config["gpu_devices"]:
    b, s, f = bsf.split("/")
    result = run("pciconf", "-l", f"pci0:{b}:{s}:{f}", capture=True)
    print(result.stdout.strip())


def gpu(config, enable):
  path = managed(config)
  stopped(config)
  text = path.read_text()
  if enable:
    if not config["gpu_devices"]:
      fail("Set gpu_devices in config.json after reserving the GPU at boot; see GPU.md")
    if "AMD" in run("sysctl", "-n", "hw.model", capture=True).stdout:
      if run("sysctl", "-n", "hw.vmm.amdvi.enable", capture=True).stdout.strip() != "1":
        fail("AMD-Vi is disabled; enable it at boot before attaching GPU devices")
    for bsf in config["gpu_devices"]:
      b, s, f = bsf.split("/")
      attached = run("pciconf", "-l", f"pci0:{b}:{s}:{f}", capture=True).stdout
      if not re.match(r"ppt[0-9]+@", attached):
        fail(f"{bsf} is not attached to ppt; refusing to detach a host device")
    if config["gpu_rom"] and not Path(config["gpu_rom"]).is_file():
      fail("gpu_rom does not exist")
  # Only touch settings owned by this command. Keep other vm-bhyve state.
  text = re.sub(r"^# BEGIN MERENDA GPU\n.*?^# END MERENDA GPU\n?", "", text, flags=re.M | re.S)
  if enable:
    lines = ["# BEGIN MERENDA GPU", 'wired_memory="yes"']
    slots = {}
    for index, bsf in enumerate(config["gpu_devices"]):
      b, s, f = bsf.split("/")
      slot = slots.setdefault((b, s), 8 + len(slots))
      lines.append(f'passthru{index}="{bsf}={slot}:{f}"')
      if index == 0 and config["gpu_rom"]:
        lines.append(f'passthru{index}_options="rom={config["gpu_rom"]}"')
    lines.append("# END MERENDA GPU")
    text += "\n" + "\n".join(lines) + "\n"
  path.write_text(text)
  print("GPU passthrough " + ("configured; install the vendor driver in Windows" if enable else "removed from VM config"))


def status(config):
  run("vm", "list")
  print(f"VNC 127.0.0.1:{config['vnc_port']}: " + ("port bound" if port_bound(config["vnc_port"]) else "not bound"))
  print(f"RDP {config['guest_ip']}:3389: " + ("reachable" if port_open(config["guest_ip"], 3389) else "not reachable"))
  print(f"SSH {config['guest_ip']}:22: " + ("reachable" if port_open(config["guest_ip"], 22) else "not reachable"))
  print("Credentials: " + str(LOCAL / "credentials.json"))


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("command", choices=("check", "download", "prepare", "create", "install", "start", "stop",
                                         "status", "wait", "baseline", "reset", "destroy", "gpu-check",
                                         "gpu-enable", "gpu-disable"))
  parser.add_argument("--discard", action="store_true", help="acknowledge loss of this test VM's changes")
  parser.add_argument("--timeout", type=int, default=1800, help="installation readiness deadline in seconds")
  args = parser.parse_args()
  config = settings()
  host(root=args.command not in ("download", "prepare", "gpu-check"))
  if args.command == "check":
    run("uname", "-r")
    run("vm", "datastore", "list")
    run("vm", "switch", "list")
    gpu_check(config)
  elif args.command == "download":
    download(config)
  elif args.command == "prepare":
    prepare(config)
  elif args.command == "create":
    create(config)
  elif args.command in ("start", "install"):
    start(config, install=args.command == "install", discard=args.discard)
  elif args.command == "stop":
    stop(config)
  elif args.command == "status":
    status(config)
  elif args.command == "wait":
    managed(config)
    if args.timeout <= 0:
      fail("timeout must be positive")
    # Windows installation can take 10-30 minutes, longer than a normal event wait.
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
      if port_open(config["guest_ip"], 3389):
        print("Windows RDP is reachable. Sign in as Administrator; run VerifyGpu.ps1 to check acceleration.")
        return
      if not (vm_path(config) / "run.lock").exists():
        fail("VM exited before RDP became ready; inspect vm-bhyve.log and bhyve.log")
      time.sleep(1)
    fail("RDP readiness deadline expired; inspect VNC and C:\\MerendaLab\\setup.log")
  elif args.command in ("baseline", "reset", "destroy"):
    managed(config)
    stopped(config)
    if args.command == "baseline":
      path = vm_config(config)
      text = re.sub(r"^disk1_.*\n", "", path.read_text(), flags=re.M)
      path.write_text(re.sub(r'^graphics_wait="[^"]*"', 'graphics_wait="no"', text, flags=re.M))
      run("vm", "snapshot", config["name"] + "@clean")
    else:
      if not args.discard:
        fail("This deletes test VM state; repeat with --discard")
      if args.command == "reset":
        # Do not use -r: newer snapshots or dependent clones must be reviewed explicitly.
        run("vm", "rollback", config["name"] + "@clean")
      else:
        run("vm", "destroy", "-f", config["name"])
  elif args.command == "gpu-check":
    gpu_check(config)
  else:
    gpu(config, enable=args.command == "gpu-enable")


if __name__ == "__main__":
  try:
    main()
  except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError) as error:
    print(f"Error: {error}", file=sys.stderr)
    sys.exit(1)
