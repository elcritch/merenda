## A frontend-oriented facade for the Moe editor engine.
##
## Kosmo owns a Moe editor and projects it into a cell grid. GUI frontends
## translate their input and paint the returned cells; Moe implementation types
## remain private to this module.

import std/[algorithm, options, os, strutils, unicode]

import pkg/celina
from pkg/figdraw import figDataDir
import pkg/results as pkgResults

import
  moepkg/[
    editor, editor_buffers, editor_display, editor_file, editor_frame,
    editor_render_views, frontend_input, handler, completion, command_line, config,
    config_loader, editor_window, encoding, motion,
  ]
import moepkg/buffer/undo as moeUndo
from moepkg/buffer/core import BufferId, getLine, getTextString, len
from moepkg/command_handlers/visual_commands import visualDelete
from moepkg/registers import setYankedRegister
from moepkg/color import EditorColorPairIndex, Rgb, ThemeColors, isTermDefaultColor
from moepkg/theme import DefaultColors
from moepkg/render_utils import steadyBottomAreaHeight
import moepkg/key_bindings/registry as moeKeys
import moepkg/modes as moeModes
import moepkg/types as moeTypes

when hasAsyncSupport:
  {.error: "Merenda's Moe facade requires Celina's synchronous backend".}

type
  KosmoEditor* = ref object
    editor: Editor
    temporaryBufferId: Option[BufferId]

  KosmoBufferId* = distinct int
    ## Stable identity for a Moe buffer without exposing Moe's buffer types.

  KosmoTab* = object
    ## Frontend-neutral information for one tab in the active editor window.
    id*: KosmoBufferId
    title*: string
    filePath*: Option[string]
    modified*: bool
    readOnly*: bool
    active*: bool
    temporary*: bool

  KosmoStatus* = object
    ## A consistent snapshot of the status information Kosmo displays.
    modeLabel*: string
    message*: string
    gitBranch*: string
    gitAdded*: int
    gitModified*: int
    gitDeleted*: int

  KosmoCommandLine* = object
    ## The command input currently owned by Moe's command overlay.
    visible*: bool
    text*: string
    cursor*: int

  KosmoCursor* = object ## Moe's cursor position in the rendered cell grid.
    row*: int
    column*: int
    visible*: bool

  KosmoBufferCursor* = object ## Zero-based cursor position in the active text buffer.
    line*: int
    column*: int

  KosmoSelectionKind* {.pure.} = enum
    Character
    Block
    Line

  KosmoSelection* = object
    ## Value snapshot of Moe's active selection using zero-based rune positions.
    ## Endpoints are inclusive; block selections describe a rectangle.
    bufferId*: KosmoBufferId
    kind*: KosmoSelectionKind
    anchor*: KosmoBufferCursor
    focus*: KosmoBufferCursor
    first*: KosmoBufferCursor
    last*: KosmoBufferCursor

  KosmoEditorMode* {.pure.} = enum
    Normal
    Insert
    Replace
    Visual
    Command
    Other

  KosmoKeyOutcome* = object ## The semantic outcome of sending a physical key to Moe.
    valid*: bool
    continueRunning*: bool
    closeTabRequested*: bool

  KosmoEditorViewState* = object
    ## Cursor and viewport state for one buffer projection in an embedding frontend.
    bufferId: Option[KosmoBufferId]
    cursorLine: int
    cursorColumn: int
    preferredColumn: int
    viewportTopLine: int
    viewportTopWrapOffset: int
    viewportLeftColumn: int
    viewportDetachedFromCursor: bool
    scrollAnimation: moeTypes.ScrollAnimation

  KosmoTabCloseResult* = object
    closed*: bool
    message*: string

  KosmoSaveResult* = object
    saved*: bool
    message*: string

  KosmoMoeThemeKind* = enum
    kmmtDefault
    kmmtConfig

  KosmoMoeThemeColor* = object
    ## An RGB theme color that can be presented without exposing Moe types.
    red*, green*, blue*: uint8

  KosmoMoeThemePreview* = object
    ## Key colors used by Kosmo's compact Moe theme preview.
    background*: KosmoMoeThemeColor
    foreground*: KosmoMoeThemeColor
    keyword*: KosmoMoeThemeColor
    functionName*: KosmoMoeThemeColor
    stringLiteral*: KosmoMoeThemeColor
    comment*: KosmoMoeThemeColor

  KosmoMoeTheme* = object
    ## A Moe theme that Kosmo can present without exposing Moe configuration types.
    kind*: KosmoMoeThemeKind
    identifier*: string
    name*: string
    path*: string
    preview*: KosmoMoeThemePreview

  KosmoMoeThemeApplyResult* = object
    applied*: bool
    message*: string

  RenderBuffer* = object
    buffer: Buffer

  RenderCell* = Cell

  KeyModifier* = enum
    kmControl
    kmAlt
    kmShift
    kmMeta

  GridRegion* = object ## A rectangle in the rendered cell grid.
    row*, column*, rows*, columns*: int

  PointerButton* = enum
    pbPrimary
    pbMiddle
    pbSecondary
    pbOther

  PointerAction* = enum
    paPress
    paRelease
    paMove
    paDrag

  PointerInput* = object ## A pointer event in rendered cell-grid coordinates.
    row*, column*: int
    button*: PointerButton
    action*: PointerAction
    clickCount*: Natural
    modifiers*: set[KeyModifier]

  ScrollInput* = object
    ## A physical-line scroll event in rendered cell-grid coordinates.
    row*, column*: int
    deltaPhysicalRows*: int
    modifiers*: set[KeyModifier]

  ScrollOutcome* = object
    ## Moe's requested and applied scroll movement, plus repaint bounds.
    handled*: bool
    region*: GridRegion
    requestedRows*: int
    appliedRows*: int
    viewportPhysicalRowsMoved*: int

  FileOpenResult* = object ## The outcome of loading a file into the active Moe buffer.
    loaded*: bool
    message*: string

func initGridRegion*(row, column, rows, columns: int): GridRegion =
  GridRegion(row: row, column: column, rows: max(rows, 0), columns: max(columns, 0))

func initPointerInput*(
    row, column: int,
    button: PointerButton = pbPrimary,
    action: PointerAction = paPress,
    clickCount: Natural = 1,
    modifiers: set[KeyModifier] = {},
): PointerInput =
  PointerInput(
    row: row,
    column: column,
    button: button,
    action: action,
    clickCount: clickCount,
    modifiers: modifiers,
  )

func initScrollInput*(
    row, column, deltaPhysicalRows: int, modifiers: set[KeyModifier] = {}
): ScrollInput =
  ScrollInput(
    row: row, column: column, deltaPhysicalRows: deltaPhysicalRows, modifiers: modifiers
  )

const KosmoMoeDefaultThemeIdentifier* = "default"

proc moeThemesDirectory*(): string =
  ## Return Moe's standard directory for user-installed TOML themes.
  getHomeDir() / ".config" / "moe" / "themes"

proc bundledMoeThemesDirectory*(): string =
  ## Return Kosmo's bundled Moe theme directory beneath the active data path.
  figDataDir() / "moe" / "themes"

proc normalizedThemePath(path: string): string =
  normalizedPath(absolutePath(path.expandTilde()))

proc configThemeIdentifier(path: string): string =
  "config:" & path.normalizedThemePath()

func moeThemeName(path: string): string =
  let baseName = splitFile(path).name
  var capitalizeNext = true
  for character in baseName:
    if character in {'-', '_'}:
      if result.len > 0 and result[^1] != ' ':
        result.add ' '
      capitalizeNext = true
    elif capitalizeNext:
      result.add character.toUpperAscii()
      capitalizeNext = false
    else:
      result.add character

func moeThemeColor(rgb: Rgb, fallback: KosmoMoeThemeColor): KosmoMoeThemeColor =
  if rgb.isTermDefaultColor():
    return fallback
  KosmoMoeThemeColor(red: rgb.red.uint8, green: rgb.green.uint8, blue: rgb.blue.uint8)

func moeThemePreview(colors: ThemeColors): KosmoMoeThemePreview =
  let
    fallbackBackground = KosmoMoeThemeColor(red: 0, green: 0, blue: 0)
    fallbackForeground = KosmoMoeThemeColor(red: 218, green: 218, blue: 218)
    background = colors[EditorColorPairIndex.default].background.rgb.moeThemeColor(
      fallbackBackground
    )
    foreground = colors[EditorColorPairIndex.default].foreground.rgb.moeThemeColor(
      fallbackForeground
    )
  KosmoMoeThemePreview(
    background: background,
    foreground: foreground,
    keyword:
      colors[EditorColorPairIndex.keyword].foreground.rgb.moeThemeColor(foreground),
    functionName:
      colors[EditorColorPairIndex.functionName].foreground.rgb.moeThemeColor(foreground),
    stringLiteral:
      colors[EditorColorPairIndex.stringLit].foreground.rgb.moeThemeColor(foreground),
    comment:
      colors[EditorColorPairIndex.comment].foreground.rgb.moeThemeColor(foreground),
  )

proc themePreview(path: string): KosmoMoeThemePreview =
  let loaded = loadThemeFromToml(path)
  if loaded.isOk:
    return loaded.get().moeThemePreview()
  DefaultColors.moeThemePreview()

proc configMoeTheme(path: string): KosmoMoeTheme =
  let normalizedPath = path.normalizedThemePath()
  KosmoMoeTheme(
    kind: kmmtConfig,
    identifier: normalizedPath.configThemeIdentifier(),
    name: normalizedPath.moeThemeName(),
    path: normalizedPath,
    preview: normalizedPath.themePreview(),
  )

proc sortConfigThemes(themes: var seq[KosmoMoeTheme]) =
  themes.sort do(left, right: KosmoMoeTheme) -> int:
    result = cmp(left.name.toLowerAscii(), right.name.toLowerAscii())
    if result == 0:
      result = cmp(left.identifier, right.identifier)

proc discoverMoeThemes*(themesDirectory: string): seq[KosmoMoeTheme] =
  ## Discover Moe-compatible TOML themes in `themesDirectory`.
  result.add KosmoMoeTheme(
    kind: kmmtDefault,
    identifier: KosmoMoeDefaultThemeIdentifier,
    name: "Default",
    preview: DefaultColors.moeThemePreview(),
  )
  if not dirExists(themesDirectory):
    return
  var configThemes: seq[KosmoMoeTheme]
  try:
    for path in walkFiles(themesDirectory / "*.toml"):
      configThemes.add path.configMoeTheme()
  except OSError:
    discard
  configThemes.sortConfigThemes()
  result.add configThemes

proc mergeConfigThemes(
    themes: var seq[KosmoMoeTheme], additions: openArray[KosmoMoeTheme]
) =
  for addition in additions:
    if addition.kind == kmmtConfig:
      var matchingIndex = -1
      for index in 1 ..< themes.len:
        if themes[index].name.toLowerAscii() == addition.name.toLowerAscii():
          matchingIndex = index
          break
      if matchingIndex >= 0:
        themes[matchingIndex] = addition
      else:
        themes.add addition

proc sortAvailableMoeThemes(themes: var seq[KosmoMoeTheme]) =
  if themes.len > 2:
    var configThemes = themes[1 ..^ 1]
    configThemes.sortConfigThemes()
    themes.setLen(1)
    themes.add configThemes

proc activeMoeThemeIdentifier*(editor: KosmoEditor): string =
  ## Return the stable identifier for the theme currently configured in Moe.
  if editor.isNil or editor.editor.isNil:
    return
  case editor.editor.config.theme.kind
  of tkDefault:
    KosmoMoeDefaultThemeIdentifier
  of tkConfig:
    editor.editor.config.theme.path.configThemeIdentifier()
  of tkVscode:
    "vscode"

proc availableMoeThemes*(editor: KosmoEditor): seq[KosmoMoeTheme] =
  ## Return bundled and installed themes, retaining a custom active path.
  result = discoverMoeThemes(bundledMoeThemesDirectory())
  result.mergeConfigThemes(discoverMoeThemes(moeThemesDirectory()))
  if editor.isNil or editor.editor.isNil or editor.editor.config.theme.kind != tkConfig:
    result.sortAvailableMoeThemes()
    return
  let currentPath = editor.editor.config.theme.path.normalizedThemePath()
  if not fileExists(currentPath):
    result.sortAvailableMoeThemes()
    return
  let current = currentPath.configMoeTheme()
  for theme in result:
    if theme.identifier == current.identifier:
      result.sortAvailableMoeThemes()
      return
  result.mergeConfigThemes([current])
  result.sortAvailableMoeThemes()

proc applyMoeTheme*(
    editor: KosmoEditor, theme: KosmoMoeTheme
): KosmoMoeThemeApplyResult =
  ## Apply a discovered theme to Moe's live configuration.
  if editor.isNil or editor.editor.isNil:
    return KosmoMoeThemeApplyResult(message: "The editor is closed.")
  if theme.kind == kmmtConfig and not fileExists(theme.path):
    return KosmoMoeThemeApplyResult(message: "Theme not found: " & theme.name)

  let previousTheme = editor.editor.config.theme
  case theme.kind
  of kmmtDefault:
    editor.editor.config.theme.kind = tkDefault
    editor.editor.config.theme.path = ""
  of kmmtConfig:
    editor.editor.config.theme.kind = tkConfig
    editor.editor.config.theme.path = theme.path

  var validation = newValidationResult()
  initTheme(editor.editor.config, validation)
  if validation.hasErrors:
    editor.editor.config.theme = previousTheme
    initTheme(editor.editor.config)
    result.message = "Failed to load theme: " & validation.toErrorMessages().join("; ")
    editor.editor.state.statusMessage = result.message
    return

  result.applied = true
  result.message = "Theme changed to: " & theme.name
  editor.editor.state.statusMessage = result.message

proc newKosmoEditor*(text = ""): KosmoEditor =
  ## Create an editor with Moe's default configuration and optional initial text.
  var config = newEditorConfig()
  config.standard.mouse = true
  config.standard.statusLine = false
  config.tabLine.enable = false
  result = KosmoEditor(editor: newEditor(config))
  discard result.editor.addCommandAlias("x", claSaveAndQuit)
  result.editor.setFrontendGitStatusEnabled(true)
  if text.len > 0:
    discard result.editor.handleKeyCombo(moeKeys.toKeyCombo('i'))
    discard result.editor.handleTextInput(text)
    discard result.editor.handleKeyCombo(moeKeys.toSpecialKeyCombo(moeKeys.skEscape))

proc close*(editor: KosmoEditor) =
  ## Release Moe-owned processes and language-server resources.
  if not editor.isNil and not editor.editor.isNil:
    editor.editor.releaseExternalResources()
    editor.editor = nil

proc readEncodingSample(path: string): string =
  let sampleLength = min(getFileSize(path), (EncodingDetectionSampleSize + 4).int64).int
  if sampleLength == 0:
    return
  var file: File
  if not open(file, path, fmRead):
    raise newException(IOError, "Cannot open file: " & path)
  defer:
    file.close()
  result = newString(sampleLength)
  result.setLen(file.readBuffer(addr result[0], sampleLength))

proc isTextEncodingSample(sample: string): bool =
  var
    encoding = detectCharacterEncoding(sample)
    bomLength = 0
  case encoding
  of CharacterEncoding.utf8:
    if sample.startsWith("\xEF\xBB\xBF"):
      bomLength = 3
  of CharacterEncoding.utf16:
    bomLength = 2
    encoding =
      if sample.startsWith("\xFF\xFE"):
        CharacterEncoding.utf16Le
      else:
        CharacterEncoding.utf16Be
  of CharacterEncoding.utf32:
    bomLength = 4
    encoding =
      if sample.startsWith("\xFF\xFE"):
        CharacterEncoding.utf32Le
      else:
        CharacterEncoding.utf32Be
  of CharacterEncoding.unknown:
    return
  else:
    discard
  let
    content =
      if bomLength < sample.len:
        sample[bomLength ..^ 1]
      else:
        ""
    decoded = decodeToUtf8(content, encoding)
  if pkgResults.isErr(decoded):
    return
  result = '\0' notin decoded.get

proc validateFileOpen(editor: KosmoEditor, path: string): FileOpenResult =
  if editor.isNil or editor.editor.isNil:
    return FileOpenResult(message: "The editor is closed.")
  if fileExists(path):
    try:
      if not path.readEncodingSample().isTextEncodingSample():
        return FileOpenResult(
          message: "Kosmo cannot open a binary file or unsupported text encoding."
        )
    except CatchableError as error:
      return FileOpenResult(message: error.msg)
  FileOpenResult(loaded: true)

proc openFileBuffer(editor: KosmoEditor, path: string): FileOpenResult =
  let pathExists = fileExists(path)
  let buffers = editor.editor.activeWindowBuffers()
  let pristineInitialBuffer =
    buffers.len == 1 and buffers[0].title == "No Name" and buffers[0].filePath.isNone and
    not buffers[0].modified
  let outcome =
    if pristineInitialBuffer and pathExists:
      editor.editor.loadFile(path)
    else:
      editor.editor.editFile(path)
  if pkgResults.isErr(outcome):
    return FileOpenResult(message: outcome.error)
  if pristineInitialBuffer and not pathExists:
    discard editor.editor.closeBuffer(buffers[0].id)
  FileOpenResult(loaded: true)

proc normalizedFilePath(path: string): string =
  normalizedPath(absolutePath(path))

proc bufferIdForPath(editor: KosmoEditor, path: string): Option[BufferId] =
  let normalized = path.normalizedFilePath
  for buffer in editor.editor.activeWindowBuffers():
    if buffer.filePath.isSome and buffer.filePath.get.normalizedFilePath == normalized:
      return some(buffer.id)

proc activeBufferId(editor: KosmoEditor): Option[BufferId] =
  for buffer in editor.editor.activeWindowBuffers():
    if buffer.active:
      return some(buffer.id)

proc normalizeTemporaryBuffer(editor: KosmoEditor) =
  if editor.temporaryBufferId.isNone:
    return
  for buffer in editor.editor.activeWindowBuffers():
    if buffer.id == editor.temporaryBufferId.get:
      if buffer.modified:
        editor.temporaryBufferId = none(BufferId)
      return
  editor.temporaryBufferId = none(BufferId)

proc discardTemporaryBuffer(editor: KosmoEditor, exceptId: Option[BufferId]) =
  editor.normalizeTemporaryBuffer()
  if editor.temporaryBufferId.isNone or editor.temporaryBufferId == exceptId:
    return
  discard editor.editor.closeBuffer(editor.temporaryBufferId.get)
  editor.temporaryBufferId = none(BufferId)

proc openFile*(editor: KosmoEditor, path: string): FileOpenResult =
  ## Permanently open `path`, promoting it when it is the temporary buffer.
  result = editor.validateFileOpen(path)
  if not result.loaded:
    return
  editor.normalizeTemporaryBuffer()
  let existing = editor.bufferIdForPath(path)
  if existing.isSome:
    result.loaded = editor.editor.activateBuffer(existing.get)
    if editor.temporaryBufferId == existing:
      editor.temporaryBufferId = none(BufferId)
    return
  result = editor.openFileBuffer(path)
  if not result.loaded:
    return
  let opened = editor.activeBufferId()
  editor.discardTemporaryBuffer(opened)
  editor.temporaryBufferId = none(BufferId)

proc previewFile*(editor: KosmoEditor, path: string): FileOpenResult =
  ## Temporarily open `path`, replacing the previous unmodified preview.
  result = editor.validateFileOpen(path)
  if not result.loaded:
    return
  editor.normalizeTemporaryBuffer()
  let existing = editor.bufferIdForPath(path)
  if existing.isSome:
    result.loaded = editor.editor.activateBuffer(existing.get)
    return
  let previous = editor.temporaryBufferId
  result = editor.openFileBuffer(path)
  if not result.loaded:
    return
  let opened = editor.activeBufferId()
  if opened.isNone:
    return FileOpenResult(message: "Moe opened the file without an active buffer.")
  editor.temporaryBufferId = none(BufferId)
  if previous.isSome and previous != opened:
    discard editor.editor.closeBuffer(previous.get)
  editor.temporaryBufferId = opened

func `$`*(id: KosmoBufferId): string {.inline.} =
  $int(id)

func `==`*(left, right: KosmoBufferId): bool {.borrow.}

func toKosmoBufferId(id: BufferId): KosmoBufferId {.inline.} =
  KosmoBufferId(int(id))

func toMoeBufferId(id: KosmoBufferId): BufferId {.inline.} =
  BufferId(int(id))

func toKosmoBufferCursor(position: moeTypes.BufferPosition): KosmoBufferCursor =
  KosmoBufferCursor(line: position.line, column: position.column)

func toKosmoSelectionKind(kind: EditorSelectionKind): KosmoSelectionKind =
  case kind
  of EditorSelectionKind.Character: KosmoSelectionKind.Character
  of EditorSelectionKind.Block: KosmoSelectionKind.Block
  of EditorSelectionKind.Line: KosmoSelectionKind.Line

proc tabs*(editor: KosmoEditor): seq[KosmoTab] =
  ## Return the ordered tabs belonging to Moe's active window.
  if editor.isNil or editor.editor.isNil:
    return
  editor.normalizeTemporaryBuffer()
  for buffer in editor.editor.activeWindowBuffers():
    result.add KosmoTab(
      id: buffer.id.toKosmoBufferId,
      title: buffer.title,
      filePath: buffer.filePath,
      modified: buffer.modified,
      readOnly: buffer.readOnly,
      active: buffer.active,
      temporary:
        editor.temporaryBufferId.isSome and buffer.id == editor.temporaryBufferId.get,
    )

proc bufferText*(editor: KosmoEditor, id: KosmoBufferId): Option[string] =
  ## Return the current in-memory text for a buffer, including unsaved edits.
  if editor.isNil or editor.editor.isNil:
    return
  let buffer = editor.editor.bufferById(id.toMoeBufferId)
  if buffer.isSome:
    result = some(buffer.get.getTextString())

proc selectTab*(editor: KosmoEditor, id: KosmoBufferId): bool {.discardable.} =
  ## Activate the tab identified by `id`.
  if editor.isNil or editor.editor.isNil:
    return
  editor.editor.activateBuffer(id.toMoeBufferId)

proc closeTab*(editor: KosmoEditor, id: KosmoBufferId): KosmoTabCloseResult =
  ## Close a tab unless Moe rejects the operation, for example when modified.
  if editor.isNil or editor.editor.isNil:
    return KosmoTabCloseResult(message: "The editor is closed.")
  let outcome = editor.editor.closeBuffer(id.toMoeBufferId)
  if pkgResults.isErr(outcome):
    return KosmoTabCloseResult(message: outcome.error)
  if editor.temporaryBufferId.isSome and editor.temporaryBufferId.get == id.toMoeBufferId:
    editor.temporaryBufferId = none(BufferId)
  KosmoTabCloseResult(closed: true)

proc save*(editor: KosmoEditor): KosmoSaveResult =
  ## Save the active buffer to its current path.
  if editor.isNil or editor.editor.isNil:
    return KosmoSaveResult(message: "The editor is closed.")
  let outcome = editor.editor.saveFile()
  if pkgResults.isErr(outcome):
    return KosmoSaveResult(message: outcome.error)
  KosmoSaveResult(saved: true)

proc moveTab*(
    editor: KosmoEditor, id: KosmoBufferId, destination: Natural
): bool {.discardable.} =
  ## Move a tab to a zero-based position in the active window.
  if editor.isNil or editor.editor.isNil:
    return
  result = editor.editor.moveBuffer(id.toMoeBufferId, destination)
  if result and editor.temporaryBufferId.isSome and
      editor.temporaryBufferId.get == id.toMoeBufferId:
    editor.temporaryBufferId = none(BufferId)

proc status*(editor: KosmoEditor): KosmoStatus =
  ## Return the status values maintained by Moe for an embedding frontend.
  if editor.isNil or editor.editor.isNil:
    return
  let snapshot = editor.editor.frontendStatus()
  KosmoStatus(
    modeLabel: snapshot.modeLabel,
    message: snapshot.message,
    gitBranch: snapshot.git.branch,
    gitAdded: snapshot.git.added,
    gitModified: snapshot.git.modified,
    gitDeleted: snapshot.git.deleted,
  )

proc cursor*(editor: KosmoEditor): KosmoCursor =
  ## Return the cursor state computed during Moe's most recent frame.
  if editor.isNil or editor.editor.isNil:
    return
  let position = editor.editor.state.screenCursor
  KosmoCursor(
    row: position.y, column: position.x, visible: editor.editor.state.cursorVisible
  )

proc bufferCursor*(editor: KosmoEditor): KosmoBufferCursor =
  ## Return the logical cursor position in the active text buffer.
  if editor.isNil or editor.editor.isNil:
    return
  let position = editor.editor.activeWindow().cursor
  position.toKosmoBufferCursor

proc currentSelection*(editor: KosmoEditor): Option[KosmoSelection] =
  ## Return a value snapshot of the active selection, or none for a lone caret.
  if editor.isNil or editor.editor.isNil:
    return
  let selection = editor.editor.currentSelection()
  if selection.isSome:
    let value = selection.get
    result = some(
      KosmoSelection(
        bufferId: value.bufferId.toKosmoBufferId,
        kind: value.kind.toKosmoSelectionKind,
        anchor: value.anchor.toKosmoBufferCursor,
        focus: value.focus.toKosmoBufferCursor,
        first: value.first.toKosmoBufferCursor,
        last: value.last.toKosmoBufferCursor,
      )
    )

proc selectedText*(editor: KosmoEditor): string =
  ## Return the text selected by Moe's character, block, or line semantics.
  if not editor.isNil and not editor.editor.isNil:
    result = editor.editor.selectedText()

proc mode*(editor: KosmoEditor): KosmoEditorMode =
  ## Return the active Moe mode reduced to the modes relevant to GUI routing.
  if editor.isNil or editor.editor.isNil:
    return KosmoEditorMode.Other
  case editor.editor.currentMode()
  of moeModes.EditorMode.Normal:
    KosmoEditorMode.Normal
  of moeModes.EditorMode.Insert:
    KosmoEditorMode.Insert
  of moeModes.EditorMode.Replace:
    KosmoEditorMode.Replace
  of moeModes.EditorMode.Visual, moeModes.EditorMode.VisualBlock,
      moeModes.EditorMode.VisualLine:
    KosmoEditorMode.Visual
  of moeModes.EditorMode.Command:
    KosmoEditorMode.Command
  else:
    KosmoEditorMode.Other

proc copySelection*(editor: KosmoEditor): string =
  ## Copy the active selection into Moe's yank and unnamed registers.
  if editor.isNil or editor.editor.isNil or editor.currentSelection().isNone:
    return
  result = editor.selectedText()
  let isLine = editor.currentSelection().get.kind == KosmoSelectionKind.Line
  editor.editor.state.registers.setYankedRegister(result, isLine)

proc cutSelection*(editor: KosmoEditor): string =
  ## Delete the active selection as one Moe undo transaction.
  if editor.isNil or editor.editor.isNil or editor.currentSelection().isNone:
    return
  result = editor.selectedText()
  visualDelete(editor.editor.activeBuffer, editor.editor.state)
  editor.editor.syncActiveWindow()
  editor.editor.setActiveWindowScreenCursor(editor.editor.activeWindow)

proc selectAll*(editor: KosmoEditor): bool {.discardable.} =
  ## Select the entire active buffer using Moe's character selection state.
  if editor.isNil or editor.editor.isNil or editor.editor.activeBuffer.len == 0:
    return
  let
    buffer = editor.editor.activeBuffer
    lastLine = buffer.len - 1
    lastColumn = max(buffer.getLine(lastLine).runeLen - 1, 0)
    currentMode = editor.editor.currentMode()
  if currentMode notin {
    moeModes.EditorMode.Visual, moeModes.EditorMode.VisualBlock,
    moeModes.EditorMode.VisualLine,
  }:
    editor.editor.state.previousMode = currentMode
  editor.editor.state.visualSelection = moeTypes.VisualSelection(
    start: moeTypes.BufferPosition(line: 0, column: 0),
    current: moeTypes.BufferPosition(line: lastLine, column: lastColumn),
    active: true,
    kind: moeTypes.VisualSelectionKind.vskChar,
  )
  editor.editor.setMode(moeModes.EditorMode.Visual)
  editor.editor.activeWindow.cursor = editor.editor.state.visualSelection.current
  editor.editor.syncActiveWindow()
  editor.editor.setActiveWindowScreenCursor(editor.editor.activeWindow)
  true

proc applyUndoPosition(editor: KosmoEditor, position: moeTypes.BufferPosition) =
  editor.editor.activeWindow.cursor = position
  editor.editor.activeWindow.preferredColumn = position.column
  editor.editor.syncActiveWindow()
  editor.editor.setActiveWindowScreenCursor(editor.editor.activeWindow)

proc undo*(editor: KosmoEditor): bool {.discardable.} =
  ## Undo one Moe transaction and synchronize its suggested cursor position.
  if editor.isNil or editor.editor.isNil:
    return
  let outcome = moeUndo.undo(editor.editor.activeBuffer)
  if outcome.isErr:
    editor.editor.state.statusMessage = outcome.error
    return
  editor.applyUndoPosition(outcome.get())
  true

proc redo*(editor: KosmoEditor): bool {.discardable.} =
  ## Redo one Moe transaction and synchronize its suggested cursor position.
  if editor.isNil or editor.editor.isNil:
    return
  let outcome = moeUndo.redo(editor.editor.activeBuffer)
  if outcome.isErr:
    editor.editor.state.statusMessage = outcome.error
    return
  editor.applyUndoPosition(outcome.get())
  true

proc newEmptyBuffer*(editor: KosmoEditor): Option[KosmoBufferId] =
  ## Create and activate an empty Moe buffer without creating a Moe split.
  if editor.isNil or editor.editor.isNil:
    return
  let outcome = editor.editor.enew()
  if outcome.isErr:
    editor.editor.state.statusMessage = outcome.error
    return
  some(editor.editor.activeBuffer.id.toKosmoBufferId)

proc revealLocation*(
    editor: KosmoEditor, line, column: int, centered = false
): bool {.discardable.} =
  ## Move the active buffer cursor to a zero-based location. The next render
  ## follows the cursor if the location lies outside the current viewport, or
  ## places it in the center when `centered` is true.
  if editor.isNil or editor.editor.isNil:
    return
  let
    window = editor.editor.activeWindow()
    cursor = editor.editor.motionController.cursorManager.clampPosition(
      moeTypes.CursorPosition(x: max(column, 0), y: max(line, 0)), window.buffer
    )
  window.cursor.line = cursor.y
  window.cursor.column = cursor.x
  window.preferredColumn = cursor.x
  if centered:
    let visibleHeight = max(window.viewport.height - steadyBottomAreaHeight(), 1)
    window.viewport.resetViewportTop(max(cursor.y - visibleHeight div 2, 0))
  else:
    window.viewport.detachedFromCursor = false
  editor.editor.syncActiveWindow()
  editor.editor.setActiveWindowScreenCursor(window)
  result = true

proc commandLine*(editor: KosmoEditor): KosmoCommandLine =
  ## Return command input for a frontend-owned command bar.
  if editor.isNil or editor.editor.isNil or
      not moeTypes.isCommandOverlay(editor.editor.state):
    return
  KosmoCommandLine(
    visible: true,
    text: editor.editor.state.input.commandText,
    cursor: editor.editor.state.input.commandCursor + 1,
  )

proc completionPopupVisible*(editor: KosmoEditor): bool =
  ## Return whether Moe currently has an active insert-completion popup.
  not editor.isNil and not editor.editor.isNil and
    editor.editor.handlerManager.insertHandler.completionManager.isActive()

proc dismissCompletionPopup*(editor: KosmoEditor) =
  ## Dismiss Moe's active insert-completion popup, if any.
  if not editor.isNil and not editor.editor.isNil:
    editor.editor.handlerManager.insertHandler.completionManager.cancelCompletion()

proc captureViewState*(editor: KosmoEditor): KosmoEditorViewState =
  ## Capture the active buffer's logical cursor and viewport for a frontend pane.
  if editor.isNil or editor.editor.isNil:
    return
  let window = editor.editor.activeWindow()
  result = KosmoEditorViewState(
    bufferId: some(window.buffer.id.toKosmoBufferId),
    cursorLine: window.cursor.line,
    cursorColumn: window.cursor.column,
    preferredColumn: window.preferredColumn,
    viewportTopLine: window.viewport.topLine,
    viewportTopWrapOffset: window.viewport.topWrapOffset,
    viewportLeftColumn: window.viewport.leftColumn,
    viewportDetachedFromCursor: window.viewport.detachedFromCursor,
    scrollAnimation: editor.editor.state.windowDisplay.scrollAnimation,
  )

func bufferId*(state: KosmoEditorViewState): Option[KosmoBufferId] =
  ## Return the buffer projected by a captured frontend view state.
  state.bufferId

proc applyViewState(editor: KosmoEditor, state: KosmoEditorViewState) =
  let window = editor.editor.activeWindow()
  let cursor = editor.editor.motionController.cursorManager.clampPosition(
    moeTypes.CursorPosition(x: state.cursorColumn, y: state.cursorLine), window.buffer
  )
  window.cursor.line = cursor.y
  window.cursor.column = cursor.x
  window.preferredColumn = max(state.preferredColumn, 0)
  window.viewport.topLine =
    state.viewportTopLine.clamp(0, max(window.buffer.len - 1, 0))
  window.viewport.topWrapOffset = max(state.viewportTopWrapOffset, 0)
  window.viewport.leftColumn = max(state.viewportLeftColumn, 0)
  window.viewport.detachedFromCursor = state.viewportDetachedFromCursor
  editor.editor.state.windowDisplay.scrollAnimation = state.scrollAnimation
  editor.editor.syncActiveWindow()
  editor.editor.setActiveWindowScreenCursor(window)

proc restoreViewState*(
    editor: KosmoEditor, state: KosmoEditorViewState
): bool {.discardable.} =
  ## Activate and restore a buffer projection previously captured by a frontend pane.
  if editor.isNil or editor.editor.isNil or state.bufferId.isNone:
    return
  if not editor.selectTab(state.bufferId.get):
    return
  editor.applyViewState(state)
  true

proc newRenderBuffer*(width, height: Natural): RenderBuffer =
  ## Create a cell grid that a Kosmo editor can render into.
  RenderBuffer(buffer: newBuffer(width, height))

func width*(buffer: RenderBuffer): int {.inline.} =
  buffer.buffer.area.width

func height*(buffer: RenderBuffer): int {.inline.} =
  buffer.buffer.area.height

proc resize*(buffer: var RenderBuffer, width, height: Natural) =
  ## Resize the cell grid, preserving cells until the next render.
  buffer.buffer.resize(rect(0, 0, width, height))

func cell*(buffer: RenderBuffer, column, row: int): RenderCell {.inline.} =
  ## Return a rendered Celina cell, including its symbol, style, and hyperlink.
  buffer.buffer.getCell(column, row)

proc render*(editor: KosmoEditor, buffer: var RenderBuffer) =
  ## Advance Moe and draw the editor into `buffer`.
  if editor.isNil or editor.editor.isNil:
    return
  editor.editor.render(buffer.buffer)

proc render*(
    editor: KosmoEditor, buffer: var RenderBuffer, state: KosmoEditorViewState
) =
  ## Draw a pane snapshot without losing detached scroll state when its grid resizes.
  if editor.isNil or editor.editor.isNil or state.bufferId.isNone:
    editor.render(buffer)
    return
  if not editor.restoreViewState(state):
    editor.render(buffer)
    return
  let wasResized = editor.editor.updateViewportSize(buffer.buffer)
  if wasResized:
    editor.editor.advanceLayoutForFrame(buffer.buffer, true)
    editor.applyViewState(state)
  editor.editor.render(buffer.buffer)

func toMoeModifiers(modifiers: set[KeyModifier]): set[frontend_input.KeyModifier] =
  if kmControl in modifiers:
    result.incl(frontend_input.kmCtrl)
  if kmAlt in modifiers:
    result.incl(frontend_input.kmAlt)
  if kmShift in modifiers:
    result.incl(frontend_input.kmShift)
  if kmMeta in modifiers:
    result.incl(frontend_input.kmMeta)

func toMoeButton(button: PointerButton): frontend_input.PointerButton =
  case button
  of pbPrimary: frontend_input.pbPrimary
  of pbMiddle: frontend_input.pbMiddle
  of pbSecondary: frontend_input.pbSecondary
  of pbOther: frontend_input.pbOther

func toMoeAction(action: PointerAction): frontend_input.PointerAction =
  case action
  of paPress: frontend_input.paPress
  of paRelease: frontend_input.paRelease
  of paMove: frontend_input.paMove
  of paDrag: frontend_input.paDrag

func fromMoeRegion(region: frontend_input.GridRegion): GridRegion =
  GridRegion(
    row: region.row, column: region.column, rows: region.rows, columns: region.columns
  )

proc handlePointerInput*(editor: KosmoEditor, input: PointerInput): bool =
  ## Send a frontend-neutral pointer event to Moe.
  if editor.isNil or editor.editor.isNil:
    return false
  editor.editor.handlePointerInput(
    frontend_input.initPointerInput(
      input.row, input.column, input.button.toMoeButton, input.action.toMoeAction,
      input.clickCount, input.modifiers.toMoeModifiers,
    )
  )

proc handleScrollInput*(editor: KosmoEditor, input: ScrollInput): ScrollOutcome =
  ## Send a frontend-neutral physical-line scroll event to Moe.
  if editor.isNil or editor.editor.isNil:
    return
  let outcome = editor.editor.handleScrollInput(
    frontend_input.initScrollInput(
      input.row, input.column, input.deltaPhysicalRows, input.modifiers.toMoeModifiers
    )
  )
  ScrollOutcome(
    handled: outcome.handled,
    region: outcome.region.fromMoeRegion,
    requestedRows: outcome.requestedRows,
    appliedRows: outcome.appliedRows,
    viewportPhysicalRowsMoved: outcome.viewportPhysicalRowsMoved,
  )

func requestsTabClose(commandText: string): bool =
  let parts = strutils.splitWhitespace(commandText.strip().toLowerAscii())
  parts.len > 0 and parts[0] in [":q", ":quit", ":x", ":wq", ":saveandquit"]

proc handleKeyOutcome*(editor: KosmoEditor, key: string): KosmoKeyOutcome =
  ## Send a physical key and retain frontend-relevant exit intent.
  if editor.isNil or editor.editor.isNil:
    return
  let combo = moeKeys.parseKeyCombo(key)
  if combo.isNone:
    return
  let command = editor.commandLine()
  result.valid = true
  result.continueRunning = editor.editor.handleKeyCombo(combo.get)
  result.closeTabRequested =
    not result.continueRunning and command.visible and command.text.requestsTabClose()

proc handleKey*(editor: KosmoEditor, key: string): bool =
  ## Send a physical key in Moe notation, for example `"j"` or `"C-s"`.
  ## Return false for invalid notation or when Moe requests a frontend close.
  let outcome = editor.handleKeyOutcome(key)
  outcome.valid and outcome.continueRunning

proc dismissCommandLine*(editor: KosmoEditor) =
  ## Cancel Moe's command overlay, if one is active.
  if editor.commandLine().visible:
    discard editor.handleKey("Esc")

proc handleTextInput*(editor: KosmoEditor, text: string): bool =
  ## Send committed text, including IME and composed Unicode input.
  if editor.isNil or editor.editor.isNil:
    return false
  editor.editor.handleTextInput(text)

proc handlePaste*(editor: KosmoEditor, text: string): bool =
  ## Insert pasted text without interpreting it as physical key input.
  if editor.isNil or editor.editor.isNil:
    return false
  editor.editor.handlePaste(text)
