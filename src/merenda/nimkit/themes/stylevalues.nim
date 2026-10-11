## Plain theme values, selectors and property normalization shared by Nim and CSS.

import std/[math, strutils, tables]
import figdraw
import ../foundation/types

export
  figdraw.FillGradientAxis, figdraw.FillKind, figdraw.Linear2, figdraw.Linear3,
  figdraw.Fill, figdraw.ColorRGBA, figdraw.toFill, figdraw.sampleColor,
  figdraw.centerColorRgba, figdraw.centerColor, figdraw.`==`

type
  EdgeInsets* = object
    top*: float32
    left*: float32
    bottom*: float32
    right*: float32

  CornerRadii* = object
    topLeft*: float32
    topRight*: float32
    bottomLeft*: float32
    bottomRight*: float32

  BoxShadowKind* = enum
    bskDrop
    bskInset

  BoxShadow* = object
    kind*: BoxShadowKind
    color*: Color
    x*: float32
    y*: float32
    blur*: float32
    spread*: float32

  StyleRole* = enum
    srView
    srBox
    srScrollView
    srScroller
    srButton
    srStepper
    srCheckBox
    srRadioButton
    srSwitch
    srSlider
    srProgressIndicator
    srTab
    srTabPanel
    srDocumentTab
    srDocumentTabBar
    srDocumentTabButton
    srTextField
    srTextView
    srMonoTextView
    srComboBox
    srDatePicker
    srComboBoxItem
    srSplitView
    srTableView
    srCascadingView
    srCascadingColumn
    srCascadingScrollView
    srCascadingScroller
    srTableHeader
    srTableHeaderCell
    srRowItem
    srCascadingRowItem
    srTooltip
    srMenuBar
    srMenuBarItem
    srStackView
    srGridView

  StyleContext* = object
    role*: StyleRole
    states*: set[WidgetState]
    id*: string
    classes*: seq[string]

  StyleSelector* = object
    role*: StyleRole
    states*: set[WidgetState]
    id*: string
    classes*: seq[string]

  StyleLayoutTarget* = enum
    sltConstant
    sltSelf
    sltParent
    sltSibling

  StyleLayoutConstraint* = object
    ## Immutable constraint data; named targets are resolved within a superview.
    attribute*: LayoutAttribute
    relation*: LayoutRelation
    target*: StyleLayoutTarget
    targetId*: string
    targetAttribute*: LayoutAttribute
    multiplier*: float32 = 1
    constant*: float32
    priority*: LayoutPriority = LayoutPriorityRequired

  CssLayoutDiagnostic* = object
    ## One runtime constraint rejection in the latest layout or fitting attempt.
    viewId*, property*, message*: string

  StyleValueKind* = enum
    svMissing
    svColor
    svFill
    svLength
    svSize
    svInsets
    svShadows
    svToken
    svKeyword
    svFontFace
    svConstraints
    svCssExpression

  StyleValue* = object
    case kind*: StyleValueKind
    of svMissing:
      discard
    of svColor:
      color*: Color
    of svFill:
      fill*: Fill
    of svLength:
      length*: float32
    of svSize:
      size*: Size
    of svInsets:
      insets*: EdgeInsets
    of svShadows:
      shadows*: seq[BoxShadow]
    of svFontFace:
      fontFace*: SystemTypeface
    of svToken:
      token*: string
    of svKeyword:
      keyword*: string
    of svConstraints:
      constraints*: seq[StyleLayoutConstraint]
    of svCssExpression:
      cssProperty*, cssText*: string

  StyleTokenStore* = ref object
    parent*: StyleTokenStore
    values*: Table[string, StyleValue]

  StyleKey*[T] = distinct string

  StylePatch* = ref object
    values*: Table[string, StyleValue]

const
  StyleFill* = StyleKey[Fill]("fill")
  StyleBackgroundColor* = StyleKey[Color]("background.color")
  StyleBackgroundFill* = StyleKey[Fill]("background.fill")
  StyleBackgroundPinstripeColor* = StyleKey[Color]("background.pinstripe.color")
  StyleBackgroundPinstripeHighlightColor* =
    StyleKey[Color]("background.pinstripe.highlight.color")
  StyleBackgroundPinstripePeriod* = StyleKey[float32]("background.pinstripe.period")
  StyleBackgroundPinstripeHeight* = StyleKey[float32]("background.pinstripe.height")
  StyleBorderColor* = StyleKey[Color]("border.color")
  StyleBorderWidth* = StyleKey[float32]("border.width")
  StyleCornerRadius* = StyleKey[float32]("corner.radius")
  StyleCornerRadiusTopLeft* = StyleKey[float32]("corner.radius.topLeft")
  StyleCornerRadiusTopRight* = StyleKey[float32]("corner.radius.topRight")
  StyleCornerRadiusBottomLeft* = StyleKey[float32]("corner.radius.bottomLeft")
  StyleCornerRadiusBottomRight* = StyleKey[float32]("corner.radius.bottomRight")
  StyleFocusRingWidth* = StyleKey[float32]("focus.ring.width")
  StyleFocusRingInset* = StyleKey[float32]("focus.ring.inset")
  StyleFocusRingColor* = StyleKey[Color]("focus.ring.color")
  StyleBoxShadows* = StyleKey[seq[BoxShadow]]("box.shadows")
  StyleColumnSelectionFill* = StyleKey[Fill]("column.selection.fill")
  StyleColumnHoverFill* = StyleKey[Fill]("column.hover.fill")
  StyleTextColor* = StyleKey[Color]("text.color")
  StyleFontName* = StyleKey[string]("font.name")
  StyleFontFace* = StyleKey[SystemTypeface]("font.face")
  StyleItalicFontFace* = StyleKey[SystemTypeface]("font.face.italic")
  StyleBoldFontFace* = StyleKey[SystemTypeface]("font.face.bold")
  StyleBoldItalicFontFace* = StyleKey[SystemTypeface]("font.face.boldItalic")
  StyleFontSize* = StyleKey[float32]("font.size")
  StyleFontSlant* = StyleKey[string]("font.slant")
  StyleLanguage* = StyleKey[string]("text.language")
  StyleTextHighlightColor* = StyleKey[Color]("text.highlight.color")
  StyleTextShadowColor* = StyleKey[Color]("text.shadow.color")
  StyleSelectionColor* = StyleKey[Color]("selection.color")
  StyleSelectionIndicatorPosition* = StyleKey[string]("selection.indicator.position")
  StyleSelectionIndicatorFill* = StyleKey[Fill]("selection.indicator.fill")
  StyleSelectionIndicatorInsets* = StyleKey[EdgeInsets]("selection.indicator.insets")
  StyleSelectionIndicatorSize* = StyleKey[float32]("selection.indicator.size")
  StyleSelectionIndicatorCornerRadius* =
    StyleKey[float32]("selection.indicator.corner.radius")
  StyleCursorColor* = StyleKey[Color]("cursor.color")
  StyleHighlightFill* = StyleKey[Fill]("highlight.fill")
  StyleMaximumHighlightFill* = StyleKey[Fill]("highlight.fill.maximum")
  StyleAlternatingFill* = StyleKey[Fill]("alternating.fill")
  StyleIndicatorFill* = StyleKey[Fill]("indicator.fill")
  StyleDropIndicatorFill* = StyleKey[Fill]("drop.indicator.fill")
  StyleInsertionIndicatorFill* = StyleKey[Fill]("insertion.indicator.fill")
  StyleKnobFill* = StyleKey[Fill]("knob.fill")
  StyleKnobValueTint* = StyleKey[float32]("knob.value.tint")
  StyleKnobBorderColor* = StyleKey[Color]("knob.border.color")
  StyleKnobSize* = StyleKey[float32]("knob.size")
  StyleKnobInset* = StyleKey[float32]("knob.inset")
  StyleKnobSizeFactor* = StyleKey[float32]("knob.size.factor")
  StyleKnobShadows* = StyleKey[seq[BoxShadow]]("knob.shadows")
  StyleTextInsets* = StyleKey[EdgeInsets]("text.insets")
  StylePadding* = StyleKey[EdgeInsets]("padding")
  StyleIndicatorSize* = StyleKey[float32]("indicator.size")
  StyleIndicatorSpacing* = StyleKey[float32]("indicator.spacing")
  StyleWidthFactor* = StyleKey[float32]("width.factor")
  StyleMaximumSize* = StyleKey[Size]("maximum.size")
  StyleSegmentSize* = StyleKey[Size]("segment.size")
  StyleEdgeInset* = StyleKey[float32]("edge.inset")
  StyleItemGap* = StyleKey[float32]("item.gap")
  StyleOverlap* = StyleKey[float32]("overlap")
  StyleRowHeight* = StyleKey[float32]("row.height")
  StyleHeaderHeight* = StyleKey[float32]("header.height")
  StyleColumnWidth* = StyleKey[float32]("column.width")
  StyleColumnMinWidth* = StyleKey[float32]("column.min.width")
  StyleColumnMaxWidth* = StyleKey[float32]("column.max.width")
  StyleResizeHandleWidth* = StyleKey[float32]("resize.handle.width")
  StyleDragThreshold* = StyleKey[float32]("drag.threshold")
  StyleAutoscrollEdge* = StyleKey[float32]("autoscroll.edge")
  StyleTitleHeight* = StyleKey[float32]("title.height")
  StyleTitleGap* = StyleKey[float32]("title.gap")
  StyleSeparatorThickness* = StyleKey[float32]("separator.thickness")
  StyleMarkColor* = StyleKey[Color]("mark.color")
  StyleMinimumSize* = StyleKey[Size]("minimum.size")
  StyleCloseButtonPosition* = StyleKey[string]("close.button.position")
  StyleChrome* = StyleKey[string]("chrome")
  StyleLayoutConstraints* = StyleKey[seq[StyleLayoutConstraint]]("layout.constraints")
  StyleLayoutWidth* = StyleKey[seq[StyleLayoutConstraint]]("layout.width")
  StyleLayoutHeight* = StyleKey[seq[StyleLayoutConstraint]]("layout.height")
  StyleLayoutMinWidth* = StyleKey[seq[StyleLayoutConstraint]]("layout.min.width")
  StyleLayoutMinHeight* = StyleKey[seq[StyleLayoutConstraint]]("layout.min.height")
  StyleLayoutMaxWidth* = StyleKey[seq[StyleLayoutConstraint]]("layout.max.width")
  StyleLayoutMaxHeight* = StyleKey[seq[StyleLayoutConstraint]]("layout.max.height")
  StyleLayoutLeft* = StyleKey[seq[StyleLayoutConstraint]]("layout.left")
  StyleLayoutTop* = StyleKey[seq[StyleLayoutConstraint]]("layout.top")
  StyleLayoutRight* = StyleKey[seq[StyleLayoutConstraint]]("layout.right")
  StyleLayoutBottom* = StyleKey[seq[StyleLayoutConstraint]]("layout.bottom")
  StyleContainerRowGap* = StyleKey[float32]("container.row.gap")
  StyleContainerColumnGap* = StyleKey[float32]("container.column.gap")
  StyleContainerInsets* = StyleKey[EdgeInsets]("container.insets")
  StyleContainerOrientation* = StyleKey[string]("container.orientation")
  StyleContainerAlignment* = StyleKey[string]("container.alignment")
  StyleContainerRowAlignment* = StyleKey[string]("container.row.alignment")
  StyleContainerColumnAlignment* = StyleKey[string]("container.column.alignment")
  StyleContainerDistribution* = StyleKey[string]("container.distribution")

  DefaultChromeName* = "default"
  AquaChromeName* = "aqua"
  RubyAquaChromeName* = "ruby-aqua"
  FlatTransparentChromeName* = "flat-transparent"
  ToolbarButtonStyleClass* = "toolbar-button"
  PopoverBoxStyleClass* = "popover-box"
  ToolbarSymbolStyleClass* = "toolbar-symbol"
  LabelStyleClass* = "label"
  LabelTitleStyleClass* = "label-title"
  LabelHeadingStyleClass* = "label-heading"
  LabelStatusStyleClass* = "label-status"
  LabelFormStyleClass* = "label-form"
  IconLabelStyleClass* = "icon-label"

func insets*(top, left, bottom, right: float32): EdgeInsets =
  EdgeInsets(top: top, left: left, bottom: bottom, right: right)

func insets*(vertical, horizontal: float32): EdgeInsets =
  insets(vertical, horizontal, vertical, horizontal)

func insets*(all: float32): EdgeInsets =
  insets(all, all, all, all)

func initCornerRadii*(
    topLeft, topRight, bottomLeft, bottomRight: float32
): CornerRadii =
  CornerRadii(
    topLeft: max(topLeft, 0.0'f32),
    topRight: max(topRight, 0.0'f32),
    bottomLeft: max(bottomLeft, 0.0'f32),
    bottomRight: max(bottomRight, 0.0'f32),
  )

func initCornerRadii*(all: float32): CornerRadii =
  initCornerRadii(all, all, all, all)

func isZero*(radii: CornerRadii): bool =
  radii.topLeft == 0.0'f32 and radii.topRight == 0.0'f32 and radii.bottomLeft == 0.0'f32 and
    radii.bottomRight == 0.0'f32

func inset*(radii: CornerRadii, amount: float32): CornerRadii =
  initCornerRadii(
    max(radii.topLeft - amount, 0.0'f32),
    max(radii.topRight - amount, 0.0'f32),
    max(radii.bottomLeft - amount, 0.0'f32),
    max(radii.bottomRight - amount, 0.0'f32),
  )

func horizontal*(insets: EdgeInsets): float32 =
  insets.left + insets.right

func vertical*(insets: EdgeInsets): float32 =
  insets.top + insets.bottom

func fill*(color: Color): Fill =
  figdraw.fill(color.rgba)

func linear*(start, stop: Color, axis: FillGradientAxis): Fill =
  figdraw.linear(start.rgba, stop.rgba, axis)

func linear*(start, mid, stop: Color, axis: FillGradientAxis, midPos = 128'u8): Fill =
  figdraw.linear(start.rgba, mid.rgba, stop.rgba, axis, midPos)

func initBoxShadow*(
    kind: BoxShadowKind,
    color: Color,
    x = 0.0'f32,
    y = 0.0'f32,
    blur = 0.0'f32,
    spread = 0.0'f32,
): BoxShadow =
  BoxShadow(kind: kind, color: color, x: x, y: y, blur: blur, spread: spread)

func dropShadow*(
    color: Color, x = 0.0'f32, y = 1.0'f32, blur = 3.0'f32, spread = 0.0'f32
): BoxShadow =
  initBoxShadow(bskDrop, color, x, y, blur, spread)

func insetShadow*(
    color: Color, x = 0.0'f32, y = 1.0'f32, blur = 2.0'f32, spread = 0.0'f32
): BoxShadow =
  initBoxShadow(bskInset, color, x, y, blur, spread)

func missingStyleValue*(): StyleValue =
  StyleValue(kind: svMissing)

func styleColor*(color: Color): StyleValue =
  StyleValue(kind: svColor, color: color)

func styleFill*(fill: Fill): StyleValue =
  StyleValue(kind: svFill, fill: fill)

func styleFill*(color: Color): StyleValue =
  styleFill(fill(color))

func styleLength*(length: float32): StyleValue =
  StyleValue(kind: svLength, length: length)

func styleSize*(size: Size): StyleValue =
  StyleValue(
    kind: svSize,
    size: Size(width: max(size.width, 0.0'f32), height: max(size.height, 0.0'f32)),
  )

func styleInsets*(insets: EdgeInsets): StyleValue =
  StyleValue(kind: svInsets, insets: insets)

func styleShadows*(shadows: openArray[BoxShadow]): StyleValue =
  StyleValue(kind: svShadows, shadows: @shadows)

proc styleConstraints*(constraints: openArray[StyleLayoutConstraint]): StyleValue =
  ## Packages value specifications without retaining any widget or native constraint.
  result = StyleValue(kind: svConstraints)
  for constraint in constraints:
    var copied = constraint
    copied.targetId = newStringOfCap(constraint.targetId.len)
    copied.targetId.add constraint.targetId
    result.constraints.add copied

func styleFontFace*(fontFace: SystemTypeface): StyleValue =
  StyleValue(kind: svFontFace, fontFace: fontFace)

func styleToken*(name: string): StyleValue =
  StyleValue(kind: svToken, token: name)

func styleKeyword*(keyword: string): StyleValue =
  StyleValue(kind: svKeyword, keyword: keyword)

func styleKeyword*(slant: FontSlant): StyleValue =
  styleKeyword(
    case slant
    of fsUpright: "normal"
    of fsItalic: "italic"
    of fsOblique: "oblique"
  )

func fontSlant*(keyword: string): FontSlant =
  case keyword
  of "italic": fsItalic
  of "oblique": fsOblique
  else: fsUpright

func styleKey*[T](name: string): StyleKey[T] =
  StyleKey[T](name)

func keyName*[T](key: StyleKey[T]): string =
  string(key)

func initStyleSelector*(
    role: StyleRole, states: set[WidgetState] = {}, id = "", classes: seq[string] = @[]
): StyleSelector =
  StyleSelector(role: role, states: states, id: id, classes: classes)

func initStyleContext*(
    role: StyleRole, states: set[WidgetState] = {}, id = "", classes: seq[string] = @[]
): StyleContext =
  StyleContext(role: role, states: states, id: id, classes: classes)

func controlStyle*(
    role: StyleRole, states: set[WidgetState] = {}, id = "", classes: seq[string] = @[]
): StyleContext =
  initStyleContext(role, states, id, classes)

func inset*(rect: Rect, insets: EdgeInsets): Rect =
  rect(
    rect.x + insets.left,
    rect.y + insets.top,
    max(rect.w - insets.left - insets.right, 0.0'f32),
    max(rect.h - insets.top - insets.bottom, 0.0'f32),
  )

proc newStyleTokenStore*(parent: StyleTokenStore = nil): StyleTokenStore =
  StyleTokenStore(parent: parent, values: initTable[string, StyleValue]())

proc newStylePatch*(): StylePatch =
  StylePatch(values: initTable[string, StyleValue]())

proc cloneText*(value: string): string =
  result = newStringOfCap(value.len)
  result.add value

proc clone*(value: StyleValue): StyleValue =
  case value.kind
  of svMissing:
    missingStyleValue()
  of svColor:
    styleColor(value.color)
  of svFill:
    styleFill(value.fill)
  of svLength:
    styleLength(value.length)
  of svSize:
    styleSize(value.size)
  of svInsets:
    styleInsets(value.insets)
  of svShadows:
    styleShadows(value.shadows)
  of svConstraints:
    styleConstraints(value.constraints)
  of svCssExpression:
    StyleValue(
      kind: svCssExpression,
      cssProperty: value.cssProperty.cloneText,
      cssText: value.cssText.cloneText,
    )
  of svFontFace:
    var variations =
      newSeqOfCap[typeof(value.fontFace.variations[0])](value.fontFace.variations.len)
    for variation in value.fontFace.variations:
      variations.add variation
    styleFontFace(
      SystemTypeface(
        file: typeof(value.fontFace.file)(
          path: value.fontFace.file.path.cloneText,
          faceIndex: value.fontFace.file.faceIndex,
        ),
        variations: move variations,
      )
    )
  of svToken:
    styleToken(value.token.cloneText)
  of svKeyword:
    styleKeyword(value.keyword.cloneText)

proc clone*(tokens: StyleTokenStore): StyleTokenStore =
  if tokens.isNil:
    return
  result = newStyleTokenStore(tokens.parent.clone)
  for name, value in tokens.values:
    result.values[name.cloneText] = value.clone

proc clone*(patch: StylePatch): StylePatch =
  if patch.isNil:
    return
  result = newStylePatch()
  for name, value in patch.values:
    result.values[name.cloneText] = value.clone

func cssTokenName*(name: string): string =
  ## Legacy dotted/camelCase names alias CSS custom properties.
  if name.startsWith("--"):
    return name
  result = "--"
  for character in name:
    if character == '.':
      result.add '-'
    elif character in {'A' .. 'Z'}:
      result.add '-'
      result.add character.toLowerAscii()
    else:
      result.add character

proc `[]=`*(tokens: StyleTokenStore, name: string, value: StyleValue) =
  tokens.values[name.cssTokenName] = value

proc `[]=`*(tokens: StyleTokenStore, name: string, value: Color) =
  tokens[name] = styleColor(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: Fill) =
  tokens[name] = styleFill(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: float32) =
  tokens[name] = styleLength(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: float) =
  tokens[name] = styleLength(value.float32)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: Size) =
  tokens[name] = styleSize(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: EdgeInsets) =
  tokens[name] = styleInsets(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: openArray[BoxShadow]) =
  tokens[name] = styleShadows(value)

proc lookupToken*(tokens: StyleTokenStore, name: string, value: var StyleValue): bool =
  let canonical = name.cssTokenName
  var current = tokens
  while not current.isNil:
    if current.values.hasKey(canonical):
      value = current.values[canonical]
      return true
    current = current.parent

proc resolveToken*(tokens: StyleTokenStore, name: string, value: var StyleValue): bool =
  var
    currentName = name
    currentValue: StyleValue
  for depth in 0 ..< 16:
    if not tokens.lookupToken(currentName, currentValue):
      value = missingStyleValue()
      return false
    if currentValue.kind != svToken:
      value = currentValue
      return true
    currentName = currentValue.token
  value = missingStyleValue()

proc resolveValue*(
    tokens: StyleTokenStore, input: StyleValue, value: var StyleValue
): bool =
  if input.kind == svToken:
    tokens.resolveToken(input.token, value)
  elif input.kind == svMissing:
    value = missingStyleValue()
    false
  else:
    value = input
    true

proc setStyle*(patch: StylePatch, key: string, value: StyleValue) =
  patch.values[key] = value
  if key == StyleCornerRadius.keyName:
    for corner in [
      StyleCornerRadiusTopLeft, StyleCornerRadiusTopRight, StyleCornerRadiusBottomLeft,
      StyleCornerRadiusBottomRight,
    ]:
      patch.values[corner.keyName] = value

proc setStyle*[T](patch: StylePatch, key: StyleKey[T], value: StyleValue) =
  patch.setStyle(key.keyName, value)

proc setStyle*(patch: StylePatch, key: StyleKey[Color], value: Color) =
  patch.setStyle(key, styleColor(value))

proc setStyle*(patch: StylePatch, key: StyleKey[Fill], value: Fill) =
  patch.setStyle(key, styleFill(value))

proc setStyle*(patch: StylePatch, key: StyleKey[float32], value: float32) =
  patch.setStyle(key, styleLength(value))

proc setStyle*(patch: StylePatch, key: StyleKey[float32], value: float) =
  patch.setStyle(key, styleLength(value.float32))

proc setStyle*(patch: StylePatch, key: StyleKey[Size], value: Size) =
  patch.setStyle(key, styleSize(value))

proc setStyle*(patch: StylePatch, key: StyleKey[EdgeInsets], value: EdgeInsets) =
  patch.setStyle(key, styleInsets(value))

proc setStyle*(
    patch: StylePatch, key: StyleKey[seq[BoxShadow]], value: openArray[BoxShadow]
) =
  patch.setStyle(key, styleShadows(value))

proc `[]=`*(patch: StylePatch, key: string, value: StyleValue) =
  patch.setStyle(key, value)

proc `[]=`*[T](patch: StylePatch, key: StyleKey[T], value: StyleValue) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[Color], value: Color) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[Fill], value: Fill) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[float32], value: float32) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[float32], value: float) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[Size], value: Size) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[EdgeInsets], value: EdgeInsets) =
  patch.setStyle(key, value)

proc `[]=`*(
    patch: StylePatch, key: StyleKey[seq[BoxShadow]], value: openArray[BoxShadow]
) =
  patch.setStyle(key, value)

proc getStyle*(patch: StylePatch, key: string, value: var StyleValue): bool =
  if patch.values.hasKey(key):
    value = patch.values[key]
    return true

proc getStyle*[T](patch: StylePatch, key: StyleKey[T], value: var StyleValue): bool =
  patch.getStyle(key.keyName, value)

func layoutAttributeCategory*(attribute: LayoutAttribute): int =
  case attribute
  of atLeft, atRight, atLeading, atTrailing, atCenterX: 1
  of atTop, atBottom, atCenterY, atFirstBaseline, atLastBaseline: 2
  of atWidth, atHeight: 3
  of atNotAnAttribute: 0

func validStyleConstraint*(constraint: StyleLayoutConstraint): bool =
  let priority = constraint.priority.priorityValue
  if constraint.attribute == atNotAnAttribute or
      constraint.constant.classify in {fcNan, fcInf, fcNegInf} or
      constraint.multiplier.classify in {fcNan, fcInf, fcNegInf} or
      constraint.multiplier <= 0 or priority.classify in {fcNan, fcInf, fcNegInf} or
      priority < 1 or priority > 1000:
    return
  if constraint.target == sltConstant:
    return constraint.attribute in {atWidth, atHeight}
  if constraint.target == sltSibling and constraint.targetId.len == 0:
    return
  constraint.attribute.layoutAttributeCategory ==
    constraint.targetAttribute.layoutAttributeCategory and
    (constraint.multiplier == 1 or constraint.attribute in {atWidth, atHeight})
