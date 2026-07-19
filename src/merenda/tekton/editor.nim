## Tekton's interactive resource-document editor.

import std/[algorithm, options, os, strutils]

import sigils/[core, selectors]

import merenda/nimkit/accessibility/accessibility
import merenda/nimkit/app/[application, documents, windowcontrollers, windows]
import merenda/nimkit/containers/[gridviews, outlineviews, tableviews]
import merenda/nimkit/controls/[buttons, colorwells, comboboxes]
import merenda/nimkit/debug/[selectionrings, viewselection]
import merenda/nimkit/foundation/events
import merenda/nimkit/foundation/[selectors as nimkitSelectors, types, undomanagers]
import
  merenda/nimkit/resources/[
    resrccbor, resrcconstruction, resrccore, resrcdocument, resrcregistry,
    resrcvalidation,
  ]
import merenda/nimkit/text/textfields
import merenda/nimkit/themes
import merenda/nimkit/view/views
import merenda/tekton/[preview, valueediting]

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

  ResourceEditorDocument* = ref object of Document
    xResources: ResourceDocument
    xRegistry: ResourceRegistry
    xInstantiationContext: ResourceInstantiationContext
    xValidationOptions: ResourceValidationOptions
    xIoDiagnostics: ResourceDiagnostics

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
    xPropertyRows: seq[ResourceEditorPropertyRow]
    xDiagnosticRows: seq[ResourceDiagnostic]
    xPreview: ResourcePreview
    xPreviewDiagnostics: ResourceDiagnostics
    xPreviewRevision: int
    xHasPreview: bool
    xSynchronizingSelection: bool
    xPreviewSelection: ViewSelection
    xSelectionRing: SelectionRing
    xHoverRing: SelectionRing
    xHoverTokens: seq[SwizzleToken]
    xHoveredResourceId: Option[ResourceId]
    xHoverGeometry: ResourcePreviewGeometry

  ResourceEditorPreviewSurface = ref object of View
    xEditor: ResourceEditor

  ResourceEditorHierarchyView = ref object of OutlineView
    xEditor: ResourceEditor

const
  ResourceEditorDocumentType* = "nimkit-resource"
  ResourceEditorPaletteKinds* = [
    "view", "control", "button", "checkBox", "radioButton", "textField", "label",
    "imageView", "stackView", "switchButton", "progressIndicator", "box", "splitView",
  ]

proc newResourceEditor*(document: ResourceEditorDocument): ResourceEditor
proc newResourceEditorWindow*(editor: ResourceEditor): Window
proc synchronize*(editor: ResourceEditor)
proc removeSelectedView*(editor: ResourceEditor): ResourceEditResult {.discardable.}
proc updatePreviewHover*(
  editor: ResourceEditor, point: Point
): ResourcePreviewHit {.discardable.}

proc clearPreviewHover*(editor: ResourceEditor)

protocol ResourceEditorDocumentEvents:
  proc resourcesDidChange*(
    document: ResourceEditorDocument, sender: ResourceEditorDocument
  ) {.signal.}

func localFilePath(fileUrl: string): string =
  result = fileUrl
  let queryStart = result.find('?')
  if queryStart >= 0:
    result.setLen(queryStart)
  let fragmentStart = result.find('#')
  if fragmentStart >= 0:
    result.setLen(fragmentStart)
  if result.startsWith("file://"):
    result = result[7 .. ^1]

proc replaceResources(
    document: ResourceEditorDocument, bundle: sink ResourceBundle, assetBasePath = ""
) =
  let manager = document.undoManagerFor()
  manager.clearAll()
  if assetBasePath.len > 0 and document.xValidationOptions.assetBasePath.len == 0:
    document.xValidationOptions.assetBasePath = assetBasePath
  if assetBasePath.len > 0 and document.xInstantiationContext.assetBasePath.len == 0:
    document.xInstantiationContext.assetBasePath = assetBasePath
  document.xResources = newResourceDocument(
    bundle, document.xRegistry, document.xValidationOptions, manager
  )
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
  )
  result.initDocument(
    fileUrl = fileUrl,
    fileType = if fileUrl.len == 0: ResourceEditorDocumentType else: "",
    fileName = if fileUrl.len == 0: "Untitled Resources.cbor" else: "",
  )
  result.xResources =
    newResourceDocument(bundle, registry, validationOptions, result.undoManagerFor())
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
  for path in document:
    paths.add path

  var items: seq[OutlineItem]
  for path in paths:
    let parent = document.findParentPath(path)
    var expandable = false
    for candidate in paths:
      if document.findParentPath(candidate) == some(path):
        expandable = true
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
    editor.xHierarchyView.outlineItems = items
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
    editor.xPropertyInspector.reloadData()
    return

  let node = document.view(id)
  editor.xSelectionLabel.text = node.kind & "  " & $id & "  ·  " & nodePath

  var knownNames: seq[string]
  for descriptor in editor.xDocument.xRegistry.viewProperties(node.kind):
    let property = document.findViewProperty(id, descriptor.name)
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
  editor.xDiagnosticRows.setLen(0)
  for diagnostic in editor.xDocument.xResources.diagnostics():
    editor.xDiagnosticRows.add diagnostic
  for diagnostic in editor.xDocument.xIoDiagnostics:
    editor.xDiagnosticRows.add diagnostic
  for diagnostic in editor.xPreviewDiagnostics:
    editor.xDiagnosticRows.add diagnostic
  editor.xDiagnosticsTitle.text = "Diagnostics (" & $editor.xDiagnosticRows.len & ")"
  editor.xDiagnosticsView.reloadData()

proc clearPreviewHover*(editor: ResourceEditor) =
  discard editor.xHoverRing.uninstall()
  editor.xHoveredResourceId = none(ResourceId)
  editor.xHoverGeometry = ResourcePreviewGeometry()
  editor.refreshPropertyRows()

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
    editor.xHoverRing = result.resourceView.installSelectionRing(
      initSelectionRingStyle(
        strokeColor = color(0.1, 0.72, 0.82, 0.9),
        fillColor = color(0.1, 0.72, 0.82, 0.08),
        lineWidth = 2.0,
        cornerRadius = 5.0,
        insets = insets(1.0),
      )
    )
    let frame = result.geometry.frameInReferenceView
    editor.xSelectionLabel.text =
      "Hover " & $result.resourceId & " · x " & $frame.x & "  y " & $frame.y & "  w " &
      $frame.w & "  h " & $frame.h
  else:
    editor.refreshPropertyRows()

protocol ResourceEditorPreviewSurfaceEvents of ResponderEventProtocol:
  method mouseMoved(surface: ResourceEditorPreviewSurface, event: MouseEvent): bool =
    if not surface.xEditor.isNil:
      discard surface.xEditor.updatePreviewHover(event.location)
    false

  method mouseExited(surface: ResourceEditorPreviewSurface, event: MouseEvent): bool =
    discard event
    if not surface.xEditor.isNil:
      surface.xEditor.clearPreviewHover()
    false

protocol ResourceEditorHierarchyEvents of ResponderEventProtocol:
  method keyDown(hierarchy: ResourceEditorHierarchyView, event: KeyEvent): bool =
    if event.key in {keyBackspace, keyDelete} and event.modifiers == {} and
        not hierarchy.xEditor.isNil:
      if hierarchy.xEditor.removeSelectedView().applied:
        return true
    let next = hierarchy.performNext(keyDown, event)
    if next.isSome:
      next.get()
    else:
      false

proc uninstallPreviewHoverTracking(editor: ResourceEditor) =
  for index in countdown(editor.xHoverTokens.high, 0):
    discard editor.xHoverTokens[index].popMethod()
  editor.xHoverTokens.setLen(0)

proc installPreviewHoverTracking(editor: ResourceEditor, view: View) =
  if view.isNil:
    return
  let editorCopy = editor
  let movedWrapper: AroundMethod = proc(
      self: DynamicAgent, invocation: var Invocation, next: DynamicMethod
  ) =
    if not next.isNil:
      next(self, invocation)
    let
      event = invocation.argsAs(MouseEvent)
      localView = View(self)
      point = localView.pointToView(event.location, editorCopy.xPreviewSurface)
    discard editorCopy.updatePreviewHover(point)
  let exitedWrapper: AroundMethod = proc(
      self: DynamicAgent, invocation: var Invocation, next: DynamicMethod
  ) =
    discard self
    if not next.isNil:
      next(self, invocation)
    if editorCopy.xHoveredResourceId.isSome:
      editorCopy.clearPreviewHover()
  editor.xHoverTokens.add DynamicAgent(view).pushMethod(
    nimkitSelectors.mouseMoved(), movedWrapper
  )
  editor.xHoverTokens.add DynamicAgent(view).pushMethod(
    nimkitSelectors.mouseExited(), exitedWrapper
  )
  for child in view.subviews():
    editor.installPreviewHoverTracking(child)

proc installPreviewHoverTracking(editor: ResourceEditor) =
  editor.uninstallPreviewHoverTracking()
  for view in editor.xPreview.rootViews():
    editor.installPreviewHoverTracking(view)

proc clearPreview(editor: ResourceEditor) =
  editor.uninstallPreviewHoverTracking()
  discard editor.xPreviewSelection.uninstall()
  discard editor.xSelectionRing.uninstall()
  discard editor.xHoverRing.uninstall()
  while editor.xPreviewSurface.subviews().len > 0:
    editor.xPreviewSurface.subviews()[^1].removeFromSuperview()
  editor.xPreview = newResourcePreview(
    editor.xDocument.xRegistry, editor.xDocument.xInstantiationContext,
    editor.xDocument.xValidationOptions,
  )
  editor.xHoveredResourceId = none(ResourceId)
  editor.xHoverGeometry = ResourcePreviewGeometry()

proc selectPreviewView(editor: ResourceEditor) =
  discard editor.xSelectionRing.uninstall()
  let selected = editor.selectedViewId()
  if selected.isNone or not editor.xHasPreview:
    return
  let view = editor.xPreview.findView(selected.get())
  if not view.isNil:
    editor.xSelectionRing = view.installSelectionRing()

proc previewResourceId(editor: ResourceEditor, selectedView: View): ResourceId =
  let found = editor.xPreview.resourceIdForView(selectedView)
  if found.isSome:
    result = found.get()

proc selectResource*(editor: ResourceEditor, id: ResourceId): bool =
  result = editor.xDocument.xResources.selectResource(id)
  if not result:
    return
  editor.refreshHierarchy()
  editor.refreshPropertyRows()
  editor.selectPreviewView()

proc previewViewSelected(editor: ResourceEditor, view: View, event: MouseEvent) =
  discard event
  let id = editor.previewResourceId(view)
  if not id.isEmpty:
    discard editor.selectResource(id)

proc rebuildPreview(editor: ResourceEditor) =
  let document = editor.xDocument.xResources
  if not document.hasLastValidRevision():
    editor.clearPreview()
    editor.xPreviewDiagnostics = ResourceDiagnostics()
    editor.xHasPreview = false
    return

  let revision = document.lastValidRevision().int
  if editor.xHasPreview and revision == editor.xPreviewRevision:
    editor.selectPreviewView()
    return

  editor.uninstallPreviewHoverTracking()
  discard editor.xHoverRing.uninstall()
  editor.xHoveredResourceId = none(ResourceId)
  editor.xHoverGeometry = ResourcePreviewGeometry()
  let update = editor.xPreview.update(
    document.lastValidBundle(), revision.Natural, editor.xPreviewSurface
  )
  editor.xPreviewDiagnostics = update.diagnostics
  if not update.applied:
    editor.installPreviewHoverTracking()
    return

  editor.xPreviewRevision = revision
  editor.xHasPreview = true
  editor.installPreviewHoverTracking()
  if not editor.xPreviewSelection.installed():
    editor.xPreviewSelection = installViewSelection(
      editor.xPreviewSurface,
      proc(view: View, event: MouseEvent) =
        editor.previewViewSelected(view, event),
      initViewSelectionOptions(includeRoot = false),
    )
  editor.selectPreviewView()

proc refreshStatus(editor: ResourceEditor) =
  let
    resources = editor.xDocument.xResources
    edited = if editor.xDocument.isDocumentEdited(): "edited" else: "saved"
  if not resources.draftIsValid():
    let preview =
      if editor.xHasPreview:
        $editor.xPreviewRevision
      else:
        "none"
    editor.xStatusLabel.text =
      "Draft " & $resources.revision() & " is invalid · preview " & preview &
      " unchanged · " & edited
  elif editor.xHasPreview:
    editor.xStatusLabel.text =
      "Draft " & $resources.revision() & " · preview " & $editor.xPreviewRevision &
      " · " & edited
  else:
    editor.xStatusLabel.text =
      "Draft " & $resources.revision() & " is valid · preview unavailable · " & edited

proc synchronize*(editor: ResourceEditor) =
  ## Synchronizes hierarchy, inspector, diagnostics, and the valid preview.
  editor.rebuildPreview()
  editor.refreshHierarchy()
  editor.refreshPropertyRows()
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
    result.edit =
      document.setViewProperty(viewId, resourceProperty(name, resourceValue(text)))
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
  let selected = editor.selectedViewId()
  if selected.isSome:
    return editor.commitPropertyText(selected.get(), name, text)
  result.message = "no view resource is selected"

proc nextViewIdentifier(document: ResourceDocument, kind: string): ResourceId =
  var index = 1
  while document.contains(resourceId(kind & "." & $index)):
    inc index
  result = resourceId(kind & "." & $index)

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
  result = document.insertView(kind.defaultViewNode(id), parent)
  if result.applied:
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
  if path.isNone or path.get().kind != rnkView:
    return ResourceEditResult(
      kind: rekRemove,
      error: reeResourceUnavailable,
      message: "the selected resource is not a view",
      resourceId: selected.get(),
      revision: document.revision(),
    )
  let parent = document.findParentPath(path.get())
  result = document.removeView(selected.get(), actionName = "Delete View")
  if not result.applied:
    return
  if parent.isSome and document.selectResource(parent.get().id):
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
  let selected = editor.selectedViewId()
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
    let selected = editor.selectedViewId()
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
  result = newButton(kind)
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
    editor.xPaletteView.addSubview(button, row = index div 3, col = index mod 3)

proc configureToolbar(
    editor: ResourceEditor, saveButton, undoButton, redoButton, deleteButton: Button
) =
  let
    saveAction = nimkitSelectors.actionSelector("resourceEditorSave")
    undoAction = nimkitSelectors.actionSelector("resourceEditorUndo")
    redoAction = nimkitSelectors.actionSelector("resourceEditorRedo")
    deleteAction = nimkitSelectors.actionSelector("resourceEditorDelete")
  saveButton.target = newActionTarget(
    saveAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard editor.xDocument.save()
      editor.synchronize(),
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
  discard result.withProtocol(ResourceEditorTableSource)
  discard result.withProtocol(ResourceEditorTableDelegate)

  for kind in ResourceEditorPaletteKinds:
    if document.xRegistry.hasViewKind(kind):
      result.xPaletteKinds.add kind

  result.xHierarchyView.configureHierarchy()
  result.xPropertyInspector.configurePropertyInspector()
  result.xDiagnosticsView.configureDiagnostics()
  result.xPropertyInspector.dataSource = result
  result.xPropertyInspector.delegate = result
  result.xDiagnosticsView.dataSource = result
  result.xDiagnosticsView.delegate = result
  result.xPreviewSurface.backgroundColor = color(0.96, 0.97, 0.99, 1.0)
  result.xPreviewSurface.clipsToBounds = true
  result.xPreviewSurface.accessibilityRole = arGroup
  result.xPreviewSurface.accessibilityLabel = "Resource preview"

  let
    hierarchyTitle = newHeadingLabel("Resource Hierarchy")
    paletteTitle = newHeadingLabel("View Palette")
    previewTitle = newHeadingLabel("Valid Revision Preview")
    inspectorTitle = newHeadingLabel("Resource Inspector")
    saveButton = newButton("Save")
    undoButton = newButton("Undo")
    redoButton = newButton("Redo")
    deleteButton = newButton("Delete")

  result.configurePalette()
  result.configureToolbar(saveButton, undoButton, redoButton, deleteButton)
  result.xRootView.addSubviews(
    autoNames(
      hierarchyTitle, result.xHierarchyView, paletteTitle, result.xPaletteView,
      previewTitle, result.xStatusLabel, result.xPreviewSurface, inspectorTitle,
      result.xSelectionLabel, result.xPropertyInspector, result.xDiagnosticsTitle,
      result.xDiagnosticsView, saveButton, undoButton, redoButton, deleteButton,
    )
  )

  activateConstraints:
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
    paletteTitle[atBottom] == result.xPaletteView[atTop] - 6.0
    paletteTitle[atHeight] == 24.0
    result.xPaletteView[atLeft] == hierarchyTitle[atLeft]
    result.xPaletteView[atWidth] == hierarchyTitle[atWidth]
    result.xPaletteView[atBottom] == result.xRootView[atBottom] - 18.0
    result.xPaletteView[atHeight] == 170.0

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
