import std/strutils

import merenda/nimkit except
  Rect, Point, Size, color, point, rect, Event, Key, KeyModifier, MouseButton
import merenda/nimkit/foundation/events as nkEvents
import merenda/nimkit/foundation/types as nimkitTypes
import merenda/nimkit/view/uirelaysviews
import uirelays as ui
import widgets/terminal as uiTerminal

const TerminalFontSize = 16

type
  CommandLogController = ref object of Responder
    commands: seq[string]
    table: TableView

  TerminalRelaysView = ref object of UIRelaysView
    terminal: uiTerminal.Terminal
    commandLog: CommandLogController
    hasTerminal: bool
    pendingEvents: seq[ui.Event]
    suppressNextTextInput: bool

protocol CommandLogDataSource of TableViewDataSource:
  method numberOfRows(source: CommandLogController, tableView: TableView): int =
    source.commands.len

  method textForCell(
      source: CommandLogController, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard tableView
    discard column
    if row in 0 ..< source.commands.len:
      source.commands[row]
    else:
      ""

proc recordCommand(source: CommandLogController, command: string) =
  if source.isNil:
    return
  let normalized = command.strip()
  if normalized.len == 0:
    return

  source.commands.add normalized
  if not source.table.isNil:
    source.table.reloadData()
    source.table.selectedIndex = source.commands.high

proc newCommandLogController(): CommandLogController =
  CommandLogController()

proc newCommandLogTable(source: CommandLogController): TableView =
  result = newTableView()
  result.addColumn(
    newTableColumn("command", "Commands Run", width = 260.0, minWidth = 180.0)
  )
  result.showsHeader = true
  result.tableHeaderHeight = 26.0
  result.rowHeight = 28.0
  result.selectionMode = tsmSingle
  result.usesAlternatingRowBackgrounds = true
  result.showsRowSeparators = true
  result.dataSource = source
  result.accessibilityLabel = "Commands run"
  source.table = result

proc focused(view: TerminalRelaysView): bool =
  let owner = view.window()
  owner of Window and Window(owner).firstResponder() == view

proc terminalArea(view: TerminalRelaysView): ui.Rect =
  let bounds = view.bounds()
  ui.rect(0, 0, max(bounds.size.width.int, 1), max(bounds.size.height.int, 1))

proc ensureTerminal(view: TerminalRelaysView): bool =
  if view.hasTerminal:
    return true

  var metrics: ui.FontMetrics
  let font = ui.openFont("", TerminalFontSize, metrics)
  if font == ui.Font(0):
    return false

  view.terminal = uiTerminal.createTerminal(font)
  view.hasTerminal = true
  true

proc enqueue(view: TerminalRelaysView, event: ui.Event) =
  view.pendingEvents.add event
  view.setNeedsDisplay(true)

proc enqueueText(view: TerminalRelaysView, text: string) =
  for event in text.toUIRelaysTextInputEvents():
    view.enqueue(event)

proc currentCommand(view: TerminalRelaysView): string =
  if not view.hasTerminal:
    return ""
  let editor = view.terminal.ed
  for index in editor.readOnly + 1 ..< editor.len:
    result.add editor[index]

proc handleTerminalAction(view: TerminalRelaysView, action: uiTerminal.TermAction) =
  discard view
  case action.kind
  of uiTerminal.noAction, uiTerminal.ctrlHover, uiTerminal.ctrlClick,
      uiTerminal.openFile, uiTerminal.saveFile:
    discard

proc isCommandSubmit(event: ui.Event): bool =
  event.kind == ui.KeyDownEvent and event.key == ui.KeyEnter

proc drawTerminalEvent(
    view: TerminalRelaysView, event: ui.Event, area: ui.Rect, focused: bool
) =
  if focused and event.isCommandSubmit():
    view.commandLog.recordCommand(view.currentCommand())
  view.handleTerminalAction(view.terminal.draw(event, area, focused))

proc drawTerminal(view: TerminalRelaysView) =
  if not view.ensureTerminal():
    return

  let
    area = view.terminalArea()
    focused = view.focused()
    events = view.pendingEvents
  view.pendingEvents.setLen(0)

  if events.len == 0:
    view.handleTerminalAction(
      view.terminal.draw(ui.Event(kind: ui.NoEvent), area, focused)
    )
  else:
    for event in events:
      view.drawTerminalEvent(event, area, focused)

  if focused or view.terminal.processRunning:
    view.setNeedsDisplay(true)

protocol TerminalRelaysDrawing of UIRelaysViewHooks:
  method drawUIRelays(view: TerminalRelaysView) =
    view.drawTerminal()

protocol TerminalRelaysEvents of ResponderEventProtocol:
  method mouseMoved(view: TerminalRelaysView, event: MouseEvent): bool =
    view.enqueue(event.toUIRelaysEvent(ui.MouseMoveEvent))
    true

  method mouseDown(view: TerminalRelaysView, event: MouseEvent): bool =
    let owner = view.window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(view)
    view.enqueue(event.toUIRelaysEvent(ui.MouseDownEvent))
    true

  method mouseDragged(view: TerminalRelaysView, event: MouseEvent): bool =
    view.enqueue(event.toUIRelaysEvent(ui.MouseMoveEvent))
    true

  method mouseUp(view: TerminalRelaysView, event: MouseEvent): bool =
    view.enqueue(event.toUIRelaysEvent(ui.MouseUpEvent))
    true

  method scrollWheel(view: TerminalRelaysView, event: ScrollEvent): bool =
    let uiEvent = event.toUIRelaysEvent()
    if uiEvent.y == 0:
      return false
    view.enqueue(uiEvent)
    true

  method keyDown(view: TerminalRelaysView, event: KeyEvent): bool =
    view.suppressNextTextInput = false
    view.enqueue(event.toUIRelaysEvent(ui.KeyDownEvent))
    if event.text.isUIRelaysTextInput() and nkEvents.kmControl notin event.modifiers and
        nkEvents.kmCommand notin event.modifiers:
      view.enqueueText(event.text)
      view.suppressNextTextInput = true
    true

  method keyUp(view: TerminalRelaysView, event: KeyEvent): bool =
    view.enqueue(event.toUIRelaysEvent(ui.KeyUpEvent))
    true

protocol TerminalRelaysTextInput of TextInputProtocol:
  method insertText(view: TerminalRelaysView, text: string) =
    if view.suppressNextTextInput:
      view.suppressNextTextInput = false
      return
    view.enqueueText(text)

proc newTerminalRelaysView(
    commandLog: CommandLogController = nil,
    frame: nimkitTypes.Rect = nimkitTypes.AutoRect,
): TerminalRelaysView =
  result = TerminalRelaysView()
  result.initUIRelaysViewFields(frame = frame)
  result.commandLog = commandLog
  result.setAcceptsFirstResponder(true)
  discard result.withProtocol(TerminalRelaysDrawing)
  discard result.withProtocol(TerminalRelaysEvents)
  discard result.withProtocol(TerminalRelaysTextInput)

proc newTerminalDemoView(): tuple[root: SplitView, terminal: TerminalRelaysView] =
  let
    commandLog = newCommandLogController()
    commandTable = newCommandLogTable(commandLog)
  result.root = newHorizontalSplitView()
  result.terminal = newTerminalRelaysView(commandLog)
  result.root.addPane(result.terminal, minSize = 360.0)
  result.root.addPane(commandTable, minSize = 220.0)
  result.root.restoreState(
    SplitViewState(fractions: @[0.72'f32, 0.28'f32], collapsed: @[false, false])
  )

let
  app = sharedApplication()
  window = newWindow("UIRelays Terminal", frame = nimkitTypes.rect(160, 120, 1040, 560))
  demo = newTerminalDemoView()

app.runWindow(window, demo.root, demo.terminal)
