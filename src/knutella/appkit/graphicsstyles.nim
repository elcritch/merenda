import ./runtime
import ./graphicscontexts
import ./views

objcImpl:
  type NSGraphicsStyle* = object of NSObject
    xView {.get: view.}: NSView

  method initWithView*(self: var NSGraphicsStyle, view: NSView): NSGraphicsStyle =
    result = asTypeRaw[NSGraphicsStyle](
      callSuperIdFrom(NSGraphicsStyle, self, getSelector("init"))
    )
    if result.isNil:
      return
    initIvarFields(result)
    result.xView = view

  method drawRectFill*(
      self: NSGraphicsStyle,
      rect: NSRect,
      color {.kw("color").}: NSColor,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    discard self
    NSGraphicsContext.currentContext().fillRect(rect, color, operation)

  method drawRoundedRectFill*(
      self: NSGraphicsStyle,
      rect: NSRect,
      color {.kw("color").}: NSColor,
      radius {.kw("radius").}: float32,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    discard self
    NSGraphicsContext.currentContext().fillRoundedRect(rect, color, radius, operation)

  method drawRectFrame*(
      self: NSGraphicsStyle,
      rect: NSRect,
      color {.kw("color").}: NSColor,
      width {.kw("width").}: float32 = 1.0,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    discard self
    NSGraphicsContext.currentContext().strokeRect(rect, color, width, operation)

  method drawRoundedRectFrame*(
      self: NSGraphicsStyle,
      rect: NSRect,
      color {.kw("color").}: NSColor,
      radius {.kw("radius").}: float32,
      width {.kw("width").}: float32 = 1.0,
      operation {.kw("operation").}: NSCompositingOperation = NSCompositeSourceOver,
  ): bool =
    discard self
    NSGraphicsContext.currentContext().strokeRoundedRect(
      rect, color, radius, width, operation
    )

  method dealloc(self: NSGraphicsStyle) {.used.} =
    destroyIvarFields(self)
    discard callSuperIdFrom(NSGraphicsStyle, self, getSelector("dealloc"))

objcImpl:
  method graphicsStyle*(self: NSView): NSGraphicsStyle =
    var allocated = NSGraphicsStyle.alloc()
    result = allocated.initWithView(self)
    allocated.value = nil
