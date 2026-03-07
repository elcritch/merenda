import ./runtime
import figdraw/commons
import figdraw/fignodes

const
  NSDeviceIsScreenName* = "NSDeviceIsScreen"
  NSDeviceIsPrinterName* = "NSDeviceIsPrinter"
  NSDeviceSizeName* = "NSDeviceSize"
  NSDeviceResolutionName* = "NSDeviceResolution"
  NSDeviceColorSpaceNameName* = "NSDeviceColorSpaceName"
  NSDeviceBitsPerSampleName* = "NSDeviceBitsPerSample"

var NSDeviceIsScreen* {.threadvar.}: NSString
var NSDeviceIsPrinter* {.threadvar.}: NSString
var NSDeviceSize* {.threadvar.}: NSString
var NSDeviceResolution* {.threadvar.}: NSString
var NSDeviceColorSpaceName* {.threadvar.}: NSString
var NSDeviceBitsPerSample* {.threadvar.}: NSString

var currentGraphicsContextId {.threadvar.}: IDPtr
var graphicsContextStack {.threadvar.}: seq[IDPtr]

var quartzDebuggingEnabled = false
var quartzDebugModeEnabled = false

proc currentGraphicsContext(): NSGraphicsContext
proc sendPtr(obj: IDPtr, op: SEL): pointer {.inline.}

type RenderGraphicsPort* = object
  renders*: ptr Renders
  parentIdx*: FigIdx
  drawBox*: NSRect

type NSGraphicsStateSnapshot = object
  shouldAntialias: bool
  imageInterpolation: NSImageInterpolation
  renderingIntent: NSColorRenderingIntent
  patternPhase: NSPoint
  compositingOperation: NSCompositingOperation
  fillColor: NSColor
  strokeColor: NSColor

proc noRenderShadows(): array[ShadowCount, RenderShadow] =
  for i in result.low .. result.high:
    result[i] = RenderShadow(
      style: NoShadow,
      blur: 0.0,
      spread: 0.0,
      x: 0.0,
      y: 0.0,
      fill: nsColor(0.0, 0.0, 0.0, 0.0).toFigColor(),
    )

proc renderGraphicsPortForContext(context: NSGraphicsContext): ptr RenderGraphicsPort =
  if context.isNil:
    return nil
  let port = sendPtr(context.value, getSelector("graphicsPort"))
  if port.isNil:
    return nil
  cast[ptr RenderGraphicsPort](port)

proc currentRenderGraphicsPort(): ptr RenderGraphicsPort =
  renderGraphicsPortForContext(currentGraphicsContext())

proc normalizeLocalDrawRect(localRect: NSRect): NSRect =
  let width = max(localRect.size.width, 0.0)
  let height = max(localRect.size.height, 0.0)
  nsRect(localRect.origin.x, localRect.origin.y, width, height)

proc clampedCornerRadius(rect: NSRect, radius: float32): float32 {.inline.} =
  max(0.0'f32, min(radius, min(rect.size.width, rect.size.height) * 0.5'f32))

proc sendId(obj: IDPtr, op: SEL): IDPtr {.inline.} =
  if obj.isNil or cast[pointer](op).isNil:
    return nil
  cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(obj, op)

proc sendBool(obj: IDPtr, op: SEL): bool {.inline.} =
  if obj.isNil or cast[pointer](op).isNil:
    return false
  cast[proc(self: IDPtr, op: SEL): bool {.cdecl, varargs.}](objc_msgSend)(obj, op)

proc sendPtr(obj: IDPtr, op: SEL): pointer {.inline.} =
  if obj.isNil or cast[pointer](op).isNil:
    return nil
  cast[proc(self: IDPtr, op: SEL): pointer {.cdecl, varargs.}](objc_msgSend)(obj, op)

proc replaceOwned(slot: var ID, next: NSObject) {.inline.} =
  slot.value = replacedOwnedId(slot.value, next.value)

proc clearOwned(slot: var ID) {.inline.} =
  slot.value = replacedOwnedId(slot.value, nil)

proc ensureGraphicsContextConstants() =
  if NSDeviceIsScreen.isNil:
    NSDeviceIsScreen = ns(NSDeviceIsScreenName)
    NSDeviceIsPrinter = ns(NSDeviceIsPrinterName)
    NSDeviceSize = ns(NSDeviceSizeName)
    NSDeviceResolution = ns(NSDeviceResolutionName)
    NSDeviceColorSpaceName = ns(NSDeviceColorSpaceNameName)
    NSDeviceBitsPerSample = ns(NSDeviceBitsPerSampleName)

proc defaultDeviceDescription(isScreen: bool): NSDictionary[NSString, NSObject] =
  ensureGraphicsContextConstants()
  result = nsDictionary[NSString, NSObject]()
  result[NSDeviceIsScreen] = ns(isScreen).NSObject

proc currentGraphicsContext(): NSGraphicsContext =
  ownFromId[NSGraphicsContext](currentGraphicsContextId)

objcImpl:
  type NSGraphicsContext* = object of NSObject
    xGraphicsPort {.get: graphicsPort.}: pointer
    xFocusStack {.get: focusStack.}: NSArray[NSObject]
    xIsDrawingToScreen {.get: isDrawingToScreen.}: bool
    xIsFlipped: bool
    xDeviceDescriptionId: ID

    xShouldAntialias {.set: setShouldAntialias, get: shouldAntialias.}: bool
    xImageInterpolation {.set: setImageInterpolation, get: imageInterpolation.}:
      NSImageInterpolation
    xRenderingIntent {.set: setColorRenderingIntent, get: colorRenderingIntent.}:
      NSColorRenderingIntent
    xPatternPhase {.set: setPatternPhase, get: patternPhase.}: NSPoint
    xCompositingOperation: NSCompositingOperation
    xFillColor: NSColor
    xStrokeColor: NSColor
    xSavedGraphicsStates: seq[NSGraphicsStateSnapshot]

  method init*(self: var NSGraphicsContext): NSGraphicsContext =
    result = asTypeRaw[NSGraphicsContext](
      callSuperIdFrom(NSGraphicsContext, self, getSelector("init"))
    )
    if result.isNil:
      return
    initIvarFields(result)
    result.xFocusStack = nsArray[NSObject]()
    result.xDeviceDescriptionId.value = nil
    replaceOwned(result.xDeviceDescriptionId, defaultDeviceDescription(false))
    result.xShouldAntialias = true
    result.xImageInterpolation = NSImageInterpolationDefault
    result.xRenderingIntent = NSColorRenderingIntentDefault
    result.xCompositingOperation = NSCompositeSourceOver
    result.xPatternPhase = nsPoint(0.0, 0.0)
    result.xFillColor = nsColor(0.0, 0.0, 0.0, 1.0)
    result.xStrokeColor = nsColor(0.0, 0.0, 0.0, 1.0)
    result.xSavedGraphicsStates = @[]

  method initWithWindow*(
      self: var NSGraphicsContext, window: NSWindow
  ): NSGraphicsContext =
    result = self.init()
    if result.isNil:
      return
    result.xIsDrawingToScreen = true
    result.xIsFlipped = false
    if window.isNil:
      replaceOwned(result.xDeviceDescriptionId, defaultDeviceDescription(true))
      return
    #let windowObj = window.NSObject
    let windowObj = window.NSObject
    if windowObj.respondsToSelector("cgContext"):
      result.xGraphicsPort = sendPtr(window.value, getSelector("cgContext"))
    if windowObj.respondsToSelector("deviceDescription"):
      let descriptionId = sendId(window.value, getSelector("deviceDescription"))
      if not descriptionId.isNil:
        replaceOwned(
          result.xDeviceDescriptionId,
          ownFromId[NSDictionary[NSString, NSObject]](descriptionId),
        )
      else:
        replaceOwned(result.xDeviceDescriptionId, defaultDeviceDescription(true))
    else:
      replaceOwned(result.xDeviceDescriptionId, defaultDeviceDescription(true))

  method initWithGraphicsPort*(
      self: var NSGraphicsContext, context: pointer, flipped {.kw("flipped").}: bool
  ): NSGraphicsContext =
    result = self.init()
    if result.isNil:
      return
    result.xGraphicsPort = context
    result.xIsFlipped = flipped
    result.xIsDrawingToScreen = false
    replaceOwned(result.xDeviceDescriptionId, defaultDeviceDescription(false))

  method initWithBitmapImageRep*(
      self: var NSGraphicsContext, imageRep: NSBitmapImageRep
  ): NSGraphicsContext =
    discard imageRep
    result = self.initWithGraphicsPort(nil, false)
    if result.isNil:
      return
    result.xIsDrawingToScreen = true
    replaceOwned(result.xDeviceDescriptionId, defaultDeviceDescription(true))

  method deviceDescription*(self: NSGraphicsContext): NSDictionary[NSString, NSObject] =
    if self.isNil or self.xDeviceDescriptionId.isNil:
      return NSDictionary[NSString, NSObject](value: nil)
    ownFromId[NSDictionary[NSString, NSObject]](self.xDeviceDescriptionId)

  method isFlipped*(self: NSGraphicsContext): bool =
    if self.isNil:
      return false
    if not self.xFocusStack.isNil and self.xFocusStack.len > 0:
      let focusView = self.xFocusStack[self.xFocusStack.len - 1]
      if not focusView.isNil:
        return sendBool(focusView.value, getSelector("isFlipped"))
    self.xIsFlipped

  method setCompositingOperation*(
      self: NSGraphicsContext, value: NSCompositingOperation
  ) =
    if self.isNil:
      return
    if value < NSCompositeClear or value > NSCompositePlusLighter:
      return
    self.xCompositingOperation = value

  method compositingOperation*(self: NSGraphicsContext): NSCompositingOperation =
    if self.isNil:
      return NSCompositeSourceOver
    self.xCompositingOperation

  method saveGraphicsState*(self: NSGraphicsContext) =
    if self.isNil:
      return
    self.xSavedGraphicsStates.add(
      NSGraphicsStateSnapshot(
        shouldAntialias: self.xShouldAntialias,
        imageInterpolation: self.xImageInterpolation,
        renderingIntent: self.xRenderingIntent,
        patternPhase: self.xPatternPhase,
        compositingOperation: self.xCompositingOperation,
        fillColor: self.xFillColor,
        strokeColor: self.xStrokeColor,
      )
    )

  method restoreGraphicsState*(self: NSGraphicsContext) =
    if self.isNil:
      return
    if self.xSavedGraphicsStates.len == 0:
      return
    let snapshot = self.xSavedGraphicsStates[^1]
    self.xSavedGraphicsStates.setLen(self.xSavedGraphicsStates.len - 1)
    self.xShouldAntialias = snapshot.shouldAntialias
    self.xImageInterpolation = snapshot.imageInterpolation
    self.xRenderingIntent = snapshot.renderingIntent
    self.xPatternPhase = snapshot.patternPhase
    self.xCompositingOperation = snapshot.compositingOperation
    self.xFillColor = snapshot.fillColor
    self.xStrokeColor = snapshot.strokeColor

  method setFillColor*(self: NSGraphicsContext, color: NSColor) =
    if self.isNil:
      return
    self.xFillColor = color

  method fillColor*(self: NSGraphicsContext): NSColor =
    if self.isNil:
      return nsColor(0.0, 0.0, 0.0, 1.0)
    self.xFillColor

  method setStrokeColor*(self: NSGraphicsContext, color: NSColor) =
    if self.isNil:
      return
    self.xStrokeColor = color

  method strokeColor*(self: NSGraphicsContext): NSColor =
    if self.isNil:
      return nsColor(0.0, 0.0, 0.0, 1.0)
    self.xStrokeColor

  method fillRect*(
      self: NSGraphicsContext,
      localRect: NSRect,
      color {.kw("color").}: NSColor,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    let renderPort = renderGraphicsPortForContext(self)
    if renderPort.isNil or renderPort.renders.isNil:
      return false
    let drawRect = normalizeLocalDrawRect(localRect)
    if drawRect.size.width <= 0.0 or drawRect.size.height <= 0.0:
      return false
    let drawColor =
      if operation == NSCompositeClear:
        nsColor(0.0, 0.0, 0.0, 0.0)
      else:
        color
    discard renderPort.renders[].addChild(
      0.ZLevel,
      renderPort.parentIdx,
      Fig(
        kind: nkRectangle,
        childCount: 0,
        screenBox: rect(
          drawRect.origin.x, drawRect.origin.y, drawRect.size.width,
          drawRect.size.height,
        ),
        fill: drawColor.solidFill(),
        corners: uniformCorners(0.0),
        shadows: noRenderShadows(),
        stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill()),
      ),
    )
    true

  method fillRoundedRect*(
      self: NSGraphicsContext,
      localRect: NSRect,
      color {.kw("color").}: NSColor,
      radius {.kw("radius").}: float32,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    let renderPort = renderGraphicsPortForContext(self)
    if renderPort.isNil or renderPort.renders.isNil:
      return false
    let drawRect = normalizeLocalDrawRect(localRect)
    if drawRect.size.width <= 0.0 or drawRect.size.height <= 0.0:
      return false
    let drawColor =
      if operation == NSCompositeClear:
        nsColor(0.0, 0.0, 0.0, 0.0)
      else:
        color
    let corner = clampedCornerRadius(drawRect, radius)
    discard renderPort.renders[].addChild(
      0.ZLevel,
      renderPort.parentIdx,
      Fig(
        kind: nkRectangle,
        childCount: 0,
        screenBox: rect(
          drawRect.origin.x, drawRect.origin.y, drawRect.size.width,
          drawRect.size.height,
        ),
        fill: drawColor.solidFill(),
        corners: uniformCorners(corner),
        shadows: noRenderShadows(),
        stroke: RenderStroke(weight: 0.0, fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill()),
      ),
    )
    true

  method strokeRect*(
      self: NSGraphicsContext,
      localRect: NSRect,
      color {.kw("color").}: NSColor,
      width {.kw("width").}: float32 = 1.0,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    if width <= 0.0:
      return false
    let renderPort = renderGraphicsPortForContext(self)
    if renderPort.isNil or renderPort.renders.isNil:
      return false
    let drawRect = normalizeLocalDrawRect(localRect)
    if drawRect.size.width <= 0.0 or drawRect.size.height <= 0.0:
      return false
    let drawColor =
      if operation == NSCompositeClear:
        nsColor(0.0, 0.0, 0.0, 0.0)
      else:
        color
    discard renderPort.renders[].addChild(
      0.ZLevel,
      renderPort.parentIdx,
      Fig(
        kind: nkRectangle,
        childCount: 0,
        screenBox: rect(
          drawRect.origin.x, drawRect.origin.y, drawRect.size.width,
          drawRect.size.height,
        ),
        fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill(),
        corners: uniformCorners(0.0),
        shadows: noRenderShadows(),
        stroke: RenderStroke(weight: width, fill: drawColor.solidFill()),
      ),
    )
    true

  method strokeRoundedRect*(
      self: NSGraphicsContext,
      localRect: NSRect,
      color {.kw("color").}: NSColor,
      radius {.kw("radius").}: float32,
      width {.kw("width").}: float32 = 1.0,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    if width <= 0.0:
      return false
    let renderPort = renderGraphicsPortForContext(self)
    if renderPort.isNil or renderPort.renders.isNil:
      return false
    let drawRect = normalizeLocalDrawRect(localRect)
    if drawRect.size.width <= 0.0 or drawRect.size.height <= 0.0:
      return false
    let drawColor =
      if operation == NSCompositeClear:
        nsColor(0.0, 0.0, 0.0, 0.0)
      else:
        color
    let corner = clampedCornerRadius(drawRect, radius)
    discard renderPort.renders[].addChild(
      0.ZLevel,
      renderPort.parentIdx,
      Fig(
        kind: nkRectangle,
        childCount: 0,
        screenBox: rect(
          drawRect.origin.x, drawRect.origin.y, drawRect.size.width,
          drawRect.size.height,
        ),
        fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill(),
        corners: uniformCorners(corner),
        shadows: noRenderShadows(),
        stroke: RenderStroke(weight: width, fill: drawColor.solidFill()),
      ),
    )
    true

  method drawTextLayout*(
      self: NSGraphicsContext,
      localRect: NSRect,
      layout {.kw("layout").}: GlyphArrangement,
      selectionStart {.kw("selectionStart").}: NSInteger = (-1).NSInteger,
      selectionEnd {.kw("selectionEnd").}: NSInteger = (-1).NSInteger,
      selectionColor {.kw("selectionColor").}: NSColor = default(NSColor),
  ): bool =
    let renderPort = renderGraphicsPortForContext(self)
    if renderPort.isNil or renderPort.renders.isNil:
      return false
    let drawRect = normalizeLocalDrawRect(localRect)
    if drawRect.size.width <= 0.0 or drawRect.size.height <= 0.0:
      return false
    if layout.runes.len == 0:
      return false
    let layoutLen = layout.runes.len
    let start = clamp(selectionStart.int, 0, max(layoutLen - 1, 0))
    let stop = clamp(selectionEnd.int, 0, max(layoutLen - 1, 0))
    let clampedStart = min(start, high(int16))
    let clampedStop = min(stop, high(int16))
    let hasSelection =
      layoutLen > 0 and selectionStart.int >= 0 and selectionEnd.int >= 0 and
      start <= stop
    let selectionFill =
      if hasSelection:
        if selectionColor.a <= 0.0:
          nsColor(0.35, 0.55, 1.0, 0.65).solidFill()
        else:
          selectionColor.solidFill()
      else:
        nsColor(0.0, 0.0, 0.0, 0.0).solidFill()
    let textFlags =
      if hasSelection:
        {NfInvertY, NfSelectText}
      else:
        {NfInvertY}

    discard renderPort.renders[].addChild(
      0.ZLevel,
      renderPort.parentIdx,
      Fig(
        kind: nkText,
        childCount: 0,
        flags: textFlags,
        screenBox: rect(
          drawRect.origin.x, drawRect.origin.y, drawRect.size.width,
          drawRect.size.height,
        ),
        fill: selectionFill,
        selectionRange:
          if hasSelection:
            clampedStart.int16 .. clampedStop.int16
          else:
            0'i16 .. -1'i16,
        textLayout: layout,
      ),
    )
    true

  method drawImage*(
      self: NSGraphicsContext,
      localRect: NSRect,
      imageId {.kw("imageId").}: ImageId,
      fraction {.kw("fraction").}: float32 = 1.0,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    if imageId.int == 0:
      return false
    if fraction <= 0.0:
      return false
    let renderPort = renderGraphicsPortForContext(self)
    if renderPort.isNil or renderPort.renders.isNil:
      return false
    let drawRect = normalizeLocalDrawRect(localRect)
    if drawRect.size.width <= 0.0 or drawRect.size.height <= 0.0:
      return false

    if operation == NSCompositeClear:
      return self.fillRect(drawRect, nsColor(0.0, 0.0, 0.0, 0.0), operation)

    let clampedFraction =
      if fraction < 0.0:
        0.0'f32
      elif fraction > 1.0:
        1.0'f32
      else:
        fraction
    let imageFill = nsColor(1.0, 1.0, 1.0, clampedFraction).solidFill()
    discard renderPort.renders[].addChild(
      0.ZLevel,
      renderPort.parentIdx,
      Fig(
        kind: nkImage,
        childCount: 0,
        screenBox: rect(
          drawRect.origin.x, drawRect.origin.y, drawRect.size.width,
          drawRect.size.height,
        ),
        fill: nsColor(0.0, 0.0, 0.0, 0.0).solidFill(),
        image: ImageStyle(id: imageId, fill: imageFill),
      ),
    )
    true

  method flushGraphics*(self: NSGraphicsContext) =
    discard self
    discard

  method pushFocusView*(self: NSGraphicsContext, view: NSView) =
    if self.isNil or view.isNil:
      return
    var stack = self.xFocusStack
    if stack.isNil:
      stack = nsArray[NSObject]()
    stack.addObject(view.NSObject)
    self.xFocusStack = stack

  method popFocusView*(self: NSGraphicsContext): NSView =
    if self.isNil or self.xFocusStack.isNil or self.xFocusStack.len == 0:
      return NSView(value: nil)
    var stack = self.xFocusStack
    let idx = stack.len - 1
    let view = stack[idx]
    stack.del(idx)
    self.xFocusStack = stack
    return NSView(view)

  method dealloc(self: NSGraphicsContext) {.used.} =
    if not self.xFocusStack.isNil:
      var stack = self.xFocusStack
      stack.clear()
    self.xFocusStack = NSArray[NSObject](value: nil)
    self.xSavedGraphicsStates.setLen(0)
    clearOwned(self.xDeviceDescriptionId)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSGraphicsContext, self, getSelector("dealloc"))

proc graphicsContextWithWindow*(
    t: typedesc[NSGraphicsContext], window: NSWindow
): NSGraphicsContext =
  var allocated = NSGraphicsContext.alloc()
  result = allocated.initWithWindow(window)
  allocated.value = nil

proc graphicsContextWithGraphicsPort*(
    t: typedesc[NSGraphicsContext], context: pointer, flipped {.kw("flipped").}: bool
): NSGraphicsContext =
  var allocated = NSGraphicsContext.alloc()
  result = allocated.initWithGraphicsPort(context, flipped)
  allocated.value = nil

proc graphicsContextWithBitmapImageRep*(
    t: typedesc[NSGraphicsContext], imageRep: NSBitmapImageRep
): NSGraphicsContext =
  var allocated = NSGraphicsContext.alloc()
  result = allocated.initWithBitmapImageRep(imageRep)
  allocated.value = nil

proc currentContext*(t: typedesc[NSGraphicsContext]): NSGraphicsContext =
  currentGraphicsContext()

proc setCurrentContext*(t: typedesc[NSGraphicsContext], context: NSGraphicsContext) =
  currentGraphicsContextId = replacedOwnedId(currentGraphicsContextId, context.value)

proc saveGraphicsState*(t: typedesc[NSGraphicsContext]) =
  let current = t.currentContext()
  if current.isNil:
    return
  graphicsContextStack.add(retainId(current.value))
  current.saveGraphicsState()

proc restoreGraphicsState*(t: typedesc[NSGraphicsContext]) =
  if graphicsContextStack.len == 0:
    return
  let previousId = graphicsContextStack[graphicsContextStack.high]
  graphicsContextStack.setLen(graphicsContextStack.len - 1)
  currentGraphicsContextId = replacedOwnedId(currentGraphicsContextId, previousId)
  let previousContext = asTypeRaw[NSGraphicsContext](previousId)
  previousContext.restoreGraphicsState()
  releaseId(previousId)

proc currentContextDrawingToScreen*(t: typedesc[NSGraphicsContext]): bool =
  let current = t.currentContext()
  if current.isNil:
    return false
  current.isDrawingToScreen()

proc setQuartzDebuggingEnabled*(t: typedesc[NSGraphicsContext], enabled: bool) =
  quartzDebuggingEnabled = enabled

proc quartzDebuggingIsEnabled*(t: typedesc[NSGraphicsContext]): bool =
  quartzDebuggingEnabled

proc inQuartzDebugMode*(t: typedesc[NSGraphicsContext]): bool =
  quartzDebuggingEnabled and quartzDebugModeEnabled

proc setQuartzDebugMode*(t: typedesc[NSGraphicsContext], mode: bool) =
  quartzDebugModeEnabled = mode

proc hasActiveGraphicsContextForDrawing*(): bool =
  let renderPort = currentRenderGraphicsPort()
  if renderPort.isNil:
    return false
  (not renderPort.renders.isNil)

proc new*(t: typedesc[NSGraphicsContext]): NSGraphicsContext =
  var allocated = NSGraphicsContext.alloc()
  result = initOwned(move(allocated))
