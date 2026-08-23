## A frontend-oriented facade for the Moe editor engine.
##
## Kosmo owns a Moe editor and projects it into a cell grid. GUI frontends
## translate their input and paint the returned cells; Moe implementation types
## remain private to this module.

import std/options

import pkg/celina
import pkg/results as pkgResults

import moepkg/[editor, editor_frame, frontend_input, handler, config]
import moepkg/key_bindings/registry as moeKeys

when hasAsyncSupport:
  {.error: "Merenda's Moe facade requires Celina's synchronous backend".}

type
  KosmoEditor* = ref object
    editor: Editor

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
  result = KosmoEditor(editor: newEditor(config))
  if text.len > 0:
    discard result.editor.handleKeyCombo(moeKeys.toKeyCombo('i'))
    discard result.editor.handleTextInput(text)
    discard result.editor.handleKeyCombo(moeKeys.toSpecialKeyCombo(moeKeys.skEscape))

proc close*(editor: KosmoEditor) =
  ## Release Moe-owned processes and language-server resources.
  if not editor.isNil and not editor.editor.isNil:
    editor.editor.releaseExternalResources()
    editor.editor = nil

proc openFile*(editor: KosmoEditor, path: string): FileOpenResult =
  ## Load `path` into the active Moe buffer.
  if editor.isNil or editor.editor.isNil:
    return FileOpenResult(message: "The editor is closed.")
  let outcome = editor.editor.loadFile(path)
  if pkgResults.isErr(outcome):
    return FileOpenResult(message: outcome.error)
  FileOpenResult(loaded: true)

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
  ## Invalid key notation raises `ValueError`.
  if editor.isNil or editor.editor.isNil:
    return false
  let combo = moeKeys.parseKeyCombo(key)
  if combo.isNone:
    raise newException(ValueError, "Invalid Moe key: " & key)
  editor.editor.handleKeyCombo(combo.get)

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
