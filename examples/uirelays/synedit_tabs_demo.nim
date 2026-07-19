import std/strutils

import merenda/nimkit except
  Rect, Point, Size, color, point, rect, Event, Key, KeyModifier, MouseButton
import merenda/nimkit/foundation/events as nkEvents
import merenda/nimkit/foundation/types as nimkitTypes
import merenda/nimkit/view/uirelaysviews
import uirelays as ui
import widgets/synedit as uiSynEdit

const
  EditorFontSize = 15
  SampleCode = """
import std/[strutils, tables]

type
  TodoPriority = enum
    low, normal, high

  TodoItem = object
    title: string
    done: bool
    priority: TodoPriority

proc describe(item: TodoItem): string =
  let marker = if item.done: "[x]" else: "[ ]"
  marker & " " & item.title & " (" & $item.priority & ")"

proc main() =
  var items = @[
    TodoItem(title: "Port uirelays SynEdit", priority: high),
    TodoItem(title: "Keep Merenda text input", priority: normal),
    TodoItem(title: "Add a demo", done: true, priority: low),
  ]

  for item in items.mitems:
    if "SynEdit" in item.title:
      item.done = true
    echo item.describe()

when isMainModule:
  main()
""".strip()
  MarkdownSample = """
# SynEdit Markdown

This is the same widget with the Markdown token mode enabled.

```nim
echo "fenced Nim text"
```

- line-number gutter
- syntax token spans
- Merenda text editing
""".strip()

type
  EditorBuffer = object
    title: string
    identifier: string
    text: string
    language: uiSynEdit.SourceLanguage
    flags: set[uiSynEdit.RenderFlag]

  SynEditRelaysView = ref object of UIRelaysView
    buffers: seq[EditorBuffer]
    editors: seq[uiSynEdit.SynEdit]
    selectedIndex: int
    hasEditors: bool
    pendingEvents: seq[ui.Event]
    suppressNextTextInput: bool

  SynEditTabsDemo = ref object of Responder
    tabs: DocumentTabs
    editor: SynEditRelaysView

proc sampleBuffers(): seq[EditorBuffer] =
  @[
    EditorBuffer(
      title: "todo.nim",
      identifier: "todo-nim",
      text: SampleCode,
      language: uiSynEdit.langNim,
      flags: {uiSynEdit.rfColorLiterals},
    ),
    EditorBuffer(
      title: "notes.md",
      identifier: "notes-markdown",
      text: MarkdownSample,
      language: uiSynEdit.langMarkdown,
      flags: {uiSynEdit.rfMarkdownImages},
    ),
  ]

proc focused(view: SynEditRelaysView): bool =
  let owner = view.window()
  owner of Window and Window(owner).firstResponder() == view

proc editorArea(view: SynEditRelaysView): ui.Rect =
  let bounds = view.bounds()
  ui.rect(0, 0, max(bounds.size.width.int, 1), max(bounds.size.height.int, 1))

proc ensureEditors(view: SynEditRelaysView): bool =
  if view.hasEditors:
    return true

  var metrics: ui.FontMetrics
  let font = ui.openFont("", EditorFontSize, metrics)
  if font == ui.Font(0):
    return false

  for buffer in view.buffers:
    var editor = uiSynEdit.createSynEdit(font)
    editor.showLineNumbers = true
    editor.lang = buffer.language
    editor.flags = buffer.flags
    editor.setText(buffer.text)
    view.editors.add editor

  view.selectedIndex = clamp(view.selectedIndex, 0, max(view.editors.len - 1, 0))
  view.hasEditors = true
  true

proc selectBuffer(view: SynEditRelaysView, index: int) =
  if view.isNil or index < 0 or index >= view.buffers.len:
    return
  view.selectedIndex = index
  view.needsDisplay = true

proc bufferIndex(view: SynEditRelaysView, identifier: string): int =
  if view.isNil:
    return -1
  for index, buffer in view.buffers:
    if buffer.identifier == identifier:
      return index
  -1

proc enqueue(view: SynEditRelaysView, event: ui.Event) =
  view.pendingEvents.add event
  view.needsDisplay = true

proc enqueueText(view: SynEditRelaysView, text: string) =
  for event in text.toUIRelaysTextInputEvents():
    view.enqueue(event)

proc drawEditorEvent(
    view: SynEditRelaysView, event: ui.Event, area: ui.Rect, focused: bool
) =
  discard view.editors[view.selectedIndex].draw(event, area, focused)

proc drawEditor(view: SynEditRelaysView) =
  if not view.ensureEditors() or view.editors.len == 0:
    return

  let
    area = view.editorArea()
    focused = view.focused()
    events = view.pendingEvents
  view.pendingEvents.setLen(0)

  if events.len == 0:
    view.drawEditorEvent(ui.Event(kind: ui.NoEvent), area, focused)
  else:
    for event in events:
      view.drawEditorEvent(event, area, focused)

  if focused:
    view.needsDisplay = true

protocol SynEditRelaysDrawing of UIRelaysViewHooks:
  method drawUIRelays(view: SynEditRelaysView) =
    view.drawEditor()

protocol SynEditRelaysEvents of ResponderEventProtocol:
  method mouseMoved(view: SynEditRelaysView, event: MouseEvent): bool =
    view.enqueue(event.toUIRelaysEvent(ui.MouseMoveEvent))
    true

  method mouseDown(view: SynEditRelaysView, event: MouseEvent): bool =
    let owner = view.window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(view)
    view.enqueue(event.toUIRelaysEvent(ui.MouseDownEvent))
    true

  method mouseDragged(view: SynEditRelaysView, event: MouseEvent): bool =
    view.enqueue(event.toUIRelaysEvent(ui.MouseMoveEvent))
    true

  method mouseUp(view: SynEditRelaysView, event: MouseEvent): bool =
    view.enqueue(event.toUIRelaysEvent(ui.MouseUpEvent))
    true

  method scrollWheel(view: SynEditRelaysView, event: ScrollEvent): bool =
    let owner = view.window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(view)
    view.enqueue(event.toUIRelaysEvent())
    true

  method keyDown(view: SynEditRelaysView, event: KeyEvent): bool =
    view.suppressNextTextInput = false
    view.enqueue(event.toUIRelaysEvent(ui.KeyDownEvent))
    if event.text.isUIRelaysTextInput() and nkEvents.kmControl notin event.modifiers and
        nkEvents.kmCommand notin event.modifiers:
      view.enqueueText(event.text)
      view.suppressNextTextInput = true
    true

  method keyUp(view: SynEditRelaysView, event: KeyEvent): bool =
    view.enqueue(event.toUIRelaysEvent(ui.KeyUpEvent))
    true

protocol SynEditRelaysTextInput of TextInputProtocol:
  method insertText(view: SynEditRelaysView, text: string) =
    if view.suppressNextTextInput:
      view.suppressNextTextInput = false
      return
    view.enqueueText(text)

protocol SynEditTabsDemoDelegate of DocumentTabsDelegate:
  method didSelectDocumentTab(
      demo: SynEditTabsDemo, tabs: DocumentTabs, item: DocumentTabItem
  ) =
    discard tabs
    demo.editor.selectBuffer(demo.editor.bufferIndex(item.identifier))

proc newSynEditRelaysView(
    buffers: openArray[EditorBuffer], frame: nimkitTypes.Rect = nimkitTypes.AutoRect
): SynEditRelaysView =
  result = SynEditRelaysView()
  result.initUIRelaysViewFields(frame = frame)
  result.buffers = @buffers
  result.acceptsFirstResponder = true
  discard result.withProtocol(SynEditRelaysDrawing)
  discard result.withProtocol(SynEditRelaysEvents)
  discard result.withProtocol(SynEditRelaysTextInput)

proc newTabsDemoController(
    tabs: DocumentTabs, editor: SynEditRelaysView
): SynEditTabsDemo =
  result = SynEditTabsDemo(tabs: tabs, editor: editor)
  initResponder(result)
  discard result.withProtocol(SynEditTabsDemoDelegate)

proc newDemoTab(buffer: EditorBuffer): DocumentTabItem =
  result = newDocumentTabItem(buffer.title, buffer.identifier, closeable = false)
  result.style = dtsRounded

proc newSynEditTabsDemoView(): tuple[root: View, editor: SynEditRelaysView] =
  let
    buffers = sampleBuffers()
    tabs = newDocumentTabs()
    editor = newSynEditRelaysView(buffers)
    demo = newTabsDemoController(tabs, editor)
    root = newView()
    layout = newStackView(laVertical)

  tabs.delegate = demo
  tabs.defaultTabStyle = dtsRounded
  tabs.allowsClosing = false
  tabs.allowsTabReordering = false
  tabs.setHuggingPriority(LayoutPriorityRequired, laVertical)
  tabs.setCompressionPriority(LayoutPriorityRequired, laVertical)

  for buffer in buffers:
    discard tabs.addDocumentTabItem(buffer.newDemoTab())
  discard tabs.selectDocumentTabAtIndex(0)

  editor.setHuggingPriority(LayoutPriorityLow, laVertical)
  editor.setCompressionPriority(LayoutPriorityLow, laVertical)

  layout.spacing = 8.0
  layout.alignment = svaFill
  layout.edgeInsets = insets(18.0, 20.0)
  layout.addArrangedSubview(tabs, editor)

  root.addSubview(layout)
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(), edges = {leLeft, leTop, leRight, leBottom}
  )

  result = (root: View(root), editor: editor)

let
  app = sharedApplication()
  window =
    newWindow("UIRelays SynEdit Tabs", frame = nimkitTypes.rect(160, 120, 920, 640))
  demo = newSynEditTabsDemoView()

app.runWindow(window, demo.root, demo.editor)
