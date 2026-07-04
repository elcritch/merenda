import std/math

import sigils/core
import uirelays as ui

import ../drawing
import ../foundation/selectors
import ../foundation/types as nimkitTypes
import ../themes
import ./views

export views

type
  UIRelaysDrawProc* = proc(view: UIRelaysView) {.closure.}

  UIRelaysView* = ref object of View
    xDrawProc: UIRelaysDrawProc

  UIRelaysRelayState = object
    drawRelays: ui.DrawRelays
    fontRelays: ui.FontRelays
    windowRelays: ui.WindowRelays
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

proc fontIndex(font: ui.Font): int =
  result = font.int - 1
  if activeRelayFrame.isNil or result < 0 or result >= activeRelayFrame.fonts.len or
      not activeRelayFrame.fonts[result].open:
    result = -1

proc fontMetricsFor(size: int): ui.FontMetrics =
  let
    normalizedSize = max(size, 1)
    lineHeight = max(ceil(normalizedSize.float32 * 1.25'f32).int, normalizedSize)
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

proc textExtentFor(style: TextStyle, text: string): ui.TextExtent =
  if text.len == 0:
    return ui.TextExtent()
  let size = text.textNaturalSize(style)
  ui.TextExtent(w: max(ceil(size.width).int, 0), h: max(ceil(size.height).int, 0))

proc textExtentFor(font: ui.Font, text: string): ui.TextExtent =
  let index = font.fontIndex()
  if index < 0:
    return ui.TextExtent()
  activeRelayFrame.fonts[index].textStyleFor(ui.color(0'u8, 0'u8, 0'u8)).textExtentFor(
    text
  )

proc imageFor(handle: ui.Image): ImageResource =
  let index = handle.int - 1
  if not activeRelayFrame.isNil and index >= 0 and index < activeRelayFrame.images.len:
    activeRelayFrame.images[index]
  else:
    nil

proc uiFillRect(rect: ui.Rect, color: ui.Color) {.nimcall.} =
  if activeDrawContext.isNil:
    return
  discard activeDrawContext.addRectangle(
    rect.toNimKitRect(), fill(color.toNimKitColor().rgba)
  )

proc uiDrawLine(x1, y1, x2, y2: int, color: ui.Color) {.nimcall.} =
  if activeDrawContext.isNil:
    return
  discard activeDrawContext.addRenderLine(
    nimkitTypes.initPoint(x1.float32, y1.float32),
    nimkitTypes.initPoint(x2.float32, y2.float32),
    fill(color.toNimKitColor().rgba),
    1.0'f32,
  )

proc uiDrawPoint(x, y: int, color: ui.Color) {.nimcall.} =
  if activeDrawContext.isNil:
    return
  discard activeDrawContext.addRectangle(
    nimkitTypes.rect(x.float32, y.float32, 1.0'f32, 1.0'f32),
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
  metrics = normalizedSize.fontMetricsFor()
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
    discard activeDrawContext.addRectangle(textRect, fill(bg.toNimKitColor().rgba))
  discard activeDrawContext.addText(
    textRect, text, activeRelayFrame.fonts[index].textStyleFor(fg)
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
    discard activeDrawContext.addImage(dst.toNimKitRect(), resource)

proc installUIRelays(context: DrawContext): UIRelaysRelayState =
  result = UIRelaysRelayState(
    drawRelays: ui.drawRelays,
    fontRelays: ui.fontRelays,
    windowRelays: ui.windowRelays,
    context: activeDrawContext,
    frame: activeRelayFrame,
  )
  activeDrawContext = context
  activeRelayFrame = UIRelaysRelayFrame()
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
    createWindow: proc(layout: var ui.ScreenLayout) {.nimcall.} =
      discard,
    refresh: proc() {.nimcall.} =
      discard,
    saveState: proc() {.nimcall.} =
      discard,
    restoreState: proc() {.nimcall.} =
      discard,
    setClipRect: proc(rect: ui.Rect) {.nimcall.} =
      discard,
    setCursor: proc(cursor: ui.CursorKind) {.nimcall.} =
      discard,
    setWindowTitle: proc(title: string) {.nimcall.} =
      discard,
  )

proc restoreUIRelays(state: UIRelaysRelayState) =
  ui.drawRelays = state.drawRelays
  ui.fontRelays = state.fontRelays
  ui.windowRelays = state.windowRelays
  activeDrawContext = state.context
  activeRelayFrame = state.frame

proc withUIRelaysDrawContext*(context: DrawContext, body: proc() {.closure.}) =
  let state = installUIRelays(context)
  try:
    body()
  finally:
    restoreUIRelays(state)

protocol UIRelaysViewHooks:
  method drawUIRelays*() {.optional.}

proc drawProc*(view: UIRelaysView): UIRelaysDrawProc =
  if view.isNil: nil else: view.xDrawProc

proc `drawProc=`*(view: UIRelaysView, drawProc: UIRelaysDrawProc) =
  if view.isNil or view.xDrawProc == drawProc:
    return
  view.xDrawProc = drawProc
  view.setNeedsDisplay(true)

protocol DefaultUIRelaysViewDrawing of ViewDrawingProtocol:
  method draw(view: UIRelaysView, context: DrawContext) =
    context.withUIRelaysDrawContext do():
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
  discard view.withProtocol(DefaultUIRelaysViewDrawing)
  view.applyInitialFrame(frame)

proc newUIRelaysView*(
    drawProc: UIRelaysDrawProc = nil, frame: nimkitTypes.Rect = AutoRect
): UIRelaysView =
  result = UIRelaysView()
  result.initUIRelaysViewFields(drawProc, frame)
