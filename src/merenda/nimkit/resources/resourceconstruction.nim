## Explicit construction of identity-bearing NimKit objects from validated resources.

import std/[os, tables]

import sigils/selectors

import ../app/[viewcontrollers, windowcontrollers, windows]
import ../controls/menus
import ../drawing/images
import ../foundation/[selectors as nimkitSelectors, types]
import ../responder/keybindings
import ../themes
import ../view/views
import ./[resourcecore, resourceregistry, resourcevalidation]

type
  ResourceLookupError* = object of CatchableError

  ResourceInstantiationContext* = object
    locale*: string
    assetBasePath*: string
    applicationTarget*: DynamicAgent
    targets*: Table[ResourceId, DynamicAgent]

  ResourceInstance* = object
    viewsValue: Table[ResourceId, View]
    controllersValue: Table[ResourceId, ViewController]
    windowsValue: Table[ResourceId, Window]
    windowControllersValue: Table[ResourceId, WindowController]
    menusValue: Table[ResourceId, Menu]
    imagesValue: Table[ResourceId, ImageResource]
    themesValue: Table[ResourceId, Theme]
    keyBindingsValue: Table[ResourceId, KeyBindingTable]

  ResourceInstantiationResult* = object
    instance*: ResourceInstance
    diagnostics*: ResourceDiagnostics

  ConstructionState = object
    bundle: ResourceBundle
    registry: ResourceRegistry
    context: ResourceInstantiationContext
    instance: ResourceInstance
    diagnostics: ResourceDiagnostics

func initResourceInstantiationContext*(
    locale = "", assetBasePath = ""
): ResourceInstantiationContext =
  ResourceInstantiationContext(
    locale: locale,
    assetBasePath: assetBasePath,
    targets: initTable[ResourceId, DynamicAgent](),
  )

proc initResourceInstance(): ResourceInstance =
  ResourceInstance(
    viewsValue: initTable[ResourceId, View](),
    controllersValue: initTable[ResourceId, ViewController](),
    windowsValue: initTable[ResourceId, Window](),
    windowControllersValue: initTable[ResourceId, WindowController](),
    menusValue: initTable[ResourceId, Menu](),
    imagesValue: initTable[ResourceId, ImageResource](),
    themesValue: initTable[ResourceId, Theme](),
    keyBindingsValue: initTable[ResourceId, KeyBindingTable](),
  )

func instantiated*(instantiation: ResourceInstantiationResult): bool =
  not instantiation.diagnostics.hasErrors

proc missingResource(kind: string, id: ResourceId) {.noinline, noreturn.} =
  raise
    newException(ResourceLookupError, kind & " resource '" & $id & "' is unavailable")

proc findView*(instance: ResourceInstance, id: ResourceId): View =
  instance.viewsValue.getOrDefault(id)

proc view*(instance: ResourceInstance, id: ResourceId): View =
  result = instance.findView(id)
  if result.isNil:
    missingResource("view", id)

proc findController*(instance: ResourceInstance, id: ResourceId): ViewController =
  instance.controllersValue.getOrDefault(id)

proc controller*(instance: ResourceInstance, id: ResourceId): ViewController =
  result = instance.findController(id)
  if result.isNil:
    missingResource("controller", id)

proc findWindow*(instance: ResourceInstance, id: ResourceId): Window =
  instance.windowsValue.getOrDefault(id)

proc window*(instance: ResourceInstance, id: ResourceId): Window =
  result = instance.findWindow(id)
  if result.isNil:
    missingResource("window", id)

proc findWindowController*(
    instance: ResourceInstance, id: ResourceId
): WindowController =
  instance.windowControllersValue.getOrDefault(id)

proc findMenu*(instance: ResourceInstance, id: ResourceId): Menu =
  instance.menusValue.getOrDefault(id)

proc menu*(instance: ResourceInstance, id: ResourceId): Menu =
  result = instance.findMenu(id)
  if result.isNil:
    missingResource("menu", id)

proc findImage*(instance: ResourceInstance, id: ResourceId): ImageResource =
  instance.imagesValue.getOrDefault(id)

proc image*(instance: ResourceInstance, id: ResourceId): ImageResource =
  result = instance.findImage(id)
  if result.isNil:
    missingResource("image", id)

proc findTheme*(instance: ResourceInstance, id: ResourceId, theme: var Theme): bool =
  if instance.themesValue.hasKey(id):
    theme = instance.themesValue[id]
    return true

proc findKeyBindings*(
    instance: ResourceInstance, id: ResourceId, bindings: var KeyBindingTable
): bool =
  if instance.keyBindingsValue.hasKey(id):
    bindings = instance.keyBindingsValue[id]
    return true

proc toImageCachePolicy(value: ResourceImageCachePolicy): ImageCachePolicy =
  case value
  of ricDefault: icpDefault
  of ricAlways: icpAlways
  of ricNever: icpNever
  of ricBySize: icpBySize

proc toShortcutModifiers(
    modifiers: set[ResourceShortcutModifier]
): set[ShortcutModifier] =
  for modifier in modifiers:
    case modifier
    of rsmShift:
      result.incl smShift
    of rsmControl:
      result.incl smControl
    of rsmOption:
      result.incl smOption
    of rsmCommand:
      result.incl smCommand
    of rsmShortcut:
      result.incl smShortcut

proc enumNamed[T: enum](name: string, value: var T): bool =
  for candidate in T:
    if $candidate == name:
      value = candidate
      return true

proc bytesToString(data: openArray[byte]): string =
  result = newString(data.len)
  for index, value in data:
    result[index] = char(value)

proc resolveAssetPath(basePath, path: string): string =
  if path.isAbsolute or basePath.len == 0:
    path
  else:
    basePath / path

proc localizedValue(bundle: ResourceBundle, locale, key, fallback: string): string =
  if key.len == 0:
    return fallback
  var currentLocale = locale
  for _ in 0 ..< 16:
    var nextLocale: string
    for catalog in bundle.localizations:
      if catalog.locale == currentLocale:
        for entry in catalog.strings:
          if entry.key == key:
            return entry.value
        nextLocale = catalog.fallbackLocale
        break
    if nextLocale.len == 0 or nextLocale == currentLocale:
      break
    currentLocale = nextLocale
  for catalog in bundle.localizations:
    for entry in catalog.strings:
      if entry.key == key:
        return entry.value
  fallback

proc initResourcePropertyContext*(
    bundle: ResourceBundle,
    instance: ResourceInstance,
    context = initResourceInstantiationContext(),
): ResourcePropertyContext =
  ## Creates the bidirectional conversion context used by registry properties.
  ##
  ## Image getters are mapped back to stable resource identifiers by identity;
  ## localized getter values are intentionally returned as their resolved string.
  let
    bundleCopy = bundle
    instanceCopy = instance
    locale = context.locale
    imageIdFor = proc(image: ImageResource): ResourceId =
      for asset in bundleCopy.images:
        if instanceCopy.findImage(asset.id) == image:
          return asset.id
  ResourcePropertyContext(
    imageFor: proc(id: ResourceId): ImageResource =
      instanceCopy.findImage(id),
    imageIdFor: imageIdFor,
    textFor: proc(key, fallback: string): string =
      bundleCopy.localizedValue(locale, key, fallback),
  )

proc localizedValue(state: ConstructionState, text: ResourceText): string =
  state.bundle.localizedValue(state.context.locale, text.key, text.fallback)

proc findFrame(node: ViewNodeResource): Rect =
  for property in node.properties:
    if property.name == "frame" and property.value.kind == rvRect:
      return property.value.rectValue
  AutoRect

proc constructImages(state: var ConstructionState) =
  for index, asset in state.bundle.images:
    let path = "images[" & $index & "]"
    try:
      let policy = asset.cachePolicy.toImageCachePolicy()
      let image =
        case asset.sourceKind
        of risNamed:
          imageNamed(asset.name)
        of risFile:
          newImageResourceFromFile(
            state.context.assetBasePath.resolveAssetPath(asset.path),
            name = asset.name,
            cachePolicy = policy,
          )
        of risEmbedded:
          newImageResourceFromData(
            asset.data.bytesToString(), name = asset.name, cachePolicy = policy
          )
      if image.isNil:
        state.diagnostics.add(
          rdsError,
          "resource.image.unavailable",
          "image asset could not be resolved",
          path = path,
          resourceId = asset.id,
        )
      else:
        state.instance.imagesValue[asset.id] = image
    except CatchableError as error:
      state.diagnostics.add(
        rdsError,
        "resource.image.decodeFailed",
        "image asset could not be loaded: " & error.msg,
        path = path,
        resourceId = asset.id,
      )

proc toStyleValue(value: ResourceStyleValue): StyleValue =
  case value.kind
  of rsvMissing:
    missingStyleValue()
  of rsvColor:
    styleColor(value.color)
  of rsvFill:
    styleFill(value.color)
  of rsvLength:
    styleLength(value.length)
  of rsvSize:
    styleSize(value.size)
  of rsvInsets:
    styleInsets(value.insets)
  of rsvShadows:
    var shadows: seq[BoxShadow]
    for shadow in value.shadows:
      shadows.add initBoxShadow(
        if shadow.kind == rskDrop: bskDrop else: bskInset,
        shadow.color,
        shadow.x,
        shadow.y,
        shadow.blur,
        shadow.spread,
      )
    styleShadows(shadows)
  of rsvToken:
    styleToken(value.text)
  of rsvKeyword:
    styleKeyword(value.text)

proc applyThemeFragment(theme: var Theme, fragment: ThemeFragmentResource) =
  for token in fragment.tokens:
    theme[token.name] = token.value.toStyleValue()
  for rule in fragment.rules:
    var role: StyleRole
    discard rule.selector.role.enumNamed(role)
    var states: set[WidgetState]
    for name in rule.selector.states:
      var state: WidgetState
      if name.enumNamed(state):
        states.incl state
    let selector =
      initStyleSelector(role, states, rule.selector.id, rule.selector.classes)
    let patch = theme.stylePatch(selector)
    for style in rule.styles:
      patch.setStyle(style.name, style.value.toStyleValue())

proc constructThemes(state: var ConstructionState) =
  var remaining = state.bundle.themes
  while remaining.len > 0:
    var next: seq[ThemeFragmentResource]
    var madeProgress = false
    for fragment in remaining:
      if fragment.parentId.isEmpty or
          state.instance.themesValue.hasKey(fragment.parentId):
        var theme =
          if fragment.parentId.isEmpty:
            initTheme()
          else:
            state.instance.themesValue[fragment.parentId].clone()
        theme.applyThemeFragment(fragment)
        state.instance.themesValue[fragment.id] = theme
        madeProgress = true
      else:
        next.add fragment
    if not madeProgress:
      for fragment in next:
        state.diagnostics.add(
          rdsError,
          "resource.theme.parentCycle",
          "theme parent chain contains a cycle",
          resourceId = fragment.id,
          relatedId = fragment.parentId,
        )
      return
    remaining = move next

proc commandFor(state: ConstructionState, id: ResourceId): CommandResource =
  for command in state.bundle.commands:
    if command.id == id:
      return command

proc constructKeyBindings(state: var ConstructionState) =
  for tableResource in state.bundle.keyBindings:
    var table: KeyBindingTable
    for binding in tableResource.bindings:
      let command = state.commandFor(binding.commandId)
      let modifiers = binding.stroke.modifiers.toShortcutModifiers()
      let stroke =
        if binding.stroke.text.len > 0:
          initShortcutStroke(binding.stroke.text, modifiers)
        else:
          initKeyStroke(binding.stroke.keyCode, modifiers.toKeyModifiers())
      table.add(stroke, actionSelector(command.selector))
    state.instance.keyBindingsValue[tableResource.id] = table

proc allocateViews(
    state: var ConstructionState, nodes: openArray[ViewNodeResource], path: string
) =
  for index, node in nodes:
    let nodePath = path & "[" & $index & "]"
    try:
      let view = state.registry.constructView(node.kind, node.findFrame())
      if view.isNil:
        state.diagnostics.add(
          rdsError,
          "resource.view.constructionFailed",
          "view factory returned nil",
          path = nodePath,
          resourceId = node.id,
        )
      else:
        view.identifier = $node.id
        state.instance.viewsValue[node.id] = view
    except CatchableError as error:
      state.diagnostics.add(
        rdsError,
        "resource.view.constructionFailed",
        "view factory failed: " & error.msg,
        path = nodePath,
        resourceId = node.id,
      )
    state.allocateViews(node.children, nodePath & ".children")

proc propertyContext(state: ConstructionState): ResourcePropertyContext =
  initResourcePropertyContext(state.bundle, state.instance, state.context)

proc configureViews(
    state: var ConstructionState, nodes: openArray[ViewNodeResource], path: string
) =
  let propertyContext = state.propertyContext()
  for index, node in nodes:
    let
      nodePath = path & "[" & $index & "]"
      view = state.instance.viewsValue.getOrDefault(node.id)
    if not view.isNil:
      for propertyIndex, property in node.properties:
        try:
          if not state.registry.applyViewProperty(
            node.kind, view, property, propertyContext
          ):
            state.diagnostics.add(
              rdsError,
              "resource.property.applyFailed",
              "property '" & property.name & "' could not be applied",
              path = nodePath & ".properties[" & $propertyIndex & "]",
              resourceId = node.id,
            )
        except CatchableError as error:
          state.diagnostics.add(
            rdsError,
            "resource.property.applyFailed",
            "property '" & property.name & "' failed: " & error.msg,
            path = nodePath & ".properties[" & $propertyIndex & "]",
            resourceId = node.id,
          )
      state.configureViews(node.children, nodePath & ".children")
      for child in node.children:
        let childView = state.instance.viewsValue.getOrDefault(child.id)
        if not childView.isNil:
          state.registry.attachChild(node.kind, view, childView)

proc allocateControllers(
    state: var ConstructionState, nodes: openArray[ControllerNodeResource], path: string
) =
  for index, node in nodes:
    let nodePath = path & "[" & $index & "]"
    try:
      let controller = state.registry.constructController(node.kind)
      if controller.isNil:
        state.diagnostics.add(
          rdsError,
          "resource.controller.constructionFailed",
          "controller factory returned nil",
          path = nodePath,
          resourceId = node.id,
        )
      else:
        state.instance.controllersValue[node.id] = controller
    except CatchableError as error:
      state.diagnostics.add(
        rdsError,
        "resource.controller.constructionFailed",
        "controller factory failed: " & error.msg,
        path = nodePath,
        resourceId = node.id,
      )
    state.allocateControllers(node.children, nodePath & ".children")

proc configureControllers(
    state: var ConstructionState, nodes: openArray[ControllerNodeResource], path: string
) =
  for index, node in nodes:
    let
      nodePath = path & "[" & $index & "]"
      controller = state.instance.controllersValue.getOrDefault(node.id)
    if not controller.isNil:
      let view = state.instance.viewsValue.getOrDefault(node.viewId)
      if not view.isNil:
        controller.setView(view)
      state.configureControllers(node.children, nodePath & ".children")
      for childResource in node.children:
        let child = state.instance.controllersValue.getOrDefault(childResource.id)
        if not child.isNil:
          controller.addChildViewController(child)

proc targetFor(state: ConstructionState, command: CommandResource): DynamicAgent =
  case command.targetKind
  of rctResponderChain:
    discard
  of rctApplication:
    result = state.context.applicationTarget
  of rctExplicit:
    if state.context.targets.hasKey(command.targetId):
      return state.context.targets[command.targetId]
    if state.instance.viewsValue.hasKey(command.targetId):
      return DynamicAgent(state.instance.viewsValue[command.targetId])
    if state.instance.controllersValue.hasKey(command.targetId):
      return DynamicAgent(state.instance.controllersValue[command.targetId])
    if state.instance.windowsValue.hasKey(command.targetId):
      return DynamicAgent(state.instance.windowsValue[command.targetId])
    if state.instance.menusValue.hasKey(command.targetId):
      return DynamicAgent(state.instance.menusValue[command.targetId])

proc menuItemModel(
    state: var ConstructionState, item: MenuItemResource, path: string
): MenuItemModel =
  let
    command = state.commandFor(item.commandId)
    action =
      if item.commandId.isEmpty:
        ActionSelector()
      else:
        actionSelector(command.selector)
    target =
      if item.commandId.isEmpty:
        DynamicAgent(nil)
      else:
        state.targetFor(command)
  if not item.commandId.isEmpty and command.targetKind != rctResponderChain:
    if target.isNil:
      state.diagnostics.add(
        rdsError,
        "resource.command.targetUnavailable",
        "command target '" & $command.targetId & "' is unavailable",
        path = path & ".commandId",
        resourceId = item.id,
        relatedId = command.targetId,
      )
    elif not target.respondsTo(action):
      state.diagnostics.add(
        rdsError,
        "resource.command.selectorMismatch",
        "command target does not respond to selector '" & command.selector & "'",
        path = path & ".commandId",
        resourceId = item.id,
        relatedId = command.targetId,
      )

  var children: seq[MenuItemModel]
  for index, child in item.children:
    children.add state.menuItemModel(child, path & ".children[" & $index & "]")
  let
    shortcutModifiers = item.keyEquivalent.modifiers.toShortcutModifiers()
    keyEquivalent =
      if item.keyEquivalent.text.len > 0:
        initShortcutStroke(item.keyEquivalent.text, shortcutModifiers)
      elif item.keyEquivalent.keyCode != 0:
        initKeyStroke(item.keyEquivalent.keyCode, shortcutModifiers.toKeyModifiers())
      else:
        KeyStroke()
  initMenuItemModel(
    identifier = $item.id,
    title = state.localizedValue(item.title),
    subtitle = state.localizedValue(item.subtitle),
    state = bsOff,
    enabled = item.enabled != rfOff,
    hidden = item.hidden,
    separator = item.separator,
    image = state.instance.imagesValue.getOrDefault(item.imageId),
    action = action,
    target = target,
    keyEquivalent = keyEquivalent,
    hasKeyEquivalent = item.hasKeyEquivalent,
    tag = item.tag,
    validates = item.validates != rfOff,
    children = children,
  )

proc allocateMenus(state: var ConstructionState) =
  for resource in state.bundle.menus:
    state.instance.menusValue[resource.id] =
      newMenu(state.localizedValue(resource.title))

proc configureMenus(state: var ConstructionState) =
  for menuIndex, resource in state.bundle.menus:
    let menu = state.instance.menusValue[resource.id]
    var models: seq[MenuItemModel]
    for itemIndex, item in resource.items:
      models.add state.menuItemModel(
        item, "menus[" & $menuIndex & "].items[" & $itemIndex & "]"
      )
    menu.itemModels = models

proc allocateWindows(state: var ConstructionState) =
  for resource in state.bundle.windows:
    let
      title = state.localizedValue(resource.title)
      frame =
        if resource.frame.w > 0.0'f32 and resource.frame.h > 0.0'f32:
          resource.frame
        else:
          defaultWindowFrame()
      window =
        case resource.kind
        of rwWindow:
          newWindow(title, frame)
        of rwPanel:
          newPanel(title, frame)
    state.instance.windowsValue[resource.id] = window

proc configureWindows(state: var ConstructionState) =
  for index, resource in state.bundle.windows:
    let window = state.instance.windowsValue[resource.id]
    if not resource.controllerId.isEmpty:
      let viewController =
        state.instance.controllersValue.getOrDefault(resource.controllerId)
      if not viewController.isNil:
        let windowController = newWindowController(window)
        windowController.setViewController(viewController)
        state.instance.windowControllersValue[resource.id] = windowController
    elif not resource.contentViewId.isEmpty:
      let content = state.instance.viewsValue.getOrDefault(resource.contentViewId)
      if not content.isNil:
        window.setContentView(content)

    if not resource.initialFirstResponderId.isEmpty:
      let responder =
        state.instance.viewsValue.getOrDefault(resource.initialFirstResponderId)
      if not responder.isNil:
        window.setInitialFirstResponder(responder)
    if not resource.keyBindingTableId.isEmpty and
        state.instance.keyBindingsValue.hasKey(resource.keyBindingTableId):
      window.setKeyBindings(state.instance.keyBindingsValue[resource.keyBindingTableId])
    if not resource.themeId.isEmpty and
        state.instance.themesValue.hasKey(resource.themeId):
      window.setAppearance(initAppearance(state.instance.themesValue[resource.themeId]))

    if resource.properties.len > 0:
      state.diagnostics.add(
        rdsWarning,
        "resource.window.propertiesDeferred",
        "window extension properties are not handled by the built-in registry",
        path = "windows[" & $index & "].properties",
        resourceId = resource.id,
      )

proc instantiateResources*(
    bundle: ResourceBundle,
    registry: ResourceRegistry,
    context = initResourceInstantiationContext(),
    validationOptions = initResourceValidationOptions(),
): ResourceInstantiationResult =
  ## Validates, allocates, configures, and connects a resource bundle.
  var effectiveValidationOptions = validationOptions
  if effectiveValidationOptions.assetBasePath.len == 0:
    effectiveValidationOptions.assetBasePath = context.assetBasePath
  result.diagnostics = bundle.validateResources(registry, effectiveValidationOptions)
  if result.diagnostics.hasErrors:
    return

  var state = ConstructionState(
    bundle: bundle,
    registry: registry,
    context: context,
    instance: initResourceInstance(),
    diagnostics: result.diagnostics,
  )
  state.constructImages()
  state.constructThemes()
  state.constructKeyBindings()
  state.allocateViews(bundle.views, "views")
  state.allocateControllers(bundle.controllers, "controllers")
  state.allocateMenus()
  state.allocateWindows()
  state.configureViews(bundle.views, "views")
  state.configureControllers(bundle.controllers, "controllers")
  state.configureMenus()
  state.configureWindows()

  result.diagnostics = move state.diagnostics
  if not result.diagnostics.hasErrors:
    result.instance = move state.instance

proc instantiateResources*(
    bundle: ResourceBundle,
    context = initResourceInstantiationContext(),
    validationOptions = initResourceValidationOptions(),
): ResourceInstantiationResult =
  bundle.instantiateResources(initNimKitResourceRegistry(), context, validationOptions)
