import std/tables

import figdraw/common/filltypes
from pkg/chroma import rgba
from sigils/selectors import DynamicAgent

import ../foundation/types

export filltypes

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
    of svToken:
      token*: string
    of svKeyword:
      keyword*: string

  StyleTokenStore* = ref object
    parent*: StyleTokenStore
    values*: Table[string, StyleValue]

  StyleKey*[T] = distinct string

  StylePatch* = ref object
    values*: Table[string, StyleValue]

  StyleRule* = object
    selector*: StyleSelector
    patch*: StylePatch

  Chrome* = ref object of DynamicAgent

  Theme* = object
    tokens*: StyleTokenStore
    rules*: seq[StyleRule]
    chromes*: Table[string, Chrome]

  Appearance* = object
    theme*: Theme

  ControlBoxStyle* = object
    fill*: Fill
    borderColor*: Color
    borderWidth*: float32
    cornerRadius*: float32
    cornerRadii*: CornerRadii
    focusRingWidth*: float32
    focusRingInset*: float32
    focusRingColor*: Color
    shadows*: seq[BoxShadow]

  ScrollViewStyle* = object
    box*: ControlBoxStyle
    scrollerTrack*: ControlBoxStyle
    scrollerKnob*: ControlBoxStyle

  TextStyle* = object
    color*: Color
    insets*: EdgeInsets
    fontName*: string
    fontSize*: float32

  ButtonStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    textHighlightColor*: Color
    textShadowColor*: Color
    minSize*: Size
    chrome*: string

  ChoiceButtonStyle* = object
    indicator*: ControlBoxStyle
    markColor*: Color
    text*: TextStyle
    indicatorSize*: float32
    indicatorSpacing*: float32
    minSize*: Size
    chrome*: string

  SwitchButtonStyle* = object
    track*: ControlBoxStyle
    knob*: ControlBoxStyle
    knobInset*: float32
    knobSizeFactor*: float32
    minSize*: Size
    chrome*: string

  SliderStyle* = object
    track*: ControlBoxStyle
    activeTrack*: ControlBoxStyle
    knob*: ControlBoxStyle
    trackHeight*: float32
    knobSize*: float32
    minSize*: Size
    chrome*: string

  TabViewStyle* = object
    tabHeight*: float32
    tabSegmentHeight*: float32
    tabMinWidth*: float32
    tabMaxWidth*: float32
    tabHorizontalPadding*: float32
    tabInset*: float32
    tabGap*: float32
    contentBorderWidth*: float32
    tabCornerRadius*: float32
    panelCornerRadius*: float32
    panelOverlap*: float32

  ThemeInstaller* = proc(theme: var Theme)

  TextFieldStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    selectionColor*: Color
    minSize*: Size

  MonoTextStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    cursorColor*: Color
    minSize*: Size
    chrome*: string

  ComboBoxStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    arrowWidth*: float32
    arrowFill*: Fill
    arrowColor*: Color
    minSize*: Size
    chrome*: string

  TableViewStyle* = object
    box*: ControlBoxStyle
    minSize*: Size
    rowHeight*: float32
    headerHeight*: float32
    columnWidth*: float32
    columnMinWidth*: float32
    columnMaxWidth*: float32
    headerResizeHandleWidth*: float32
    headerDragThreshold*: float32
    headerAutoscrollEdge*: float32

  SplitViewStyle* = object
    divider*: ControlBoxStyle
    dividerThickness*: float32

  RowItemStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    minSize*: Size

  BoxStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    contentInsets*: EdgeInsets
    titleHeight*: float32
    titleGap*: float32
    separatorThickness*: float32
    minSize*: Size

const
  StyleFill* = StyleKey[Fill]("fill")
  StyleBackgroundColor* = StyleKey[Color]("background.color")
  StyleBackgroundFill* = StyleKey[Fill]("background.fill")
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
  StyleTextColor* = StyleKey[Color]("text.color")
  StyleFontName* = StyleKey[string]("font.name")
  StyleFontSize* = StyleKey[float32]("font.size")
  StyleTextHighlightColor* = StyleKey[Color]("text.highlight.color")
  StyleTextShadowColor* = StyleKey[Color]("text.shadow.color")
  StyleSelectionColor* = StyleKey[Color]("selection.color")
  StyleCursorColor* = StyleKey[Color]("cursor.color")
  StyleHighlightFill* = StyleKey[Fill]("highlight.fill")
  StyleAlternatingFill* = StyleKey[Fill]("alternating.fill")
  StyleIndicatorFill* = StyleKey[Fill]("indicator.fill")
  StyleDropIndicatorFill* = StyleKey[Fill]("drop.indicator.fill")
  StyleInsertionIndicatorFill* = StyleKey[Fill]("insertion.indicator.fill")
  StyleKnobFill* = StyleKey[Fill]("knob.fill")
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
  StyleChrome* = StyleKey[string]("chrome")

  DefaultChromeName* = "default"
  AquaChromeName* = "aqua"
  FlatTransparentChromeName* = "flat-transparent"
  LabelStyleClass* = "label"
  LabelTitleStyleClass* = "label-title"
  LabelHeadingStyleClass* = "label-heading"
  LabelStatusStyleClass* = "label-status"
  LabelFormStyleClass* = "label-form"

var themeInstallers {.threadvar.}: seq[ThemeInstaller]

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
  filltypes.fill(color.rgba)

func linear*(start, stop: Color, axis: FillGradientAxis): Fill =
  filltypes.linear(start.rgba, stop.rgba, axis)

func linear*(start, mid, stop: Color, axis: FillGradientAxis, midPos = 128'u8): Fill =
  filltypes.linear(start.rgba, mid.rgba, stop.rgba, axis, midPos)

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

func styleToken*(name: string): StyleValue =
  StyleValue(kind: svToken, token: name)

func styleKeyword*(keyword: string): StyleValue =
  StyleValue(kind: svKeyword, keyword: keyword)

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

proc clone*(tokens: StyleTokenStore): StyleTokenStore =
  if tokens.isNil:
    return
  result = newStyleTokenStore(tokens.parent.clone)
  result.values = tokens.values

proc clone*(patch: StylePatch): StylePatch =
  if patch.isNil:
    return
  result = newStylePatch()
  result.values = patch.values

proc clone*(theme: Theme): Theme =
  result.tokens = theme.tokens.clone
  for rule in theme.rules:
    result.rules.add StyleRule(selector: rule.selector, patch: rule.patch.clone)
  result.chromes = theme.chromes

proc registerThemeInstaller*(installer: ThemeInstaller) =
  themeInstallers.add installer

proc installThemeExtensions*(theme: var Theme) =
  for installer in themeInstallers:
    installer(theme)

proc installChrome*(theme: var Theme, name: string, chrome: Chrome) =
  if name.len == 0:
    return
  if chrome.isNil:
    if name in theme.chromes:
      theme.chromes.del(name)
  else:
    theme.chromes[name] = chrome

proc hasChrome*(theme: Theme, name: string): bool =
  name in theme.chromes

proc chrome*(theme: Theme, name: string): Chrome =
  if name in theme.chromes:
    return theme.chromes[name]

proc installChrome*(appearance: var Appearance, name: string, chrome: Chrome) =
  appearance.theme.installChrome(name, chrome)

proc hasChrome*(appearance: Appearance, name: string): bool =
  appearance.theme.hasChrome(name)

proc chrome*(appearance: Appearance, name: string): Chrome =
  appearance.theme.chrome(name)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: StyleValue) =
  tokens.values[name] = value

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

proc `[]=`*(theme: var Theme, name: string, value: StyleValue) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: Color) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: Fill) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: float32) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: float) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: Size) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: EdgeInsets) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: openArray[BoxShadow]) =
  theme.tokens[name] = value

proc lookupToken(tokens: StyleTokenStore, name: string, value: var StyleValue): bool =
  var current = tokens
  while not current.isNil:
    if current.values.hasKey(name):
      value = current.values[name]
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

func matches*(selector: StyleSelector, context: StyleContext): bool =
  if selector.role != context.role:
    return false
  if not (selector.states <= context.states):
    return false
  if selector.id.len > 0 and selector.id != context.id:
    return false
  for class in selector.classes:
    if class notin context.classes:
      return false
  true

func specificity(selector: StyleSelector): int =
  result = selector.classes.len * 100
  for state in selector.states:
    discard state
    result += 1
  if selector.id.len > 0:
    result += 10000

func inheritedStyleRole(role: StyleRole): StyleRole =
  case role
  of srStepper: srButton
  of srDocumentTab, srDocumentTabButton: srTab
  of srDocumentTabBar: srTabPanel
  else: role

proc stylePatch*(theme: var Theme, selector: StyleSelector): StylePatch =
  for rule in theme.rules:
    if rule.selector == selector:
      return rule.patch
  result = newStylePatch()
  theme.rules.add StyleRule(selector: selector, patch: result)

proc stylePatch*(theme: Theme, selector: StyleSelector): StylePatch =
  for rule in theme.rules:
    if rule.selector == selector:
      return rule.patch

proc addRule*(theme: var Theme, selector: StyleSelector, patch: StylePatch) =
  theme.rules.add StyleRule(selector: selector, patch: patch)

proc setStyle*[T](
    theme: var Theme, selector: StyleSelector, key: StyleKey[T], value: StyleValue
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Color], value: Color
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Fill], value: Fill
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float32
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Size], value: Size
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*[T](
    theme: var Theme, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(theme: var Theme, role: StyleRole, key: StyleKey[Color], value: Color) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(theme: var Theme, role: StyleRole, key: StyleKey[Fill], value: Fill) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float32
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(theme: var Theme, role: StyleRole, key: StyleKey[Size], value: Size) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme, role: StyleRole, key: StyleKey[EdgeInsets], value: EdgeInsets
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*[T](
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc `[]=`*[T](
    theme: var Theme, selector: StyleSelector, key: StyleKey[T], value: StyleValue
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Color], value: Color
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Fill], value: Fill
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float32
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Size], value: Size
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(selector, key, value)

proc `[]=`*[T](theme: var Theme, role: StyleRole, key: StyleKey[T], value: StyleValue) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[Color], value: Color) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[Fill], value: Fill) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float32) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[Size], value: Size) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var Theme, role: StyleRole, key: StyleKey[EdgeInsets], value: EdgeInsets
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(role, key, value)

proc `[]=`*[T](
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(role, states, key, value)

proc `[]`*[T](theme: Theme, role: StyleRole, key: StyleKey[T]): StyleValue =
  let patch = theme.stylePatch(initStyleSelector(role))
  if patch.isNil or not patch.getStyle(key, result):
    result = missingStyleValue()

proc ruleValue(
    theme: Theme, context: StyleContext, key: string, fallback: StyleValue
): StyleValue =
  result = fallback
  var bestSpecificity = -1
  for rule in theme.rules:
    template applyRule(matchContext: StyleContext, roleRank: int) =
      var value: StyleValue
      if rule.selector.matches(matchContext) and rule.patch.getStyle(key, value):
        let ruleSpecificity = rule.selector.specificity() * 10 + roleRank
        if ruleSpecificity >= bestSpecificity:
          var resolved: StyleValue
          if theme.tokens.resolveValue(value, resolved):
            result = resolved
            bestSpecificity = ruleSpecificity
          elif value.kind != svToken:
            result = value
            bestSpecificity = ruleSpecificity

    let inheritedRole = context.role.inheritedStyleRole()
    if inheritedRole != context.role:
      var inheritedContext = context
      inheritedContext.role = inheritedRole
      applyRule(inheritedContext, 0)
    applyRule(context, 1)

proc colorRule(
    theme: Theme, context: StyleContext, key: StyleKey[Color], fallback: Color
): Color =
  let value = theme.ruleValue(context, key.keyName, styleColor(fallback))
  case value.kind
  of svColor:
    value.color
  of svFill:
    value.fill.centerColor()
  else:
    fallback

proc fillRule(
    theme: Theme, context: StyleContext, key: StyleKey[Fill], fallback: Fill
): Fill =
  let value = theme.ruleValue(context, key.keyName, styleFill(fallback))
  case value.kind
  of svFill:
    value.fill
  of svColor:
    fill(value.color)
  else:
    fallback

proc lengthRule(
    theme: Theme, context: StyleContext, key: StyleKey[float32], fallback: float32
): float32 =
  let value = theme.ruleValue(context, key.keyName, styleLength(fallback))
  if value.kind == svLength: value.length else: fallback

proc sizeRule(
    theme: Theme, context: StyleContext, key: StyleKey[Size], fallback: Size
): Size =
  let value = theme.ruleValue(context, key.keyName, styleSize(fallback))
  if value.kind == svSize: value.size else: fallback

proc insetsRule(
    theme: Theme, context: StyleContext, key: StyleKey[EdgeInsets], fallback: EdgeInsets
): EdgeInsets =
  let value = theme.ruleValue(context, key.keyName, styleInsets(fallback))
  if value.kind == svInsets: value.insets else: fallback

proc shadowsRule(
    theme: Theme,
    context: StyleContext,
    key: StyleKey[seq[BoxShadow]],
    fallback: seq[BoxShadow],
): seq[BoxShadow] =
  let value = theme.ruleValue(context, key.keyName, styleShadows(fallback))
  if value.kind == svShadows: value.shadows else: fallback

proc keywordRule(
    theme: Theme, context: StyleContext, key: StyleKey[string], fallback: string
): string =
  let value = theme.ruleValue(context, key.keyName, styleKeyword(fallback))
  if value.kind == svKeyword: value.keyword else: fallback

proc styleValue*(theme: Theme, name: string, fallback: StyleValue): StyleValue =
  if theme.tokens.isNil:
    return fallback
  if not theme.tokens.resolveToken(name, result):
    result = fallback

proc colorToken*(theme: Theme, name: string, fallback: Color): Color =
  let value = theme.styleValue(name, styleColor(fallback))
  case value.kind
  of svColor:
    value.color
  of svFill:
    value.fill.centerColor()
  else:
    fallback

proc fillToken*(theme: Theme, name: string, fallback: Fill): Fill =
  let value = theme.styleValue(name, styleFill(fallback))
  case value.kind
  of svFill:
    value.fill
  of svColor:
    fill(value.color)
  else:
    fallback

proc lengthToken*(theme: Theme, name: string, fallback: float32): float32 =
  let value = theme.styleValue(name, styleLength(fallback))
  if value.kind == svLength: value.length else: fallback

proc sizeToken*(theme: Theme, name: string, fallback: Size): Size =
  let value = theme.styleValue(name, styleSize(fallback))
  if value.kind == svSize: value.size else: fallback

proc insetsToken*(theme: Theme, name: string, fallback: EdgeInsets): EdgeInsets =
  let value = theme.styleValue(name, styleInsets(fallback))
  if value.kind == svInsets: value.insets else: fallback

proc shadowsToken*(
    theme: Theme, name: string, fallback: seq[BoxShadow]
): seq[BoxShadow] =
  let value = theme.styleValue(name, styleShadows(fallback))
  if value.kind == svShadows: value.shadows else: fallback

proc styleValue*(
    appearance: Appearance, name: string, fallback: StyleValue
): StyleValue =
  appearance.theme.styleValue(name, fallback)

proc colorToken*(appearance: Appearance, name: string, fallback: Color): Color =
  appearance.theme.colorToken(name, fallback)

proc fillToken*(appearance: Appearance, name: string, fallback: Fill): Fill =
  appearance.theme.fillToken(name, fallback)

proc lengthToken*(appearance: Appearance, name: string, fallback: float32): float32 =
  appearance.theme.lengthToken(name, fallback)

proc sizeToken*(appearance: Appearance, name: string, fallback: Size): Size =
  appearance.theme.sizeToken(name, fallback)

proc insetsToken*(
    appearance: Appearance, name: string, fallback: EdgeInsets
): EdgeInsets =
  appearance.theme.insetsToken(name, fallback)

proc shadowsToken*(
    appearance: Appearance, name: string, fallback: seq[BoxShadow]
): seq[BoxShadow] =
  appearance.theme.shadowsToken(name, fallback)

proc resolveFill*(
    theme: Theme, context: StyleContext, fallback: Fill, key = StyleFill
): Fill =
  theme.fillRule(context, key, fallback)

proc resolveFill*(
    appearance: Appearance, context: StyleContext, fallback: Fill, key = StyleFill
): Fill =
  appearance.theme.resolveFill(context, fallback, key)

proc resolveColor*(
    theme: Theme, context: StyleContext, key: StyleKey[Color], fallback: Color
): Color =
  theme.colorRule(context, key, fallback)

proc resolveColor*(
    appearance: Appearance, context: StyleContext, key: StyleKey[Color], fallback: Color
): Color =
  appearance.theme.resolveColor(context, key, fallback)

proc resolveLength*(
    theme: Theme, context: StyleContext, key: StyleKey[float32], fallback: float32
): float32 =
  theme.lengthRule(context, key, fallback)

proc resolveLength*(
    appearance: Appearance,
    context: StyleContext,
    key: StyleKey[float32],
    fallback: float32,
): float32 =
  appearance.theme.resolveLength(context, key, fallback)

proc resolveInsets*(
    theme: Theme, context: StyleContext, key: StyleKey[EdgeInsets], fallback: EdgeInsets
): EdgeInsets =
  theme.insetsRule(context, key, fallback)

proc resolveInsets*(
    appearance: Appearance,
    context: StyleContext,
    key: StyleKey[EdgeInsets],
    fallback: EdgeInsets,
): EdgeInsets =
  appearance.theme.resolveInsets(context, key, fallback)

proc resolveChromeName*(theme: Theme, context: StyleContext): string =
  theme.keywordRule(context, StyleChrome, DefaultChromeName)

proc resolveChromeName*(appearance: Appearance, context: StyleContext): string =
  appearance.theme.resolveChromeName(context)

proc resolveTextStyle*(
    theme: Theme,
    context: StyleContext,
    colorFallback: Color,
    insetsFallback: EdgeInsets,
): TextStyle =
  TextStyle(
    color: theme.colorRule(context, StyleTextColor, colorFallback),
    insets: theme.insetsRule(context, StyleTextInsets, insetsFallback),
    fontName: theme.keywordRule(context, StyleFontName, defaultFontName()),
    fontSize: max(theme.lengthRule(context, StyleFontSize, defaultFontSize()), 1.0'f32),
  )

proc resolveTextStyle*(
    appearance: Appearance,
    context: StyleContext,
    colorFallback: Color,
    insetsFallback: EdgeInsets,
): TextStyle =
  appearance.theme.resolveTextStyle(context, colorFallback, insetsFallback)

proc setStyle*[T](
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[T],
    value: StyleValue,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Color],
    value: Color,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Fill],
    value: Fill,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float32,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Size],
    value: Size,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*[T](
    appearance: var Appearance, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Color], value: Color
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Fill], value: Fill
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float32
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Size], value: Size
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.theme.setStyle(role, key, value)

proc `[]=`*[T](
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[T],
    value: StyleValue,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Color],
    value: Color,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Fill],
    value: Fill,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float32,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Size],
    value: Size,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.theme[selector, key] = value

proc `[]=`*[T](
    appearance: var Appearance, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Color], value: Color
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Fill], value: Fill
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float32
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Size], value: Size
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.setStyle(role, key, value)

proc `[]=`*[T](
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[T],
    value: StyleValue,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.theme[role, states, key] = value

proc `[]`*[T](appearance: Appearance, role: StyleRole, key: StyleKey[T]): StyleValue =
  appearance.theme[role, key]

proc cornerRadiiRule(
    theme: Theme, context: StyleContext, fallback: float32
): CornerRadii =
  initCornerRadii(
    theme.lengthRule(context, StyleCornerRadiusTopLeft, fallback),
    theme.lengthRule(context, StyleCornerRadiusTopRight, fallback),
    theme.lengthRule(context, StyleCornerRadiusBottomLeft, fallback),
    theme.lengthRule(context, StyleCornerRadiusBottomRight, fallback),
  )

proc resolveControlBoxStyle(
    theme: Theme,
    context: StyleContext,
    fillFallback: Fill,
    borderColorFallback: Color,
    borderWidthFallback = 1.0'f32,
    cornerRadiusFallback = 6.0'f32,
    focusRingWidthFallback = 3.0'f32,
    focusRingInsetFallback = 2.0'f32,
    focusRingColorFallback = color(0.24, 0.48, 0.92, 0.58),
    fillKey: StyleKey[Fill] = StyleFill,
    borderColorKey: StyleKey[Color] = StyleBorderColor,
    shadowKey: StyleKey[seq[BoxShadow]] = StyleBoxShadows,
    shadowsFallback: seq[BoxShadow] = @[],
): ControlBoxStyle =
  let cornerRadius = theme.lengthRule(context, StyleCornerRadius, cornerRadiusFallback)
  ControlBoxStyle(
    fill: theme.fillRule(context, fillKey, fillFallback),
    borderColor: theme.colorRule(context, borderColorKey, borderColorFallback),
    borderWidth: theme.lengthRule(context, StyleBorderWidth, borderWidthFallback),
    cornerRadius: cornerRadius,
    cornerRadii: theme.cornerRadiiRule(context, cornerRadius),
    focusRingWidth:
      theme.lengthRule(context, StyleFocusRingWidth, focusRingWidthFallback),
    focusRingInset:
      theme.lengthRule(context, StyleFocusRingInset, focusRingInsetFallback),
    focusRingColor:
      theme.colorRule(context, StyleFocusRingColor, focusRingColorFallback),
    shadows: theme.shadowsRule(context, shadowKey, shadowsFallback),
  )

proc resolveScrollViewStyle*(theme: Theme, context: StyleContext): ScrollViewStyle =
  let scrollerContext =
    if context.role in {srScroller, srCascadingScroller}:
      context
    else:
      controlStyle(
        srScroller, context.states, id = context.id, classes = context.classes
      )
  ScrollViewStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(0.98, 0.985, 0.995, 1.0)),
      color(0.55, 0.58, 0.64, 1.0),
      cornerRadiusFallback = 0.0,
      focusRingWidthFallback = 0.0,
      focusRingInsetFallback = 0.0,
      focusRingColorFallback = color(0.0, 0.0, 0.0, 0.0),
    ),
    scrollerTrack: theme.resolveControlBoxStyle(
      scrollerContext,
      fill(color(0.88, 0.90, 0.94, 0.70)),
      color(0.67, 0.71, 0.78, 0.80),
      cornerRadiusFallback = 3.0,
      focusRingWidthFallback = 0.0,
      focusRingInsetFallback = 0.0,
      focusRingColorFallback = color(0.0, 0.0, 0.0, 0.0),
    ),
    scrollerKnob: theme.resolveControlBoxStyle(
      scrollerContext,
      fill(color(0.36, 0.42, 0.50, 0.65)),
      color(0.24, 0.29, 0.36, 0.50),
      cornerRadiusFallback = 3.0,
      focusRingWidthFallback = 0.0,
      focusRingInsetFallback = 0.0,
      focusRingColorFallback = color(0.0, 0.0, 0.0, 0.0),
      fillKey = StyleKnobFill,
      borderColorKey = StyleKnobBorderColor,
      shadowKey = StyleKnobShadows,
    ),
  )

proc resolveButtonStyle*(theme: Theme, context: StyleContext): ButtonStyle =
  ButtonStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(0.20, 0.48, 0.86, 1.0)),
      color(0.10, 0.25, 0.46, 1.0),
      cornerRadiusFallback = 14.0,
    ),
    text: theme.resolveTextStyle(context, color(1.0, 1.0, 1.0, 1.0), insets(0.0, 8.0)),
    textHighlightColor:
      theme.colorRule(context, StyleTextHighlightColor, color(0.0, 0.0, 0.0, 0.0)),
    textShadowColor:
      theme.colorRule(context, StyleTextShadowColor, color(0.0, 0.0, 0.0, 0.0)),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(0.0, 32.0)),
    chrome: theme.resolveChromeName(context),
  )

proc resolveChoiceButtonStyle*(theme: Theme, context: StyleContext): ChoiceButtonStyle =
  ChoiceButtonStyle(
    indicator: theme.resolveControlBoxStyle(
      context,
      fill(color(1.0, 1.0, 1.0, 1.0)),
      color(0.50, 0.55, 0.62, 1.0),
      cornerRadiusFallback = 6.0,
    ),
    markColor: theme.colorRule(context, StyleMarkColor, color(1.0, 1.0, 1.0, 1.0)),
    text:
      theme.resolveTextStyle(context, color(0.08, 0.09, 0.11, 1.0), insets(0.0, 2.0)),
    indicatorSize: theme.lengthRule(context, StyleIndicatorSize, 14.0),
    indicatorSpacing: theme.lengthRule(context, StyleIndicatorSpacing, 7.0),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(0.0, 18.0)),
    chrome: theme.resolveChromeName(context),
  )

proc resolveSwitchButtonStyle*(theme: Theme, context: StyleContext): SwitchButtonStyle =
  let
    indicatorSize = theme.lengthRule(context, StyleIndicatorSize, 24.0)
    widthFactor = theme.lengthRule(context, StyleWidthFactor, 1.67)
    configuredSize =
      theme.sizeRule(context, StyleMinimumSize, initSize(0.0, indicatorSize))
    minSize = initSize(
      if configuredSize.width > 0.0'f32:
        configuredSize.width
      else:
        indicatorSize * widthFactor,
      if configuredSize.height > 0.0'f32: configuredSize.height else: indicatorSize,
    )
  SwitchButtonStyle(
    track: theme.resolveControlBoxStyle(
      context,
      fill(color(0.72, 0.78, 0.84, 1.0)),
      color(0.38, 0.45, 0.53, 0.70),
      cornerRadiusFallback = 12.0,
      focusRingInsetFallback = -3.0,
      focusRingColorFallback = color(0.28, 0.62, 1.0, 0.80),
    ),
    knob: theme.resolveControlBoxStyle(
      context,
      fill(color(0.96, 0.97, 0.99, 1.0)),
      color(0.32, 0.36, 0.44, 0.78),
      cornerRadiusFallback = 10.3,
      fillKey = StyleKnobFill,
      borderColorKey = StyleKnobBorderColor,
      shadowKey = StyleKnobShadows,
    ),
    knobInset: theme.lengthRule(context, StyleKnobInset, 1.7),
    knobSizeFactor: theme.lengthRule(context, StyleKnobSizeFactor, 2.0),
    minSize: minSize,
    chrome: theme.resolveChromeName(context),
  )

proc resolveSliderStyle*(theme: Theme, context: StyleContext): SliderStyle =
  SliderStyle(
    track: theme.resolveControlBoxStyle(
      context,
      fill(color(0.76, 0.82, 0.88, 1.0)),
      color(0.38, 0.46, 0.56, 0.75),
      cornerRadiusFallback = 3.0,
      shadowsFallback = @[insetShadow(color(0.0, 0.0, 0.0, 0.16), y = 1.0, blur = 2.0)],
    ),
    activeTrack: theme.resolveControlBoxStyle(
      context,
      fill(color(0.13, 0.55, 0.96, 1.0)),
      color(0.02, 0.20, 0.58, 0.70),
      cornerRadiusFallback = 3.0,
      fillKey = StyleHighlightFill,
      borderColorKey = StyleFocusRingColor,
      shadowsFallback = @[insetShadow(color(0.0, 0.0, 0.0, 0.16), y = 1.0, blur = 2.0)],
    ),
    knob: theme.resolveControlBoxStyle(
      context,
      fill(color(0.92, 0.94, 0.97, 1.0)),
      color(0.36, 0.40, 0.48, 0.92),
      cornerRadiusFallback = 9.0,
      fillKey = StyleKnobFill,
      borderColorKey = StyleKnobBorderColor,
      shadowKey = StyleKnobShadows,
      shadowsFallback =
        @[
          dropShadow(color(0.0, 0.0, 0.0, 0.20), y = 1.0, blur = 3.0),
          insetShadow(color(1.0, 1.0, 1.0, 0.75), y = 1.0, blur = 2.0),
        ],
    ),
    trackHeight: theme.lengthRule(context, StyleIndicatorSize, 6.0'f32),
    knobSize: theme.lengthRule(context, StyleKnobSize, 18.0'f32),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(160.0'f32, 24.0'f32)),
    chrome: theme.resolveChromeName(context),
  )

proc resolveProgressIndicatorStyle*(theme: Theme, context: StyleContext): SliderStyle =
  theme.resolveSliderStyle(context)

proc resolveTabViewStyle*(theme: Theme, context: StyleContext): TabViewStyle =
  let
    panelContext = controlStyle(srTabPanel)
    minSize = theme.sizeRule(context, StyleMinimumSize, initSize(48.0'f32, 24.0'f32))
    maxSize = theme.sizeRule(context, StyleMaximumSize, initSize(180.0'f32, 0.0'f32))
    segmentSize = theme.sizeRule(context, StyleSegmentSize, initSize(0.0'f32, 20.0'f32))
    padding = theme.insetsRule(context, StylePadding, insets(0.0'f32, 12.0'f32))
    tabHeight = max(minSize.height, 0.0'f32)
  TabViewStyle(
    tabHeight: tabHeight,
    tabSegmentHeight: max(segmentSize.height, 0.0'f32),
    tabMinWidth: max(minSize.width, 0.0'f32),
    tabMaxWidth: max(maxSize.width, minSize.width),
    tabHorizontalPadding: max(padding.horizontal / 2.0'f32, 0.0'f32),
    tabInset: theme.lengthRule(context, StyleEdgeInset, 8.0'f32),
    tabGap: theme.lengthRule(context, StyleItemGap, 1.0'f32),
    contentBorderWidth: theme.lengthRule(panelContext, StyleBorderWidth, 1.0'f32),
    tabCornerRadius: theme.lengthRule(context, StyleCornerRadius, 4.0'f32),
    panelCornerRadius: theme.lengthRule(panelContext, StyleCornerRadius, 4.0'f32),
    panelOverlap: theme.lengthRule(context, StyleOverlap, tabHeight / 2.0'f32),
  )

proc resolveTextFieldStyle*(
    theme: Theme, context: StyleContext, textColor: Color
): TextFieldStyle =
  TextFieldStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(1.0, 1.0, 1.0, 1.0)),
      color(0.72, 0.75, 0.80, 1.0),
      cornerRadiusFallback = 6.0,
    ),
    text: theme.resolveTextStyle(context, textColor, insets(0.0, 6.0)),
    selectionColor:
      theme.colorRule(context, StyleSelectionColor, color(0.22, 0.46, 0.84, 0.32)),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(80.0, 24.0)),
  )

proc resolveTextFieldStyle*(theme: Theme, context: StyleContext): TextFieldStyle =
  theme.resolveTextFieldStyle(context, color(0.08, 0.09, 0.11, 1.0))

proc resolveMonoTextStyle*(theme: Theme, context: StyleContext): MonoTextStyle =
  MonoTextStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(0.98, 0.985, 0.995, 1.0)),
      color(0.72, 0.75, 0.80, 1.0),
      cornerRadiusFallback = 6.0,
    ),
    text: theme.resolveTextStyle(context, color(0.08, 0.09, 0.11, 1.0), insets(6.0)),
    cursorColor:
      theme.colorRule(context, StyleCursorColor, color(0.08, 0.45, 0.95, 0.45)),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(80.0, 24.0)),
    chrome: theme.resolveChromeName(context),
  )

proc resolveComboBoxStyle*(theme: Theme, context: StyleContext): ComboBoxStyle =
  ComboBoxStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(1.0, 1.0, 1.0, 1.0)),
      color(0.72, 0.75, 0.80, 1.0),
      cornerRadiusFallback = 6.0,
    ),
    text:
      theme.resolveTextStyle(context, color(0.08, 0.09, 0.11, 1.0), insets(0.0, 8.0)),
    arrowWidth: theme.lengthRule(context, StyleIndicatorSize, 24.0),
    arrowFill: theme.fillRule(
      context,
      StyleIndicatorFill,
      theme.fillRule(context, StyleFill, fill(color(1.0, 1.0, 1.0, 1.0))),
    ),
    arrowColor: theme.colorRule(context, StyleMarkColor, color(0.20, 0.22, 0.26, 1.0)),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(90.0, 24.0)),
    chrome: theme.resolveChromeName(context),
  )

proc resolveTableViewStyle*(theme: Theme, context: StyleContext): TableViewStyle =
  TableViewStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(1.0, 1.0, 1.0, 1.0)),
      color(0.72, 0.75, 0.80, 1.0),
      cornerRadiusFallback = 6.0,
    ),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(120.0, 24.0)),
    rowHeight: theme.lengthRule(context, StyleRowHeight, 22.0'f32),
    headerHeight: theme.lengthRule(context, StyleHeaderHeight, 24.0'f32),
    columnWidth: theme.lengthRule(context, StyleColumnWidth, 120.0'f32),
    columnMinWidth: theme.lengthRule(context, StyleColumnMinWidth, 24.0'f32),
    columnMaxWidth: theme.lengthRule(context, StyleColumnMaxWidth, 10000.0'f32),
    headerResizeHandleWidth: theme.lengthRule(context, StyleResizeHandleWidth, 5.0'f32),
    headerDragThreshold: theme.lengthRule(context, StyleDragThreshold, 3.0'f32),
    headerAutoscrollEdge: theme.lengthRule(context, StyleAutoscrollEdge, 18.0'f32),
  )

proc resolveSplitViewStyle*(theme: Theme, context: StyleContext): SplitViewStyle =
  SplitViewStyle(
    divider: theme.resolveControlBoxStyle(
      context,
      fill(color(0.84, 0.86, 0.90, 1.0)),
      color(0.58, 0.62, 0.68, 1.0),
      borderWidthFallback = 1.0,
      cornerRadiusFallback = 2.0,
      focusRingWidthFallback = 0.0,
      focusRingInsetFallback = 0.0,
      focusRingColorFallback = color(0.0, 0.0, 0.0, 0.0),
    ),
    dividerThickness: theme.lengthRule(context, StyleSeparatorThickness, 6.0'f32),
  )

proc resolveRowItemStyle*(theme: Theme, context: StyleContext): RowItemStyle =
  RowItemStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(1.0, 1.0, 1.0, 1.0)),
      color(0.0, 0.0, 0.0, 0.0),
      borderWidthFallback = 0.0,
      cornerRadiusFallback = 0.0,
      focusRingWidthFallback = 0.0,
      focusRingInsetFallback = 0.0,
      focusRingColorFallback = color(0.0, 0.0, 0.0, 0.0),
    ),
    text:
      theme.resolveTextStyle(context, color(0.08, 0.09, 0.11, 1.0), insets(0.0, 6.0)),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(0.0, 22.0)),
  )

proc resolveBoxStyle*(theme: Theme, context: StyleContext): BoxStyle =
  BoxStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(0.0, 0.0, 0.0, 0.0)),
      color(0.60, 0.64, 0.70, 1.0),
      borderWidthFallback = 1.0,
      cornerRadiusFallback = 4.0,
      focusRingWidthFallback = 0.0,
      focusRingInsetFallback = 0.0,
      focusRingColorFallback = color(0.0, 0.0, 0.0, 0.0),
    ),
    text:
      theme.resolveTextStyle(context, color(0.12, 0.14, 0.18, 1.0), insets(0.0, 8.0)),
    contentInsets: theme.insetsRule(context, StylePadding, insets(14.0, 12.0)),
    titleHeight: theme.lengthRule(context, StyleTitleHeight, 18.0'f32),
    titleGap: theme.lengthRule(context, StyleTitleGap, 4.0'f32),
    separatorThickness: theme.lengthRule(context, StyleSeparatorThickness, 1.0'f32),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(0.0, 0.0)),
  )

proc resolveScrollViewStyle*(
    appearance: Appearance, context: StyleContext
): ScrollViewStyle =
  appearance.theme.resolveScrollViewStyle(context)

proc resolveButtonStyle*(appearance: Appearance, context: StyleContext): ButtonStyle =
  appearance.theme.resolveButtonStyle(context)

proc resolveChoiceButtonStyle*(
    appearance: Appearance, context: StyleContext
): ChoiceButtonStyle =
  appearance.theme.resolveChoiceButtonStyle(context)

proc resolveSwitchButtonStyle*(
    appearance: Appearance, context: StyleContext
): SwitchButtonStyle =
  appearance.theme.resolveSwitchButtonStyle(context)

proc resolveSliderStyle*(appearance: Appearance, context: StyleContext): SliderStyle =
  appearance.theme.resolveSliderStyle(context)

proc resolveProgressIndicatorStyle*(
    appearance: Appearance, context: StyleContext
): SliderStyle =
  appearance.theme.resolveProgressIndicatorStyle(context)

proc resolveTabViewStyle*(appearance: Appearance, context: StyleContext): TabViewStyle =
  appearance.theme.resolveTabViewStyle(context)

proc resolveTextFieldStyle*(
    appearance: Appearance, context: StyleContext, textColor: Color
): TextFieldStyle =
  appearance.theme.resolveTextFieldStyle(context, textColor)

proc resolveTextFieldStyle*(
    appearance: Appearance, context: StyleContext
): TextFieldStyle =
  appearance.theme.resolveTextFieldStyle(context)

proc resolveMonoTextStyle*(
    appearance: Appearance, context: StyleContext
): MonoTextStyle =
  appearance.theme.resolveMonoTextStyle(context)

proc resolveComboBoxStyle*(
    appearance: Appearance, context: StyleContext
): ComboBoxStyle =
  appearance.theme.resolveComboBoxStyle(context)

proc resolveTableViewStyle*(
    appearance: Appearance, context: StyleContext
): TableViewStyle =
  appearance.theme.resolveTableViewStyle(context)

proc resolveSplitViewStyle*(
    appearance: Appearance, context: StyleContext
): SplitViewStyle =
  appearance.theme.resolveSplitViewStyle(context)

proc resolveRowItemStyle*(appearance: Appearance, context: StyleContext): RowItemStyle =
  appearance.theme.resolveRowItemStyle(context)

proc resolveBoxStyle*(appearance: Appearance, context: StyleContext): BoxStyle =
  appearance.theme.resolveBoxStyle(context)

func buttonTextRect*(style: ButtonStyle, bounds: Rect): Rect =
  bounds.inset(style.text.insets)

func choiceIndicatorRect*(style: ChoiceButtonStyle, bounds: Rect): Rect =
  let
    size = max(style.indicatorSize, 0.0'f32)
    x = bounds.origin.x + style.text.insets.left
    y = bounds.origin.y + max((bounds.size.height - size) / 2.0'f32, 0.0'f32)
  rect(x, y, size, size)

func choiceTextRect*(style: ChoiceButtonStyle, bounds: Rect): Rect =
  let indicator = style.choiceIndicatorRect(bounds)
  rect(
    indicator.maxX + style.indicatorSpacing,
    bounds.origin.y + style.text.insets.top,
    bounds.size.width - style.text.insets.left - style.text.insets.right -
      style.indicatorSize - style.indicatorSpacing,
    bounds.size.height - style.text.insets.top - style.text.insets.bottom,
  )

func textFieldTextRect*(style: TextFieldStyle, bounds: Rect): Rect =
  bounds.inset(style.text.insets)

func comboBoxArrowRect*(style: ComboBoxStyle, bounds: Rect): Rect =
  let arrowWidth = min(max(style.arrowWidth, 0.0'f32), bounds.size.width)
  rect(bounds.maxX - arrowWidth, bounds.origin.y, arrowWidth, bounds.size.height)

func comboBoxTextRect*(style: ComboBoxStyle, bounds: Rect): Rect =
  let
    arrow = style.comboBoxArrowRect(bounds)
    insets = style.text.insets
  rect(
    bounds.origin.x + insets.left,
    bounds.origin.y + insets.top,
    max(bounds.size.width - insets.left - insets.right - arrow.size.width, 0.0'f32),
    max(bounds.size.height - insets.top - insets.bottom, 0.0'f32),
  )

func rowItemTextRect*(style: RowItemStyle, bounds: Rect): Rect =
  bounds.inset(style.text.insets)

func boxTitleBandHeight*(
    style: BoxStyle, hasTitle: bool, titleHeight = 0.0'f32
): float32 =
  if not hasTitle:
    0.0'f32
  else:
    max(style.titleHeight, titleHeight) + max(style.titleGap, 0.0'f32)

func controlChromeOutset*(box: ControlBoxStyle): float32 =
  max(-box.focusRingInset, 0.0'f32)

func boxContentRect*(
    style: BoxStyle, bounds: Rect, hasTitle: bool, titleHeight = 0.0'f32
): Rect =
  let chromeEdge = style.box.borderWidth + style.box.controlChromeOutset()
  result = bounds.inset(style.contentInsets)
  result.x += chromeEdge
  result.w = max(result.w - chromeEdge * 2.0'f32, 0.0'f32)
  let titleBand = style.boxTitleBandHeight(hasTitle, titleHeight)
  result.y += titleBand + chromeEdge
  result.h = max(result.h - titleBand - chromeEdge * 2.0'f32, 0.0'f32)

func controlChromeWidth*(box: ControlBoxStyle): float32 =
  box.borderWidth * 2.0'f32 + box.controlChromeOutset() * 2.0'f32

func controlChromeHeight*(box: ControlBoxStyle): float32 =
  box.controlChromeWidth()

func controlSizeWithChrome*(
    contentSize: Size, insets: EdgeInsets, box: ControlBoxStyle, minSize: Size
): Size =
  initSize(
    max(minSize.width, contentSize.width + insets.horizontal + box.controlChromeWidth()),
    max(
      minSize.height, contentSize.height + insets.vertical + box.controlChromeHeight()
    ),
  )

func boxControlSize*(
    style: BoxStyle, contentSize, titleSize: Size, hasTitle: bool
): Size =
  initSize(
    max(
      style.minSize.width,
      max(
        contentSize.width,
        if hasTitle:
          titleSize.width + style.text.insets.horizontal
        else:
          0.0'f32,
      ) + style.contentInsets.horizontal + style.box.controlChromeWidth(),
    ),
    max(
      style.minSize.height,
      contentSize.height + style.contentInsets.vertical +
        style.boxTitleBandHeight(hasTitle, titleSize.height) +
        style.box.controlChromeHeight(),
    ),
  )

func buttonControlSize*(style: ButtonStyle, titleSize: Size): Size =
  controlSizeWithChrome(titleSize, style.text.insets, style.box, style.minSize)

func choiceControlSize*(style: ChoiceButtonStyle, titleSize: Size): Size =
  let
    indicatorChrome = style.indicator.controlChromeWidth()
    indicatorWidth = style.indicatorSize + indicatorChrome
    indicatorHeight = style.indicatorSize + style.indicator.controlChromeHeight()
    contentWidth = indicatorWidth + style.indicatorSpacing + titleSize.width
    contentHeight = max(indicatorHeight, titleSize.height)
  controlSizeWithChrome(
    initSize(contentWidth, contentHeight),
    style.text.insets,
    style.indicator,
    style.minSize,
  )

func textFieldControlSize*(style: TextFieldStyle, textSize: Size): Size =
  controlSizeWithChrome(textSize, style.text.insets, style.box, style.minSize)

func comboBoxControlSize*(style: ComboBoxStyle, textSize: Size): Size =
  let contentSize = initSize(textSize.width + style.arrowWidth, textSize.height)
  controlSizeWithChrome(contentSize, style.text.insets, style.box, style.minSize)
