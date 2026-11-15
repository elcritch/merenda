import importlib.util
import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('virtualbox_lab', Path(__file__).with_name('lab.py'))
lab = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lab)


class SafetyTests(unittest.TestCase):
  def setUp(self):
    self.config = lab.settings()
    self.values = {
      'VMState': 'poweroff',
      'CfgFile': str(Path(self.config['base_folder']) / self.config['name'] /
                     (self.config['name'] + '.vbox')),
    }

  def test_generated_password_has_ten_ascii_letters(self):
    for _ in range(20):
      self.assertRegex(lab.create_password(), r'^[A-Za-z]{10}$')

  def test_loaded_bhyve_blocks_virtualbox_even_without_running_guests(self):
    with patch.object(lab, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
      with self.assertRaisesRegex(RuntimeError, 'vmm is loaded'):
        lab.exclusive()
      self.assertEqual(run.call_count, 1)

  def test_unmanaged_vm_cannot_be_stopped(self):
    with patch.object(lab, 'info', return_value=self.values), patch.object(
        lab, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='No value set!\n')) as run:
      with self.assertRaisesRegex(RuntimeError, 'unmanaged'):
        lab.stop(self.config)
      self.assertEqual(run.call_count, 1)

  def test_matching_name_and_marker_do_not_authorize_different_vm_path(self):
    values = self.values | {'CfgFile': '/somewhere-else/important.vbox'}
    with patch.object(lab, 'info', return_value=values), patch.object(
        lab, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='Value: ' + lab.OWNER)):
      with self.assertRaisesRegex(RuntimeError, 'configuration path'):
        lab.managed(self.config)

  def test_snapshot_restore_requires_discard_and_stopped_guest(self):
    with patch.object(lab, 'host'), patch.object(lab, 'private_dir'), patch.object(
        lab, 'managed', return_value=self.values), patch.object(lab, 'run') as run, patch(
        'sys.argv', ['lab.py', 'reset']):
      with self.assertRaisesRegex(RuntimeError, 'discards guest changes'):
        lab.main()
      run.assert_not_called()
    with patch.object(lab, 'managed', return_value=self.values | {'VMState': 'running'}):
      with self.assertRaisesRegex(RuntimeError, 'Shut down'):
        lab.stopped(self.config)

  def test_existing_vm_is_not_reconfigured_by_create(self):
    with patch.object(lab, 'info', return_value=self.values), patch.object(lab, 'run') as run:
      with self.assertRaisesRegex(RuntimeError, 'already exists'):
        lab.create(self.config)
      run.assert_not_called()

  def test_download_checks_cached_iso_against_trusted_digest(self):
    with tempfile.TemporaryDirectory() as temporary:
      iso = Path(temporary) / 'windows.iso'
      iso.write_bytes(b'Windows test image')
      self.config['iso_path'] = str(iso)
      self.config['iso_sha256'] = hashlib.sha256(iso.read_bytes()).hexdigest()
      with patch.object(lab, 'run') as run:
        lab.download(self.config)
        run.assert_not_called()
        iso.write_bytes(b'corrupted image')
        with self.assertRaisesRegex(RuntimeError, 'SHA-256'):
          lab.download(self.config)
        run.assert_not_called()

  def test_create_rejects_wrong_iso_before_creating_a_vm(self):
    with tempfile.TemporaryDirectory() as temporary:
      directory = Path(temporary)
      iso = directory / 'windows.iso'
      iso.write_bytes(b'incorrect image')
      (directory / 'bootstrap.iso').touch()
      self.config['base_folder'] = temporary
      self.config['iso_path'] = str(iso)
      self.config['iso_sha256'] = '0' * 64
      with patch.object(lab, 'LOCAL', directory), patch.object(lab, 'info', return_value={}), \
           patch.object(lab, 'run') as run:
        with self.assertRaisesRegex(RuntimeError, 'SHA-256'):
          lab.create(self.config)
        run.assert_not_called()


if __name__ == '__main__':
  unittest.main()
