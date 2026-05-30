import std/[math, strutils]

import ./runtime
import ./graphicscontexts
import ./colors

const
  NSBlack* = 0.0'f32
  NSDarkGray* = 0.333'f32
  NSLightGray* = 0.667'f32
  NSWhite* = 1.0'f32

  NSDeviceBlackColorSpaceName* = "NSDeviceBlackColorSpace"
  NSCalibratedBlackColorSpaceName* = "NSCalibratedBlackColorSpace"

var NSDeviceBlackColorSpace* {.threadvar.}: NSString
var NSCalibratedBlackColorSpace* {.threadvar.}: NSString

proc ensureGraphicsColorSpaceNames() =
  ensureColorSpaceNames()
  if NSDeviceBlackColorSpace.isNil:
    NSDeviceBlackColorSpace = ns(NSDeviceBlackColorSpaceName)
    NSCalibratedBlackColorSpace = ns(NSCalibratedBlackColorSpaceName)

proc rectIsEmpty(rect: NSRect): bool {.inline.} =
  rect.size.width <= 0.0 or rect.size.height <= 0.0

proc maxX(rect: NSRect): float32 {.inline.} =
  rect.origin.x + rect.size.width

proc maxY(rect: NSRect): float32 {.inline.} =
  rect.origin.y + rect.size.height

proc intersectRect(a: NSRect, b: NSRect): NSRect =
  let x0 = max(a.origin.x, b.origin.x)
  let y0 = max(a.origin.y, b.origin.y)
  let x1 = min(maxX(a), maxX(b))
  let y1 = min(maxY(a), maxY(b))
  if x1 <= x0 or y1 <= y0:
    return nsRect(0.0, 0.0, 0.0, 0.0)
  nsRect(x0, y0, x1 - x0, y1 - y0)

proc drawRectWithColor(
    rect: NSRect, color: NSColor, operation: NSCompositingOperation
): bool =
  if rectIsEmpty(rect):
    return false
  NSGraphicsContext.currentContext().fillRect(rect, color, operation)

proc drawFrameWithColor(
    rect: NSRect, color: NSColor, width: float32, operation: NSCompositingOperation
): bool =
  if rectIsEmpty(rect):
    return false
  NSGraphicsContext.currentContext().strokeRect(rect, color, width, operation)

proc drawColorRects(
    boundsRect: NSRect,
    clipRect: NSRect,
    rects: openArray[NSRect],
    colors: openArray[NSColor],
    count: int,
): NSRect =
  let limit = min(count, min(rects.len, colors.len))
  if limit <= 0:
    return boundsRect
  for i in 0 ..< limit:
    let clipped = intersectRect(rects[i], clipRect)
    if rectIsEmpty(clipped):
      continue
    discard drawRectWithColor(clipped, colors[i], NSCompositeCopy)
  boundsRect

proc NSBitsPerSampleFromDepth*(depth: NSWindowDepth): int =
  let rawDepth = cast[int32](depth)
  int(rawDepth and 0xFF'i32)

proc NSColorSpaceFromDepth*(depth: NSWindowDepth): NSString =
  ensureGraphicsColorSpaceNames()
  let rawDepth = cast[int32](depth)
  let code = int((rawDepth and 0xFF00'i32) shr 8)
  case code
  of 0:
    NSCalibratedBlackColorSpace
  of 1:
    NSCalibratedWhiteColorSpace
  of 2:
    NSCalibratedRGBColorSpace
  of 5:
    NSDeviceCMYKColorSpace
  of 6:
    NSDeviceRGBColorSpace
  else:
    NSString(value: nil)

proc NSNumberOfColorComponents*(colorSpaceName: NSString): int =
  if colorSpaceName.isNil:
    return 0
  let colorSpace = ($colorSpaceName).toLowerAscii()
  if colorSpace.contains("rgb"):
    return 3
  if colorSpace.contains("cmyk"):
    return 4
  1

proc NSBitsPerPixelFromDepth*(depth: NSWindowDepth): int =
  let colorSpace = NSColorSpaceFromDepth(depth)
  if colorSpace.isNil:
    return 0
  let bitsPerSample = NSBitsPerSampleFromDepth(depth)
  bitsPerSample * NSNumberOfColorComponents(colorSpace)

proc NSPlanarFromDepth*(depth: NSWindowDepth): bool =
  discard depth
  false

proc NSRectClipList*(rects: ptr NSRect, count: int) =
  discard rects
  discard count

proc NSRectClip*(rect: NSRect) =
  discard rect

proc NSRectFillListWithColors*(rects: ptr NSRect, colors: ptr NSColor, count: int) =
  if rects.isNil or colors.isNil or count <= 0:
    return
  let rectItems = cast[ptr UncheckedArray[NSRect]](rects)
  let colorItems = cast[ptr UncheckedArray[NSColor]](colors)
  for i in 0 ..< count:
    discard drawRectWithColor(rectItems[i], colorItems[i], NSCompositeCopy)

proc NSRectFillListWithColors*(rects: openArray[NSRect], colors: openArray[NSColor]) =
  let count = min(rects.len, colors.len)
  if count <= 0:
    return
  NSRectFillListWithColors(unsafeAddr rects[0], unsafeAddr colors[0], count)

proc NSRectFillListWithGrays*(rects: ptr NSRect, grays: ptr float32, count: int) =
  if rects.isNil or grays.isNil or count <= 0:
    return
  let rectItems = cast[ptr UncheckedArray[NSRect]](rects)
  let grayItems = cast[ptr UncheckedArray[float32]](grays)
  for i in 0 ..< count:
    let gray = max(0.0'f32, min(1.0'f32, grayItems[i]))
    discard
      drawRectWithColor(rectItems[i], nsColor(gray, gray, gray, 1.0), NSCompositeCopy)

proc NSRectFillListWithGrays*(rects: openArray[NSRect], grays: openArray[float32]) =
  let count = min(rects.len, grays.len)
  if count <= 0:
    return
  NSRectFillListWithGrays(unsafeAddr rects[0], unsafeAddr grays[0], count)

proc NSRectFillList*(rects: ptr NSRect, count: int) =
  if rects.isNil or count <= 0:
    return
  let color = NSGraphicsContext.currentContext().fillColor()
  let rectItems = cast[ptr UncheckedArray[NSRect]](rects)
  for i in 0 ..< count:
    discard drawRectWithColor(rectItems[i], color, NSCompositeCopy)

proc NSRectFillList*(rects: openArray[NSRect]) =
  if rects.len == 0:
    return
  NSRectFillList(unsafeAddr rects[0], rects.len)

proc NSRectFill*(rect: NSRect) =
  let color = NSGraphicsContext.currentContext().fillColor()
  discard drawRectWithColor(rect, color, NSCompositeCopy)

proc NSEraseRect*(rect: NSRect) =
  discard drawRectWithColor(rect, NSColor.whiteColor(), NSCompositeCopy)

proc NSRectFillListUsingOperation*(
    rects: ptr NSRect, count: int, operation: NSCompositingOperation
) =
  if rects.isNil or count <= 0:
    return
  let color = NSGraphicsContext.currentContext().fillColor()
  let rectItems = cast[ptr UncheckedArray[NSRect]](rects)
  for i in 0 ..< count:
    discard drawRectWithColor(rectItems[i], color, operation)

proc NSRectFillUsingOperation*(rect: NSRect, operation: NSCompositingOperation) =
  discard
    drawRectWithColor(rect, NSGraphicsContext.currentContext().fillColor(), operation)

proc NSFrameRectWithWidth*(rect: NSRect, width: float32) =
  discard drawFrameWithColor(
    rect, NSGraphicsContext.currentContext().strokeColor(), width, NSCompositeCopy
  )

proc NSFrameRectWithWidthUsingOperation*(
    rect: NSRect, width: float32, operation: NSCompositingOperation
) =
  discard drawFrameWithColor(
    rect, NSGraphicsContext.currentContext().strokeColor(), width, operation
  )

proc NSFrameRect*(rect: NSRect) =
  discard drawFrameWithColor(
    rect, NSGraphicsContext.currentContext().strokeColor(), 1.0, NSCompositeSourceOver
  )

proc NSDottedFrameRect*(rect: NSRect) =
  if rectIsEmpty(rect):
    return
  let color = NSColor.blackColor()
  let minX = floor(rect.origin.x).int
  let minY = floor(rect.origin.y).int
  let maxXInt = ceil(maxX(rect)).int
  let maxYInt = ceil(maxY(rect)).int
  var on = false

  for x in minX ..< maxXInt:
    on = not on
    if on:
      discard drawRectWithColor(
        nsRect(x.float32, minY.float32, 1.0, 1.0), color, NSCompositeCopy
      )

  for y in minY ..< maxYInt:
    on = not on
    if on:
      discard drawRectWithColor(
        nsRect((maxXInt - 1).float32, y.float32, 1.0, 1.0), color, NSCompositeCopy
      )

  var x = maxXInt
  while x > minX:
    dec x
    on = not on
    if on:
      discard drawRectWithColor(
        nsRect(x.float32, maxYInt.float32, 1.0, 1.0), color, NSCompositeCopy
      )

  var y = maxYInt
  while y > minY:
    dec y
    on = not on
    if on:
      discard drawRectWithColor(
        nsRect(minX.float32, y.float32, 1.0, 1.0), color, NSCompositeCopy
      )

proc NSDrawButton*(rect: NSRect, clipRect: NSRect) =
  var rects: array[7, NSRect]
  var colors: array[7, NSColor]
  for i in 0 ..< rects.len:
    rects[i] = rect

  let flipped = NSGraphicsContext.currentContext().isFlipped()
  if flipped:
    colors[0] = NSColor.blackColor()
    rects[0].origin.y += rect.size.height - 1
    rects[0].size.height = 1

    colors[1] = NSColor.blackColor()
    rects[1].origin.x += rect.size.width - 1
    rects[1].size.width = 1

    colors[2] = NSColor.darkGrayColor()
    rects[2].origin.x += 1
    rects[2].size.width -= 2
    rects[2].origin.y += rect.size.height - 2
    rects[2].size.height = 1

    colors[3] = NSColor.darkGrayColor()
    rects[3].origin.x += rect.size.width - 2
    rects[3].origin.y += 1
    rects[3].size.width = 1
    rects[3].size.height -= 2

    colors[4] = NSColor.whiteColor()
    rects[4].size.height = 1
    rects[4].size.width -= 1

    colors[5] = NSColor.whiteColor()
    rects[5].size.width = 1
    rects[5].size.height -= 1

    colors[6] = NSColor.controlColor()
    rects[6].origin.x += 1
    rects[6].origin.y += 1
    rects[6].size.width -= 3
    rects[6].size.height -= 3
  else:
    colors[0] = NSColor.blackColor()
    rects[0].size.height = 1

    colors[1] = NSColor.blackColor()
    rects[1].origin.x += rect.size.width - 1
    rects[1].size.width = 1

    colors[2] = NSColor.darkGrayColor()
    rects[2].origin.x += 1
    rects[2].origin.y += 1
    rects[2].size.width -= 2
    rects[2].size.height = 1

    colors[3] = NSColor.darkGrayColor()
    rects[3].origin.x += rect.size.width - 2
    rects[3].origin.y += 2
    rects[3].size.width = 1
    rects[3].size.height -= 2

    colors[4] = NSColor.whiteColor()
    rects[4].origin.y += 1
    rects[4].size.width = 1
    rects[4].size.height -= 1

    colors[5] = NSColor.whiteColor()
    rects[5].origin.y += rect.size.height - 1
    rects[5].size.width -= 1
    rects[5].size.height = 1

    colors[6] = NSColor.controlColor()
    rects[6].origin.x += 1
    rects[6].origin.y += 2
    rects[6].size.width -= 3
    rects[6].size.height -= 3

  discard drawColorRects(rect, clipRect, rects, colors, 7)

proc NSDrawGrayBezel*(rect: NSRect, clipRect: NSRect) =
  var rects: array[4, NSRect]
  var colors: array[4, NSColor]
  for i in 0 ..< rects.len:
    rects[i] = rect

  let flipped = NSGraphicsContext.currentContext().isFlipped()
  if flipped:
    colors[0] = NSColor.whiteColor()
    colors[1] = NSColor.controlShadowColor()
    rects[1].size.width -= 1
    rects[1].size.height -= 1
    colors[2] = NSColor.blackColor()
    rects[2].origin.x += 1
    rects[2].origin.y += 1
    rects[2].size.width -= 3
    rects[2].size.height -= 3
    colors[3] = NSColor.controlColor()
    rects[3].origin.x += 2
    rects[3].origin.y += 2
    rects[3].size.width -= 3
    rects[3].size.height -= 3
  else:
    colors[0] = NSColor.whiteColor()
    colors[1] = NSColor.controlShadowColor()
    rects[1].origin.y += 1
    rects[1].size.width -= 1
    rects[1].size.height -= 1
    colors[2] = NSColor.blackColor()
    rects[2].origin.x += 1
    rects[2].origin.y += 2
    rects[2].size.width -= 3
    rects[2].size.height -= 3
    colors[3] = NSColor.controlColor()
    rects[3].origin.x += 2
    rects[3].origin.y += 1
    rects[3].size.width -= 3
    rects[3].size.height -= 3

  discard drawColorRects(rect, clipRect, rects, colors, 4)

proc NSDrawWhiteBezel*(rect: NSRect, clipRect: NSRect) =
  var rects: array[7, NSRect]
  var colors: array[7, NSColor]
  for i in 0 ..< rects.len:
    rects[i] = rect

  let flipped = NSGraphicsContext.currentContext().isFlipped()
  if flipped:
    colors[0] = NSColor.whiteColor()
    colors[1] = NSColor.controlShadowColor()
    rects[1].size.height = 1
    colors[2] = NSColor.controlShadowColor()
    rects[2].size.width = 1
    rects[2].size.height -= 1
    colors[3] = NSColor.controlColor()
    rects[3].origin.x += 1
    rects[3].origin.y += 1
    rects[3].size.width -= 2
    rects[3].size.height -= 2
    colors[4] = NSColor.blackColor()
    rects[4].origin.x += 1
    rects[4].origin.y += 1
    rects[4].size.width -= 2
    rects[4].size.height = 1
    colors[5] = NSColor.blackColor()
    rects[5].origin.x += 1
    rects[5].origin.y += 1
    rects[5].size.width = 1
    rects[5].size.height -= 3
    colors[6] = NSColor.whiteColor()
    rects[6].origin.x += 2
    rects[6].origin.y += 2
    rects[6].size.width -= 4
    rects[6].size.height -= 4
  else:
    colors[0] = NSColor.whiteColor()
    colors[1] = NSColor.controlShadowColor()
    rects[1].origin.y += rect.size.height
    rects[1].size.height = 1
    colors[2] = NSColor.controlShadowColor()
    rects[2].size.width = 1
    rects[2].origin.y += 1
    rects[2].size.height -= 1
    colors[3] = NSColor.controlColor()
    rects[3].origin.x += 1
    rects[3].origin.y += 1
    rects[3].size.width -= 2
    rects[3].size.height -= 2
    colors[4] = NSColor.blackColor()
    rects[4].origin.x += 1
    rects[4].origin.y += rect.size.height - 1
    rects[4].size.width -= 2
    rects[4].size.height = 1
    colors[5] = NSColor.blackColor()
    rects[5].origin.x += 1
    rects[5].origin.y += 2
    rects[5].size.width = 1
    rects[5].size.height -= 3
    colors[6] = NSColor.whiteColor()
    rects[6].origin.x += 2
    rects[6].origin.y += 2
    rects[6].size.width -= 4
    rects[6].size.height -= 3

  discard drawColorRects(rect, clipRect, rects, colors, 7)

proc NSDrawDarkBezel*(rect: NSRect, clipRect: NSRect) =
  NSDrawGrayBezel(rect, clipRect)

proc NSDrawLightBezel*(rect: NSRect, clipRect: NSRect) =
  NSDrawWhiteBezel(rect, clipRect)

proc NSDrawGroove*(rect: NSRect, clipRect: NSRect) =
  var rects: array[4, NSRect]
  var colors: array[4, NSColor]
  for i in 0 ..< rects.len:
    rects[i] = rect

  let flipped = NSGraphicsContext.currentContext().isFlipped()
  if flipped:
    colors[0] = NSColor.controlShadowColor()
    colors[1] = NSColor.whiteColor()
    rects[1].origin.x += 1
    rects[1].origin.y += 1
    colors[2] = NSColor.controlShadowColor()
    rects[2].origin.x += 2
    rects[2].origin.y += 2
    rects[2].size.width -= 3
    rects[2].size.height -= 3
    colors[3] = NSColor.controlColor()
    rects[3].origin.x += 2
    rects[3].origin.y += 2
    rects[3].size.width -= 4
    rects[3].size.height -= 4
  else:
    colors[0] = NSColor.controlShadowColor()
    colors[1] = NSColor.whiteColor()
    rects[1].origin.x += 1
    rects[1].size.height -= 1
    colors[2] = NSColor.controlShadowColor()
    rects[2].origin.x += 2
    rects[2].origin.y += 1
    rects[2].size.width -= 3
    rects[2].size.height -= 3
    colors[3] = NSColor.controlColor()
    rects[3].origin.x += 2
    rects[3].origin.y += 2
    rects[3].size.width -= 4
    rects[3].size.height -= 4

  discard drawColorRects(rect, clipRect, rects, colors, 4)

proc NSDrawWindowBackground*(rect: NSRect) =
  NSColor.windowBackgroundColor().setFill()
  NSRectFill(rect)

proc NSDrawTiledRects*(
    bounds: NSRect, clip: NSRect, sides: ptr NSRectEdge, grays: ptr float32, count: int
): NSRect =
  discard clip
  discard sides
  discard grays
  discard count
  bounds

proc NSHighlightRect*(rect: NSRect) =
  discard drawRectWithColor(rect, NSColor.highlightColor(), NSCompositeSourceOver)

proc NSCopyBits*(gState: int, rect: NSRect, point: NSPoint) =
  discard gState
  discard rect
  discard point

proc NSBeep*() =
  discard

proc NSEnableScreenUpdates*() =
  discard

proc NSDisableScreenUpdates*() =
  discard

proc NSShowAnimationEffect*(
    effect: NSAnimationEffect,
    center: NSPoint,
    size: NSSize,
    delegate: NSObject,
    didEndSelector: SEL,
    context: pointer,
) =
  discard effect
  discard center
  discard size
  discard delegate
  discard didEndSelector
  discard context
