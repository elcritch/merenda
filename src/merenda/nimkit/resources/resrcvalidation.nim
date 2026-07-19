## Structural and semantic validation for NimKit resource bundles.

import std/[math, options, os, sets, tables]

import ../foundation/types
import ../themes
import ./[resrccore, resrcregistry]

type
  ResourceValidationOptions* = object
    assetBasePath*: string
    limits*: ResourceLoadLimits
    checkFileAssets*: bool

  ValidationState = object
    diagnostics: ResourceDiagnostics
    identifiers: Table[ResourceId, ResourceReferenceKind]
    identifierPaths: Table[ResourceId, string]
    localizedKeys: HashSet[string]
    nodeCount: int
    embeddedAssetBytes: int

func initResourceValidationOptions*(assetBasePath = ""): ResourceValidationOptions =
  ResourceValidationOptions(
    assetBasePath: assetBasePath,
    limits: initResourceLoadLimits(),
    checkFileAssets: true,
  )

proc addIdentifier(
    state: var ValidationState,
    id: ResourceId,
    kind: ResourceReferenceKind,
    path: string,
    required = true,
) =
  if id.isEmpty:
    if required:
      state.diagnostics.add(
        rdsError,
        "resource.identifier.missing",
        "resource identifier is required",
        path = path,
      )
  elif state.identifiers.hasKey(id):
    state.diagnostics.add(
      rdsError,
      "resource.identifier.duplicate",
      "resource identifier '" & $id & "' is already used at " & state.identifierPaths[
        id
      ],
      path = path,
      resourceId = id,
    )
  else:
    state.identifiers[id] = kind
    state.identifierPaths[id] = path

proc collectViewIdentifiers(
    state: var ValidationState,
    nodes: openArray[ViewNodeResource],
    path: string,
    depth: int,
    limits: ResourceLoadLimits,
) =
  if depth > limits.maximumTreeDepth:
    state.diagnostics.add(
      rdsError,
      "resource.tree.tooDeep",
      "view tree exceeds the configured depth limit",
      path = path,
    )
    return
  for index, node in nodes:
    let nodePath = path & "[" & $index & "]"
    inc state.nodeCount
    state.addIdentifier(node.id, rrView, nodePath & ".id")
    state.collectViewIdentifiers(
      node.children, nodePath & ".children", depth + 1, limits
    )

proc collectControllerIdentifiers(
    state: var ValidationState,
    nodes: openArray[ControllerNodeResource],
    path: string,
    depth: int,
    limits: ResourceLoadLimits,
) =
  if depth > limits.maximumTreeDepth:
    state.diagnostics.add(
      rdsError,
      "resource.tree.tooDeep",
      "controller tree exceeds the configured depth limit",
      path = path,
    )
    return
  for index, node in nodes:
    let nodePath = path & "[" & $index & "]"
    inc state.nodeCount
    state.addIdentifier(node.id, rrController, nodePath & ".id")
    state.collectControllerIdentifiers(
      node.children, nodePath & ".children", depth + 1, limits
    )

proc collectMenuItemIdentifiers(
    state: var ValidationState,
    items: openArray[MenuItemResource],
    path: string,
    depth: int,
    limits: ResourceLoadLimits,
) =
  if depth > limits.maximumTreeDepth:
    state.diagnostics.add(
      rdsError,
      "resource.tree.tooDeep",
      "menu tree exceeds the configured depth limit",
      path = path,
    )
    return
  for index, item in items:
    let itemPath = path & "[" & $index & "]"
    inc state.nodeCount
    state.addIdentifier(
      item.id, rrMenu, itemPath & ".id", required = not item.separator
    )
    state.collectMenuItemIdentifiers(
      item.children, itemPath & ".children", depth + 1, limits
    )

proc collectIdentifiers(
    state: var ValidationState, bundle: ResourceBundle, limits: ResourceLoadLimits
) =
  state.collectViewIdentifiers(bundle.views, "views", 1, limits)
  for index, guide in bundle.layoutGuides:
    state.addIdentifier(guide.id, rrLayoutGuide, "layoutGuides[" & $index & "].id")
  for index, constraint in bundle.layoutConstraints:
    state.addIdentifier(
      constraint.id, rrLayoutConstraint, "layoutConstraints[" & $index & "].id"
    )
  state.collectControllerIdentifiers(bundle.controllers, "controllers", 1, limits)
  for index, window in bundle.windows:
    state.addIdentifier(window.id, rrWindow, "windows[" & $index & "].id")
  for index, menu in bundle.menus:
    let path = "menus[" & $index & "]"
    state.addIdentifier(menu.id, rrMenu, path & ".id")
    state.collectMenuItemIdentifiers(menu.items, path & ".items", 1, limits)
  for index, command in bundle.commands:
    state.addIdentifier(command.id, rrCommand, "commands[" & $index & "].id")
  for index, image in bundle.images:
    state.addIdentifier(image.id, rrImage, "images[" & $index & "].id")
  for index, table in bundle.keyBindings:
    state.addIdentifier(table.id, rrKeyBindings, "keyBindings[" & $index & "].id")
  for index, theme in bundle.themes:
    state.addIdentifier(theme.id, rrTheme, "themes[" & $index & "].id")
  for catalogIndex, catalog in bundle.localizations:
    state.addIdentifier(
      catalog.id,
      rrLocalization,
      "localizations[" & $catalogIndex & "].id",
      required = bundle.version.minor >= 1,
    )
    for stringIndex, entry in catalog.strings:
      let path = "localizations[" & $catalogIndex & "].strings[" & $stringIndex & "]"
      if entry.key.len == 0:
        state.diagnostics.add(
          rdsError,
          "resource.localization.keyMissing",
          "localized string key is required",
          path = path & ".key",
        )
      else:
        state.localizedKeys.incl entry.key

proc checkReference(
    state: var ValidationState, reference: ResourceReference, path: string
) =
  if reference.id.isEmpty:
    state.diagnostics.add(
      rdsError,
      "resource.reference.missing",
      "resource reference is missing an identifier",
      path = path,
    )
  elif reference.kind == rrLocalizedString:
    if $reference.id notin state.localizedKeys:
      state.diagnostics.add(
        rdsError,
        "resource.localization.unavailable",
        "localized string '" & $reference.id & "' is unavailable",
        path = path,
        relatedId = reference.id,
      )
  elif reference.kind != rrTarget:
    if not state.identifiers.hasKey(reference.id):
      state.diagnostics.add(
        rdsError,
        "resource.reference.unavailable",
        "referenced resource '" & $reference.id & "' is unavailable",
        path = path,
        relatedId = reference.id,
      )
    elif state.identifiers[reference.id] != reference.kind:
      state.diagnostics.add(
        rdsError,
        "resource.reference.kindMismatch",
        "resource '" & $reference.id & "' does not have the expected kind",
        path = path,
        relatedId = reference.id,
      )

proc validateProperties(
    state: var ValidationState,
    registry: ResourceRegistry,
    node: ViewNodeResource,
    path: string,
) =
  var names = initHashSet[string]()
  for index, property in node.properties:
    let propertyPath = path & ".properties[" & $index & "]"
    if property.name.len == 0:
      state.diagnostics.add(
        rdsError,
        "resource.property.nameMissing",
        "property name is required",
        path = propertyPath & ".name",
        resourceId = node.id,
      )
    elif property.name in names:
      state.diagnostics.add(
        rdsError,
        "resource.property.duplicate",
        "property '" & property.name & "' is specified more than once",
        path = propertyPath,
        resourceId = node.id,
      )
    else:
      names.incl property.name
      if registry.hasViewKind(node.kind) and
          not registry.acceptsViewProperty(
            node.kind, property.name, property.value.kind
          ):
        state.diagnostics.add(
          rdsError,
          "resource.property.incompatible",
          "property '" & property.name & "' is unavailable for view kind '" & node.kind &
            "' or has an incompatible value",
          path = propertyPath,
          resourceId = node.id,
        )
    if property.value.kind == rvReference:
      state.checkReference(property.value.referenceValue, propertyPath & ".value")

proc validateViewNodes(
    state: var ValidationState,
    registry: ResourceRegistry,
    nodes: openArray[ViewNodeResource],
    path: string,
) =
  for index, node in nodes:
    let nodePath = path & "[" & $index & "]"
    if node.kind.len == 0 or not registry.hasViewKind(node.kind):
      state.diagnostics.add(
        rdsError,
        "resource.view.kindUnavailable",
        "view kind '" & node.kind & "' is not registered",
        path = nodePath & ".kind",
        resourceId = node.id,
      )
    state.validateProperties(registry, node, nodePath)
    state.validateViewNodes(registry, node.children, nodePath & ".children")

proc validateControllerNodes(
    state: var ValidationState,
    registry: ResourceRegistry,
    nodes: openArray[ControllerNodeResource],
    path: string,
) =
  for index, node in nodes:
    let nodePath = path & "[" & $index & "]"
    if node.kind.len == 0 or not registry.hasControllerKind(node.kind):
      state.diagnostics.add(
        rdsError,
        "resource.controller.kindUnavailable",
        "controller kind '" & node.kind & "' is not registered",
        path = nodePath & ".kind",
        resourceId = node.id,
      )
    if node.properties.len > 0:
      state.diagnostics.add(
        rdsWarning,
        "resource.controller.propertiesDeferred",
        "controller extension properties are not handled by the built-in registry",
        path = nodePath & ".properties",
        resourceId = node.id,
      )
    if node.viewId.isEmpty or not state.identifiers.hasKey(node.viewId):
      state.diagnostics.add(
        rdsError,
        "resource.controller.viewUnavailable",
        "controller view '" & $node.viewId & "' is unavailable",
        path = nodePath & ".viewId",
        resourceId = node.id,
        relatedId = node.viewId,
      )
    elif state.identifiers[node.viewId] != rrView:
      state.diagnostics.add(
        rdsError,
        "resource.reference.kindMismatch",
        "controller view reference does not identify a view",
        path = nodePath & ".viewId",
        resourceId = node.id,
        relatedId = node.viewId,
      )
    state.validateControllerNodes(registry, node.children, nodePath & ".children")

func layoutAxis(anchor: ResourceLayoutAnchor): int =
  case anchor
  of rlaLeft, rlaRight, rlaLeading, rlaTrailing, rlaCenterX: 1
  of rlaTop, rlaBottom, rlaCenterY, rlaLastBaseline, rlaFirstBaseline: 2
  of rlaWidth, rlaHeight: 3
  of rlaNotAnAnchor: 0

func finiteResourceFloat(value: float32): bool =
  classify(value.float) notin {fcNan, fcInf, fcNegInf}

proc viewNodeContains(node: ViewNodeResource, id: ResourceId): bool =
  if node.id == id:
    return true
  for child in node.children:
    if child.viewNodeContains(id):
      return true

proc viewContains(
    nodes: openArray[ViewNodeResource], ownerId, itemId: ResourceId
): bool =
  for node in nodes:
    if node.id == ownerId:
      return node.viewNodeContains(itemId)
    if node.children.viewContains(ownerId, itemId):
      return true

proc endpointViewId(
    bundle: ResourceBundle, item: ResourceLayoutItemReference
): ResourceId =
  case item.kind
  of rliView:
    item.id
  of rliGuide:
    let guide = bundle.findLayoutGuide(item.id)
    if guide.isSome:
      guide.get().owningViewId
    else:
      ResourceId("")

proc validateLayoutItem(
    state: var ValidationState, item: ResourceLayoutItemReference, path: string
) =
  state.checkReference(
    resourceReference(if item.kind == rliView: rrView else: rrLayoutGuide, item.id),
    path,
  )

proc validateLayout(state: var ValidationState, bundle: ResourceBundle) =
  for index, guide in bundle.layoutGuides:
    let path = "layoutGuides[" & $index & "]"
    state.checkReference(
      resourceReference(rrView, guide.owningViewId), path & ".owningViewId"
    )
    for (name, value) in [
      ("top", guide.insets.top),
      ("left", guide.insets.left),
      ("bottom", guide.insets.bottom),
      ("right", guide.insets.right),
    ]:
      if not finiteResourceFloat(value):
        state.diagnostics.add(
          rdsError,
          "resource.layout.guideInsetInvalid",
          "layout guide inset '" & name & "' must be finite",
          path = path & ".insets." & name,
          resourceId = guide.id,
        )

  for index, constraint in bundle.layoutConstraints:
    let
      path = "layoutConstraints[" & $index & "]"
      hasSecond = not constraint.secondItem.id.isEmpty
      firstAxis = constraint.firstAnchor.layoutAxis()
      secondAxis = constraint.secondAnchor.layoutAxis()
    state.checkReference(
      resourceReference(rrView, constraint.owningViewId), path & ".owningViewId"
    )
    state.validateLayoutItem(constraint.firstItem, path & ".firstItem")
    if constraint.firstAnchor == rlaNotAnAnchor:
      state.diagnostics.add(
        rdsError,
        "resource.layout.anchorMissing",
        "layout constraint first anchor is required",
        path = path & ".firstAnchor",
        resourceId = constraint.id,
      )
    if constraint.firstItem.kind == rliGuide and
        constraint.firstAnchor in {rlaFirstBaseline, rlaLastBaseline}:
      state.diagnostics.add(
        rdsError,
        "resource.layout.guideAnchorInvalid",
        "layout guides do not provide baseline anchors",
        path = path & ".firstAnchor",
        resourceId = constraint.id,
      )

    if hasSecond:
      state.validateLayoutItem(constraint.secondItem, path & ".secondItem")
      if constraint.secondAnchor == rlaNotAnAnchor:
        state.diagnostics.add(
          rdsError,
          "resource.layout.anchorMissing",
          "layout constraint second anchor is required",
          path = path & ".secondAnchor",
          resourceId = constraint.id,
        )
      elif firstAxis != secondAxis:
        state.diagnostics.add(
          rdsError,
          "resource.layout.anchorMismatch",
          "layout constraint anchors must use compatible axes",
          path = path & ".secondAnchor",
          resourceId = constraint.id,
        )
      if constraint.secondItem.kind == rliGuide and
          constraint.secondAnchor in {rlaFirstBaseline, rlaLastBaseline}:
        state.diagnostics.add(
          rdsError,
          "resource.layout.guideAnchorInvalid",
          "layout guides do not provide baseline anchors",
          path = path & ".secondAnchor",
          resourceId = constraint.id,
        )
    elif constraint.secondAnchor != rlaNotAnAnchor:
      state.diagnostics.add(
        rdsError,
        "resource.layout.secondItemMissing",
        "a second anchor requires a second layout item",
        path = path & ".secondItem",
        resourceId = constraint.id,
      )
    elif firstAxis != 3:
      state.diagnostics.add(
        rdsError,
        "resource.layout.constantAnchorInvalid",
        "constant-only constraints require a width or height anchor",
        path = path & ".firstAnchor",
        resourceId = constraint.id,
      )

    if not finiteResourceFloat(constraint.multiplier) or constraint.multiplier <= 0.0'f32:
      state.diagnostics.add(
        rdsError,
        "resource.layout.multiplierInvalid",
        "layout constraint multiplier must be finite and greater than zero",
        path = path & ".multiplier",
        resourceId = constraint.id,
      )
    if not finiteResourceFloat(constraint.constant):
      state.diagnostics.add(
        rdsError,
        "resource.layout.constantInvalid",
        "layout constraint constant must be finite",
        path = path & ".constant",
        resourceId = constraint.id,
      )
    if not finiteResourceFloat(constraint.priority) or constraint.priority <= 0.0'f32 or
        constraint.priority > 1000.0'f32:
      state.diagnostics.add(
        rdsError,
        "resource.layout.priorityInvalid",
        "layout constraint priority must be greater than 0 and at most 1000",
        path = path & ".priority",
        resourceId = constraint.id,
      )

    for endpoint in [constraint.firstItem, constraint.secondItem]:
      if endpoint.id.isEmpty:
        continue
      let endpointView = bundle.endpointViewId(endpoint)
      if not endpointView.isEmpty and
          not bundle.views.viewContains(constraint.owningViewId, endpointView):
        state.diagnostics.add(
          rdsError,
          "resource.layout.ownerMismatch",
          "layout constraint owner must contain every endpoint",
          path = path & ".owningViewId",
          resourceId = constraint.id,
          relatedId = endpoint.id,
        )

proc resolveAssetPath(basePath, path: string): string =
  if path.isAbsolute or basePath.len == 0:
    path
  else:
    basePath / path

proc validateImages(
    state: var ValidationState,
    bundle: ResourceBundle,
    options: ResourceValidationOptions,
) =
  for index, image in bundle.images:
    let path = "images[" & $index & "]"
    case image.sourceKind
    of risNamed:
      if image.name.len == 0:
        state.diagnostics.add(
          rdsError,
          "resource.image.nameMissing",
          "named image source requires a name",
          path = path & ".name",
          resourceId = image.id,
        )
    of risFile:
      if image.path.len == 0:
        state.diagnostics.add(
          rdsError,
          "resource.image.pathMissing",
          "file image source requires a path",
          path = path & ".path",
          resourceId = image.id,
        )
      elif options.checkFileAssets and
          not fileExists(options.assetBasePath.resolveAssetPath(image.path)):
        state.diagnostics.add(
          rdsError,
          "resource.image.unavailable",
          "image file '" & image.path & "' is unavailable",
          path = path & ".path",
          resourceId = image.id,
        )
    of risEmbedded:
      state.embeddedAssetBytes += image.data.len
      if image.data.len == 0:
        state.diagnostics.add(
          rdsError,
          "resource.image.dataMissing",
          "embedded image source contains no data",
          path = path & ".data",
          resourceId = image.id,
        )
      elif image.data.len > options.limits.maximumEmbeddedAssetBytes:
        state.diagnostics.add(
          rdsError,
          "resource.image.tooLarge",
          "embedded image exceeds the configured byte limit",
          path = path & ".data",
          resourceId = image.id,
        )

proc validateLocalizations(state: var ValidationState, bundle: ResourceBundle) =
  var locales = initHashSet[string]()
  for catalogIndex, catalog in bundle.localizations:
    let catalogPath = "localizations[" & $catalogIndex & "]"
    if catalog.locale.len == 0:
      state.diagnostics.add(
        rdsError,
        "resource.localization.localeMissing",
        "localization catalog locale is required",
        path = catalogPath & ".locale",
      )
    elif catalog.locale in locales:
      state.diagnostics.add(
        rdsError,
        "resource.localization.localeDuplicate",
        "localization locale '" & catalog.locale & "' is duplicated",
        path = catalogPath & ".locale",
      )
    else:
      locales.incl catalog.locale
    var keys = initHashSet[string]()
    for stringIndex, entry in catalog.strings:
      if entry.key in keys:
        state.diagnostics.add(
          rdsError,
          "resource.localization.keyDuplicate",
          "localized string key '" & entry.key & "' is duplicated in the catalog",
          path = catalogPath & ".strings[" & $stringIndex & "].key",
        )
      else:
        keys.incl entry.key

  for catalogIndex, catalog in bundle.localizations:
    if catalog.fallbackLocale.len > 0 and catalog.fallbackLocale notin locales:
      state.diagnostics.add(
        rdsError,
        "resource.localization.fallbackUnavailable",
        "fallback locale '" & catalog.fallbackLocale & "' is unavailable",
        path = "localizations[" & $catalogIndex & "].fallbackLocale",
      )

  var fallbacks = initTable[string, string]()
  for catalog in bundle.localizations:
    if catalog.locale.len > 0 and catalog.fallbackLocale.len > 0:
      fallbacks[catalog.locale] = catalog.fallbackLocale
  for catalogIndex, catalog in bundle.localizations:
    var
      current = catalog.locale
      visited = initHashSet[string]()
    while current.len > 0 and fallbacks.hasKey(current):
      if current in visited:
        state.diagnostics.add(
          rdsError,
          "resource.localization.fallbackCycle",
          "localization fallback chain contains a cycle",
          path = "localizations[" & $catalogIndex & "].fallbackLocale",
        )
        break
      visited.incl current
      current = fallbacks[current]

proc validateMenus(
    state: var ValidationState, items: openArray[MenuItemResource], path: string
) =
  for index, item in items:
    let itemPath = path & "[" & $index & "]"
    if not item.commandId.isEmpty:
      state.checkReference(
        resourceReference(rrCommand, item.commandId), itemPath & ".commandId"
      )
    if not item.imageId.isEmpty:
      state.checkReference(
        resourceReference(rrImage, item.imageId), itemPath & ".imageId"
      )
    state.validateMenus(item.children, itemPath & ".children")

proc enumNameValid[T: enum](name: string): bool =
  for value in T:
    if $value == name:
      return true

proc validateThemes(
    state: var ValidationState, registry: ResourceRegistry, bundle: ResourceBundle
) =
  var tokenNames = initHashSet[string]()
  var themeParents = initTable[ResourceId, ResourceId]()
  for theme in bundle.themes:
    if not theme.parentId.isEmpty:
      themeParents[theme.id] = theme.parentId
    for token in theme.tokens:
      if token.name.len > 0:
        tokenNames.incl token.name

  for themeIndex, theme in bundle.themes:
    let themePath = "themes[" & $themeIndex & "]"
    if not theme.parentId.isEmpty:
      state.checkReference(
        resourceReference(rrTheme, theme.parentId), themePath & ".parentId"
      )
    var localTokens = initHashSet[string]()
    for tokenIndex, token in theme.tokens:
      let tokenPath = themePath & ".tokens[" & $tokenIndex & "]"
      if token.name.len == 0:
        state.diagnostics.add(
          rdsError,
          "resource.theme.tokenNameMissing",
          "theme token name is required",
          path = tokenPath & ".name",
          resourceId = theme.id,
        )
      elif token.name in localTokens:
        state.diagnostics.add(
          rdsError,
          "resource.theme.tokenDuplicate",
          "theme token '" & token.name & "' is duplicated",
          path = tokenPath,
          resourceId = theme.id,
        )
      else:
        localTokens.incl token.name
      if token.value.kind == rsvToken and token.value.text notin tokenNames:
        state.diagnostics.add(
          rdsError,
          "resource.theme.tokenUnavailable",
          "theme token '" & token.value.text & "' is unavailable",
          path = tokenPath & ".value",
          resourceId = theme.id,
        )
    for ruleIndex, rule in theme.rules:
      let rulePath = themePath & ".rules[" & $ruleIndex & "]"
      if not enumNameValid[StyleRole](rule.selector.role):
        state.diagnostics.add(
          rdsError,
          "resource.theme.roleInvalid",
          "theme style role '" & rule.selector.role & "' is invalid",
          path = rulePath & ".selector.role",
          resourceId = theme.id,
        )
      for stateIndex, stateName in rule.selector.states:
        if not enumNameValid[WidgetState](stateName):
          state.diagnostics.add(
            rdsError,
            "resource.theme.stateInvalid",
            "theme widget state '" & stateName & "' is invalid",
            path = rulePath & ".selector.states[" & $stateIndex & "]",
            resourceId = theme.id,
          )
      for styleIndex, style in rule.styles:
        let stylePath = rulePath & ".styles[" & $styleIndex & "]"
        if style.name.len == 0:
          state.diagnostics.add(
            rdsError,
            "resource.theme.styleNameMissing",
            "theme style name is required",
            path = stylePath & ".name",
            resourceId = theme.id,
          )
        if style.value.kind == rsvToken and style.value.text notin tokenNames:
          state.diagnostics.add(
            rdsError,
            "resource.theme.tokenUnavailable",
            "theme token '" & style.value.text & "' is unavailable",
            path = stylePath & ".value",
            resourceId = theme.id,
          )
        if style.name == StyleChrome.keyName and style.value.kind == rsvKeyword and
            not registry.hasChromeName(style.value.text):
          state.diagnostics.add(
            rdsError,
            "resource.theme.chromeUnavailable",
            "theme chrome '" & style.value.text & "' is unavailable",
            path = stylePath & ".value",
            resourceId = theme.id,
          )

  for themeIndex, theme in bundle.themes:
    var
      current = theme.id
      visited = initHashSet[ResourceId]()
    while themeParents.hasKey(current):
      if current in visited:
        state.diagnostics.add(
          rdsError,
          "resource.theme.parentCycle",
          "theme parent chain contains a cycle",
          path = "themes[" & $themeIndex & "].parentId",
          resourceId = theme.id,
        )
        break
      visited.incl current
      current = themeParents[current]

proc validateResources*(
    bundle: ResourceBundle,
    registry: ResourceRegistry,
    options = initResourceValidationOptions(),
): ResourceDiagnostics =
  ## Validates a decoded bundle without constructing runtime UI identities.
  var state = ValidationState(
    identifiers: initTable[ResourceId, ResourceReferenceKind](),
    identifierPaths: initTable[ResourceId, string](),
    localizedKeys: initHashSet[string](),
  )
  if bundle.format != ResourceFormatName:
    state.diagnostics.add(
      rdsError,
      "resource.format.unsupported",
      "unsupported resource format '" & bundle.format & "'",
      path = "format",
    )
  if bundle.version.major != CurrentResourceVersion.major:
    state.diagnostics.add(
      rdsError,
      "resource.version.incompatible",
      "resource major version is incompatible",
      path = "version.major",
    )
  elif bundle.version.minor > CurrentResourceVersion.minor:
    state.diagnostics.add(
      rdsWarning,
      "resource.version.newerMinor",
      "resource minor version is newer than the supported version",
      path = "version.minor",
    )

  state.collectIdentifiers(bundle, options.limits)
  if state.nodeCount > options.limits.maximumNodes:
    state.diagnostics.add(
      rdsError, "resource.nodes.tooMany",
      "resource bundle exceeds the configured node limit",
    )
  state.validateViewNodes(registry, bundle.views, "views")
  state.validateLayout(bundle)
  state.validateControllerNodes(registry, bundle.controllers, "controllers")

  for index, window in bundle.windows:
    let path = "windows[" & $index & "]"
    if not window.contentViewId.isEmpty and not window.controllerId.isEmpty:
      state.diagnostics.add(
        rdsError,
        "resource.window.contentConflict",
        "window cannot specify both contentViewId and controllerId",
        path = path,
        resourceId = window.id,
      )
    if not window.contentViewId.isEmpty:
      state.checkReference(
        resourceReference(rrView, window.contentViewId), path & ".contentViewId"
      )
    if not window.controllerId.isEmpty:
      state.checkReference(
        resourceReference(rrController, window.controllerId), path & ".controllerId"
      )
    if not window.initialFirstResponderId.isEmpty:
      state.checkReference(
        resourceReference(rrView, window.initialFirstResponderId),
        path & ".initialFirstResponderId",
      )
    if not window.keyBindingTableId.isEmpty:
      state.checkReference(
        resourceReference(rrKeyBindings, window.keyBindingTableId),
        path & ".keyBindingTableId",
      )
    if not window.themeId.isEmpty:
      state.checkReference(
        resourceReference(rrTheme, window.themeId), path & ".themeId"
      )

  for index, command in bundle.commands:
    let path = "commands[" & $index & "]"
    if command.selector.len == 0:
      state.diagnostics.add(
        rdsError,
        "resource.command.selectorMissing",
        "command selector is required",
        path = path & ".selector",
        resourceId = command.id,
      )
    elif not registry.hasActionSelector(command.selector):
      state.diagnostics.add(
        rdsError,
        "resource.command.selectorMismatch",
        "command selector '" & command.selector & "' is not registered",
        path = path & ".selector",
        resourceId = command.id,
      )
    if command.targetKind == rctExplicit and command.targetId.isEmpty:
      state.diagnostics.add(
        rdsError,
        "resource.command.targetMissing",
        "explicit command target identifier is required",
        path = path & ".targetId",
        resourceId = command.id,
      )

  for index, table in bundle.keyBindings:
    for bindingIndex, binding in table.bindings:
      let path = "keyBindings[" & $index & "].bindings[" & $bindingIndex & "]"
      if binding.stroke.text.len == 0 and binding.stroke.keyCode == 0:
        state.diagnostics.add(
          rdsError,
          "resource.keyBinding.strokeMissing",
          "key binding requires text or a key code",
          path = path & ".stroke",
          resourceId = table.id,
        )
      state.checkReference(
        resourceReference(rrCommand, binding.commandId), path & ".commandId"
      )
      let command = bundle.findCommand(binding.commandId)
      if command.isSome and command.get.targetKind != rctResponderChain:
        state.diagnostics.add(
          rdsError,
          "resource.keyBinding.targetMismatch",
          "key binding commands must use responder-chain dispatch",
          path = path & ".commandId",
          resourceId = table.id,
          relatedId = binding.commandId,
        )

  for menuIndex, menu in bundle.menus:
    state.validateMenus(menu.items, "menus[" & $menuIndex & "].items")
  state.validateImages(bundle, options)
  state.validateLocalizations(bundle)
  if state.embeddedAssetBytes > options.limits.maximumEmbeddedAssetBytes:
    state.diagnostics.add(
      rdsError,
      "resource.images.tooLarge",
      "combined embedded image data exceeds the configured byte limit",
      path = "images",
    )
  state.validateThemes(registry, bundle)
  result = move state.diagnostics
