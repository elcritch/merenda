## Experimental direct declarative views: retained widgets with owned MVC bindings.
## This API may change incompatibly and has no stability promise.
## `view.viewBody` composes actual views and owns component lifetimes; the original `viewBody` overload
## remains available for comparing the ViewSpec prototype.
import ./directviews/[bindings, runtime, dsl, modelbindings]
export bindings, runtime, dsl, modelbindings
