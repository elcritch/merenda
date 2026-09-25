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
    xViewIds: Table[pointer, ResourceId]
    xViewSnapshots: Table[ResourceId, ViewSnapshot]
    xControllers: Table[ResourceId, ViewController]
    xLayout: ResourceLayoutInstance
    xHost: View
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
    snapshots[node.id] = ViewSnapshot(
      node: ViewNodeResource(id: node.id, kind: node.kind, properties: node.properties),
      parentId: parentId,
      path: nodePath,
    )
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
      if previous[id].parentId != next[id].parentId or previous[id].path != next[id].path:
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

proc sameNonViewResources(previous, next: ResourceBundle): bool =
  previous.format == next.format and previous.version == next.version and
    previous.namespace == next.namespace and previous.controllers == next.controllers and
    previous.windows == next.windows and previous.menus == next.menus and
    previous.commands == next.commands and previous.images == next.images and
    previous.localizations == next.localizations and
    previous.keyBindings == next.keyBindings and previous.themes == next.themes

proc updateProperties(
    preview: ResourcePreview,
    bundle: ResourceBundle,
    revision: Natural,
    snapshots: Table[ResourceId, ViewSnapshot],
    updateResult: var ResourcePreviewUpdateResult,
): bool =
  ## Handles revisions that keep the resource graph and all non-view resources.
  ## Stage just the changed views, then apply getter-backed values transactionally.
  if not preview.xHasRevision or not sameNonViewResources(preview.xBundle, bundle) or
      snapshots.len != preview.xViewSnapshots.len:
    return
  for id, snapshot in snapshots:
    if not preview.xViewSnapshots.hasKey(id):
      return
    let previous = preview.xViewSnapshots[id]
    if snapshot.node.kind != previous.node.kind or snapshot.path != previous.path:
      return

  var options = preview.xValidationOptions
  if options.assetBasePath.len == 0:
    options.assetBasePath = preview.xContext.assetBasePath
  updateResult.diagnostics = bundle.validateResources(preview.xRegistry, options)
  if updateResult.diagnostics.hasErrors:
    return true

  let context = initResourcePropertyContext(bundle, preview.xInstance, preview.xContext)
  var
    updates: seq[PropertyUpdate]
    reused = initHashSet[ResourceId]()
    updated = initHashSet[ResourceId]()
  let layoutChanged =
    preview.xBundle.layoutGuides != bundle.layoutGuides or
    preview.xBundle.layoutConstraints != bundle.layoutConstraints
  var nextLayout = preview.xLayout
  if layoutChanged:
    let views = preview.xViews
    nextLayout = bundle.instantiateResourceLayout(
      proc(id: ResourceId): View =
        views.getOrDefault(id),
      activate = false,
    )
    for diagnostic in nextLayout.diagnostics():
      updateResult.diagnostics.entries.add diagnostic
    if not nextLayout.instantiated:
      return true
  for id, snapshot in snapshots:
    reused.incl id
    let previous = preview.xViewSnapshots[id]
    if previous.node.properties != snapshot.node.properties:
      var names: seq[string]
      for name in preview.xRegistry.changedPropertyNames(previous.node, snapshot.node):
        if preview.xRegistry.propertyValue(previous.node, name) !=
            preview.xRegistry.propertyValue(snapshot.node, name):
          names.add name
      if names.len > 0:
        let currentView = preview.xViews[id]
        var staged: View
        try:
          var frame = AutoRect
          for property in snapshot.node.properties:
            if property.name == "frame" and property.value.kind == rvRect:
              frame = property.value.rectValue
          staged = preview.xRegistry.constructView(snapshot.node.kind, frame)
          if staged.isNil:
            return false
          for property in snapshot.node.properties:
            if not preview.xRegistry.applyViewProperty(
              snapshot.node.kind, staged, property, context
            ):
              updateResult.diagnostics.add(
                rdsError,
                "resource.preview.propertyPreflightFailed",
                "property '" & property.name & "' failed preview preflight",
                path = snapshot.path & ".properties." & property.name,
                resourceId = id,
              )
              return true
          for name in names:
            let
              current = preview.xRegistry.readViewProperty(
                snapshot.node.kind, currentView, name, context
              )
              desired = preview.xRegistry.readViewProperty(
                snapshot.node.kind, staged, name, context
              )
            if not current.read or not desired.read:
              return false
            updates.add PropertyUpdate(
              resourceId: id,
              kind: snapshot.node.kind,
              name: name,
              view: currentView,
              value: desired.value,
              rollbackValue: current.value,
              path: snapshot.path & ".properties." & name,
            )
            updated.incl id
        except CatchableError as error:
          updateResult.diagnostics.add(
            rdsError,
            "resource.preview.propertyPreflightFailed",
            "preview property preflight failed: " & error.msg,
            path = snapshot.path,
            resourceId = id,
          )
          return true

  for index, update in updates:
    try:
      if not preview.xRegistry.applyViewProperty(
        update.kind, update.view, resourceProperty(update.name, update.value), context
      ):
        raise newException(ValueError, "property setter rejected the value")
    except CatchableError as error:
      # A setter can mutate its view before failing, so include the attempted setter.
      preview.rollbackProperties(updates, index, context, updateResult.diagnostics)
      updateResult.diagnostics.add(
        rdsError,
        "resource.preview.propertyApplyFailed",
        "property '" & update.name & "' reconciliation failed: " & error.msg,
        path = update.path,
        resourceId = update.resourceId,
      )
      return true

  if layoutChanged:
    try:
      preview.xLayout.deactivate()
      nextLayout.activate()
    except CatchableError as error:
      nextLayout.deactivate()
      preview.xLayout.activate()
      preview.rollbackProperties(
        updates, updates.high, context, updateResult.diagnostics
      )
      updateResult.diagnostics.add(
        rdsError,
        "resource.preview.layoutApplyFailed",
        "layout reconciliation failed: " & error.msg,
      )
      return true
    preview.xLayout = nextLayout
    preview.xInstance.rebindResourceIdentities(
      preview.xViews, preview.xControllers, nextLayout
    )
  addChanges(preview.xViewSnapshots, snapshots, reused, updated, updateResult.changes)
  preview.xBundle = bundle
  preview.xViewSnapshots = snapshots
  preview.xRevision = revision
  updateResult.revision = revision
  updateResult.applied = true
  true

proc update*(
    preview: ResourcePreview,
    bundle: ResourceBundle,
    revision: Natural,
    host: View = nil,
): ResourcePreviewUpdateResult =
  ## Reconciles one valid resource revision into the installed preview.
  ##
  ## Property edits stage only changed views and retain the installed hierarchy.
  ## Structural edits use full construction as a preflight graph. View and controller
  ## identities are committed only after getter-backed property updates and all
  ## hierarchy changes succeed. On failure, mappings and the installed graph stay
  ## at the previous revision.
  result.revision = if preview.hasRevision: preview.xRevision else: revision
  let nextViewSnapshots = bundle.viewSnapshots()
  if host == preview.xHost and
      preview.updateProperties(bundle, revision, nextViewSnapshots, result):
    return
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
    previousViewSnapshots = preview.xViewSnapshots
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
    lastApplied = index
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
  construction.instance.rebindResourceIdentities(nextViews, nextControllers, nextLayout)
  preview.xInstance = move construction.instance
  preview.xViews = move nextViews
  preview.xViewSnapshots = nextViewSnapshots
  preview.xViewIds.clear()
  for id, view in preview.xViews:
    preview.xViewIds[cast[pointer](view)] = id
  preview.xControllers = move nextControllers
  preview.xLayout = nextLayout
  preview.xHost = host
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
  let view = preview.xViews.getOrDefault(id)
  if preview.xViewSnapshots.hasKey(id) and not view.isNil:
    let context =
      initResourcePropertyContext(preview.xBundle, preview.xInstance, preview.xContext)
    result = preview.xRegistry.readViewProperty(
      preview.xViewSnapshots[id].node.kind, view, name, context
    )

proc resourceIdForView*(preview: ResourcePreview, view: View): Option[ResourceId] =
  ## Maps a hit view or one of its implementation subviews to a resource id.
  var candidate = view
  while not candidate.isNil:
    let key = cast[pointer](candidate)
    if preview.xViewIds.hasKey(key):
      return some(preview.xViewIds[key])
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
  ## Picks preview content even when the editor host intercepts design input.
  if preview.isNil or host.isNil or
      (host.clipsToBounds() and not host.pointInside(point)):
    return
  var hit: View
  var level = low(int)
  let children = host.subviews()
  for index in countdown(children.high, 0):
    let child = children[index]
    let candidate = child.hitTest(child.pointFromView(point, host))
    if not candidate.isNil:
      let candidateLevel = max(
        child.hitTestLevel(child.pointFromView(point, host)),
        candidate.hitTestLevel(candidate.pointFromView(point, host)),
      )
      if hit.isNil or candidateLevel > level:
        hit = candidate
        level = candidateLevel
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

proc anchorPosition(view: View, attribute: LayoutAttribute, reference: View): float32 =
  let frame = view.rectToView(view.bounds(), reference)
  case attribute
  of atLeft, atLeading:
    frame.x
  of atRight, atTrailing:
    frame.x + frame.w
  of atTop:
    frame.y
  of atBottom:
    frame.y + frame.h
  of atWidth:
    frame.w
  of atHeight:
    frame.h
  of atCenterX:
    frame.x + frame.w / 2
  of atCenterY:
    frame.y + frame.h / 2
  of atFirstBaseline:
    view.pointToView(initPoint(0, view.firstBaselineOffset()), reference).y
  of atLastBaseline:
    view.pointToView(
      initPoint(0, view.bounds().h - view.lastBaselineOffset()), reference
    ).y
  of atNotAnAttribute:
    0.0'f32

proc layoutDiagnostics*(
    preview: ResourcePreview, reference: View
): ResourceDiagnostics =
  ## Evaluates authored constraints after layout, including constraints the solver
  ## could not satisfy because of conflicting constraints or control size limits.
  if preview.isNil or not preview.hasRevision:
    return
  for index, resource in preview.xBundle.layoutConstraints:
    let constraint = preview.findLayoutConstraint(resource.id)
    if not constraint.isNil and constraint.active():
      let first =
        constraint.firstItem().anchorPosition(constraint.firstAttribute(), reference)
      let second =
        if constraint.secondItem().isNil:
          0.0'f32
        else:
          constraint.secondItem().anchorPosition(
            constraint.secondAttribute(), reference
          )
      let delta = first - (second * constraint.multiplier() + constraint.constant())
      let satisfied =
        case constraint.relation()
        of lrEqual:
          abs(delta) <= 0.5'f32
        of lrLessThanOrEqual:
          delta <= 0.5'f32
        of lrGreaterThanOrEqual:
          delta >= -0.5'f32
      if not satisfied:
        result.add(
          rdsWarning,
          "resource.layout.unsatisfied",
          "constraint is not satisfied; check its anchors, priority, and the view's size limits",
          path = "layoutConstraints[" & $index & "]",
          resourceId = resource.id,
        )
