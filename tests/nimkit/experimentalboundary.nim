## Verify the standard umbrella excludes experimental view DSL entry points.
import merenda/nimkit

static:
  doAssert not declared(viewBody)
  doAssert not declared(newDirectView)
  doAssert not declared(newDeclarativeView)
  doAssert declared(BindingScope)
  doAssert declared(CollectionSigil)
  doAssert declared(ActionTarget)

import ./fixtures/experimentalimports
