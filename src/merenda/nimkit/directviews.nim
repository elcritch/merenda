## Experimental direct declarative views: retained widgets with owned MVC bindings.
## `session.viewBody` composes actual views; the original `viewBody` overload
## remains available for comparing the ViewSpec prototype.
import ./directviews/[bindings, runtime, dsl, modelbindings]
export bindings, runtime, dsl, modelbindings
