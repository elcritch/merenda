# NimKit Resources

NimKit resources describe UI structure and assets as plain Nim values. Decoding a
resource bundle does not construct views, controllers, windows, menus, selectors,
images, or backend handles. Construction happens only through
`instantiateResources` after validation succeeds.

The format is NimKit-native. It is not a nib or storyboard compatibility format.
Future Cocoa, GNUstep, or other backend adapters can translate their native formats
into `ResourceBundle` records without exposing platform resource types in the core
API.

## Loading Flow

```nim
import merenda/nimkit
import merenda/nimkit/resources

let loaded = loadResourceBundle("ui/main.cbor")
if not loaded.loaded:
  for diagnostic in loaded.diagnostics:
    echo diagnostic.path, ": ", diagnostic.message
  quit 1

let context = initResourceInstantiationContext(
  locale = "en-GB",
  assetBasePath = "ui",
)
let construction = loaded.bundle.instantiateResources(context)
if not construction.instantiated:
  for diagnostic in construction.diagnostics:
    echo diagnostic.code, ": ", diagnostic.message
  quit 1

let window = construction.instance.window(resourceId("main.window"))
```

`decodeResourceBundle` and `loadResourceBundle` return diagnostics for malformed
CBOR and incompatible envelopes. `validateResources` checks identifiers, references,
registered kinds and properties, selectors, localization fallback, key bindings,
theme fragments, and image assets. Required runtime lookups raise
`ResourceLookupError`; `findView`, `findWindow`, `findMenu`, and similar helpers
provide optional nil-returning lookup.

## Stable CBOR Envelope

The top-level record contains:

- `format`: `org.merenda.nimkit.resources`
- `version`: a major and minor format version
- `namespace`: an application-defined bundle namespace
- ordered collections for views, controllers, windows, menus, commands, images,
  localizations, key bindings, and theme fragments

`encodeResourceBundle` uses cborious object maps, string enum names, and canonical
CBOR. Map fields allow additive minor-version changes and unknown fields are skipped
by the decoder. A major-version mismatch is an error; a newer minor version produces
a warning so callers can choose their own acceptance policy.

Wire records use sequences rather than maps for named collections. This preserves
source order and lets validation report duplicate identifiers and keys instead of
silently replacing them.

Geometry and styling fields use NimKit's native `Rect`, `Size`, `EdgeInsets`, and
`Color` value types directly. They do not introduce resource-specific wrappers or
conversion APIs.

## Construction Registry

`initNimKitResourceRegistry` provides built-in factories for views, controls,
buttons, checkboxes, radio buttons, text fields, labels, image views, stack views,
and view controllers. It also registers common view/control properties, standard
action selectors, and standard chrome names.

Applications can extend a registry before validation and construction:

```nim
type InspectorView = ref object of View
  xShowsDetails: bool

protocol InspectorViewProtocol {.selectorScope: protocol, setterStyle: nim.} from InspectorView:
  property showsDetails -> bool {.field: xShowsDetails.}

proc newInspectorView(frame: Rect): InspectorView =
  result = InspectorView()
  initViewFields(result, frame)
  discard result.withProto()

var registry = initNimKitResourceRegistry()
registry.registerActionSelector("showInspector")
registry.registerViewKind(
  "inspectorView",
  proc(frame: Rect): View = newInspectorView(frame),
)
registry.registerViewProtocolProperties(
  "inspectorView", InspectorViewProtocol
)

let construction = bundle.instantiateResources(registry)
```

Factories allocate identities during the first construction pass. Properties and
view/controller relationships are applied during the second pass, so references do
not depend on declaration order. `registerViewProtocolProperties` discovers matching
Sigils property getter/setter requirements and binds resource values to the generated
Nim-style setter selectors. The built-in registry supplies decoders for primitive,
geometry, color, image, and common enum property types. Applications can add another
typed decoder with `registerResourceValueType`; `registerViewProperty` remains an
escape hatch for properties that need custom conversion. Because dispatch still uses
the property protocol, normal layout, drawing, responder, accessibility, and
native-window side effects are preserved.

Construction returns windows without showing them or adding them to an application.
Image resources remain local to the `ResourceInstance`; they are not published in the
global named-image registry.

## Resource Limits

`ResourceLoadLimits` controls the maximum encoded bytes, node count, tree depth, and
embedded image bytes. File image paths are resolved relative to `assetBasePath`.
Embedded images are stored as CBOR byte strings.

Diagnostics use stable string codes and include severity, structural path, resource
identifier, and related identifier. This makes them suitable for build tools,
inspectors, and future resource compilers as well as runtime logging.
