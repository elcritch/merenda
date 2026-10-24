#!/usr/bin/env python3
"""Manage the disposable VirtualBox Windows guest as the desktop user."""

import argparse
import grp
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import socket
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
LOCAL = HERE / '.local'
OWNER_KEY = 'MerendaLab/Owner'
OWNER = str(HERE)


def fail(message):
  raise RuntimeError(message)


def run(*args, capture=False, check=True, env=None):
  return subprocess.run([str(a) for a in args], check=check, text=True, env=env,
                        stdout=subprocess.PIPE if capture else None,
                        stderr=subprocess.PIPE if capture else None)


def settings():
  config = json.loads((HERE / 'config.example.json').read_text())
  overrides = HERE / 'config.json'
  if overrides.exists():
    custom = json.loads(overrides.read_text())
    if custom.keys() - config.keys():
      fail('Unknown configuration keys')
    config.update(custom)
  if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,39}', config['name']):
    fail('Invalid VM name')
  for key in ('base_folder', 'source_disk', 'runtime_dir', 'xauthority'):
    if not Path(config[key]).is_absolute():
      fail(f'{key} must be absolute')
  for key in ('cpus', 'memory_mb', 'ssh_port', 'rdp_port'):
    if type(config[key]) is not int or config[key] < 1:
      fail(f'{key} must be a positive integer')
  for key in ('ssh_port', 'rdp_port'):
    if not 1024 <= config[key] <= 65535:
      fail(f'Invalid {key}')
  if config['ssh_port'] == config['rdp_port']:
    fail('SSH and RDP ports must differ')
  return config


def private_dir():
  LOCAL.mkdir(mode=0o700, exist_ok=True)
  LOCAL.chmod(0o700)


def host():
  if platform.system() != 'FreeBSD' or os.geteuid() == 0:
    fail('Run as the FreeBSD desktop user, without sudo')
  if not shutil.which('VBoxManage'):
    fail('Install virtualbox-ose-72 and its matching kernel module first')


def info(config):
  result = run('VBoxManage', 'showvminfo', config['name'], '--machinereadable', capture=True, check=False)
  if result.returncode:
    return {}
  values = {}
  for line in result.stdout.splitlines():
    key, separator, value = line.partition('=')
    if separator:
      values[key.strip('"')] = value.strip('"')
  return values


def managed(config):
  values = info(config)
  marker = run('VBoxManage', 'getextradata', config['name'], OWNER_KEY, capture=True).stdout.strip()
  if not values or marker != 'Value: ' + OWNER:
    fail('Refusing to mutate an unmanaged VM')
  expected = Path(config['base_folder']) / config['name'] / (config['name'] + '.vbox')
  if Path(values['CfgFile']).resolve() != expected.resolve():
    fail('Unexpected VirtualBox configuration path')
  return values


def stopped(config):
  if managed(config)['VMState'] not in ('poweroff', 'aborted'):
    fail('Shut down the VM first; saved sessions must be handled explicitly')


def exclusive():
  # bhyve enables SVM when vmm loads, even when no guest is running.
  if run('kldstat', '-q', '-m', 'vmm', capture=True, check=False).returncode == 0:
    fail('bhyve vmm is loaded. Stop bhyve guests and unload vmm before starting VirtualBox; see README.md')
  if not Path('/dev/vboxdrv').exists():
    fail('Load vboxdrv after unloading vmm; see README.md')
  if grp.getgrnam('vboxusers').gr_gid not in os.getgroups():
    fail('Start a fresh login to pick up vboxusers membership, or run through sudo -u "$USER"')


def prepare(config):
  private_dir()
  version = run('VBoxManage', '--version', capture=True).stdout.strip().split('r')[0]
  if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
    fail('Unexpected VirtualBox version')
  iso = LOCAL / f'VBoxGuestAdditions_{version}.iso'
  url = f'https://download.virtualbox.org/virtualbox/{version}/'
  if not iso.exists():
    partial = iso.with_suffix('.iso.partial')
    run('curl', '--fail', '--location', '--retry', '2', '--proto', '=https',
        '--proto-redir', '=https', '--output', partial, url + iso.name)
    partial.replace(iso)
  sums = run('curl', '--fail', '--silent', '--show-error', '--location', '--proto', '=https',
             '--proto-redir', '=https', url + 'SHA256SUMS', capture=True).stdout
  expected = next((line.split()[0] for line in sums.splitlines()
                   if line.split()[-1].lstrip('*') == iso.name), None)
  with iso.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
  if digest != expected:
    fail('Guest Additions SHA-256 does not match Oracle SHA256SUMS')
  (LOCAL / 'guest-additions.sha256').write_text(digest + '  ' + iso.name + '\n')
  media = LOCAL / 'bootstrap'
  if media.exists():
    shutil.rmtree(media)
  media.mkdir()
  shutil.copytree(HERE / 'guest', media / 'guest')
  common = HERE.parent / 'windows-bhyve' / 'guest'
  for name in ('PrepareGuest.ps1', 'EnableSsh.ps1'):
    shutil.copyfile(common / name, media / 'guest' / name)
  key = (HERE / config['ssh_key']).resolve()
  shutil.copyfile(key.with_suffix('.pub'), media / 'guest' / 'HostKey.pub')
  (media / 'network.json').write_text(json.dumps({
    'ip': '10.0.2.15', 'prefix': 24, 'gateway': '10.0.2.2', 'dns': ['10.0.2.3'],
  }))
  partial = LOCAL / 'bootstrap.iso.partial'
  run('makefs', '-t', 'cd9660', '-o', 'isolevel=2', '-o', 'rockridge',
      '-o', 'label=MERENDA_VBOX', partial, media)
  partial.replace(LOCAL / 'bootstrap.iso')
  (LOCAL / 'additions-path').write_text(str(iso))
  print('Bootstrap media and matching, checksum-verified Guest Additions ready')


def create(config):
  if info(config):
    fail('VM already exists')
  folder = Path(config['base_folder']) / config['name']
  disk = folder / 'windows.vdi'
  if not disk.is_file() or disk.is_symlink():
    fail('Convert the stopped bhyve baseline to windows.vdi first; see README.md')
  additions = Path((LOCAL / 'additions-path').read_text())
  run('VBoxManage', 'createvm', '--name', config['name'], '--ostype', 'Windows2025_64',
      '--basefolder', config['base_folder'], '--register')
  run('VBoxManage', 'setextradata', config['name'], OWNER_KEY, OWNER)
  run('VBoxManage', 'modifyvm', config['name'], '--memory', config['memory_mb'],
      '--cpus', config['cpus'], '--firmware', 'efi64', '--ioapic', 'on',
      '--graphicscontroller', 'vboxsvga', '--vram', '256', '--accelerate-3d', 'on',
      '--boot1', 'disk', '--boot2', 'dvd', '--boot3', 'none', '--boot4', 'none',
      '--nic1', 'nat', '--nic-type1', '82540EM', '--cable-connected1', 'on',
      '--nat-pf1', f'ssh,tcp,127.0.0.1,{config["ssh_port"]},10.0.2.15,22',
      '--nat-pf1', f'rdp,tcp,127.0.0.1,{config["rdp_port"]},10.0.2.15,3389',
      '--audio-enabled', 'off', '--clipboard-mode', 'disabled', '--drag-and-drop', 'disabled')
  run('VBoxManage', 'storagectl', config['name'], '--name', 'SATA', '--add', 'sata',
      '--controller', 'IntelAhci', '--portcount', '4', '--bootable', 'on')
  for port, kind, medium in ((0, 'hdd', disk), (1, 'dvddrive', LOCAL / 'bootstrap.iso'),
                              (2, 'dvddrive', additions)):
    run('VBoxManage', 'storageattach', config['name'], '--storagectl', 'SATA',
        '--port', port, '--device', '0', '--type', kind, '--medium', medium)
  print('Created ' + config['name'] + ' with VBoxSVGA, 256 MiB VRAM, and 3D enabled')


def stop(config):
  if managed(config)['VMState'] == 'poweroff':
    return
  run('VBoxManage', 'controlvm', config['name'], 'acpipowerbutton')
  deadline = time.monotonic() + 60
  while time.monotonic() < deadline:
    if info(config).get('VMState') == 'poweroff':
      return
    time.sleep(0.25)
  fail('ACPI shutdown timed out; inspect the guest console')


def start(config):
  stopped(config)
  exclusive()
  env = os.environ | {'DISPLAY': config['display'], 'XAUTHORITY': config['xauthority'],
                      'XDG_RUNTIME_DIR': config['runtime_dir']}
  # VBoxManage delegates GUI launch to VBoxSVC, whose environment can be stale
  # when it was first started from an SSH/agent session. Start the frontend
  # directly with the desktop environment instead.
  with (LOCAL / 'frontend.log').open('a') as log:
    process = subprocess.Popen(['VirtualBoxVM', '--startvm', config['name']],
                               env=env, stdout=log, stderr=log, start_new_session=True)
  deadline = time.monotonic() + 60
  while time.monotonic() < deadline:
    if info(config).get('VMState') == 'running':
      print('VirtualBox is running; inspect the console for Windows readiness')
      return
    if process.poll() is not None:
      fail('VirtualBox frontend exited; inspect .local/frontend.log and Logs/VBox.log')
    time.sleep(0.25)
  fail('VirtualBox startup timed out; inspect the console and logs')


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('command', choices=('prepare', 'create', 'start', 'stop', 'status',
                      'baseline', 'reset', 'screenshot', 'secure', 'password', 'run', 'bootstrap', 'probe'))
  parser.add_argument('--discard', action='store_true')
  args = parser.parse_args()
  config = settings()
  host()
  private_dir()
  if args.command == 'prepare':
    prepare(config)
  elif args.command == 'create':
    create(config)
  elif args.command == 'start':
    start(config)
  elif args.command == 'stop':
    stop(config)
  elif args.command == 'status':
    values = managed(config)
    for key in ('name', 'VMState', 'memory', 'cpus', 'graphicscontroller', 'vram', 'accelerate3d'):
      print(key + ': ' + values.get(key, '?'))
    for label, port in (('SSH', config['ssh_port']), ('RDP', config['rdp_port'])):
      try:
        with socket.create_connection(('127.0.0.1', port), timeout=1):
          print(f'{label}: listening on 127.0.0.1:{port} (guest readiness requires authentication)')
      except OSError:
        print(label + ': not listening')
  elif args.command in ('baseline', 'reset'):
    stopped(config)
    if args.command == 'reset':
      if not args.discard:
        fail('Reset discards guest changes; repeat with --discard')
      run('VBoxManage', 'snapshot', config['name'], 'restore', 'clean')
    else:
      for port in (1, 2):
        run('VBoxManage', 'storageattach', config['name'], '--storagectl', 'SATA',
            '--port', port, '--device', '0', '--type', 'dvddrive', '--medium', 'emptydrive')
      run('VBoxManage', 'snapshot', config['name'], 'take', 'clean',
          '--description', 'Stopped Windows evaluation with Guest Additions; GPU support requires separate verification')
  else:
    if managed(config)['VMState'] != 'running':
      fail('VM must be running')
    control = ('VBoxManage', 'controlvm', config['name'])
    if args.command == 'screenshot':
      run(*control, 'screenshotpng', LOCAL / 'screen.png')
      print(LOCAL / 'screen.png')
    elif args.command == 'secure':
      run(*control, 'keyboardputscancode', '1d', '38', 'e0', '53', 'e0', 'd3', 'b8', '9d')
    elif args.command == 'run':
      run(*control, 'keyboardputscancode', 'e0', '5b', '13', '93', 'e0', 'db')
    elif args.command == 'password':
      # Read through a private file so the password never appears in argv or logs.
      credentials = json.loads((HERE / config['credentials']).read_text())
      password_file = LOCAL / 'password-input'
      try:
        password_file.touch(mode=0o600)
        password_file.write_text(credentials['password'])
        run(*control, 'keyboardputfile', password_file)
        run(*control, 'keyboardputscancode', '1c', '9c')
      finally:
        password_file.unlink(missing_ok=True)
    else:
      if args.command == 'bootstrap':
        script = "Get-Volume|? FileSystemLabel -eq MERENDA_VBOX|% {& ($_.DriveLetter+':\\guest\\Bootstrap.ps1')}"
      else:
        script = r'& C:\MerendaLab\ProbeOpenGl.ps1'
      # Open Run with the separate `run` command and observe the dialog before
      # typing. Sending text immediately after Win+R loses initial characters.
      run(*control, 'keyboardputscancode', '1d', '1e', '9e', '9d')  # Ctrl+A
      command_file = LOCAL / 'console-command'
      command_file.write_text('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -Command "' + script + '"')
      run(*control, 'keyboardputfile', command_file)
      run(*control, 'keyboardputscancode', '1c', '9c')


if __name__ == '__main__':
  try:
    main()
  except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError) as error:
    print('Error: ' + str(error), file=sys.stderr)
    sys.exit(1)
