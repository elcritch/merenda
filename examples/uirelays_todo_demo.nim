import std/[strutils, tables, unicode]

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes
import merenda/nimkit/view/uirelaysviews
import uirelays as ui
import uirelays/layout as uiLayout

const
  BaseFontSize = 15
  LayoutSpec =
    """
  | header, 2 lines |
  | composer, 2 lines |
  | list, * |
  | status, 1 line |
"""

type
  TodoItem = object
    text: string
    done: bool

  TodoFocus = enum
    tfComposer
    tfList

  HoverKind = enum
    hkNone
    hkComposer
    hkRow
    hkCheckbox
    hkDelete

  HoverTarget = object
    kind: HoverKind
    index: int

  TodoRelaysView = ref object of UIRelaysView
    items: seq[TodoItem]
    inputText: string
    focus: TodoFocus
    selectedIndex: int
    scrollIndex: int
    mousePoint: ui.Point
    suppressNextTextInput: bool

let
  TodoLayout = uiLayout.parseLayout(LayoutSpec)
  BgColor = ui.color(244'u8, 243'u8, 241'u8)
  PanelColor = ui.color(255'u8, 255'u8, 255'u8)
  PanelAltColor = ui.color(247'u8, 248'u8, 249'u8)
  BorderColor = ui.color(216'u8, 219'u8, 223'u8)
  TextColor = ui.color(29'u8, 31'u8, 34'u8)
  MutedTextColor = ui.color(103'u8, 107'u8, 112'u8)
  AccentColor = ui.color(44'u8, 120'u8, 220'u8)
  SelectedRowColor = ui.color(233'u8, 240'u8, 250'u8)
  SuccessColor = ui.color(46'u8, 160'u8, 67'u8)
  DangerColor = ui.color(208'u8, 56'u8, 76'u8)
  PlaceholderColor = ui.color(126'u8, 130'u8, 135'u8)
  DividerColor = ui.color(229'u8, 232'u8, 235'u8)

proc clampInt(value, minValue, maxValue: int): int =
  min(max(value, minValue), maxValue)

proc toUiPoint(point: nimkitTypes.Point): ui.Point =
  ui.point(point.x.int, point.y.int)

proc todoFontMetrics(): ui.FontMetrics =
  let lineHeight = max((BaseFontSize * 5 + 3) div 4, BaseFontSize)
  ui.FontMetrics(
    ascent: BaseFontSize,
    descent: max(lineHeight - BaseFontSize, 0),
    lineHeight: lineHeight,
  )

proc insetRect(rect: ui.Rect, pad: int): ui.Rect =
  ui.rect(
    rect.x + pad, rect.y + pad, max(0, rect.w - pad * 2), max(0, rect.h - pad * 2)
  )

proc drawBorder(rect: ui.Rect, color: ui.Color) =
  if rect.w <= 0 or rect.h <= 0:
    return
  ui.drawLine(rect.x, rect.y, rect.x + rect.w - 1, rect.y, color)
  ui.drawLine(rect.x, rect.y, rect.x, rect.y + rect.h - 1, color)
  ui.drawLine(
    rect.x + rect.w - 1, rect.y, rect.x + rect.w - 1, rect.y + rect.h - 1, color
  )
  ui.drawLine(
    rect.x, rect.y + rect.h - 1, rect.x + rect.w - 1, rect.y + rect.h - 1, color
  )

proc countDone(items: openArray[TodoItem]): int =
  for item in items:
    if item.done:
      inc result

proc summaryText(total, done: int): string =
  let remaining = total - done
  if total == 0:
    return "No tasks"
  if done == 0:
    return $remaining & " remaining"
  if remaining == 0:
    return "All completed"
  $remaining & " remaining, " & $done & " completed"

proc removeLastRune(text: var string) =
  if text.len == 0:
    return
  let (_, runeBytes) = lastRune(text, text.high)
  text.setLen(text.len - runeBytes)

proc insertableText(text: string): bool =
  if text.len == 0:
    return false
  for ch in text:
    if ch < ' ':
      return false
  true

proc truncateText(font: ui.Font, text: string, maxWidth: int): string =
  if maxWidth <= 0:
    return ""
  if ui.measureText(font, text).w <= maxWidth:
    return text

  let
    ellipsis = "..."
    ellipsisWidth = ui.measureText(font, ellipsis).w
  if ellipsisWidth > maxWidth:
    return ""

  var runeEnds: seq[int]
  var index = 0
  while index < text.len:
    index += runeLenAt(text, index)
    runeEnds.add index

  var
    low = 0
    high = runeEnds.len
  while low < high:
    let
      mid = (low + high + 1) shr 1
      candidate =
        if mid == 0:
          ellipsis
        else:
          text[0 ..< runeEnds[mid - 1]] & ellipsis
    if ui.measureText(font, candidate).w <= maxWidth:
      low = mid
    else:
      high = mid - 1

  if low == 0:
    return ellipsis
  result = text[0 ..< runeEnds[low - 1]]
  result.add ellipsis

proc rowHeightFor(metrics: ui.FontMetrics): int =
  metrics.lineHeight + 8

proc visibleRowsFor(listInner: ui.Rect, rowHeight: int): int =
  max(1, listInner.h div rowHeight)

proc checkboxRect(rowRect: ui.Rect): ui.Rect =
  let size = min(16, max(10, rowRect.h - 8))
  ui.rect(rowRect.x + 8, rowRect.y + (rowRect.h - size) div 2, size, size)

proc deleteRect(rowRect: ui.Rect): ui.Rect =
  let size = min(18, max(12, rowRect.h - 8))
  ui.rect(
    rowRect.x + rowRect.w - 8 - size, rowRect.y + (rowRect.h - size) div 2, size, size
  )

proc rowRectFor(listInner: ui.Rect, rowHeight, visibleIndex: int): ui.Rect =
  ui.rect(listInner.x, listInner.y + visibleIndex * rowHeight, listInner.w, rowHeight)

proc listInnerRect(listRect: ui.Rect): ui.Rect =
  listRect.insetRect(6)

proc composerInnerRect(composerRect: ui.Rect): ui.Rect =
  composerRect.insetRect(8)

proc cellsFor(
    view: TodoRelaysView, metrics = todoFontMetrics()
): Table[string, ui.Rect] =
  let bounds = view.bounds()
  TodoLayout.resolve(
    max(0, bounds.size.width.int), max(0, bounds.size.height.int), metrics.lineHeight
  )

proc clampSelection(view: TodoRelaysView, visibleRows: int) =
  if view.items.len == 0:
    view.selectedIndex = -1
    view.scrollIndex = 0
    return

  view.selectedIndex = clampInt(view.selectedIndex, 0, view.items.len - 1)
  let maxScroll = max(0, view.items.len - visibleRows)
  view.scrollIndex = clampInt(view.scrollIndex, 0, maxScroll)

  if view.selectedIndex < view.scrollIndex:
    view.scrollIndex = view.selectedIndex
  elif view.selectedIndex >= view.scrollIndex + visibleRows:
    view.scrollIndex = view.selectedIndex - visibleRows + 1

  view.scrollIndex = clampInt(view.scrollIndex, 0, maxScroll)

proc hitList(
    listInner: ui.Rect,
    rowHeight, scrollIndex: int,
    items: openArray[TodoItem],
    point: ui.Point,
): HoverTarget =
  if not listInner.contains(point):
    return HoverTarget(kind: hkNone, index: -1)

  let
    visibleIndex = (point.y - listInner.y) div rowHeight
    itemIndex = scrollIndex + visibleIndex
  if itemIndex < 0 or itemIndex >= items.len:
    return HoverTarget(kind: hkNone, index: -1)

  let rowRect = rowRectFor(listInner, rowHeight, visibleIndex)
  if rowRect.deleteRect().contains(point):
    return HoverTarget(kind: hkDelete, index: itemIndex)
  if rowRect.checkboxRect().contains(point):
    return HoverTarget(kind: hkCheckbox, index: itemIndex)
  HoverTarget(kind: hkRow, index: itemIndex)

proc hoverTarget(view: TodoRelaysView, metrics = todoFontMetrics()): HoverTarget =
  let cells = view.cellsFor(metrics)
  let
    composerRect = cells["composer"].composerInnerRect()
    listInner = cells["list"].listInnerRect()
    rowHeight = metrics.rowHeightFor()
  if composerRect.contains(view.mousePoint):
    return HoverTarget(kind: hkComposer, index: -1)
  hitList(listInner, rowHeight, view.scrollIndex, view.items, view.mousePoint)

proc drawCheckbox(rect: ui.Rect, checked: bool) =
  ui.fillRect(rect, if checked: SuccessColor else: PanelColor)
  drawBorder(rect, if checked: SuccessColor else: BorderColor)
  if checked:
    ui.drawLine(
      rect.x + 4,
      rect.y + rect.h div 2,
      rect.x + rect.w div 2 - 1,
      rect.y + rect.h - 5,
      PanelColor,
    )
    ui.drawLine(
      rect.x + rect.w div 2 - 1,
      rect.y + rect.h - 5,
      rect.x + rect.w - 4,
      rect.y + 4,
      PanelColor,
    )

proc drawDeleteButton(rect: ui.Rect, hovered: bool) =
  let
    foreground = if hovered: PanelColor else: DangerColor
    background = if hovered: DangerColor else: PanelColor
    pad = 4
  ui.fillRect(rect, background)
  drawBorder(rect, DangerColor)
  ui.drawLine(
    rect.x + pad,
    rect.y + pad,
    rect.x + rect.w - pad - 1,
    rect.y + rect.h - pad - 1,
    foreground,
  )
  ui.drawLine(
    rect.x + rect.w - pad - 1,
    rect.y + pad,
    rect.x + pad,
    rect.y + rect.h - pad - 1,
    foreground,
  )

proc addTask(view: TodoRelaysView) =
  let trimmed = view.inputText.strip()
  if trimmed.len == 0:
    return
  view.items.add TodoItem(text: trimmed)
  view.inputText.setLen(0)
  view.selectedIndex = view.items.high
  view.focus = tfList
  view.setNeedsDisplay(true)

proc deleteSelected(view: TodoRelaysView) =
  if view.selectedIndex >= 0 and view.selectedIndex < view.items.len:
    view.items.delete(view.selectedIndex)
    view.setNeedsDisplay(true)

proc toggleSelected(view: TodoRelaysView) =
  if view.selectedIndex >= 0 and view.selectedIndex < view.items.len:
    view.items[view.selectedIndex].done = not view.items[view.selectedIndex].done
    view.setNeedsDisplay(true)

proc drawTodo(view: TodoRelaysView) =
  var metrics: ui.FontMetrics
  let font = ui.openFont("", BaseFontSize, metrics)
  if font == ui.Font(0):
    metrics = todoFontMetrics()

  let
    bounds = view.bounds()
    width = max(0, bounds.size.width.int)
    height = max(0, bounds.size.height.int)
    cells = TodoLayout.resolve(width, height, metrics.lineHeight)
    headerRect = cells["header"]
    composerCell = cells["composer"]
    listRect = cells["list"]
    statusRect = cells["status"]
    composerBox = composerCell.composerInnerRect()
    listInner = listRect.listInnerRect()
    rowHeight = metrics.rowHeightFor()
    listVisibleRows = visibleRowsFor(listInner, rowHeight)

  view.clampSelection(listVisibleRows)
  let
    hover = view.hoverTarget(metrics)
    doneCount = view.items.countDone()
    openCount = view.items.len - doneCount

  ui.fillRect(ui.rect(0, 0, width, height), BgColor)

  ui.fillRect(headerRect, PanelColor)
  discard ui.drawText(
    font, headerRect.x + 14, headerRect.y + 10, "Tasks", TextColor, PanelColor
  )
  discard ui.drawText(
    font,
    headerRect.x + 14,
    headerRect.y + 28,
    summaryText(view.items.len, doneCount),
    MutedTextColor,
    PanelColor,
  )
  ui.drawLine(
    headerRect.x + 14,
    headerRect.y + headerRect.h - 1,
    headerRect.x + headerRect.w - 14,
    headerRect.y + headerRect.h - 1,
    DividerColor,
  )

  ui.fillRect(composerCell, PanelColor)
  let composerBg = if view.focus == tfComposer: PanelColor else: PanelAltColor
  ui.fillRect(composerBox, composerBg)
  drawBorder(composerBox, if view.focus == tfComposer: AccentColor else: BorderColor)

  let
    composerTextX = composerBox.x + 10
    composerTextY = composerBox.y + (composerBox.h - metrics.lineHeight) div 2
  if view.inputText.len == 0:
    discard ui.drawText(
      font, composerTextX, composerTextY, "Add a task", PlaceholderColor, composerBg
    )
  else:
    let shown = truncateText(font, view.inputText, composerBox.w - 20)
    discard
      ui.drawText(font, composerTextX, composerTextY, shown, TextColor, composerBg)

  if view.focus == tfComposer:
    let
      caretText = truncateText(font, view.inputText, composerBox.w - 20)
      caretX = composerTextX + ui.measureText(font, caretText).w + 1
    ui.drawLine(
      caretX, composerBox.y + 7, caretX, composerBox.y + composerBox.h - 8, AccentColor
    )

  ui.fillRect(listRect, PanelColor)
  ui.drawLine(
    listRect.x + 14, listRect.y, listRect.x + listRect.w - 14, listRect.y, DividerColor
  )

  if view.items.len == 0:
    discard ui.drawText(
      font,
      listInner.x + 10,
      listInner.y + 10,
      "Nothing to do.",
      PlaceholderColor,
      PanelColor,
    )
  else:
    for visibleIndex in 0 ..< listVisibleRows:
      let itemIndex = view.scrollIndex + visibleIndex
      if itemIndex >= view.items.len:
        break

      let
        rowRect = rowRectFor(listInner, rowHeight, visibleIndex)
        rowBg =
          if itemIndex == view.selectedIndex:
            SelectedRowColor
          elif hover.index == itemIndex:
            PanelAltColor
          else:
            PanelColor
      ui.fillRect(rowRect, rowBg)
      if itemIndex == view.selectedIndex:
        ui.fillRect(ui.rect(rowRect.x, rowRect.y, 3, rowRect.h), AccentColor)
      ui.drawLine(
        rowRect.x,
        rowRect.y + rowRect.h - 1,
        rowRect.x + rowRect.w,
        rowRect.y + rowRect.h - 1,
        DividerColor,
      )

      let
        boxRect = rowRect.checkboxRect()
        delRect = rowRect.deleteRect()
      drawCheckbox(boxRect, view.items[itemIndex].done)
      drawDeleteButton(delRect, hover.kind == hkDelete and hover.index == itemIndex)

      let
        textX = boxRect.x + boxRect.w + 10
        maxTextWidth = delRect.x - textX - 10
        shown = truncateText(font, view.items[itemIndex].text, maxTextWidth)
        textY = rowRect.y + (rowRect.h - metrics.lineHeight) div 2
        foreground = if view.items[itemIndex].done: MutedTextColor else: TextColor
      discard ui.drawText(font, textX, textY, shown, foreground, rowBg)

      if view.items[itemIndex].done:
        let
          extent = ui.measureText(font, shown)
          strikeY = textY + metrics.lineHeight div 2
        ui.drawLine(textX, strikeY, textX + extent.w, strikeY, MutedTextColor)

  ui.fillRect(statusRect, PanelColor)
  let statusText =
    if openCount == 0 and view.items.len > 0:
      "All tasks completed"
    elif view.items.len == 0:
      "Ready"
    else:
      $openCount & " remaining"
  discard ui.drawText(
    font, statusRect.x + 14, statusRect.y + 6, statusText, MutedTextColor, PanelColor
  )

  ui.closeFont(font)

proc handleMouseClick(view: TodoRelaysView, point: ui.Point) =
  let
    metrics = todoFontMetrics()
    cells = view.cellsFor(metrics)
    composerRect = cells["composer"].composerInnerRect()
    listInner = cells["list"].listInnerRect()
    rowHeight = metrics.rowHeightFor()
    visibleRows = visibleRowsFor(listInner, rowHeight)

  if composerRect.contains(point):
    view.focus = tfComposer
    view.setNeedsDisplay(true)
    return

  let hover = hitList(listInner, rowHeight, view.scrollIndex, view.items, point)
  case hover.kind
  of hkDelete:
    view.focus = tfList
    if hover.index >= 0 and hover.index < view.items.len:
      view.items.delete(hover.index)
      view.clampSelection(visibleRows)
      view.setNeedsDisplay(true)
  of hkCheckbox:
    view.focus = tfList
    if hover.index >= 0 and hover.index < view.items.len:
      view.selectedIndex = hover.index
      view.items[hover.index].done = not view.items[hover.index].done
      view.clampSelection(visibleRows)
      view.setNeedsDisplay(true)
  of hkRow:
    view.focus = tfList
    view.selectedIndex = hover.index
    view.clampSelection(visibleRows)
    view.setNeedsDisplay(true)
  else:
    discard

protocol TodoRelaysDrawing of UIRelaysViewHooks:
  method drawUIRelays(view: TodoRelaysView) =
    view.drawTodo()

protocol TodoRelaysEvents of ResponderEventProtocol:
  method mouseMoved(view: TodoRelaysView, event: MouseEvent): bool =
    view.mousePoint = event.location.toUiPoint()
    view.setNeedsDisplay(true)
    true

  method mouseDown(view: TodoRelaysView, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    let owner = view.window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(view)
    view.mousePoint = event.location.toUiPoint()
    view.handleMouseClick(view.mousePoint)
    true

  method scrollWheel(view: TodoRelaysView, event: ScrollEvent): bool =
    let
      metrics = todoFontMetrics()
      cells = view.cellsFor(metrics)
      listInner = cells["list"].listInnerRect()
      rowHeight = metrics.rowHeightFor()
      visibleRows = visibleRowsFor(listInner, rowHeight)
    if not listInner.contains(event.location.toUiPoint()):
      return false
    let maxScroll = max(0, view.items.len - visibleRows)
    if event.deltaY < 0.0'f32:
      view.scrollIndex = clampInt(view.scrollIndex + 1, 0, maxScroll)
    elif event.deltaY > 0.0'f32:
      view.scrollIndex = clampInt(view.scrollIndex - 1, 0, maxScroll)
    view.clampSelection(visibleRows)
    view.setNeedsDisplay(true)
    true

  method keyDown(view: TodoRelaysView, event: KeyEvent): bool =
    view.suppressNextTextInput = false
    case event.key
    of keyTab:
      if view.focus == tfComposer:
        view.focus = tfList
        if view.selectedIndex < 0 and view.items.len > 0:
          view.selectedIndex = 0
      else:
        view.focus = tfComposer
      view.setNeedsDisplay(true)
      true
    of keyEnter:
      if view.focus == tfComposer:
        view.addTask()
      else:
        view.toggleSelected()
      true
    of keySpace:
      if view.focus == tfList:
        view.toggleSelected()
        return true
      false
    of keyBackspace:
      if view.focus == tfComposer:
        view.inputText.removeLastRune()
        view.setNeedsDisplay(true)
      else:
        view.deleteSelected()
      true
    of keyDelete:
      if view.focus == tfList:
        view.deleteSelected()
        return true
      false
    of keyArrowUp:
      if view.focus == tfList and view.items.len > 0:
        if view.selectedIndex < 0:
          view.selectedIndex = 0
        else:
          dec view.selectedIndex
        view.clampSelection(
          visibleRowsFor(
            view.cellsFor()["list"].listInnerRect(), rowHeightFor(todoFontMetrics())
          )
        )
        view.setNeedsDisplay(true)
        return true
      false
    of keyArrowDown:
      if view.focus == tfList and view.items.len > 0:
        if view.selectedIndex < 0:
          view.selectedIndex = 0
        else:
          inc view.selectedIndex
        view.clampSelection(
          visibleRowsFor(
            view.cellsFor()["list"].listInnerRect(), rowHeightFor(todoFontMetrics())
          )
        )
        view.setNeedsDisplay(true)
        return true
      false
    else:
      if view.focus == tfComposer and event.text.insertableText():
        view.inputText.add event.text
        view.suppressNextTextInput = true
        view.setNeedsDisplay(true)
        return true
      false

protocol TodoRelaysTextInput of TextInputProtocol:
  method insertText(view: TodoRelaysView, text: string) =
    if view.suppressNextTextInput:
      view.suppressNextTextInput = false
      return
    if view.focus == tfComposer and text.insertableText():
      view.inputText.add text
      view.setNeedsDisplay(true)

proc newTodoRelaysView(frame: nimkitTypes.Rect = nimkitTypes.AutoRect): TodoRelaysView =
  result = TodoRelaysView(
    items:
      @[
        TodoItem(text: "Review this week's priorities", done: true),
        TodoItem(text: "Reply to client email"),
        TodoItem(text: "Prepare tomorrow's notes"),
      ],
    focus: tfComposer,
    selectedIndex: 0,
    scrollIndex: 0,
    mousePoint: ui.point(-1, -1),
  )
  initUIRelaysViewFields(result, frame = frame)
  result.setAcceptsFirstResponder(true)
  discard result.withProtocol(TodoRelaysDrawing)
  discard result.withProtocol(TodoRelaysEvents)
  discard result.withProtocol(TodoRelaysTextInput)

let
  app = sharedApplication()
  window = newWindow("UIRelays Todo", frame = nimkitTypes.rect(160, 120, 760, 560))
  todo = newTodoRelaysView()

window.setContentView(todo)
discard window.makeFirstResponder(todo)
app.addWindow(window)
window.makeKeyAndOrderFront()
app.run()
