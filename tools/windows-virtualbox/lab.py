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
import secrets
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
  for key in ('base_folder', 'runtime_dir', 'xauthority'):
    if not Path(config[key]).is_absolute():
      fail(f'{key} must be absolute')
  for key in ('cpus', 'memory_mb', 'disk_size_mb', 'ssh_port', 'rdp_port', 'vnc_port'):
    if type(config[key]) is not int or config[key] < 1:
      fail(f'{key} must be a positive integer')
  for key in ('ssh_port', 'rdp_port', 'vnc_port'):
    if not 1024 <= config[key] <= 65535:
      fail(f'Invalid {key}')
  if len({config['ssh_port'], config['rdp_port'], config['vnc_port']}) != 3:
    fail('SSH, RDP and VNC ports must differ')
  if not config['iso_url'].startswith('https://'):
    fail('ISO URL must use HTTPS')
  if not re.fullmatch(r'[0-9a-fA-F]{64}', config['iso_sha256']):
    fail('ISO SHA-256 must be a 64-character hex digest')
  return config


def private_dir():
  LOCAL.mkdir(mode=0o700, exist_ok=True)
  LOCAL.chmod(0o700)


def create_password():
  return ''.join(secrets.choice('bcdfghjklmnpqrstvwxyz') + secrets.choice('aeiou')
                 for _ in range(5)).capitalize()


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


def download(config):
  iso = (HERE / config['iso_path']).resolve()
  iso.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
  partial = iso.with_suffix(iso.suffix + '.partial')
  source = iso if iso.exists() else partial
  if source == partial:
    run('curl', '--fail', '--location', '--retry', '3', '--proto', '=https',
        '--proto-redir', '=https', '--continue-at', '-', '--output', partial,
        config['iso_url'])
  with source.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
  if digest.lower() != config['iso_sha256'].lower():
    fail('Windows ISO SHA-256 does not match the configured Microsoft digest')
  if source == partial:
    partial.replace(iso)
  print('Verified Windows installation ISO:', iso)


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
  key.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
  if not key.exists():
    run('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'merenda-windows-lab', '-f', key)
  if not key.with_suffix('.pub').is_file():
    fail('SSH public key is missing: ' + str(key.with_suffix('.pub')))
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
  if folder.exists():
    fail('VM directory already exists; refusing to overwrite it')
  iso = (HERE / config['iso_path']).resolve()
  if not iso.is_file() or not (LOCAL / 'bootstrap.iso').is_file():
    fail('Run download and prepare first')
  with iso.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != config['iso_sha256'].lower():
      fail('Windows ISO SHA-256 does not match the configured Microsoft digest')
  additions = Path((LOCAL / 'additions-path').read_text())
  if not additions.is_file():
    fail('Run prepare to obtain matching Guest Additions')
  credentials = (HERE / config['credentials']).resolve()
  if credentials.exists():
    password = json.loads(credentials.read_text())['password']
  else:
    password = create_password()
    credentials.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(credentials, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
      json.dump({'username': 'Administrator', 'password': password}, stream, indent=2)
      stream.write('\n')
  run('VBoxManage', 'createvm', '--name', config['name'], '--ostype', 'Windows11_64',
      '--basefolder', config['base_folder'], '--register')
  folder.chmod(0o700)
  run('VBoxManage', 'setextradata', config['name'], OWNER_KEY, OWNER)
  run('VBoxManage', 'modifyvm', config['name'], '--memory', config['memory_mb'],
      '--cpus', config['cpus'], '--firmware', 'efi64', '--ioapic', 'on', '--tpm-type', '2.0',
      '--graphicscontroller', 'vboxsvga', '--vram', '256', '--accelerate-3d', 'off',
      '--boot1', 'dvd', '--boot2', 'disk', '--boot3', 'none', '--boot4', 'none',
      '--nic1', 'nat', '--nic-type1', '82540EM', '--cable-connected1', 'on',
      '--nat-pf1', f'ssh,tcp,127.0.0.1,{config["ssh_port"]},10.0.2.15,22',
      '--nat-pf1', f'rdp,tcp,127.0.0.1,{config["rdp_port"]},10.0.2.15,3389',
      '--vrde', 'on', '--vrde-extpack', 'VNC', '--vrde-address', '127.0.0.1',
      '--vrde-port', config['vnc_port'],
      '--audio-enabled', 'off', '--clipboard-mode', 'disabled', '--drag-and-drop', 'disabled')
  run('VBoxManage', 'modifynvram', config['name'], 'inituefivarstore')
  run('VBoxManage', 'modifynvram', config['name'], 'enrollmssignatures')
  run('VBoxManage', 'modifynvram', config['name'], 'enrollorclpk')
  run('VBoxManage', 'modifynvram', config['name'], 'secureboot', '--enable')
  run('VBoxManage', 'storagectl', config['name'], '--name', 'SATA', '--add', 'sata',
      '--controller', 'IntelAhci', '--portcount', '6', '--bootable', 'on')
  run('VBoxManage', 'createmedium', 'disk', '--filename', disk, '--size', config['disk_size_mb'],
      '--format', 'VDI', '--variant', 'Standard')
  for port, kind, medium in ((0, 'hdd', disk), (3, 'dvddrive', LOCAL / 'bootstrap.iso'),
                              (4, 'dvddrive', additions)):
    run('VBoxManage', 'storageattach', config['name'], '--storagectl', 'SATA',
        '--port', port, '--device', '0', '--type', kind, '--medium', medium)
  password_file = LOCAL / 'unattended-password'
  password_file_created = False
  try:
    fd = os.open(password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    password_file_created = True
    with os.fdopen(fd, 'w') as stream:
      stream.write(password)
    script = "Get-Volume|? FileSystemLabel -eq MERENDA_VBOX|% {& ($_.DriveLetter+':\\guest\\Bootstrap.ps1')}"
    command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "' + script + '"'
    run('VBoxManage', 'unattended', 'install', config['name'], '--iso=' + str(iso),
        '--user=Administrator', '--user-password-file=' + str(password_file),
        '--admin-password-file=' + str(password_file), '--locale=en_US', '--country=US',
        '--language=en-US', '--image-index=1', '--post-install-command=' + command,
        capture=True)
  finally:
    if password_file_created:
      password_file.unlink(missing_ok=True)
  # Unattended setup replaces/ejects existing optical media while creating its
  # installer ISO. Reattach the bootstrap and additions on separate ports.
  for port, medium in ((4, LOCAL / 'bootstrap.iso'), (5, additions)):
    run('VBoxManage', 'storageattach', config['name'], '--storagectl', 'SATA',
        '--port', port, '--device', '0', '--type', 'dvddrive', '--medium', medium)
  print('Created Windows 11 VM; run start --headless and inspect the VNC console')


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


def start(config, headless=False):
  stopped(config)
  exclusive()
  if headless:
    run('VBoxManage', 'startvm', config['name'], '--type', 'headless')
    return
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
  parser.add_argument('command', choices=('download', 'prepare', 'create', 'start', 'stop', 'status',
                      'baseline', 'reset', 'screenshot', 'secure', 'password', 'run', 'bootstrap', 'probe'))
  parser.add_argument('--discard', action='store_true')
  parser.add_argument('--headless', action='store_true')
  args = parser.parse_args()
  config = settings()
  host()
  private_dir()
  if args.command == 'download':
    download(config)
  elif args.command == 'prepare':
    prepare(config)
  elif args.command == 'create':
    create(config)
  elif args.command == 'start':
    start(config, headless=args.headless)
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
      values = managed(config)
      for port in range(1, 6):
        if values.get(f'SATA-{port}-0', 'none') not in ('none', 'emptydrive'):
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
