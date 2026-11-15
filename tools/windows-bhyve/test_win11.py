import unittest
import xml.etree.ElementTree as ET

import win11


class Windows11Setup(unittest.TestCase):
  def test_config_and_unattended_image(self):
    config = win11.settings()
    self.assertEqual(config['name'], 'merenda-win11')
    self.assertEqual(config['image_index'], 1)
    self.assertEqual(config['guest_ip'], '172.31.0.21')
    root = ET.fromstring(win11.answer_xml(config, 'abcdefghij'))
    ns = {'u': win11.lab.NS}
    self.assertEqual(root.find('.//u:AdministratorPassword/u:Value', ns).text, 'abcdefghij')
    self.assertEqual(root.find('.//u:LocalAccount/u:Name', ns).text, 'Merenda')
    self.assertEqual(root.find('.//u:LocalAccount/u:Group', ns).text, 'Administrators')
    self.assertEqual(root.find('.//u:LocalAccount/u:Password/u:Value', ns).text, 'abcdefghij')
    self.assertEqual(root.find('.//u:SkipUserOOBE', ns).text, 'true')
    self.assertEqual(root.find('.//u:OSImage/u:InstallFrom/u:MetaData/u:Value', ns).text, '1')

  def test_tpm_attached_to_separate_vm(self):
    config = win11.settings()
    text = win11.template(config)
    self.assertIn('prestart="start-tpm.sh"', text)
    self.assertIn('-l tpm,swtpm,/vm/merenda-win11/tpm/swtpm.sock', text)
    self.assertNotIn('passthru0=', text)


if __name__ == '__main__':
  unittest.main()
