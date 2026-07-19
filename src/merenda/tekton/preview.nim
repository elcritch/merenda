## Tekton's transactional, identity-preserving resource previews.

import std/[algorithm, options, sets, strutils, tables]

import sigils/selectors

import ../nimkit/app/[viewcontrollers, windowcontrollers, windows]
import ../nimkit/controls/menus
import ../nimkit/drawing/images
import ../nimkit/foundation/types
import ../nimkit/responder/keybindings
import
  ../nimkit/resources/
    [resrcconstruction, resrccore, resrclayout, resrcregistry, resrcvalidation]
import ../nimkit/themes
import ../nimkit/view/views

type
  ResourcePreviewObjectKind* = enum
    rpokView
    rpokController

  ResourcePreviewChangeKind* = enum
    rpckInserted
    rpckRemoved
    rpckReused
    rpckReplaced
    rpckMoved
    rpckUpdated

  ResourcePreviewChange* = object
    resourceId*: ResourceId
    objectKind*: ResourcePreviewObjectKind
    kinds*: set[ResourcePreviewChangeKind]
    previousPath*: string
    path*: string

  ResourcePreviewUpdateResult* = object
    applied*: bool
    revision*: Natural
    diagnostics*: ResourceDiagnostics
    changes*: seq[ResourcePreviewChange]

  ResourcePreviewGeometry* = object
    found*: bool
    resourceId*: ResourceId
    view*: View
    bounds*: Rect
    frameInReferenceView*: Rect

  ResourcePreviewHit* = object
    found*: bool
    resourceId*: ResourceId
    hitView*: View
    resourceView*: View
    geometry*: ResourcePreviewGeometry

  ViewSnapshot = object
    node: ViewNodeResource
    parentId: ResourceId
    path: string

  ControllerSnapshot = object
    node: ControllerNodeResource
    parentId: ResourceId
    path: string

  PropertyUpdate = object
    resourceId: ResourceId
    kind: string
    name: string
    view: View
    value: ResourceValue
    rollbackValue: ResourceValue
    path: string

  ResourcePreview* = ref object
    xRegistry: ResourceRegistry
    xContext: ResourceInstantiationContext
    xValidationOptions: ResourceValidationOptions
    xBundle: ResourceBundle
    xInstance: ResourceInstance
    xViews: Table[ResourceId, View]
    xControllers: Table[ResourceId, ViewController]
    xLayout: ResourceLayoutInstance
    xRevision: Natural
    xHasRevision: bool

proc newResourcePreview*(
    registry = initNimKitResourceRegistry(),
    context = initResourceInstantiationContext(),
    validationOptions = initResourceValidationOptions(),
): ResourcePreview =
  ## Creates an empty preview ready to reconcile valid resource revisions.
  ResourcePreview(
    xRegistry: registry,
    xContext: context,
    xValidationOptions: validationOptions,
    xViews: initTable[ResourceId, View](),
    xControllers: initTable[ResourceId, ViewController](),
  )

func hasRevision*(preview: ResourcePreview): bool =
  not preview.isNil and preview.xHasRevision

proc revision*(preview: ResourcePreview): Natural =
  if preview.hasRevision:
    result = preview.xRevision

proc bundle*(preview: ResourcePreview): ResourceBundle =
  ## Returns a value copy of the installed resource revision.
  preview.xBundle

proc missingPreviewResource(kind: string, id: ResourceId) {.noinline, noreturn.} =
  raise newException(
    ResourceLookupError, kind & " preview resource '" & $id & "' is unavailable"
  )

proc findView*(preview: ResourcePreview, id: ResourceId): View =
  if not preview.isNil:
    result = preview.xViews.getOrDefault(id)

proc view*(preview: ResourcePreview, id: ResourceId): View =
  result = preview.findView(id)
  if result.isNil:
    missingPreviewResource("view", id)

proc findController*(preview: ResourcePreview, id: ResourceId): ViewController =
  if not preview.isNil:
    result = preview.xControllers.getOrDefault(id)

proc controller*(preview: ResourcePreview, id: ResourceId): ViewController =
  result = preview.findController(id)
  if result.isNil:
    missingPreviewResource("controller", id)

proc findWindow*(preview: ResourcePreview, id: ResourceId): Window =
  if not preview.isNil:
    result = preview.xInstance.findWindow(id)

proc window*(preview: ResourcePreview, id: ResourceId): Window =
  result = preview.findWindow(id)
  if result.isNil:
    missingPreviewResource("window", id)

proc findWindowController*(preview: ResourcePreview, id: ResourceId): WindowController =
  if not preview.isNil:
    result = preview.xInstance.findWindowController(id)

proc findMenu*(preview: ResourcePreview, id: ResourceId): Menu =
  if not preview.isNil:
    result = preview.xInstance.findMenu(id)

proc menu*(preview: ResourcePreview, id: ResourceId): Menu =
  result = preview.findMenu(id)
  if result.isNil:
    missingPreviewResource("menu", id)

proc findImage*(preview: ResourcePreview, id: ResourceId): ImageResource =
  if not preview.isNil:
    result = preview.xInstance.findImage(id)

proc image*(preview: ResourcePreview, id: ResourceId): ImageResource =
  result = preview.findImage(id)
  if result.isNil:
    missingPreviewResource("image", id)

proc findTheme*(preview: ResourcePreview, id: ResourceId, theme: var Theme): bool =
  if not preview.isNil:
    result = preview.xInstance.findTheme(id, theme)

proc findKeyBindings*(
    preview: ResourcePreview, id: ResourceId, bindings: var KeyBindingTable
): bool =
  if not preview.isNil:
    result = preview.xInstance.findKeyBindings(id, bindings)

proc findLayoutGuide*(
    preview: ResourcePreview, id: ResourceId, guide: var LayoutGuide
): bool =
  if not preview.isNil:
    result = preview.xLayout.findLayoutGuide(id, guide)

proc layoutGuide*(preview: ResourcePreview, id: ResourceId): LayoutGuide =
  if preview.isNil:
    raise newException(ResourceLookupError, "resource preview is unavailable")
  preview.xLayout.layoutGuide(id)

proc findLayoutConstraint*(preview: ResourcePreview, id: ResourceId): LayoutConstraint =
  if not preview.isNil:
    result = preview.xLayout.findLayoutConstraint(id)

proc layoutConstraint*(preview: ResourcePreview, id: ResourceId): LayoutConstraint =
  if preview.isNil:
    raise newException(ResourceLookupError, "resource preview is unavailable")
  preview.xLayout.layoutConstraint(id)

iterator rootViews*(preview: ResourcePreview): View =
  ## Iterates top-level preview views in resource order.
  if not preview.isNil:
    for node in preview.xBundle.views:
      let view = preview.xViews.getOrDefault(node.id)
      if not view.isNil:
        yield view

proc collectViews(
    nodes: openArray[ViewNodeResource],
    parentId: ResourceId,
    path: string,
    snapshots: var Table[ResourceId, ViewSnapshot],
) =
  for index, node in nodes:
    let nodePath = path & "[" & $index & "]"
    snapshots[node.id] = ViewSnapshot(node: node, parentId: parentId, path: nodePath)
    collectViews(node.children, node.id, nodePath & ".children", snapshots)

proc viewSnapshots(bundle: ResourceBundle): Table[ResourceId, ViewSnapshot] =
  result = initTable[ResourceId, ViewSnapshot]()
  collectViews(bundle.views, ResourceId(""), "views", result)

proc collectControllers(
    nodes: openArray[ControllerNodeResource],
    parentId: ResourceId,
    path: string,
    snapshots: var Table[ResourceId, ControllerSnapshot],
) =
  for index, node in nodes:
    let nodePath = path & "[" & $index & "]"
    snapshots[node.id] =
      ControllerSnapshot(node: node, parentId: parentId, path: nodePath)
    collectControllers(node.children, node.id, nodePath & ".children", snapshots)

proc controllerSnapshots(
    bundle: ResourceBundle
): Table[ResourceId, ControllerSnapshot] =
  result = initTable[ResourceId, ControllerSnapshot]()
  collectControllers(bundle.controllers, ResourceId(""), "controllers", result)

proc stagedViews(
    snapshots: Table[ResourceId, ViewSnapshot], instance: ResourceInstance
): Table[ResourceId, View] =
  result = initTable[ResourceId, View]()
  for id in snapshots.keys:
    result[id] = instance.findView(id)

proc stagedControllers(
    snapshots: Table[ResourceId, ControllerSnapshot], instance: ResourceInstance
): Table[ResourceId, ViewController] =
  result = initTable[ResourceId, ViewController]()
  for id in snapshots.keys:
    result[id] = instance.findController(id)

proc canonicalPropertyName(registry: ResourceRegistry, kind, name: string): string =
  let descriptor = registry.findViewPropertyDescriptor(kind, name)
  if descriptor.isNone or descriptor.get().aliasOf.len == 0:
    name
  else:
    descriptor.get().aliasOf

proc propertyValue(
    registry: ResourceRegistry, node: ViewNodeResource, canonicalName: string
): Option[ResourceValue] =
  for property in node.properties:
    if registry.canonicalPropertyName(node.kind, property.name) == canonicalName:
      return some(property.value)
  none(ResourceValue)

proc changedPropertyNames(
    registry: ResourceRegistry, previous, next: ViewNodeResource
): seq[string] =
  var names = initHashSet[string]()
  for property in previous.properties:
    names.incl registry.canonicalPropertyName(previous.kind, property.name)
  for property in next.properties:
    names.incl registry.canonicalPropertyName(next.kind, property.name)
  for name in names:
    result.add name
  result.sort()

proc imageDependencyChanged(
    previous, next: Option[ResourceValue],
    previousContext, nextContext: ResourcePropertyContext,
): bool =
  if previous.isNone or next.isNone:
    return
  let
    previousValue = previous.get()
    nextValue = next.get()
  if previousValue.kind != rvReference or nextValue.kind != rvReference or
      previousValue.referenceValue.kind != rrImage or
      nextValue.referenceValue.kind != rrImage or
      previousValue.referenceValue.id != nextValue.referenceValue.id or
      previousContext.imageFor.isNil or nextContext.imageFor.isNil:
    return
  previousContext.imageFor(previousValue.referenceValue.id) !=
    nextContext.imageFor(nextValue.referenceValue.id)

proc preparePropertyUpdates(
    preview: ResourcePreview,
    previous, next: ViewSnapshot,
    previousView, stagedView: View,
    previousContext, nextContext: ResourcePropertyContext,
    updates: var seq[PropertyUpdate],
): bool =
  ## Returns false when a changed property cannot be safely read back. The caller
  ## then uses the staged replacement instead of risking stale state.
  result = true
  for name in preview.xRegistry.changedPropertyNames(previous.node, next.node):
    let
      previousAuthored = preview.xRegistry.propertyValue(previous.node, name)
      nextAuthored = preview.xRegistry.propertyValue(next.node, name)
      current = preview.xRegistry.readViewProperty(
        previous.node.kind, previousView, name, previousContext
      )
      desired = preview.xRegistry.readViewProperty(
        next.node.kind, stagedView, name, nextContext
      )
    if current.read and desired.read:
      if current.value != desired.value or
          imageDependencyChanged(
            previousAuthored, nextAuthored, previousContext, nextContext
          ):
        updates.add PropertyUpdate(
          resourceId: next.node.id,
          kind: next.node.kind,
          name: name,
          view: previousView,
          value: desired.value,
          rollbackValue: current.value,
          path: next.path & ".properties." & name,
        )
    elif previousAuthored != nextAuthored:
      return false

proc rollbackProperties(
    preview: ResourcePreview,
    updates: openArray[PropertyUpdate],
    lastApplied: int,
    context: ResourcePropertyContext,
    diagnostics: var ResourceDiagnostics,
) =
  if lastApplied < 0:
    return
  for index in countdown(lastApplied, 0):
    let update = updates[index]
    try:
      if not preview.xRegistry.applyViewProperty(
        update.kind,
        update.view,
        resourceProperty(update.name, update.rollbackValue),
        context,
      ):
        diagnostics.add(
          rdsError,
          "resource.preview.rollbackFailed",
          "property '" & update.name & "' could not be rolled back",
          path = update.path,
          resourceId = update.resourceId,
        )
    except CatchableError as error:
      diagnostics.add(
        rdsError,
        "resource.preview.rollbackFailed",
        "property '" & update.name & "' rollback failed: " & error.msg,
        path = update.path,
        resourceId = update.resourceId,
      )

proc detachViewHierarchy(
    registry: ResourceRegistry,
    snapshots: Table[ResourceId, ViewSnapshot],
    views: Table[ResourceId, View],
) =
  for id, snapshot in snapshots.pairs:
    if not snapshot.parentId.isEmpty:
      let
        parentSnapshot = snapshots.getOrDefault(snapshot.parentId)
        parent = views.getOrDefault(snapshot.parentId)
        child = views.getOrDefault(id)
      if not parent.isNil and not child.isNil:
        registry.detachChild(parentSnapshot.node.kind, parent, child)

proc attachViewHierarchy(
    registry: ResourceRegistry,
    nodes: openArray[ViewNodeResource],
    views: Table[ResourceId, View],
) =
  for node in nodes:
    let parent = views.getOrDefault(node.id)
    for childNode in node.children:
      let child = views.getOrDefault(childNode.id)
      if not parent.isNil and not child.isNil:
        registry.attachChild(node.kind, parent, child)
    attachViewHierarchy(registry, node.children, views)

proc detachControllerHierarchy(
    snapshots: Table[ResourceId, ControllerSnapshot],
    controllers: Table[ResourceId, ViewController],
) =
  for id, snapshot in snapshots.pairs:
    if not snapshot.parentId.isEmpty:
      let controller = controllers.getOrDefault(id)
      if not controller.isNil:
        discard controller.removeFromParentViewController()

proc configureControllerHierarchy(
    nodes: openArray[ControllerNodeResource],
    controllers: Table[ResourceId, ViewController],
    views: Table[ResourceId, View],
) =
  for node in nodes:
    let controller = controllers.getOrDefault(node.id)
    if not controller.isNil:
      controller.setView(views.getOrDefault(node.viewId))
      for childNode in node.children:
        let child = controllers.getOrDefault(childNode.id)
        if not child.isNil:
          controller.addChildViewController(child)
    configureControllerHierarchy(node.children, controllers, views)

proc detachRoots(bundle: ResourceBundle, views: Table[ResourceId, View], host: View) =
  if host.isNil:
    return
  for node in bundle.views:
    let view = views.getOrDefault(node.id)
    if not view.isNil and view.superview() == host:
      view.removeFromSuperview()

proc attachRoots(bundle: ResourceBundle, views: Table[ResourceId, View], host: View) =
  if host.isNil:
    return
  for node in bundle.views:
    let view = views.getOrDefault(node.id)
    if not view.isNil:
      view.translatesAutoresizingMaskIntoConstraints = false
      host.addSubview(view)

proc restorePreviousGraph(
    preview: ResourcePreview,
    nextBundle: ResourceBundle,
    nextViews: Table[ResourceId, View],
    nextControllers: Table[ResourceId, ViewController],
    host: View,
) =
  detachRoots(nextBundle, nextViews, host)
  detachControllerHierarchy(nextBundle.controllerSnapshots(), nextControllers)
  for id, controller in nextControllers.pairs:
    if preview.xControllers.getOrDefault(id) != controller:
      controller.setView(nil)
  preview.xRegistry.detachViewHierarchy(nextBundle.viewSnapshots(), nextViews)
  preview.xRegistry.attachViewHierarchy(preview.xBundle.views, preview.xViews)
  configureControllerHierarchy(
    preview.xBundle.controllers, preview.xControllers, preview.xViews
  )
  attachRoots(preview.xBundle, preview.xViews, host)

proc rewireWindows(
    bundle: ResourceBundle,
    instance: ResourceInstance,
    views: Table[ResourceId, View],
    controllers: Table[ResourceId, ViewController],
) =
  for resource in bundle.windows:
    let window = instance.findWindow(resource.id)
    if window.isNil:
      continue
    if not resource.controllerId.isEmpty:
      let windowController = instance.findWindowController(resource.id)
      if not windowController.isNil:
        windowController.setViewController(
          controllers.getOrDefault(resource.controllerId)
        )
    elif not resource.contentViewId.isEmpty:
      window.setContentView(views.getOrDefault(resource.contentViewId))
    if not resource.initialFirstResponderId.isEmpty:
      window.setInitialFirstResponder(
        views.getOrDefault(resource.initialFirstResponderId)
      )

proc collectMenuCommands(
    items: openArray[MenuItemResource], commands: var Table[ResourceId, ResourceId]
) =
  for item in items:
    commands[item.id] = item.commandId
    collectMenuCommands(item.children, commands)

proc rewireMenuModels(
    models: var seq[MenuItemModel],
    itemCommands: Table[ResourceId, ResourceId],
    bundle: ResourceBundle,
    context: ResourceInstantiationContext,
    instance: ResourceInstance,
    views: Table[ResourceId, View],
    controllers: Table[ResourceId, ViewController],
) =
  for model in models.mitems:
    let itemId = resourceId(model.identifier)
    if itemCommands.hasKey(itemId):
      let command = bundle.findCommand(itemCommands[itemId])
      if command.isSome:
        case command.get().targetKind
        of rctResponderChain:
          model.target = nil
        of rctApplication:
          model.target = context.applicationTarget
        of rctExplicit:
          let targetId = command.get().targetId
          if context.targets.hasKey(targetId):
            model.target = context.targets[targetId]
          elif views.hasKey(targetId):
            model.target = DynamicAgent(views[targetId])
          elif controllers.hasKey(targetId):
            model.target = DynamicAgent(controllers[targetId])
          elif not instance.findWindow(targetId).isNil:
            model.target = DynamicAgent(instance.findWindow(targetId))
          elif not instance.findMenu(targetId).isNil:
            model.target = DynamicAgent(instance.findMenu(targetId))
          else:
            model.target = nil
    rewireMenuModels(
      model.children, itemCommands, bundle, context, instance, views, controllers
    )

proc rewireMenus(
    bundle: ResourceBundle,
    context: ResourceInstantiationContext,
    instance: ResourceInstance,
    views: Table[ResourceId, View],
    controllers: Table[ResourceId, ViewController],
) =
  var itemCommands = initTable[ResourceId, ResourceId]()
  for resource in bundle.menus:
    collectMenuCommands(resource.items, itemCommands)
  for resource in bundle.menus:
    let menu = instance.findMenu(resource.id)
    if not menu.isNil:
      var models = menu.itemModels()
      rewireMenuModels(
        models, itemCommands, bundle, context, instance, views, controllers
      )
      menu.itemModels = models

proc addChanges(
    previous, next: Table[ResourceId, ViewSnapshot],
    reused: HashSet[ResourceId],
    updated: HashSet[ResourceId],
    changes: var seq[ResourcePreviewChange],
) =
  var ids = initHashSet[ResourceId]()
  for id in previous.keys:
    ids.incl id
  for id in next.keys:
    ids.incl id
  var sortedIds: seq[ResourceId]
  for id in ids:
    sortedIds.add id
  sortedIds.sort(
    proc(a, b: ResourceId): int =
      cmp($a, $b)
  )
  for id in sortedIds:
    let
      hadPrevious = previous.hasKey(id)
      hasNext = next.hasKey(id)
    var change = ResourcePreviewChange(
      resourceId: id,
      objectKind: rpokView,
      previousPath:
        if hadPrevious:
          previous[id].path
        else:
          "",
      path:
        if hasNext:
          next[id].path
        else:
          "",
    )
    if not hadPrevious:
      change.kinds.incl rpckInserted
    elif not hasNext:
      change.kinds.incl rpckRemoved
    elif id in reused:
      change.kinds.incl rpckReused
      if previous[id].parentId != next[id].parentId:
        change.kinds.incl rpckMoved
      if id in updated:
        change.kinds.incl rpckUpdated
    else:
      change.kinds.incl rpckReplaced
    changes.add change

proc addChanges(
    previous, next: Table[ResourceId, ControllerSnapshot],
    reused: HashSet[ResourceId],
    changes: var seq[ResourcePreviewChange],
) =
  var ids = initHashSet[ResourceId]()
  for id in previous.keys:
    ids.incl id
  for id in next.keys:
    ids.incl id
  var sortedIds: seq[ResourceId]
  for id in ids:
    sortedIds.add id
  sortedIds.sort(
    proc(a, b: ResourceId): int =
      cmp($a, $b)
  )
  for id in sortedIds:
    let
      hadPrevious = previous.hasKey(id)
      hasNext = next.hasKey(id)
    var change = ResourcePreviewChange(
      resourceId: id,
      objectKind: rpokController,
      previousPath:
        if hadPrevious:
          previous[id].path
        else:
          "",
      path:
        if hasNext:
          next[id].path
        else:
          "",
    )
    if not hadPrevious:
      change.kinds.incl rpckInserted
    elif not hasNext:
      change.kinds.incl rpckRemoved
    elif id in reused:
      change.kinds.incl rpckReused
      if previous[id].parentId != next[id].parentId:
        change.kinds.incl rpckMoved
    else:
      change.kinds.incl rpckReplaced
    changes.add change

proc update*(
    preview: ResourcePreview,
    bundle: ResourceBundle,
    revision: Natural,
    host: View = nil,
): ResourcePreviewUpdateResult =
  ## Reconciles one valid resource revision into the installed preview.
  ##
  ## Full construction is used as a preflight graph. Existing view and controller
  ## identities are committed only after getter-backed property updates and all
  ## hierarchy changes succeed. On failure, mappings and the installed graph stay
  ## at the previous revision.
  result.revision = if preview.hasRevision: preview.xRevision else: revision
  var construction: ResourceInstantiationResult
  try:
    construction = bundle.instantiateResources(
      preview.xRegistry, preview.xContext, preview.xValidationOptions
    )
  except CatchableError as error:
    result.diagnostics.add(
      rdsError,
      "resource.preview.preflightFailed",
      "preview construction preflight failed: " & error.msg,
    )
    return
  result.diagnostics = construction.diagnostics
  if not construction.instantiated:
    return

  let
    previousViewSnapshots = preview.xBundle.viewSnapshots()
    nextViewSnapshots = bundle.viewSnapshots()
    previousControllerSnapshots = preview.xBundle.controllerSnapshots()
    nextControllerSnapshots = bundle.controllerSnapshots()
    previousPropertyContext =
      initResourcePropertyContext(preview.xBundle, preview.xInstance, preview.xContext)
    nextPropertyContext =
      initResourcePropertyContext(bundle, construction.instance, preview.xContext)
    stagedViewMap = stagedViews(nextViewSnapshots, construction.instance)
    stagedControllerMap =
      stagedControllers(nextControllerSnapshots, construction.instance)
  var
    nextViews = initTable[ResourceId, View]()
    nextControllers = initTable[ResourceId, ViewController]()
    reusedViews = initHashSet[ResourceId]()
    reusedControllers = initHashSet[ResourceId]()
    updatedViews = initHashSet[ResourceId]()
    propertyUpdates: seq[PropertyUpdate]

  for id, snapshot in nextViewSnapshots.pairs:
    let stagedView = construction.instance.findView(id)
    if preview.xHasRevision and previousViewSnapshots.hasKey(id) and
        previousViewSnapshots[id].node.kind == snapshot.node.kind:
      let previousView = preview.xViews.getOrDefault(id)
      var candidateUpdates: seq[PropertyUpdate]
      if not previousView.isNil and
          preview.preparePropertyUpdates(
            previousViewSnapshots[id],
            snapshot,
            previousView,
            stagedView,
            previousPropertyContext,
            nextPropertyContext,
            candidateUpdates,
          ):
        nextViews[id] = previousView
        reusedViews.incl id
        if candidateUpdates.len > 0:
          updatedViews.incl id
          propertyUpdates.add candidateUpdates
        continue
    nextViews[id] = stagedView

  for id, snapshot in nextControllerSnapshots.pairs:
    let stagedController = construction.instance.findController(id)
    if preview.xHasRevision and previousControllerSnapshots.hasKey(id) and
        previousControllerSnapshots[id].node.kind == snapshot.node.kind and
        previousControllerSnapshots[id].node.viewId == snapshot.node.viewId:
      let previousController = preview.xControllers.getOrDefault(id)
      if not previousController.isNil:
        nextControllers[id] = previousController
        reusedControllers.incl id
        continue
    nextControllers[id] = stagedController

  let nextLayout = bundle.instantiateResourceLayout(
    proc(id: ResourceId): View =
      nextViews.getOrDefault(id),
    activate = false,
  )
  for diagnostic in nextLayout.diagnostics():
    result.diagnostics.entries.add diagnostic
  if not nextLayout.instantiated:
    return

  for update in propertyUpdates:
    try:
      let stagedView = construction.instance.findView(update.resourceId)
      if not preview.xRegistry.applyViewProperty(
        update.kind,
        stagedView,
        resourceProperty(update.name, update.value),
        nextPropertyContext,
      ):
        result.diagnostics.add(
          rdsError,
          "resource.preview.propertyPreflightFailed",
          "property '" & update.name & "' failed preview preflight",
          path = update.path,
          resourceId = update.resourceId,
        )
        return
    except CatchableError as error:
      result.diagnostics.add(
        rdsError,
        "resource.preview.propertyPreflightFailed",
        "property '" & update.name & "' failed preview preflight: " & error.msg,
        path = update.path,
        resourceId = update.resourceId,
      )
      return

  var lastApplied = -1
  for index, update in propertyUpdates:
    try:
      if not preview.xRegistry.applyViewProperty(
        update.kind,
        update.view,
        resourceProperty(update.name, update.value),
        nextPropertyContext,
      ):
        result.diagnostics.add(
          rdsError,
          "resource.preview.propertyApplyFailed",
          "property '" & update.name & "' could not be reconciled",
          path = update.path,
          resourceId = update.resourceId,
        )
        preview.rollbackProperties(
          propertyUpdates, lastApplied, previousPropertyContext, result.diagnostics
        )
        return
      lastApplied = index
    except CatchableError as error:
      result.diagnostics.add(
        rdsError,
        "resource.preview.propertyApplyFailed",
        "property '" & update.name & "' reconciliation failed: " & error.msg,
        path = update.path,
        resourceId = update.resourceId,
      )
      preview.rollbackProperties(
        propertyUpdates, lastApplied, previousPropertyContext, result.diagnostics
      )
      return

  try:
    preview.xLayout.deactivate()
    detachRoots(preview.xBundle, preview.xViews, host)
    detachControllerHierarchy(previousControllerSnapshots, preview.xControllers)
    detachControllerHierarchy(nextControllerSnapshots, stagedControllerMap)
    for id, controller in preview.xControllers.pairs:
      if id notin reusedControllers:
        controller.setView(nil)
    preview.xRegistry.detachViewHierarchy(previousViewSnapshots, preview.xViews)
    preview.xRegistry.detachViewHierarchy(nextViewSnapshots, stagedViewMap)
    preview.xRegistry.attachViewHierarchy(bundle.views, nextViews)
    configureControllerHierarchy(bundle.controllers, nextControllers, nextViews)
    rewireWindows(bundle, construction.instance, nextViews, nextControllers)
    rewireMenus(
      bundle, preview.xContext, construction.instance, nextViews, nextControllers
    )
    nextLayout.activate()
    attachRoots(bundle, nextViews, host)
  except CatchableError as error:
    var rollbackMessages: seq[string]
    try:
      nextLayout.deactivate()
      preview.restorePreviousGraph(bundle, nextViews, nextControllers, host)
    except CatchableError as rollbackError:
      rollbackMessages.add rollbackError.msg
    try:
      preview.xLayout.activate()
    except CatchableError as rollbackError:
      rollbackMessages.add rollbackError.msg
    if rollbackMessages.len > 0:
      result.diagnostics.add(
        rdsError,
        "resource.preview.rollbackFailed",
        "preview hierarchy/layout rollback failed: " & rollbackMessages.join("; "),
      )
    preview.rollbackProperties(
      propertyUpdates, lastApplied, previousPropertyContext, result.diagnostics
    )
    result.diagnostics.add(
      rdsError,
      "resource.preview.hierarchyApplyFailed",
      "preview hierarchy reconciliation failed: " & error.msg,
    )
    return

  addChanges(
    previousViewSnapshots, nextViewSnapshots, reusedViews, updatedViews, result.changes
  )
  addChanges(
    previousControllerSnapshots, nextControllerSnapshots, reusedControllers,
    result.changes,
  )
  preview.xBundle = bundle
  preview.xInstance = construction.instance
  preview.xViews = move nextViews
  preview.xControllers = move nextControllers
  preview.xLayout = nextLayout
  preview.xRevision = revision
  preview.xHasRevision = true
  result.applied = true
  result.revision = revision

proc readViewProperty*(
    preview: ResourcePreview, id: ResourceId, name: string
): ResourcePropertyReadResult =
  ## Reads a live, runtime-normalized property value through the registry getter.
  if preview.isNil or not preview.xHasRevision:
    return
  let
    snapshot = preview.xBundle.findView(id)
    view = preview.xViews.getOrDefault(id)
  if snapshot.isSome and not view.isNil:
    let context =
      initResourcePropertyContext(preview.xBundle, preview.xInstance, preview.xContext)
    result =
      preview.xRegistry.readViewProperty(snapshot.get().kind, view, name, context)

proc resourceIdForView*(preview: ResourcePreview, view: View): Option[ResourceId] =
  ## Maps a hit view or one of its implementation subviews to a resource id.
  var candidate = view
  while not candidate.isNil:
    for id, resourceView in preview.xViews.pairs:
      if resourceView == candidate:
        return some(id)
    candidate = candidate.superview()
  none(ResourceId)

proc geometry*(
    preview: ResourcePreview, id: ResourceId, referenceView: View
): ResourcePreviewGeometry =
  let view = preview.findView(id)
  if view.isNil:
    return
  ResourcePreviewGeometry(
    found: true,
    resourceId: id,
    view: view,
    bounds: view.bounds(),
    frameInReferenceView: view.rectToView(view.bounds(), referenceView),
  )

proc hitTest*(preview: ResourcePreview, host: View, point: Point): ResourcePreviewHit =
  ## Hit-tests a preview host and maps implementation subviews to resources.
  if preview.isNil or host.isNil:
    return
  let hit = host.hitTest(point)
  if hit.isNil:
    return
  let id = preview.resourceIdForView(hit)
  if id.isNone:
    return
  ResourcePreviewHit(
    found: true,
    resourceId: id.get(),
    hitView: hit,
    resourceView: preview.findView(id.get()),
    geometry: preview.geometry(id.get(), host),
  )
