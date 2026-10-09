import std/[atomics, sets, strutils, tables]

import figdraw except CornerRadii
from sigils/selectors import DynamicAgent

import ../foundation/types
import ./[stylevalues]
import ./private/[cssproperties, cssvalues]
from ./private/csstokens import CssDiagnostic

export stylevalues except cloneText, lookupToken

export
  figdraw.FillGradientAxis, figdraw.FillKind, figdraw.Linear2, figdraw.Linear3,
  figdraw.Fill, figdraw.ColorRGBA, figdraw.toFill, figdraw.sampleColor,
  figdraw.centerColorRgba, figdraw.centerColor, figdraw.`==`

type
  LayoutStyleSelection* = object
    ## A borrowed declaration in an immutable theme, counted before list copying.
    patch: StylePatch
    key: string

  StyleRule* = object
    selector*: StyleSelector
    patch*: StylePatch
    origin*: StyleRuleOrigin
    isCss*: bool
    important*: bool
    cssSpecificity*: array[3, int]
    sourceOrder*: int
    line*, column*: int

  StyleRuleOrigin* = enum
    sroTheme ## Bundled or newly constructed theme defaults.
    sroCss ## Application stylesheets, including appended CSS.
    sroOverride ## Explicit edits to an existing theme or appearance.

  TokenPriority = object
    origin: StyleRuleOrigin
    important: bool

  Chrome* = ref object of DynamicAgent

  ThemeGeneration* = distinct uint64

  Theme* = object
    xTokens: StyleTokenStore
    xRules: seq[StyleRule]
    xChromes: Table[string, Chrome]
    xRulesByProperty: Table[string, array[StyleRole, seq[int]]]
    xResolvedRules: seq[StylePatch]
    xGeneration: ThemeGeneration
    xMetricStates: set[WidgetState]
    xTokenPriorities: Table[string, TokenPriority]
    xSourceOrder: int
    xHasLayoutRules: bool

  ThemeBuilder* = object
    xTokens: StyleTokenStore
    xRules: seq[StyleRule]
    xChromes: Table[string, Chrome]
    xBaseGeneration: ThemeGeneration
    xChanged: bool
    xWriteOrigin: StyleRuleOrigin
    xTokenPriorities: Table[string, TokenPriority]
    xSourceOrder: int

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

var
  themeInstallers: seq[ThemeInstaller]
  themeGenerationCounter: Atomic[uint64]

proc clone(selector: StyleSelector): StyleSelector =
  result.role = selector.role
  result.states = selector.states
  result.id = selector.id.cloneText
  for className in selector.classes:
    result.classes.add className.cloneText

proc cloneRules(rules: openArray[StyleRule]): seq[StyleRule] =
  var previous, patch: StylePatch
  for rule in rules:
    if rule.patch != previous or patch.isNil:
      patch = rule.patch.clone
      previous = rule.patch
    var copied = rule
    copied.selector = rule.selector.clone
    copied.patch = patch
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

proc initThemeBuilder*(theme: Theme, origin = sroOverride): ThemeBuilder =
  ## Creates an isolated builder initialized from an immutable snapshot.
  ThemeBuilder(
    xTokens: theme.xTokens.clone,
    xRules: theme.xRules.cloneRules(),
    xChromes: theme.xChromes.cloneChromes,
    xBaseGeneration: theme.xGeneration,
    xTokenPriorities: theme.xTokenPriorities,
    xWriteOrigin: origin,
    xSourceOrder: theme.xSourceOrder,
  )

proc finish*(builder: ThemeBuilder, diagnostics: var seq[CssDiagnostic]): Theme =
  ## Compiler hook: freezes declarations and reports invalid CSS during compilation.
  result.xTokens = builder.xTokens.clone
  result.xRules = builder.xRules.cloneRules()
  result.xChromes = builder.xChromes.cloneChromes
  result.xTokenPriorities = builder.xTokenPriorities
  result.xSourceOrder = builder.xSourceOrder
  var
    previousCssPatch, compiledCss: StylePatch
    invalidCss: StyleValue
    reported: HashSet[int]
  for index, rule in result.xRules:
    var compiled: StylePatch
    if rule.isCss:
      if rule.patch != previousCssPatch:
        previousCssPatch = rule.patch
        compiledCss = result.xTokens.resolveCssPatch(rule.patch, invalidCss)
      compiled = compiledCss
      if compiled.isNil and rule.sourceOrder notin reported:
        reported.incl rule.sourceOrder
        let variable =
          case invalidCss.kind
          of svToken: invalidCss.token
          of svCssExpression: invalidCss.cssText
          else: ""
        diagnostics.add CssDiagnostic(
          line: rule.line,
          column: rule.column,
          message:
            if variable.len == 0:
              "Invalid CSS declaration"
            else:
              "Unresolved or wrong-type variable " & variable &
                " (missing, cyclic, or beyond 16 reference steps)",
        )
    else:
      compiled = newStylePatch()
      for key, value in rule.patch.values:
        var resolved: StyleValue
        if result.xTokens.resolveValue(value, resolved):
          var validNative = true
          if resolved.kind == svConstraints:
            for constraint in resolved.constraints:
              if not constraint.validStyleConstraint:
                validNative = false
          if validNative and (
            resolved.kind != svCssExpression or
            result.xTokens.resolveCssValue(value, key, resolved)
          ):
            compiled.values[key] = resolved
    for key in rule.patch.values.keys:
      if key.startsWith("layout."):
        result.xHasLayoutRules = true
      if styleAffectsMetrics(key):
        result.xMetricStates = result.xMetricStates + rule.selector.states
    result.xResolvedRules.add compiled
    if not compiled.isNil:
      for key in compiled.values.keys:
        result.xRulesByProperty.mgetOrPut(key, default(array[StyleRole, seq[int]]))[
          rule.selector.role
        ].add index
  if ssPressed in result.xMetricStates:
    result.xMetricStates.incl ssHighlighted
  if builder.xChanged or builder.xBaseGeneration == ThemeGeneration(0):
    result.xGeneration = nextThemeGeneration()
  else:
    result.xGeneration = builder.xBaseGeneration

proc finish*(builder: ThemeBuilder): Theme =
  ## Freezes and compiles declarations once; drawing only reads typed values.
  var diagnostics: seq[CssDiagnostic]
  builder.finish(diagnostics)

proc noteThemeMutation(builder: var ThemeBuilder) =
  builder.xChanged = true

func sameAppearanceGeneration*(left, right: Appearance): bool =
  ## Compare immutable cache snapshots without traversing every theme value.
  left.theme.xGeneration == right.theme.xGeneration

proc registerThemeInstaller*(installer: ThemeInstaller) =
  themeInstallers.add installer

proc themeExtensionsGeneration*(): Natural =
  ## Changes when another native theme extension is registered.
  themeInstallers.len

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

proc setToken(
    theme: var ThemeBuilder,
    name: string,
    value: StyleValue,
    important: bool,
    origin: StyleRuleOrigin,
): bool =
  let canonical = name.cssTokenName
  if canonical in theme.xTokenPriorities:
    let previous = theme.xTokenPriorities[canonical]
    if previous.origin > origin or
        (previous.origin == origin and previous.important and not important):
      return
  theme.xTokens[canonical] = value
  theme.xTokenPriorities[canonical] =
    TokenPriority(origin: origin, important: important)
  theme.noteThemeMutation()
  true

proc `[]=`*(theme: var ThemeBuilder, name: string, value: StyleValue) =
  discard theme.setToken(name, value, false, theme.xWriteOrigin)

proc setCssToken*(
    theme: var ThemeBuilder,
    name: string,
    value: StyleValue,
    important = false,
    origin = sroCss,
) =
  ## Source-independent layers also apply to theme custom properties.
  discard theme.setToken(name, value, important, origin)

func hasLayoutRules*(theme: Theme): bool =
  ## Whether the snapshot contains native or CSS constraint specifications.
  theme.xHasLayoutRules

func metricStates*(theme: Theme): set[WidgetState] =
  ## States whose declarations can change intrinsic content metrics, from either source.
  theme.xMetricStates

func metricsChange*(theme: Theme, states: set[WidgetState]): bool =
  ## Whether changing these states can affect intrinsic content metrics.
  (theme.xMetricStates * states) != {}

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

func selectorSpecificity(selector: StyleSelector): array[3, int] =
  [ord(selector.id.len > 0), selector.classes.len + card(selector.states), 1]

func ruleRank(rule: StyleRule, roleRank = 0): array[7, int] =
  [
    ord(rule.origin),
    ord(rule.important),
    rule.cssSpecificity[0],
    rule.cssSpecificity[1],
    rule.cssSpecificity[2],
    roleRank,
    rule.sourceOrder,
  ]

func rankAtLeast(left, right: array[7, int]): bool =
  for index in 0 .. left.high:
    if left[index] != right[index]:
      return left[index] > right[index]
  true

func inheritedStyleRole(role: StyleRole): StyleRole =
  case role
  of srStepper: srButton
  of srMenuBar: srTabPanel
  of srMenuBarItem: srTab
  of srDocumentTab, srDocumentTabButton: srTab
  of srDocumentTabBar: srTabPanel
  else: role

proc stylePatch(theme: var ThemeBuilder, selector: StyleSelector): StylePatch =
  inc theme.xSourceOrder
  result = newStylePatch()
  theme.xRules.add StyleRule(
    selector: selector,
    patch: result,
    origin: theme.xWriteOrigin,
    cssSpecificity: selector.selectorSpecificity,
    sourceOrder: theme.xSourceOrder,
  )

proc exactStylePatch(rules: openArray[StyleRule], selector: StyleSelector): StylePatch =
  var best: Table[string, int]
  for index, rule in rules:
    if rule.selector == selector:
      if result.isNil:
        result = newStylePatch()
      for key, value in rule.patch.values:
        if key notin best or rule.ruleRank.rankAtLeast(rules[best[key]].ruleRank):
          result.values[key] = value
          best[key] = index

proc stylePatchView(theme: Theme, selector: StyleSelector): StylePatch =
  exactStylePatch(theme.xRules, selector)

proc stylePatch*(theme: Theme, selector: StyleSelector): StylePatch =
  ## Returns a mutable copy without exposing snapshot-owned storage.
  theme.stylePatchView(selector).clone

proc addRule*(theme: var ThemeBuilder, selector: StyleSelector, patch: StylePatch) =
  inc theme.xSourceOrder
  theme.xRules.add StyleRule(
    selector: selector,
    patch: patch,
    origin: theme.xWriteOrigin,
    cssSpecificity: selector.selectorSpecificity,
    sourceOrder: theme.xSourceOrder,
  )
  theme.noteThemeMutation()

proc nextSourceOrder*(theme: var ThemeBuilder): int =
  ## Compiler hook: one source-order value for an expanded CSS declaration.
  inc theme.xSourceOrder
  theme.xSourceOrder

proc addCssRule*(
    theme: var ThemeBuilder,
    selector: StyleSelector,
    patch: StylePatch,
    specificity: array[3, int],
    sourceOrder: int,
    important = false,
    line = 1,
    column = 1,
    origin = sroCss,
) =
  ## Compiler hook: adds a CSS declaration without merging identical selectors.
  theme.xRules.add StyleRule(
    selector: selector,
    patch: patch,
    origin: origin,
    isCss: true,
    important: important,
    cssSpecificity: specificity,
    sourceOrder: sourceOrder,
    line: line,
    column: column,
  )
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
  let patch = exactStylePatch(theme.xRules, initStyleSelector(role))
  if patch.isNil or not patch.getStyle(key, result):
    result = missingStyleValue()

proc ruleValue(
    theme: Theme, context: StyleContext, key: string, fallback: StyleValue
): StyleValue =
  result = fallback
  var bestRank = [-1, -1, -1, -1, -1, -1, -1]
  let inheritedRole = context.role.inheritedStyleRole
  let keyCount =
    if key in [StyleBackgroundFill.keyName, StyleBackgroundColor.keyName]: 2 else: 1
  for keyIndex in 0 ..< keyCount:
    let name = if keyIndex == 0: key else: StyleFill.keyName
    if name in theme.xRulesByProperty:
      for role in [inheritedRole, context.role]:
        var matchContext = context
        matchContext.role = role
        for index in theme.xRulesByProperty[name][role]:
          let rule = theme.xRules[index]
          if rule.selector.matches(matchContext):
            let rank = rule.ruleRank(ord(role == context.role))
            if rank.rankAtLeast(bestRank):
              result = theme.xResolvedRules[index].values[name]
              bestRank = rank
        if inheritedRole == context.role:
          break

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
  if not theme.xTokens.resolveCssToken(name, fallback.kind, result):
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
  case value.kind
  of svSize:
    value.size
  of svLength:
    initSize(value.length, value.length)
  else:
    fallback

proc insetsToken*(theme: Theme, name: string, fallback: EdgeInsets): EdgeInsets =
  let value = theme.styleValue(name, styleInsets(fallback))
  case value.kind
  of svInsets:
    value.insets
  of svLength:
    insets(value.length)
  else:
    fallback

proc shadowsToken*(
    theme: Theme, name: string, fallback: seq[BoxShadow]
): seq[BoxShadow] =
  let value = theme.styleValue(name, styleShadows(fallback))
  if value.kind == svShadows:
    value.shadows
  elif value.kind == svKeyword and value.keyword == "none":
    @[]
  else:
    fallback

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
  ## Selects already-compiled data without copying potentially large lists.
  var bestRank = [-1, -1, -1, -1, -1, -1, -1]
  let name = key.keyName
  let inheritedRole = context.role.inheritedStyleRole
  if name in theme.xRulesByProperty:
    for role in [inheritedRole, context.role]:
      var matchContext = context
      matchContext.role = role
      for index in theme.xRulesByProperty[name][role]:
        if not checkWork.isNil:
          checkWork()
        let rule = theme.xRules[index]
        let patch = theme.xResolvedRules[index]
        if rule.selector.matches(matchContext) and
            patch.values[name].kind == svConstraints:
          let rank = rule.ruleRank(ord(role == context.role))
          if rank.rankAtLeast(bestRank):
            result = LayoutStyleSelection(patch: patch, key: name)
            bestRank = rank
      if inheritedRole == context.role:
        break

func constraintCount*(selection: LayoutStyleSelection): Natural =
  ## Reads borrowed list metadata without copying or validating list entries.
  if not selection.patch.isNil:
    selection.patch.values[selection.key].constraints.len
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
    var spec = selection.patch.values[selection.key].constraints[index]
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
