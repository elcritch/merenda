## Verify that the experimental entry points are available by explicit import.
import merenda/nimkit/directviews

static:
  doAssert declared(viewBody)
  doAssert declared(newDirectView)
