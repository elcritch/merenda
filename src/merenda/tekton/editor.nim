## Tekton's interactive resource-document editor.

import std/[algorithm, options, os, sets, strutils, tables]

import sigils/[core, selectors]

import ../nimkit/accessibility/accessibility
import ../nimkit/app/[application, documents, panels, windowcontrollers, windows]
import ../nimkit/containers/[gridviews, outlineviews, scrollviews, tableviews]
import ../nimkit/controls/[buttons, colorpicker, comboboxes]
import ../nimkit/debug/selectionrings
import ../nimkit/foundation/events
import ../nimkit/foundation/[selectors as nimkitSelectors, types, undomanagers, urls]
import ../nimkit/responder/keybindings
import
  ../nimkit/resources/[
    resrccbor, resrcconstruction, resrccore, resrcdocument, resrcregistry,
    resrcvalidation,
  ]
import ../nimkit/text/textfields
import ../nimkit/themes
import ../nimkit/view/views
import ./[preview, recordediting, valueediting]

export valueediting

type
  ResourcePropertyEditorKind* = enum
    rpekReadOnly
    rpekText
    rpekCheckBox
    rpekComboBox
    rpekColorWell

  ResourceEditorPropertyRow* = object
    descriptor*: ResourcePropertyDescriptor
    value*: Option[ResourceValue]
    text*: string
    diagnosticPath*: string

  ResourcePropertyEditResult* = object
    edit*: ResourceEditResult
    parsed*: bool
    value*: ResourceValue
    message*: string

  ResourceViewSiblingDirection* = enum
    rvsdEarlier
    rvsdLater

  ResourceEditorDocument* = ref object of Document
    xResources: ResourceDocument
    xRegistry: ResourceRegistry
    xInstantiationContext: ResourceInstantiationContext
    xValidationOptions: ResourceValidationOptions
    xIoDiagnostics: ResourceDiagnostics
    xExplicitAssetBasePath: bool
    xExplicitValidationBasePath: bool

  ResourceEditor* = ref object of Responder
    xDocument: ResourceEditorDocument
    xRootView: View
    xHierarchyView: OutlineView
    xPaletteView: GridView
    xPropertyInspector: TableView
    xDiagnosticsView: TableView
    xPreviewSurface: View
    xStatusLabel: Label
    xSelectionLabel: Label
    xDiagnosticsTitle: Label
    xPaletteKinds: seq[string]
    xPaletteButtons: seq[Button]
    xUndoButton: Button
    xRedoButton: Button
    xDuplicateButton: Button
    xMoveEarlierButton: Button
    xMoveLaterButton: Button
    xPropertyRows: seq[ResourceEditorPropertyRow]
    xDiagnosticRows: seq[ResourceDiagnostic]
    xPreview: ResourcePreview
    xPreviewDiagnostics: ResourceDiagnostics
    xLayoutDiagnostics: ResourceDiagnostics
    xPreviewRevision: int
    xHasPreview: bool
    xObservedResources: ResourceDocument
    xSynchronizedRevision: int
    xInspectorSelection: Option[ResourceId]
    xHierarchyItems: seq[OutlineItem]
    xHierarchyRevision: int
    xSelectionText: string
    xInteractivePreview: bool
    xCanvasConstraints: Table[ResourceId, seq[LayoutConstraint]]
    xSynchronizingSelection: bool
    xSelectionRing: SelectionRing
    xRelatedSelectionRing: SelectionRing
    xHoverRing: SelectionRing
    xHoveredResourceId: Option[ResourceId]
    xHoverGeometry: ResourcePreviewGeometry
    xSelectionFallbackId: Option[ResourceId]
    xDraggedResourceId: Option[ResourceId]
    xDraggedView: View
    xDragStartPoint: Point
    xDragStartFrame: Rect
    xDragDidMove: bool

  ResourceEditorPreviewSurface = ref object of View
    xEditor: ResourceEditor

  ResourceEditorHierarchyView = ref object of OutlineView
    xEditor: ResourceEditor

const
  ResourceEditorDocumentType* = "nimkit-resource"
  ResourceEditorPaletteKinds* = [
    "view", "control", "button", "checkBox", "radioButton", "textField", "label",
    "imageView", "stackView", "switchButton", "progressIndicator", "box", "splitView",
    "slider", "stepper",
  ]

proc newResourceEditor*(document: ResourceEditorDocument): ResourceEditor
proc newResourceEditorWindow*(editor: ResourceEditor): Window
proc synchronize*(editor: ResourceEditor)
proc selectResource*(editor: ResourceEditor, id: ResourceId): bool
proc removeSelectedView*(editor: ResourceEditor): ResourceEditResult {.discardable.}
proc duplicateSelectedView*(editor: ResourceEditor): ResourceEditResult {.discardable.}
proc reorderSelectedView*(
  editor: ResourceEditor, direction: ResourceViewSiblingDirection
): ResourceEditResult {.discardable.}

proc nudgeSelectedView*(
  editor: ResourceEditor, delta: Point
): ResourceEditResult {.discardable.}

proc resizeSelectedView*(
  editor: ResourceEditor, delta: Size
): ResourceEditResult {.discardable.}

proc saveEditorDocument*(
  editor: ResourceEditor, choosePath = false
): bool {.discardable.}

proc updatePreviewHover*(
  editor: ResourceEditor, point: Point
): ResourcePreviewHit {.discardable.}

proc clearPreviewHover*(editor: ResourceEditor)
proc interactivePreview*(editor: ResourceEditor): bool =
  editor.xInteractivePreview

proc `interactivePreview=`*(editor: ResourceEditor, value: bool) =
  ## Design mode captures canvas input; interaction mode runs the preview controls.
  editor.xInteractivePreview = value
  editor.clearPreviewHover()

proc beginPreviewDrag(
  editor: ResourceEditor, view: View, point: Point
): bool {.discardable.}

proc updatePreviewDrag*(editor: ResourceEditor, point: Point): bool {.discardable.}
proc endPreviewDrag*(editor: ResourceEditor): bool {.discardable.}
proc previewResourceId(editor: ResourceEditor, selectedView: View): ResourceId

protocol ResourceEditorDocumentEvents:
  proc resourcesDidChange*(
    document: ResourceEditorDocument, sender: ResourceEditorDocument
  ) {.signal.}

proc localFilePath(fileUrl: string): string =
  initUrl(fileUrl).localFilePath(getCurrentDir())

proc replaceResources(
    document: ResourceEditorDocument, bundle: sink ResourceBundle, assetBasePath = ""
) =
  let manager = document.undoManagerFor()
  if not document.xExplicitValidationBasePath:
    document.xValidationOptions.assetBasePath = assetBasePath
  if not document.xExplicitAssetBasePath:
    document.xInstantiationContext.assetBasePath = assetBasePath
  document.xResources = newResourceDocument(
    bundle, document.xRegistry, document.xValidationOptions, manager
  )
  manager.clearAll()
  emit document.resourcesDidChange(document)

protocol ResourceEditorDocumentIo of DocumentFileProtocol:
  method canReadType(document: ResourceEditorDocument, fileType: string): bool =
    fileType in ["", "cbor", ResourceEditorDocumentType]

  method canWriteType(document: ResourceEditorDocument, fileType: string): bool =
    fileType in ["", "cbor", ResourceEditorDocumentType]

  method readContents(
      document: ResourceEditorDocument, fileUrl: string, fileType: string
  ): bool =
    discard fileType
    let
      path = fileUrl.localFilePath()
      loaded = loadResourceBundle(path)
    document.xIoDiagnostics = loaded.diagnostics
    if not loaded.loaded:
      emit document.resourcesDidChange(document)
      return
    document.replaceResources(loaded.bundle, path.parentDir())
    result = true

  method writeContents(
      document: ResourceEditorDocument, fileUrl: string, fileType: string
  ): bool =
    discard fileType
    document.xIoDiagnostics = ResourceDiagnostics()
    let path = fileUrl.localFilePath()
    try:
      writeFile(path, document.xResources.bundle().encodeResourceBundle())
      result = true
    except CatchableError as error:
      document.xIoDiagnostics.add(
        rdsError,
        "resource.file.unavailable",
        "could not write resource file '" & path & "': " & error.msg,
        path = path,
      )
    emit document.resourcesDidChange(document)

protocol ResourceEditorDocumentWindows of DocumentWindowProtocol:
  method makeWindowControllers(
      document: ResourceEditorDocument
  ): seq[WindowController] =
    let editor = newResourceEditor(document)
    result = @[newWindowController(editor.newResourceEditorWindow())]

proc newResourceEditorDocument*(
    bundle: sink ResourceBundle,
    fileUrl = "",
    registry = initNimKitResourceRegistry(),
    instantiationContext = initResourceInstantiationContext(),
    validationOptions = initResourceValidationOptions(),
): ResourceEditorDocument =
  result = ResourceEditorDocument(
    xRegistry: registry,
    xInstantiationContext: instantiationContext,
    xValidationOptions: validationOptions,
    xExplicitAssetBasePath: instantiationContext.assetBasePath.len > 0,
    xExplicitValidationBasePath: validationOptions.assetBasePath.len > 0,
  )
  result.initDocument(
    fileUrl = fileUrl,
    fileType = if fileUrl.len == 0: ResourceEditorDocumentType else: "",
    fileName = if fileUrl.len == 0: "Untitled Resources.cbor" else: "",
  )
  if fileUrl.len > 0:
    let basePath = fileUrl.localFilePath().parentDir()
    if not result.xExplicitAssetBasePath:
      result.xInstantiationContext.assetBasePath = basePath
    if not result.xExplicitValidationBasePath:
      result.xValidationOptions.assetBasePath = basePath
  result.xResources = newResourceDocument(
    bundle, registry, result.xValidationOptions, result.undoManagerFor()
  )
  result.setUndoManager(result.xResources.undoManager())
  discard result.withProtocol(ResourceEditorDocumentIo)
  discard result.withProtocol(ResourceEditorDocumentWindows)

proc newResourceEditorDocument*(
    namespace = "",
    fileUrl = "",
    registry = initNimKitResourceRegistry(),
    instantiationContext = initResourceInstantiationContext(),
    validationOptions = initResourceValidationOptions(),
): ResourceEditorDocument =
  newResourceEditorDocument(
    initResourceBundle(namespace),
    fileUrl,
    registry,
    instantiationContext,
    validationOptions,
  )

proc resources*(document: ResourceEditorDocument): ResourceDocument =
  document.xResources

proc ioDiagnostics*(document: ResourceEditorDocument): lent ResourceDiagnostics =
  document.xIoDiagnostics

proc paletteKinds*(editor: ResourceEditor): lent seq[string] =
  editor.xPaletteKinds

proc paletteButton*(editor: ResourceEditor, kind: string): Button =
  for index, candidate in editor.xPaletteKinds:
    if candidate == kind and index < editor.xPaletteButtons.len:
      return editor.xPaletteButtons[index]

proc duplicateButton*(editor: ResourceEditor): Button =
  editor.xDuplicateButton

proc undoButton*(editor: ResourceEditor): Button =
  editor.xUndoButton

proc redoButton*(editor: ResourceEditor): Button =
  editor.xRedoButton

proc moveEarlierButton*(editor: ResourceEditor): Button =
  editor.xMoveEarlierButton

proc moveLaterButton*(editor: ResourceEditor): Button =
  editor.xMoveLaterButton

proc rootView*(editor: ResourceEditor): View =
  editor.xRootView

proc hierarchyView*(editor: ResourceEditor): OutlineView =
  editor.xHierarchyView

proc paletteView*(editor: ResourceEditor): GridView =
  editor.xPaletteView

proc propertyInspector*(editor: ResourceEditor): TableView =
  editor.xPropertyInspector

proc diagnosticsView*(editor: ResourceEditor): TableView =
  editor.xDiagnosticsView

proc previewSurface*(editor: ResourceEditor): View =
  editor.xPreviewSurface

proc propertyRows*(editor: ResourceEditor): lent seq[ResourceEditorPropertyRow] =
  editor.xPropertyRows

proc diagnosticRows*(editor: ResourceEditor): lent seq[ResourceDiagnostic] =
  editor.xDiagnosticRows

func hasPreview*(editor: ResourceEditor): bool =
  editor.xHasPreview

proc previewRevision*(editor: ResourceEditor): Natural =
  if editor.xHasPreview:
    result = editor.xPreviewRevision.Natural

proc previewInstance*(editor: ResourceEditor): ResourcePreview =
  editor.xPreview

func hasPreviewSelection*(editor: ResourceEditor): bool =
  editor.xSelectionRing.installed()

proc hoveredResourceId*(editor: ResourceEditor): Option[ResourceId] =
  editor.xHoveredResourceId

proc hoverGeometry*(editor: ResourceEditor): ResourcePreviewGeometry =
  editor.xHoverGeometry

proc previewGeometry*(editor: ResourceEditor, id: ResourceId): ResourcePreviewGeometry =
  editor.xPreview.geometry(id, editor.xPreviewSurface)

proc previewHitTest*(editor: ResourceEditor, point: Point): ResourcePreviewHit =
  editor.xPreview.hitTest(editor.xPreviewSurface, point)

func propertyEditorKind*(row: ResourceEditorPropertyRow): ResourcePropertyEditorKind =
  if not row.descriptor.editable:
    rpekReadOnly
  elif row.value.isSome and (
    (
      row.descriptor.acceptedKinds != {} and
      row.value.get().kind notin row.descriptor.acceptedKinds
    ) or
    (row.descriptor.options.len > 0 and row.value.get() notin row.descriptor.options)
  ):
    rpekText
  elif row.descriptor.options.len > 0:
    rpekComboBox
  elif row.descriptor.acceptedKinds == {rvBool}:
    rpekCheckBox
  elif rvColor in row.descriptor.acceptedKinds:
    rpekColorWell
  else:
    rpekText

func resourceNodeKindTitle(kind: ResourceNodeKind): string =
  case kind
  of rnkView: "View"
  of rnkLayoutGuide: "Layout Guide"
  of rnkLayoutConstraint: "Layout Constraint"
  of rnkController: "Controller"
  of rnkWindow: "Window"
  of rnkMenu: "Menu"
  of rnkMenuItem: "Menu Item"
  of rnkCommand: "Command"
  of rnkImage: "Image"
  of rnkLocalization: "Localization"
  of rnkKeyBindings: "Key Bindings"
  of rnkTheme: "Theme"

proc nodeTitle(document: ResourceDocument, path: ResourceNodePath): string =
  let detail =
    case path.kind
    of rnkView:
      document.view(path.id).kind
    of rnkController:
      document.controller(path.id).kind
    else:
      path.kind.resourceNodeKindTitle()
  result = detail & " — " & $path.id

proc selectedResourceId(editor: ResourceEditor): Option[ResourceId] =
  let selected = editor.xDocument.xResources.selectedResourceIds()
  if selected.len > 0:
    some(selected[0])
  else:
    none(ResourceId)

proc selectedViewId(editor: ResourceEditor): Option[ResourceId] =
  let selected = editor.selectedResourceId()
  if selected.isSome:
    let path = editor.xDocument.xResources.findNodePath(selected.get())
    if path.isSome and path.get().kind == rnkView:
      return selected
  none(ResourceId)

proc refreshHierarchy(editor: ResourceEditor) =
  let document = editor.xDocument.xResources
  var expanded = editor.xHierarchyView.expandedItemIdentifiers()
  for id in document.selectedResourceIds():
    let path = document.findNodePath(id)
    if path.isSome:
      var parent = document.findParentPath(path.get())
      while parent.isSome:
        let parentId = $parent.get().id
        if parentId notin expanded:
          expanded.add parentId
        parent = document.findParentPath(parent.get())
  var paths: seq[ResourceNodePath]
  if editor.xHierarchyRevision != document.revision().int:
    for path in document:
      paths.add path

  var parents = initHashSet[ResourceId]()
  for path in paths:
    let parent = document.findParentPath(path)
    if parent.isSome:
      parents.incl parent.get().id
  var items: seq[OutlineItem]
  for path in paths:
    let parent = document.findParentPath(path)
    let expandable = path.id in parents
    items.add initOutlineItem(
      $path.id,
      document.nodeTitle(path),
      parentIdentifier =
        if parent.isSome:
          $parent.get().id
        else:
          "",
      expandable = expandable,
      leaf = not expandable,
      tooltip = document.diagnosticPath(path),
    )

  editor.xSynchronizingSelection = true
  try:
    if editor.xHierarchyRevision != document.revision().int:
      if items != editor.xHierarchyItems:
        editor.xHierarchyView.outlineItems = items
        editor.xHierarchyItems = move items
      editor.xHierarchyRevision = document.revision().int
    editor.xHierarchyView.expandedItemIdentifiers = expanded
    var selected: seq[string]
    for id in document.selectedResourceIds():
      selected.add $id
    editor.xHierarchyView.selectedItemIdentifiers = selected
  finally:
    editor.xSynchronizingSelection = false

proc unknownPropertyDescriptor(property: ResourceProperty): ResourcePropertyDescriptor =
  ResourcePropertyDescriptor(
    name: property.name,
    nimTypeName: $property.value.kind,
    acceptedKinds: {property.value.kind},
    editable: true,
  )

func displayedId(id: ResourceId): string =
  if id.isEmpty:
    "—"
  else:
    $id

func displayedText(text: ResourceText): string =
  if text.key.len > 0:
    "@" & text.key & (if text.fallback.len > 0: " (" & text.fallback & ")"
    else: "")
  else:
    text.fallback

func displayedLayoutItem(item: ResourceLayoutItemReference): string =
  if item.id.isEmpty:
    "—"
  else:
    $item.kind & ":" & $item.id

proc addDetailRow(
    editor: ResourceEditor, name, nimTypeName, text, diagnosticPath: string
) =
  editor.xPropertyRows.add ResourceEditorPropertyRow(
    descriptor:
      ResourcePropertyDescriptor(name: name, nimTypeName: nimTypeName, editable: false),
    text: text,
    diagnosticPath: diagnosticPath,
  )

proc refreshResourceDetailRows(editor: ResourceEditor, path: ResourceNodePath) =
  let
    document = editor.xDocument.xResources
    basePath = document.diagnosticPath(path)
  template detail(name, nimType, value: untyped) =
    editor.addDetailRow(name, nimType, $value, basePath & "." & name)

  template reference(name, value: untyped) =
    editor.addDetailRow(name, "ResourceId", displayedId(value), basePath & "." & name)

  case path.kind
  of rnkView:
    discard
  of rnkLayoutGuide:
    let guide = document.layoutGuide(path.id)
    reference("owningViewId", guide.owningViewId)
    detail("insets", "EdgeInsets", guide.insets)
  of rnkLayoutConstraint:
    let constraint = document.layoutConstraint(path.id)
    reference("owningViewId", constraint.owningViewId)
    detail(
      "firstItem",
      "ResourceLayoutItemReference",
      displayedLayoutItem(constraint.firstItem),
    )
    detail("firstAnchor", "ResourceLayoutAnchor", constraint.firstAnchor)
    detail("relation", "ResourceLayoutRelation", constraint.relation)
    detail(
      "secondItem",
      "ResourceLayoutItemReference",
      displayedLayoutItem(constraint.secondItem),
    )
    detail("secondAnchor", "ResourceLayoutAnchor", constraint.secondAnchor)
    detail("multiplier", "float32", constraint.multiplier)
    detail("constant", "float32", constraint.constant)
    detail("priority", "float32", constraint.priority)
    detail("active", "bool", constraint.active)
  of rnkController:
    let controller = document.controller(path.id)
    detail("kind", "string", controller.kind)
    reference("viewId", controller.viewId)
    detail("children", "seq[ControllerNodeResource]", controller.children.len)
  of rnkWindow:
    let window = document.window(path.id)
    detail("kind", "ResourceWindowKind", window.kind)
    detail("title", "ResourceText", displayedText(window.title))
    detail("frame", "Rect", window.frame)
    reference("contentViewId", window.contentViewId)
    reference("controllerId", window.controllerId)
    reference("initialFirstResponderId", window.initialFirstResponderId)
    reference("keyBindingTableId", window.keyBindingTableId)
    reference("themeId", window.themeId)
  of rnkMenu:
    let menu = document.menu(path.id)
    detail("title", "ResourceText", displayedText(menu.title))
    detail("items", "seq[MenuItemResource]", menu.items.len)
  of rnkMenuItem:
    let item = document.menuItem(path.id)
    detail("title", "ResourceText", displayedText(item.title))
    detail("subtitle", "ResourceText", displayedText(item.subtitle))
    reference("commandId", item.commandId)
    reference("imageId", item.imageId)
    if item.hasKeyEquivalent:
      detail("keyEquivalent", "KeyStrokeResource", item.keyEquivalent)
    detail("enabled", "ResourceFlag", item.enabled)
    detail("hidden", "bool", item.hidden)
    detail("separator", "bool", item.separator)
    detail("tag", "int", item.tag)
    detail("validates", "ResourceFlag", item.validates)
  of rnkCommand:
    let command = document.command(path.id)
    detail("selector", "string", command.selector)
    detail("targetKind", "ResourceCommandTargetKind", command.targetKind)
    reference("targetId", command.targetId)
  of rnkImage:
    let image = document.image(path.id)
    detail("sourceKind", "ResourceImageSourceKind", image.sourceKind)
    detail("name", "string", image.name)
    detail("path", "string", image.path)
    detail("mediaType", "string", image.mediaType)
    detail("dataBytes", "int", image.data.len)
    detail("cachePolicy", "ResourceImageCachePolicy", image.cachePolicy)
  of rnkLocalization:
    let catalog = document.localization(path.id)
    detail("locale", "string", catalog.locale)
    detail("fallbackLocale", "string", catalog.fallbackLocale)
    for index, entry in catalog.strings:
      editor.addDetailRow(
        "string[" & $index & "]",
        "LocalizedStringResource",
        entry.key & " = " & entry.value,
        basePath & ".strings[" & $index & "]",
      )
  of rnkKeyBindings:
    let bindings = document.keyBindings(path.id)
    for index, binding in bindings.bindings:
      editor.addDetailRow(
        "binding[" & $index & "]",
        "KeyBindingResource",
        $binding.stroke & " → " & $binding.commandId,
        basePath & ".bindings[" & $index & "]",
      )
  of rnkTheme:
    let theme = document.theme(path.id)
    reference("parentId", theme.parentId)
    for index, token in theme.tokens:
      editor.addDetailRow(
        "token[" & $index & "]",
        "ThemeTokenResource",
        token.name & " (" & $token.value.kind & ")",
        basePath & ".tokens[" & $index & "]",
      )
    detail("rules", "seq[ThemeRuleResource]", theme.rules.len)

proc refreshPropertyRows(editor: ResourceEditor) =
  editor.xPropertyRows.setLen(0)
  let selected = editor.selectedResourceId()
  if selected.isNone:
    editor.xPropertyInspector.reloadData()
    editor.xSelectionLabel.text = "Select a resource to inspect its properties."
    return

  let
    document = editor.xDocument.xResources
    id = selected.get()
    path = document.nodePath(id)
    nodePath = document.diagnosticPath(path)
  if path.kind != rnkView:
    editor.xSelectionLabel.text =
      path.kind.resourceNodeKindTitle() & "  " & $id & "  ·  " & nodePath
    editor.refreshResourceDetailRows(path)
    for field in document.recordFields(id):
      var found = false
      let row = ResourceEditorPropertyRow(
        descriptor: field.descriptor,
        value: some(field.value),
        text: field.value.formatResourceValue(),
        diagnosticPath: nodePath & "." & field.descriptor.name,
      )
      for existing in editor.xPropertyRows.mitems:
        if existing.descriptor.name == field.descriptor.name:
          existing = row
          found = true
      if not found:
        editor.xPropertyRows.add row
    editor.xPropertyInspector.reloadData()
    return

  let node = document.view(id)
  editor.xSelectionLabel.text = node.kind & "  " & $id & "  ·  " & nodePath

  var knownNames: seq[string]
  for descriptor in editor.xDocument.xRegistry.viewProperties(node.kind):
    var property = document.findViewProperty(id, descriptor.name)
    if property.isNone:
      let effective = editor.xPreview.readViewProperty(id, descriptor.name)
      if effective.read:
        property = some(resourceProperty(descriptor.name, effective.value))
    editor.xPropertyRows.add ResourceEditorPropertyRow(
      descriptor: descriptor,
      value:
        if property.isSome:
          some(property.get().value)
        else:
          none(ResourceValue),
      text:
        if property.isSome:
          property.get().value.formatResourceValue()
        else:
          "",
      diagnosticPath: nodePath & ".properties." & descriptor.name,
    )
    knownNames.add descriptor.name

  for property in node.properties:
    if property.name notin knownNames:
      editor.xPropertyRows.add ResourceEditorPropertyRow(
        descriptor: property.unknownPropertyDescriptor(),
        value: some(property.value),
        text: property.value.formatResourceValue(),
        diagnosticPath: nodePath & ".properties." & property.name,
      )

  editor.xPropertyRows.sort(
    proc(a, b: ResourceEditorPropertyRow): int =
      cmp(a.descriptor.name, b.descriptor.name)
  )
  editor.xPropertyInspector.reloadData()

proc refreshDiagnosticRows(editor: ResourceEditor) =
  let previous = editor.xDiagnosticRows
  editor.xDiagnosticRows.setLen(0)
  for diagnostic in editor.xDocument.xResources.diagnostics():
    editor.xDiagnosticRows.add diagnostic
  for diagnostic in editor.xDocument.xIoDiagnostics:
    editor.xDiagnosticRows.add diagnostic
  for diagnostic in editor.xPreviewDiagnostics:
    editor.xDiagnosticRows.add diagnostic
  for diagnostic in editor.xLayoutDiagnostics:
    editor.xDiagnosticRows.add diagnostic
  editor.xDiagnosticsTitle.text = "Diagnostics (" & $editor.xDiagnosticRows.len & ")"
  if previous != editor.xDiagnosticRows:
    editor.xDiagnosticsView.reloadData()

proc clearPreviewHover*(editor: ResourceEditor) =
  discard editor.xHoverRing.uninstall()
  editor.xHoveredResourceId = none(ResourceId)
  editor.xHoverGeometry = ResourcePreviewGeometry()
  editor.xSelectionLabel.text = editor.xSelectionText

func previewHoverRingStyle(): SelectionRingStyle =
  initSelectionRingStyle(
    strokeColor = color(0.1, 0.72, 0.82, 0.9),
    fillColor = color(0.1, 0.72, 0.82, 0.08),
    lineWidth = 2.0,
    cornerRadius = 5.0,
    insets = insets(1.0),
  )

proc installPreviewHoverRing(editor: ResourceEditor) =
  if editor.xHoveredResourceId.isNone or not editor.xHasPreview:
    return
  let view = editor.xPreview.findView(editor.xHoveredResourceId.get())
  if not view.isNil:
    editor.xHoverRing = view.installSelectionRing(previewHoverRingStyle())

proc updatePreviewHover*(
    editor: ResourceEditor, point: Point
): ResourcePreviewHit {.discardable.} =
  if not editor.xHasPreview:
    return
  result = editor.previewHitTest(point)
  let nextId =
    if result.found:
      some(result.resourceId)
    else:
      none(ResourceId)
  if nextId == editor.xHoveredResourceId:
    if result.found:
      editor.xHoverGeometry = result.geometry
    return

  discard editor.xHoverRing.uninstall()
  editor.xHoveredResourceId = nextId
  editor.xHoverGeometry = result.geometry
  if result.found:
    editor.installPreviewHoverRing()
    let frame = result.geometry.frameInReferenceView
    editor.xSelectionLabel.text =
      "Hover " & $result.resourceId & " · x " & $frame.x & "  y " & $frame.y & "  w " &
      $frame.w & "  h " & $frame.h
  else:
    editor.xSelectionLabel.text = editor.xSelectionText

protocol ResourceEditorPreviewSurfacePicking of ViewProtocol:
  method hitTest(surface: ResourceEditorPreviewSurface, point: Point): View =
    if surface.isHidden() or not views.pointInside(surface, point):
      return
    if not surface.xEditor.isNil and surface.xEditor.xInteractivePreview:
      let hit = surface.xEditor.previewHitTest(point)
      if hit.found:
        return hit.hitView
    surface

protocol ResourceEditorPreviewSurfaceLayout of ViewLayoutProtocol:
  method layout(surface: ResourceEditorPreviewSurface) =
    if not surface.xEditor.isNil:
      let editor = surface.xEditor
      let diagnostics = editor.xPreview.layoutDiagnostics(surface)
      if diagnostics != editor.xLayoutDiagnostics:
        editor.xLayoutDiagnostics = diagnostics
        editor.refreshDiagnosticRows()

protocol ResourceEditorPreviewSurfaceEvents of ResponderEventProtocol:
  method mouseDown(surface: ResourceEditorPreviewSurface, event: MouseEvent): bool =
    if not surface.xEditor.isNil and event.button == mbPrimary:
      let hit = surface.xEditor.previewHitTest(event.location)
      if hit.found:
        discard surface.xEditor.selectResource(hit.resourceId)
        discard surface.xEditor.beginPreviewDrag(hit.resourceView, event.location)
      return true

  method mouseDragged(surface: ResourceEditorPreviewSurface, event: MouseEvent): bool =
    if not surface.xEditor.isNil and event.button == mbPrimary:
      return surface.xEditor.updatePreviewDrag(event.location)

  method mouseUp(surface: ResourceEditorPreviewSurface, event: MouseEvent): bool =
    if not surface.xEditor.isNil and event.button == mbPrimary:
      discard surface.xEditor.endPreviewDrag()
      return true

  method mouseMoved(surface: ResourceEditorPreviewSurface, event: MouseEvent): bool =
    if not surface.xEditor.isNil:
      discard surface.xEditor.updatePreviewHover(event.location)
    false

  method mouseExited(surface: ResourceEditorPreviewSurface, event: MouseEvent): bool =
    discard event
    if not surface.xEditor.isNil:
      surface.xEditor.clearPreviewHover()
    false

proc freeformParent(document: ResourceDocument, id: ResourceId): bool =
  let path = document.findNodePath(id)
  if path.isNone or path.get().kind != rnkView:
    return
  for constraint in document.bundle().layoutConstraints:
    if constraint.active and (
      (constraint.firstItem.kind == rliView and constraint.firstItem.id == id) or
      (constraint.secondItem.kind == rliView and constraint.secondItem.id == id)
    ):
      return
  let parent = document.findParentPath(path.get())
  if parent.isNone:
    return true
  parent.get().kind == rnkView and document.view(parent.get().id).kind in [
    "view", "box"
  ]

proc beginPreviewDrag(editor: ResourceEditor, view: View, point: Point): bool =
  if view.isNil or not editor.xDocument.xResources.draftIsValid():
    return
  let
    id = editor.previewResourceId(view)
    document = editor.xDocument.xResources
  if id.isEmpty or not document.freeformParent(id):
    return
  let frame = document.findViewProperty(id, "frame")
  if frame.isNone or frame.get().value.kind != rvRect:
    return
  discard editor.selectResource(id)
  editor.xDraggedResourceId = some(id)
  editor.xDraggedView = editor.xPreview.findView(id)
  editor.xDragStartPoint = point
  editor.xDragStartFrame = frame.get().value.rectValue
  editor.xDragDidMove = false
  result = not editor.xDraggedView.isNil

proc updatePreviewDrag*(editor: ResourceEditor, point: Point): bool =
  if editor.xDraggedResourceId.isNone or editor.xDraggedView.isNil:
    return
  let
    delta =
      initPoint(point.x - editor.xDragStartPoint.x, point.y - editor.xDragStartPoint.y)
    nextFrame = rect(
      editor.xDragStartFrame.x + delta.x,
      editor.xDragStartFrame.y + delta.y,
      editor.xDragStartFrame.w,
      editor.xDragStartFrame.h,
    )
  editor.xDragDidMove = editor.xDragDidMove or delta != Point()
  editor.xDraggedView.frame = nextFrame
  let id = editor.xDraggedResourceId.get()
  if editor.xCanvasConstraints.hasKey(id):
    editor.xCanvasConstraints[id][0].constant = nextFrame.x
    editor.xCanvasConstraints[id][1].constant = nextFrame.y
  result = true

proc endPreviewDrag*(editor: ResourceEditor): bool =
  if editor.xDraggedResourceId.isNone or editor.xDraggedView.isNil:
    return
  let
    id = editor.xDraggedResourceId.get()
    draggedFrame = editor.xDraggedView.frame()
    delta = initPoint(
      draggedFrame.x - editor.xDragStartFrame.x,
      draggedFrame.y - editor.xDragStartFrame.y,
    )
    didMove = editor.xDragDidMove
  editor.xDraggedResourceId = none(ResourceId)
  editor.xDraggedView = nil
  editor.xDragDidMove = false
  if not didMove:
    return true
  let edit = editor.nudgeSelectedView(delta)
  if not edit.applied and editor.xDocument.xResources.contains(id):
    let previewView = editor.xPreview.findView(id)
    if not previewView.isNil:
      previewView.frame = editor.xDragStartFrame
  result = edit.applied

protocol ResourceEditorHierarchyEvents of ResponderEventProtocol:
  method keyDown(hierarchy: ResourceEditorHierarchyView, event: KeyEvent): bool =
    if not hierarchy.xEditor.isNil:
      if event.key == keyS and
          event.modifiers in [shortcutModifiers(), shortcutModifiers() + {kmShift}]:
        discard
          hierarchy.xEditor.saveEditorDocument(choosePath = kmShift in event.modifiers)
        return true
      elif event.key in {keyBackspace, keyDelete} and event.modifiers == {}:
        if hierarchy.xEditor.removeSelectedView().applied:
          return true
      elif event.key == keyD and event.modifiers == shortcutModifiers():
        discard hierarchy.xEditor.duplicateSelectedView()
        return true
      elif event.key == keyArrowUp and event.modifiers == shortcutModifiers():
        discard hierarchy.xEditor.reorderSelectedView(rvsdEarlier)
        return true
      elif event.key == keyArrowDown and event.modifiers == shortcutModifiers():
        discard hierarchy.xEditor.reorderSelectedView(rvsdLater)
        return true
      elif event.key in {keyArrowLeft, keyArrowRight, keyArrowUp, keyArrowDown} and
          event.modifiers in
          [shortcutModifiers() + {kmOption}, shortcutModifiers() + {kmOption, kmShift}]:
        let amount = if kmShift in event.modifiers: 10.0'f32 else: 1.0'f32
        let delta =
          case event.key
          of keyArrowLeft:
            initSize(-amount, 0)
          of keyArrowRight:
            initSize(amount, 0)
          of keyArrowUp:
            initSize(0, -amount)
          of keyArrowDown:
            initSize(0, amount)
          else:
            Size()
        discard hierarchy.xEditor.resizeSelectedView(delta)
        return true
      elif event.key in {keyArrowLeft, keyArrowRight, keyArrowUp, keyArrowDown} and
          kmOption in event.modifiers and event.modifiers <= {kmOption, kmShift}:
        let amount = if kmShift in event.modifiers: 10.0'f32 else: 1.0'f32
        let delta =
          case event.key
          of keyArrowLeft:
            initPoint(-amount, 0)
          of keyArrowRight:
            initPoint(amount, 0)
          of keyArrowUp:
            initPoint(0, -amount)
          of keyArrowDown:
            initPoint(0, amount)
          else:
            Point()
        discard hierarchy.xEditor.nudgeSelectedView(delta)
        return true
    let next = hierarchy.performNext(keyDown, event)
    if next.isSome:
      next.get()
    else:
      false

proc clearPreview(editor: ResourceEditor) =
  editor.xLayoutDiagnostics = ResourceDiagnostics()
  for constraints in editor.xCanvasConstraints.values:
    constraints.deactivate()
  editor.xCanvasConstraints.clear()
  discard editor.xHoverRing.uninstall()
  discard editor.xSelectionRing.uninstall()
  discard editor.xRelatedSelectionRing.uninstall()
  while editor.xPreviewSurface.subviews().len > 0:
    editor.xPreviewSurface.subviews()[^1].removeFromSuperview()
  editor.xPreview = newResourcePreview(
    editor.xDocument.xRegistry, editor.xDocument.xInstantiationContext,
    editor.xDocument.xValidationOptions,
  )
  editor.xHoveredResourceId = none(ResourceId)
  editor.xHoverGeometry = ResourcePreviewGeometry()
  editor.xDraggedResourceId = none(ResourceId)
  editor.xDraggedView = nil
  editor.xDragDidMove = false

proc selectPreviewView(editor: ResourceEditor) =
  discard editor.xHoverRing.uninstall()
  discard editor.xSelectionRing.uninstall()
  discard editor.xRelatedSelectionRing.uninstall()
  let selected = editor.selectedViewId()
  if selected.isSome and editor.xHasPreview:
    let view = editor.xPreview.findView(selected.get())
    if not view.isNil:
      editor.xSelectionRing = view.installSelectionRing()
  elif editor.xHasPreview:
    let id = editor.selectedResourceId()
    if id.isSome:
      var guide: LayoutGuide
      if editor.xPreview.findLayoutGuide(id.get(), guide):
        editor.xSelectionRing = guide.owningView().installSelectionRing(
            initSelectionRingStyle(insets = guide.insets(), cornerRadius = 0)
          )
      else:
        let constraint = editor.xPreview.findLayoutConstraint(id.get())
        if not constraint.isNil:
          editor.xSelectionRing = constraint.firstItem().installSelectionRing()
          editor.xRelatedSelectionRing =
            constraint.secondItem().installSelectionRing(previewHoverRingStyle())
  editor.installPreviewHoverRing()

proc previewResourceId(editor: ResourceEditor, selectedView: View): ResourceId =
  let found = editor.xPreview.resourceIdForView(selectedView)
  if found.isSome:
    result = found.get()

proc selectResource*(editor: ResourceEditor, id: ResourceId): bool =
  let previous = editor.selectedResourceId()
  result = editor.xDocument.xResources.selectResource(id)
  if not result:
    return
  if previous != some(id):
    editor.xSelectionFallbackId = previous
  editor.refreshHierarchy()
  if previous != some(id):
    editor.refreshPropertyRows()
    editor.xSelectionText = editor.xSelectionLabel.text
    editor.xInspectorSelection = some(id)
    editor.selectPreviewView()

proc rebuildPreview(editor: ResourceEditor) =
  let document = editor.xDocument.xResources
  if not document.hasLastValidRevision():
    editor.clearPreview()
    editor.xPreviewDiagnostics = ResourceDiagnostics()
    editor.xHasPreview = false
    return

  let revision = document.lastValidRevision().int
  if editor.xHasPreview and revision == editor.xPreviewRevision:
    return

  discard editor.xHoverRing.uninstall()
  editor.xHoveredResourceId = none(ResourceId)
  editor.xHoverGeometry = ResourcePreviewGeometry()
  let update = editor.xPreview.update(
    document.lastValidBundle(), revision.Natural, editor.xPreviewSurface
  )
  editor.xPreviewDiagnostics = update.diagnostics
  if not update.applied:
    return

  editor.xPreviewRevision = revision
  editor.xHasPreview = true
  var constraints: Table[ResourceId, seq[LayoutConstraint]]
  for node in document.lastValidBundle().views:
    let view = editor.xPreview.findView(node.id)
    for property in node.properties:
      if property.name == "frame" and property.value.kind == rvRect and not view.isNil:
        let frame = property.value.rectValue
        var current = editor.xCanvasConstraints.getOrDefault(node.id)
        if current.len > 0 and current[0].firstItem() != view:
          current.deactivate()
          current.setLen(0)
        if current.len == 0:
          current =
            @[
              view[atLeft].equalTo(
                editor.xPreviewSurface[atLeft],
                constant = frame.x,
                priority = LayoutPriority(999),
              ),
              view[atTop].equalTo(
                editor.xPreviewSurface[atTop],
                constant = frame.y,
                priority = LayoutPriority(999),
              ),
              view[atWidth].equalTo(frame.w, priority = LayoutPriority(999)),
              view[atHeight].equalTo(frame.h, priority = LayoutPriority(999)),
            ]
          current.activate()
        else:
          current[0].constant = frame.x
          current[1].constant = frame.y
          current[2].constant = frame.w
          current[3].constant = frame.h
        constraints[node.id] = current
  for id, previous in editor.xCanvasConstraints:
    if not constraints.hasKey(id):
      previous.deactivate()
  editor.xCanvasConstraints = move constraints
  editor.selectPreviewView()

proc refreshStatus(editor: ResourceEditor) =
  let
    resources = editor.xDocument.xResources
    edited =
      if editor.xDocument.isDocumentEdited():
        "Unsaved changes"
      elif editor.xDocument.fileUrl().len == 0:
        "Untitled document"
      else:
        "All changes saved"
  if not resources.draftIsValid():
    editor.xStatusLabel.text = "Fix errors to update the preview · " & edited
  elif editor.xHasPreview:
    editor.xStatusLabel.text = edited
  else:
    editor.xStatusLabel.text = "Preview unavailable · " & edited

proc synchronize*(editor: ResourceEditor) =
  ## Synchronizes hierarchy, inspector, diagnostics, and the valid preview.
  let resources = editor.xDocument.xResources
  if resources != editor.xObservedResources:
    editor.clearPreview()
    editor.xHasPreview = false
    editor.xPreviewRevision = -1
    editor.xSynchronizedRevision = -1
    editor.xHierarchyRevision = -1
    editor.xSelectionFallbackId = none(ResourceId)
    editor.xObservedResources = resources
  if resources.selectedResourceIds().len == 0 and editor.xSelectionFallbackId.isSome and
      resources.contains(editor.xSelectionFallbackId.get()):
    discard resources.selectResource(editor.xSelectionFallbackId.get())
  let changed = resources.revision().int != editor.xSynchronizedRevision
  editor.rebuildPreview()
  if changed or editor.selectedResourceId() != editor.xInspectorSelection:
    editor.refreshHierarchy()
    editor.refreshPropertyRows()
    editor.xInspectorSelection = editor.selectedResourceId()
    editor.xSelectionText = editor.xSelectionLabel.text
  editor.xSynchronizedRevision = resources.revision().int
  editor.refreshDiagnosticRows()
  editor.refreshStatus()

proc resourceEditorUndoStateDidChange(
    editor: ResourceEditor, manager: UndoManager
) {.slot.} =
  if manager == editor.xDocument.undoManagerFor():
    editor.synchronize()

proc resourceEditorDocumentDidChange(
    editor: ResourceEditor, sender: ResourceEditorDocument
) {.slot.} =
  if sender == editor.xDocument:
    editor.synchronize()

proc resourceHierarchySelectionDidChange(
    editor: ResourceEditor, sender: DynamicAgent
) {.slot.} =
  if editor.xSynchronizingSelection or sender != DynamicAgent(editor.xHierarchyView):
    return
  let identifier = editor.xHierarchyView.selectedItemIdentifier()
  if identifier.len == 0:
    editor.xDocument.xResources.clearSelection()
    editor.refreshPropertyRows()
    editor.selectPreviewView()
  else:
    discard editor.selectResource(resourceId(identifier))

proc diagnosticSelectionDidChange(
    editor: ResourceEditor, sender: DynamicAgent
) {.slot.} =
  if sender != DynamicAgent(editor.xDiagnosticsView):
    return
  let index = editor.xDiagnosticsView.selectedIndex()
  if index in 0 ..< editor.xDiagnosticRows.len:
    let id = editor.xDiagnosticRows[index].resourceId
    if not id.isEmpty:
      discard editor.selectResource(id)

proc commitPropertyText*(
    editor: ResourceEditor, viewId: ResourceId, name, text: string
): ResourcePropertyEditResult =
  let
    document = editor.xDocument.xResources
    node = document.findView(viewId)
  if node.isNone:
    let edited = document.editRecordField(viewId, name, text)
    result = ResourcePropertyEditResult(
      parsed: edited.parsed,
      value: edited.value,
      message: edited.message,
      edit: edited.edit,
    )
    if result.edit.applied:
      editor.synchronize()
    return

  let
    descriptor =
      editor.xDocument.xRegistry.findViewPropertyDescriptor(node.get().kind, name)
    current = document.findViewProperty(viewId, name)
    preferred =
      if current.isSome:
        current.get().value
      else:
        ResourceValue()
    acceptedKinds =
      if descriptor.isSome:
        descriptor.get().acceptedKinds
      else:
        {preferred.kind}
    parsed = text.parseResourceValue(acceptedKinds, preferred)
  result = ResourcePropertyEditResult(
    parsed: parsed.parsed,
    value: parsed.value,
    message: parsed.message,
    edit: document.setViewProperty(
      viewId, resourceProperty(name, parsed.value), actionName = "Change " & name
    ),
  )
  if result.edit.applied:
    editor.synchronize()

proc commitSelectedPropertyText*(
    editor: ResourceEditor, name, text: string
): ResourcePropertyEditResult =
  let selected = editor.selectedResourceId()
  if selected.isSome:
    return editor.commitPropertyText(selected.get(), name, text)
  result.message = "no resource is selected"

proc nextViewIdentifier(document: ResourceDocument, kind: string): ResourceId =
  var index = 1
  while document.contains(resourceId(kind & "." & $index)):
    inc index
  result = resourceId(kind & "." & $index)

proc insertResourceKind*(
    editor: ResourceEditor, kind: ResourceNodeKind
): ResourceEditResult =
  ## Adds an identified resource using the selected view as its initial owner.
  let document = editor.xDocument.xResources
  var owner = editor.selectedViewId().get(ResourceId(""))
  let selected = editor.selectedResourceId()
  if owner.isEmpty and selected.isSome:
    let parent = document.findParentPath(document.nodePath(selected.get()))
    if parent.isSome and parent.get().kind == rnkView:
      owner = parent.get().id
  let id = document.nextViewIdentifier(kind.resourceNodeKindTitle().replace(" ", ""))
  case kind
  of rnkLayoutGuide:
    result = document.insertResource(initResourceLayoutGuide(id, owner, insets(8.0)))
  of rnkLayoutConstraint:
    var width = 180.0'f32
    let view = editor.xPreview.findView(owner)
    if not view.isNil:
      width = view.frame().w
    result = document.insertResource(
      initResourceLayoutConstraint(
        id, owner, resourceLayoutItem(owner), rlaWidth, constant = width
      )
    )
  of rnkWindow:
    result = document.insertResource(
      WindowResource(
        id: id,
        title: resourceText("Window"),
        frame: rect(80, 80, 640, 480),
        contentViewId: owner,
      )
    )
  of rnkCommand:
    result = document.insertResource(CommandResource(id: id, selector: "performClick"))
  of rnkImage:
    result = document.insertResource(ImageAssetResource(id: id, sourceKind: risFile))
  of rnkLocalization:
    result = document.insertResource(LocalizedCatalogResource(id: id, locale: "en"))
  of rnkKeyBindings:
    result = document.insertResource(KeyBindingTableResource(id: id))
  of rnkTheme:
    result = document.insertResource(ThemeFragmentResource(id: id))
  else:
    result.message = "this resource kind cannot be inserted here"
    result.error = reeResourceUnavailable
  if result.applied:
    editor.xSelectionFallbackId = selected
    discard editor.selectResource(id)
    editor.synchronize()

proc pinSelectedView*(editor: ResourceEditor, padding = 16.0'f32): ResourceEditResult =
  ## Pins all four edges to the parent in one undo group.
  let
    document = editor.xDocument.xResources
    selected = editor.selectedViewId()
  if selected.isNone:
    result.message = "select a child view to pin to its parent"
    result.error = reeResourceUnavailable
    return
  let id = selected.get()
  let parent = document.findParentPath(document.nodePath(id))
  if parent.isNone or parent.get().kind != rnkView or not document.freeformParent(id):
    result.message = "select an unconstrained child of a freeform container"
    result.error = reeParentUnavailable
    return
  let manager = document.undoManager()
  manager.beginUndoGrouping()
  try:
    discard document.setViewProperty(
      id,
      resourceProperty(
        "translatesAutoresizingMaskIntoConstraints", resourceValue(false)
      ),
    )
    for anchor in [rlaLeft, rlaTop, rlaRight, rlaBottom]:
      let constraintId = document.nextViewIdentifier($id & "." & $anchor)
      let constant =
        if anchor in {rlaLeft, rlaTop}:
          padding
        else:
          -padding
      result = document.insertResource(
        initResourceLayoutConstraint(
          constraintId,
          parent.get().id,
          resourceLayoutItem(id),
          anchor,
          resourceLayoutItem(parent.get().id),
          anchor,
          constant = constant,
        )
      )
    manager.setActionName("Pin to Parent")
  finally:
    discard manager.endUndoGrouping()
  editor.synchronize()

type SelectedViewLocation = object
  id: ResourceId
  parentId: ResourceId
  index: int
  siblingCount: int

proc selectedViewLocation(editor: ResourceEditor): Option[SelectedViewLocation] =
  let
    document = editor.xDocument.xResources
    selected = editor.selectedViewId()
  if selected.isNone:
    return
  let
    path = document.nodePath(selected.get())
    parent = document.findParentPath(path)
    parentId =
      if parent.isSome and parent.get().kind == rnkView:
        parent.get().id
      else:
        ResourceId("")
    siblings =
      if parentId.isEmpty:
        document.bundle().views
      else:
        document.view(parentId).children
  for index, sibling in siblings:
    if sibling.id == selected.get():
      return some(
        SelectedViewLocation(
          id: sibling.id, parentId: parentId, index: index, siblingCount: siblings.len
        )
      )

proc rejectedSelectedViewEdit(
    editor: ResourceEditor,
    kind: ResourceEditKind,
    message: string,
    id = ResourceId(""),
    error = reeResourceUnavailable,
): ResourceEditResult =
  ResourceEditResult(
    kind: kind,
    error: error,
    message: message,
    resourceId: id,
    revision: editor.xDocument.xResources.revision(),
  )

proc nextDuplicateIdentifier(
    document: ResourceDocument, kind: string, reserved: HashSet[ResourceId]
): ResourceId =
  var index = 1
  while true:
    result = resourceId(kind & "." & $index)
    if not document.contains(result) and result notin reserved:
      return
    inc index

proc remapDuplicateIdentifiers(
    document: ResourceDocument,
    node: var ViewNodeResource,
    replacements: var Table[ResourceId, ResourceId],
    reserved: var HashSet[ResourceId],
) =
  let previousId = node.id
  node.id = document.nextDuplicateIdentifier(node.kind, reserved)
  replacements[previousId] = node.id
  reserved.incl node.id
  for child in node.children.mitems:
    document.remapDuplicateIdentifiers(child, replacements, reserved)

proc remapDuplicateReferences(
    node: var ViewNodeResource, replacements: Table[ResourceId, ResourceId]
) =
  for property in node.properties.mitems:
    if property.value.kind == rvReference and
        replacements.hasKey(property.value.referenceValue.id):
      property.value.referenceValue.id = replacements[property.value.referenceValue.id]
  for child in node.children.mitems:
    child.remapDuplicateReferences(replacements)

proc offsetDuplicateFrame(node: var ViewNodeResource) =
  for property in node.properties.mitems:
    if property.name == "frame" and property.value.kind == rvRect:
      let frame = property.value.rectValue
      property.value.rectValue =
        rect(frame.x + 12.0'f32, frame.y + 12.0'f32, frame.w, frame.h)
      return

proc duplicateSelectedView*(editor: ResourceEditor): ResourceEditResult =
  let location = editor.selectedViewLocation()
  if location.isNone:
    return editor.rejectedSelectedViewEdit(rekInsert, "no view resource is selected")
  let
    document = editor.xDocument.xResources
    source = document.view(location.get().id)
  var
    duplicate = source
    replacements = initTable[ResourceId, ResourceId]()
    reserved = initHashSet[ResourceId]()
  document.remapDuplicateIdentifiers(duplicate, replacements, reserved)
  duplicate.remapDuplicateReferences(replacements)
  duplicate.offsetDuplicateFrame()
  result = document.insertView(
    duplicate,
    location.get().parentId,
    Natural(location.get().index + 1),
    actionName = "Duplicate View",
  )
  if result.applied:
    editor.xSelectionFallbackId = editor.selectedResourceId()
    discard document.selectResource(duplicate.id)
    editor.synchronize()

proc reorderSelectedView*(
    editor: ResourceEditor, direction: ResourceViewSiblingDirection
): ResourceEditResult =
  let location = editor.selectedViewLocation()
  if location.isNone:
    return editor.rejectedSelectedViewEdit(rekMove, "no view resource is selected")
  let targetIndex =
    case direction
    of rvsdEarlier:
      location.get().index - 1
    of rvsdLater:
      location.get().index + 1
  if targetIndex < 0 or targetIndex >= location.get().siblingCount:
    return editor.rejectedSelectedViewEdit(
      rekMove,
      "the selected view is already at that edge",
      location.get().id,
      reeUnchanged,
    )
  let document = editor.xDocument.xResources
  result = document.moveView(
    location.get().id,
    location.get().parentId,
    Natural(targetIndex),
    actionName = "Reorder View",
  )
  if result.applied:
    editor.synchronize()

proc nudgeSelectedView*(editor: ResourceEditor, delta: Point): ResourceEditResult =
  let selected = editor.selectedViewId()
  if selected.isNone:
    return editor.rejectedSelectedViewEdit(rekReplace, "no view resource is selected")
  if delta == Point():
    return editor.rejectedSelectedViewEdit(
      rekReplace, "the view position is unchanged", selected.get(), reeUnchanged
    )
  let
    document = editor.xDocument.xResources
    frameProperty = document.findViewProperty(selected.get(), "frame")
  if not document.freeformParent(selected.get()):
    return editor.rejectedSelectedViewEdit(
      rekReplace, "the selected view is positioned by its parent layout", selected.get()
    )
  if frameProperty.isNone or frameProperty.get().value.kind != rvRect:
    return editor.rejectedSelectedViewEdit(
      rekReplace, "the selected view does not have an editable frame", selected.get()
    )
  let
    previousFrame = frameProperty.get().value.rectValue
    frame = rect(
      previousFrame.x + delta.x,
      previousFrame.y + delta.y,
      previousFrame.w,
      previousFrame.h,
    )
  result = document.setViewProperty(
    selected.get(),
    resourceProperty("frame", resourceValue(frame)),
    actionName = "Move View",
  )
  if result.applied:
    editor.synchronize()

proc resizeSelectedView*(editor: ResourceEditor, delta: Size): ResourceEditResult =
  let selected = editor.selectedViewId()
  if selected.isNone:
    return editor.rejectedSelectedViewEdit(rekReplace, "no view resource is selected")
  if delta == Size():
    return editor.rejectedSelectedViewEdit(
      rekReplace, "the view size is unchanged", selected.get(), reeUnchanged
    )
  let
    document = editor.xDocument.xResources
    frameProperty = document.findViewProperty(selected.get(), "frame")
  if not document.freeformParent(selected.get()):
    return editor.rejectedSelectedViewEdit(
      rekReplace, "the selected view is sized by its parent layout", selected.get()
    )
  if frameProperty.isNone or frameProperty.get().value.kind != rvRect:
    return editor.rejectedSelectedViewEdit(
      rekReplace, "the selected view does not have an editable frame", selected.get()
    )
  let
    previousFrame = frameProperty.get().value.rectValue
    frame = rect(
      previousFrame.x,
      previousFrame.y,
      max(previousFrame.w + delta.width, 1.0'f32),
      max(previousFrame.h + delta.height, 1.0'f32),
    )
  if frame == previousFrame:
    return editor.rejectedSelectedViewEdit(
      rekReplace, "the view size is unchanged", selected.get(), reeUnchanged
    )
  result = document.setViewProperty(
    selected.get(),
    resourceProperty("frame", resourceValue(frame)),
    actionName = "Resize View",
  )
  if result.applied:
    editor.synchronize()

proc defaultViewNode(kind: string, id: ResourceId): ViewNodeResource =
  let offset = 18.0'f32
  var properties =
    @[resourceProperty("frame", resourceValue(rect(offset, offset, 180, 44)))]
  case kind
  of "view":
    properties.add resourceProperty(
      "backgroundColor", resourceValue(color(0.92, 0.95, 1.0, 1.0))
    )
  of "control":
    properties.add resourceProperty("enabled", resourceValue(true))
  of "button", "checkBox", "radioButton":
    properties.add resourceProperty("title", resourceValue(kind))
  of "textField":
    properties.add resourceProperty("stringValue", resourceValue("Editable text"))
  of "label":
    properties.add resourceProperty("stringValue", resourceValue("Label"))
  of "stackView":
    properties.add resourceProperty("orientation", resourceValue("laVertical"))
    properties.add resourceProperty("spacing", resourceValue(8.0'f32))
    properties.add resourceProperty("edgeInsets", resourceValue(insets(8.0)))
  of "switchButton":
    properties.add resourceProperty("on", resourceValue(false))
  of "progressIndicator":
    properties.add resourceProperty("value", resourceValue(0.5'f32))
  of "box":
    properties.add resourceProperty("title", resourceValue("Group"))
  of "splitView":
    properties.add resourceProperty("splitAxis", resourceValue("laHorizontal"))
  else:
    discard
  result = initViewNodeResource(id, kind, properties)

proc cascadeNewViewFrame(
    document: ResourceDocument, parentId: ResourceId, node: var ViewNodeResource
) =
  let freeformContainer =
    parentId.isEmpty or document.view(parentId).kind in ["view", "box"]
  if not freeformContainer:
    return
  let siblings =
    if parentId.isEmpty:
      document.bundle().views
    else:
      document.view(parentId).children
  var attempt = 0
  while true:
    let offset = 18.0'f32 + attempt.float32 * 24.0'f32
    var occupied = false
    for sibling in siblings:
      let frame = document.findViewProperty(sibling.id, "frame")
      if frame.isSome and frame.get().value.kind == rvRect and
          frame.get().value.rectValue.x == offset and
          frame.get().value.rectValue.y == offset:
        occupied = true
        break
    if not occupied:
      for property in node.properties.mitems:
        if property.name == "frame" and property.value.kind == rvRect:
          let previous = property.value.rectValue
          property.value.rectValue = rect(offset, offset, previous.w, previous.h)
          return
      return
    inc attempt

proc insertViewKind*(editor: ResourceEditor, kind: string): ResourceEditResult =
  let document = editor.xDocument.xResources
  if not editor.xDocument.xRegistry.hasViewKind(kind):
    return ResourceEditResult(
      kind: rekInsert,
      error: reeResourceUnavailable,
      message: "view kind '" & kind & "' is unavailable",
      revision: document.revision(),
    )
  let id = document.nextViewIdentifier(kind)
  var parent = ResourceId("")
  let selected = editor.selectedResourceId()
  if selected.isSome:
    let path = document.findNodePath(selected.get())
    if path.isSome and path.get().kind == rnkView:
      let selectedView = document.view(selected.get())
      if selectedView.kind in ["view", "stackView", "box", "splitView"]:
        parent = selected.get()
      else:
        let parentPath = document.findParentPath(path.get())
        if parentPath.isSome and parentPath.get().kind == rnkView:
          parent = parentPath.get().id
    elif path.isSome:
      let parentPath = document.findParentPath(path.get())
      if parentPath.isSome and parentPath.get().kind == rnkView:
        parent = parentPath.get().id
  var node = kind.defaultViewNode(id)
  document.cascadeNewViewFrame(parent, node)
  result = document.insertView(node, parent)
  if result.applied:
    editor.xSelectionFallbackId = editor.selectedResourceId()
    discard document.selectResource(id)
    editor.synchronize()

proc removeSelectedView*(editor: ResourceEditor): ResourceEditResult =
  let
    document = editor.xDocument.xResources
    selected = editor.selectedResourceId()
  if selected.isNone:
    return ResourceEditResult(
      kind: rekRemove,
      error: reeResourceUnavailable,
      message: "no view resource is selected",
      revision: document.revision(),
    )
  let path = document.findNodePath(selected.get())
  if path.isSome and path.get().kind != rnkView:
    let parent = document.findParentPath(path.get())
    result = document.removeResource(selected.get())
    if result.applied:
      if parent.isSome:
        discard document.selectResource(parent.get().id)
      editor.synchronize()
    return
  let
    parent = document.findParentPath(path.get())
    parentId =
      if parent.isSome and parent.get().kind == rnkView:
        parent.get().id
      else:
        ResourceId("")
    siblings =
      if parentId.isEmpty:
        document.bundle().views
      else:
        document.view(parentId).children
  var nextSelection = ResourceId("")
  for index, sibling in siblings:
    if sibling.id != selected.get():
      continue
    if index + 1 < siblings.len:
      nextSelection = siblings[index + 1].id
    elif index > 0:
      nextSelection = siblings[index - 1].id
    break
  var removedIds = initHashSet[ResourceId]()
  proc collectIds(node: ViewNodeResource) =
    removedIds.incl node.id
    for child in node.children:
      collectIds(child)

  collectIds(document.view(selected.get()))
  var guides, constraints: seq[ResourceId]
  for guide in document.bundle().layoutGuides:
    if guide.owningViewId in removedIds:
      removedIds.incl guide.id
      guides.add guide.id
  for constraint in document.bundle().layoutConstraints:
    if constraint.owningViewId in removedIds or constraint.firstItem.id in removedIds or
        constraint.secondItem.id in removedIds:
      constraints.add constraint.id
  let manager = document.undoManager()
  manager.beginUndoGrouping()
  try:
    for id in constraints:
      discard document.removeResource(id)
    for id in guides:
      discard document.removeResource(id)
    result = document.removeView(selected.get(), actionName = "Delete View")
    manager.setActionName("Delete View")
  finally:
    discard manager.endUndoGrouping()
  if not result.applied:
    return
  if not nextSelection.isEmpty and document.selectResource(nextSelection):
    discard
  elif parent.isSome and document.selectResource(parent.get().id):
    discard
  else:
    document.clearSelection()
    for candidate in document:
      if candidate.kind == rnkView:
        discard document.selectResource(candidate.id)
        break
  editor.synchronize()

proc propertyChoiceTexts(row: ResourceEditorPropertyRow): seq[string] =
  for value in row.descriptor.options:
    result.add value.formatResourceValue()

proc newPropertyCheckBox(
    editor: ResourceEditor, viewId: ResourceId, row: ResourceEditorPropertyRow
): Button =
  result = newCheckBox("")
  if row.value.isSome and row.value.get().kind == rvBool and row.value.get().boolValue:
    result.state = bsOn
  let
    checkBox = result
    propertyName = row.descriptor.name
    action = nimkitSelectors.actionSelector("resourceEditorToggle" & propertyName)
  checkBox.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      discard
        editor.commitPropertyText(viewId, propertyName, $(checkBox.state() == bsOn)),
  )
  checkBox.action = action

proc newPropertyComboBox(
    editor: ResourceEditor, viewId: ResourceId, row: ResourceEditorPropertyRow
): ComboBox =
  let options = row.propertyChoiceTexts()
  result = newComboBox(options)
  result.editable = false
  let selected = options.find(row.text)
  if selected >= 0:
    result.selectedIndex = selected
  let
    comboBox = result
    propertyName = row.descriptor.name
    action = nimkitSelectors.actionSelector("resourceEditorChoose" & propertyName)
  comboBox.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      let index = comboBox.indexOfSelectedItem()
      if index >= 0:
        discard
          editor.commitPropertyText(viewId, propertyName, comboBox.itemAtIndex(index))
    ,
  )
  comboBox.action = action

proc newPropertyColorWell(
    editor: ResourceEditor, viewId: ResourceId, row: ResourceEditorPropertyRow
): PopupColorWell =
  let selectedColor =
    if row.value.isSome and row.value.get().kind == rvColor:
      row.value.get().colorValue
    else:
      color(0.0, 0.0, 0.0, 0.0)
  var choices = defaultPopupColorChoices()
  var found = false
  for choice in choices:
    if choice.color == selectedColor:
      found = true
  if not found:
    choices.insert(initPopupColorChoice("Custom", selectedColor), 0)
  result = newPopupColorWell(choices, selectedColor)
  let
    colorWell = result
    propertyName = row.descriptor.name
    action = nimkitSelectors.actionSelector("resourceEditorChoose" & propertyName)
  colorWell.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.commitPropertyText(
        viewId, propertyName, resourceValue(colorWell.color()).formatResourceValue()
      ),
  )
  colorWell.action = action

proc propertyEditorView(editor: ResourceEditor, row: ResourceEditorPropertyRow): View =
  let selected = editor.selectedResourceId()
  if selected.isNone:
    return
  case row.propertyEditorKind()
  of rpekCheckBox:
    View(editor.newPropertyCheckBox(selected.get(), row))
  of rpekComboBox:
    View(editor.newPropertyComboBox(selected.get(), row))
  of rpekColorWell:
    View(editor.newPropertyColorWell(selected.get(), row))
  of rpekReadOnly, rpekText:
    nil

protocol ResourceEditorTableSource of TableViewDataSource:
  method numberOfRows(editor: ResourceEditor, tableView: TableView): int =
    if tableView == editor.xPropertyInspector:
      editor.xPropertyRows.len
    elif tableView == editor.xDiagnosticsView:
      editor.xDiagnosticRows.len
    else:
      0

  method textForCell(
      editor: ResourceEditor, tableView: TableView, row: int, column: TableColumn
  ): string =
    if tableView == editor.xPropertyInspector and row in 0 ..< editor.xPropertyRows.len:
      let property = editor.xPropertyRows[row]
      case column.identifier()
      of "property": property.descriptor.name
      of "type": property.descriptor.nimTypeName
      of "value": property.text
      else: ""
    elif tableView == editor.xDiagnosticsView and row in 0 ..< editor.xDiagnosticRows.len:
      let diagnostic = editor.xDiagnosticRows[row]
      case column.identifier()
      of "severity":
        $diagnostic.severity
      of "path":
        diagnostic.path
      of "message":
        diagnostic.code & ": " & diagnostic.message
      else:
        ""
    else:
      ""

  method identifierForRow(
      editor: ResourceEditor, tableView: TableView, row: int
  ): string =
    if tableView == editor.xPropertyInspector and row in 0 ..< editor.xPropertyRows.len:
      editor.xPropertyRows[row].descriptor.name
    elif tableView == editor.xDiagnosticsView and row in 0 ..< editor.xDiagnosticRows.len:
      let diagnostic = editor.xDiagnosticRows[row]
      diagnostic.path & ":" & diagnostic.code
    else:
      ""

protocol ResourceEditorTableDelegate of TableViewDelegate:
  method validationErrorForCell(
      editor: ResourceEditor,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ): string =
    let selected = editor.selectedResourceId()
    if tableView == editor.xPropertyInspector and column.identifier() == "value" and
        row in 0 ..< editor.xPropertyRows.len and selected.isSome and
        editor.xDocument.xResources.nodePath(selected.get()).kind != rnkView:
      let checked = editor.xDocument.xResources.editRecordField(
        selected.get(), editor.xPropertyRows[row].descriptor.name, value, commit = false
      )
      if not checked.parsed:
        return checked.message

  method viewForCell(
      editor: ResourceEditor, tableView: TableView, row: int, column: TableColumn
  ): View =
    if tableView == editor.xPropertyInspector and column.identifier() == "value" and
        row in 0 ..< editor.xPropertyRows.len:
      return editor.propertyEditorView(editor.xPropertyRows[row])

  method hitPolicyForCell(
      editor: ResourceEditor,
      tableView: TableView,
      row: int,
      column: TableColumn,
      target: View,
      event: MouseEvent,
  ): CellHitPolicy =
    discard target
    discard event
    if tableView == editor.xPropertyInspector and column.identifier() == "value" and
        row in 0 ..< editor.xPropertyRows.len and
        editor.xPropertyRows[row].propertyEditorKind() in
        {rpekCheckBox, rpekComboBox, rpekColorWell}:
      return chpSelectAndTrack
    chpDefault

  method shouldEditCell(
      editor: ResourceEditor, tableView: TableView, row: int, column: TableColumn
  ): bool =
    tableView == editor.xPropertyInspector and column.identifier() == "value" and
      row in 0 ..< editor.xPropertyRows.len and
      editor.xPropertyRows[row].propertyEditorKind() == rpekText

  method didCommitEditingCell(
      editor: ResourceEditor,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ) =
    if tableView != editor.xPropertyInspector or column.identifier() != "value" or
        row notin 0 ..< editor.xPropertyRows.len:
      return
    let selected = editor.selectedResourceId()
    if selected.isSome:
      discard editor.commitPropertyText(
        selected.get(), editor.xPropertyRows[row].descriptor.name, value
      )

proc configureTable(tableView: TableView) =
  tableView.showsHeader = true
  tableView.tableHeaderHeight = 26.0
  tableView.rowHeight = 26.0
  tableView.selectionMode = tsmSingle
  tableView.usesAlternatingRowBackgrounds = true
  tableView.showsRowSeparators = true

proc configureHierarchy(outline: OutlineView) =
  outline.outlineColumn().title = "Resource"
  outline.outlineColumn().width = 244.0
  outline.configureTable()

proc configurePropertyInspector(tableView: TableView) =
  tableView.configureTable()
  tableView.addColumn(newTableColumn("property", "Property", width = 124.0))
  tableView.addColumn(newTableColumn("type", "Type", width = 92.0))
  tableView.addColumn(newTableColumn("value", "Resource Value", width = 210.0))

proc configureDiagnostics(tableView: TableView) =
  tableView.configureTable()
  tableView.addColumn(newTableColumn("severity", "Level", width = 62.0))
  tableView.addColumn(newTableColumn("path", "Path", width = 146.0))
  tableView.addColumn(newTableColumn("message", "Diagnostic", width = 260.0))

proc newPaletteButton(editor: ResourceEditor, kind: string): Button =
  let action = nimkitSelectors.actionSelector("resourceEditorInsert" & kind)
  let title =
    case kind
    of "checkBox":
      "Checkbox"
    of "radioButton":
      "Radio Button"
    of "textField":
      "Text Field"
    of "imageView":
      "Image"
    of "stackView":
      "Stack"
    of "switchButton":
      "Switch"
    of "progressIndicator":
      "Progress"
    of "splitView":
      "Split View"
    else:
      kind.capitalizeAscii()
  result = newButton(title)
  result.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.insertViewKind(kind),
  )
  result.action = action
  result.toolTip = "Insert a " & kind & " resource"

proc configurePalette(editor: ResourceEditor) =
  editor.xPaletteView.edgeInsets = insets(4.0)
  editor.xPaletteView.spacing[dcol] = 6.0
  editor.xPaletteView.spacing[drow] = 6.0
  for index, kind in editor.xPaletteKinds:
    let button = editor.newPaletteButton(kind)
    editor.xPaletteButtons.add button
    editor.xPaletteView.addSubview(button, row = index div 2, col = index mod 2)
  editor.xPaletteView.frame =
    rect(0, 0, 236, ((editor.xPaletteKinds.len + 1) div 2).float32 * 34 + 8)

proc saveEditorDocument*(editor: ResourceEditor, choosePath = false): bool =
  ## Commits the current field and prompts for a destination for untitled documents.
  if editor.xPropertyInspector.editingState().active and
      not editor.xPropertyInspector.commitEditingCell(""):
    return
  if choosePath or editor.xDocument.fileUrl().len == 0:
    let panel = newSavePanel()
    panel.allowedFileTypes = @["cbor"]
    panel.nameFieldStringValue =
      if editor.xDocument.fileUrl().len == 0:
        "Untitled Resources.cbor"
      else:
        editor.xDocument.fileUrl().localFilePath().extractFilename()
    panel.directoryUrl =
      if editor.xDocument.fileUrl().len == 0:
        getCurrentDir()
      else:
        editor.xDocument.fileUrl().localFilePath().parentDir()
    if sharedApplication().runModal(panel) == PanelResponseOk:
      result = editor.xDocument.saveAs(panel.selectedUrl(), "cbor")
  else:
    result = editor.xDocument.save()
  editor.synchronize()

proc configureToolbar(
    editor: ResourceEditor,
    saveButton, undoButton, redoButton, deleteButton, duplicateButton,
      moveEarlierButton, moveLaterButton: Button,
) =
  let
    saveAction = nimkitSelectors.actionSelector("resourceEditorSave")
    undoAction = nimkitSelectors.actionSelector("resourceEditorUndo")
    redoAction = nimkitSelectors.actionSelector("resourceEditorRedo")
    deleteAction = nimkitSelectors.actionSelector("resourceEditorDelete")
    duplicateAction = nimkitSelectors.actionSelector("resourceEditorDuplicate")
    moveEarlierAction = nimkitSelectors.actionSelector("resourceEditorMoveEarlier")
    moveLaterAction = nimkitSelectors.actionSelector("resourceEditorMoveLater")
  saveButton.target = newActionTarget(
    saveAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.saveEditorDocument(),
  )
  saveButton.action = saveAction
  undoButton.target = newActionTarget(
    undoAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.xDocument.undoManagerFor().performUndo(),
  )
  undoButton.action = undoAction
  redoButton.target = newActionTarget(
    redoAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.xDocument.undoManagerFor().performRedo(),
  )
  redoButton.action = redoAction
  deleteButton.target = newActionTarget(
    deleteAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.removeSelectedView(),
  )
  deleteButton.action = deleteAction
  duplicateButton.target = newActionTarget(
    duplicateAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.duplicateSelectedView(),
  )
  duplicateButton.action = duplicateAction
  duplicateButton.toolTip = "Duplicate the selected view (Shortcut-D)"
  moveEarlierButton.target = newActionTarget(
    moveEarlierAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.reorderSelectedView(rvsdEarlier),
  )
  moveEarlierButton.action = moveEarlierAction
  moveEarlierButton.toolTip = "Move the selected view earlier (Shortcut-Up)"
  moveLaterButton.target = newActionTarget(
    moveLaterAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.reorderSelectedView(rvsdLater),
  )
  moveLaterButton.action = moveLaterAction
  moveLaterButton.toolTip = "Move the selected view later (Shortcut-Down)"

proc newResourceEditor*(document: ResourceEditorDocument): ResourceEditor =
  let
    previewSurface = ResourceEditorPreviewSurface()
    hierarchyView = ResourceEditorHierarchyView()
  initViewFields(previewSurface)
  initOutlineViewFields(hierarchyView)
  discard hierarchyView.withProtocol(ResourceEditorHierarchyEvents)
  result = ResourceEditor(
    xDocument: document,
    xRootView: newView(),
    xHierarchyView: hierarchyView,
    xPaletteView: newGridView(),
    xPropertyInspector: newTableView(),
    xDiagnosticsView: newTableView(),
    xPreviewSurface: previewSurface,
    xStatusLabel: newStatusLabel(),
    xSelectionLabel: newStatusLabel(),
    xDiagnosticsTitle: newHeadingLabel("Diagnostics"),
    xPreview: newResourcePreview(
      document.xRegistry, document.xInstantiationContext, document.xValidationOptions
    ),
    xPreviewRevision: -1,
  )
  initResponder(result)
  previewSurface.xEditor = result
  hierarchyView.xEditor = result
  discard previewSurface.withProtocol(ResourceEditorPreviewSurfaceEvents)
  discard previewSurface.withProtocol(ResourceEditorPreviewSurfacePicking)
  discard previewSurface.withProtocol(ResourceEditorPreviewSurfaceLayout)
  discard result.withProtocol(ResourceEditorTableSource)
  discard result.withProtocol(ResourceEditorTableDelegate)

  for kind in ResourceEditorPaletteKinds:
    if document.xRegistry.hasViewKind(kind):
      result.xPaletteKinds.add kind
  for descriptor in document.xRegistry.viewKinds():
    if descriptor.kind notin result.xPaletteKinds:
      result.xPaletteKinds.add descriptor.kind

  result.xHierarchyView.configureHierarchy()
  result.xPropertyInspector.configurePropertyInspector()
  result.xDiagnosticsView.configureDiagnostics()
  result.xPropertyInspector.dataSource = result
  result.xPropertyInspector.delegate = result
  result.xDiagnosticsView.dataSource = result
  result.xDiagnosticsView.delegate = result
  result.xPreviewSurface.backgroundColor = color(0.96, 0.97, 0.99, 1.0)
  result.xPreviewSurface.appearance = initAppearance(initAquaTheme())
  result.xPreviewSurface.clipsToBounds = true
  result.xPreviewSurface.accessibilityRole = arGroup
  result.xPreviewSurface.accessibilityLabel = "Resource preview"

  let
    hierarchyTitle = newHeadingLabel("Resource Hierarchy")
    paletteTitle = newHeadingLabel("View Palette")
    previewTitle = newHeadingLabel("Preview")
    inspectorTitle = newHeadingLabel("Resource Inspector")
    saveButton = newButton("Save")
    undoButton = newButton("Undo")
    redoButton = newButton("Redo")
    deleteButton = newButton("Delete")
    duplicateButton = newButton("Duplicate")
    moveEarlierButton = newButton("Up")
    moveLaterButton = newButton("Down")
    interactButton = newCheckBox("Interact")
    openButton = newButton("Open…")
    saveAsButton = newButton("Save As…")
    pinButton = newButton("Pin to Parent")
    resourcePicker = newComboBox(
      [
        "Layout Guide", "Layout Constraint", "Window", "Command", "Image",
        "Localization", "Key Bindings", "Theme",
      ]
    )
    addResourceButton = newButton("Add")
    paletteScroll = newScrollView(documentView = result.xPaletteView)
    themePicker = newComboBox(
      ["Aqua", "Dark BSD", "macOS", "macOS Dark", "Nebula", "Peachy", "Synthwave83"]
    )

  let editor = result
  themePicker.editable = false
  themePicker.selectedIndex = 0
  themePicker.toolTip = "Preview theme (does not change the resource document)"
  let themeAction = nimkitSelectors.actionSelector("resourceEditorPreviewTheme")
  themePicker.target = newActionTarget(
    themeAction,
    proc(sender: DynamicAgent) =
      let names =
        ["aqua", "darkbsd", "macos", "macos-dark", "nebula", "peachy", "synthwave83"]
      let index = themePicker.indexOfSelectedItem()
      if index in 0 ..< names.len:
        editor.xPreviewSurface.appearance =
          initAppearance(initThemeByName(names[index]))
    ,
  )
  themePicker.action = themeAction
  let interactAction = nimkitSelectors.actionSelector("resourceEditorInteract")
  interactButton.target = newActionTarget(
    interactAction,
    proc(sender: DynamicAgent) =
      editor.interactivePreview = Button(sender).state() == bsOn,
  )
  interactButton.action = interactAction
  interactButton.toolTip = "Run preview controls; uncheck to select and position views"
  resourcePicker.editable = false
  resourcePicker.selectedIndex = 0
  let addAction = nimkitSelectors.actionSelector("resourceEditorAddResource")
  addResourceButton.target = newActionTarget(
    addAction,
    proc(sender: DynamicAgent) =
      let kinds = [
        rnkLayoutGuide, rnkLayoutConstraint, rnkWindow, rnkCommand, rnkImage,
        rnkLocalization, rnkKeyBindings, rnkTheme,
      ]
      let index = resourcePicker.indexOfSelectedItem()
      if index in 0 ..< kinds.len:
        discard editor.insertResourceKind(kinds[index])
    ,
  )
  addResourceButton.action = addAction
  let pinAction = nimkitSelectors.actionSelector("resourceEditorPin")
  pinButton.target = newActionTarget(
    pinAction,
    proc(sender: DynamicAgent) =
      let edit = editor.pinSelectedView()
      if not edit.applied:
        editor.xStatusLabel.text = edit.message
    ,
  )
  pinButton.action = pinAction
  let saveAsAction = nimkitSelectors.actionSelector("resourceEditorSaveAs")
  saveAsButton.target = newActionTarget(
    saveAsAction,
    proc(sender: DynamicAgent) =
      discard editor.saveEditorDocument(choosePath = true),
  )
  saveAsButton.action = saveAsAction
  let openAction = nimkitSelectors.actionSelector("resourceEditorOpen")
  openButton.target = newActionTarget(
    openAction,
    proc(sender: DynamicAgent) =
      let panel = newOpenPanel()
      panel.allowedFileTypes = @["cbor"]
      if sharedApplication().runModal(panel) == PanelResponseOk:
        let opened = newResourceEditorDocument()
        if opened.readFromFileUrl(panel.selectedUrl()):
          for path in opened.resources():
            discard opened.resources().selectResource(path.id)
            break
          discard opened.showWindows(sharedApplication())
        else:
          editor.xStatusLabel.text = "Could not open the resource file"
    ,
  )
  openButton.action = openAction

  result.configurePalette()
  paletteScroll.hasHorizontalScroller = false
  paletteScroll.hasVerticalScroller = true
  paletteScroll.autohidesScrollers = true
  result.xUndoButton = undoButton
  result.xRedoButton = redoButton
  result.xDuplicateButton = duplicateButton
  result.xMoveEarlierButton = moveEarlierButton
  result.xMoveLaterButton = moveLaterButton
  result.configureToolbar(
    saveButton, undoButton, redoButton, deleteButton, duplicateButton,
    moveEarlierButton, moveLaterButton,
  )
  result.xRootView.addSubviews(
    autoNames(
      hierarchyTitle, result.xHierarchyView, paletteTitle, paletteScroll, previewTitle,
      result.xStatusLabel, result.xPreviewSurface, inspectorTitle,
      result.xSelectionLabel, result.xPropertyInspector, result.xDiagnosticsTitle,
      result.xDiagnosticsView, saveButton, undoButton, redoButton, deleteButton,
      duplicateButton, moveEarlierButton, moveLaterButton, interactButton, openButton,
      saveAsButton, pinButton, resourcePicker, addResourceButton, themePicker,
    )
  )

  activateConstraints:
    interactButton[atTop] == saveButton[atTop]
    interactButton[atLeft] == result.xRootView[atLeft] + 18.0
    interactButton[atWidth] == 110.0
    interactButton[atHeight] == saveButton[atHeight]
    openButton[atTop] == saveButton[atTop]
    openButton[atLeft] == interactButton[atRight] + 8.0
    openButton[atWidth] == 70.0
    openButton[atHeight] == saveButton[atHeight]
    saveAsButton[atTop] == saveButton[atTop]
    saveAsButton[atLeft] == openButton[atRight] + 8.0
    saveAsButton[atWidth] == 90.0
    saveAsButton[atHeight] == saveButton[atHeight]
    pinButton[atTop] == saveButton[atTop]
    pinButton[atLeft] == saveAsButton[atRight] + 8.0
    pinButton[atWidth] == 110.0
    pinButton[atHeight] == saveButton[atHeight]
    themePicker[atTop] == saveButton[atTop]
    themePicker[atLeft] == pinButton[atRight] + 12.0
    themePicker[atWidth] == 140.0
    themePicker[atHeight] == saveButton[atHeight]
    saveButton[atTop] == result.xRootView[atTop] + 14.0
    saveButton[atRight] == result.xRootView[atRight] - 18.0
    saveButton[atWidth] == 72.0
    saveButton[atHeight] == 30.0
    redoButton[atTop] == saveButton[atTop]
    redoButton[atRight] == saveButton[atLeft] - 8.0
    redoButton[atWidth] == 72.0
    redoButton[atHeight] == saveButton[atHeight]
    undoButton[atTop] == saveButton[atTop]
    undoButton[atRight] == redoButton[atLeft] - 8.0
    undoButton[atWidth] == 72.0
    undoButton[atHeight] == saveButton[atHeight]
    deleteButton[atTop] == saveButton[atTop]
    deleteButton[atRight] == undoButton[atLeft] - 8.0
    deleteButton[atWidth] == 72.0
    deleteButton[atHeight] == saveButton[atHeight]
    duplicateButton[atTop] == saveButton[atTop]
    duplicateButton[atRight] == deleteButton[atLeft] - 8.0
    duplicateButton[atWidth] == 88.0
    duplicateButton[atHeight] == saveButton[atHeight]
    moveLaterButton[atTop] == saveButton[atTop]
    moveLaterButton[atRight] == duplicateButton[atLeft] - 8.0
    moveLaterButton[atWidth] == 64.0
    moveLaterButton[atHeight] == saveButton[atHeight]
    moveEarlierButton[atTop] == saveButton[atTop]
    moveEarlierButton[atRight] == moveLaterButton[atLeft] - 8.0
    moveEarlierButton[atWidth] == 64.0
    moveEarlierButton[atHeight] == saveButton[atHeight]

    hierarchyTitle[atTop] == saveButton[atBottom] + 12.0
    hierarchyTitle[atLeft] == result.xRootView[atLeft] + 18.0
    hierarchyTitle[atWidth] == 250.0
    hierarchyTitle[atHeight] == 24.0
    result.xHierarchyView[atTop] == hierarchyTitle[atBottom] + 6.0
    result.xHierarchyView[atLeft] == hierarchyTitle[atLeft]
    result.xHierarchyView[atWidth] == hierarchyTitle[atWidth]
    result.xHierarchyView[atBottom] == paletteTitle[atTop] - 10.0
    paletteTitle[atLeft] == hierarchyTitle[atLeft]
    paletteTitle[atWidth] == hierarchyTitle[atWidth]
    paletteTitle[atBottom] == paletteScroll[atTop] - 6.0
    paletteTitle[atHeight] == 24.0
    paletteScroll[atLeft] == hierarchyTitle[atLeft]
    paletteScroll[atWidth] == hierarchyTitle[atWidth]
    paletteScroll[atBottom] == resourcePicker[atTop] - 8.0
    paletteScroll[atHeight] == 220.0
    resourcePicker[atLeft] == hierarchyTitle[atLeft]
    resourcePicker[atWidth] == 180.0
    resourcePicker[atBottom] == result.xRootView[atBottom] - 18.0
    resourcePicker[atHeight] == 30.0
    addResourceButton[atLeft] == resourcePicker[atRight] + 6.0
    addResourceButton[atRight] == hierarchyTitle[atRight]
    addResourceButton[atTop] == resourcePicker[atTop]
    addResourceButton[atHeight] == resourcePicker[atHeight]

    previewTitle[atTop] == hierarchyTitle[atTop]
    previewTitle[atLeft] == result.xHierarchyView[atRight] + 18.0
    previewTitle[atRight] == inspectorTitle[atLeft] - 18.0
    previewTitle[atHeight] == hierarchyTitle[atHeight]
    result.xStatusLabel[atTop] == previewTitle[atBottom] + 4.0
    result.xStatusLabel[atLeft] == previewTitle[atLeft]
    result.xStatusLabel[atRight] == previewTitle[atRight]
    result.xStatusLabel[atHeight] == 22.0
    result.xPreviewSurface[atTop] == result.xStatusLabel[atBottom] + 8.0
    result.xPreviewSurface[atLeft] == previewTitle[atLeft]
    result.xPreviewSurface[atRight] == previewTitle[atRight]
    result.xPreviewSurface[atBottom] == result.xRootView[atBottom] - 18.0

    inspectorTitle[atTop] == hierarchyTitle[atTop]
    inspectorTitle[atRight] == result.xRootView[atRight] - 18.0
    inspectorTitle[atWidth] == 390.0
    inspectorTitle[atHeight] == hierarchyTitle[atHeight]
    result.xSelectionLabel[atTop] == inspectorTitle[atBottom] + 4.0
    result.xSelectionLabel[atLeft] == inspectorTitle[atLeft]
    result.xSelectionLabel[atRight] == inspectorTitle[atRight]
    result.xSelectionLabel[atHeight] == 22.0
    result.xPropertyInspector[atTop] == result.xSelectionLabel[atBottom] + 6.0
    result.xPropertyInspector[atLeft] == inspectorTitle[atLeft]
    result.xPropertyInspector[atRight] == inspectorTitle[atRight]
    result.xPropertyInspector[atBottom] == result.xDiagnosticsTitle[atTop] - 10.0
    result.xDiagnosticsTitle[atLeft] == inspectorTitle[atLeft]
    result.xDiagnosticsTitle[atRight] == inspectorTitle[atRight]
    result.xDiagnosticsTitle[atBottom] == result.xDiagnosticsView[atTop] - 6.0
    result.xDiagnosticsTitle[atHeight] == 24.0
    result.xDiagnosticsView[atLeft] == inspectorTitle[atLeft]
    result.xDiagnosticsView[atRight] == inspectorTitle[atRight]
    result.xDiagnosticsView[atBottom] == result.xRootView[atBottom] - 18.0
    result.xDiagnosticsView[atHeight] == 190.0

  result.xHierarchyView.connect(
    selectionDidChange, result, resourceHierarchySelectionDidChange
  )
  result.xDiagnosticsView.connect(
    selectionDidChange, result, diagnosticSelectionDidChange
  )
  document.undoManagerFor().connect(
    stateDidChange, result, resourceEditorUndoStateDidChange
  )
  document.connect(resourcesDidChange, result, resourceEditorDocumentDidChange)
  result.synchronize()

proc newResourceEditorWindow*(editor: ResourceEditor): Window =
  result = newWindow(editor.xDocument.displayName(), frame = rect(90, 80, 1260, 760))
  result.setContentView(editor.xRootView)
  discard result.makeFirstResponder(editor.xHierarchyView)
