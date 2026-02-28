import ./runtime
import ./cells
import ./images
import ./graphics
import ./colors

proc scaledImageSizeInFrameSize(
    imageSize: NSSize, frameSize: NSSize, scaling: int
): NSSize =
  if imageSize.width <= 0 or imageSize.height <= 0:
    return nsSize(0, 0)
  case scaling
  of NSImageScaleProportionallyDown:
    let xscale = frameSize.width / imageSize.width
    let yscale = frameSize.height / imageSize.height
    let scale = min(1.0'f32, min(xscale, yscale))
    nsSize(imageSize.width * scale, imageSize.height * scale)
  of NSImageScaleAxesIndependently:
    frameSize
  of NSImageScaleProportionallyUpOrDown:
    let xscale = frameSize.width / imageSize.width
    let yscale = frameSize.height / imageSize.height
    let scale = min(xscale, yscale)
    nsSize(imageSize.width * scale, imageSize.height * scale)
  else:
    imageSize

proc imageValue(self: NSImageCell): NSImage =
  let direct = self.image()
  if not direct.isNil:
    return direct
  let objectValue = self.objectValue()
  if objectValue.isNil:
    return NSImage(value: nil)
  if objectValue.isKindOfClass(NSImage):
    return ownFromId[NSImage](objectValue.value)
  NSImage(value: nil)

objcImpl:
  type NSImageCell* = object of NSCell
    xAnimates {.set: setAnimates, get: animates.}: bool
    xImageAlignment {.set: setImageAlignment, get: imageAlignment.}: NSImageAlignment
    xImageScaling {.set: setImageScaling, get: imageScaling.}: int
    xFrameStyle {.set: setImageFrameStyle, get: imageFrameStyle.}: int

  method init*(self: var NSImageCell): NSImageCell =
    result =
      asTypeRaw[NSImageCell](callSuperIdFrom(NSImageCell, self, getSelector("init")))
    if result.isNil:
      return
    result.setType(NSImageCellType)

  method imageRectForBounds*(self: NSImageCell, frame: NSRect): NSRect =
    let image = imageValue(self)
    if image.isNil:
      return nsRect(frame.origin.x, frame.origin.y, 0.0, 0.0)

    let imageSize =
      scaledImageSizeInFrameSize(image.size(), frame.size, self.xImageScaling)
    var rect = frame

    case self.xImageAlignment
    of NSImageAlignTop:
      rect.origin.x += (frame.size.width * 0.5) - (imageSize.width * 0.5)
      rect.origin.y += frame.size.height - imageSize.height
    of NSImageAlignTopLeft:
      rect.origin.y += frame.size.height - imageSize.height
    of NSImageAlignTopRight:
      rect.origin.x += frame.size.width - imageSize.width
      rect.origin.y += frame.size.height - imageSize.height
    of NSImageAlignLeft:
      rect.origin.y += (frame.size.height * 0.5) - (imageSize.height * 0.5)
    of NSImageAlignBottom:
      rect.origin.x += (frame.size.width * 0.5) - (imageSize.width * 0.5)
    of NSImageAlignBottomLeft:
      discard
    of NSImageAlignBottomRight:
      rect.origin.x += frame.size.width - imageSize.width
    of NSImageAlignRight:
      rect.origin.x += frame.size.width - imageSize.width
      rect.origin.y += (frame.size.height * 0.5) - (imageSize.height * 0.5)
    else:
      rect.origin.x += (frame.size.width * 0.5) - (imageSize.width * 0.5)
      rect.origin.y += (frame.size.height * 0.5) - (imageSize.height * 0.5)

    rect.size = imageSize
    rect

  method drawInteriorWithFrame*(
      self: NSImageCell, controlFrame: NSRect, control {.kw("inView").}: NSView
  ) =
    discard control
    let image = imageValue(self)
    if image.isNil:
      return
    let drawInRect = self.imageRectForBounds(controlFrame)
    if drawInRect.size.width <= 0.0 or drawInRect.size.height <= 0.0:
      return
    image.drawInRect(
      drawInRect, nsRect(0.0, 0.0, 0.0, 0.0), NSCompositeSourceOver.int, 1.0
    )

  method drawWithFrame*(
      self: NSImageCell, frame: NSRect, control {.kw("inView").}: NSView
  ) =
    var inner = frame
    case self.xFrameStyle
    of NSImageFramePhoto:
      var shadow = frame
      shadow.size.height = max(shadow.size.height - 1.0, 0.0)
      shadow.size.width = max(shadow.size.width - 1.0, 0.0)
      shadow.origin.x += 1.0
      NSColor.darkGrayColor().setFill()
      NSRectFillUsingOperation(shadow, NSCompositeSourceOver)

      shadow.origin.x -= 1.0
      shadow.origin.y += 1.0
      NSColor.whiteColor().setFill()
      NSRectFillUsingOperation(shadow, NSCompositeCopy)

      inner = nsRect(
        frame.origin.x + 2.0,
        frame.origin.y + 2.0,
        max(frame.size.width - 4.0, 0.0),
        max(frame.size.height - 4.0, 0.0),
      )
    of NSImageFrameGrayBezel:
      NSDrawGrayBezel(frame, frame)
      inner = nsRect(
        frame.origin.x + 2.0,
        frame.origin.y + 2.0,
        max(frame.size.width - 4.0, 0.0),
        max(frame.size.height - 4.0, 0.0),
      )
    of NSImageFrameGroove:
      NSDrawGroove(frame, frame)
      inner = nsRect(
        frame.origin.x + 2.0,
        frame.origin.y + 2.0,
        max(frame.size.width - 4.0, 0.0),
        max(frame.size.height - 4.0, 0.0),
      )
    of NSImageFrameButton:
      NSDrawButton(frame, frame)
      inner = nsRect(
        frame.origin.x + 2.0,
        frame.origin.y + 2.0,
        max(frame.size.width - 4.0, 0.0),
        max(frame.size.height - 4.0, 0.0),
      )
    else:
      discard
    self.drawInteriorWithFrame(inner, control)

  method dealloc(self: NSImageCell) {.used.} =
    destroyIvarFields(self)
    discard callSuperIdFrom(NSImageCell, self, getSelector("dealloc"))

proc new*(t: typedesc[NSImageCell]): NSImageCell =
  var allocated = NSImageCell.alloc()
  result = initOwned(move(allocated))
