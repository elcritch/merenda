## Stable backend-neutral records for declarative NimKit resources.
##
## These records intentionally contain no identity-bearing NimKit objects. A decoded
## bundle can be inspected and validated without constructing views, controllers,
## windows, menus, images, selectors, or backend resources.

import std/[hashes, options]

from ../foundation/types import Color, Rect, Size
from ../themes/themecore import EdgeInsets

type
  ResourceLookupError* = object of CatchableError

  ResourceId* = distinct string

  ResourceVersion* = object
    major*: int
    minor*: int

  ResourceReferenceKind* = enum
    rrNone
    rrView
    rrLayoutGuide
    rrLayoutConstraint
    rrController
    rrWindow
    rrMenu
    rrCommand
    rrImage
    rrLocalizedString
    rrLocalization
    rrKeyBindings
    rrTheme
    rrTarget

  ResourceReference* = object
    kind*: ResourceReferenceKind
    id*: ResourceId

  ResourceValueKind* = enum
    rvNone
    rvString
    rvInt
    rvFloat
    rvBool
    rvStrings
    rvRect
    rvSize
    rvInsets
    rvColor
    rvReference

  ResourceValue* = object
    ## A non-variant wire value. Keeping every payload field present makes canonical
    ## map decoding independent of discriminator key order.
    kind*: ResourceValueKind
    stringValue*: string
    intValue*: int
    floatValue*: float32
    boolValue*: bool
    stringValues*: seq[string]
    rectValue*: Rect
    sizeValue*: Size
    insetsValue*: EdgeInsets
    colorValue*: Color
    referenceValue*: ResourceReference

  ResourceProperty* = object
    name*: string
    value*: ResourceValue

  ResourceText* = object
    key*: string
    fallback*: string

  ResourceFlag* = enum
    rfDefault
    rfOff
    rfOn

  ViewNodeResource* = object
    id*: ResourceId
    kind*: string
    properties*: seq[ResourceProperty]
    children*: seq[ViewNodeResource]

  ResourceLayoutItemKind* = enum
    rliView
    rliGuide

  ResourceLayoutAnchor* = enum
    rlaNotAnAnchor
    rlaLeft
    rlaRight
    rlaTop
    rlaBottom
    rlaLeading
    rlaTrailing
    rlaWidth
    rlaHeight
    rlaCenterX
    rlaCenterY
    rlaLastBaseline
    rlaFirstBaseline

  ResourceLayoutRelation* = enum
    rlrLessThanOrEqual
    rlrEqual
    rlrGreaterThanOrEqual

  ResourceLayoutItemReference* = object
    kind*: ResourceLayoutItemKind
    id*: ResourceId

  ResourceLayoutGuide* = object
    id*: ResourceId
    owningViewId*: ResourceId
    insets*: EdgeInsets

  ResourceLayoutConstraint* = object
    id*: ResourceId
    owningViewId*: ResourceId
    firstItem*: ResourceLayoutItemReference
    firstAnchor*: ResourceLayoutAnchor
    relation*: ResourceLayoutRelation
    secondItem*: ResourceLayoutItemReference
    secondAnchor*: ResourceLayoutAnchor
    multiplier*: float32
    constant*: float32
    priority*: float32
    active*: bool

  ControllerNodeResource* = object
    id*: ResourceId
    kind*: string
    viewId*: ResourceId
    properties*: seq[ResourceProperty]
    children*: seq[ControllerNodeResource]

  ResourceWindowKind* = enum
    rwWindow
    rwPanel

  WindowResource* = object
    id*: ResourceId
    kind*: ResourceWindowKind
    title*: ResourceText
    frame*: Rect
    contentViewId*: ResourceId
    controllerId*: ResourceId
    initialFirstResponderId*: ResourceId
    keyBindingTableId*: ResourceId
    themeId*: ResourceId
    properties*: seq[ResourceProperty]

  ResourceCommandTargetKind* = enum
    rctResponderChain
    rctApplication
    rctExplicit

  CommandResource* = object
    id*: ResourceId
    selector*: string
    targetKind*: ResourceCommandTargetKind
    targetId*: ResourceId

  ResourceShortcutModifier* = enum
    rsmShift
    rsmControl
    rsmOption
    rsmCommand
    rsmShortcut

  KeyStrokeResource* = object
    text*: string
    keyCode*: int
    modifiers*: set[ResourceShortcutModifier]

  KeyBindingResource* = object
    stroke*: KeyStrokeResource
    commandId*: ResourceId

  KeyBindingTableResource* = object
    id*: ResourceId
    bindings*: seq[KeyBindingResource]

  MenuItemResource* = object
    id*: ResourceId
    title*: ResourceText
    subtitle*: ResourceText
    commandId*: ResourceId
    imageId*: ResourceId
    keyEquivalent*: KeyStrokeResource
    hasKeyEquivalent*: bool
    enabled*: ResourceFlag
    hidden*: bool
    separator*: bool
    tag*: int
    validates*: ResourceFlag
    children*: seq[MenuItemResource]

  MenuResource* = object
    id*: ResourceId
    title*: ResourceText
    items*: seq[MenuItemResource]

  ResourceImageSourceKind* = enum
    risNamed
    risFile
    risEmbedded

  ResourceImageCachePolicy* = enum
    ricDefault
    ricAlways
    ricNever
    ricBySize

  ImageAssetResource* = object
    id*: ResourceId
    sourceKind*: ResourceImageSourceKind
    name*: string
    path*: string
    mediaType*: string
    data*: seq[byte]
    cachePolicy*: ResourceImageCachePolicy

  LocalizedStringResource* = object
    key*: string
    value*: string

  LocalizedCatalogResource* = object
    id*: ResourceId
    locale*: string
    fallbackLocale*: string
    strings*: seq[LocalizedStringResource]

  ResourceShadowKind* = enum
    rskDrop
    rskInset

  ResourceShadow* = object
    kind*: ResourceShadowKind
    color*: Color
    x*: float32
    y*: float32
    blur*: float32
    spread*: float32

  ResourceStyleValueKind* = enum
    rsvMissing
    rsvColor
    rsvFill
    rsvLength
    rsvSize
    rsvInsets
    rsvShadows
    rsvToken
    rsvKeyword

  ResourceStyleValue* = object
    kind*: ResourceStyleValueKind
    color*: Color
    length*: float32
    size*: Size
    insets*: EdgeInsets
    shadows*: seq[ResourceShadow]
    text*: string

  ThemeTokenResource* = object
    name*: string
    value*: ResourceStyleValue

  ThemeStyleResource* = object
    name*: string
    value*: ResourceStyleValue

  ThemeSelectorResource* = object
    role*: string
    states*: seq[string]
    id*: string
    classes*: seq[string]

  ThemeRuleResource* = object
    selector*: ThemeSelectorResource
    styles*: seq[ThemeStyleResource]

  ThemeFragmentResource* = object
    id*: ResourceId
    parentId*: ResourceId
    tokens*: seq[ThemeTokenResource]
    rules*: seq[ThemeRuleResource]

  ResourceBundle* = object
    format*: string
    version*: ResourceVersion
    namespace*: string
    views*: seq[ViewNodeResource]
    layoutGuides*: seq[ResourceLayoutGuide]
    layoutConstraints*: seq[ResourceLayoutConstraint]
    controllers*: seq[ControllerNodeResource]
    windows*: seq[WindowResource]
    menus*: seq[MenuResource]
    commands*: seq[CommandResource]
    images*: seq[ImageAssetResource]
    localizations*: seq[LocalizedCatalogResource]
    keyBindings*: seq[KeyBindingTableResource]
    themes*: seq[ThemeFragmentResource]

  ResourceDiagnosticSeverity* = enum
    rdsInfo
    rdsWarning
    rdsError

  ResourceDiagnostic* = object
    severity*: ResourceDiagnosticSeverity
    code*: string
    message*: string
    path*: string
    resourceId*: ResourceId
    relatedId*: ResourceId

  ResourceDiagnostics* = object
    entries*: seq[ResourceDiagnostic]

  ResourceLoadLimits* = object
    maximumDataBytes*: int
    maximumNodes*: int
    maximumTreeDepth*: int
    maximumEmbeddedAssetBytes*: int

  ResourceLoadResult* = object
    bundle*: ResourceBundle
    diagnostics*: ResourceDiagnostics

const
  ResourceFormatName* = "org.merenda.nimkit.resources"
  CurrentResourceVersion* = ResourceVersion(major: 1, minor: 1)

func `==`*(a, b: ResourceId): bool {.borrow.}
func hash*(id: ResourceId): Hash {.borrow.}
func `$`*(id: ResourceId): string {.borrow.}

func resourceId*(value: string): ResourceId =
  ResourceId(value)

func isEmpty*(id: ResourceId): bool =
  string(id).len == 0

func initResourceVersion*(major, minor: Natural): ResourceVersion =
  ResourceVersion(major: major, minor: minor)

func initResourceBundle*(namespace = ""): ResourceBundle =
  ResourceBundle(
    format: ResourceFormatName, version: CurrentResourceVersion, namespace: namespace
  )

func initResourceLoadLimits*(): ResourceLoadLimits =
  ResourceLoadLimits(
    maximumDataBytes: 64 * 1024 * 1024,
    maximumNodes: 100_000,
    maximumTreeDepth: 256,
    maximumEmbeddedAssetBytes: 32 * 1024 * 1024,
  )

func resourceReference*(
    kind: ResourceReferenceKind, id: ResourceId
): ResourceReference =
  ResourceReference(kind: kind, id: id)

func resourceValue*(value: string): ResourceValue =
  ResourceValue(kind: rvString, stringValue: value)

func resourceValue*(value: int): ResourceValue =
  ResourceValue(kind: rvInt, intValue: value)

func resourceValue*(value: float32): ResourceValue =
  ResourceValue(kind: rvFloat, floatValue: value)

func resourceValue*(value: float): ResourceValue =
  ResourceValue(kind: rvFloat, floatValue: value.float32)

func resourceValue*(value: bool): ResourceValue =
  ResourceValue(kind: rvBool, boolValue: value)

func resourceValue*(value: openArray[string]): ResourceValue =
  ResourceValue(kind: rvStrings, stringValues: @value)

func resourceValue*(value: Rect): ResourceValue =
  ResourceValue(kind: rvRect, rectValue: value)

func resourceValue*(value: Size): ResourceValue =
  ResourceValue(kind: rvSize, sizeValue: value)

func resourceValue*(value: EdgeInsets): ResourceValue =
  ResourceValue(kind: rvInsets, insetsValue: value)

func resourceValue*(value: Color): ResourceValue =
  ResourceValue(kind: rvColor, colorValue: value)

func resourceValue*(value: ResourceReference): ResourceValue =
  ResourceValue(kind: rvReference, referenceValue: value)

func resourceProperty*(name: string, value: ResourceValue): ResourceProperty =
  ResourceProperty(name: name, value: value)

func resourceText*(value: string): ResourceText =
  ResourceText(fallback: value)

func localizedResourceText*(key: string, fallback = ""): ResourceText =
  ResourceText(key: key, fallback: fallback)

func initViewNodeResource*(
    id: ResourceId,
    kind = "view",
    properties: openArray[ResourceProperty] = [],
    children: openArray[ViewNodeResource] = [],
): ViewNodeResource =
  ViewNodeResource(id: id, kind: kind, properties: @properties, children: @children)

func resourceLayoutItem*(id: ResourceId, kind = rliView): ResourceLayoutItemReference =
  ResourceLayoutItemReference(kind: kind, id: id)

func initResourceLayoutGuide*(
    id, owningViewId: ResourceId, insets = EdgeInsets()
): ResourceLayoutGuide =
  ResourceLayoutGuide(id: id, owningViewId: owningViewId, insets: insets)

func initResourceLayoutConstraint*(
    id, owningViewId: ResourceId,
    firstItem: ResourceLayoutItemReference,
    firstAnchor: ResourceLayoutAnchor,
    secondItem = ResourceLayoutItemReference(),
    secondAnchor = rlaNotAnAnchor,
    relation = rlrEqual,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = 1000.0'f32,
    active = true,
): ResourceLayoutConstraint =
  ResourceLayoutConstraint(
    id: id,
    owningViewId: owningViewId,
    firstItem: firstItem,
    firstAnchor: firstAnchor,
    relation: relation,
    secondItem: secondItem,
    secondAnchor: secondAnchor,
    multiplier: multiplier,
    constant: constant,
    priority: priority,
    active: active,
  )

func initControllerNodeResource*(
    id: ResourceId,
    viewId: ResourceId,
    kind = "viewController",
    children: openArray[ControllerNodeResource] = [],
): ControllerNodeResource =
  ControllerNodeResource(id: id, kind: kind, viewId: viewId, children: @children)

proc add*(
    diagnostics: var ResourceDiagnostics,
    severity: ResourceDiagnosticSeverity,
    code, message: string,
    path = "",
    resourceId = ResourceId(""),
    relatedId = ResourceId(""),
) =
  diagnostics.entries.add ResourceDiagnostic(
    severity: severity,
    code: code,
    message: message,
    path: path,
    resourceId: resourceId,
    relatedId: relatedId,
  )

func len*(diagnostics: ResourceDiagnostics): int =
  diagnostics.entries.len

iterator items*(diagnostics: ResourceDiagnostics): ResourceDiagnostic =
  for diagnostic in diagnostics.entries:
    yield diagnostic

func hasErrors*(diagnostics: ResourceDiagnostics): bool =
  for diagnostic in diagnostics.entries:
    if diagnostic.severity == rdsError:
      return true

func loaded*(loadResult: ResourceLoadResult): bool =
  not loadResult.diagnostics.hasErrors

proc findViewNode(
    nodes: openArray[ViewNodeResource], id: ResourceId, found: var ViewNodeResource
): bool =
  for node in nodes:
    if node.id == id:
      found = node
      return true
    if node.children.findViewNode(id, found):
      return true

proc findControllerNode(
    nodes: openArray[ControllerNodeResource],
    id: ResourceId,
    found: var ControllerNodeResource,
): bool =
  for node in nodes:
    if node.id == id:
      found = node
      return true
    if node.children.findControllerNode(id, found):
      return true

proc findView*(bundle: ResourceBundle, id: ResourceId): Option[ViewNodeResource] =
  var found: ViewNodeResource
  if bundle.views.findViewNode(id, found):
    some(found)
  else:
    none(ViewNodeResource)

proc findLayoutGuide*(
    bundle: ResourceBundle, id: ResourceId
): Option[ResourceLayoutGuide] =
  for guide in bundle.layoutGuides:
    if guide.id == id:
      return some(guide)
  none(ResourceLayoutGuide)

proc findLayoutConstraint*(
    bundle: ResourceBundle, id: ResourceId
): Option[ResourceLayoutConstraint] =
  for constraint in bundle.layoutConstraints:
    if constraint.id == id:
      return some(constraint)
  none(ResourceLayoutConstraint)

proc findController*(
    bundle: ResourceBundle, id: ResourceId
): Option[ControllerNodeResource] =
  var found: ControllerNodeResource
  if bundle.controllers.findControllerNode(id, found):
    some(found)
  else:
    none(ControllerNodeResource)

proc findCommand*(bundle: ResourceBundle, id: ResourceId): Option[CommandResource] =
  for command in bundle.commands:
    if command.id == id:
      return some(command)
  none(CommandResource)

proc findImage*(bundle: ResourceBundle, id: ResourceId): Option[ImageAssetResource] =
  for image in bundle.images:
    if image.id == id:
      return some(image)
  none(ImageAssetResource)

proc findMenu*(bundle: ResourceBundle, id: ResourceId): Option[MenuResource] =
  for menu in bundle.menus:
    if menu.id == id:
      return some(menu)
  none(MenuResource)
