/* Minimal old HarfBuzz for testing runtime version diagnostics. */
int hb_version_atleast(unsigned int major, unsigned int minor, unsigned int micro) {
  (void)major;
  (void)minor;
  (void)micro;
  return 0;
}

const char *hb_version_string(void) {
  return "6.0.0";
}
