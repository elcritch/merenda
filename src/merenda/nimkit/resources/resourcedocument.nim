## Editable, validated resource documents for GUI-builder workflows.
##
## `ResourceDocument` owns editor identity and mutation history. Serialized
## `ResourceBundle` records remain ordinary values and are never exposed through
## mutable borrows.

import std/[algorithm, options, sets, tables]

import ../foundation/undomanagers
import ./[resourcecore, resourceregistry, resourcevalidation]

type
  ResourceDocumentLookupError* = object of CatchableError
  ResourceDocumentStateError* = object of CatchableError

  ResourceNodeKind* = enum
    rnkView
    rnkController
    rnkWindow
    rnkMenu
    rnkMenuItem
    rnkCommand
    rnkImage
    rnkKeyBindings
    rnkTheme

  ResourceNodePath* = object
    ## Stable editor path. The identifier, rather than a sequence index, is the
    ## durable portion; `diagnosticPath` resolves its current structural location.
    kind*: ResourceNodeKind
    id*: ResourceId

  ResourceEditKind* = enum
    rekInsert
    rekRemove
    rekMove
    rekReplace

  ResourceEditError* = enum
    reeNone
    reeResourceUnavailable
    reeParentUnavailable
    reeIndexOutOfBounds
    reeIdentifierMissing
    reeIdentifierDuplicate
    reeIdentifierMismatch
    reeHierarchyCycle
    reeUnchanged

  ResourceEditResult* = object
    applied*: bool
    kind*: ResourceEditKind
    error*: ResourceEditError
    message*: string
    resourceId*: ResourceId
    revision*: Natural
    path*: Option[ResourceNodePath]
    previousPath*: Option[ResourceNodePath]
    diagnosticPath*: string
    previousDiagnosticPath*: string
    diagnostics*: ResourceDiagnostics

  ResourceViewInsertOperation* = object
    node*: ViewNodeResource
    parentId*: ResourceId
    index*: Option[Natural]
    actionName*: string

  ResourceViewRemoveOperation* = object
    id*: ResourceId
    actionName*: string

  ResourceViewMoveOperation* = object
    id*: ResourceId
    parentId*: ResourceId
    index*: Option[Natural]
    actionName*: string

  ResourceViewReplaceOperation* = object
    id*: ResourceId
    node*: ViewNodeResource
    actionName*: string

  ResourceViewPropertyReplaceOperation* = object
    viewId*: ResourceId
    property*: ResourceProperty
    actionName*: string

  ResourceIndexEntry = object
    path: ResourceNodePath
    parent: Option[ResourceNodePath]
    diagnosticPath: string
    order: int

  ResourceDocument* = ref object
    xDraft: ResourceBundle
    xLastValid: ResourceBundle
    xHasLastValid: bool
    xRevision: int
    xLastValidRevision: int
    xDiagnostics: ResourceDiagnostics
    xSelectionIds: seq[ResourceId]
    xUndoManager: UndoManager
    xRegistry: ResourceRegistry
    xValidationOptions: ResourceValidationOptions
    xIndex: Table[ResourceId, ResourceIndexEntry]

func resourceNodePath*(kind: ResourceNodeKind, id: ResourceId): ResourceNodePath =
  ResourceNodePath(kind: kind, id: id)

func initResourceViewInsertOperation*(
    node: ViewNodeResource,
    parentId = ResourceId(""),
    index = none(Natural),
    actionName = "Insert View",
): ResourceViewInsertOperation =
  ResourceViewInsertOperation(
    node: node, parentId: parentId, index: index, actionName: actionName
  )

func initResourceViewRemoveOperation*(
    id: ResourceId, actionName = "Remove View"
): ResourceViewRemoveOperation =
  ResourceViewRemoveOperation(id: id, actionName: actionName)

func initResourceViewMoveOperation*(
    id: ResourceId,
    parentId = ResourceId(""),
    index = none(Natural),
    actionName = "Move View",
): ResourceViewMoveOperation =
  ResourceViewMoveOperation(
    id: id, parentId: parentId, index: index, actionName: actionName
  )

func initResourceViewReplaceOperation*(
    id: ResourceId, node: ViewNodeResource, actionName = "Replace View"
): ResourceViewReplaceOperation =
  ResourceViewReplaceOperation(id: id, node: node, actionName: actionName)

func initResourceViewPropertyReplaceOperation*(
    viewId: ResourceId, property: ResourceProperty, actionName = "Change View Property"
): ResourceViewPropertyReplaceOperation =
  ResourceViewPropertyReplaceOperation(
    viewId: viewId, property: property, actionName: actionName
  )

proc addIndexEntry(
    index: var Table[ResourceId, ResourceIndexEntry],
    kind: ResourceNodeKind,
    id: ResourceId,
    diagnosticPath: string,
    order: var int,
    parent = none(ResourceNodePath),
) =
  let currentOrder = order
  inc order
  if id.isEmpty or index.hasKey(id):
    return
  let path = resourceNodePath(kind, id)
  index[id] = ResourceIndexEntry(
    path: path, parent: parent, diagnosticPath: diagnosticPath, order: currentOrder
  )

proc indexViewNodes(
    index: var Table[ResourceId, ResourceIndexEntry],
    nodes: openArray[ViewNodeResource],
    basePath: string,
    order: var int,
    parent = none(ResourceNodePath),
) =
  for nodeIndex, node in nodes:
    let
      diagnosticPath = basePath & "[" & $nodeIndex & "]"
      path = resourceNodePath(rnkView, node.id)
    index.addIndexEntry(rnkView, node.id, diagnosticPath, order, parent)
    index.indexViewNodes(node.children, diagnosticPath & ".children", order, some(path))

proc indexControllerNodes(
    index: var Table[ResourceId, ResourceIndexEntry],
    nodes: openArray[ControllerNodeResource],
    basePath: string,
    order: var int,
    parent = none(ResourceNodePath),
) =
  for nodeIndex, node in nodes:
    let
      diagnosticPath = basePath & "[" & $nodeIndex & "]"
      path = resourceNodePath(rnkController, node.id)
    index.addIndexEntry(rnkController, node.id, diagnosticPath, order, parent)
    index.indexControllerNodes(
      node.children, diagnosticPath & ".children", order, some(path)
    )

proc indexMenuItems(
    index: var Table[ResourceId, ResourceIndexEntry],
    items: openArray[MenuItemResource],
    basePath: string,
    parent: ResourceNodePath,
    order: var int,
) =
  for itemIndex, item in items:
    let
      diagnosticPath = basePath & "[" & $itemIndex & "]"
      path = resourceNodePath(rnkMenuItem, item.id)
    index.addIndexEntry(rnkMenuItem, item.id, diagnosticPath, order, some(parent))
    let childParent = if item.id.isEmpty: parent else: path
    index.indexMenuItems(
      item.children, diagnosticPath & ".children", childParent, order
    )

proc buildIndex(bundle: ResourceBundle): Table[ResourceId, ResourceIndexEntry] =
  result = initTable[ResourceId, ResourceIndexEntry]()
  var order: int
  result.indexViewNodes(bundle.views, "views", order)
  result.indexControllerNodes(bundle.controllers, "controllers", order)
  for index, window in bundle.windows:
    result.addIndexEntry(rnkWindow, window.id, "windows[" & $index & "]", order)
  for index, menu in bundle.menus:
    let
      diagnosticPath = "menus[" & $index & "]"
      path = resourceNodePath(rnkMenu, menu.id)
    result.addIndexEntry(rnkMenu, menu.id, diagnosticPath, order)
    result.indexMenuItems(menu.items, diagnosticPath & ".items", path, order)
  for index, command in bundle.commands:
    result.addIndexEntry(rnkCommand, command.id, "commands[" & $index & "]", order)
  for index, image in bundle.images:
    result.addIndexEntry(rnkImage, image.id, "images[" & $index & "]", order)
  for index, bindings in bundle.keyBindings:
    result.addIndexEntry(
      rnkKeyBindings, bindings.id, "keyBindings[" & $index & "]", order
    )
  for index, theme in bundle.themes:
    result.addIndexEntry(rnkTheme, theme.id, "themes[" & $index & "]", order)

proc pruneSelection(document: ResourceDocument) =
  var selected: seq[ResourceId]
  for id in document.xSelectionIds:
    if document.xIndex.hasKey(id):
      selected.add id
  document.xSelectionIds = move selected

proc updateDraft(document: ResourceDocument, bundle: sink ResourceBundle) =
  document.xDraft = bundle
  inc document.xRevision
  document.xIndex = buildIndex(document.xDraft)
  document.pruneSelection()
  document.xDiagnostics =
    document.xDraft.validateResources(document.xRegistry, document.xValidationOptions)
  if not document.xDiagnostics.hasErrors:
    document.xLastValid = document.xDraft
    document.xHasLastValid = true
    document.xLastValidRevision = document.xRevision

proc replaceDraft(
    document: ResourceDocument, bundle: sink ResourceBundle, actionName: string
) =
  let previous = document.xDraft
  document.xUndoManager.registerUndo(
    proc() =
      document.replaceDraft(previous, actionName),
    actionName,
  )
  document.updateDraft(bundle)

proc newResourceDocument*(
    bundle: sink ResourceBundle,
    registry = initNimKitResourceRegistry(),
    validationOptions = initResourceValidationOptions(),
    undoManager: UndoManager = nil,
): ResourceDocument =
  ## Creates an editor document without constructing runtime UI identities.
  result = ResourceDocument(
    xDraft: bundle,
    xRegistry: registry,
    xValidationOptions: validationOptions,
    xUndoManager:
      if undoManager.isNil:
        newUndoManager()
      else:
        undoManager,
  )
  result.xIndex = buildIndex(result.xDraft)
  result.xDiagnostics =
    result.xDraft.validateResources(result.xRegistry, result.xValidationOptions)
  if not result.xDiagnostics.hasErrors:
    result.xLastValid = result.xDraft
    result.xHasLastValid = true

proc newResourceDocument*(
    namespace = "",
    registry = initNimKitResourceRegistry(),
    validationOptions = initResourceValidationOptions(),
    undoManager: UndoManager = nil,
): ResourceDocument =
  ## Creates an empty, valid resource document.
  newResourceDocument(
    initResourceBundle(namespace), registry, validationOptions, undoManager
  )

proc bundle*(document: ResourceDocument): lent ResourceBundle =
  ## Borrows the current draft for read-only inspection.
  document.xDraft

proc lastValidBundle*(document: ResourceDocument): lent ResourceBundle =
  ## Borrows the most recent valid draft.
  if not document.xHasLastValid:
    raise newException(
      ResourceDocumentStateError, "resource document has no valid revision"
    )
  document.xLastValid

func hasLastValidRevision*(document: ResourceDocument): bool =
  document.xHasLastValid

func revision*(document: ResourceDocument): Natural =
  document.xRevision.Natural

proc lastValidRevision*(document: ResourceDocument): Natural =
  if not document.xHasLastValid:
    raise newException(
      ResourceDocumentStateError, "resource document has no valid revision"
    )
  document.xLastValidRevision.Natural

proc diagnostics*(document: ResourceDocument): lent ResourceDiagnostics =
  document.xDiagnostics

func draftIsValid*(document: ResourceDocument): bool =
  not document.xDiagnostics.hasErrors

proc undoManager*(document: ResourceDocument): UndoManager =
  document.xUndoManager

proc selectedResourceIds*(document: ResourceDocument): lent seq[ResourceId] =
  document.xSelectionIds

proc selectResources*(document: ResourceDocument, ids: openArray[ResourceId]) =
  ## Replaces editor selection with unique identifiers present in the draft.
  var seen = initHashSet[ResourceId]()
  document.xSelectionIds.setLen(0)
  for id in ids:
    if document.xIndex.hasKey(id) and id notin seen:
      seen.incl id
      document.xSelectionIds.add id

proc selectResource*(document: ResourceDocument, id: ResourceId): bool =
  if not document.xIndex.hasKey(id):
    return
  document.selectResources([id])
  true

proc clearSelection*(document: ResourceDocument) =
  document.xSelectionIds.setLen(0)

func isSelected*(document: ResourceDocument, id: ResourceId): bool =
  id in document.xSelectionIds

func contains*(document: ResourceDocument, id: ResourceId): bool =
  document.xIndex.hasKey(id)

func findNodePath*(
    document: ResourceDocument, id: ResourceId
): Option[ResourceNodePath] =
  if document.xIndex.hasKey(id):
    return some(document.xIndex[id].path)

proc missingResource(kind: string, id: ResourceId) {.noinline, noreturn.} =
  raise newException(
    ResourceDocumentLookupError,
    kind & " resource '" & $id & "' is unavailable in the document",
  )

proc nodePath*(document: ResourceDocument, id: ResourceId): ResourceNodePath =
  let found = document.findNodePath(id)
  if found.isNone:
    missingResource("identified", id)
  found.get()

proc diagnosticPath*(document: ResourceDocument, path: ResourceNodePath): string =
  if not document.xIndex.hasKey(path.id) or
      document.xIndex[path.id].path.kind != path.kind:
    missingResource("path", path.id)
  document.xIndex[path.id].diagnosticPath

func findParentPath*(
    document: ResourceDocument, path: ResourceNodePath
): Option[ResourceNodePath] =
  if document.xIndex.hasKey(path.id) and document.xIndex[path.id].path.kind == path.kind:
    return document.xIndex[path.id].parent

iterator items*(document: ResourceDocument): ResourceNodePath =
  ## Iterates all identified records in current structural order.
  var entries: seq[ResourceIndexEntry]
  for entry in document.xIndex.values:
    entries.add entry
  entries.sort(
    proc(a, b: ResourceIndexEntry): int =
      cmp(a.order, b.order)
  )
  for entry in entries:
    yield entry.path

iterator viewNodes*(document: ResourceDocument): ViewNodeResource =
  ## Iterates view records depth-first as values.
  var stack: seq[ViewNodeResource]
  for index in countdown(document.xDraft.views.high, 0):
    stack.add document.xDraft.views[index]
  while stack.len > 0:
    let node = stack.pop()
    yield node
    for index in countdown(node.children.high, 0):
      stack.add node.children[index]

proc findView*(document: ResourceDocument, id: ResourceId): Option[ViewNodeResource] =
  document.xDraft.findView(id)

proc view*(document: ResourceDocument, id: ResourceId): ViewNodeResource =
  let found = document.findView(id)
  if found.isNone:
    missingResource("view", id)
  found.get()

proc findViewProperty*(
    document: ResourceDocument, viewId: ResourceId, name: string
): Option[ResourceProperty] =
  let found = document.findView(viewId)
  if found.isSome:
    for property in found.get().properties:
      if property.name == name:
        return some(property)

proc viewProperty*(
    document: ResourceDocument, viewId: ResourceId, name: string
): ResourceProperty =
  let found = document.findViewProperty(viewId, name)
  if found.isNone:
    missingResource("view property " & name & " on", viewId)
  found.get()

proc findController*(
    document: ResourceDocument, id: ResourceId
): Option[ControllerNodeResource] =
  document.xDraft.findController(id)

proc controller*(document: ResourceDocument, id: ResourceId): ControllerNodeResource =
  let found = document.findController(id)
  if found.isNone:
    missingResource("controller", id)
  found.get()

proc findWindow*(document: ResourceDocument, id: ResourceId): Option[WindowResource] =
  for window in document.xDraft.windows:
    if window.id == id:
      return some(window)

proc window*(document: ResourceDocument, id: ResourceId): WindowResource =
  let found = document.findWindow(id)
  if found.isNone:
    missingResource("window", id)
  found.get()

proc findMenu*(document: ResourceDocument, id: ResourceId): Option[MenuResource] =
  document.xDraft.findMenu(id)

proc menu*(document: ResourceDocument, id: ResourceId): MenuResource =
  let found = document.findMenu(id)
  if found.isNone:
    missingResource("menu", id)
  found.get()

proc findMenuItem(
    items: openArray[MenuItemResource], id: ResourceId, found: var MenuItemResource
): bool =
  for item in items:
    if item.id == id:
      found = item
      return true
    if item.children.findMenuItem(id, found):
      return true

proc findMenuItem*(
    document: ResourceDocument, id: ResourceId
): Option[MenuItemResource] =
  for menu in document.xDraft.menus:
    var found: MenuItemResource
    if menu.items.findMenuItem(id, found):
      return some(found)

proc menuItem*(document: ResourceDocument, id: ResourceId): MenuItemResource =
  let found = document.findMenuItem(id)
  if found.isNone:
    missingResource("menu item", id)
  found.get()

proc findCommand*(document: ResourceDocument, id: ResourceId): Option[CommandResource] =
  document.xDraft.findCommand(id)

proc command*(document: ResourceDocument, id: ResourceId): CommandResource =
  let found = document.findCommand(id)
  if found.isNone:
    missingResource("command", id)
  found.get()

proc findImage*(
    document: ResourceDocument, id: ResourceId
): Option[ImageAssetResource] =
  document.xDraft.findImage(id)

proc image*(document: ResourceDocument, id: ResourceId): ImageAssetResource =
  let found = document.findImage(id)
  if found.isNone:
    missingResource("image", id)
  found.get()

proc findKeyBindings*(
    document: ResourceDocument, id: ResourceId
): Option[KeyBindingTableResource] =
  for bindings in document.xDraft.keyBindings:
    if bindings.id == id:
      return some(bindings)

proc keyBindings*(document: ResourceDocument, id: ResourceId): KeyBindingTableResource =
  let found = document.findKeyBindings(id)
  if found.isNone:
    missingResource("key bindings", id)
  found.get()

proc findTheme*(
    document: ResourceDocument, id: ResourceId
): Option[ThemeFragmentResource] =
  for theme in document.xDraft.themes:
    if theme.id == id:
      return some(theme)

proc theme*(document: ResourceDocument, id: ResourceId): ThemeFragmentResource =
  let found = document.findTheme(id)
  if found.isNone:
    missingResource("theme", id)
  found.get()

proc viewContains(node: ViewNodeResource, id: ResourceId): bool =
  if node.id == id:
    return true
  for child in node.children:
    if child.viewContains(id):
      return true

proc collectViewIdentifiers(
    node: ViewNodeResource, ids: var HashSet[ResourceId], error: var ResourceEditError
) =
  if error != reeNone:
    return
  if node.id.isEmpty:
    error = reeIdentifierMissing
    return
  if node.id in ids:
    error = reeIdentifierDuplicate
    return
  ids.incl node.id
  for child in node.children:
    child.collectViewIdentifiers(ids, error)

proc validateInsertedSubtree(
    document: ResourceDocument, node: ViewNodeResource, allowed: HashSet[ResourceId]
): ResourceEditError =
  var ids = initHashSet[ResourceId]()
  node.collectViewIdentifiers(ids, result)
  if result != reeNone:
    return
  for id in ids:
    if document.xIndex.hasKey(id) and id notin allowed:
      return reeIdentifierDuplicate

proc childCount(
    nodes: openArray[ViewNodeResource], parentId: ResourceId, count: var int
): bool =
  if parentId.isEmpty:
    count = nodes.len
    return true
  for node in nodes:
    if node.id == parentId:
      count = node.children.len
      return true
    if node.children.childCount(parentId, count):
      return true

proc insertViewNode(
    nodes: var seq[ViewNodeResource],
    parentId: ResourceId,
    index: int,
    node: ViewNodeResource,
): bool =
  if parentId.isEmpty:
    nodes.insert(node, index)
    return true
  for nodeIndex in 0 ..< nodes.len:
    if nodes[nodeIndex].id == parentId:
      nodes[nodeIndex].children.insert(node, index)
      return true
    if nodes[nodeIndex].children.insertViewNode(parentId, index, node):
      return true

proc removeViewNode(
    nodes: var seq[ViewNodeResource],
    id: ResourceId,
    removed: var ViewNodeResource,
    parentId: var ResourceId,
    index: var int,
    currentParent = ResourceId(""),
): bool =
  for nodeIndex in 0 ..< nodes.len:
    if nodes[nodeIndex].id == id:
      removed = nodes[nodeIndex]
      parentId = currentParent
      index = nodeIndex
      nodes.delete(nodeIndex)
      return true
    if nodes[nodeIndex].children.removeViewNode(
      id, removed, parentId, index, nodes[nodeIndex].id
    ):
      return true

proc replaceViewNode(
    nodes: var seq[ViewNodeResource], id: ResourceId, replacement: ViewNodeResource
): bool =
  for nodeIndex in 0 ..< nodes.len:
    if nodes[nodeIndex].id == id:
      nodes[nodeIndex] = replacement
      return true
    if nodes[nodeIndex].children.replaceViewNode(id, replacement):
      return true

proc sameResourceValue(a, b: ResourceValue): bool =
  if a.kind != b.kind:
    return
  case a.kind
  of rvNone:
    true
  of rvString:
    a.stringValue == b.stringValue
  of rvInt:
    a.intValue == b.intValue
  of rvFloat:
    a.floatValue == b.floatValue
  of rvBool:
    a.boolValue == b.boolValue
  of rvStrings:
    a.stringValues == b.stringValues
  of rvRect:
    a.rectValue == b.rectValue
  of rvSize:
    a.sizeValue == b.sizeValue
  of rvInsets:
    a.insetsValue == b.insetsValue
  of rvColor:
    a.colorValue == b.colorValue
  of rvReference:
    a.referenceValue.kind == b.referenceValue.kind and
      a.referenceValue.id == b.referenceValue.id

proc replaceViewProperty(
    nodes: var seq[ViewNodeResource],
    viewId: ResourceId,
    property: ResourceProperty,
    changed: var bool,
): bool =
  for nodeIndex in 0 ..< nodes.len:
    if nodes[nodeIndex].id == viewId:
      for propertyIndex in 0 ..< nodes[nodeIndex].properties.len:
        if nodes[nodeIndex].properties[propertyIndex].name == property.name:
          if nodes[nodeIndex].properties[propertyIndex].value.sameResourceValue(
            property.value
          ):
            return true
          nodes[nodeIndex].properties[propertyIndex] = property
          changed = true
          return true
      nodes[nodeIndex].properties.add property
      changed = true
      return true
    if nodes[nodeIndex].children.replaceViewProperty(viewId, property, changed):
      return true

proc removeViewProperty(
    nodes: var seq[ViewNodeResource],
    viewId: ResourceId,
    name: string,
    changed: var bool,
): bool =
  for nodeIndex in 0 ..< nodes.len:
    if nodes[nodeIndex].id == viewId:
      for propertyIndex in 0 ..< nodes[nodeIndex].properties.len:
        if nodes[nodeIndex].properties[propertyIndex].name == name:
          nodes[nodeIndex].properties.delete(propertyIndex)
          changed = true
          return true
      return true
    if nodes[nodeIndex].children.removeViewProperty(viewId, name, changed):
      return true

func resolvedIndex(index: Option[Natural], count: int): int =
  if index.isSome:
    index.get().int
  else:
    count

proc rejectedEdit(
    document: ResourceDocument,
    kind: ResourceEditKind,
    id: ResourceId,
    error: ResourceEditError,
    message: string,
): ResourceEditResult =
  ResourceEditResult(
    kind: kind,
    error: error,
    message: message,
    resourceId: id,
    revision: document.revision,
    path: document.findNodePath(id),
    previousPath: document.findNodePath(id),
    diagnosticPath:
      if document.xIndex.hasKey(id):
        document.xIndex[id].diagnosticPath
      else:
        "",
    previousDiagnosticPath:
      if document.xIndex.hasKey(id):
        document.xIndex[id].diagnosticPath
      else:
        "",
    diagnostics: document.xDiagnostics,
  )

proc appliedEdit(
    document: ResourceDocument,
    kind: ResourceEditKind,
    id: ResourceId,
    previousPath: Option[ResourceNodePath],
    previousDiagnosticPath: string,
): ResourceEditResult =
  let path = document.findNodePath(id)
  ResourceEditResult(
    applied: true,
    kind: kind,
    resourceId: id,
    revision: document.revision,
    path: path,
    previousPath: previousPath,
    diagnosticPath:
      if document.xIndex.hasKey(id):
        document.xIndex[id].diagnosticPath
      else:
        "",
    previousDiagnosticPath: previousDiagnosticPath,
    diagnostics: document.xDiagnostics,
  )

proc apply*(
    document: ResourceDocument, operation: ResourceViewInsertOperation
): ResourceEditResult {.discardable.} =
  let id = operation.node.id
  if id.isEmpty:
    return document.rejectedEdit(
      rekInsert, id, reeIdentifierMissing, "inserted views require identifiers"
    )
  if not operation.parentId.isEmpty:
    let parentPath = document.findNodePath(operation.parentId)
    if parentPath.isNone or parentPath.get().kind != rnkView:
      return document.rejectedEdit(
        rekInsert, id, reeParentUnavailable, "view parent is unavailable"
      )
  let subtreeError =
    document.validateInsertedSubtree(operation.node, initHashSet[ResourceId]())
  if subtreeError != reeNone:
    return document.rejectedEdit(
      rekInsert, id, subtreeError, "inserted view identifiers are invalid"
    )
  var count: int
  discard document.xDraft.views.childCount(operation.parentId, count)
  let index = operation.index.resolvedIndex(count)
  if index < 0 or index > count:
    return document.rejectedEdit(
      rekInsert, id, reeIndexOutOfBounds, "view insertion index is out of bounds"
    )

  var candidate = document.xDraft
  discard candidate.views.insertViewNode(operation.parentId, index, operation.node)
  document.replaceDraft(candidate, operation.actionName)
  document.appliedEdit(rekInsert, id, none(ResourceNodePath), "")

proc apply*(
    document: ResourceDocument, operation: ResourceViewRemoveOperation
): ResourceEditResult {.discardable.} =
  let previousPath = document.findNodePath(operation.id)
  if previousPath.isNone or previousPath.get().kind != rnkView:
    return document.rejectedEdit(
      rekRemove, operation.id, reeResourceUnavailable, "view is unavailable"
    )
  let previousDiagnosticPath = document.xIndex[operation.id].diagnosticPath
  var
    candidate = document.xDraft
    removed: ViewNodeResource
    parentId: ResourceId
    index: int
  discard candidate.views.removeViewNode(operation.id, removed, parentId, index)
  document.replaceDraft(candidate, operation.actionName)
  document.appliedEdit(rekRemove, operation.id, previousPath, previousDiagnosticPath)

proc apply*(
    document: ResourceDocument, operation: ResourceViewMoveOperation
): ResourceEditResult {.discardable.} =
  let previousPath = document.findNodePath(operation.id)
  if previousPath.isNone or previousPath.get().kind != rnkView:
    return document.rejectedEdit(
      rekMove, operation.id, reeResourceUnavailable, "view is unavailable"
    )
  if not operation.parentId.isEmpty:
    let parentPath = document.findNodePath(operation.parentId)
    if parentPath.isNone or parentPath.get().kind != rnkView:
      return document.rejectedEdit(
        rekMove, operation.id, reeParentUnavailable, "view parent is unavailable"
      )
  let moving = document.view(operation.id)
  if not operation.parentId.isEmpty and moving.viewContains(operation.parentId):
    return document.rejectedEdit(
      rekMove, operation.id, reeHierarchyCycle,
      "a view cannot move into its own subtree",
    )
  let previousDiagnosticPath = document.xIndex[operation.id].diagnosticPath
  var
    candidate = document.xDraft
    removed: ViewNodeResource
    previousParentId: ResourceId
    previousIndex: int
  discard candidate.views.removeViewNode(
    operation.id, removed, previousParentId, previousIndex
  )
  var count: int
  if not candidate.views.childCount(operation.parentId, count):
    return document.rejectedEdit(
      rekMove, operation.id, reeParentUnavailable, "view parent is unavailable"
    )
  let index = operation.index.resolvedIndex(count)
  if index < 0 or index > count:
    return document.rejectedEdit(
      rekMove, operation.id, reeIndexOutOfBounds, "view move index is out of bounds"
    )
  if previousParentId == operation.parentId and previousIndex == index:
    return document.rejectedEdit(
      rekMove, operation.id, reeUnchanged, "view is already at that position"
    )
  discard candidate.views.insertViewNode(operation.parentId, index, removed)
  document.replaceDraft(candidate, operation.actionName)
  document.appliedEdit(rekMove, operation.id, previousPath, previousDiagnosticPath)

proc apply*(
    document: ResourceDocument, operation: ResourceViewReplaceOperation
): ResourceEditResult {.discardable.} =
  let previousPath = document.findNodePath(operation.id)
  if previousPath.isNone or previousPath.get().kind != rnkView:
    return document.rejectedEdit(
      rekReplace, operation.id, reeResourceUnavailable, "view is unavailable"
    )
  if operation.node.id != operation.id:
    return document.rejectedEdit(
      rekReplace, operation.id, reeIdentifierMismatch,
      "replacement view must preserve its identifier",
    )
  let previous = document.view(operation.id)
  var allowed = initHashSet[ResourceId]()
  var ignoredError = reeNone
  previous.collectViewIdentifiers(allowed, ignoredError)
  let subtreeError = document.validateInsertedSubtree(operation.node, allowed)
  if subtreeError != reeNone:
    return document.rejectedEdit(
      rekReplace, operation.id, subtreeError, "replacement view identifiers are invalid"
    )
  let previousDiagnosticPath = document.xIndex[operation.id].diagnosticPath
  var candidate = document.xDraft
  discard candidate.views.replaceViewNode(operation.id, operation.node)
  document.replaceDraft(candidate, operation.actionName)
  document.appliedEdit(rekReplace, operation.id, previousPath, previousDiagnosticPath)

proc apply*(
    document: ResourceDocument, operation: ResourceViewPropertyReplaceOperation
): ResourceEditResult {.discardable.} =
  let previousPath = document.findNodePath(operation.viewId)
  if previousPath.isNone or previousPath.get().kind != rnkView:
    return document.rejectedEdit(
      rekReplace, operation.viewId, reeResourceUnavailable, "view is unavailable"
    )
  let previousDiagnosticPath = document.xIndex[operation.viewId].diagnosticPath
  var
    candidate = document.xDraft
    changed: bool
  discard
    candidate.views.replaceViewProperty(operation.viewId, operation.property, changed)
  if not changed:
    return document.rejectedEdit(
      rekReplace, operation.viewId, reeUnchanged, "view property is unchanged"
    )
  document.replaceDraft(candidate, operation.actionName)
  document.appliedEdit(
    rekReplace, operation.viewId, previousPath, previousDiagnosticPath
  )

proc insertView*(
    document: ResourceDocument,
    node: ViewNodeResource,
    parentId = ResourceId(""),
    actionName = "Insert View",
): ResourceEditResult {.discardable.} =
  document.apply(
    initResourceViewInsertOperation(node, parentId, actionName = actionName)
  )

proc insertView*(
    document: ResourceDocument,
    node: ViewNodeResource,
    parentId: ResourceId,
    index: Natural,
    actionName = "Insert View",
): ResourceEditResult {.discardable.} =
  document.apply(
    initResourceViewInsertOperation(node, parentId, some(index), actionName)
  )

proc removeView*(
    document: ResourceDocument, id: ResourceId, actionName = "Remove View"
): ResourceEditResult {.discardable.} =
  document.apply(initResourceViewRemoveOperation(id, actionName))

proc moveView*(
    document: ResourceDocument,
    id: ResourceId,
    parentId = ResourceId(""),
    actionName = "Move View",
): ResourceEditResult {.discardable.} =
  document.apply(initResourceViewMoveOperation(id, parentId, actionName = actionName))

proc moveView*(
    document: ResourceDocument,
    id, parentId: ResourceId,
    index: Natural,
    actionName = "Move View",
): ResourceEditResult {.discardable.} =
  document.apply(initResourceViewMoveOperation(id, parentId, some(index), actionName))

proc replaceView*(
    document: ResourceDocument,
    id: ResourceId,
    node: ViewNodeResource,
    actionName = "Replace View",
): ResourceEditResult {.discardable.} =
  document.apply(initResourceViewReplaceOperation(id, node, actionName))

proc setViewProperty*(
    document: ResourceDocument,
    viewId: ResourceId,
    property: ResourceProperty,
    actionName = "Change View Property",
): ResourceEditResult {.discardable.} =
  document.apply(initResourceViewPropertyReplaceOperation(viewId, property, actionName))

proc removeViewProperty*(
    document: ResourceDocument,
    viewId: ResourceId,
    name: string,
    actionName = "Remove View Property",
): ResourceEditResult {.discardable.} =
  let previousPath = document.findNodePath(viewId)
  if previousPath.isNone or previousPath.get().kind != rnkView:
    return document.rejectedEdit(
      rekRemove, viewId, reeResourceUnavailable, "view is unavailable"
    )
  let previousDiagnosticPath = document.xIndex[viewId].diagnosticPath
  var
    candidate = document.xDraft
    changed: bool
  discard candidate.views.removeViewProperty(viewId, name, changed)
  if not changed:
    return document.rejectedEdit(
      rekRemove, viewId, reeUnchanged, "view property is unavailable"
    )
  document.replaceDraft(candidate, actionName)
  document.appliedEdit(rekRemove, viewId, previousPath, previousDiagnosticPath)
