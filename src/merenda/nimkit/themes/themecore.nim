import std/[atomics, math, sets, strutils, tables]

import figdraw
from sigils/selectors import DynamicAgent

import ../foundation/types
import ./private/cssproperties

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

  StyleTokenStore* = ref object
    parent*: StyleTokenStore
    values*: Table[string, StyleValue]

  StyleKey*[T] = distinct string

  StylePatch* = ref object
    values*: Table[string, StyleValue]

  LayoutStyleSelection* = object
    ## A borrowed declaration in an immutable theme, counted before list copying.
    patch: StylePatch
    tokens: StyleTokenStore
    key: string
    scalar: StyleLayoutConstraint
    hasScalar: bool

  StyleRule* = object
    selector*: StyleSelector
    patch*: StylePatch
    origin*: StyleRuleOrigin
    important*: bool
    cssSpecificity*: array[3, int]
    sourceOrder*: int
    line*, column*: int

  StyleRuleOrigin* = enum
    sroTheme
    sroCss
    sroOverride

  Chrome* = ref object of DynamicAgent

  ThemeGeneration* = distinct uint64

  Theme* = object
    xTokens: StyleTokenStore
    xRules: seq[StyleRule]
    xChromes: Table[string, Chrome]
    xRulesByRole: array[StyleRole, seq[int]]
    xGeneration: ThemeGeneration
    xHasCss: bool
    xCssMetricStates: set[WidgetState]
    xCssImportantTokens: HashSet[string]
    xNativeCssTokens: HashSet[string]
    xCssSourceOrder: int
    xHasLayoutRules: bool

  ThemeBuilder* = object
    xTokens: StyleTokenStore
    xRules: seq[StyleRule]
    xChromes: Table[string, Chrome]
    xBaseGeneration: ThemeGeneration
    xChanged: bool
    xHasCss: bool
    xCssImportantTokens: HashSet[string]
    xNativeCssTokens: HashSet[string]
    xCssSourceOrder: int

  Appearance* = object
    theme*: Theme

  FontFaceSet* = object ## Exact local faces for the common styles in one font family.
    regular*: SystemTypeface
    italic*: SystemTypeface
    bold*: SystemTypeface
    boldItalic*: SystemTypeface

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
    fontFace*: SystemTypeface
    italicFontFace*: SystemTypeface
    boldFontFace*: SystemTypeface
    boldItalicFontFace*: SystemTypeface
    fontSize*: float32
    fontSlant*: FontSlant
    language*: LanguageTag

  TooltipStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    padding*: EdgeInsets

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
    activeTrackMaximumFill*: Fill
    knob*: ControlBoxStyle
    knobValueTint*: float32
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

  ThemeInstaller* = proc(builder: var ThemeBuilder)

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
    gripColor*: Color
    gripLength*: float32

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

var
  themeInstallers: seq[ThemeInstaller]
  themeGenerationCounter: Atomic[uint64]

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

proc cloneText(value: string): string =
  result = newStringOfCap(value.len)
  result.add value

proc clone(value: StyleValue): StyleValue =
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

proc clone(selector: StyleSelector): StyleSelector =
  result.role = selector.role
  result.states = selector.states
  result.id = selector.id.cloneText
  for className in selector.classes:
    result.classes.add className.cloneText

proc cloneRules(rules: openArray[StyleRule]): seq[StyleRule] =
  for rule in rules:
    var copied = rule
    copied.selector = rule.selector.clone
    copied.patch = rule.patch.clone
    result.add copied

proc cloneChromes(chromes: Table[string, Chrome]): Table[string, Chrome] =
  result = initTable[string, Chrome]()
  for name, chrome in chromes:
    result[name.cloneText] = chrome

proc clone*(theme: Theme): Theme =
  ## Immutable theme snapshots can be copied without changing their generation.
  theme

proc tokens*(theme: Theme): StyleTokenStore =
  ## Returns a mutable copy of the snapshot's token store.
  theme.xTokens.clone

proc rules*(theme: Theme): seq[StyleRule] =
  ## Returns a mutable copy of the snapshot's style rules.
  theme.xRules.cloneRules()

proc chromes*(theme: Theme): Table[string, Chrome] =
  ## Returns a value copy of the snapshot's chrome registry.
  theme.xChromes.cloneChromes

func generation*(theme: Theme): ThemeGeneration =
  theme.xGeneration

func `==`*(left, right: ThemeGeneration): bool =
  uint64(left) == uint64(right)

func isInitialized*(theme: Theme): bool =
  not theme.xTokens.isNil

proc nextThemeGeneration(): ThemeGeneration =
  ThemeGeneration(themeGenerationCounter.fetchAdd(1'u64, moRelaxed) + 1'u64)

proc initThemeBuilder*(): ThemeBuilder =
  ## Creates a builder for a new immutable theme snapshot.
  ThemeBuilder(
    xTokens: newStyleTokenStore(), xChromes: initTable[string, Chrome](), xChanged: true
  )

proc initThemeBuilder*(tokens: StyleTokenStore): ThemeBuilder =
  ## Creates a builder initialized with an isolated copy of `tokens`.
  result = initThemeBuilder()
  result.xTokens = tokens.clone

proc initThemeBuilder*(theme: Theme): ThemeBuilder =
  ## Creates an isolated builder initialized from an immutable snapshot.
  ThemeBuilder(
    xTokens: theme.xTokens.clone,
    xRules: theme.xRules.cloneRules(),
    xChromes: theme.xChromes.cloneChromes,
    xBaseGeneration: theme.xGeneration,
    xHasCss: theme.xHasCss,
    xCssImportantTokens: theme.xCssImportantTokens,
    xNativeCssTokens: theme.xNativeCssTokens,
    xCssSourceOrder: theme.xCssSourceOrder,
  )

proc finish*(builder: ThemeBuilder): Theme =
  ## Freezes the builder into an immutable, independently owned snapshot.
  result.xTokens = builder.xTokens.clone
  result.xRules = builder.xRules.cloneRules()
  result.xChromes = builder.xChromes.cloneChromes
  result.xHasCss = builder.xHasCss
  result.xCssImportantTokens = builder.xCssImportantTokens
  result.xNativeCssTokens = builder.xNativeCssTokens
  result.xCssSourceOrder = builder.xCssSourceOrder
  for index, rule in result.xRules:
    result.xRulesByRole[rule.selector.role].add index
    for key in rule.patch.values.keys:
      if key.startsWith("layout."):
        result.xHasLayoutRules = true
      if key.startsWith("layout.") or key.startsWith("container."):
        result.xCssMetricStates = result.xCssMetricStates + rule.selector.states
    if rule.origin == sroCss:
      for key in rule.patch.values.keys:
        var spec: CssPropertySpec
        if key.startsWith("font.") or key.startsWith("layout.") or
            (cssPropertyByKey(key, spec) and spec.metric) or
            key in [
              "text.insets", "padding", "minimum.size", "border.width", "chrome",
              "focus.ring.inset",
            ]:
          result.xCssMetricStates = result.xCssMetricStates + rule.selector.states
  if ssPressed in result.xCssMetricStates:
    result.xCssMetricStates.incl ssHighlighted
  if builder.xChanged or builder.xBaseGeneration == ThemeGeneration(0):
    result.xGeneration = nextThemeGeneration()
  else:
    result.xGeneration = builder.xBaseGeneration

proc noteThemeMutation(builder: var ThemeBuilder) =
  builder.xChanged = true

func sameAppearanceGeneration*(left, right: Appearance): bool =
  ## Compare immutable cache snapshots without traversing every theme value.
  left.theme.xGeneration == right.theme.xGeneration

proc registerThemeInstaller*(installer: ThemeInstaller) =
  themeInstallers.add installer

proc installThemeExtensions*(theme: var ThemeBuilder) =
  for installer in themeInstallers:
    installer(theme)

proc installChrome*(theme: var ThemeBuilder, name: string, chrome: Chrome) =
  if name.len == 0:
    return
  if chrome.isNil:
    if name in theme.xChromes:
      theme.xChromes.del(name)
      theme.noteThemeMutation()
  else:
    if name in theme.xChromes and theme.xChromes[name] == chrome:
      return
    theme.xChromes[name] = chrome
    theme.noteThemeMutation()

proc hasChrome*(theme: Theme, name: string): bool =
  name in theme.xChromes

proc chrome*(theme: Theme, name: string): Chrome =
  if name in theme.xChromes:
    return theme.xChromes[name]

proc installChrome*(appearance: var Appearance, name: string, chrome: Chrome) =
  var builder = initThemeBuilder(appearance.theme)
  builder.installChrome(name, chrome)
  appearance.theme = builder.finish()

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

proc `[]=`*(theme: var ThemeBuilder, name: string, value: StyleValue) =
  theme.xTokens[name] = value
  if theme.xHasCss and name.startsWith("--"):
    theme.xNativeCssTokens.incl name
  theme.noteThemeMutation()

proc setCssToken*(
    theme: var ThemeBuilder, name: string, value: StyleValue, important = false
) =
  ## Compiler hook: preserves custom-property importance across stylesheet appends.
  if name in theme.xNativeCssTokens or
      (name in theme.xCssImportantTokens and not important):
    return
  theme.xTokens[name] = value
  theme.xHasCss = true
  if important:
    theme.xCssImportantTokens.incl name
  theme.noteThemeMutation()

func hasCss*(theme: Theme): bool =
  ## Whether this snapshot contains CSS declarations or root custom properties.
  theme.xHasCss

func hasLayoutRules*(theme: Theme): bool =
  ## Whether the snapshot contains native or CSS constraint specifications.
  theme.xHasLayoutRules

func cssMetricStates*(theme: Theme): set[WidgetState] =
  ## States whose CSS declarations can change intrinsic content metrics.
  theme.xCssMetricStates

func cssMetricsChange*(theme: Theme, states: set[WidgetState]): bool =
  (theme.xCssMetricStates * states) != {}

proc `[]=`*(theme: var ThemeBuilder, name: string, value: Color) =
  theme[name] = styleColor(value)

proc `[]=`*(theme: var ThemeBuilder, name: string, value: Fill) =
  theme[name] = styleFill(value)

proc `[]=`*(theme: var ThemeBuilder, name: string, value: float32) =
  theme[name] = styleLength(value)

proc `[]=`*(theme: var ThemeBuilder, name: string, value: float) =
  theme[name] = styleLength(value.float32)

proc `[]=`*(theme: var ThemeBuilder, name: string, value: Size) =
  theme[name] = styleSize(value)

proc `[]=`*(theme: var ThemeBuilder, name: string, value: EdgeInsets) =
  theme[name] = styleInsets(value)

proc `[]=`*(theme: var ThemeBuilder, name: string, value: openArray[BoxShadow]) =
  theme[name] = styleShadows(value)

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
  of srMenuBar: srTabPanel
  of srMenuBarItem: srTab
  of srDocumentTab, srDocumentTabButton: srTab
  of srDocumentTabBar: srTabPanel
  else: role

proc stylePatch(theme: var ThemeBuilder, selector: StyleSelector): StylePatch =
  let origin = if theme.xHasCss: sroOverride else: sroTheme
  for rule in theme.xRules:
    if rule.selector == selector and rule.origin == origin:
      return rule.patch
  result = newStylePatch()
  theme.xRules.add StyleRule(selector: selector, patch: result, origin: origin)

func higherExactRule(left, right: StyleRule): bool =
  if left.origin != right.origin:
    return left.origin > right.origin
  if left.origin == sroCss:
    if left.important != right.important:
      return left.important
    for index in 0 .. 2:
      if left.cssSpecificity[index] != right.cssSpecificity[index]:
        return left.cssSpecificity[index] > right.cssSpecificity[index]
    return left.sourceOrder >= right.sourceOrder

proc exactStylePatch(
    rules: openArray[StyleRule], selector: StyleSelector, hasCss: bool
): StylePatch =
  if not hasCss:
    for rule in rules:
      if rule.selector == selector:
        return rule.patch
  else:
    var best: Table[string, int]
    for index, rule in rules:
      if rule.selector == selector:
        if result.isNil:
          result = newStylePatch()
        for key, value in rule.patch.values:
          if key notin best or rule.higherExactRule(rules[best[key]]):
            result.values[key] = value
            best[key] = index

proc stylePatchView(theme: Theme, selector: StyleSelector): StylePatch =
  exactStylePatch(theme.xRules, selector, theme.xHasCss)

proc stylePatch*(theme: Theme, selector: StyleSelector): StylePatch =
  ## Returns a mutable copy without exposing snapshot-owned storage.
  theme.stylePatchView(selector).clone

proc addRule*(theme: var ThemeBuilder, selector: StyleSelector, patch: StylePatch) =
  theme.xRules.add StyleRule(
    selector: selector,
    patch: patch,
    origin: (if theme.xHasCss: sroOverride else: sroTheme),
  )
  theme.noteThemeMutation()

proc nextCssSourceOrder*(theme: var ThemeBuilder): int =
  ## Compiler hook: one source-order value for an expanded CSS declaration.
  inc theme.xCssSourceOrder
  theme.xCssSourceOrder

proc addCssRule*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    patch: StylePatch,
    specificity: array[3, int],
    sourceOrder: int,
    important = false,
    line = 1,
    column = 1,
) =
  ## Compiler hook: adds a CSS declaration without merging identical selectors.
  theme.xRules.add StyleRule(
    selector: selector,
    patch: patch,
    origin: sroCss,
    important: important,
    cssSpecificity: specificity,
    sourceOrder: sourceOrder,
    line: line,
    column: column,
  )
  theme.xHasCss = true
  theme.noteThemeMutation()

proc setStyle*[T](
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*(
    theme: var ThemeBuilder, selector: StyleSelector, key: string, value: StyleValue
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*(
    theme: var ThemeBuilder, selector: StyleSelector, key: StyleKey[Color], value: Color
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*(
    theme: var ThemeBuilder, selector: StyleSelector, key: StyleKey[Fill], value: Fill
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float32,
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float,
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*(
    theme: var ThemeBuilder, selector: StyleSelector, key: StyleKey[Size], value: Size
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.stylePatch(selector).setStyle(key, value)
  theme.noteThemeMutation()

proc setStyle*[T](
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[Color], value: Color
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[Fill], value: Fill
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[float32], value: float32
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[float32], value: float
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[Size], value: Size
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*[T](
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc `[]=`*[T](
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var ThemeBuilder, selector: StyleSelector, key: StyleKey[Color], value: Color
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var ThemeBuilder, selector: StyleSelector, key: StyleKey[Fill], value: Fill
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float32,
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float,
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var ThemeBuilder, selector: StyleSelector, key: StyleKey[Size], value: Size
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(selector, key, value)

proc `[]=`*[T](
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[Color], value: Color
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[Fill], value: Fill
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[float32], value: float32
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[float32], value: float
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var ThemeBuilder, role: StyleRole, key: StyleKey[Size], value: Size
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(role, key, value)

proc `[]=`*[T](
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var ThemeBuilder,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(role, states, key, value)

proc `[]`*[T](theme: Theme, role: StyleRole, key: StyleKey[T]): StyleValue =
  let patch = theme.stylePatchView(initStyleSelector(role))
  if patch.isNil or not patch.getStyle(key, result):
    result = missingStyleValue()

proc `[]`*[T](theme: ThemeBuilder, role: StyleRole, key: StyleKey[T]): StyleValue =
  let patch = exactStylePatch(theme.xRules, initStyleSelector(role), theme.xHasCss)
  if patch.isNil or not patch.getStyle(key, result):
    result = missingStyleValue()

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

proc resolveCssValue*(
    theme: Theme, value: StyleValue, key: string, resolved: var StyleValue
): bool =
  ## Compiler/resolver hook for bounded typed CSS variables and shorthand coercion.
  if not theme.xTokens.resolveValue(value, resolved):
    return
  var geometry: CssGeometryProperty
  if cssGeometryByKey(key, geometry):
    if value.kind == svToken and resolved.kind == svConstraints:
      return
    if resolved.kind == svLength:
      if resolved.length.classify in {fcNan, fcInf, fcNegInf} or
          (not geometry.edge and resolved.length < 0):
        return
      var constraint = StyleLayoutConstraint(
        attribute: geometry.attribute,
        relation: geometry.relation,
        constant: resolved.length,
        priority: geometry.priority,
      )
      if geometry.edge:
        constraint.target = sltParent
        constraint.targetAttribute = geometry.attribute
        if geometry.attribute in {atRight, atBottom}:
          constraint.constant = -constraint.constant
      resolved = styleConstraints([constraint])
    if resolved.kind != svConstraints:
      return
    for constraint in resolved.constraints:
      if not constraint.validStyleConstraint:
        return
    result = true
    return
  if key == StyleLayoutConstraints.keyName:
    if resolved.kind != svConstraints:
      return
    for constraint in resolved.constraints:
      if not constraint.validStyleConstraint:
        return
    return true
  var spec: CssPropertySpec
  if cssPropertyByKey(key, spec):
    case spec.kind
    of cpkColor:
      return resolved.kind == svColor
    of cpkFill:
      return resolved.kind in {svColor, svFill}
    of cpkLength:
      return
        resolved.kind == svLength and
        resolved.length.classify notin {fcNan, fcInf, fcNegInf} and
        resolved.length >= spec.minimum and resolved.length <= spec.maximum
    of cpkSize:
      if resolved.kind == svLength:
        resolved = styleSize(initSize(resolved.length, resolved.length))
      return
        resolved.kind == svSize and
        resolved.size.width.classify notin {fcNan, fcInf, fcNegInf} and
        resolved.size.height.classify notin {fcNan, fcInf, fcNegInf} and
        resolved.size.width >= 0 and resolved.size.height >= 0
    of cpkInsets:
      if resolved.kind == svLength:
        resolved = styleInsets(insets(resolved.length))
      if resolved.kind != svInsets:
        return
      for amount in [
        resolved.insets.top, resolved.insets.right, resolved.insets.bottom,
        resolved.insets.left,
      ]:
        if amount.classify in {fcNan, fcInf, fcNegInf} or amount < 0:
          return
      return true
    of cpkShadows:
      return resolved.kind == svShadows
    of cpkKeyword:
      if resolved.kind != svKeyword or resolved.keyword.len == 0:
        return
      if spec.keywords.len > 0:
        resolved = styleKeyword(resolved.keyword.toLowerAscii())
        return resolved.keyword in spec.keywords.split('|')
      return true
  case key
  of "text.color", "border.color", "focus.ring.color":
    result = resolved.kind == svColor
  of "fill", "background.fill":
    result = resolved.kind in {svColor, svFill}
  of "font.name", "chrome":
    result = resolved.kind == svKeyword and resolved.keyword.len > 0
  of "font.slant":
    result =
      resolved.kind == svKeyword and resolved.keyword in ["normal", "italic", "oblique"]
  of "font.face", "font.face.italic", "font.face.bold", "font.face.boldItalic":
    result = resolved.kind == svFontFace
  of "text.insets", "padding":
    if resolved.kind == svLength:
      resolved = styleInsets(insets(resolved.length))
    if resolved.kind == svInsets:
      result = true
      for amount in [
        resolved.insets.top, resolved.insets.right, resolved.insets.bottom,
        resolved.insets.left,
      ]:
        if amount.classify in {fcNan, fcInf, fcNegInf} or amount < 0:
          return false
  of "minimum.size":
    if resolved.kind == svSize:
      result = resolved.size.width >= 0 and resolved.size.height >= 0
  of "box.shadows":
    result = resolved.kind == svShadows
  else:
    if resolved.kind == svLength:
      let amount = resolved.length
      result =
        amount.classify notin {fcNan, fcInf, fcNegInf} and
        (amount >= 0 or key == "focus.ring.inset")

func rankAtLeast(left, right: array[7, int]): bool =
  for index in 0 .. left.high:
    if left[index] != right[index]:
      return left[index] > right[index]
  true

proc validCssPatch(theme: Theme, patch: StylePatch): bool =
  for key, value in patch.values:
    var resolved: StyleValue
    if not theme.resolveCssValue(value, key, resolved):
      return
  true

proc ruleValue(
    theme: Theme, context: StyleContext, key: string, fallback: StyleValue
): StyleValue =
  result = fallback
  var
    bestRank = [-1, -1, -1, -1, -1, -1, -1]
    inheritedContext = context
  let inheritedRole = context.role.inheritedStyleRole()
  inheritedContext.role = inheritedRole

  template applyRule(rule: StyleRule, matchContext: StyleContext, roleRank: int) =
    block:
      var value: StyleValue
      if rule.selector.matches(matchContext) and rule.patch.getStyle(key, value):
        let rank =
          if rule.origin == sroCss:
            [
              ord(rule.origin),
              ord(rule.important),
              rule.cssSpecificity[0],
              rule.cssSpecificity[1],
              rule.cssSpecificity[2],
              rule.sourceOrder,
              roleRank,
            ]
          else:
            [
              ord(rule.origin),
              0,
              0,
              0,
              0,
              rule.selector.specificity() * 10 + roleRank,
              0,
            ]
        if rank.rankAtLeast(bestRank):
          var resolved: StyleValue
          if rule.origin == sroCss:
            if theme.validCssPatch(rule.patch) and
                theme.resolveCssValue(value, key, resolved):
              result = resolved
              bestRank = rank
          elif theme.xTokens.resolveValue(value, resolved):
            result = resolved
            bestRank = rank
          elif value.kind != svToken:
            result = value
            bestRank = rank

  if inheritedRole != context.role:
    for ruleIndex in theme.xRulesByRole[inheritedRole]:
      applyRule(theme.xRules[ruleIndex], inheritedContext, 0)
  for ruleIndex in theme.xRulesByRole[context.role]:
    applyRule(theme.xRules[ruleIndex], context, 1)

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

proc fontFaceRule(
    theme: Theme,
    context: StyleContext,
    key: StyleKey[SystemTypeface],
    fallback: SystemTypeface,
): SystemTypeface =
  let value = theme.ruleValue(context, key.keyName, styleFontFace(fallback))
  if value.kind == svFontFace: value.fontFace else: fallback

proc keywordRule(
    theme: Theme, context: StyleContext, key: StyleKey[string], fallback: string
): string =
  let value = theme.ruleValue(context, key.keyName, styleKeyword(fallback))
  if value.kind == svKeyword: value.keyword else: fallback

proc styleValue*(theme: Theme, name: string, fallback: StyleValue): StyleValue =
  if theme.xTokens.isNil:
    return fallback
  if not theme.xTokens.resolveToken(name, result):
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

const
  UIFontNameToken* = "font.ui.name"
  MonospaceFontNameToken* = "font.monospace.name"
  UIFontFaceToken* = "font.ui.face"
  MonospaceFontFaceToken* = "font.monospace.face"
  UIFontItalicFaceToken* = "font.ui.face.italic"
  MonospaceFontItalicFaceToken* = "font.monospace.face.italic"
  UIFontBoldFaceToken* = "font.ui.face.bold"
  MonospaceFontBoldFaceToken* = "font.monospace.face.bold"
  UIFontBoldItalicFaceToken* = "font.ui.face.boldItalic"
  MonospaceFontBoldItalicFaceToken* = "font.monospace.face.boldItalic"

func fontNameToken(role: FontRole): string =
  case role
  of frUI: UIFontNameToken
  of frMonospace: MonospaceFontNameToken

func fontFaceToken(role: FontRole): string =
  case role
  of frUI: UIFontFaceToken
  of frMonospace: MonospaceFontFaceToken

func italicFontFaceToken(role: FontRole): string =
  case role
  of frUI: UIFontItalicFaceToken
  of frMonospace: MonospaceFontItalicFaceToken

func boldFontFaceToken(role: FontRole): string =
  case role
  of frUI: UIFontBoldFaceToken
  of frMonospace: MonospaceFontBoldFaceToken

func boldItalicFontFaceToken(role: FontRole): string =
  case role
  of frUI: UIFontBoldItalicFaceToken
  of frMonospace: MonospaceFontBoldItalicFaceToken

proc fontName*(theme: Theme, role: FontRole): string =
  ## Resolves a user-configurable font role from the theme token store.
  let value =
    theme.styleValue(role.fontNameToken(), styleKeyword(defaultFontName(role)))
  if value.kind == svKeyword:
    value.keyword
  else:
    defaultFontName(role)

proc setFontName*(theme: var ThemeBuilder, role: FontRole, name: string) =
  ## Sets a font role, or restores its environment/platform default when empty.
  let resolved =
    if name.len > 0:
      name
    else:
      defaultFontName(role)
  theme[role.fontNameToken()] = styleKeyword(resolved)

proc fontFace*(theme: Theme, role: FontRole): SystemTypeface =
  ## Resolves the exact local face selected for a user-configurable font role.
  let value = theme.styleValue(role.fontFaceToken(), styleFontFace(result))
  if value.kind == svFontFace:
    result = value.fontFace

proc fontFaces*(theme: Theme, role: FontRole): FontFaceSet =
  ## Resolves all exact local faces configured for a font role.
  result.regular = theme.fontFace(role)
  let
    italic = theme.styleValue(role.italicFontFaceToken(), styleFontFace(result.italic))
    bold = theme.styleValue(role.boldFontFaceToken(), styleFontFace(result.bold))
    boldItalic =
      theme.styleValue(role.boldItalicFontFaceToken(), styleFontFace(result.boldItalic))
  if italic.kind == svFontFace:
    result.italic = italic.fontFace
  if bold.kind == svFontFace:
    result.bold = bold.fontFace
  if boldItalic.kind == svFontFace:
    result.boldItalic = boldItalic.fontFace

proc setFontFaces*(theme: var ThemeBuilder, role: FontRole, fontFaces: FontFaceSet) =
  ## Sets the exact local faces for a user-configurable font role.
  theme[role.fontFaceToken()] = styleFontFace(fontFaces.regular)
  theme[role.italicFontFaceToken()] = styleFontFace(fontFaces.italic)
  theme[role.boldFontFaceToken()] = styleFontFace(fontFaces.bold)
  theme[role.boldItalicFontFaceToken()] = styleFontFace(fontFaces.boldItalic)

proc setFontFace*(theme: var ThemeBuilder, role: FontRole, fontFace: SystemTypeface) =
  ## Sets one face and clears styled alternatives; missing styles use this face.
  theme.setFontFaces(role, FontFaceSet(regular: fontFace))

proc fontName*(appearance: Appearance, role: FontRole): string =
  ## Resolves a user-configurable font role from an appearance.
  appearance.theme.fontName(role)

proc fontFace*(appearance: Appearance, role: FontRole): SystemTypeface =
  ## Resolves the exact local face selected for a user-configurable font role.
  appearance.theme.fontFace(role)

proc fontFaces*(appearance: Appearance, role: FontRole): FontFaceSet =
  ## Resolves all exact local faces configured for a font role.
  appearance.theme.fontFaces(role)

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

proc resolveKeyword*(
    theme: Theme, context: StyleContext, key: StyleKey[string], fallback: string
): string =
  theme.keywordRule(context, key, fallback)

proc resolveKeyword*(
    appearance: Appearance,
    context: StyleContext,
    key: StyleKey[string],
    fallback: string,
): string =
  appearance.theme.resolveKeyword(context, key, fallback)

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

proc layoutStyleSelection*(
    theme: Theme,
    context: StyleContext,
    key = StyleLayoutConstraints,
    checkWork: proc() {.closure.} = nil,
): LayoutStyleSelection =
  ## Selects layout data without cloning a constraint list. Optional work checks
  ## let layout solvers enforce a deadline while scanning declarations/tokens.
  var
    bestRank = [-1, -1, -1, -1, -1, -1, -1]
    inheritedContext = context
  let name = key.keyName
  let inheritedRole = context.role.inheritedStyleRole()
  inheritedContext.role = inheritedRole

  template checkSelectionWork() =
    if not checkWork.isNil:
      checkWork()

  template applyLayoutRule(rule: StyleRule, matchContext: StyleContext, roleRank: int) =
    block:
      checkSelectionWork()
      if rule.selector.matches(matchContext) and rule.patch.values.hasKey(name):
        let rank =
          if rule.origin == sroCss:
            [
              ord(rule.origin),
              ord(rule.important),
              rule.cssSpecificity[0],
              rule.cssSpecificity[1],
              rule.cssSpecificity[2],
              rule.sourceOrder,
              roleRank,
            ]
          else:
            [
              ord(rule.origin),
              0,
              0,
              0,
              0,
              rule.selector.specificity() * 10 + roleRank,
              0,
            ]
        if rank.rankAtLeast(bestRank):
          var candidate: LayoutStyleSelection
          if rule.patch.values[name].kind == svConstraints:
            # CSS literal lists were validated atomically during compilation.
            # Native list entries are checked individually by the solver.
            candidate = LayoutStyleSelection(patch: rule.patch, key: name)
          else:
            var listToken = false
            if rule.patch.values[name].kind == svToken:
              var tokenName = rule.patch.values[name].token
              for depth in 0 ..< 16:
                checkSelectionWork()
                var tokenStore = theme.xTokens
                while not tokenStore.isNil and not tokenStore.values.hasKey(tokenName):
                  checkSelectionWork()
                  tokenStore = tokenStore.parent
                if tokenStore.isNil:
                  break
                if tokenStore.values[tokenName].kind == svConstraints:
                  listToken = true
                  if rule.origin != sroCss:
                    candidate = LayoutStyleSelection(tokens: tokenStore, key: tokenName)
                  break
                if tokenStore.values[tokenName].kind != svToken:
                  break
                tokenName = tokenStore.values[tokenName].token
            if candidate.tokens.isNil and not listToken:
              var scalar: StyleValue
              if theme.resolveCssValue(rule.patch.values[name], name, scalar) and
                  scalar.kind == svConstraints and scalar.constraints.len == 1:
                candidate =
                  LayoutStyleSelection(scalar: scalar.constraints[0], hasScalar: true)
          if not candidate.patch.isNil or not candidate.tokens.isNil or
              candidate.hasScalar:
            result = candidate
            bestRank = rank

  if inheritedRole != context.role:
    for index in theme.xRulesByRole[inheritedRole]:
      applyLayoutRule(theme.xRules[index], inheritedContext, 0)
  for index in theme.xRulesByRole[context.role]:
    applyLayoutRule(theme.xRules[index], context, 1)

func constraintCount*(selection: LayoutStyleSelection): Natural =
  ## Reads borrowed list metadata without copying or validating list entries.
  if not selection.patch.isNil:
    selection.patch.values[selection.key].constraints.len
  elif not selection.tokens.isNil:
    selection.tokens.values[selection.key].constraints.len
  elif selection.hasScalar:
    1
  else:
    0

proc resolveLayoutConstraints*(
    selection: LayoutStyleSelection, checkWork: proc() {.closure.} = nil
): seq[StyleLayoutConstraint] =
  ## Makes one independently owned copy after the caller checks list size.
  let count = selection.constraintCount
  result = newSeqOfCap[StyleLayoutConstraint](count)
  for index in 0 ..< count:
    if not checkWork.isNil:
      checkWork()
    var spec =
      if not selection.patch.isNil:
        selection.patch.values[selection.key].constraints[index]
      elif not selection.tokens.isNil:
        selection.tokens.values[selection.key].constraints[index]
      else:
        selection.scalar
    var id = newStringOfCap(spec.targetId.len)
    id.add spec.targetId
    spec.targetId = move id
    result.add spec

proc resolveLayoutConstraints*(
    theme: Theme, context: StyleContext, key = StyleLayoutConstraints
): seq[StyleLayoutConstraint] =
  ## Returns independently owned specifications from the winning declaration.
  theme.layoutStyleSelection(context, key).resolveLayoutConstraints()

proc resolveChromeName*(appearance: Appearance, context: StyleContext): string =
  appearance.theme.resolveChromeName(context)

proc resolveTextStyle*(
    theme: Theme,
    context: StyleContext,
    colorFallback: Color,
    insetsFallback: EdgeInsets,
): TextStyle =
  let fontSlant = theme.keywordRule(context, StyleFontSlant, "normal").fontSlant
  TextStyle(
    color: theme.colorRule(context, StyleTextColor, colorFallback),
    insets: theme.insetsRule(context, StyleTextInsets, insetsFallback),
    fontName: theme.keywordRule(context, StyleFontName, defaultFontName()),
    fontFace: theme.fontFaceRule(context, StyleFontFace, SystemTypeface()),
    italicFontFace: theme.fontFaceRule(context, StyleItalicFontFace, SystemTypeface()),
    boldFontFace: theme.fontFaceRule(context, StyleBoldFontFace, SystemTypeface()),
    boldItalicFontFace:
      theme.fontFaceRule(context, StyleBoldItalicFontFace, SystemTypeface()),
    fontSize: max(theme.lengthRule(context, StyleFontSize, defaultFontSize()), 1.0'f32),
    fontSlant: fontSlant,
    language:
      theme.keywordRule(context, StyleLanguage, $defaultLanguageTag()).initLanguageTag(),
  )

proc resolveTextStyle*(
    appearance: Appearance,
    context: StyleContext,
    colorFallback: Color,
    insetsFallback: EdgeInsets,
): TextStyle =
  appearance.theme.resolveTextStyle(context, colorFallback, insetsFallback)

template editAppearanceTheme(appearance: var Appearance, body: untyped) =
  block:
    var builder {.inject.} = initThemeBuilder(appearance.theme)
    body
    appearance.theme = builder.finish()

proc setStyle*[T](
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[T],
    value: StyleValue,
) =
  editAppearanceTheme(appearance):
    builder.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Color],
    value: Color,
) =
  editAppearanceTheme(appearance):
    builder.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Fill],
    value: Fill,
) =
  editAppearanceTheme(appearance):
    builder.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float32,
) =
  editAppearanceTheme(appearance):
    builder.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Size],
    value: Size,
) =
  editAppearanceTheme(appearance):
    builder.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float,
) =
  editAppearanceTheme(appearance):
    builder.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  editAppearanceTheme(appearance):
    builder.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  editAppearanceTheme(appearance):
    builder.setStyle(selector, key, value)

proc setStyle*[T](
    appearance: var Appearance, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  editAppearanceTheme(appearance):
    builder.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Color], value: Color
) =
  editAppearanceTheme(appearance):
    builder.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Fill], value: Fill
) =
  editAppearanceTheme(appearance):
    builder.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float32
) =
  editAppearanceTheme(appearance):
    builder.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float
) =
  editAppearanceTheme(appearance):
    builder.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Size], value: Size
) =
  editAppearanceTheme(appearance):
    builder.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  editAppearanceTheme(appearance):
    builder.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  editAppearanceTheme(appearance):
    builder.setStyle(role, key, value)

proc `[]=`*[T](
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[T],
    value: StyleValue,
) =
  editAppearanceTheme(appearance):
    builder[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Color],
    value: Color,
) =
  editAppearanceTheme(appearance):
    builder[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Fill],
    value: Fill,
) =
  editAppearanceTheme(appearance):
    builder[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float32,
) =
  editAppearanceTheme(appearance):
    builder[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float,
) =
  editAppearanceTheme(appearance):
    builder[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Size],
    value: Size,
) =
  editAppearanceTheme(appearance):
    builder[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  editAppearanceTheme(appearance):
    builder[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  editAppearanceTheme(appearance):
    builder[selector, key] = value

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
  editAppearanceTheme(appearance):
    builder[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  editAppearanceTheme(appearance):
    builder[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  editAppearanceTheme(appearance):
    builder[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  editAppearanceTheme(appearance):
    builder[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  editAppearanceTheme(appearance):
    builder[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  editAppearanceTheme(appearance):
    builder[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  editAppearanceTheme(appearance):
    builder[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  editAppearanceTheme(appearance):
    builder[role, states, key] = value

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

proc resolveTooltipStyle*(
    theme: Theme, context = controlStyle(srTooltip)
): TooltipStyle =
  TooltipStyle(
    box: theme.resolveControlBoxStyle(
      context,
      fill(color(1.0, 1.0, 1.0, 0.96)),
      color(0.55, 0.58, 0.64, 0.72),
      borderWidthFallback = 0.75,
      cornerRadiusFallback = 5.0,
      focusRingWidthFallback = 0.0,
      focusRingInsetFallback = 0.0,
      focusRingColorFallback = color(0.0, 0.0, 0.0, 0.0),
      shadowsFallback = @[dropShadow(color(0.0, 0.0, 0.0, 0.32), y = 2.0, blur = 7.0)],
    ),
    text: theme.resolveTextStyle(context, color(0.08, 0.09, 0.11, 1.0), insets(0.0)),
    padding: theme.insetsRule(context, StylePadding, insets(5.0, 8.0)),
  )

proc resolveTooltipStyle*(
    appearance: Appearance, context = controlStyle(srTooltip)
): TooltipStyle =
  appearance.theme.resolveTooltipStyle(context)

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
      focusRingInsetFallback = (if context.role == srCheckBox: -3.0 else: 2.0),
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
  let activeTrack = theme.resolveControlBoxStyle(
    context,
    fill(color(0.13, 0.55, 0.96, 1.0)),
    color(0.02, 0.20, 0.58, 0.70),
    cornerRadiusFallback = 3.0,
    fillKey = StyleHighlightFill,
    borderColorKey = StyleFocusRingColor,
    shadowsFallback = @[insetShadow(color(0.0, 0.0, 0.0, 0.16), y = 1.0, blur = 2.0)],
  )
  SliderStyle(
    track: theme.resolveControlBoxStyle(
      context,
      fill(color(0.76, 0.82, 0.88, 1.0)),
      color(0.38, 0.46, 0.56, 0.75),
      cornerRadiusFallback = 3.0,
      shadowsFallback = @[insetShadow(color(0.0, 0.0, 0.0, 0.16), y = 1.0, blur = 2.0)],
    ),
    activeTrack: activeTrack,
    activeTrackMaximumFill:
      theme.fillRule(context, StyleMaximumHighlightFill, activeTrack.fill),
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
    knobValueTint: theme.lengthRule(context, StyleKnobValueTint, 1.0'f32),
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
  let divider = theme.resolveControlBoxStyle(
    context,
    fill(color(0.84, 0.86, 0.90, 1.0)),
    color(0.58, 0.62, 0.68, 1.0),
    borderWidthFallback = 1.0,
    cornerRadiusFallback = 2.0,
    focusRingWidthFallback = 0.0,
    focusRingInsetFallback = 0.0,
    focusRingColorFallback = color(0.0, 0.0, 0.0, 0.0),
  )
  SplitViewStyle(
    divider: divider,
    dividerThickness: theme.lengthRule(context, StyleSeparatorThickness, 6.0'f32),
    gripColor: theme.colorRule(context, StyleMarkColor, divider.borderColor),
    gripLength: theme.lengthRule(context, StyleIndicatorSize, 28.0'f32),
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
  # Focus rings paint outside the indicator without taking up layout space.
  let
    borderSize = style.indicator.borderWidth * 2.0'f32
    indicatorSize = style.indicatorSize + borderSize
    contentWidth = indicatorSize + style.indicatorSpacing + titleSize.width
    contentHeight = max(indicatorSize, titleSize.height)
  initSize(
    max(style.minSize.width, contentWidth + style.text.insets.horizontal + borderSize),
    max(style.minSize.height, contentHeight + style.text.insets.vertical + borderSize),
  )

func textFieldControlSize*(style: TextFieldStyle, textSize: Size): Size =
  controlSizeWithChrome(textSize, style.text.insets, style.box, style.minSize)

func comboBoxControlSize*(style: ComboBoxStyle, textSize: Size): Size =
  let contentSize = initSize(textSize.width + style.arrowWidth, textSize.height)
  controlSizeWithChrome(contentSize, style.text.insets, style.box, style.minSize)
