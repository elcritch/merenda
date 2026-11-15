#!/usr/bin/env python3
"""Windows 11 evaluation guest using the existing vm-bhyve lab commands."""
import json
import os
from pathlib import Path
import re
import shutil
import sys
import xml.etree.ElementTree as ET

import lab

original_answer_xml = lab.answer_xml
original_template = lab.template
original_create = lab.create
original_prepare = lab.prepare


def settings():
  config = json.loads((lab.HERE / 'config.example.json').read_text())
  config.update(name='merenda-win11', guest_ip='172.31.0.21', computer_name='MERENDA-WIN11',
                vnc_port=5902, image_index=1, gpu_devices=['199/0/0', '199/0/1'],
                iso_url='https://go.microsoft.com/fwlink/?LinkId=2382600&clcid=0x409&culture=en-us&country=us',
                iso_sha256='bc3f24086ebadc94489066b5ad78089e2cf5c3491e90e790bb81a2b199c10e38')
  return config


def answer_xml(config, password):
  root = ET.fromstring(original_answer_xml(config, password))
  ns = {'u': lab.NS}
  shell = root.find("u:settings[@pass='oobeSystem']/u:component[@name='Microsoft-Windows-Shell-Setup']", ns)
  accounts = shell.find('u:UserAccounts', ns)
  local = lab.add(lab.add(accounts, 'LocalAccounts'), 'LocalAccount',
                  **{f'{{{lab.WCM}}}action': 'add'})
  local_password = lab.add(local, 'Password')
  lab.add(local_password, 'Value', password)
  lab.add(local_password, 'PlainText', 'true')
  lab.add(local, 'Description', 'Merenda test administrator')
  lab.add(local, 'DisplayName', 'Merenda')
  lab.add(local, 'Group', 'Administrators')
  lab.add(local, 'Name', 'Merenda')
  oobe = shell.find('u:OOBE', ns)
  lab.add(oobe, 'SkipUserOOBE', 'true')
  lab.add(oobe, 'SkipMachineOOBE', 'true')
  ET.indent(root, space='  ')
  return ET.tostring(root, encoding='utf-8', xml_declaration=True)


def template(config):
  socket = lab.vm_path(config) / 'tpm' / 'swtpm.sock'
  return original_template(config) + f'prestart="start-tpm.sh"\nbhyve_options="-l tpm,swtpm,{socket}"\n'


def prepare(config):
  lab.private_dir()
  secret = lab.LOCAL / 'credentials.json'
  if not secret.exists():
    previous = lab.HERE.parent / 'windows-virtualbox' / '.local' / 'windows11-credentials.json'
    if not previous.exists():
      lab.fail(f'Previous Windows 11 credentials not found: {previous}')
    credentials = json.loads(previous.read_text())
    if not re.fullmatch(r'[A-Za-z]{10}', credentials.get('password', '')):
      lab.fail('Previous Windows 11 password is not the expected 10 letters')
    fd = os.open(secret, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
      json.dump({'username': 'Merenda', 'password': credentials['password']}, stream)
      stream.write('\n')
  else:
    credentials = json.loads(secret.read_text())
    credentials['username'] = 'Merenda'
    secret.write_text(json.dumps(credentials, indent=2) + '\n')
    secret.chmod(0o600)
  original_prepare(config, skip_missing_ssh=True)


def create(config):
  if not shutil.which('swtpm') or not shutil.which('swtpm_ioctl'):
    lab.fail('Install the swtpm package before creating the Windows 11 VM')
  original_create(config)
  script = lab.vm_path(config) / 'start-tpm.sh'
  shutil.copyfile(lab.HERE / 'start-tpm.sh', script)
  script.chmod(0o700)


if __name__ == '__main__':
  try:
    lab.LOCAL = lab.HERE / '.local' / 'windows11'
    lab.ISO = lab.HERE / '.local' / 'windows-11-enterprise-26h2-x64-en-us.iso'
    lab.ANSWER = lab.LOCAL / 'answer.iso'
    lab.settings = settings
    lab.answer_xml = answer_xml
    lab.template = template
    lab.prepare = prepare
    lab.create = create
    lab.main()
  except (RuntimeError, ValueError, OSError, lab.subprocess.CalledProcessError) as error:
    print(f'Error: {error}', file=sys.stderr)
    sys.exit(1)
