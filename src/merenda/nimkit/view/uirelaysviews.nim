import std/[math, os, times, unicode]

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw
import sigils/core
import uirelays as ui

import ../app/pasteboards
import ../drawing
import ../foundation/events as nkEvents
import ../foundation/selectors
import ../foundation/types as nimkitTypes
import ../themes
import ./views

export views

type
  UIRelaysDrawProc* = proc(view: UIRelaysView) {.closure.}

  UIRelaysView* = ref object of View
    xDrawProc: UIRelaysDrawProc
    xRelayFrame: UIRelaysRelayFrame

  UIRelaysRelayState = object
    drawRelays: ui.DrawRelays
    fontRelays: ui.FontRelays
    windowRelays: ui.WindowRelays
    inputRelays: ui.InputRelays
    clipboardRelays: ui.ClipboardRelays
    context: DrawContext
    frame: UIRelaysRelayFrame

  UIRelaysFontInfo = object
    fontName: string
    size: int
    metrics: ui.FontMetrics
    open: bool

  UIRelaysRelayFrame = ref object
    fonts: seq[UIRelaysFontInfo]
    images: seq[ImageResource]
    parent: FigIdx
    parentStack: seq[FigIdx]

var
  activeDrawContext {.threadvar.}: DrawContext
  activeRelayFrame {.threadvar.}: UIRelaysRelayFrame

func toNimKitColor(color: ui.Color): nimkitTypes.Color =
  nimkitTypes.color(
    color.r.float32 / 255.0'f32,
    color.g.float32 / 255.0'f32,
    color.b.float32 / 255.0'f32,
    color.a.float32 / 255.0'f32,
  )

func toNimKitRect(rect: ui.Rect): nimkitTypes.Rect =
  nimkitTypes.rect(rect.x.float32, rect.y.float32, rect.w.float32, rect.h.float32)

proc toUIRelaysPoint*(point: nimkitTypes.Point): ui.Point =
  ui.point(point.x.int, point.y.int)

proc toUIRelaysMouseButton*(button: nkEvents.MouseButton): ui.MouseButton =
  case button
  of nkEvents.mbPrimary: ui.LeftButton
  of nkEvents.mbSecondary: ui.RightButton
  of nkEvents.mbOther: ui.MiddleButton

proc toUIRelaysModifiers*(modifiers: set[nkEvents.KeyModifier]): set[ui.Modifier] =
  if nkEvents.kmShift in modifiers:
    result.incl ui.ShiftPressed
  if nkEvents.kmControl in modifiers:
    result.incl ui.CtrlPressed
  if nkEvents.kmOption in modifiers:
    result.incl ui.AltPressed
  if nkEvents.kmCommand in modifiers:
    result.incl ui.GuiPressed

proc toUIRelaysKey*(key: nkEvents.Key): ui.KeyCode =
  if key >= nkEvents.keyA and key <= nkEvents.keyZ:
    return ui.KeyCode(ui.KeyA.ord + key.ord - nkEvents.keyA.ord)
  if key >= nkEvents.keyF1 and key <= nkEvents.keyF12:
    return ui.KeyCode(ui.KeyF1.ord + key.ord - nkEvents.keyF1.ord)

  case key
  of nkEvents.key0: ui.Key0
  of nkEvents.key1: ui.Key1
  of nkEvents.key2: ui.Key2
  of nkEvents.key3: ui.Key3
  of nkEvents.key4: ui.Key4
  of nkEvents.key5: ui.Key5
  of nkEvents.key6: ui.Key6
  of nkEvents.key7: ui.Key7
  of nkEvents.key8: ui.Key8
  of nkEvents.key9: ui.Key9
  of nkEvents.keyEnter: ui.KeyEnter
  of nkEvents.keySpace: ui.KeySpace
  of nkEvents.keyEscape: ui.KeyEsc
  of nkEvents.keyTab: ui.KeyTab
  of nkEvents.keyBackspace: ui.KeyBackspace
  of nkEvents.keyDelete: ui.KeyDelete
  of nkEvents.keyInsert: ui.KeyInsert
  of nkEvents.keyArrowLeft: ui.KeyLeft
  of nkEvents.keyArrowRight: ui.KeyRight
  of nkEvents.keyArrowUp: ui.KeyUp
  of nkEvents.keyArrowDown: ui.KeyDown
  of nkEvents.keyPageUp: ui.KeyPageUp
  of nkEvents.keyPageDown: ui.KeyPageDown
  of nkEvents.keyHome: ui.KeyHome
  of nkEvents.keyEnd: ui.KeyEnd
  of nkEvents.keyCapsLock: ui.KeyCapslock
  of nkEvents.keyComma: ui.KeyComma
  of nkEvents.keyDot: ui.KeyPeriod
  of nkEvents.keySlash: ui.KeySlash
  of nkEvents.keyMinus: ui.KeyMinus
  of nkEvents.keyEqual: ui.KeyEqual
  of nkEvents.keyAdd: ui.KeyPlus
  else: ui.KeyNone

proc toUIRelaysEvent*(event: nkEvents.MouseEvent, kind: ui.EventKind): ui.Event =
  ui.Event(
    kind: kind,
    x: event.location.x.int,
    y: event.location.y.int,
    button: event.button.toUIRelaysMouseButton(),
    mods: event.modifiers.toUIRelaysModifiers(),
    clicks: max(event.clickCount, 1),
  )

proc toUIRelaysEvent*(event: nkEvents.KeyEvent, kind: ui.EventKind): ui.Event =
  ui.Event(
    kind: kind,
    key: event.key.toUIRelaysKey(),
    mods: event.modifiers.toUIRelaysModifiers(),
  )

proc toUIRelaysEvent*(event: nkEvents.ScrollEvent): ui.Event =
  let scrollY =
    if event.deltaY < 0.0'f32:
      -1
    elif event.deltaY > 0.0'f32:
      1
    else:
      0
  ui.Event(
    kind: ui.MouseWheelEvent,
    x: event.location.x.int,
    y: scrollY,
    mods: event.modifiers.toUIRelaysModifiers(),
  )

proc isUIRelaysTextInput*(text: string): bool =
  if text.len == 0:
    return false
  for ch in text:
    if ch < ' ':
      return false
  true

proc toUIRelaysTextInputEvents*(text: string): seq[ui.Event] =
  if not text.isUIRelaysTextInput():
    return

  var index = 0
  while index < text.len:
    let next = index + runeLenAt(text, index)
    var eventText: array[4, char]
    for offset, ch in text[index ..< next]:
      if offset < eventText.len:
        eventText[offset] = ch
    result.add ui.Event(kind: ui.TextInputEvent, text: eventText)
    index = next

proc fontIndex(font: ui.Font): int =
  result = font.int - 1
  if activeRelayFrame.isNil or result < 0 or result >= activeRelayFrame.fonts.len or
      not activeRelayFrame.fonts[result].open:
    result = -1

proc fontMetricsFor(fontName: string, size: int): ui.FontMetrics =
  let
    normalizedSize = max(size, 1)
    style = TextStyle(
      color: nimkitTypes.color(0.0, 0.0, 0.0, 1.0),
      insets: insets(0.0'f32),
      fontName: fontName,
      fontSize: normalizedSize.float32,
    )
    lineHeight = max(ceil("Mg".textNaturalSize(style).height).int, normalizedSize)
  ui.FontMetrics(
    ascent: normalizedSize,
    descent: max(lineHeight - normalizedSize, 0),
    lineHeight: lineHeight,
  )

proc textStyleFor(fontInfo: UIRelaysFontInfo, color: ui.Color): TextStyle =
  result = TextStyle(
    color: color.toNimKitColor(),
    insets: insets(0.0'f32),
    fontName: fontInfo.fontName,
    fontSize: max(fontInfo.size.float32, 1.0'f32),
  )

proc textWidthFor(style: TextStyle, text: string): int =
  if text.len == 0:
    return 0
  let
    lineHeight = max(ceil("Mg".textNaturalSize(style).height), style.fontSize)
    layout = textLayout(nimkitTypes.rect(0.0, 0.0, 10000.0, lineHeight), text, style)
    carets = layout.caretPositionsFor(text.runeLen())
  if carets.len > 0:
    var width = 0.0'f32
    for caret in carets:
      width = max(width, caret.pos.x)
    return max(ceil(width).int, 0)

  max(ceil(layout.bounding.w).int, 0)

proc textExtentFor(font: ui.Font, text: string): ui.TextExtent =
  let index = font.fontIndex()
  if index < 0:
    return ui.TextExtent()
  let fontInfo = activeRelayFrame.fonts[index]
  ui.TextExtent(
    w: fontInfo.textStyleFor(ui.color(0'u8, 0'u8, 0'u8)).textWidthFor(text),
    h: fontInfo.metrics.lineHeight,
  )

proc imageFor(handle: ui.Image): ImageResource =
  let index = handle.int - 1
  if not activeRelayFrame.isNil and index >= 0 and index < activeRelayFrame.images.len:
    activeRelayFrame.images[index]
  else:
    nil

proc relayParent(): FigIdx =
  if not activeRelayFrame.isNil:
    activeRelayFrame.parent
  elif not activeDrawContext.isNil:
    activeDrawContext.renderParent()
  else:
    (-1).FigIdx

proc uiFillRect(rect: ui.Rect, color: ui.Color) {.nimcall.} =
  if activeDrawContext.isNil:
    return
  discard activeDrawContext.addRenderRectangle(
    relayParent(),
    activeDrawContext.renderRectFor(rect.toNimKitRect()),
    fill(color.toNimKitColor().rgba),
  )

proc uiDrawLine(x1, y1, x2, y2: int, color: ui.Color) {.nimcall.} =
  if activeDrawContext.isNil:
    return
  discard activeDrawContext.addRenderLine(
    relayParent(),
    nimkitTypes.initPoint(x1.float32, y1.float32),
    nimkitTypes.initPoint(x2.float32, y2.float32),
    fill(color.toNimKitColor().rgba),
    1.0'f32,
  )

proc uiDrawPoint(x, y: int, color: ui.Color) {.nimcall.} =
  if activeDrawContext.isNil:
    return
  discard activeDrawContext.addRenderRectangle(
    relayParent(),
    activeDrawContext.renderRectFor(
      nimkitTypes.rect(x.float32, y.float32, 1.0'f32, 1.0'f32)
    ),
    fill(color.toNimKitColor().rgba),
  )

proc uiOpenFont(
    path: string, size: int, metrics: var ui.FontMetrics
): ui.Font {.nimcall.} =
  if activeRelayFrame.isNil:
    return ui.Font(0)
  let
    normalizedSize =
      if size > 0:
        size
      else:
        max(defaultFontSize().round().int, 1)
    fontName =
      if path.len > 0:
        path
      else:
        defaultFontName()
  metrics = fontMetricsFor(fontName, normalizedSize)
  activeRelayFrame.fonts.add UIRelaysFontInfo(
    fontName: fontName, size: normalizedSize, metrics: metrics, open: true
  )
  result = ui.Font(activeRelayFrame.fonts.len)

proc uiCloseFont(font: ui.Font) {.nimcall.} =
  let index = font.fontIndex()
  if index >= 0:
    activeRelayFrame.fonts[index] = UIRelaysFontInfo()

proc uiGetFontMetrics(font: ui.Font): ui.FontMetrics {.nimcall.} =
  let index = font.fontIndex()
  if index >= 0:
    result = activeRelayFrame.fonts[index].metrics

proc uiMeasureText(font: ui.Font, text: string): ui.TextExtent {.nimcall.} =
  font.textExtentFor(text)

proc uiDrawText(
    font: ui.Font, x, y: int, text: string, fg, bg: ui.Color
): ui.TextExtent {.nimcall.} =
  let index = font.fontIndex()
  if index < 0:
    return ui.TextExtent()
  result = font.textExtentFor(text)
  if activeDrawContext.isNil or text.len == 0:
    return
  let textRect =
    nimkitTypes.rect(x.float32, y.float32, result.w.float32, result.h.float32)
  if bg.a > 0'u8 and result.w > 0 and result.h > 0:
    discard activeDrawContext.addRenderRectangle(
      relayParent(),
      activeDrawContext.renderRectFor(textRect),
      fill(bg.toNimKitColor().rgba),
    )
  discard activeDrawContext.addText(
    DefaultDrawLevel,
    relayParent(),
    textRect,
    text,
    activeRelayFrame.fonts[index].textStyleFor(fg),
  )

proc uiLoadImage(path: string): ui.Image {.nimcall.} =
  if activeRelayFrame.isNil:
    return ui.Image(0)
  try:
    let image = newImageResourceFromFile(path)
    activeRelayFrame.images.add image
    result = ui.Image(activeRelayFrame.images.len)
  except CatchableError:
    result = ui.Image(0)

proc uiFreeImage(image: ui.Image) {.nimcall.} =
  let index = image.int - 1
  if not activeRelayFrame.isNil and index >= 0 and index < activeRelayFrame.images.len:
    activeRelayFrame.images[index] = nil

proc uiDrawImage(image: ui.Image, src, dst: ui.Rect) {.nimcall.} =
  discard src
  if activeDrawContext.isNil:
    return
  let resource = image.imageFor()
  if not resource.isNil:
    discard activeDrawContext.addImage(
      DefaultDrawLevel, relayParent(), dst.toNimKitRect(), resource
    )

proc uiCreateWindow(layout: var ui.ScreenLayout) {.nimcall.} =
  if activeDrawContext.isNil:
    return
  let bounds = activeDrawContext.bounds()
  layout.width = max(bounds.size.width.round().int, 1)
  layout.height = max(bounds.size.height.round().int, 1)
  layout.scaleX = 1
  layout.scaleY = 1

proc uiSaveState() {.nimcall.} =
  if activeRelayFrame.isNil:
    return
  activeRelayFrame.parentStack.add activeRelayFrame.parent

proc uiRestoreState() {.nimcall.} =
  if activeRelayFrame.isNil or activeRelayFrame.parentStack.len == 0:
    return
  activeRelayFrame.parent = activeRelayFrame.parentStack.pop()

proc uiSetClipRect(rect: ui.Rect) {.nimcall.} =
  if activeDrawContext.isNil or activeRelayFrame.isNil:
    return
  let clip = activeDrawContext.addRenderRectangle(
    activeRelayFrame.parent,
    activeDrawContext.renderRectFor(rect.toNimKitRect()),
    fill(nimkitTypes.color(0.0, 0.0, 0.0, 0.0).rgba),
    clips = true,
  )
  activeRelayFrame.parent = clip

proc uiPollEvent(e: var ui.Event, flags: set[ui.InputFlag]): bool {.nimcall.} =
  discard e
  discard flags
  false

proc uiWaitEvent(
    e: var ui.Event, timeoutMs: int, flags: set[ui.InputFlag]
): bool {.nimcall.} =
  discard e
  discard timeoutMs
  discard flags
  false

proc uiGetTicks(): int {.nimcall.} =
  int(epochTime() * 1000.0)

proc uiSleep(ms: int) {.nimcall.} =
  os.sleep(ms)

proc uiShutdown() {.nimcall.} =
  discard

proc uiGetClipboardText(): string {.nimcall.} =
  generalPasteboard().plainText()

proc uiPutClipboardText(text: string) {.nimcall.} =
  discard generalPasteboard().setPlainText(text)

proc relayFrameFor(
    context: DrawContext, frame: UIRelaysRelayFrame
): UIRelaysRelayFrame =
  result =
    if frame.isNil:
      UIRelaysRelayFrame()
    else:
      frame
  result.parent = context.renderParent()
  result.parentStack.setLen(0)

proc installUIRelays(
    context: DrawContext, frame: UIRelaysRelayFrame = nil
): UIRelaysRelayState =
  result = UIRelaysRelayState(
    drawRelays: ui.drawRelays,
    fontRelays: ui.fontRelays,
    windowRelays: ui.windowRelays,
    inputRelays: ui.inputRelays,
    clipboardRelays: ui.clipboardRelays,
    context: activeDrawContext,
    frame: activeRelayFrame,
  )
  activeDrawContext = context
  activeRelayFrame = context.relayFrameFor(frame)
  ui.drawRelays = ui.DrawRelays(
    fillRect: uiFillRect,
    drawLine: uiDrawLine,
    drawPoint: uiDrawPoint,
    loadImage: uiLoadImage,
    freeImage: uiFreeImage,
    drawImage: uiDrawImage,
  )
  ui.fontRelays = ui.FontRelays(
    openFont: uiOpenFont,
    closeFont: uiCloseFont,
    getFontMetrics: uiGetFontMetrics,
    measureText: uiMeasureText,
    drawText: uiDrawText,
  )
  ui.windowRelays = ui.WindowRelays(
    createWindow: uiCreateWindow,
    refresh: proc() {.nimcall.} =
      discard,
    saveState: uiSaveState,
    restoreState: uiRestoreState,
    setClipRect: uiSetClipRect,
    setCursor: proc(cursor: ui.CursorKind) {.nimcall.} =
      discard,
    setWindowTitle: proc(title: string) {.nimcall.} =
      discard,
  )
  ui.inputRelays = ui.InputRelays(
    pollEvent: uiPollEvent,
    waitEvent: uiWaitEvent,
    getTicks: uiGetTicks,
    sleep: uiSleep,
    shutdown: uiShutdown,
  )
  ui.clipboardRelays =
    ui.ClipboardRelays(getText: uiGetClipboardText, putText: uiPutClipboardText)

proc restoreUIRelays(state: UIRelaysRelayState) =
  ui.drawRelays = state.drawRelays
  ui.fontRelays = state.fontRelays
  ui.windowRelays = state.windowRelays
  ui.inputRelays = state.inputRelays
  ui.clipboardRelays = state.clipboardRelays
  activeDrawContext = state.context
  activeRelayFrame = state.frame

proc withUIRelaysDrawContext*(context: DrawContext, body: proc() {.closure.}) =
  let state = installUIRelays(context)
  try:
    body()
  finally:
    restoreUIRelays(state)

proc withUIRelaysDrawContext*(
    view: UIRelaysView, context: DrawContext, body: proc() {.closure.}
) =
  if view.isNil:
    context.withUIRelaysDrawContext(body)
    return
  if view.xRelayFrame.isNil:
    view.xRelayFrame = UIRelaysRelayFrame()
  let state = installUIRelays(context, view.xRelayFrame)
  try:
    body()
  finally:
    restoreUIRelays(state)

protocol UIRelaysViewHooks:
  method drawUIRelays*() {.optional.}

proc drawProc*(view: UIRelaysView): UIRelaysDrawProc =
  if view.isNil: nil else: view.xDrawProc

proc `drawProc=`*(view: UIRelaysView, drawProc: UIRelaysDrawProc) =
  if view.xDrawProc == drawProc:
    return
  view.xDrawProc = drawProc
  view.needsDisplay = true

protocol DefaultUIRelaysViewDrawing of ViewDrawingProtocol:
  method draw(view: UIRelaysView, context: DrawContext) =
    view.withUIRelaysDrawContext(context) do():
      if not view.xDrawProc.isNil:
        view.xDrawProc(view)
      discard DynamicAgent(view).sendLocalIfHandled(drawUIRelays(), ())

proc initUIRelaysViewFields*(
    view: UIRelaysView,
    drawProc: UIRelaysDrawProc = nil,
    frame: nimkitTypes.Rect = AutoRect,
) =
  initViewFields(view, frame)
  view.background = nimkitTypes.color(0.0, 0.0, 0.0, 0.0)
  view.xDrawProc = drawProc
  view.xRelayFrame = UIRelaysRelayFrame()
  discard view.withProtocol(DefaultUIRelaysViewDrawing)
  view.applyInitialFrame(frame)

proc newUIRelaysView*(
    drawProc: UIRelaysDrawProc = nil, frame: nimkitTypes.Rect = AutoRect
): UIRelaysView =
  result = UIRelaysView()
  result.initUIRelaysViewFields(drawProc, frame)
