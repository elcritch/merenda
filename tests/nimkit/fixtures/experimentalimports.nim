## Verify that the experimental entry points are available by explicit import.
import merenda/nimkit/declarative
import merenda/nimkit/directviews

static:
  doAssert declared(viewBody)
  doAssert declared(newDirectView)
  doAssert declared(newDeclarativeView)
