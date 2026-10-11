"""Host-side checks; never start guests or mutate the host's VM datasets."""

import json
from pathlib import Path
import shutil
import socket
import struct
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import lab


class LabSafetyTests(unittest.TestCase):
  def setUp(self):
    self.config = json.loads((lab.HERE / "config.example.json").read_text())

  def test_unmanaged_vm_cannot_be_reset_or_destroyed(self):
    with tempfile.TemporaryDirectory() as temporary:
      self.config["vm_dir"] = temporary
      directory = lab.vm_path(self.config)
      directory.mkdir()
      path = lab.vm_config(self.config)
      path.write_text('loader="uefi"\n')
      with patch.object(lab, "run") as command:
        with self.assertRaisesRegex(RuntimeError, "unmanaged"):
          lab.managed(self.config)
        command.assert_not_called()

  def test_restart_lock_prevents_mutation_between_bhyve_processes(self):
    with tempfile.TemporaryDirectory() as temporary:
      self.config["vm_dir"] = temporary
      directory = lab.vm_path(self.config)
      directory.mkdir()
      (directory / "run.lock").write_text("test-host\n")
      with self.assertRaisesRegex(RuntimeError, "stopped first"):
        lab.stopped(self.config)

  def test_reinstall_requires_explicit_discard(self):
    with tempfile.TemporaryDirectory() as temporary:
      self.config["vm_dir"] = temporary
      directory = lab.vm_path(self.config)
      directory.mkdir()
      (directory / "install-started").touch()
      with patch.object(lab, "managed"), patch.object(lab, "stopped"), patch.object(lab, "run") as command:
        with self.assertRaisesRegex(RuntimeError, "wipes the guest disk"):
          lab.start(self.config, install=True)
        command.assert_not_called()

  def test_gpu_enable_does_not_detach_a_host_driver(self):
    self.config["gpu_devices"] = ["199/0/0"]
    with patch.object(lab, "managed") as managed, patch.object(lab, "stopped"), patch.object(lab, "run") as command:
      command.return_value.stdout = "vgapci0@pci0:199:0:0: class=0x030000\n"
      with self.assertRaisesRegex(RuntimeError, "not attached to ppt"):
        lab.gpu(self.config, enable=True)
      managed.return_value.write_text.assert_not_called()
      self.assertFalse(any("devctl" in call.args for call in command.call_args_list))

  def test_reinstall_clears_old_setup_state_and_boot_order(self):
    with tempfile.TemporaryDirectory() as temporary:
      self.config["vm_dir"] = temporary
      directory = lab.vm_path(self.config)
      directory.mkdir()
      config_file = lab.vm_config(self.config)
      config_file.write_text(lab.template(self.config))
      disk = directory / "disk0.img"
      disk.write_bytes(b"previous Windows installation" * 100)
      size = disk.stat().st_size
      variables = directory / "uefi-vars.fd"
      variables.write_bytes(b"old Windows Boot Manager")
      iso = Path(temporary) / "windows.iso"
      answer = Path(temporary) / "answer.iso"
      iso.touch()
      answer.touch()
      with patch.object(lab, "managed", return_value=config_file), patch.object(lab, "stopped"), \
           patch.object(lab, "ISO", iso), patch.object(lab, "ANSWER", answer), patch.object(lab, "run") as command:
        lab.start(self.config, install=True, discard=True)
      self.assertEqual(disk.read_bytes(), b"\0" * size)
      self.assertFalse(variables.exists())
      command.assert_called_once_with("vm", "install", self.config["name"], iso)

  def test_answer_password_is_xml_escaped_and_targets_guest_disk_zero(self):
    password = 'Mw9!x<&"test'
    root = ET.fromstring(lab.answer_xml(self.config, password))
    ns = {"u": lab.NS}
    self.assertEqual(root.find(".//u:AdministratorPassword/u:Value", ns).text, password)
    self.assertEqual(root.find(".//u:InstallTo/u:DiskID", ns).text, "0")
    self.assertEqual(root.find(".//u:InstallTo/u:PartitionID", ns).text, "3")

  def test_specialize_commands_fit_windows_unattend_schema_limit(self):
    root = ET.fromstring(lab.answer_xml(self.config, "Mw9!test-password"))
    commands = root.findall(".//{*}RunSynchronousCommand/{*}Path")
    self.assertTrue(commands)
    for command in commands:
      self.assertLessEqual(len(command.text), 259)

  def test_vnc_status_probe_does_not_connect_and_release_boot_wait(self):
    with socket.socket() as listener:
      listener.bind(("127.0.0.1", 0))
      listener.listen()
      listener.settimeout(0.01)
      self.assertTrue(lab.port_bound(listener.getsockname()[1]))
      with self.assertRaises(TimeoutError):
        listener.accept()

  @unittest.skipUnless(shutil.which("makefs") and shutil.which("ssh-keygen"), "requires FreeBSD media tools")
  def test_windows_can_find_bootstrap_files_without_rock_ridge(self):
    # Windows uses the primary ISO9660 names, which can differ from Unix names.
    # Inspect the generated media without using its Rock Ridge extensions.
    with tempfile.TemporaryDirectory() as temporary:
      local = Path(temporary) / "private"
      answer = local / "answer.iso"
      with patch.object(lab, "LOCAL", local), patch.object(lab, "ANSWER", answer):
        lab.prepare(self.config)
      self.assertEqual((local / "credentials.json").stat().st_mode & 0o777, 0o600)
      with answer.open("rb") as stream:
        stream.seek(16 * 2048)
        descriptor = stream.read(2048)
        self.assertEqual(descriptor[40:72].decode().strip(), "MERENDA_SETUP")

        def entries(record):
          extent, = struct.unpack_from("<I", record, 2)
          size, = struct.unpack_from("<I", record, 10)
          stream.seek(extent * 2048)
          data = stream.read(size)
          found = {}
          offset = 0
          while offset < len(data):
            length = data[offset]
            if not length:
              offset = (offset // 2048 + 1) * 2048
              continue
            item = data[offset:offset + length]
            found[item[33:33 + item[32]]] = item
            offset += length
          return found

        root = entries(descriptor[156:190])
        self.assertIn(b"AUTOUNATTEND.XML;1", root)
        self.assertIn(b"NETWORK.JSON;1", root)
        guest = entries(root[b"GUEST"])
        for name in ("Bootstrap.ps1", "PrepareGuest.ps1", "EnableSsh.ps1", "VerifyGpu.ps1", "HostKey.pub"):
          self.assertIn((name.upper() + ";1").encode(), guest)


if __name__ == "__main__":
  unittest.main()
