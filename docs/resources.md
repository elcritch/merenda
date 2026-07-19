# NimKit Resources

NimKit resources describe UI structure and assets as plain Nim values. Decoding a
resource bundle does not construct views, controllers, windows, menus, selectors,
images, layout constraints, or backend handles. Construction happens only through
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
theme fragments, layout endpoints and ownership, and image assets. Required runtime
lookups raise `ResourceLookupError`; `findView`, `findWindow`, `findMenu`, and
similar helpers provide non-raising optional lookup.

## Stable CBOR Envelope

The top-level record contains:

- `format`: `org.merenda.nimkit.resources`
- `version`: a major and minor format version
- `namespace`: an application-defined bundle namespace
- ordered collections for views, layout guides, layout constraints, controllers,
  windows, menus, commands, images, localizations, key bindings, and theme fragments

`encodeResourceBundle` uses cborious object maps, string enum names, and canonical
CBOR. Map fields allow additive minor-version changes and unknown fields are skipped
by the decoder. A major-version mismatch is an error; a newer minor version produces
a warning so callers can choose their own acceptance policy.

Format 1.1 adds layout guides/constraints and stable localization catalog
identifiers. Version 1.0 bundles remain readable; their catalogs may omit an
identifier and therefore do not appear as selectable document hierarchy nodes.

Wire records use sequences rather than maps for named collections. This preserves
source order and lets validation report duplicate identifiers and keys instead of
silently replacing them.

Geometry and styling fields use NimKit's native `Rect`, `Size`, `EdgeInsets`, and
`Color` value types directly. They do not introduce resource-specific wrappers or
conversion APIs.

## Construction Registry

`initNimKitResourceRegistry` provides built-in factories for views, controls,
buttons, checkboxes, radio buttons, text fields, labels, image views, stack views,
switches, progress indicators, boxes, split views, and view controllers. It also
registers common view/control properties, standard action selectors, and standard
chrome names.

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

## Layout Resources

Layout guides and constraints are plain, backend-neutral records. Both own stable
identifiers; constraints refer to views or guides with `ResourceLayoutItemReference`
and use resource-specific anchor and relation enums. An explicit owning view keeps
constraint storage deterministic.

```nim
bundle.layoutGuides = @[
  initResourceLayoutGuide(
    resourceId("root.content"), resourceId("root"), insets(16.0)
  )
]
bundle.layoutConstraints = @[
  initResourceLayoutConstraint(
    resourceId("button.leading"),
    resourceId("root"),
    resourceLayoutItem(resourceId("button")),
    rlaLeading,
    resourceLayoutItem(resourceId("root.content"), rliGuide),
    rlaLeading,
  )
]
```

Validation checks endpoint kinds, anchor compatibility, owner containment,
multipliers, constants, priorities, and guide insets. Construction lowers guide
anchors to their owning views with the correct inset-adjusted constant and exposes
`layoutGuide`/`findLayoutGuide` and `layoutConstraint`/`findLayoutConstraint` lookup.
Active constraints are installed into the existing NimKit solver; inactive records
remain available for inspection.

## Editable Resource Documents

`ResourceDocument` adds editor identity and mutation history around a value-only
`ResourceBundle`. It owns the current draft, the most recent valid bundle, revision
numbers, diagnostics, selected resource identifiers, and an `UndoManager`. The
serialized records remain plain values, and document lookup returns values or
read-only borrows rather than mutable access into nested sequences.

```nim
let document = newResourceDocument(bundle)
let inserted = document.insertView(
  initViewNodeResource(resourceId("status"), kind = "label"),
  parentId = resourceId("root"),
)

if inserted.applied:
  echo document.revision
else:
  echo inserted.message

discard document.undoManager.performUndo()
```

Typed view-tree insert, remove, move, replace, and property operations update
identifier indexes, stable `ResourceNodePath` values, validation diagnostics,
revisions, and undo registration as one transaction. Structurally ambiguous
operations such as duplicate identifiers, unavailable parents, invalid indexes, and
hierarchy cycles are rejected with `ResourceEditError`. Semantically invalid property
edits remain in the current draft with diagnostics while `lastValidBundle` continues
to provide a safe preview source.

Use `findNodePath`/`nodePath` and the typed optional/required lookup pairs for views,
layout records, controllers, windows, menus, commands, images, localization, key
bindings, and themes.
`diagnosticPath` resolves a stable identifier path to its current index-addressed
validation location. Iteration yields value copies, and deleting a subtree prunes
unavailable selection identifiers automatically.

The registry exposes deterministic, read-only property schema through `viewKinds`
and `viewProperties`. Required and optional descriptor lookup are available through
`viewKindDescriptor`/`findViewKindDescriptor` and
`viewPropertyDescriptor`/`findViewPropertyDescriptor`. Property descriptors include
the declaring kind, inheritance and alias information, getter and setter selector
names, Nim type name, accepted `ResourceValueKind` values, and editability. UI-only
labels, grouping, ranges, and specialized editor hints intentionally remain outside
the core registry contract.

## Interactive Resource Editor

`ResourceEditorDocument` combines the value-only resource draft with NimKit's
application `Document` behavior. `showWindows` creates the first builder window:
the resource hierarchy and palette are on the left, the valid preview is in the
center, and the generic property inspector and path-addressed diagnostics are on
the right.

```nim
let
  document = newResourceEditorDocument(bundle, fileUrl = "ui.cbor")
  app = sharedApplication()

discard document.resources().selectResource(resourceId("root"))
discard document.showWindows(app)
app.run()
```

The 13-kind palette and editable view inspector are driven by the same registry used
for runtime construction. Selecting a non-view hierarchy item shows path-addressed,
read-only details for layout, controller/window ownership, target/action connections,
menus, commands, images, localization, key bindings, and themes.

The view inspector parses values according to each `ResourcePropertyDescriptor`. If
typed input cannot be parsed, it is committed as a string value so the exact draft
text remains visible and validation can diagnose the mismatch. Valid revisions are
reconciled while preserving compatible view and controller identities; layout
constraints are rebuilt against the resulting view map. Invalid drafts never replace
the last working preview. Hierarchy clicks and preview clicks both update selection by
`ResourceId`, and preview selection uses `installViewSelection` and
`installSelectionRing` rather than changing serialized records or preview state.

The editor installs `DocumentFileProtocol` for canonical CBOR reads and writes and
shares the resource draft's `UndoManager` with the application document. A save or
revert updates the manager's clean state and the normal document edited indicator.

Run the complete vertical slice with:

```sh
nim r examples/resource_builder_demo.nim
```

## Resource Limits

`ResourceLoadLimits` controls the maximum encoded bytes, node count, tree depth, and
embedded image bytes. File image paths are resolved relative to `assetBasePath`.
Embedded images are stored as CBOR byte strings.

Diagnostics use stable string codes and include severity, structural path, resource
identifier, and related identifier. This makes them suitable for build tools,
inspectors, and future resource compilers as well as runtime logging.
