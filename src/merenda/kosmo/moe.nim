## A frontend-oriented facade for the Moe editor engine.
##
## Kosmo owns a Moe editor and projects it into a cell grid. GUI frontends
## translate their input and paint the returned cells; Moe implementation types
## remain private to this module.

import std/[options, os]

import pkg/celina
import pkg/results as pkgResults

import
  moepkg/[
    editor, editor_buffers, editor_display, editor_frame, editor_render_views,
    frontend_input, handler, completion, config, editor_window, encoding, motion,
  ]
from moepkg/buffer/core import BufferId
import moepkg/key_bindings/registry as moeKeys
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

proc newKosmoEditor*(text = ""): KosmoEditor =
  ## Create an editor with Moe's default configuration and optional initial text.
  var config = newEditorConfig()
  config.standard.mouse = true
  config.standard.statusLine = false
  config.tabLine.enable = false
  result = KosmoEditor(editor: newEditor(config))
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

proc validateFileOpen(editor: KosmoEditor, path: string): FileOpenResult =
  if editor.isNil or editor.editor.isNil:
    return FileOpenResult(message: "The editor is closed.")
  if fileExists(path):
    try:
      if detectCharacterEncoding(readFile(path)) == CharacterEncoding.unknown:
        return FileOpenResult(
          message: "Kosmo cannot open a binary file or unsupported text encoding."
        )
    except IOError as error:
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

proc handleKey*(editor: KosmoEditor, key: string): bool =
  ## Send a physical key in Moe notation, for example `"j"` or `"C-s"`.
  ## Return false when `key` is not valid Moe notation.
  if editor.isNil or editor.editor.isNil:
    return false
  let combo = moeKeys.parseKeyCombo(key)
  if combo.isNone:
    return false
  editor.editor.handleKeyCombo(combo.get)

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
