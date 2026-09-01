## A synchronous NimKit frontend for the Moe editor engine.

import std/[math, options, os, strutils, unicode]

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ../nimkit/foundation/selectors as nimkitSelectors
import
  ./[
    cli, filesearchpanel, filetree, moe, moehighlighting, panedocuments, quickopen,
    settings, shortcuts,
  ]
import pkg/celina as celina

export
  filesearchpanel, filetree, moe, moehighlighting, panedocuments, quickopen, settings,
  shortcuts

const
  KosmoIconPng =
    staticRead(currentSourcePath().parentDir / "../../../data/kosmo-icon.png")
  KosmoVersion* {.strdefine.} = "0.14.0"
  KosmoGitHashOverride* {.strdefine.} = ""
  KosmoGitHash* =
    when KosmoGitHashOverride.len > 0:
      KosmoGitHashOverride
    else:
      block:
        const repositoryRoot = currentSourcePath().parentDir / "../../.."
        const revision =
          gorgeEx("git -C " & quoteShell(repositoryRoot) & " rev-parse --short=12 HEAD")
        if revision.exitCode == 0:
          revision.output.strip()
        else:
          "unknown"
  KosmoAboutCredits =
    """
Powered by Moe, the Vim-like text editor.
https://github.com/fox0430/moe

Licensed under the GNU General Public License v3.0 (GPL-3.0)."""
  KosmoTabBarHeight* = 34.0'f32
  KosmoStatusBarHeight* = 22.0'f32
  KosmoCommandBarHeight* = 24.0'f32
  KosmoQuickOpenTopInset = 96.0'f32
  KosmoQuickOpenBottomInset = 24.0'f32
  KosmoEditorStyleId* = "kosmo.editor"
  KosmoPaneIndicatorStyleId* = "kosmo.pane-indicator"
  KosmoMarkdownControlsStyleId* = "kosmo.markdown-controls"
  KosmoMarkdownControlButtonStyleClass = "kosmo-markdown-control-button"
  KosmoPreviewTabStyleClass* = "kosmo-preview"
  KosmoMarkdownDefaultFontSize* = 14.0'f32
  KosmoMarkdownMinimumFontSize* = 9.0'f32
  KosmoMarkdownMaximumFontSize* = 28.0'f32
  KosmoInactivePaneStyleClass* = "kosmo-inactive-pane"
  KosmoCursorOpacity = 0.45'f32
  KosmoPaneOutlineOpacity = 0.38'f32
  KosmoInactiveTabAccentOpacity = 0.18'f32
  KosmoInactiveTabTextOpacity = 0.72'f32
  KosmoPaneOutlineWidth = 1.0'f32
  KosmoMarkdownControlsWidth = 184.0'f32
  KosmoMarkdownControlsHeight = 38.0'f32
  KosmoMarkdownControlsInset = 10.0'f32
  KosmoMarkdownFontSizeIncrement = 1.0'f32
  KosmoControlScrollMultiplier = 3.0'f32
  KosmoGridOverscanRows = 1
  KosmoMoeBottomAreaRows = 1
  KosmoTabIdentifierPrefix = "kosmo.buffer."
  KosmoTerminalIdentifierPrefix = "kosmo.terminal."
  KosmoFilesTabIdentifier* = "kosmo.sidebar.files"
  KosmoFindTabIdentifier* = "kosmo.sidebar.find"
  KosmoFilesIconSvg =
    """<svg width="24" height="24" viewBox="0 0 24 24"><path fill="#000" d="M2 5h8l2 2h10v13H2z"/></svg>"""
  KosmoFindIconSvg =
    """<svg width="24" height="24" viewBox="0 0 24 24"><circle cx="10" cy="10" r="6" fill="none" stroke="#000" stroke-width="2.4"/><path fill="#000" d="M14.2 13l7 7-1.7 1.7-7-7z"/></svg>"""

type
  KosmoMarkdownMode* = enum
    kmmPreview
    kmmSyntax

  KosmoMarkdownColorMode* = enum
    kmcmLight
    kmcmDark

  KosmoEditorContentKind = enum
    keckOther
    keckSyntax
    keckMarkdownPreview

  KosmoPaneCommand = enum
    kpcNone
    kpcSplitBelow
    kpcSplitRight
    kpcNewBelow
    kpcFocusNext
    kpcFocusLeft
    kpcFocusBelow
    kpcFocusAbove
    kpcFocusRight
    kpcClose
    kpcGrowHeight
    kpcShrinkHeight
    kpcShrinkWidth
    kpcGrowWidth
    kpcEqualize

  KosmoCommandBar* = ref object of nimkit.MonoTextView

  KosmoPaneIndicator = ref object of nimkit.View

  KosmoMarkdownView = ref object of nimkit.MarkdownView
    editorView: WeakRef[KosmoEditorView]

  KosmoMarkdownControls* = ref object of nimkit.Box
    modeButton*: nimkit.Button
    colorModeButton*: nimkit.Button
    decreaseFontButton*: nimkit.Button
    increaseFontButton*: nimkit.Button
    editorView: WeakRef[KosmoEditorView]
    xColorMode: KosmoMarkdownColorMode
    xThemeColorMode: KosmoMarkdownColorMode
    xFontSize: float32

  KosmoEditorView* = ref object of nimkit.MonoTextView
    editor*: KosmoEditor
    documentTabs*: nimkit.DocumentTabs
    renderBuffer: RenderBuffer
    statusLabel: nimkit.Label
    commandBar: KosmoCommandBar
    scrollOffsetRows: float32
    lastTabs: seq[KosmoTab]
    syncingTabs: bool
    tabsDelegate: KosmoEditorTabsHandler
    usesBufferSubset: bool
    bufferIds: seq[KosmoBufferId]
    selectedBufferId: Option[KosmoBufferId]
    markdownSyntaxBufferIds: seq[KosmoBufferId]
    viewStates: seq[KosmoEditorViewState]
    dockGroup: WeakRef[KosmoEditorGroup]
    pendingPanePrefix: bool

  KosmoEditorTabsHandler = ref object of nimkit.Responder
    editorView: WeakRef[KosmoEditorView]
    dockController: WeakRef[KosmoDockController]
    appearanceWindow: WeakRef[nimkit.Window]

  KosmoEditorPane* = ref object of nimkit.View
    documentTabs*: nimkit.DocumentTabs
    editorView*: KosmoEditorView
    commandBar*: KosmoCommandBar
    markdownView*: KosmoMarkdownView
    markdownControls*: KosmoMarkdownControls
    contentView*: nimkit.View
    activeIndicator: KosmoPaneIndicator
    dockGroup: WeakRef[KosmoEditorGroup]

  KosmoSidebarPane* = ref object of nimkit.View
    tabs*: nimkit.CompactTabView
    fileTree: KosmoFileTree
    searchPanel: KosmoFileSearchPanel
    activeIndicator: KosmoPaneIndicator
    dockController: WeakRef[KosmoDockController]
    observedWindow: WeakRef[nimkit.Window]

  KosmoEditorGroup* = ref object
    identifier*: string
    panel*: nimkit.DockPanel
    pane*: KosmoEditorPane
    editorView*: KosmoEditorView
    workspace*: nimkit.DockView
    window*: nimkit.Window
    documents: seq[KosmoPaneDocument]
    tabOrder: seq[string]
    selectedTabIdentifier: string

  KosmoDockHost = ref object
    workspace: nimkit.DockView
    window: nimkit.Window
    contentView: nimkit.View
    statusLabel: nimkit.Label
    primary: bool

  KosmoDockController = ref object
    frontend: WeakRef[KosmoApplication]
    editor: KosmoEditor
    groups: seq[KosmoEditorGroup]
    hosts: seq[KosmoDockHost]
    xActiveGroup: KosmoEditorGroup
    nextGroupIdentifier: int
    nextDocumentIdentifier: int
    shortcutBindings: nimkit.KeyBindingTable
    shortcutProfile: KosmoShortcutProfile
    editorInputPolicy: KosmoEditorInputPolicy
    xSidebarFocused: bool

  KosmoContentView = ref object of nimkit.View
    splitView: nimkit.SplitView
    statusLabel: nimkit.Label
    setInitialDivider: bool
    lastSplitWidth: float32
    fileTreeWidth: float32
    onShowFileExplorer: proc() {.closure.}
    onFindInFiles: proc() {.closure.}
    onQuickOpen: proc() {.closure.}
    onNewTerminal: proc() {.closure.}
    onFocusPanel: proc(panelNumber: int) {.closure.}
    quickOpenPanel: KosmoQuickOpenPanel

  KosmoDetachedContentView = ref object of nimkit.View
    workspace: nimkit.DockView
    statusLabel: nimkit.Label

  KosmoWindowManager* = ref object
    application*: nimkit.Application
    keyBindingsPath: string
    frontends: seq[KosmoApplication]

  KosmoWindowLifecycle = ref object of nimkit.Responder
    frontend: WeakRef[KosmoApplication]

  KosmoApplication* = ref object
    application*: nimkit.Application
    window*: nimkit.Window
    editorView*: KosmoEditorView
    editorPane*: KosmoEditorPane
    documentTabs*: nimkit.DocumentTabs
    statusLabel*: nimkit.Label
    fileTree*: KosmoFileTree
    sidebarPane*: KosmoSidebarPane
    sidebarTabs*: nimkit.CompactTabView
    searchPanel*: KosmoFileSearchPanel
    quickOpenPanel*: KosmoQuickOpenPanel
    splitView*: nimkit.SplitView
    dockView*: nimkit.DockView
    contentView*: nimkit.MenuRootView
    documentView: KosmoContentView
    dockController: KosmoDockController
    xSettingsWindow: KosmoSettingsWindow
    xTerminalOptionAsMeta: bool
    xWindowManager: WeakRef[KosmoWindowManager]
    xWindowLifecycle: KosmoWindowLifecycle
    xHasFileBrowser: bool
    xClosed: bool

proc updateActivePaneIndicator(group: KosmoEditorGroup, active: bool) =
  if group.isNil or group.pane.isNil:
    return
  if active:
    group.pane.documentTabs.removeStyleClass(KosmoInactivePaneStyleClass)
  else:
    group.pane.documentTabs.addStyleClass(KosmoInactivePaneStyleClass)
  if not group.pane.activeIndicator.isNil:
    group.pane.activeIndicator.hidden = not active

func activeGroup(controller: KosmoDockController): KosmoEditorGroup =
  controller.xActiveGroup

proc `activeGroup=`(controller: KosmoDockController, group: KosmoEditorGroup) =
  if controller.xActiveGroup == group:
    return
  controller.xActiveGroup = group
  for candidate in controller.groups:
    candidate.updateActivePaneIndicator(
      candidate == group and not controller.xSidebarFocused
    )

proc `sidebarFocused=`(controller: KosmoDockController, focused: bool) =
  if controller.isNil or controller.xSidebarFocused == focused:
    return
  controller.xSidebarFocused = focused
  for group in controller.groups:
    group.updateActivePaneIndicator(
      group == controller.activeGroup and not controller.xSidebarFocused
    )

proc showFileExplorer*(frontend: KosmoApplication): bool {.discardable.}
proc showFindInFiles*(frontend: KosmoApplication): bool {.discardable.}
func hasFileBrowser*(frontend: KosmoApplication): bool
proc showQuickOpen*(frontend: KosmoApplication): bool {.discardable.}
proc newEditorTab*(frontend: KosmoApplication): bool {.discardable.}
proc newTerminal*(frontend: KosmoApplication): bool {.discardable.}
proc showSettings*(frontend: KosmoApplication): bool {.discardable.}
proc openPath*(frontend: KosmoApplication, path: string): bool {.discardable.}
proc show*(frontend: KosmoApplication)
proc close*(frontend: KosmoApplication)
proc activateGroup(controller: KosmoDockController, view: KosmoEditorView)
proc focusPanel(controller: KosmoDockController, panelNumber: int): bool
proc preferredPaneResponder(group: KosmoEditorGroup): nimkit.Responder
proc groupForView(
  controller: KosmoDockController, view: KosmoEditorView
): KosmoEditorGroup

proc chooseFile(frontend: KosmoApplication)
proc chooseFile(manager: KosmoWindowManager)
proc chooseProject(manager: KosmoWindowManager)
func isEditingAction(action: string): bool

proc splitCurrentPaneTab(
  controller: KosmoDockController,
  source: KosmoEditorGroup,
  position: nimkit.DockPosition,
): bool

proc performPaneCommand(
  controller: KosmoDockController, source: KosmoEditorGroup, command: KosmoPaneCommand
): bool

func shortcutKeyTitle(stroke: nimkit.KeyStroke): string =
  if stroke.text.len > 0:
    return stroke.text.toUpperAscii()
  if stroke.key >= nimkit.keyA and stroke.key <= nimkit.keyZ:
    return $char(ord('A') + ord(stroke.key) - ord(nimkit.keyA))
  if stroke.key >= nimkit.key1 and stroke.key <= nimkit.key9:
    return $char(ord('1') + ord(stroke.key) - ord(nimkit.key1))
  if stroke.key == nimkit.key0:
    return "0"
  if stroke.key >= nimkit.keyF1 and stroke.key <= nimkit.keyF15:
    return "F" & $(ord(stroke.key) - ord(nimkit.keyF1) + 1)
  case stroke.key
  of nimkit.keyTilde:
    "`"
  of nimkit.keyMinus:
    "-"
  of nimkit.keyEqual:
    "="
  of nimkit.keyLeftBracket:
    "["
  of nimkit.keyRightBracket:
    "]"
  of nimkit.keySpace:
    "Space"
  of nimkit.keyEscape:
    "Esc"
  of nimkit.keyEnter:
    "Enter"
  of nimkit.keyTab:
    "Tab"
  of nimkit.keyBackspace:
    "Backspace"
  of nimkit.keySlash:
    "/"
  of nimkit.keyDot:
    "."
  of nimkit.keyComma:
    ","
  of nimkit.keySemicolon:
    ";"
  of nimkit.keyQuote:
    "'"
  of nimkit.keyBackslash:
    "\\"
  of nimkit.keyPageUp:
    "Page Up"
  of nimkit.keyPageDown:
    "Page Down"
  of nimkit.keyHome:
    "Home"
  of nimkit.keyEnd:
    "End"
  of nimkit.keyInsert:
    "Insert"
  of nimkit.keyDelete:
    "Delete"
  of nimkit.keyArrowLeft:
    "Left"
  of nimkit.keyArrowRight:
    "Right"
  of nimkit.keyArrowUp:
    "Up"
  of nimkit.keyArrowDown:
    "Down"
  of nimkit.keyUnknown:
    if stroke.keyCode == 0:
      "Unknown"
    else:
      $stroke.keyCode
  else:
    let name = $stroke.key
    if name.startsWith("key"):
      name[3 .. ^1]
    else:
      name

func shortcutStrokeTitle(stroke: nimkit.KeyStroke): string =
  var parts: seq[string]
  if nimkit.kmCommand in stroke.modifiers:
    when defined(macosx) or defined(macos):
      parts.add "Cmd"
    else:
      parts.add "Super"
  if nimkit.kmControl in stroke.modifiers:
    parts.add "Ctrl"
  if nimkit.kmOption in stroke.modifiers:
    parts.add "Option"
  if nimkit.kmShift in stroke.modifiers:
    parts.add "Shift"
  parts.add stroke.shortcutKeyTitle()
  parts.join("+")

func shortcutSequenceTitle(sequence: nimkit.KeySequence): string =
  for index, stroke in sequence.strokes:
    if index > 0:
      result.add " "
    result.add stroke.shortcutStrokeTitle()

func kosmoShortcutSettings*(
    bindings: nimkit.KeyBindingTable
): seq[KosmoShortcutSetting] =
  ## Build display rows for Kosmo's currently resolved shortcut bindings.
  for action in kosmoActions():
    var keys: seq[string]
    for binding in bindings.bindings:
      if $binding.selector.name == action.identifier:
        keys.add binding.sequence.shortcutSequenceTitle()
    if action.identifier == KosmoSplitHorizontalAction:
      keys.add "Ctrl+W S / Ctrl+W Ctrl+S"
    elif action.identifier == KosmoSplitVerticalAction:
      keys.add "Ctrl+W V / Ctrl+W Ctrl+V"
    result.add KosmoShortcutSetting(
      action: action.identifier, description: action.description, keys: keys.join(", ")
    )

func focusPanelNumber(selector: nimkit.CommandSelector): int =
  let name = $selector.name
  if not name.startsWith(KosmoFocusPanelActionPrefix):
    return
  try:
    result = parseInt(name[KosmoFocusPanelActionPrefix.len .. ^1])
  except ValueError:
    discard
  if result notin 1 .. KosmoMaxFocusPanelShortcut:
    result = 0

func toMoeModifiers(modifiers: set[nimkit.KeyModifier]): set[moe.KeyModifier] =
  if nimkit.kmControl in modifiers:
    result.incl moe.kmControl
  if nimkit.kmOption in modifiers:
    result.incl moe.kmAlt
  if nimkit.kmShift in modifiers:
    result.incl moe.kmShift
  if nimkit.kmCommand in modifiers:
    result.incl moe.kmMeta

func toPointerButton(button: nimkit.MouseButton): PointerButton =
  case button
  of nimkit.mbPrimary: pbPrimary
  of nimkit.mbSecondary: pbSecondary
  of nimkit.mbOther: pbOther

func keyName(event: nimkit.KeyEvent): string =
  if event.key >= nimkit.keyA and event.key <= nimkit.keyZ:
    return $char(ord('a') + ord(event.key) - ord(nimkit.keyA))
  if event.key >= nimkit.key0 and event.key <= nimkit.key9:
    return $char(ord('0') + ord(event.key) - ord(nimkit.key0))
  case event.key
  of nimkit.keySpace: "Space"
  of nimkit.keyEscape: "Esc"
  of nimkit.keyEnter: "Enter"
  of nimkit.keyTab: "Tab"
  of nimkit.keyBackspace: "Backspace"
  of nimkit.keyDelete: "Delete"
  of nimkit.keyArrowUp: "Up"
  of nimkit.keyArrowDown: "Down"
  of nimkit.keyArrowLeft: "Left"
  of nimkit.keyArrowRight: "Right"
  of nimkit.keyPageUp: "PageUp"
  of nimkit.keyPageDown: "PageDown"
  of nimkit.keyHome: "Home"
  of nimkit.keyEnd: "End"
  of nimkit.keyMinus: "-"
  of nimkit.keyEqual: "="
  of nimkit.keySlash: "/"
  of nimkit.keyDot: "."
  of nimkit.keyComma: ","
  of nimkit.keySemicolon: ";"
  of nimkit.keyQuote: "'"
  of nimkit.keyBackslash: "\\"
  else: event.text

func keyNotation(event: nimkit.KeyEvent): string =
  let key = event.keyName()
  if key.len == 0:
    return
  var parts: seq[string]
  if nimkit.kmControl in event.modifiers:
    parts.add "C"
  if nimkit.kmOption in event.modifiers or nimkit.kmCommand in event.modifiers:
    parts.add "M"
  if nimkit.kmShift in event.modifiers:
    parts.add "S"
  parts.add key
  parts.join("-")

func awaitsCommittedText(event: nimkit.KeyEvent): bool =
  if event.modifiers - {nimkit.kmShift} != {}:
    return false
  case event.key
  of nimkit.keyA .. nimkit.keyZ,
      nimkit.keyTilde,
      nimkit.key1 .. nimkit.key0,
      nimkit.keyMinus,
      nimkit.keyEqual,
      nimkit.keyLeftBracket,
      nimkit.keyRightBracket,
      nimkit.keySpace,
      nimkit.keySlash,
      nimkit.keyDot,
      nimkit.keyComma,
      nimkit.keySemicolon,
      nimkit.keyQuote,
      nimkit.keyBackslash,
      nimkit.keyNumpad0 .. nimkit.keyNumpad9,
      nimkit.keyNumpadDot,
      nimkit.keyAdd,
      nimkit.keySubtract,
      nimkit.keyMultiply,
      nimkit.keyDivide:
    true
  else:
    false

func toNimkitColor(color: celina.ColorValue): nimkit.Color =
  let rgb = celina.toRgb(color)
  return nimkit.color(
    float32(rgb.r) / 255.0'f32,
    float32(rgb.g) / 255.0'f32,
    float32(rgb.b) / 255.0'f32,
    1.0'f32,
  )

func toMonoTextCell(cell: RenderCell): nimkit.MonoTextCell =
  var
    foreground = cell.style.fg
    background = cell.style.bg
  if celina.Reversed in cell.style.modifiers:
    swap foreground, background
  nimkit.initMonoTextCell(
    cell.symbol,
    foreground.toNimkitColor,
    background.toNimkitColor,
    foreground.kind != celina.Default,
    background.kind != celina.Default,
  )

func tabIdentifier(id: KosmoBufferId): string =
  KosmoTabIdentifierPrefix & $id

proc parseTabIdentifier(identifier: string, id: var KosmoBufferId): bool =
  if not identifier.startsWith(KosmoTabIdentifierPrefix):
    return
  try:
    id = KosmoBufferId(parseInt(identifier[KosmoTabIdentifierPrefix.len .. ^1]))
    return true
  except ValueError:
    discard

func isMarkdownFilePath*(path: string): bool =
  ## Return whether `path` uses a conventional Markdown-family extension.
  splitFile(path).ext.toLowerAscii() in
    [".md", ".markdown", ".mdown", ".mkd", ".mkdn", ".mdwn", ".mdtxt", ".mdtext"]

func isMarkdownTab(tab: KosmoTab): bool =
  tab.filePath.isSome and tab.filePath.get.isMarkdownFilePath()

func markdownMode*(view: KosmoEditorView, id: KosmoBufferId): KosmoMarkdownMode =
  ## Return the pane-local presentation mode for a Markdown buffer.
  if not view.isNil and id in view.markdownSyntaxBufferIds: kmmSyntax else: kmmPreview

func markdownColorMode*(controls: KosmoMarkdownControls): KosmoMarkdownColorMode =
  ## Return the pane-local Markdown preview color mode.
  if controls.isNil: kmcmLight else: controls.xColorMode

func markdownFontSize*(controls: KosmoMarkdownControls): float32 =
  ## Return the pane-local Markdown preview base font size.
  if controls.isNil: KosmoMarkdownDefaultFontSize else: controls.xFontSize

proc syncMarkdownColorButton(controls: KosmoMarkdownControls) =
  if controls.isNil or controls.colorModeButton.isNil:
    return
  controls.colorModeButton.title =
    if controls.xColorMode == kmcmLight: "Dark" else: "Light"
  controls.colorModeButton.accessibilityLabel =
    if controls.xColorMode == kmcmLight:
      "Use dark Markdown preview"
    else:
      "Use light Markdown preview"
  controls.colorModeButton.toolTip = controls.colorModeButton.accessibilityLabel()

func markdownColorMode(appearance: nimkit.Appearance): KosmoMarkdownColorMode =
  let
    context = nimkit.controlStyle(nimkit.srView)
    fallback = appearance.resolveColor(
      context, nimkit.StyleBackgroundColor, nimkit.color(1.0, 1.0, 1.0, 1.0)
    )
    background = appearance
      .resolveFill(context, nimkit.fill(fallback), nimkit.StyleBackgroundFill)
      .centerColor()
    luminance =
      0.2126'f32 * background.r + 0.7152'f32 * background.g + 0.0722'f32 * background.b
  if luminance < 0.5'f32: kmcmDark else: kmcmLight

proc syncMarkdownColorMode(
    controls: KosmoMarkdownControls, appearance: nimkit.Appearance
) =
  if controls.isNil:
    return
  let mode = appearance.markdownColorMode()
  if controls.xColorMode == controls.xThemeColorMode:
    controls.xColorMode = mode
  controls.xThemeColorMode = mode
  controls.syncMarkdownColorButton()

func markdownPresentationStyle(controls: KosmoMarkdownControls): nimkit.MarkdownStyle =
  result = nimkit.initMarkdownStyle()
  if not controls.isNil and controls.xColorMode == kmcmDark:
    result.backgroundColor = nimkit.color(0.055, 0.065, 0.085, 1.0)
    result.textColor = nimkit.color(0.84, 0.86, 0.90, 1.0)
    result.headingColor = nimkit.color(0.96, 0.97, 0.99, 1.0)
    result.strongColor = nimkit.color(0.96, 0.97, 0.99, 1.0)
    result.emphasisColor = nimkit.color(0.80, 0.65, 0.96, 1.0)
    result.linkColor = nimkit.color(0.40, 0.69, 0.98, 1.0)
    result.codeColor = nimkit.color(0.96, 0.53, 0.64, 1.0)
    result.quoteColor = nimkit.color(0.67, 0.72, 0.82, 1.0)
    result.mutedColor = nimkit.color(0.56, 0.61, 0.70, 1.0)
    result.ruleColor = nimkit.color(0.35, 0.40, 0.49, 1.0)
    result.codeBlockStyle.backgroundColor = nimkit.color(0.08, 0.10, 0.14, 1.0)
    result.codeBlockStyle.outlineColor = nimkit.color(0.28, 0.33, 0.42, 1.0)
    for tokenClass in nimkit.SyntaxTokenClass:
      result.syntaxTokenColors[tokenClass] = result.codeColor
    result.syntaxTokenColors[nimkit.stcKeyword] = nimkit.color(0.80, 0.65, 0.96, 1.0)
    result.syntaxTokenColors[nimkit.stcIdentifier] = nimkit.color(0.54, 0.71, 0.98, 1.0)
    result.syntaxTokenColors[nimkit.stcString] = nimkit.color(0.65, 0.89, 0.63, 1.0)
    result.syntaxTokenColors[nimkit.stcNumber] = nimkit.color(0.98, 0.70, 0.53, 1.0)
    result.syntaxTokenColors[nimkit.stcComment] = result.mutedColor
    result.syntaxTokenColors[nimkit.stcOperator] = nimkit.color(0.54, 0.71, 0.98, 1.0)
    result.syntaxTokenColors[nimkit.stcPunctuation] =
      nimkit.color(0.58, 0.60, 0.70, 1.0)
    result.syntaxTokenColors[nimkit.stcPreprocessor] =
      nimkit.color(0.80, 0.65, 0.96, 1.0)

  let
    fontSize = if controls.isNil: KosmoMarkdownDefaultFontSize else: controls.xFontSize
    scale = fontSize / KosmoMarkdownDefaultFontSize
  result.bodyFontSize = fontSize
  for size in result.headingFontSizes.mitems:
    size *= scale

proc syncMarkdownControls(pane: KosmoEditorPane, visible: bool, mode = kmmPreview) =
  if pane.isNil or pane.markdownControls.isNil:
    return
  let controls = pane.markdownControls
  controls.hidden = not visible
  if not visible:
    return
  controls.modeButton.title = if mode == kmmPreview: "</>" else: "MD"
  controls.modeButton.accessibilityLabel =
    if mode == kmmPreview: "Edit Markdown source" else: "Preview Markdown"
  controls.modeButton.toolTip = controls.modeButton.accessibilityLabel()
  controls.syncMarkdownColorButton()
  controls.decreaseFontButton.enabled =
    controls.xFontSize > KosmoMarkdownMinimumFontSize
  controls.increaseFontButton.enabled =
    controls.xFontSize < KosmoMarkdownMaximumFontSize

proc forgetMarkdownMode(view: KosmoEditorView, id: KosmoBufferId) =
  let index = view.markdownSyntaxBufferIds.find(id)
  if index >= 0:
    view.markdownSyntaxBufferIds.delete(index)

proc documentIndex(group: KosmoEditorGroup, identifier: string): int =
  if group.isNil:
    return -1
  for index, document in group.documents:
    if document.identifier == identifier:
      return index
  -1

proc documentForIdentifier(
    group: KosmoEditorGroup, identifier: string
): KosmoPaneDocument =
  let index = group.documentIndex(identifier)
  if index >= 0:
    result = group.documents[index]

func documents*(group: KosmoEditorGroup): lent seq[KosmoPaneDocument] =
  ## Return the non-Moe documents currently owned by this pane group.
  group.documents

proc setContentView(pane: KosmoEditorPane, contentView: nimkit.View)

proc selectEditorContent(view: KosmoEditorView, id: KosmoBufferId) =
  if view.dockGroup.isNil:
    return
  let group = view.dockGroup[]
  group.selectedTabIdentifier = id.tabIdentifier
  group.pane.setContentView(view)

func statusText(status: KosmoStatus, tabs: openArray[KosmoTab]): string =
  var parts: seq[string]
  if status.modeLabel.len > 0:
    parts.add status.modeLabel
  for tab in tabs:
    if tab.active:
      parts.add tab.title
      break
  if status.message.len > 0:
    parts.add status.message
  if status.gitBranch.len > 0:
    var git = "Git: " & status.gitBranch
    if status.gitAdded != 0:
      git.add " +" & $status.gitAdded
    if status.gitModified != 0:
      git.add " ~" & $status.gitModified
    if status.gitDeleted != 0:
      git.add " -" & $status.gitDeleted
    parts.add git
  parts.join("  •  ")

proc visibleTabs(view: KosmoEditorView, tabs: openArray[KosmoTab]): seq[KosmoTab] =
  if not view.usesBufferSubset:
    return @tabs
  var visibleIds: seq[KosmoBufferId]
  for id in view.bufferIds:
    for tab in tabs:
      if tab.id == id:
        result.add tab
        visibleIds.add id
        break
  view.bufferIds = visibleIds

proc syncEditorTabOrder(view: KosmoEditorView) =
  let tabs = view.editor.tabs()
  if tabs.len != view.bufferIds.len:
    var
      desiredIds = newSeqOfCap[KosmoBufferId](tabs.len)
      groupIndex = 0
    for tab in tabs:
      if tab.id in view.bufferIds:
        desiredIds.add view.bufferIds[groupIndex]
        inc groupIndex
      else:
        desiredIds.add tab.id
    for index, id in desiredIds:
      discard view.editor.moveTab(id, index.Natural)
  else:
    for index, id in view.bufferIds:
      discard view.editor.moveTab(id, index.Natural)

proc viewStateIndex(view: KosmoEditorView, id: KosmoBufferId): int =
  for index, state in view.viewStates:
    if state.bufferId == some(id):
      return index
  -1

proc saveViewState(view: KosmoEditorView) =
  if not view.usesBufferSubset or view.selectedBufferId.isNone:
    return
  let state = view.editor.captureViewState()
  if state.bufferId != view.selectedBufferId:
    return
  let index = view.viewStateIndex(view.selectedBufferId.get)
  if index >= 0:
    view.viewStates[index] = state
  else:
    view.viewStates.add state

proc removeViewState(view: KosmoEditorView, id: KosmoBufferId) =
  let index = view.viewStateIndex(id)
  if index >= 0:
    view.viewStates.delete(index)

proc closeTab(view: KosmoEditorView, id: KosmoBufferId): KosmoTabCloseResult =
  result = view.editor.closeTab(id)
  if result.closed:
    view.forgetMarkdownMode(id)
  if result.closed and view.usesBufferSubset:
    let bufferIndex = view.bufferIds.find(id)
    if bufferIndex >= 0:
      view.bufferIds.delete(bufferIndex)
    view.removeViewState(id)
    view.selectedBufferId = none(KosmoBufferId)
  elif not result.closed and not view.statusLabel.isNil:
    view.statusLabel.text = result.message

proc bufferIsVisibleOutside(
    controller: KosmoDockController, source: KosmoEditorGroup, id: KosmoBufferId
): bool =
  for group in controller.groups:
    if group != source and id in group.editorView.bufferIds:
      return true

proc selectVisibleBuffer(view: KosmoEditorView, tabs: openArray[KosmoTab]) =
  if not view.usesBufferSubset:
    return
  view.saveViewState()
  var selectedIsVisible = false
  if view.selectedBufferId.isSome:
    for tab in tabs:
      if tab.id == view.selectedBufferId.get:
        selectedIsVisible = true
        break
  if not selectedIsVisible:
    view.selectedBufferId =
      if tabs.len > 0:
        some(tabs[^1].id)
      else:
        none(KosmoBufferId)
  if view.selectedBufferId.isSome:
    let index = view.viewStateIndex(view.selectedBufferId.get)
    if index >= 0:
      discard view.editor.restoreViewState(view.viewStates[index])
    else:
      discard view.editor.selectTab(view.selectedBufferId.get)

proc adoptActiveBuffer(view: KosmoEditorView) =
  if not view.usesBufferSubset:
    return
  for tab in view.editor.tabs():
    if tab.active:
      if tab.id notin view.bufferIds:
        view.bufferIds.add tab.id
      view.selectedBufferId = some(tab.id)
      view.selectEditorContent(tab.id)
      view.lastTabs.setLen(0)
      return

proc syncTabs(view: KosmoEditorView, tabs: seq[KosmoTab]) =
  let visibleTabs = view.visibleTabs(tabs)
  if view.documentTabs.isNil:
    return
  var editorModels: seq[nimkit.DocumentTabModel]
  for tab in visibleTabs:
    let styleClasses =
      if tab.temporary:
        @[KosmoPreviewTabStyleClass]
      else:
        @[]
    editorModels.add nimkit.initDocumentTabModel(
      identifier = tab.id.tabIdentifier,
      title = tab.title,
      closeable = true,
      modified = tab.modified,
      styleClasses = styleClasses,
      tooltip = tab.filePath.get(tab.title),
    )
  var
    models = editorModels
    selectedIdentifier = ""
  if not view.dockGroup.isNil:
    let group = view.dockGroup[]
    var currentIdentifiers = newSeqOfCap[string](editorModels.len + group.documents.len)
    for model in editorModels:
      currentIdentifiers.add model.identifier
    for document in group.documents:
      currentIdentifiers.add document.identifier

    var reconciledOrder = newSeqOfCap[string](currentIdentifiers.len)
    for identifier in group.tabOrder:
      if identifier in currentIdentifiers and identifier notin reconciledOrder:
        reconciledOrder.add identifier
    for identifier in currentIdentifiers:
      if identifier notin reconciledOrder:
        reconciledOrder.add identifier
    group.tabOrder = reconciledOrder

    models.setLen(0)
    for identifier in group.tabOrder:
      var found = false
      for model in editorModels:
        if model.identifier == identifier:
          models.add model
          found = true
          break
      if not found:
        let document = group.documentForIdentifier(identifier)
        if not document.isNil:
          models.add document.documentTabModel()
    if group.selectedTabIdentifier in currentIdentifiers:
      selectedIdentifier = group.selectedTabIdentifier
    elif currentIdentifiers.len > 0:
      selectedIdentifier = currentIdentifiers[^1]
      group.selectedTabIdentifier = selectedIdentifier
  elif view.usesBufferSubset and view.selectedBufferId.isSome:
    selectedIdentifier = view.selectedBufferId.get.tabIdentifier
  else:
    for tab in visibleTabs:
      if tab.active:
        selectedIdentifier = tab.id.tabIdentifier
        break

  if visibleTabs == view.lastTabs and models == view.documentTabs.documentTabModels() and
      selectedIdentifier == view.documentTabs.selectedDocumentTabIdentifier:
    return
  view.syncingTabs = true
  defer:
    view.syncingTabs = false
  view.documentTabs.documentTabModels = models
  view.documentTabs.selectedDocumentTabIdentifier = selectedIdentifier
  view.lastTabs = visibleTabs

proc isActiveEditorGroup(view: KosmoEditorView): bool =
  if view.tabsDelegate.isNil or view.tabsDelegate.dockController.isNil:
    return true
  let controller = view.tabsDelegate.dockController[]
  controller.activeGroup.isNil or controller.activeGroup.editorView == view

proc syncCommandBar(view: KosmoEditorView, command: KosmoCommandLine) =
  let bar = view.commandBar
  if bar.isNil:
    return
  let visible = command.visible and view.isActiveEditorGroup()
  bar.hidden = not visible
  if not visible:
    return

  var runes: seq[Rune]
  for rune in command.text.runes:
    runes.add rune
  let
    cursor = command.cursor.clamp(0, runes.len)
    columns = max(runes.len, cursor + 1)
    cursorColor = bar.cursorColor()
  var cells = newSeq[nimkit.MonoTextCell](columns)
  for column in 0 ..< columns:
    let rune =
      if column < runes.len:
        runes[column]
      else:
        Rune(' ')
    cells[column] = nimkit.initMonoTextCell(
      rune, backgroundColor = cursorColor, hasBackgroundColor = column == cursor
    )
  bar.replaceGrid(1, columns, cells)

  let metrics = bar.monoTextMetrics()
  if metrics.cellWidth > 0.0'f32:
    let visibleColumns = max(int(floor(bar.bounds().size.width / metrics.cellWidth)), 1)
    let firstColumn = max(cursor - visibleColumns + 1, 0)
    bar.gridOffset = nimkit.initPoint(-firstColumn.float32 * metrics.cellWidth, 0.0'f32)

proc syncChrome(view: KosmoEditorView) =
  let tabs = view.visibleTabs(view.editor.tabs())
  view.syncTabs(tabs)
  if not view.statusLabel.isNil and view.isActiveEditorGroup():
    let text = view.editor.status().statusText(tabs)
    if view.statusLabel.text != text:
      view.statusLabel.text = text
  let command = view.editor.commandLine()
  view.syncCommandBar(command)
  let cursor = view.editor.cursor()
  view.setCursorPosition(cursor.row, cursor.column)
  view.cursorVisible = cursor.visible and not command.visible

func kosmoPaneOutlineColor(base: nimkit.Appearance): nimkit.Color =
  let accentColor = base.resolveColor(
    nimkit.controlStyle(nimkit.srDocumentTab),
    nimkit.StyleMarkColor,
    nimkit.color(0.20, 0.45, 0.92, 1.0),
  )
  nimkit.color(
    accentColor.r, accentColor.g, accentColor.b, accentColor.a * KosmoPaneOutlineOpacity
  )

proc installKosmoPaneIndicatorStyle(
    appearance: var nimkit.Appearance, base: nimkit.Appearance
) =
  let selector = nimkit.initStyleSelector(nimkit.srBox, id = KosmoPaneIndicatorStyleId)
  appearance.setStyle(selector, nimkit.StyleBorderColor, base.kosmoPaneOutlineColor())
  appearance.setStyle(selector, nimkit.StyleBorderWidth, KosmoPaneOutlineWidth)
  appearance.setStyle(selector, nimkit.StyleCornerRadius, 0.0'f32)

proc installKosmoMarkdownControlsStyle(appearance: var nimkit.Appearance) =
  let
    controlsSelector =
      nimkit.initStyleSelector(nimkit.srBox, id = KosmoMarkdownControlsStyleId)
    buttonSelector = nimkit.initStyleSelector(
      nimkit.srButton, classes = @[KosmoMarkdownControlButtonStyleClass]
    )
  appearance.setStyle(controlsSelector, nimkit.StylePadding, nimkit.insets(4.0'f32))
  appearance.setStyle(controlsSelector, nimkit.StyleCornerRadius, 8.0'f32)
  appearance.setStyle(
    controlsSelector,
    nimkit.StyleBoxShadows,
    @[nimkit.dropShadow(nimkit.color(0.0, 0.0, 0.0, 0.28), y = 2.0, blur = 7.0)],
  )
  appearance.setStyle(
    buttonSelector, nimkit.StyleTextInsets, nimkit.insets(0.0'f32, 2.0'f32)
  )

proc refresh*(view: KosmoEditorView)

proc applyKosmoEditorStyle(view: KosmoEditorView, base: nimkit.Appearance) =
  var appearance = base
  let
    selector = nimkit.initStyleSelector(nimkit.srMonoTextView, id = KosmoEditorStyleId)
    previewTabSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTab, classes = @[KosmoPreviewTabStyleClass]
    )
    inactiveTabSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTab,
      {nimkit.ssSelected},
      classes = @[KosmoInactivePaneStyleClass],
    )
    tabContext = nimkit.controlStyle(nimkit.srDocumentTab)
    cursorColor =
      base.resolveMonoTextStyle(nimkit.controlStyle(nimkit.srMonoTextView)).cursorColor
    accentColor = base.resolveColor(
      tabContext, nimkit.StyleMarkColor, nimkit.color(0.20, 0.45, 0.92, 1.0)
    )
    normalTabFill =
      base.resolveFill(tabContext, nimkit.fill(nimkit.color(0.16, 0.18, 0.22, 1.0)))
    normalTabTextColor = base.resolveColor(
      tabContext, nimkit.StyleTextColor, nimkit.color(0.72, 0.74, 0.80, 1.0)
    )
    inactiveAccentColor = nimkit.color(
      accentColor.r,
      accentColor.g,
      accentColor.b,
      accentColor.a * KosmoInactiveTabAccentOpacity,
    )
    inactiveTabTextColor = nimkit.color(
      normalTabTextColor.r,
      normalTabTextColor.g,
      normalTabTextColor.b,
      normalTabTextColor.a * KosmoInactiveTabTextOpacity,
    )
  appearance.setStyle(
    selector,
    nimkit.StyleCursorColor,
    nimkit.color(cursorColor.r, cursorColor.g, cursorColor.b, KosmoCursorOpacity),
  )
  appearance.setStyle(selector, nimkit.StyleFocusRingWidth, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleFocusRingInset, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadius, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadiusTopLeft, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadiusTopRight, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadiusBottomLeft, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadiusBottomRight, 0.0'f32)
  appearance.setStyle(
    previewTabSelector, nimkit.StyleFontSlant, nimkit.styleKeyword(nimkit.fsItalic)
  )
  appearance.setStyle(inactiveTabSelector, nimkit.StyleFill, normalTabFill)
  appearance.setStyle(inactiveTabSelector, nimkit.StyleTextColor, inactiveTabTextColor)
  appearance.setStyle(
    inactiveTabSelector,
    nimkit.StyleSelectionIndicatorFill,
    nimkit.fill(inactiveAccentColor),
  )
  appearance.installKosmoPaneIndicatorStyle(base)
  appearance.installKosmoMarkdownControlsStyle()
  view.styleId = KosmoEditorStyleId
  view.appearance = appearance
  if not view.documentTabs.isNil:
    view.documentTabs.appearance = appearance
  if not view.commandBar.isNil:
    view.commandBar.appearance = appearance
  if not view.dockGroup.isNil:
    let pane = view.dockGroup[].pane
    if not pane.activeIndicator.isNil:
      pane.activeIndicator.appearance = appearance
    if not pane.markdownControls.isNil:
      pane.markdownControls.syncMarkdownColorMode(base)
      pane.markdownControls.appearance = appearance

protocol KosmoEditorAppearanceObserver of nimkit.WindowAppearanceEvents:
  proc didChangeEffectiveAppearance(
      handler: KosmoEditorTabsHandler, appearance: nimkit.Appearance
  ) {.slot.} =
    if not handler.editorView.isNil:
      handler.editorView[].applyKosmoEditorStyle(appearance)
      handler.editorView[].refresh()

protocol KosmoEditorFocusObserver of nimkit.WindowFocusEvents:
  proc didChangeFirstResponder(
      handler: KosmoEditorTabsHandler, previous: nimkit.Responder
  ) {.slot.} =
    discard previous
    if handler.editorView.isNil or handler.dockController.isNil:
      return
    let
      view = handler.editorView[]
      controller = handler.dockController[]
    if view.dockGroup.isNil:
      return
    let group = view.dockGroup[]
    var responder = group.window.firstResponder()
    while not responder.isNil:
      if responder == nimkit.Responder(group.pane):
        controller.activateGroup(view)
        return
      responder = responder.nextResponder()

proc stopObservingWindow(handler: KosmoEditorTabsHandler) =
  if handler.isNil or handler.appearanceWindow.isNil:
    return
  handler.unobserveProtocol(handler.appearanceWindow[], nimkit.WindowAppearanceEvents)
  handler.unobserveProtocol(handler.appearanceWindow[], nimkit.WindowFocusEvents)
  handler.appearanceWindow = default(WeakRef[nimkit.Window])

proc observeAppearance(handler: KosmoEditorTabsHandler, window: nimkit.Window) =
  handler.stopObservingWindow()
  if window.isNil:
    return
  handler.appearanceWindow = window.unsafeWeakRef()
  handler.observeProtocol(window, nimkit.WindowAppearanceEvents)
  handler.observeProtocol(window, nimkit.WindowFocusEvents)

proc syncSelectedEditorContent(
    view: KosmoEditorView, tabs: openArray[KosmoTab]
): KosmoEditorContentKind =
  if view.dockGroup.isNil:
    return keckSyntax
  let group = view.dockGroup[]
  var selectedId: KosmoBufferId
  if not group.selectedTabIdentifier.parseTabIdentifier(selectedId):
    group.pane.syncMarkdownControls(false)
    return keckOther
  for tab in tabs:
    if tab.id != selectedId:
      continue
    if not tab.isMarkdownTab:
      group.pane.syncMarkdownControls(false)
      group.pane.setContentView(view)
      return keckSyntax
    let mode = view.markdownMode(selectedId)
    group.pane.syncMarkdownControls(true, mode)
    if mode == kmmPreview:
      let source = view.editor.bufferText(selectedId)
      if source.isNone:
        group.pane.setContentView(view)
        return keckSyntax
      group.pane.markdownView.imageBasePath = tab.filePath.get.parentDir
      group.pane.markdownView.markdownStyle =
        group.pane.markdownControls.markdownPresentationStyle()
      group.pane.markdownView.markdown = source.get
      group.pane.setContentView(group.pane.markdownView)
      return keckMarkdownPreview
    group.pane.setContentView(view)
    return keckSyntax
  group.pane.syncMarkdownControls(false)
  keckOther

proc refresh*(view: KosmoEditorView) =
  ## Render the current editor state into the synchronous cell-grid view.
  if (view.editor.completionPopupVisible() or view.editor.commandLine().visible) and
      not view.isActiveEditorGroup():
    return
  let tabs = view.visibleTabs(view.editor.tabs())
  view.selectVisibleBuffer(tabs)
  case view.syncSelectedEditorContent(tabs)
  of keckMarkdownPreview:
    view.syncChrome()
    view.cursorVisible = false
    if not view.commandBar.isNil:
      view.commandBar.hidden = true
    return
  of keckOther:
    view.syncChrome()
    return
  of keckSyntax:
    discard
  let metrics = view.monoTextMetrics()
  if metrics.cellWidth <= 0.0'f32 or metrics.lineHeight <= 0.0'f32:
    return
  let
    bounds = view.bounds()
    columns = max(int(ceil(bounds.size.width / metrics.cellWidth)), 1)
    rows = max(
      int(ceil(bounds.size.height / metrics.lineHeight)) + KosmoGridOverscanRows +
        KosmoMoeBottomAreaRows,
      1,
    )
  if view.renderBuffer.width != columns or view.renderBuffer.height != rows:
    view.renderBuffer.resize(columns.Natural, rows.Natural)
  view.editor.render(view.renderBuffer, view.editor.captureViewState())
  view.saveViewState()
  var cells = newSeq[nimkit.MonoTextCell](rows * columns)
  for row in 0 ..< rows:
    for column in 0 ..< columns:
      cells[row * columns + column] = view.renderBuffer.cell(column, row).toMonoTextCell
  view.replaceGrid(rows, columns, cells)
  view.gridOffset =
    nimkit.initPoint(0.0'f32, -view.scrollOffsetRows * metrics.lineHeight)
  view.syncChrome()

proc toggleMarkdownMode(view: KosmoEditorView, id: KosmoBufferId): bool =
  for tab in view.editor.tabs():
    if tab.id != id or not tab.isMarkdownTab:
      continue
    if view.markdownMode(id) == kmmPreview:
      view.markdownSyntaxBufferIds.add id
    else:
      view.forgetMarkdownMode(id)
    view.lastTabs.setLen(0)
    view.refresh()
    return true

proc openFile*(view: KosmoEditorView, path: string): bool {.discardable.} =
  ## Load a file selected by the frontend and refresh the cell grid.
  view.saveViewState()
  let outcome = view.editor.openFile(path)
  if outcome.loaded:
    view.adoptActiveBuffer()
    view.refresh()
    return true
  if not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message

proc previewFile*(view: KosmoEditorView, path: string): bool {.discardable.} =
  ## Load `path` as the replaceable file-tree preview and refresh the grid.
  view.saveViewState()
  let outcome = view.editor.previewFile(path)
  if outcome.loaded:
    view.adoptActiveBuffer()
    view.refresh()
    return true
  if not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message

proc bufferColumn(match: nimkit.FileSearchMatch): int =
  let byteColumn = clamp(match.column - 1, 0, match.lineText.len)
  if byteColumn > 0:
    result = match.lineText[0 ..< byteColumn].runeLen

proc openSearchResult(
    view: KosmoEditorView,
    match: nimkit.FileSearchMatch,
    disposition: FileTreeOpenDisposition,
): bool =
  view.saveViewState()
  let outcome =
    case disposition
    of fodTemporary:
      view.editor.previewFile(match.path)
    of fodPermanent:
      view.editor.openFile(match.path)
  if outcome.loaded:
    view.adoptActiveBuffer()
    discard view.editor.revealLocation(
      max(match.line - 1, 0), match.bufferColumn(), centered = true
    )
    view.refresh()
    return true
  if not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message

proc scrollBy*(
    view: KosmoEditorView,
    deltaY: float32,
    row = 0,
    column = 0,
    modifiers: set[nimkit.KeyModifier] = {},
): ScrollOutcome =
  ## Translate fractional wheel input and accelerate Control-modified scrolling.
  view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
  let multiplier =
    if nimkit.kmControl in modifiers: KosmoControlScrollMultiplier else: 1.0'f32
  view.scrollOffsetRows -= deltaY * multiplier
  let rows = int(floor(view.scrollOffsetRows))
  if rows == 0:
    result.handled = true
    let metrics = view.monoTextMetrics()
    view.gridOffset =
      nimkit.initPoint(0.0'f32, -view.scrollOffsetRows * metrics.lineHeight)
    return
  view.scrollOffsetRows -= rows.float32
  result = view.editor.handleScrollInput(
    initScrollInput(row, column, rows, modifiers.toMoeModifiers)
  )
  if result.appliedRows != rows:
    view.scrollOffsetRows = 0.0'f32
  view.refresh()

proc closeCurrentTab(controller: KosmoDockController, view: KosmoEditorView)
proc finishTabClose(controller: KosmoDockController, view: KosmoEditorView)
proc saveCurrentTab(controller: KosmoDockController, view: KosmoEditorView)
proc selectRelativeTab(
  controller: KosmoDockController, view: KosmoEditorView, offset: int
)

proc activatePaneTab(
  controller: KosmoDockController,
  group: KosmoEditorGroup,
  identifier: string,
  focus = true,
)

proc closeCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup)

proc saveCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup)

proc removeBuffer(group: KosmoEditorGroup, id: KosmoBufferId)

proc openPaneDocument(
  controller: KosmoDockController, group: KosmoEditorGroup, document: KosmoPaneDocument
): bool

proc selectRelativePaneTab(
  controller: KosmoDockController, group: KosmoEditorGroup, offset: int
)

proc updateDockTarget(
  controller: KosmoDockController, tabs: nimkit.DocumentTabs, location: nimkit.Point
)

proc finishDockDrag(
  controller: KosmoDockController,
  tabs: nimkit.DocumentTabs,
  item: nimkit.DocumentTabItem,
  location: nimkit.Point,
)

proc sendKeyDownToMoe(view: KosmoEditorView, keyEvent: nimkit.KeyEvent): bool =
  var keyOutcome: KosmoKeyOutcome
  if keyEvent.key == nimkit.keyEnter:
    keyOutcome = view.editor.handleKeyOutcome("Enter")
  elif keyEvent.text.len > 0 and keyEvent.modifiers - {nimkit.kmShift} == {}:
    discard view.editor.handleTextInput(keyEvent.text)
  elif keyEvent.awaitsCommittedText():
    return false
  else:
    let notation = keyEvent.keyNotation()
    if notation.len > 0:
      keyOutcome = view.editor.handleKeyOutcome(notation)
  if keyOutcome.closeTabRequested and not view.tabsDelegate.dockController.isNil:
    view.tabsDelegate.dockController[].closeCurrentTab(view)
    return true
  view.refresh()
  true

proc paneCommand(event: nimkit.KeyEvent): KosmoPaneCommand =
  let modifiers = event.modifiers
  if modifiers - {nimkit.kmControl, nimkit.kmShift} != {}:
    return
  if event.key >= nimkit.keyA and event.key <= nimkit.keyZ:
    let letter = char(ord('a') + ord(event.key) - ord(nimkit.keyA))
    case letter
    of 's':
      if nimkit.kmShift notin modifiers:
        return kpcSplitBelow
    of 'v':
      if nimkit.kmShift notin modifiers:
        return kpcSplitRight
    of 'n':
      if nimkit.kmShift notin modifiers:
        return kpcNewBelow
    of 'w':
      if nimkit.kmShift notin modifiers:
        return kpcFocusNext
    of 'h':
      if nimkit.kmShift notin modifiers:
        return kpcFocusLeft
    of 'j':
      if nimkit.kmShift notin modifiers:
        return kpcFocusBelow
    of 'k':
      if nimkit.kmShift notin modifiers:
        return kpcFocusAbove
    of 'l':
      if nimkit.kmShift notin modifiers:
        return kpcFocusRight
    of 'c':
      if nimkit.kmShift notin modifiers:
        return kpcClose
    else:
      discard
    return
  case event.key
  of nimkit.keyEqual:
    if nimkit.kmShift in modifiers or event.text == "+": kpcGrowHeight else: kpcEqualize
  of nimkit.keyMinus:
    kpcShrinkHeight
  of nimkit.keyComma:
    if nimkit.kmShift in modifiers or event.text == "<": kpcShrinkWidth else: kpcNone
  of nimkit.keyDot:
    if nimkit.kmShift in modifiers or event.text == ">": kpcGrowWidth else: kpcNone
  else:
    kpcNone

proc handlePendingPaneKey(view: KosmoEditorView, event: nimkit.KeyEvent): bool =
  if not view.pendingPanePrefix:
    return false
  view.pendingPanePrefix = false
  if event.key == nimkit.keyEscape:
    return true
  let command = event.paneCommand()
  if command != kpcNone and not view.tabsDelegate.dockController.isNil and
      not view.dockGroup.isNil:
    discard
      view.tabsDelegate.dockController[].performPaneCommand(view.dockGroup[], command)
    return true

  # Preserve Moe mappings for continuations Kosmo does not claim.
  discard view.editor.handleKeyOutcome("C-w")
  discard view.sendKeyDownToMoe(event)
  true

proc handleMarkdownPaneKey(view: KosmoMarkdownView, event: nimkit.KeyEvent): bool =
  ## Route scoped pane commands from a focused Markdown preview.
  if view.isNil or view.editorView.isNil:
    return false
  let editorView = view.editorView[]
  if editorView.tabsDelegate.isNil or editorView.tabsDelegate.dockController.isNil or
      editorView.dockGroup.isNil:
    return false
  if editorView.pendingPanePrefix:
    editorView.pendingPanePrefix = false
    if event.key == nimkit.keyEscape:
      return true
    let command = event.paneCommand()
    if command != kpcNone:
      discard editorView.tabsDelegate.dockController[].performPaneCommand(
        editorView.dockGroup[], command
      )
      return true
    return false
  if event.key == nimkit.keyForText("w") and event.modifiers == {nimkit.kmControl}:
    editorView.pendingPanePrefix = true
    return true
  false

proc handleRawEvent(view: KosmoEditorView, event: nimkit.MonoTextRawEvent): bool =
  if event.kind == nimkit.mtreMouseDown and not view.tabsDelegate.dockController.isNil:
    view.tabsDelegate.dockController[].activateGroup(view)
  view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
  case event.kind
  of nimkit.mtreMouseDown, nimkit.mtreMouseDragged, nimkit.mtreMouseUp:
    if event.kind == nimkit.mtreMouseDown:
      let window = view.window()
      if window of nimkit.Window:
        discard nimkit.Window(window).makeFirstResponder(view)
    let action =
      case event.kind
      of nimkit.mtreMouseDown: paPress
      of nimkit.mtreMouseDragged: paDrag
      of nimkit.mtreMouseUp: paRelease
      else: paMove
    discard view.editor.handlePointerInput(
      initPointerInput(
        event.row,
        event.column,
        event.mouseEvent.button.toPointerButton,
        action,
        max(event.mouseEvent.clickCount, 1).Natural,
        event.mouseEvent.modifiers.toMoeModifiers,
      )
    )
    view.refresh()
    true
  of nimkit.mtreScrollWheel:
    discard view.scrollBy(
      event.scrollEvent.deltaY, event.row, event.column, event.scrollEvent.modifiers
    )
    true
  of nimkit.mtreKeyDown:
    let keyEvent = event.keyEvent
    if view.handlePendingPaneKey(keyEvent):
      return true
    view.sendKeyDownToMoe(keyEvent)
  of nimkit.mtreFlagsChanged:
    true

protocol KosmoEditorInput of nimkit.TextInputProtocol:
  method insertText(view: KosmoEditorView, text: string) =
    if text.len > 0:
      view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
      discard view.editor.handleTextInput(text)
      view.refresh()

proc editorCopy(view: KosmoEditorView) =
  if view.editor.currentSelection().isSome:
    discard nimkit.generalPasteboard().setPlainText(view.editor.copySelection())
    view.refresh()

proc editorCut(view: KosmoEditorView) =
  if view.editor.currentSelection().isSome:
    discard nimkit.generalPasteboard().setPlainText(view.editor.cutSelection())
    view.refresh()

proc editorPaste(view: KosmoEditorView) =
  discard view.editor.handlePaste(nimkit.generalPasteboard().plainText())
  view.refresh()

protocol KosmoEditorEditingCommands of nimkit.TextEditingCommandProtocol:
  method copy(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    view.editorCopy()

  method cut(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    view.editorCut()

  method paste(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    view.editorPaste()

  method selectAll(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    discard view.editor.selectAll()
    view.refresh()

  method undo(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    discard view.editor.undo()
    view.refresh()

  method redo(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    discard view.editor.redo()
    view.refresh()

func isEditingAction(action: string): bool =
  action.kosmoAction().kind == KosmoActionKind.Editing

proc handleKosmoKeyEquivalent(view: KosmoEditorView, event: nimkit.KeyEvent): bool =
  if view.handlePendingPaneKey(event):
    return true
  if view.tabsDelegate.isNil or view.tabsDelegate.dockController.isNil:
    return false
  let controller = view.tabsDelegate.dockController[]
  if event.key == nimkit.keyTab and event.modifiers - {nimkit.kmShift} == {} and
      view.editor.mode() in {KosmoEditorMode.Insert, KosmoEditorMode.Replace}:
    return view.sendKeyDownToMoe(event)
  if event.key == nimkit.keyForText("w") and event.modifiers == {nimkit.kmControl} and
      controller.editorInputPolicy != KosmoEditorInputPolicy.Native:
    if view.editor.mode() == KosmoEditorMode.Normal:
      view.pendingPanePrefix = true
      return true
    return view.sendKeyDownToMoe(event)

  let selector = controller.shortcutBindings.commandFor(event)
  if selector.isNone or not ($selector.get.name).isEditingAction():
    return false
  let sendToMoe =
    case controller.editorInputPolicy
    of KosmoEditorInputPolicy.Vim:
      true
    of KosmoEditorInputPolicy.Native:
      false
    of KosmoEditorInputPolicy.Hybrid:
      view.editor.mode() notin
        {KosmoEditorMode.Insert, KosmoEditorMode.Replace, KosmoEditorMode.Visual}
  if sendToMoe:
    return view.sendKeyDownToMoe(event)
  false

protocol KosmoEditorCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(view: KosmoEditorView, args: nimkit.TryToPerformArgs): bool =
    if view.tabsDelegate.isNil or view.tabsDelegate.dockController.isNil:
      return false
    let controller = view.tabsDelegate.dockController[]
    let panelNumber = args.selector.focusPanelNumber()
    if panelNumber > 0:
      discard controller.focusPanel(panelNumber)
      return true
    case $args.selector.name
    of KosmoNewFileAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].newEditorTab()
    of KosmoOpenFileAction:
      if not controller.frontend.isNil:
        controller.frontend[].chooseFile()
    of KosmoOpenProjectAction:
      if not controller.frontend.isNil and not controller.frontend[].xWindowManager.isNil:
        controller.frontend[].xWindowManager[].chooseProject()
    of KosmoQuickOpenAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showQuickOpen()
    of KosmoNewTerminalAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].newTerminal()
    of KosmoSaveAction:
      controller.saveCurrentTab(view)
    of KosmoCloseTabAction:
      controller.closeCurrentTab(view)
    of KosmoCloseWindowAction:
      let group = controller.groupForView(view)
      if not group.isNil:
        group.window.close()
    of KosmoQuitAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].application.terminate()
    of KosmoPreviousTabAction:
      controller.selectRelativeTab(view, -1)
    of KosmoNextTabAction:
      controller.selectRelativeTab(view, 1)
    of KosmoSplitHorizontalAction:
      discard
        controller.splitCurrentPaneTab(controller.groupForView(view), nimkit.dpBottom)
    of KosmoSplitVerticalAction:
      discard
        controller.splitCurrentPaneTab(controller.groupForView(view), nimkit.dpRight)
    of KosmoShowFileExplorerAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFileExplorer()
    of KosmoFindInFilesAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFindInFiles()
    of KosmoShowSettingsAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showSettings()
    of KosmoCopyAction:
      view.editorCopy()
    of KosmoCutAction:
      view.editorCut()
    of KosmoPasteAction:
      view.editorPaste()
    of KosmoSelectAllAction:
      discard view.editor.selectAll()
      view.refresh()
    of KosmoUndoAction:
      discard view.editor.undo()
      view.refresh()
    of KosmoRedoAction:
      discard view.editor.redo()
      view.refresh()
    else:
      return false
    true

proc targetView(handler: KosmoEditorTabsHandler): KosmoEditorView =
  if not handler.editorView.isNil:
    return handler.editorView[]

protocol KosmoEditorTabsDelegate of nimkit.DocumentTabsDelegate:
  method didSelectDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
  ) =
    discard tabs
    let view = handler.targetView()
    if view.isNil:
      return
    if view.syncingTabs:
      return
    if not handler.dockController.isNil and not view.dockGroup.isNil:
      handler.dockController[].activatePaneTab(view.dockGroup[], item.identifier())
      return
    var id: KosmoBufferId
    if item.identifier.parseTabIdentifier(id):
      view.saveViewState()
      view.editor.dismissCompletionPopup()
      view.editor.dismissCommandLine()
      if view.usesBufferSubset:
        view.selectedBufferId = some(id)
      if not handler.dockController.isNil:
        handler.dockController[].activateGroup(view)
      if view.usesBufferSubset:
        view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
      elif not view.editor.selectTab(id):
        view.lastTabs.setLen(0)
      view.refresh()

  method didDoubleClickDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
  ) =
    discard tabs
    let view = handler.targetView()
    if view.isNil or view.syncingTabs:
      return
    var id: KosmoBufferId
    if not item.identifier.parseTabIdentifier(id):
      return
    for tab in view.editor.tabs():
      if tab.id == id and tab.temporary and tab.filePath.isSome:
        discard view.openFile(tab.filePath.get)
        return

  method shouldCloseDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
      index: int,
  ): bool =
    discard tabs
    discard index
    let view = handler.targetView()
    if view.isNil:
      return
    if view.syncingTabs:
      return
    var id: KosmoBufferId
    if item.identifier.parseTabIdentifier(id):
      if not handler.dockController.isNil and not view.dockGroup.isNil:
        let
          controller = handler.dockController[]
          group = view.dockGroup[]
        if controller.bufferIsVisibleOutside(group, id):
          group.removeBuffer(id)
          return true
      let outcome = view.closeTab(id)
      return outcome.closed
    if view.dockGroup.isNil:
      return
    let
      group = view.dockGroup[]
      documentIndex = group.documentIndex(item.identifier())
    if documentIndex < 0 or not group.documents[documentIndex].close():
      return
    group.documents.delete(documentIndex)
    let orderIndex = group.tabOrder.find(item.identifier())
    if orderIndex >= 0:
      group.tabOrder.delete(orderIndex)
    true

  method didCloseDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
      index: int,
  ) =
    discard tabs
    discard item
    discard index
    let view = handler.targetView()
    if not view.isNil:
      if handler.dockController.isNil:
        view.refresh()
      else:
        handler.dockController[].finishTabClose(view)

  method didMoveDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
      fromIndex: int,
      toIndex: int,
  ) =
    discard tabs
    discard fromIndex
    let view = handler.targetView()
    if view.isNil:
      return
    var id: KosmoBufferId
    if not view.dockGroup.isNil:
      let group = view.dockGroup[]
      let orderIndex = group.tabOrder.find(item.identifier())
      if orderIndex >= 0:
        group.tabOrder.delete(orderIndex)
        group.tabOrder.insert(item.identifier(), min(toIndex, group.tabOrder.len))
      if item.identifier.parseTabIdentifier(id) and view.usesBufferSubset:
        var bufferIds: seq[KosmoBufferId]
        for identifier in group.tabOrder:
          var bufferId: KosmoBufferId
          if identifier.parseTabIdentifier(bufferId):
            bufferIds.add bufferId
        view.bufferIds = bufferIds
        view.syncEditorTabOrder()
    elif item.identifier.parseTabIdentifier(id):
      if not view.editor.moveTab(id, toIndex.Natural):
        view.lastTabs.setLen(0)
    view.refresh()

  method didBeginDraggingDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      info: nimkit.DocumentTabDragInfo,
  ) =
    if not handler.dockController.isNil:
      handler.dockController[].updateDockTarget(tabs, info.location)

  method didDragDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      info: nimkit.DocumentTabDragInfo,
  ) =
    if not handler.dockController.isNil:
      handler.dockController[].updateDockTarget(tabs, info.location)

  method didEndDraggingDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      info: nimkit.DocumentTabDragInfo,
  ) =
    if not handler.dockController.isNil:
      handler.dockController[].finishDockDrag(tabs, info.item, info.location)

proc newKosmoEditorView*(editor = newKosmoEditor()): KosmoEditorView =
  result = KosmoEditorView(
    editor: editor,
    documentTabs: nimkit.newDocumentTabs(),
    renderBuffer: newRenderBuffer(80, 24),
  )
  result.initMonoTextViewFields(editable = true)
  result.clipsToBounds = true
  result.padding = 0.0'f32
  result.fontName = nimkit.DefaultMonoFontName
  result.fontSize = 14.0'f32
  result.textColor = nimkit.color(0.88, 0.9, 0.94, 1.0)
  result.backgroundColor = nimkit.color(0.04, 0.05, 0.07, 1.0)
  result.applyKosmoEditorStyle(result.effectiveAppearance())
  result.rawEventPolicy = nimkit.initMonoTextRawEventPolicy(
    capturedEvents = nimkit.AllMonoTextRawEvents - {nimkit.mtreKeyDown}
  )
  let editorView = result
  result.rawEventHandler = proc(event: nimkit.MonoTextRawEvent): bool =
    editorView.handleRawEvent(event)
  discard result.withProtocol(KosmoEditorInput)
  discard result.withProtocol(KosmoEditorEditingCommands)
  discard result.withProtocol(KosmoEditorCommandDispatch)
  let keyEquivalentMethod: nimkit.DynamicMethod = proc(
      self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
  ) =
    let event = invocation.argsAs(nimkit.KeyEvent)
    invocation.setResult(KosmoEditorView(self).handleKosmoKeyEquivalent(event))
  discard
    result.replaceMethod(nimkitSelectors.performKeyEquivalent(), keyEquivalentMethod)
  result.tabsDelegate = KosmoEditorTabsHandler(editorView: result.unsafeWeakRef())
  discard result.tabsDelegate.withProtocol(KosmoEditorTabsDelegate)
  result.documentTabs.delegate = result.tabsDelegate
  result.syncChrome()

protocol KosmoCommandBarHitTesting of nimkit.ViewProtocol:
  method pointInside(bar: KosmoCommandBar, point: nimkit.Point): bool =
    discard bar
    discard point

proc newKosmoCommandBar(view: KosmoEditorView): KosmoCommandBar =
  result = KosmoCommandBar()
  result.initMonoTextViewFields()
  result.clipsToBounds = true
  result.padding = 0.0'f32
  result.fontName = view.fontName()
  result.fontSize = view.fontSize()
  result.textColor = nimkit.color(0.88, 0.9, 0.94, 1.0)
  result.cursorVisible = false
  result.styleId = KosmoEditorStyleId
  result.appearance = view.effectiveAppearance()
  result.hidden = true
  discard result.withProtocol(KosmoCommandBarHitTesting)

protocol KosmoPaneIndicatorDrawing of nimkit.ViewDrawingProtocol:
  method draw(indicator: KosmoPaneIndicator, context: nimkit.DrawContext) =
    let bounds = indicator.bounds()
    if bounds.isEmpty:
      return
    let
      styleContext = nimkit.controlStyle(nimkit.srBox, id = KosmoPaneIndicatorStyleId)
      outlineColor = context.appearance.resolveColor(
        styleContext,
        nimkit.StyleBorderColor,
        nimkit.color(0.20, 0.45, 0.92, KosmoPaneOutlineOpacity),
      )
      outlineWidth = context.appearance.resolveLength(
        styleContext, nimkit.StyleBorderWidth, KosmoPaneOutlineWidth
      )
      cornerRadius = context.appearance.resolveLength(
        styleContext, nimkit.StyleCornerRadius, 0.0'f32
      )
      inset = outlineWidth * 0.5'f32
      outlineRect = nimkit.rect(
        bounds.minX + inset,
        bounds.minY + inset,
        max(bounds.size.width - outlineWidth, 0.0'f32),
        max(bounds.size.height - outlineWidth, 0.0'f32),
      )
    discard context.addRenderRectangle(
      context.renderRectFor(outlineRect),
      nimkit.fill(nimkit.color(0.0, 0.0, 0.0, 0.0)),
      outlineColor,
      outlineWidth,
      cornerRadius,
    )

protocol KosmoPaneIndicatorHitTesting of nimkit.ViewProtocol:
  method pointInside(indicator: KosmoPaneIndicator, point: nimkit.Point): bool =
    discard indicator
    discard point

proc newKosmoPaneIndicator(): KosmoPaneIndicator =
  result = KosmoPaneIndicator()
  result.initViewFields()
  result.background = nimkit.color(0.0, 0.0, 0.0, 0.0)
  result.styleId = KosmoPaneIndicatorStyleId
  result.hidden = true
  discard result.withProtocol(KosmoPaneIndicatorDrawing)
  discard result.withProtocol(KosmoPaneIndicatorHitTesting)

proc selectedMarkdownBufferId(controls: KosmoMarkdownControls): Option[KosmoBufferId] =
  if controls.isNil or controls.editorView.isNil:
    return
  let view = controls.editorView[]
  if view.dockGroup.isNil:
    return
  var id: KosmoBufferId
  if not view.dockGroup[].selectedTabIdentifier.parseTabIdentifier(id):
    return
  for tab in view.editor.tabs():
    if tab.id == id and tab.isMarkdownTab:
      return some(id)

proc focusMarkdownContent(controls: KosmoMarkdownControls) =
  if controls.isNil or controls.editorView.isNil:
    return
  let view = controls.editorView[]
  if view.dockGroup.isNil:
    return
  let group = view.dockGroup[]
  if not group.window.isNil:
    discard group.window.makeFirstResponder(nimkit.Responder(group.pane.contentView))

proc toggleSelectedMarkdownMode(controls: KosmoMarkdownControls) =
  let id = controls.selectedMarkdownBufferId()
  if id.isNone or controls.editorView.isNil:
    return
  if controls.editorView[].toggleMarkdownMode(id.get):
    controls.focusMarkdownContent()

proc toggleMarkdownColorMode(controls: KosmoMarkdownControls) =
  if controls.isNil:
    return
  controls.xColorMode = if controls.xColorMode == kmcmLight: kmcmDark else: kmcmLight
  if not controls.editorView.isNil:
    controls.editorView[].refresh()

proc changeMarkdownFontSize(controls: KosmoMarkdownControls, delta: float32) =
  if controls.isNil:
    return
  let nextSize = clamp(
    controls.xFontSize + delta,
    KosmoMarkdownMinimumFontSize,
    KosmoMarkdownMaximumFontSize,
  )
  if abs(nextSize - controls.xFontSize) <= 0.001'f32:
    return
  controls.xFontSize = nextSize
  if not controls.editorView.isNil:
    controls.editorView[].refresh()

proc newKosmoMarkdownControls(view: KosmoEditorView): KosmoMarkdownControls =
  let
    colorMode = view.effectiveAppearance().markdownColorMode()
    modeButton = nimkit.newButton("</>")
    colorModeButton = nimkit.newButton(if colorMode == kmcmLight: "Dark" else: "Light")
    decreaseFontButton = nimkit.newButton("-")
    increaseFontButton = nimkit.newButton("+")
    row = nimkit.newStackView(nimkit.laHorizontal)
  result = KosmoMarkdownControls(
    modeButton: modeButton,
    colorModeButton: colorModeButton,
    decreaseFontButton: decreaseFontButton,
    increaseFontButton: increaseFontButton,
    editorView: view.unsafeWeakRef(),
    xColorMode: colorMode,
    xThemeColorMode: colorMode,
    xFontSize: KosmoMarkdownDefaultFontSize,
  )
  result.initBoxFields()
  result.styleId = KosmoMarkdownControlsStyleId
  result.accessibilityLabel = "Markdown preview controls"
  result.hidden = true

  modeButton.reservedTitles = ["</>", "MD"]
  modeButton.accessibilityLabel = "Edit Markdown source"
  modeButton.toolTip = "Edit Markdown source"
  colorModeButton.reservedTitles = ["Dark", "Light"]
  result.syncMarkdownColorButton()
  decreaseFontButton.accessibilityLabel = "Decrease Markdown font size"
  decreaseFontButton.toolTip = "Decrease Markdown font size"
  increaseFontButton.accessibilityLabel = "Increase Markdown font size"
  increaseFontButton.toolTip = "Increase Markdown font size"
  for button in [modeButton, colorModeButton, decreaseFontButton, increaseFontButton]:
    button.addStyleClass(KosmoMarkdownControlButtonStyleClass)

  row.spacing = 2.0'f32
  row.distribution = nimkit.svdFillEqually
  row.addArrangedSubview(
    modeButton, colorModeButton, decreaseFontButton, increaseFontButton
  )
  result.contentView = row

  let weakControls = result.unsafeWeakRef()
  let modeAction = nimkit.actionSelector("kosmo.toggleMarkdownMode")
  modeButton.target = nimkit.newActionTarget(
    modeAction,
    proc(sender: nimkit.DynamicAgent) =
      discard sender
      if not weakControls.isNil:
        weakControls[].toggleSelectedMarkdownMode()
    ,
  )
  modeButton.action = modeAction

  let colorModeAction = nimkit.actionSelector("kosmo.toggleMarkdownColorMode")
  colorModeButton.target = nimkit.newActionTarget(
    colorModeAction,
    proc(sender: nimkit.DynamicAgent) =
      discard sender
      if not weakControls.isNil:
        weakControls[].toggleMarkdownColorMode()
    ,
  )
  colorModeButton.action = colorModeAction

  let decreaseFontAction = nimkit.actionSelector("kosmo.decreaseMarkdownFontSize")
  decreaseFontButton.target = nimkit.newActionTarget(
    decreaseFontAction,
    proc(sender: nimkit.DynamicAgent) =
      discard sender
      if not weakControls.isNil:
        weakControls[].changeMarkdownFontSize(-KosmoMarkdownFontSizeIncrement)
    ,
  )
  decreaseFontButton.action = decreaseFontAction

  let increaseFontAction = nimkit.actionSelector("kosmo.increaseMarkdownFontSize")
  increaseFontButton.target = nimkit.newActionTarget(
    increaseFontAction,
    proc(sender: nimkit.DynamicAgent) =
      discard sender
      if not weakControls.isNil:
        weakControls[].changeMarkdownFontSize(KosmoMarkdownFontSizeIncrement)
    ,
  )
  increaseFontButton.action = increaseFontAction

proc applyKosmoSidebarStyle(pane: KosmoSidebarPane, base: nimkit.Appearance) =
  var appearance = base
  let
    tabContext = nimkit.controlStyle(nimkit.srTab)
    selectedTabContext = nimkit.controlStyle(nimkit.srTab, {nimkit.ssSelected})
    inactiveTabSelector = nimkit.initStyleSelector(nimkit.srTab, {nimkit.ssSelected})
    activeTabSelector =
      nimkit.initStyleSelector(nimkit.srTab, {nimkit.ssSelected, nimkit.ssFocused})
    cancelButtonSelector =
      nimkit.initStyleSelector(nimkit.srButton, id = KosmoCancelSearchButtonStyleId)
    highlightedCancelButtonSelector = nimkit.initStyleSelector(
      nimkit.srButton, {nimkit.ssHighlighted}, id = KosmoCancelSearchButtonStyleId
    )
    normalTabFill =
      base.resolveFill(tabContext, nimkit.fill(nimkit.color(0.16, 0.18, 0.22, 1.0)))
    normalTabTextColor = base.resolveColor(
      tabContext, nimkit.StyleTextColor, nimkit.color(0.72, 0.74, 0.80, 1.0)
    )
    selectedTabFill = base.resolveFill(
      selectedTabContext, nimkit.fill(nimkit.color(0.18, 0.42, 0.88, 0.18))
    )
    selectedTabTextColor = base.resolveColor(
      selectedTabContext, nimkit.StyleTextColor, nimkit.color(0.22, 0.50, 0.92, 1.0)
    )
    selectedTabIndicatorFill = base.resolveFill(
      selectedTabContext,
      nimkit.fill(selectedTabTextColor),
      nimkit.StyleSelectionIndicatorFill,
    )
    inactiveTabTextColor = nimkit.color(
      normalTabTextColor.r,
      normalTabTextColor.g,
      normalTabTextColor.b,
      normalTabTextColor.a * KosmoInactiveTabTextOpacity,
    )
    inactiveTabIndicatorColor = nimkit.color(
      selectedTabTextColor.r,
      selectedTabTextColor.g,
      selectedTabTextColor.b,
      selectedTabTextColor.a * KosmoInactiveTabAccentOpacity,
    )
  appearance.setStyle(inactiveTabSelector, nimkit.StyleFill, normalTabFill)
  appearance.setStyle(inactiveTabSelector, nimkit.StyleTextColor, inactiveTabTextColor)
  appearance.setStyle(
    inactiveTabSelector,
    nimkit.StyleSelectionIndicatorFill,
    nimkit.fill(inactiveTabIndicatorColor),
  )
  appearance.setStyle(activeTabSelector, nimkit.StyleFill, selectedTabFill)
  appearance.setStyle(activeTabSelector, nimkit.StyleTextColor, selectedTabTextColor)
  appearance.setStyle(
    activeTabSelector, nimkit.StyleSelectionIndicatorFill, selectedTabIndicatorFill
  )
  appearance.setStyle(
    cancelButtonSelector,
    nimkit.StyleFill,
    nimkit.fill(nimkit.color(0.12, 0.13, 0.16, 1.0)),
  )
  appearance.setStyle(
    cancelButtonSelector, nimkit.StyleBorderColor, nimkit.color(0.38, 0.40, 0.46, 1.0)
  )
  appearance.setStyle(
    cancelButtonSelector, nimkit.StyleTextColor, nimkit.color(0.88, 0.89, 0.92, 1.0)
  )
  appearance.setStyle(cancelButtonSelector, nimkit.StyleBorderWidth, 1.0'f32)
  appearance.setStyle(cancelButtonSelector, nimkit.StyleCornerRadius, 10.0'f32)
  appearance.setStyle(
    cancelButtonSelector,
    nimkit.StyleChrome,
    nimkit.styleKeyword(nimkit.DefaultChromeName),
  )
  appearance.setStyle(
    highlightedCancelButtonSelector,
    nimkit.StyleFill,
    nimkit.fill(nimkit.color(0.22, 0.23, 0.27, 1.0)),
  )
  appearance.installKosmoPaneIndicatorStyle(base)
  pane.activeIndicator.appearance = appearance
  pane.tabs.appearance = appearance
  pane.searchPanel.cancelButton.appearance = appearance

proc containsResponder(pane: KosmoSidebarPane, candidate: nimkit.Responder): bool =
  var responder = candidate
  while not responder.isNil:
    if responder == nimkit.Responder(pane):
      return true
    responder = responder.nextResponder()

proc hasSidebarFocus(pane: KosmoSidebarPane): bool =
  if pane.isNil or pane.observedWindow.isNil:
    return
  let window = pane.observedWindow[]
  if pane.containsResponder(window.firstResponder()):
    return true
  pane.containsResponder(window.fieldEditorClient())

proc updateSidebarFocus(pane: KosmoSidebarPane) =
  if pane.isNil:
    return
  let focused = pane.hasSidebarFocus()
  pane.tabs.focused = focused
  pane.activeIndicator.hidden = not focused
  pane.fileTree.showsFocusedRowHighlight = focused
  pane.searchPanel.resultsView.showsFocusedRowHighlight = focused
  if not pane.dockController.isNil:
    pane.dockController[].sidebarFocused = focused

protocol KosmoSidebarAppearanceObserver of nimkit.WindowAppearanceEvents:
  proc didChangeEffectiveAppearance(
      pane: KosmoSidebarPane, appearance: nimkit.Appearance
  ) {.slot.} =
    pane.applyKosmoSidebarStyle(appearance)

protocol KosmoSidebarFocusObserver of nimkit.WindowFocusEvents:
  proc didChangeFirstResponder(
      pane: KosmoSidebarPane, previous: nimkit.Responder
  ) {.slot.} =
    discard previous
    pane.updateSidebarFocus()

proc stopObservingWindow(pane: KosmoSidebarPane) =
  if pane.isNil or pane.observedWindow.isNil:
    return
  pane.unobserveProtocol(pane.observedWindow[], nimkit.WindowAppearanceEvents)
  pane.unobserveProtocol(pane.observedWindow[], nimkit.WindowFocusEvents)
  pane.observedWindow = default(WeakRef[nimkit.Window])

proc observeWindow(pane: KosmoSidebarPane, window: nimkit.Window) =
  pane.stopObservingWindow()
  if window.isNil:
    return
  pane.observedWindow = window.unsafeWeakRef()
  pane.observeProtocol(window, nimkit.WindowAppearanceEvents)
  pane.observeProtocol(window, nimkit.WindowFocusEvents)
  pane.applyKosmoSidebarStyle(window.effectiveAppearance())
  pane.updateSidebarFocus()

protocol KosmoSidebarPaneLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(pane: KosmoSidebarPane) =
    let
      bounds = pane.bounds()
      tabHeight = min(pane.tabs.tabBarHeight, bounds.size.height)
    pane.tabs.setFrameFromLayout(bounds)
    pane.activeIndicator.setFrameFromLayout(
      nimkit.rect(
        0.0'f32,
        tabHeight,
        bounds.size.width,
        max(bounds.size.height - tabHeight, 0.0'f32),
      )
    )

proc newKosmoSidebarPane(
    tabs: nimkit.CompactTabView,
    fileTree: KosmoFileTree,
    searchPanel: KosmoFileSearchPanel,
): KosmoSidebarPane =
  let activeIndicator = newKosmoPaneIndicator()
  result = KosmoSidebarPane(
    tabs: tabs,
    fileTree: fileTree,
    searchPanel: searchPanel,
    activeIndicator: activeIndicator,
  )
  result.initViewFields()
  result.clipsToBounds = true
  result.addSubview(tabs)
  result.addSubview(activeIndicator)
  discard result.withProtocol(KosmoSidebarPaneLayout)
  result.updateSidebarFocus()

protocol KosmoEditorPaneLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(pane: KosmoEditorPane) =
    let
      bounds = pane.bounds()
      tabHeight = min(KosmoTabBarHeight, bounds.size.height)
      editorHeight = max(bounds.size.height - KosmoTabBarHeight, 1.0'f32)
      commandBarHeight = min(KosmoCommandBarHeight, editorHeight)
    pane.documentTabs.setFrameFromLayout(
      nimkit.rect(0, 0, bounds.size.width, tabHeight)
    )
    if not pane.contentView.isNil:
      pane.contentView.setFrameFromLayout(
        nimkit.rect(0, tabHeight, bounds.size.width, editorHeight)
      )
    pane.commandBar.setFrameFromLayout(
      nimkit.rect(
        0,
        max(tabHeight, bounds.size.height - commandBarHeight),
        bounds.size.width,
        commandBarHeight,
      )
    )
    pane.activeIndicator.setFrameFromLayout(
      nimkit.rect(0, tabHeight, bounds.size.width, editorHeight)
    )
    if not pane.markdownControls.isNil:
      let
        controlsWidth = min(
          KosmoMarkdownControlsWidth,
          max(bounds.size.width - KosmoMarkdownControlsInset * 2.0'f32, 1.0'f32),
        )
        controlsHeight = min(KosmoMarkdownControlsHeight, editorHeight)
      pane.markdownControls.setFrameFromLayout(
        nimkit.rect(
          max(bounds.size.width - controlsWidth - KosmoMarkdownControlsInset, 0.0'f32),
          tabHeight + KosmoMarkdownControlsInset,
          controlsWidth,
          controlsHeight,
        )
      )
    if pane.contentView == nimkit.View(pane.editorView):
      pane.editorView.refresh()

proc setContentView(pane: KosmoEditorPane, contentView: nimkit.View) =
  if pane.isNil or contentView.isNil or pane.contentView == contentView:
    return
  if pane.contentView == nimkit.View(pane.markdownView) and
      contentView != nimkit.View(pane.markdownView):
    pane.markdownView.markdown = ""
  if pane.contentView.isNil:
    pane.addSubview(contentView, positioned = nimkit.svpBelow)
  elif not pane.replaceSubview(pane.contentView, contentView):
    pane.addSubview(contentView, positioned = nimkit.svpBelow)
  pane.contentView = contentView
  if contentView != nimkit.View(pane.editorView):
    pane.commandBar.hidden = true
  pane.setNeedsLayout()

protocol KosmoEditorPaneCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(pane: KosmoEditorPane, args: nimkit.TryToPerformArgs): bool =
    if pane.dockGroup.isNil:
      return false
    let group = pane.dockGroup[]
    if group.editorView.tabsDelegate.isNil or
        group.editorView.tabsDelegate.dockController.isNil:
      return false
    let controller = group.editorView.tabsDelegate.dockController[]
    let panelNumber = args.selector.focusPanelNumber()
    if panelNumber > 0:
      discard controller.focusPanel(panelNumber)
      return true
    case $args.selector.name
    of KosmoNewFileAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].newEditorTab()
    of KosmoOpenFileAction:
      if not controller.frontend.isNil:
        controller.frontend[].chooseFile()
    of KosmoOpenProjectAction:
      if not controller.frontend.isNil and not controller.frontend[].xWindowManager.isNil:
        controller.frontend[].xWindowManager[].chooseProject()
    of KosmoQuickOpenAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showQuickOpen()
    of KosmoNewTerminalAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].newTerminal()
    of KosmoSaveAction:
      controller.saveCurrentPaneTab(group)
    of KosmoCloseTabAction:
      controller.closeCurrentPaneTab(group)
    of KosmoCloseWindowAction:
      group.window.close()
    of KosmoQuitAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].application.terminate()
    of KosmoPreviousTabAction:
      controller.selectRelativePaneTab(group, -1)
    of KosmoNextTabAction:
      controller.selectRelativePaneTab(group, 1)
    of KosmoSplitHorizontalAction:
      discard controller.splitCurrentPaneTab(group, nimkit.dpBottom)
    of KosmoSplitVerticalAction:
      discard controller.splitCurrentPaneTab(group, nimkit.dpRight)
    of KosmoShowFileExplorerAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFileExplorer()
    of KosmoFindInFilesAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFindInFiles()
    of KosmoShowSettingsAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showSettings()
    of KosmoCopyAction:
      group.editorView.editorCopy()
    of KosmoCutAction:
      group.editorView.editorCut()
    of KosmoPasteAction:
      group.editorView.editorPaste()
    of KosmoSelectAllAction:
      discard group.editorView.editor.selectAll()
      group.editorView.refresh()
    of KosmoUndoAction:
      discard group.editorView.editor.undo()
      group.editorView.refresh()
    of KosmoRedoAction:
      discard group.editorView.editor.redo()
      group.editorView.refresh()
    else:
      return false
    true

proc localMarkdownLinkPath(pane: KosmoEditorPane, link: string): string =
  let url = nimkit.initUrl(link)
  if not url.isFileUrl() or (not url.hasScheme() and url.host().len > 0):
    return
  let path = url.localFilePath(pane.markdownView.imageBasePath)
  if path.len > 0:
    result = absolutePath(path)

protocol KosmoMarkdownLinkDelegate of nimkit.TextViewDelegateProtocol:
  method tvClickedLink(
      pane: KosmoEditorPane,
      textView: nimkit.TextView,
      link: string,
      range: nimkit.TextRange,
  ): bool =
    if textView.attachmentAtIndex(int(range.location)).attachment.identifier.len > 0:
      return true
    let path = pane.localMarkdownLinkPath(link)
    if path.len == 0:
      return link.len > 0
    if not fileExists(path) and not dirExists(path):
      return false
    if pane.dockGroup.isNil:
      return false
    let group = pane.dockGroup[]
    if group.editorView.tabsDelegate.dockController.isNil:
      return false
    let controller = group.editorView.tabsDelegate.dockController[]
    if controller.frontend.isNil:
      return false
    controller.frontend[].openPath(path)

proc newKosmoEditorPane(editorView: KosmoEditorView): KosmoEditorPane =
  let
    commandBar = newKosmoCommandBar(editorView)
    markdownView = KosmoMarkdownView()
    markdownControls = newKosmoMarkdownControls(editorView)
    activeIndicator = newKosmoPaneIndicator()
  markdownView.initMarkdownViewFields(syntaxHighlighter = moeSyntaxHighlighter)
  markdownView.editorView = editorView.unsafeWeakRef()
  result = KosmoEditorPane(
    documentTabs: editorView.documentTabs,
    editorView: editorView,
    commandBar: commandBar,
    markdownView: markdownView,
    markdownControls: markdownControls,
    contentView: editorView,
    activeIndicator: activeIndicator,
  )
  editorView.commandBar = commandBar
  result.initViewFields()
  result.addSubview(result.documentTabs)
  result.addSubview(editorView)
  result.addSubview(commandBar)
  result.addSubview(activeIndicator)
  result.addSubview(markdownControls)
  discard result.withProtocol(KosmoEditorPaneLayout)
  discard result.withProtocol(KosmoEditorPaneCommandDispatch)
  discard result.withProtocol(KosmoMarkdownLinkDelegate)
  let keyEquivalentMethod: nimkit.DynamicMethod = proc(
      self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
  ) =
    let event = invocation.argsAs(nimkit.KeyEvent)
    let markdownView = KosmoMarkdownView(self)
    if markdownView.handleMarkdownPaneKey(event):
      invocation.setResult(true)
    else:
      invocation.setResult(markdownView.handleMarkdownNavigationKey(event))
  discard result.markdownView.replaceMethod(
    nimkitSelectors.performKeyEquivalent(), keyEquivalentMethod
  )
  result.markdownView.textView().delegate = nimkit.DynamicAgent(result)

proc groupForView(
    controller: KosmoDockController, view: KosmoEditorView
): KosmoEditorGroup =
  for group in controller.groups:
    if group.editorView == view:
      return group

proc groupForTabs(
    controller: KosmoDockController, tabs: nimkit.DocumentTabs
): KosmoEditorGroup =
  for group in controller.groups:
    if group.editorView.documentTabs == tabs:
      return group

proc groupForPanel(
    controller: KosmoDockController, panel: nimkit.DockPanel
): KosmoEditorGroup =
  for group in controller.groups:
    if group.panel == panel:
      return group

proc appendGroupsInPanelOrder(
    controller: KosmoDockController,
    view: nimkit.View,
    groups: var seq[KosmoEditorGroup],
) =
  if view of nimkit.DockPanel:
    let group = controller.groupForPanel(nimkit.DockPanel(view))
    if not group.isNil:
      groups.add group
  elif view of nimkit.SplitView:
    for pane in nimkit.SplitView(view).panes():
      controller.appendGroupsInPanelOrder(pane, groups)

proc groupsInPanelOrder(controller: KosmoDockController): seq[KosmoEditorGroup] =
  for host in controller.hosts:
    if not host.window.isNil and not host.window.isClosed():
      controller.appendGroupsInPanelOrder(host.workspace.rootView(), result)

proc hostForWorkspace(
    controller: KosmoDockController, workspace: nimkit.DockView
): KosmoDockHost =
  for host in controller.hosts:
    if host.workspace == workspace:
      return host

proc focusedEditorGroup(controller: KosmoDockController): KosmoEditorGroup =
  if controller.isNil or controller.frontend.isNil:
    return
  let window = controller.frontend[].application.keyWindow()
  if window.isNil:
    return
  var responder = window.firstResponder()
  while not responder.isNil:
    for group in controller.groups:
      if responder == nimkit.Responder(group.pane):
        return group
    responder = responder.nextResponder()

proc activePaneGroup(controller: KosmoDockController): KosmoEditorGroup =
  result = controller.focusedEditorGroup()
  if result.isNil:
    result = controller.activeGroup
  if result.isNil and controller.groups.len > 0:
    result = controller.groups[0]

proc activeEditorView(controller: KosmoDockController): KosmoEditorView =
  let group = controller.activePaneGroup()
  if not group.isNil:
    result = group.editorView

proc installShortcutBindings(controller: KosmoDockController, window: nimkit.Window) =
  var bindings = window.keyBindings()
  for command in kosmoShortcutCommands():
    discard bindings.remove(nimkit.actionSelector(command))
  for binding in controller.shortcutBindings.bindings:
    bindings.add(binding.sequence, binding.selector)
  window.setKeyBindings(bindings)

proc activateGroup(controller: KosmoDockController, view: KosmoEditorView) =
  if controller.isNil or view.isNil:
    return
  let group = controller.groupForView(view)
  if not group.isNil:
    if controller.activeGroup != group:
      let previous = controller.activeGroup
      controller.editor.dismissCompletionPopup()
      controller.editor.dismissCommandLine()
      if not previous.isNil:
        previous.editorView.refresh()
    controller.activeGroup = group
    let tabs = view.visibleTabs(view.editor.tabs())
    view.selectVisibleBuffer(tabs)
    discard view.syncSelectedEditorContent(tabs)
    view.syncChrome()

proc activatePaneTab(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    identifier: string,
    focus = true,
) =
  if controller.isNil or group.isNil:
    return
  group.selectedTabIdentifier = identifier
  controller.activateGroup(group.editorView)
  var id: KosmoBufferId
  if identifier.parseTabIdentifier(id):
    group.pane.setContentView(group.editorView)
    group.editorView.saveViewState()
    group.editorView.editor.dismissCompletionPopup()
    group.editorView.editor.dismissCommandLine()
    group.editorView.selectedBufferId = some(id)
    group.editorView.selectVisibleBuffer(
      group.editorView.visibleTabs(group.editorView.editor.tabs())
    )
    group.editorView.refresh()
    if focus:
      discard group.window.makeFirstResponder(nimkit.Responder(group.pane.contentView))
    return

  let document = group.documentForIdentifier(identifier)
  if document.isNil:
    return
  group.editorView.editor.dismissCompletionPopup()
  group.editorView.editor.dismissCommandLine()
  group.pane.setContentView(document.contentView)
  group.editorView.syncTabs(group.editorView.editor.tabs())
  if not group.editorView.statusLabel.isNil:
    group.editorView.statusLabel.text = document.title
  group.pane.layoutSubtreeIfNeeded()
  if focus and not document.preferredFirstResponder.isNil:
    discard group.window.makeFirstResponder(document.preferredFirstResponder)

proc activatePanelWindow(controller: KosmoDockController, window: nimkit.Window) =
  if controller.frontend.isNil or window.isNil:
    return
  let app = controller.frontend[].application
  let keyWindow = app.keyWindow()
  if not keyWindow.isNil and keyWindow != window:
    app.activateWindow(window)

proc focusPanel(controller: KosmoDockController, panelNumber: int): bool =
  if controller.isNil or panelNumber < 1:
    return
  if panelNumber == 1:
    if controller.frontend.isNil:
      return
    let frontend = controller.frontend[]
    controller.activatePanelWindow(frontend.window)
    return frontend.showFileExplorer()

  let
    groupIndex = panelNumber - 2
    groups = controller.groupsInPanelOrder()
  if groupIndex notin 0 ..< groups.len:
    return
  let group = groups[groupIndex]
  if group.window.isNil or group.window.isClosed():
    return

  controller.activatePanelWindow(group.window)
  controller.activateGroup(group.editorView)
  let document = group.documentForIdentifier(group.selectedTabIdentifier)
  if group.selectedTabIdentifier.len > 0:
    controller.activatePaneTab(group, group.selectedTabIdentifier, focus = false)
  else:
    group.pane.setContentView(group.editorView)

  let responder =
    if document.isNil or document.preferredFirstResponder.isNil:
      group.preferredPaneResponder()
    else:
      nimkit.Responder(document.preferredFirstResponder)
  result = group.window.makeFirstResponder(responder)

proc initialBufferIds(editor: KosmoEditor): seq[KosmoBufferId] =
  for tab in editor.tabs():
    result.add tab.id

proc configureGroupView(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    bufferIds: openArray[KosmoBufferId],
) =
  let view = group.editorView
  view.usesBufferSubset = true
  view.bufferIds = @bufferIds
  view.selectedBufferId =
    if bufferIds.len > 0:
      some(bufferIds[^1])
    else:
      none(KosmoBufferId)
  view.lastTabs.setLen(0)
  view.dockGroup = group.unsafeWeakRef()
  group.pane.dockGroup = group.unsafeWeakRef()
  group.tabOrder.setLen(0)
  for id in bufferIds:
    group.tabOrder.add id.tabIdentifier
  group.selectedTabIdentifier =
    if bufferIds.len > 0:
      bufferIds[^1].tabIdentifier
    else:
      ""
  view.tabsDelegate.dockController = controller.unsafeWeakRef()
  let host = controller.hostForWorkspace(group.workspace)
  if not host.isNil:
    view.statusLabel = host.statusLabel
  if not controller.frontend.isNil:
    view.applyKosmoEditorStyle(controller.frontend[].application.effectiveAppearance())
  view.tabsDelegate.observeAppearance(group.window)
  view.refresh()

proc newEditorGroup(
    controller: KosmoDockController,
    workspace: nimkit.DockView,
    window: nimkit.Window,
    bufferIds: openArray[KosmoBufferId],
    editorView: KosmoEditorView = nil,
    editorPane: KosmoEditorPane = nil,
    addToWorkspace = false,
): KosmoEditorGroup =
  let
    view =
      if editorView.isNil:
        newKosmoEditorView(controller.editor)
      else:
        editorView
    pane =
      if editorPane.isNil:
        newKosmoEditorPane(view)
      else:
        editorPane
    panel = nimkit.newDockPanel(pane)
  inc controller.nextGroupIdentifier
  result = KosmoEditorGroup(
    identifier: "kosmo.group." & $controller.nextGroupIdentifier,
    panel: panel,
    pane: pane,
    editorView: view,
    workspace: workspace,
    window: window,
  )
  controller.groups.add result
  controller.configureGroupView(result, bufferIds)
  if addToWorkspace:
    discard workspace.addPanel(panel)
  if controller.activeGroup.isNil:
    controller.activeGroup = result
  else:
    result.updateActivePaneIndicator(false)

proc removeBuffer(group: KosmoEditorGroup, id: KosmoBufferId) =
  let index = group.editorView.bufferIds.find(id)
  if index < 0:
    return
  group.editorView.bufferIds.delete(index)
  group.editorView.removeViewState(id)
  group.editorView.forgetMarkdownMode(id)
  group.editorView.selectedBufferId = none(KosmoBufferId)
  group.editorView.lastTabs.setLen(0)
  let orderIndex = group.tabOrder.find(id.tabIdentifier)
  if orderIndex >= 0:
    group.tabOrder.delete(orderIndex)

proc addBuffer(group: KosmoEditorGroup, id: KosmoBufferId) =
  if id notin group.editorView.bufferIds:
    group.editorView.bufferIds.add id
  group.editorView.selectedBufferId = some(id)
  group.editorView.lastTabs.setLen(0)
  if id.tabIdentifier notin group.tabOrder:
    group.tabOrder.add id.tabIdentifier

proc removeGroup(controller: KosmoDockController, group: KosmoEditorGroup) =
  if group.isNil:
    return
  group.editorView.tabsDelegate.stopObservingWindow()
  group.editorView.tabsDelegate.dockController = default(WeakRef[KosmoDockController])
  group.editorView.dockGroup = default(WeakRef[KosmoEditorGroup])
  group.pane.dockGroup = default(WeakRef[KosmoEditorGroup])
  let wasActive = controller.activeGroup == group
  discard group.workspace.removePanel(group.panel)
  let index = controller.groups.find(group)
  if index >= 0:
    controller.groups.delete(index)
  let host = controller.hostForWorkspace(group.workspace)
  if not host.isNil and group.workspace.len == 0 and not host.primary:
    host.window.close()
  if wasActive:
    controller.activeGroup = nil
    for candidate in controller.groups:
      if controller.activeGroup.isNil and candidate.workspace == group.workspace:
        controller.activeGroup = candidate
    if controller.activeGroup.isNil and controller.groups.len > 0:
      controller.activeGroup = controller.groups[0]

proc finishTabClose(controller: KosmoDockController, view: KosmoEditorView) =
  let group = controller.groupForView(view)
  if group.isNil:
    view.refresh()
    return
  if view.bufferIds.len == 0 and group.documents.len == 0 and group.workspace.len > 1:
    let wasActive = controller.activeGroup == group
    controller.removeGroup(group)
    if wasActive and not controller.activeGroup.isNil:
      let replacement = controller.activeGroup
      controller.activateGroup(replacement.editorView)
      discard replacement.window.makeFirstResponder(replacement.editorView)
      replacement.editorView.refresh()
    return
  let selectedItem = view.documentTabs.selectedDocumentTabItem()
  if not selectedItem.isNil:
    controller.activatePaneTab(group, selectedItem.identifier())
    return
  if view.bufferIds.len == 0 and group.documents.len == 0:
    view.adoptActiveBuffer()
  view.lastTabs.setLen(0)
  view.refresh()

proc closeCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup) =
  if controller.isNil or group.isNil:
    return
  controller.activeGroup = group
  group.editorView.editor.dismissCommandLine()
  let index =
    group.pane.documentTabs.indexOfDocumentTabIdentifier(group.selectedTabIdentifier)
  if index >= 0:
    discard group.pane.documentTabs.closeDocumentTabAtIndex(index)
  else:
    group.editorView.refresh()

proc closeCurrentTab(controller: KosmoDockController, view: KosmoEditorView) =
  let group = controller.groupForView(view)
  if not group.isNil:
    controller.closeCurrentPaneTab(group)
    return
  view.editor.dismissCommandLine()
  view.refresh()

proc saveCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup) =
  if controller.isNil or group.isNil:
    return
  let document = group.documentForIdentifier(group.selectedTabIdentifier)
  if not document.isNil:
    controller.activeGroup = group
    discard document.save()
    return
  controller.saveCurrentTab(group.editorView)

proc saveCurrentTab(controller: KosmoDockController, view: KosmoEditorView) =
  controller.activateGroup(view)
  view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
  let outcome = view.editor.save()
  view.lastTabs.setLen(0)
  view.refresh()
  if not outcome.saved and not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message

proc selectRelativeTab(
    controller: KosmoDockController, view: KosmoEditorView, offset: int
) =
  let group = controller.groupForView(view)
  if not group.isNil:
    controller.selectRelativePaneTab(group, offset)
    return
  controller.activateGroup(view)
  let tabs = view.visibleTabs(view.editor.tabs())
  if tabs.len == 0:
    return
  var selectedIndex = 0
  if view.selectedBufferId.isSome:
    for index, tab in tabs:
      if tab.id == view.selectedBufferId.get:
        selectedIndex = index
        break
  let targetIndex = (selectedIndex + offset + tabs.len) mod tabs.len
  discard view.documentTabs.selectDocumentTabWithIdentifier(
    tabs[targetIndex].id.tabIdentifier
  )

proc selectRelativePaneTab(
    controller: KosmoDockController, group: KosmoEditorGroup, offset: int
) =
  if controller.isNil or group.isNil or group.pane.documentTabs.len == 0:
    return
  controller.activeGroup = group
  var selectedIndex =
    group.pane.documentTabs.indexOfDocumentTabIdentifier(group.selectedTabIdentifier)
  if selectedIndex < 0:
    selectedIndex = 0
  let targetIndex =
    (selectedIndex + offset + group.pane.documentTabs.len) mod
    group.pane.documentTabs.len
  discard group.pane.documentTabs.selectDocumentTabAtIndex(targetIndex)

proc finishPaneTabMove(
    controller: KosmoDockController,
    source, target: KosmoEditorGroup,
    identifier: string,
) =
  if source != target:
    var id: KosmoBufferId
    if identifier.parseTabIdentifier(id):
      target.addBuffer(id)
      source.removeBuffer(id)
    else:
      let documentIndex = source.documentIndex(identifier)
      if documentIndex < 0:
        return
      let document = source.documents[documentIndex]
      source.documents.delete(documentIndex)
      let orderIndex = source.tabOrder.find(identifier)
      if orderIndex >= 0:
        source.tabOrder.delete(orderIndex)
      target.documents.add document
      if identifier notin target.tabOrder:
        target.tabOrder.add identifier
    if source.editorView.bufferIds.len == 0 and source.documents.len == 0:
      controller.removeGroup(source)
    else:
      source.editorView.lastTabs.setLen(0)
      source.editorView.refresh()
      let fallback = source.pane.documentTabs.selectedDocumentTabItem()
      if not fallback.isNil:
        controller.activatePaneTab(source, fallback.identifier(), focus = false)
  controller.activeGroup = target
  target.selectedTabIdentifier = identifier
  target.editorView.lastTabs.setLen(0)
  target.editorView.refresh()
  controller.activatePaneTab(target, identifier)

proc splitCurrentPaneTab(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    position: nimkit.DockPosition,
): bool =
  if controller.isNil or source.isNil or position == nimkit.dpCenter:
    return false
  let selectedItem = source.pane.documentTabs.selectedDocumentTabItem()
  if selectedItem.isNil:
    return false
  let
    identifier = selectedItem.identifier()
    duplicatesCurrentTab = source.pane.documentTabs.len == 1
  var
    id: KosmoBufferId
    bufferIds: seq[KosmoBufferId]
    duplicateDocument: KosmoPaneDocument
  if identifier.parseTabIdentifier(id):
    bufferIds.add id
  else:
    let document = source.documentForIdentifier(identifier)
    if document.isNil:
      return false
    if duplicatesCurrentTab:
      try:
        duplicateDocument = document.duplicate()
      except nimkit.TerminexSessionError as error:
        if not source.editorView.statusLabel.isNil:
          source.editorView.statusLabel.text = error.msg
        return false
      if duplicateDocument.isNil:
        if not source.editorView.statusLabel.isNil:
          source.editorView.statusLabel.text = "This tab cannot be duplicated"
        return false

  let target = controller.newEditorGroup(source.workspace, source.window, bufferIds)
  if not source.workspace.splitPanel(source.panel, target.panel, position):
    if not duplicateDocument.isNil:
      discard duplicateDocument.close()
    controller.removeGroup(target)
    return false
  if duplicatesCurrentTab:
    if duplicateDocument.isNil:
      controller.activatePaneTab(target, identifier)
      return true
    let opened = controller.openPaneDocument(target, duplicateDocument)
    if opened and
        target.documentForIdentifier(duplicateDocument.identifier) == duplicateDocument:
      return true
    discard duplicateDocument.close()
    controller.removeGroup(target)
    return false
  controller.finishPaneTabMove(source, target, identifier)
  true

proc splitCurrentBuffer(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    position: nimkit.DockPosition,
): bool =
  let selectedItem = source.pane.documentTabs.selectedDocumentTabItem()
  if selectedItem.isNil:
    return
  var id: KosmoBufferId
  if not selectedItem.identifier().parseTabIdentifier(id):
    return controller.splitCurrentPaneTab(source, position)
  let target = controller.newEditorGroup(source.workspace, source.window, [id])
  if not source.workspace.splitPanel(source.panel, target.panel, position):
    controller.removeGroup(target)
    return
  controller.activatePaneTab(target, id.tabIdentifier)
  true

proc splitNewBufferBelow(
    controller: KosmoDockController, source: KosmoEditorGroup
): bool =
  let bufferId = controller.editor.newEmptyBuffer()
  if bufferId.isNone:
    return
  let target =
    controller.newEditorGroup(source.workspace, source.window, [bufferId.get])
  if not source.workspace.splitPanel(source.panel, target.panel, nimkit.dpBottom):
    controller.removeGroup(target)
    return
  controller.activatePaneTab(target, bufferId.get.tabIdentifier)
  true

proc preferredPaneResponder(group: KosmoEditorGroup): nimkit.Responder =
  if group.pane.contentView == nimkit.View(group.pane.markdownView):
    nimkit.Responder(group.pane.markdownView)
  else:
    nimkit.Responder(group.editorView)

proc focusGroup(controller: KosmoDockController, group: KosmoEditorGroup): bool =
  if controller.isNil or group.isNil:
    return
  controller.activateGroup(group.editorView)
  discard group.window.makeFirstResponder(group.preferredPaneResponder())
  group.editorView.refresh()
  true

proc focusNextGroup(controller: KosmoDockController, source: KosmoEditorGroup): bool =
  var candidates: seq[KosmoEditorGroup]
  for group in controller.groups:
    if group.workspace == source.workspace:
      candidates.add group
  let index = candidates.find(source)
  if candidates.len < 2 or index < 0:
    return
  controller.focusGroup(candidates[(index + 1) mod candidates.len])

proc focusSpatialGroup(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    direction: KosmoPaneCommand,
): bool =
  let sourceRect = source.panel.rectToView(source.panel.bounds(), source.workspace)
  let
    sourceX = sourceRect.origin.x + sourceRect.size.width * 0.5'f32
    sourceY = sourceRect.origin.y + sourceRect.size.height * 0.5'f32
  var
    target: KosmoEditorGroup
    bestScore = float32.high
  for candidate in controller.groups:
    if candidate == source or candidate.workspace != source.workspace:
      continue
    let candidateRect =
      candidate.panel.rectToView(candidate.panel.bounds(), candidate.workspace)
    let
      dx = candidateRect.origin.x + candidateRect.size.width * 0.5'f32 - sourceX
      dy = candidateRect.origin.y + candidateRect.size.height * 0.5'f32 - sourceY
      eligible =
        case direction
        of kpcFocusLeft:
          dx < 0.0'f32
        of kpcFocusRight:
          dx > 0.0'f32
        of kpcFocusAbove:
          dy < 0.0'f32
        of kpcFocusBelow:
          dy > 0.0'f32
        else:
          false
    if not eligible:
      continue
    let score =
      case direction
      of kpcFocusLeft, kpcFocusRight:
        abs(dx) + abs(dy) * 0.35'f32
      of kpcFocusAbove, kpcFocusBelow:
        abs(dy) + abs(dx) * 0.35'f32
      else:
        float32.high
    if score < bestScore:
      bestScore = score
      target = candidate
  controller.focusGroup(target)

proc closePane(controller: KosmoDockController, source: KosmoEditorGroup): bool =
  if source.workspace.len <= 1:
    return
  for document in source.documents:
    if not document.closeable or not document.close():
      return
  var replacement: KosmoEditorGroup
  for candidate in controller.groups:
    if candidate != source and candidate.workspace == source.workspace:
      replacement = candidate
      break
  controller.removeGroup(source)
  controller.focusGroup(replacement)

proc containingSplit(
    source: KosmoEditorGroup, axis: nimkit.LayoutAxis
): tuple[splitView: nimkit.SplitView, paneIndex: int] =
  var child = nimkit.View(source.panel)
  while not child.isNil:
    let parent = child.superview()
    if parent of nimkit.SplitView and nimkit.SplitView(parent).splitAxis == axis:
      return (
        splitView: nimkit.SplitView(parent),
        paneIndex: nimkit.SplitView(parent).paneIndex(child),
      )
    child = parent
  (splitView: nil, paneIndex: -1)

proc resizePane(source: KosmoEditorGroup, axis: nimkit.LayoutAxis, grow: bool): bool =
  const ResizeStep = 32.0'f32
  let context = source.containingSplit(axis)
  if context.splitView.isNil or context.splitView.paneCount() < 2 or
      context.paneIndex < 0:
    return
  let
    hasFollowing = context.paneIndex < context.splitView.paneCount() - 1
    dividerIndex =
      if hasFollowing:
        context.paneIndex
      else:
        context.paneIndex - 1
    direction =
      if hasFollowing:
        (if grow: 1.0'f32 else: -1.0'f32)
      else:
        (if grow: -1.0'f32 else: 1.0'f32)
    position = context.splitView.positionOfDivider(dividerIndex)
  context.splitView.setPositionOfDivider(
    dividerIndex, position + direction * ResizeStep
  )
  true

proc equalizeSplits(view: nimkit.View) =
  if view of nimkit.SplitView:
    let splitView = nimkit.SplitView(view)
    var state = splitView.captureState()
    for index in 0 ..< state.fractions.len:
      state.fractions[index] = 1.0'f32
    splitView.restoreState(state)
  for child in view.xSubviews:
    child.equalizeSplits()

proc performPaneCommand(
    controller: KosmoDockController, source: KosmoEditorGroup, command: KosmoPaneCommand
): bool =
  if controller.isNil or source.isNil:
    return
  case command
  of kpcSplitBelow:
    controller.splitCurrentBuffer(source, nimkit.dpBottom)
  of kpcSplitRight:
    controller.splitCurrentBuffer(source, nimkit.dpRight)
  of kpcNewBelow:
    controller.splitNewBufferBelow(source)
  of kpcFocusNext:
    controller.focusNextGroup(source)
  of kpcFocusLeft, kpcFocusBelow, kpcFocusAbove, kpcFocusRight:
    controller.focusSpatialGroup(source, command)
  of kpcClose:
    controller.closePane(source)
  of kpcGrowHeight:
    source.resizePane(nimkit.laVertical, true)
  of kpcShrinkHeight:
    source.resizePane(nimkit.laVertical, false)
  of kpcShrinkWidth:
    source.resizePane(nimkit.laHorizontal, false)
  of kpcGrowWidth:
    source.resizePane(nimkit.laHorizontal, true)
  of kpcEqualize:
    source.workspace.rootView().equalizeSplits()
    true
  of kpcNone:
    false

proc screenPoint(tabs: nimkit.DocumentTabs, location: nimkit.Point): nimkit.Point =
  let owner = tabs.window()
  if owner of nimkit.Window:
    return nimkit.Window(owner).convertPointToScreen(tabs.pointToWindow(location))
  tabs.pointToWindow(location)

proc targetAtScreenPoint(
    controller: KosmoDockController, point: nimkit.Point
): tuple[workspace: nimkit.DockView, target: nimkit.DockDropTarget] =
  for host in controller.hosts:
    if not host.window.isNil and not host.window.isClosed():
      let
        windowPoint = host.window.convertPointFromScreen(point)
        workspacePoint = host.workspace.pointFromWindow(windowPoint)
      if host.workspace.bounds().contains(workspacePoint):
        var target = host.workspace.dropTargetAtPoint(workspacePoint)
        if target.valid():
          let group = controller.groupForPanel(target.panel)
          if not group.isNil:
            let tabPoint = group.editorView.documentTabs.pointFromView(
              workspacePoint, host.workspace
            )
            if group.editorView.documentTabs.bounds().contains(tabPoint):
              let panelRect =
                target.panel.rectToView(target.panel.bounds(), host.workspace)
              target = nimkit.DockDropTarget(
                panel: target.panel, position: nimkit.dpCenter, rect: panelRect
              )
          return (host.workspace, target)

proc clearDockTargets(controller: KosmoDockController) =
  for host in controller.hosts:
    host.workspace.clearDropTarget()

proc updateDockTarget(
    controller: KosmoDockController, tabs: nimkit.DocumentTabs, location: nimkit.Point
) =
  if controller.isNil:
    return
  controller.clearDockTargets()
  let resolved = controller.targetAtScreenPoint(tabs.screenPoint(location))
  if not resolved.workspace.isNil and resolved.target.valid():
    resolved.workspace.dropTarget = resolved.target

protocol KosmoDetachedContentLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(content: KosmoDetachedContentView) =
    let bounds = content.bounds()
    content.statusLabel.setFrameFromLayout(
      nimkit.rect(
        0,
        max(bounds.size.height - KosmoStatusBarHeight, 0.0'f32),
        bounds.size.width,
        KosmoStatusBarHeight,
      )
    )
    content.workspace.setFrameFromLayout(
      nimkit.rect(
        0, 0, bounds.size.width, max(bounds.size.height - KosmoStatusBarHeight, 1.0'f32)
      )
    )

proc newKosmoDetachedContentView(
    workspace: nimkit.DockView, statusLabel: nimkit.Label
): KosmoDetachedContentView =
  result = KosmoDetachedContentView(workspace: workspace, statusLabel: statusLabel)
  result.initViewFields()
  result.addSubview(workspace)
  result.addSubview(statusLabel)
  discard result.withProtocol(KosmoDetachedContentLayout)

proc detachPaneTab(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    identifier: string,
    screenLocation: nimkit.Point,
) =
  if controller.frontend.isNil:
    return
  let
    frontend = controller.frontend[]
    workspace = nimkit.newDockView()
    statusLabel = nimkit.newStatusLabel("Ready")
    contentView = newKosmoDetachedContentView(workspace, statusLabel)
    window = nimkit.newWindow(
      "Kosmo",
      nimkit.rect(screenLocation.x - 360.0'f32, screenLocation.y - 24.0'f32, 720, 520),
    )
    host = KosmoDockHost(
      workspace: workspace,
      window: window,
      contentView: contentView,
      statusLabel: statusLabel,
    )
  controller.hosts.add host
  controller.installShortcutBindings(window)
  var
    id: KosmoBufferId
    bufferIds: seq[KosmoBufferId]
  if identifier.parseTabIdentifier(id):
    bufferIds.add id
  let group =
    controller.newEditorGroup(workspace, window, bufferIds, addToWorkspace = true)
  controller.finishPaneTabMove(source, group, identifier)
  window.setContentView(contentView)
  frontend.application.addWindow(window)
  if frontend.application.isRunning():
    frontend.application.activateWindow(window)

proc finishDockDrag(
    controller: KosmoDockController,
    tabs: nimkit.DocumentTabs,
    item: nimkit.DocumentTabItem,
    location: nimkit.Point,
) =
  if controller.isNil or item.isNil:
    return
  let
    point = tabs.screenPoint(location)
    resolved = controller.targetAtScreenPoint(point)
    source = controller.groupForTabs(tabs)
  controller.clearDockTargets()
  if source.isNil:
    return
  let identifier = item.identifier()
  var id: KosmoBufferId
  if not identifier.parseTabIdentifier(id) and
      source.documentForIdentifier(identifier).isNil:
    return

  if resolved.target.valid():
    let target = controller.groupForPanel(resolved.target.panel)
    if target.isNil:
      return
    if resolved.target.position == nimkit.dpCenter:
      if target != source:
        controller.finishPaneTabMove(source, target, identifier)
    else:
      let bufferIds =
        if identifier.parseTabIdentifier(id):
          @[id]
        else:
          @[]
      let next = controller.newEditorGroup(resolved.workspace, target.window, bufferIds)
      if resolved.workspace.splitPanel(
        target.panel, next.panel, resolved.target.position
      ):
        controller.finishPaneTabMove(source, next, identifier)
      else:
        controller.removeGroup(next)
  else:
    controller.detachPaneTab(source, identifier, point)

proc openPaneDocument(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    document: KosmoPaneDocument,
): bool =
  if controller.isNil or group.isNil or document.isNil or document.identifier.len == 0 or
      document.contentView.isNil:
    return
  var bufferId: KosmoBufferId
  if document.identifier.parseTabIdentifier(bufferId):
    return
  for candidate in controller.groups:
    if not candidate.documentForIdentifier(document.identifier).isNil:
      controller.activatePaneTab(candidate, document.identifier)
      return true
  if document.preferredFirstResponder.isNil:
    document.preferredFirstResponder = document.contentView
  group.documents.add document
  group.tabOrder.add document.identifier
  group.selectedTabIdentifier = document.identifier
  group.editorView.lastTabs.setLen(0)
  group.editorView.refresh()
  controller.activatePaneTab(group, document.identifier)
  true

proc newTerminalDocument(
    controller: KosmoDockController, options: nimkit.TerminexSpawnOptions
): KosmoPaneDocument =
  let terminalView = nimkit.newTerminalView()
  if not controller.frontend.isNil:
    terminalView.optionAsMeta = controller.frontend[].xTerminalOptionAsMeta
  try:
    terminalView.start(options)
  except nimkit.TerminexSessionError:
    terminalView.close()
    raise

  inc controller.nextDocumentIdentifier
  let weakController = controller.unsafeWeakRef()
  result = newKosmoPaneDocument(
    identifier = KosmoTerminalIdentifierPrefix & $controller.nextDocumentIdentifier,
    title = "Terminal " & $controller.nextDocumentIdentifier,
    contentView = terminalView,
    tooltip = "Terminal",
    onClose = proc(document: KosmoPaneDocument): bool =
      discard document
      terminalView.close()
      true,
    onDuplicate = proc(document: KosmoPaneDocument): KosmoPaneDocument =
      discard document
      if not weakController.isNil:
        result = weakController[].newTerminalDocument(options)
    ,
  )

proc openTerminal(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    options: nimkit.TerminexSpawnOptions,
): bool =
  if controller.isNil or group.isNil:
    return
  var document: KosmoPaneDocument
  try:
    document = controller.newTerminalDocument(options)
  except nimkit.TerminexSessionError as error:
    if not group.editorView.statusLabel.isNil:
      group.editorView.statusLabel.text = error.msg
    return
  if controller.openPaneDocument(group, document):
    return true
  discard document.close()

proc newEditorTab*(frontend: KosmoApplication): bool {.discardable.} =
  ## Create and select an unnamed buffer in the active editor pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  let
    controller = frontend.dockController
    group = controller.activePaneGroup()
  if group.isNil:
    return
  let bufferId = controller.editor.newEmptyBuffer()
  if bufferId.isNone:
    return
  group.addBuffer(bufferId.get)
  controller.activatePaneTab(group, bufferId.get.tabIdentifier)
  result = true

proc newTerminal*(frontend: KosmoApplication): bool {.discardable.} =
  ## Open a terminal in the active editor pane.
  if frontend.isNil or frontend.dockController.isNil or frontend.fileTree.isNil:
    return
  let
    controller = frontend.dockController
    group = controller.activePaneGroup()
    options =
      nimkit.initTerminalSpawnOptions(workingDirectory = frontend.fileTree.rootPath)
  result = controller.openTerminal(group, options)

protocol KosmoContentLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(content: KosmoContentView) =
    let
      bounds = content.bounds()
      splitWidthChanged =
        content.setInitialDivider and
        abs(bounds.size.width - content.lastSplitWidth) > 0.001'f32
    content.statusLabel.setFrameFromLayout(
      nimkit.rect(
        0,
        max(bounds.size.height - KosmoStatusBarHeight, 0.0'f32),
        bounds.size.width,
        KosmoStatusBarHeight,
      )
    )
    content.splitView.setFrameFromLayout(
      nimkit.rect(
        0, 0, bounds.size.width, max(bounds.size.height - KosmoStatusBarHeight, 1.0'f32)
      )
    )
    if not content.quickOpenPanel.isNil:
      let
        availableWidth = max(bounds.size.width - 48.0'f32, 1.0'f32)
        availableHeight = max(
          bounds.size.height - KosmoStatusBarHeight - KosmoQuickOpenTopInset -
            KosmoQuickOpenBottomInset,
          1.0'f32,
        )
        popupWidth = min(availableWidth, 640.0'f32)
        popupHeight = min(availableHeight, 360.0'f32)
      content.quickOpenPanel.setFrameFromLayout(
        nimkit.rect(
          max((bounds.size.width - popupWidth) * 0.5'f32, 0.0'f32),
          KosmoQuickOpenTopInset + content.quickOpenPanel.presentationOffset(),
          popupWidth,
          popupHeight,
        )
      )
    if not content.setInitialDivider and bounds.size.width > 0.0'f32:
      content.splitView.setPositionOfDivider(0, min(bounds.size.width * 0.25, 260.0))
      content.setInitialDivider = true
    elif splitWidthChanged:
      content.splitView.setPositionOfDivider(0, content.fileTreeWidth)
    content.lastSplitWidth = bounds.size.width
    if content.splitView.paneCount() > 1 and not splitWidthChanged:
      content.fileTreeWidth = content.splitView.positionOfDivider(0)

protocol KosmoContentCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(
      content: KosmoContentView, args: nimkit.TryToPerformArgs
  ): bool =
    let panelNumber = args.selector.focusPanelNumber()
    if panelNumber > 0:
      if content.onFocusPanel.isNil:
        return false
      content.onFocusPanel(panelNumber)
      return true
    case $args.selector.name
    of KosmoNewTerminalAction:
      if content.onNewTerminal.isNil:
        return false
      content.onNewTerminal()
    of KosmoShowFileExplorerAction:
      if content.onShowFileExplorer.isNil:
        return false
      content.onShowFileExplorer()
    of KosmoFindInFilesAction:
      if content.onFindInFiles.isNil:
        return false
      content.onFindInFiles()
    of KosmoQuickOpenAction:
      if content.onQuickOpen.isNil:
        return false
      content.onQuickOpen()
    else:
      return false
    true

proc newKosmoContentView(
    splitView: nimkit.SplitView,
    statusLabel: nimkit.Label,
    quickOpenPanel: KosmoQuickOpenPanel,
): KosmoContentView =
  result = KosmoContentView(
    splitView: splitView, statusLabel: statusLabel, quickOpenPanel: quickOpenPanel
  )
  result.initViewFields()
  result.addSubview(splitView)
  result.addSubview(statusLabel)
  result.addSubview(quickOpenPanel)
  discard result.withProtocol(KosmoContentLayout)
  discard result.withProtocol(KosmoContentCommandDispatch)

proc showFileExplorer*(frontend: KosmoApplication): bool {.discardable.} =
  ## Select the files sidebar tab and focus its tree.
  if frontend.isNil or not frontend.hasFileBrowser() or frontend.sidebarTabs.isNil or
      frontend.fileTree.isNil:
    return
  if not frontend.sidebarTabs.selectCompactTabAtIndex(0):
    return
  result = frontend.window.makeFirstResponder(frontend.fileTree)

proc showFindInFiles*(frontend: KosmoApplication): bool {.discardable.} =
  ## Select the find sidebar tab and focus its search query.
  if frontend.isNil or not frontend.hasFileBrowser() or frontend.sidebarTabs.isNil or
      frontend.searchPanel.isNil:
    return
  frontend.searchPanel.rootPath = frontend.fileTree.rootPath
  if not frontend.sidebarTabs.selectCompactTabAtIndex(1):
    return
  result = frontend.searchPanel.focusQuery()

proc showQuickOpen*(frontend: KosmoApplication): bool {.discardable.} =
  ## Present the fuzzy project-file picker and open its selected file.
  if frontend.isNil or frontend.quickOpenPanel.isNil or frontend.fileTree.isNil:
    return
  let weakFrontend = frontend.unsafeWeakRef()
  result = frontend.quickOpenPanel.present(
    frontend.window,
    frontend.fileTree.rootPath,
    proc(path: string) =
      if weakFrontend.isNil:
        return
      let activeView = weakFrontend[].dockController.activeEditorView()
      if not activeView.isNil:
        discard activeView.openFile(path)
    ,
  )

func terminalOptionAsMeta*(frontend: KosmoApplication): bool =
  ## Return whether Kosmo terminals use Option/Alt as the Meta modifier.
  not frontend.isNil and frontend.xTerminalOptionAsMeta

proc `terminalOptionAsMeta=`*(frontend: KosmoApplication, enabled: bool) =
  ## Apply the Option/Alt-as-Meta preference to current and future terminals.
  if frontend.isNil:
    return
  frontend.xTerminalOptionAsMeta = enabled
  if not frontend.xSettingsWindow.isNil:
    frontend.xSettingsWindow.optionAsMeta = enabled
  if frontend.dockController.isNil:
    return
  for group in frontend.dockController.groups:
    for document in group.documents:
      if document.contentView of nimkit.TerminalView:
        nimkit.TerminalView(document.contentView).optionAsMeta = enabled

func moeThemeSettings(themes: openArray[KosmoMoeTheme]): seq[KosmoMoeThemeSetting] =
  for theme in themes:
    result.add KosmoMoeThemeSetting(
      identifier: theme.identifier, name: theme.name, preview: theme.preview
    )

proc setMoeTheme*(frontend: KosmoApplication, identifier: string): bool =
  ## Apply an available Moe theme and repaint every editor pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  for theme in frontend.dockController.editor.availableMoeThemes():
    if theme.identifier != identifier:
      continue
    let outcome = frontend.dockController.editor.applyMoeTheme(theme)
    for group in frontend.dockController.groups:
      group.editorView.refresh()
    if not outcome.applied and not frontend.statusLabel.isNil:
      frontend.statusLabel.text = outcome.message
    return outcome.applied

proc menuItemWithIdentifier(menu: nimkit.Menu, identifier: string): nimkit.MenuItem =
  if menu.isNil:
    return
  for item in menu.items():
    if item.identifier() == identifier:
      return item
    let nested = item.submenu().menuItemWithIdentifier(identifier)
    if not nested.isNil:
      return nested

proc synchronizeKosmoMenuBindings(frontend: KosmoApplication) =
  if frontend.isNil or frontend.dockController.isNil:
    return
  let menu = frontend.application.mainMenu()
  for action in kosmoActions():
    let item = menu.menuItemWithIdentifier(action.identifier)
    if item.isNil:
      continue
    var found = false
    for binding in frontend.dockController.shortcutBindings.bindings:
      if binding.selector == nimkit.actionSelector(action.identifier) and
          binding.sequence.strokes.len == 1:
        let stroke = binding.sequence.strokes[0]
        item.setKeyEquivalent(stroke.key, stroke.modifiers)
        found = true
        break
    if not found:
      item.setKeyEquivalent("")

proc updateShortcutSettingsWindow(frontend: KosmoApplication) =
  if frontend.isNil or frontend.xSettingsWindow.isNil:
    return
  let controller = frontend.dockController
  frontend.xSettingsWindow.shortcutProfile = controller.shortcutProfile
  frontend.xSettingsWindow.editorInputPolicy = controller.editorInputPolicy
  frontend.xSettingsWindow.shortcuts =
    controller.shortcutBindings.kosmoShortcutSettings()

proc setShortcutProfile*(frontend: KosmoApplication, profile: KosmoShortcutProfile) =
  ## Apply a shortcut profile immediately to every Kosmo window and menu.
  if frontend.isNil or frontend.dockController.isNil or
      frontend.dockController.shortcutProfile == profile:
    return
  let controller = frontend.dockController
  controller.shortcutProfile = profile
  controller.shortcutBindings = initKosmoKeyBindings(profile)
  for host in controller.hosts:
    controller.installShortcutBindings(host.window)
  frontend.synchronizeKosmoMenuBindings()
  frontend.updateShortcutSettingsWindow()

func shortcutProfile*(frontend: KosmoApplication): KosmoShortcutProfile =
  if frontend.isNil or frontend.dockController.isNil:
    defaultKosmoShortcutProfile()
  else:
    frontend.dockController.shortcutProfile

proc setEditorInputPolicy*(frontend: KosmoApplication, policy: KosmoEditorInputPolicy) =
  ## Apply Moe/native key routing immediately to every editor pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  frontend.dockController.editorInputPolicy = policy
  frontend.updateShortcutSettingsWindow()

func editorInputPolicy*(frontend: KosmoApplication): KosmoEditorInputPolicy =
  if frontend.isNil or frontend.dockController.isNil:
    defaultKosmoEditorInputPolicy()
  else:
    frontend.dockController.editorInputPolicy

func settingsWindow*(frontend: KosmoApplication): KosmoSettingsWindow =
  ## Return Kosmo's settings controller after the panel has been created.
  if not frontend.isNil:
    result = frontend.xSettingsWindow

proc showSettings*(frontend: KosmoApplication): bool {.discardable.} =
  ## Present Kosmo's application settings without Merenda's global settings pages.
  if frontend.isNil or frontend.application.isNil:
    return
  let
    shortcuts = frontend.dockController.shortcutBindings.kosmoShortcutSettings()
    moeThemes = frontend.dockController.editor.availableMoeThemes()
    moeThemeSettings = moeThemes.moeThemeSettings()
    selectedMoeThemeIdentifier =
      frontend.dockController.editor.activeMoeThemeIdentifier()
  if frontend.xSettingsWindow.isNil or frontend.xSettingsWindow.window.isClosed():
    let weakFrontend = frontend.unsafeWeakRef()
    frontend.xSettingsWindow = newKosmoSettingsWindow(
      optionAsMeta = frontend.xTerminalOptionAsMeta,
      optionAsMetaHandler = proc(enabled: bool) =
        if not weakFrontend.isNil:
          weakFrontend[].terminalOptionAsMeta = enabled
      ,
      shortcutProfile = frontend.dockController.shortcutProfile,
      shortcutProfileHandler = proc(profile: KosmoShortcutProfile) =
        if not weakFrontend.isNil:
          weakFrontend[].setShortcutProfile(profile)
      ,
      editorInputPolicy = frontend.dockController.editorInputPolicy,
      editorInputPolicyHandler = proc(policy: KosmoEditorInputPolicy) =
        if not weakFrontend.isNil:
          weakFrontend[].setEditorInputPolicy(policy)
      ,
      shortcuts = shortcuts,
      moeThemes = moeThemeSettings,
      selectedMoeThemeIdentifier = selectedMoeThemeIdentifier,
      moeThemeHandler = proc(identifier: string): bool =
        if not weakFrontend.isNil:
          return weakFrontend[].setMoeTheme(identifier)
      ,
    )
  else:
    frontend.xSettingsWindow.optionAsMeta = frontend.xTerminalOptionAsMeta
    frontend.updateShortcutSettingsWindow()
    frontend.xSettingsWindow.updateMoeThemes(
      moeThemeSettings, selectedMoeThemeIdentifier
    )
  result =
    not frontend.application.showWindow(
      frontend.xSettingsWindow.window, frontend.xSettingsWindow.contentView,
      frontend.xSettingsWindow.firstResponder,
    ).isNil

func ownsWindow(frontend: KosmoApplication, window: nimkit.Window): bool =
  if frontend.isNil or window.isNil or frontend.dockController.isNil:
    return
  for host in frontend.dockController.hosts:
    if host.window == window:
      return true

proc activeFrontend(manager: KosmoWindowManager): KosmoApplication =
  if manager.isNil:
    return
  let keyWindow = manager.application.keyWindow()
  for frontend in manager.frontends:
    if not frontend.xClosed and frontend.ownsWindow(keyWindow):
      return frontend
  let mainWindow = manager.application.mainWindow()
  for frontend in manager.frontends:
    if not frontend.xClosed and frontend.ownsWindow(mainWindow):
      return frontend
  if manager.frontends.len > 0:
    for index in countdown(manager.frontends.high, 0):
      if not manager.frontends[index].xClosed:
        return manager.frontends[index]

proc unregister(manager: KosmoWindowManager, frontend: KosmoApplication) =
  if manager.isNil:
    return
  let index = manager.frontends.find(frontend)
  if index >= 0:
    manager.frontends.delete(index)

protocol KosmoWindowLifecycleDelegate of nimkit.WindowDelegateProtocol:
  method windowDidClose(lifecycle: KosmoWindowLifecycle, window: nimkit.Window) =
    discard window
    if not lifecycle.frontend.isNil:
      lifecycle.frontend[].close()

proc newKosmoWindowManager*(
    app = nimkit.sharedApplication(), keyBindingsPath = ""
): KosmoWindowManager =
  ## Create the owner for all project and file windows in a Kosmo session.
  if not app.isNil:
    app.icon = nimkit.newImageResourceFromData(KosmoIconPng, name = "kosmo-icon")
    app.aboutInfo = nimkit.ApplicationAboutInfo(
      version: KosmoVersion, buildVersion: KosmoGitHash, credits: KosmoAboutCredits
    )
  KosmoWindowManager(application: app, keyBindingsPath: keyBindingsPath)

func hasFileBrowser*(frontend: KosmoApplication): bool =
  ## Return whether this window displays a project file browser.
  not frontend.isNil and frontend.xHasFileBrowser

func projectWindowTitle(rootPaths: openArray[string]): string =
  result = "Kosmo"
  if rootPaths.len > 0:
    result.add " (" & nimkit.fileBrowserDisplayName(rootPaths[0])
    if rootPaths.len > 1:
      result.add " + " & $(rootPaths.len - 1)
    result.add ")"

proc updateProjectWindowTitle(frontend: KosmoApplication) =
  if not frontend.isNil and not frontend.window.isNil and not frontend.fileTree.isNil:
    frontend.window.title = projectWindowTitle(frontend.fileTree.rootPaths)

proc managedWindows*(manager: KosmoWindowManager): seq[KosmoApplication] =
  ## Return the live Kosmo windows owned by this session.
  if manager.isNil:
    return
  for frontend in manager.frontends:
    if not frontend.xClosed:
      result.add frontend

proc configureKosmoSettingsMenu(frontend: KosmoApplication) =
  let mainMenu = frontend.application.mainMenu()
  if mainMenu.isNil or mainMenu.len == 0:
    return
  let applicationMenu = mainMenu[0].submenu()
  if not applicationMenu.isNil and applicationMenu.len > 2:
    let settingsItem = applicationMenu[2]
    let manager =
      if frontend.xWindowManager.isNil:
        nil
      else:
        frontend.xWindowManager[]
    settingsItem.identifier = KosmoShowSettingsAction
    settingsItem.action = nimkit.actionSelector(KosmoShowSettingsAction)
    settingsItem.target = nimkit.newActionTarget(
      nimkit.actionSelector(KosmoShowSettingsAction)
    ) do(sender: nimkit.DynamicAgent):
      discard sender
      if not manager.isNil:
        let active = manager.activeFrontend()
        if not active.isNil:
          discard active.showSettings()

  let windowMenu = frontend.application.windowsMenu()
  if windowMenu.isNil:
    return
  var merendaSettingsIndex = -1
  for index, item in windowMenu.items():
    if not item.isNil and
        item.action().name == nimkit.actionSelector("showMerendaSettings").name:
      merendaSettingsIndex = index
      break
  if merendaSettingsIndex < 0:
    return
  discard windowMenu.removeItem(windowMenu[merendaSettingsIndex])
  if merendaSettingsIndex < windowMenu.len and
      windowMenu[merendaSettingsIndex].isSeparatorItem():
    discard windowMenu.removeItem(windowMenu[merendaSettingsIndex])

proc configureKosmoStandardActionMenus(frontend: KosmoApplication) =
  let mainMenu = frontend.application.mainMenu()
  if mainMenu.isNil or mainMenu.len < 3:
    return
  let editMenu = mainMenu[2].submenu()
  if not editMenu.isNil:
    for item in editMenu.items():
      let action = item.action()
      var identifier = ""
      if action.name == nimkit.undo().name:
        identifier = KosmoUndoAction
      elif action.name == nimkit.redo().name:
        identifier = KosmoRedoAction
      elif action.name == nimkit.cut().name:
        identifier = KosmoCutAction
      elif action.name == nimkit.copy().name:
        identifier = KosmoCopyAction
      elif action.name == nimkit.paste().name:
        identifier = KosmoPasteAction
      elif action.name == nimkit.selectAll().name:
        identifier = KosmoSelectAllAction
      if identifier.len > 0:
        item.identifier = identifier

  let applicationMenu = mainMenu[0].submenu()
  if applicationMenu.isNil:
    return
  for item in applicationMenu.items():
    if item.action().name == nimkit.terminate().name:
      let app = frontend.application
      item.identifier = KosmoQuitAction
      item.action = nimkit.actionSelector(KosmoQuitAction)
      item.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoQuitAction)) do(
        sender: nimkit.DynamicAgent
      ):
        discard sender
        discard app.terminate()
      break

proc configureKosmoWorkspaceMenu(frontend: KosmoApplication) =
  let windowMenu = frontend.application.windowsMenu()
  if windowMenu.isNil or not windowMenu.menuItemWithIdentifier(KosmoNextTabAction).isNil:
    return
  let manager =
    if frontend.xWindowManager.isNil:
      nil
    else:
      frontend.xWindowManager[]

  proc addAction(title, identifier: string) =
    let item = nimkit.newMenuItem(title, nimkit.actionSelector(identifier))
    item.identifier = identifier
    item.target = nimkit.newActionTarget(nimkit.actionSelector(identifier)) do(
      sender: nimkit.DynamicAgent
    ):
      discard sender
      if manager.isNil:
        return
      let active = manager.activeFrontend()
      if active.isNil:
        return
      let
        controller = active.dockController
        group = controller.activePaneGroup()
      case identifier
      of KosmoPreviousTabAction:
        controller.selectRelativePaneTab(group, -1)
      of KosmoNextTabAction:
        controller.selectRelativePaneTab(group, 1)
      of KosmoSplitHorizontalAction:
        discard controller.splitCurrentPaneTab(group, nimkit.dpBottom)
      of KosmoSplitVerticalAction:
        discard controller.splitCurrentPaneTab(group, nimkit.dpRight)
      of KosmoShowFileExplorerAction:
        discard active.showFileExplorer()
      of KosmoFindInFilesAction:
        discard active.showFindInFiles()
      else:
        if identifier.startsWith(KosmoFocusPanelActionPrefix):
          discard
            controller.focusPanel(nimkit.actionSelector(identifier).focusPanelNumber())
    discard windowMenu.addItem(item)

  windowMenu.addSeparator()
  addAction("Previous Tab", KosmoPreviousTabAction)
  addAction("Next Tab", KosmoNextTabAction)
  windowMenu.addSeparator()
  addAction("Split Below", KosmoSplitHorizontalAction)
  addAction("Split Right", KosmoSplitVerticalAction)
  windowMenu.addSeparator()
  addAction("Show Files", KosmoShowFileExplorerAction)
  addAction("Find in Files", KosmoFindInFilesAction)

  let
    focusMenu = nimkit.newMenu("Focus Panel")
    focusMenuItem = nimkit.newMenuItem("Focus Panel")
  focusMenuItem.submenu = focusMenu
  for panelNumber in 1 .. KosmoMaxFocusPanelShortcut:
    let
      targetPanelNumber = panelNumber
      identifier = targetPanelNumber.focusPanelAction()
    let item = nimkit.newMenuItem(
      "Panel " & $targetPanelNumber, nimkit.actionSelector(identifier)
    )
    item.identifier = identifier
    item.target = nimkit.newActionTarget(nimkit.actionSelector(identifier)) do(
      sender: nimkit.DynamicAgent
    ):
      discard sender
      if not manager.isNil:
        let active = manager.activeFrontend()
        if not active.isNil:
          discard active.dockController.focusPanel(targetPanelNumber)
    discard focusMenu.addItem(item)
  discard windowMenu.addItem(focusMenuItem)

proc newKosmoApplication(
    manager: KosmoWindowManager, filePath = "", hasFileBrowser = true
): KosmoApplication =
  let
    app = manager.application
    keyBindingsPath = manager.keyBindingsPath
  var shortcutConfiguration = initKosmoShortcutConfiguration()
  var keyBindingErrors: seq[string]
  if keyBindingsPath.len > 0:
    let loaded = loadKosmoShortcutConfiguration(keyBindingsPath, shortcutConfiguration)
    shortcutConfiguration = loaded.configuration
    keyBindingErrors = loaded.errors
  let existingMainMenu = app.mainMenu()
  if existingMainMenu.isNil or existingMainMenu.len < 5 or
      existingMainMenu[1].title != "File" or existingMainMenu[2].title != "Edit" or
      existingMainMenu[3].title != "Window" or existingMainMenu[4].title != "Help":
    app.installStandardMainMenu()
  let
    initialRootPath =
      if not hasFileBrowser:
        ""
      elif dirExists(filePath):
        absolutePath(filePath)
      else:
        getCurrentDir()
    editorView = newKosmoEditorView()
    editorPane = newKosmoEditorPane(editorView)
    fileTree = newKosmoFileTree(initialRootPath)
    searchPanel = newKosmoFileSearchPanel(fileTree.rootPath)
    quickOpenPanel = newKosmoQuickOpenPanel(fileTree.rootPath)
    sidebarTabs = nimkit.newCompactTabView(
      [
        nimkit.initCompactTabItem(
          KosmoFilesTabIdentifier,
          "Files",
          nimkit.newSvgMtsdfResource(KosmoFilesIconSvg, "kosmo-files"),
          fileTree,
        ),
        nimkit.initCompactTabItem(
          KosmoFindTabIdentifier,
          "Find",
          nimkit.newSvgMtsdfResource(KosmoFindIconSvg, "kosmo-find"),
          searchPanel,
        ),
      ]
    )
    sidebarPane = newKosmoSidebarPane(sidebarTabs, fileTree, searchPanel)
    splitView = nimkit.newSplitView(nimkit.laHorizontal)
    dockView = nimkit.newDockView()
    mainMenu = app.mainMenu()
    fileMenu = nimkit.newMenu("File")
    fileItem = mainMenu[1]
    newItem = nimkit.newMenuItem("New…", nimkit.actionSelector(KosmoNewFileAction))
    openItem = nimkit.newMenuItem("Open…", nimkit.actionSelector(KosmoOpenFileAction))
    openProjectItem = nimkit.newMenuItem(
      "Open Project…", nimkit.actionSelector(KosmoOpenProjectAction)
    )
    quickOpenItem =
      nimkit.newMenuItem("Open Quickly…", nimkit.actionSelector(KosmoQuickOpenAction))
    terminalItem =
      nimkit.newMenuItem("New Terminal", nimkit.actionSelector(KosmoNewTerminalAction))
    saveItem = nimkit.newMenuItem("Save", nimkit.actionSelector(KosmoSaveAction))
    closeTabItem =
      nimkit.newMenuItem("Close Tab", nimkit.actionSelector(KosmoCloseTabAction))
    closeWindowItem =
      nimkit.newMenuItem("Close Window", nimkit.actionSelector(KosmoCloseWindowAction))
  editorView.applyKosmoEditorStyle(app.effectiveAppearance())
  newItem.identifier = KosmoNewFileAction
  openItem.identifier = KosmoOpenFileAction
  openProjectItem.identifier = KosmoOpenProjectAction
  quickOpenItem.identifier = KosmoQuickOpenAction
  terminalItem.identifier = KosmoNewTerminalAction
  saveItem.identifier = KosmoSaveAction
  closeTabItem.identifier = KosmoCloseTabAction
  closeWindowItem.identifier = KosmoCloseWindowAction
  fileItem.submenu = fileMenu
  discard fileMenu.addItem(newItem)
  discard fileMenu.addItem(openItem)
  discard fileMenu.addItem(openProjectItem)
  fileMenu.addSeparator()
  discard fileMenu.addItem(quickOpenItem)
  discard fileMenu.addItem(terminalItem)
  fileMenu.addSeparator()
  discard fileMenu.addItem(saveItem)
  fileMenu.addSeparator()
  discard fileMenu.addItem(closeTabItem)
  discard fileMenu.addItem(closeWindowItem)

  if hasFileBrowser:
    splitView.addPane(sidebarPane, minSize = 160.0'f32, maxSize = 420.0'f32)
  splitView.addPane(dockView, minSize = 320.0'f32)

  let
    statusLabel = nimkit.newStatusLabel("Ready")
    documentView = newKosmoContentView(splitView, statusLabel, quickOpenPanel)
    contentView = nimkit.newMenuRootView(mainMenu, documentView)
  editorView.statusLabel = statusLabel
  editorView.syncChrome()
  result = KosmoApplication(
    application: app,
    window: nimkit.newWindow(
      projectWindowTitle(fileTree.rootPaths), nimkit.rect(120, 100, 1024, 720)
    ),
    editorView: editorView,
    editorPane: editorPane,
    documentTabs: editorView.documentTabs,
    statusLabel: statusLabel,
    fileTree: fileTree,
    sidebarPane: sidebarPane,
    sidebarTabs: sidebarTabs,
    searchPanel: searchPanel,
    quickOpenPanel: quickOpenPanel,
    splitView: splitView,
    dockView: dockView,
    contentView: contentView,
    documentView: documentView,
    xTerminalOptionAsMeta: true,
    xWindowManager: manager.unsafeWeakRef(),
    xHasFileBrowser: hasFileBrowser,
  )
  let
    controller = KosmoDockController(
      editor: editorView.editor,
      shortcutBindings: shortcutConfiguration.bindings,
      shortcutProfile: shortcutConfiguration.profile,
      editorInputPolicy: shortcutConfiguration.editorInput,
    )
    mainHost = KosmoDockHost(
      workspace: dockView,
      window: result.window,
      contentView: contentView,
      statusLabel: statusLabel,
      primary: true,
    )
  result.dockController = controller
  result.xWindowLifecycle = KosmoWindowLifecycle(frontend: result.unsafeWeakRef())
  nimkit.initResponder(result.xWindowLifecycle)
  discard result.xWindowLifecycle.withProtocol(KosmoWindowLifecycleDelegate)
  result.window.delegate = result.xWindowLifecycle
  manager.frontends.add result
  controller.frontend = result.unsafeWeakRef()
  sidebarPane.dockController = controller.unsafeWeakRef()
  sidebarPane.observeWindow(result.window)
  quickOpenPanel.observeWindow(result.window)
  documentView.onShowFileExplorer = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].showFileExplorer()
  documentView.onFindInFiles = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].showFindInFiles()
  documentView.onQuickOpen = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].showQuickOpen()
  documentView.onNewTerminal = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].newTerminal()
  documentView.onFocusPanel = proc(panelNumber: int) =
    discard controller.focusPanel(panelNumber)
  controller.hosts.add mainHost
  controller.installShortcutBindings(result.window)
  discard controller.newEditorGroup(
    dockView,
    result.window,
    editorView.editor.initialBufferIds(),
    editorView,
    editorPane,
    addToWorkspace = true,
  )

  let frontend = result.unsafeWeakRef()
  result.configureKosmoSettingsMenu()
  result.configureKosmoStandardActionMenus()
  result.configureKosmoWorkspaceMenu()
  result.synchronizeKosmoMenuBindings()
  newItem.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoNewFileAction)) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      discard active.newEditorTab()
  openItem.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoOpenFileAction)) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    manager.chooseFile()
  openProjectItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoOpenProjectAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    manager.chooseProject()
  quickOpenItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoQuickOpenAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      discard active.showQuickOpen()
  terminalItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoNewTerminalAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      discard active.newTerminal()
  saveItem.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoSaveAction)) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      let controller = active.dockController
      controller.saveCurrentPaneTab(controller.activePaneGroup())
  closeTabItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoCloseTabAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      let controller = active.dockController
      controller.closeCurrentPaneTab(controller.activePaneGroup())
  closeWindowItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoCloseWindowAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      let group = active.dockController.activePaneGroup()
      if not group.isNil:
        group.window.close()
  fileTree.onOpenFile = proc(path: string, disposition: FileTreeOpenDisposition) =
    if frontend.isNil:
      return
    let activeView = frontend[].dockController.activeEditorView()
    if activeView.isNil:
      return
    case disposition
    of fodTemporary:
      discard activeView.previewFile(path)
    of fodPermanent:
      discard activeView.openFile(path)
  searchPanel.onOpenResult = proc(
      match: nimkit.FileSearchMatch, disposition: FileTreeOpenDisposition
  ) =
    if frontend.isNil:
      return
    let activeView = frontend[].dockController.activeEditorView()
    if not activeView.isNil:
      discard activeView.openSearchResult(match, disposition)
  if fileExists(filePath):
    discard result.dockController.activeEditorView().openFile(filePath)
  elif dirExists(filePath):
    statusLabel.text = absolutePath(filePath)
  if keyBindingErrors.len > 0:
    statusLabel.text = keyBindingErrors.join("; ")
  discard fileTree.startGitStatusMonitoring()

proc newKosmoApplication*(
    app = nimkit.sharedApplication(),
    filePath = "",
    keyBindingsPath = "",
    hasFileBrowser = true,
): KosmoApplication =
  let manager = newKosmoWindowManager(app, keyBindingsPath)
  result = newKosmoApplication(manager, filePath, hasFileBrowser)

proc openProject*(
    manager: KosmoWindowManager, path: string
): KosmoApplication {.discardable.} =
  ## Create and show a project window rooted at `path`.
  if manager.isNil or path.len == 0 or not dirExists(path):
    return
  result = newKosmoApplication(manager, absolutePath(path), hasFileBrowser = true)
  result.show()

proc openProject*(
    frontend: KosmoApplication, path: string
): KosmoApplication {.discardable.} =
  ## Create a project window in the same application session as `frontend`.
  if frontend.isNil or frontend.xWindowManager.isNil:
    return
  result = frontend.xWindowManager[].openProject(path)

proc openFileWindow(
    manager: KosmoWindowManager, path: string
): KosmoApplication {.discardable.} =
  if manager.isNil or not fileExists(path):
    return
  result = newKosmoApplication(manager, absolutePath(path), hasFileBrowser = false)
  result.show()

proc openPath*(manager: KosmoWindowManager, path: string): bool {.discardable.} =
  ## Apply Open… semantics to the active window, creating one when necessary.
  if manager.isNil:
    return
  let frontend = manager.activeFrontend()
  if not frontend.isNil:
    return frontend.openPath(path)
  if dirExists(path):
    result = not manager.openProject(path).isNil
  elif fileExists(path):
    result = not manager.openFileWindow(path).isNil

proc chooseFile(frontend: KosmoApplication) =
  if frontend.isNil:
    return
  let panel = nimkit.newOpenPanel()
  panel.message = "Open a file or add a folder to this window."
  panel.canChooseDirectories = true
  panel.directoryUrl = frontend.fileTree.rootPath
  if frontend.application.runModal(panel) == nimkit.PanelResponseOk:
    discard frontend.openPath(nimkit.filePathFromUrl(panel.selectedUrl()))

proc chooseFile(manager: KosmoWindowManager) =
  if manager.isNil:
    return
  let frontend = manager.activeFrontend()
  if not frontend.isNil:
    frontend.chooseFile()
    return
  let panel = nimkit.newOpenPanel()
  panel.message = "Open a file or folder in Kosmo."
  panel.canChooseDirectories = true
  panel.directoryUrl = getCurrentDir()
  if manager.application.runModal(panel) != nimkit.PanelResponseOk:
    return
  discard manager.openPath(nimkit.filePathFromUrl(panel.selectedUrl()))

proc chooseProject(manager: KosmoWindowManager) =
  if manager.isNil:
    return
  let
    frontend = manager.activeFrontend()
    panel = nimkit.newOpenPanel()
  panel.window.title = "Open Project"
  panel.message = "Choose a folder to open in a new Kosmo window."
  panel.prompt = "Open Project"
  panel.canChooseFiles = false
  panel.canChooseDirectories = true
  panel.directoryUrl =
    if frontend.isNil or frontend.fileTree.rootPath.len == 0:
      getCurrentDir()
    else:
      frontend.fileTree.rootPath
  if manager.application.runModal(panel) == nimkit.PanelResponseOk:
    discard manager.openProject(nimkit.filePathFromUrl(panel.selectedUrl()))

proc loadKosmoKeyBindings*(
    frontend: KosmoApplication, path: string
): nimkit.KeyBindingJsonResult =
  ## Reset Kosmo shortcuts to their defaults, then apply overrides from `path`.
  if frontend.isNil or frontend.dockController.isNil:
    result.errors.add "The Kosmo frontend is closed"
    return
  let loaded = loadKosmoShortcutConfiguration(path)
  result.applied = loaded.applied
  result.errors = loaded.errors
  frontend.dockController.shortcutBindings = loaded.configuration.bindings
  frontend.dockController.shortcutProfile = loaded.configuration.profile
  frontend.dockController.editorInputPolicy = loaded.configuration.editorInput
  for host in frontend.dockController.hosts:
    frontend.dockController.installShortcutBindings(host.window)
  frontend.synchronizeKosmoMenuBindings()
  frontend.updateShortcutSettingsWindow()

proc openPath*(frontend: KosmoApplication, path: string): bool {.discardable.} =
  ## Open a file here, or add a folder to this window's visible browser.
  if frontend.isNil or frontend.dockController.isNil:
    return
  if dirExists(path):
    if not frontend.hasFileBrowser():
      if frontend.xWindowManager.isNil:
        return
      return not frontend.xWindowManager[].openProject(path).isNil
    let root = absolutePath(path)
    result = root in frontend.fileTree.rootPaths or frontend.fileTree.addRootPath(root)
  elif fileExists(path):
    result = frontend.dockController.activeEditorView().openFile(path)
  if result and dirExists(path):
    frontend.updateProjectWindowTitle()
    if not frontend.searchPanel.isNil:
      frontend.searchPanel.rootPath = frontend.fileTree.rootPath

proc openDocument*(
    frontend: KosmoApplication, document: KosmoPaneDocument
): bool {.discardable.} =
  ## Open any view-backed document in the currently focused pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  let group = frontend.dockController.activePaneGroup()
  frontend.dockController.openPaneDocument(group, document)

proc openTerminal*(
    frontend: KosmoApplication, options = nimkit.initTerminalSpawnOptions()
): bool {.discardable.} =
  ## Open a terminal document in the currently focused pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  var resolvedOptions = options
  if resolvedOptions.workingDirectory.len == 0:
    resolvedOptions.workingDirectory = frontend.fileTree.rootPath
  let group = frontend.dockController.activePaneGroup()
  frontend.dockController.openTerminal(group, resolvedOptions)

proc editorGroups*(frontend: KosmoApplication): seq[KosmoEditorGroup] =
  ## Return the editor groups currently hosted by Kosmo dock workspaces.
  if not frontend.isNil and not frontend.dockController.isNil:
    result = frontend.dockController.groups

proc detachedEditorWindows*(frontend: KosmoApplication): seq[nimkit.Window] =
  ## Return the live windows created by detaching document tabs.
  if frontend.isNil or frontend.dockController.isNil:
    return
  for host in frontend.dockController.hosts:
    if not host.primary and not host.window.isNil and not host.window.isClosed():
      result.add host.window

proc show*(frontend: KosmoApplication) =
  ## Present the Kosmo window and make the editor its first responder.
  if not frontend.isNil:
    discard frontend.application.showWindow(
      frontend.window, frontend.contentView, frontend.dockController.activeEditorView()
    )

proc close*(frontend: KosmoApplication) =
  ## Release the editor resources held by the frontend.
  if frontend.isNil or frontend.xClosed:
    return
  frontend.xClosed = true
  if not frontend.quickOpenPanel.isNil and frontend.quickOpenPanel.isOpen():
    frontend.quickOpenPanel.dismiss()
  if not frontend.xSettingsWindow.isNil and
      not frontend.xSettingsWindow.window.isClosed():
    frontend.xSettingsWindow.window.close()
  if not frontend.dockController.isNil:
    for group in frontend.dockController.groups:
      group.editorView.tabsDelegate.stopObservingWindow()
      for document in group.documents:
        discard document.close()
    let hosts = frontend.dockController.hosts
    for host in hosts:
      if not host.primary and not host.window.isNil and not host.window.isClosed():
        host.window.close()
  if not frontend.sidebarPane.isNil:
    frontend.sidebarPane.stopObservingWindow()
  if not frontend.quickOpenPanel.isNil:
    frontend.quickOpenPanel.stopObservingWindow()
  if not frontend.editorView.isNil:
    frontend.editorView.editor.close()
  if not frontend.searchPanel.isNil:
    frontend.searchPanel.close()
  if not frontend.fileTree.isNil:
    frontend.fileTree.stopGitStatusMonitoring()
  if not frontend.xWindowManager.isNil:
    frontend.xWindowManager[].unregister(frontend)

proc close*(manager: KosmoWindowManager) =
  ## Release every live frontend owned by this Kosmo session.
  if manager.isNil:
    return
  let frontends = manager.frontends
  manager.frontends.setLen(0)
  for frontend in frontends:
    frontend.close()

proc runKosmo*(filePath = "") =
  ## Run Kosmo as a standalone NimKit text-editor application.
  let
    app = nimkit.sharedApplication()
    keyBindingsPath = defaultKosmoKeyBindingsPath()
    manager = newKosmoWindowManager(
      app, keyBindingsPath = if fileExists(keyBindingsPath): keyBindingsPath else: ""
    )
  let frontend = newKosmoApplication(
    manager, filePath, hasFileBrowser = filePath.len == 0 or not fileExists(filePath)
  )
  defer:
    manager.close()
  frontend.show()
  frontend.application.run()

when isMainModule:
  let commandLine = parseKosmoCommandLine(commandLineParams())
  if commandLine.help:
    echo KosmoUsage
  elif commandLine.background:
    launchKosmoInBackground(commandLine.arguments)
  else:
    runKosmo(commandLine.filePath)
