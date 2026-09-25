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

## Tekton Resource Editor

Tekton's `ResourceEditorDocument` combines the value-only resource draft with NimKit's
application `Document` behavior. `showWindows` creates the first builder window:
the resource hierarchy and palette are on the left, the valid preview is in the
center, and the generic property inspector and path-addressed diagnostics are on
the right.

```nim
import merenda/tekton

let
  document = newResourceEditorDocument(bundle, fileUrl = "ui.cbor")
  app = sharedApplication()

discard document.resources().selectResource(resourceId("root"))
discard document.showWindows(app)
app.run()
```

The view palette follows the runtime registry, including custom registered kinds,
sliders, and steppers. The resource picker below it adds layout guides, constraints,
windows, commands, images, localization catalogs, key binding tables, and themes.
Select a view before adding a guide, constraint, or window to use it as the owner or
content view. Newly added resources with missing references remain editable and show
diagnostics until their required fields are filled in.

The inspector edits guide insets, constraint endpoints and anchors, relation,
multiplier, constant, priority, and activation; window titles and connections; command
targets; image sources; and catalog/theme metadata. Enum fields offer choices and
boolean fields use checkboxes. Controllers, menu trees, key binding entries,
localization strings, and theme rules still have read-only detail rows.

The view inspector chooses controls from each `ResourcePropertyDescriptor`: boolean
properties use checkboxes, enum-backed properties use combo boxes populated from the
registry, colors use a popup color well, and open-ended values retain text editing. If
typed text cannot be parsed, it is committed as a string value so the exact draft text
remains visible and validation can diagnose the mismatch. Valid revisions are
reconciled while preserving compatible view and controller identities. Property edits
stage only changed widgets; edits to layout records rebuild constraints against the
existing views. Unchanged hierarchies, assets, and constraints are retained. Invalid drafts never replace
the last working preview. Hierarchy clicks and preview clicks both update selection by
`ResourceId`. Design mode captures input at the canvas, so selecting a checkbox does
not toggle it or invoke application actions. Enable **Interact** to run the controls.
The inspector displays live defaults without adding them to the document; authored
values, including invalid text, take precedence. Invalid boolean/enum drafts switch
to text editing so they can be corrected.

Select a guide to see its inset outline, or a constraint to highlight its endpoints.
**Pin to Parent** creates four edge constraints for a selected child of a freeform
container as one undo action. Active layout constraints disable freeform dragging
and keyboard resizing. After layout, unsatisfied authored constraints appear in
Diagnostics, including conflicts with a control's size limits. Invalid numeric text
in typed resource fields stays in the field editor with an error; validly parsed but
inconsistent records remain drafts and keep the last valid preview.

Palette buttons insert into selected containers and beside selected leaf views. The
Delete and Backspace keys remove the selected view or flat resource. Deleting a view
also removes its guides and touching constraints in the same undo action, and selects
the nearest sibling or parent. Use Duplicate, Up, and Down for view duplication and
ordering; Option-arrow moves freeform views, and Shortcut-Option-arrow resizes them
(Shift changes the step from one to ten points).

The editor installs `DocumentFileProtocol` for canonical CBOR reads and writes and
shares the resource draft's `UndoManager` with the application document. A save or
revert updates the manager's clean state and the normal document edited indicator.
**Save** prompts for a destination for new documents, **Save As** writes another file,
and **Open** opens a file in a separate editor window. Save commits the active field
first and stops if its text is invalid. Resource image paths are resolved relative to
the opened document unless the caller supplies an explicit asset base directory.

Run the complete vertical slice with:

```sh
nim r src/merenda/tekton.nim
```

The app module exports `tektonStarterBundle`, `newTektonDocument`, and `runTekton`, so
applications and tests can host the builder without relying on example-only code. Pass
an existing CBOR path to load it at startup. The reusable editor, preview reconciler,
and resource-value editing APIs are available through `import merenda/tekton`; they are
kept separate from the backend-neutral `merenda/nimkit/resources` API.

For typed operations, `ResourceDocument.insertResource`, `replaceResource`,
`removeResource`, and `moveResource` support flat resource records. Insert and replace
also have `ResourceInsertOperation[T]` and `ResourceReplaceOperation[T]` forms. Identity
and index errors reject an operation; semantic errors stay in the draft. Use the
shared undo manager's `beginUndoGrouping`/`endUndoGrouping` to group operations.

Tekton edits resource documents; it does not attach to a separate running process or
generate application logic. For inspection inside an existing app, use NimKit's
`showViewInspector(root, app)` (see `examples/view_inspector_demo.nim`). The remaining
work toward a complete Interface Builder is recorded in [the Tekton review](tekton-review.md).

## Resource Limits

`ResourceLoadLimits` controls the maximum encoded bytes, node count, tree depth, and
embedded image bytes. File image paths are resolved relative to `assetBasePath`.
Embedded images are stored as CBOR byte strings.

Diagnostics use stable string codes and include severity, structural path, resource
identifier, and related identifier. This makes them suitable for build tools,
inspectors, and future resource compilers as well as runtime logging.
