## Typed, weak-owner binding recipes for value descriptions.
import ../viewbindings
import ../view/views
export viewbindings

type ViewBinding* = object
  configure: proc(scope: BindingScope, view: View) {.closure.}
  ownsText*: bool

proc viewBinding*[R: Responder, C; V: View](
    owner: R,
    context: C,
    configure: proc(scope: BindingScope, owner: R, context: C, view: V) {.nimcall.},
    ownsText = false,
): ViewBinding =
  ## Values describe setup; mounting owns its subscriptions. Detached snapshots
  ## use the spec's ordinary property values and do not install this recipe.
  var receiver: BackRef[R]
  receiver.target = owner
  result.ownsText = ownsText
  result.configure = proc(scope: BindingScope, view: View) =
    let owner = receiver{}
    if not owner.isNil:
      if not (view of V):
        raise newException(ValueError, "binding recipe has an incompatible widget type")
      configure(scope, owner, context, V(view))

proc configureBindings*(binding: ViewBinding, scope: BindingScope, view: View) =
  scope.beginBindings()
  try:
    if not binding.configure.isNil:
      binding.configure(scope, view)
  finally:
    scope.endBindings()
