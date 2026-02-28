import std/math

import ./runtime
import ./responders
import ./views
import ./colors
import ./graphics
import ./fonts

const
  NSNoTitle* = 0
  NSAboveTop* = 1
  NSAtTop* = 2
  NSBelowTop* = 3
  NSAboveBottom* = 4
  NSAtBottom* = 5
  NSBelowBottom* = 6

  NSBoxPrimary* = 0
  NSBoxSecondary* = 1
  NSBoxSeparator* = 2
  NSBoxOldStyle* = 3
  NSBoxCustom* = 4

  TextGap = 4.0'f32

objcImpl:
  type NSBox* = object of NSView
    xBoxType {.get: boxType.}: int
    xBorderType {.get: borderType.}: int
    xTitlePosition {.get: titlePosition.}: int
    xTransparent {.get: isTransparent.}: bool
    xContentMargins {.get: contentViewMargins.}: NSSize
    xTitle {.get: title.}: NSString
    xContentView: NSView
    xBorderWidth {.get: borderWidth.}: float32
    xCornerRadius {.get: cornerRadius.}: float32
    xBorderColor {.get: borderColor.}: NSColor
    xFillColor {.get: fillColor.}: NSColor
    xTitleFont {.get: titleFont.}: NSFont

proc boxHasVisibleTitle(self: NSBox): bool =
  if self.isNil:
    return false
  if self.xTitlePosition == NSNoTitle:
    return false
  (not self.xTitle.isNil) and self.xTitle.len > 0

proc boxTitleHeight(self: NSBox): float32 =
  if not boxHasVisibleTitle(self):
    return 0.0
  let fontSize =
    if self.xTitleFont.isNil:
      12.0'f32
    else:
      max(self.xTitleFont.pointSize(), 1.0'f32)
  ceil(fontSize + 2.0'f32).float32

proc boxGrooveRect(self: NSBox): NSRect =
  var resultRect = self.bounds()
  let titleHeight = boxTitleHeight(self)

  case self.xTitlePosition
  of NSNoTitle:
    discard
  of NSAboveTop:
    let delta = titleHeight + TextGap
    resultRect.size.height = max(resultRect.size.height - delta, 0.0)
  of NSAtTop:
    let delta = floor(titleHeight * 0.5'f32).float32
    resultRect.size.height = max(resultRect.size.height - delta, 0.0)
  of NSBelowTop:
    discard
  of NSAboveBottom:
    discard
  of NSAtBottom:
    let delta = floor(titleHeight * 0.5'f32).float32
    resultRect.origin.y += delta
    resultRect.size.height = max(resultRect.size.height - delta, 0.0)
  of NSBelowBottom:
    let delta = titleHeight + TextGap
    resultRect.origin.y += delta
    resultRect.size.height = max(resultRect.size.height - delta, 0.0)
  else:
    discard

  resultRect

proc boxContentRect(self: NSBox): NSRect =
  var rect = boxGrooveRect(self)
  let baseInset =
    case self.xBorderType
    of NSNoBorder.int: 0.0'f32
    of NSGrooveBorder.int: 2.0'f32
    else: 1.0'f32
  let borderInset =
    if self.xBoxType == NSBoxCustom and self.xBorderType != NSNoBorder.int:
      max(baseInset, self.xBorderWidth)
    else:
      baseInset
  let insetX = max(borderInset + self.xContentMargins.width, 0.0)
  let insetY = max(borderInset + self.xContentMargins.height, 0.0)
  rect.origin.x += insetX
  rect.origin.y += insetY
  rect.size.width = max(rect.size.width - insetX * 2.0, 0.0)
  rect.size.height = max(rect.size.height - insetY * 2.0, 0.0)
  rect

proc boxUpdateContentViewFrame(self: NSBox) =
  if self.isNil or self.xContentView.isNil:
    return
  let contentRect = boxContentRect(self)
  self.xContentView.setFrame(
    contentRect.origin.x, contentRect.origin.y, contentRect.size.width,
    contentRect.size.height,
  )

proc boxTitleRect(self: NSBox): NSRect =
  if self.isNil or not boxHasVisibleTitle(self):
    return nsRect(0.0, 0.0, 0.0, 0.0)
  let bounds = self.bounds()
  let titleHeight = boxTitleHeight(self)
  result.origin.x = 10.0 + TextGap
  result.size.height = titleHeight
  result.size.width = max(bounds.size.width - result.origin.x, 0.0)

  case self.xTitlePosition
  of NSAboveTop, NSAtTop:
    result.origin.y = bounds.size.height - result.size.height
  of NSBelowTop:
    result.origin.y = bounds.size.height - (result.size.height + TextGap)
  of NSAboveBottom:
    result.origin.y = TextGap
  of NSAtBottom:
    result.origin.y = 0.0
  of NSBelowBottom:
    result.origin.y = 0.0
  else:
    discard

proc boxDrawTitleWithFrame(self: NSBox, frame: NSRect, view: NSView) =
  discard view
  if not boxHasVisibleTitle(self):
    return
  discard frame
  # Title text is currently rendered by the FigDraw text pass in rendering.nim.

proc boxDrawBorderAndTitle(self: NSBox, rect: NSRect, view: NSView) =
  if self.isNil or self.isTransparent():
    return

  let grooveRect = boxGrooveRect(self)
  if grooveRect.size.width <= 0.0 or grooveRect.size.height <= 0.0:
    return

  if self.xBoxType != NSBoxSeparator:
    NSColor.controlColor().setFill()
    NSRectFill(grooveRect)

  if self.xBoxType == NSBoxCustom:
    self.xFillColor.setFill()
    NSRectFill(rect)
    if self.xBorderType != NSNoBorder.int:
      self.xBorderColor.setStroke()
      NSFrameRectWithWidth(self.bounds(), self.xBorderWidth)
  elif self.xBoxType == NSBoxSeparator:
    NSColor.grayColor().setFill()
    if grooveRect.size.width > grooveRect.size.height:
      let y = grooveRect.origin.y + floor(grooveRect.size.height * 0.5)
      NSRectFill(nsRect(grooveRect.origin.x, y, grooveRect.size.width, 1.0))
    else:
      let x = grooveRect.origin.x + floor(grooveRect.size.width * 0.5)
      NSRectFill(nsRect(x, grooveRect.origin.y, 1.0, grooveRect.size.height))
  else:
    case self.xBorderType
    of NSNoBorder.int:
      discard
    of NSLineBorder.int:
      NSColor.blackColor().setStroke()
      NSFrameRect(grooveRect)
    of NSBezelBorder.int:
      NSDrawGrayBezel(grooveRect, rect)
    of NSGrooveBorder.int:
      NSDrawGroove(grooveRect, rect)
    else:
      discard

  if boxHasVisibleTitle(self):
    boxDrawTitleWithFrame(self, boxTitleRect(self), view)

objcImpl:
  method hasVisibleTitle*(self: NSBox): bool =
    boxHasVisibleTitle(self)

  method titleHeight*(self: NSBox): float32 =
    boxTitleHeight(self)

  method grooveRect*(self: NSBox): NSRect =
    boxGrooveRect(self)

  method contentRect*(self: NSBox): NSRect =
    boxContentRect(self)

  method updateContentViewFrame*(self: NSBox) =
    boxUpdateContentViewFrame(self)

  method init*(self: var NSBox): NSBox =
    result = asTypeRaw[NSBox](callSuperIdFrom(NSBox, self, getSelector("init")))
    if result.isNil:
      return
    result.xBoxType = NSBoxPrimary
    result.xBorderType = NSLineBorder.int
    result.xTitlePosition = NSAboveTop
    result.xTransparent = true
    result.xContentMargins = nsSize(0.0, 0.0)
    result.xTitle = @ns""
    result.xContentView = NSView(value: nil)
    result.xBorderWidth = 1.0
    result.xCornerRadius = 0.0
    result.xBorderColor = nsColor(0.0, 0.0, 0.0, 0.42)
    result.xFillColor = nsColor(0.0, 0.0, 0.0, 0.0)
    result.xTitleFont = NSFont.userFontOfSize(0.0)

    var contentAlloc = NSView.alloc()
    var content = contentAlloc.initWithFrame(
      0.0'f32, 0.0'f32, result.bounds().size.width, result.bounds().size.height
    )
    contentAlloc.value = nil
    if not content.isNil:
      var children = result.viewSubviews()
      children.add(content)
      result.viewSubviews = children
      content.viewSuperview = retain(asRetainedType[NSView](result))
      content.setNextResponder(asRetainedType[NSResponder](result))
      result.xContentView = retain(content)
      boxUpdateContentViewFrame(result)
    content.value = nil

  method setBoxType*(self: NSBox, value: int) =
    if self.isNil:
      return
    self.xBoxType = value
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method setBorderType*(self: NSBox, value: int) =
    if self.isNil:
      return
    self.xBorderType = value
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method setTitle*(self: NSBox, value: NSString) =
    if self.isNil:
      return
    self.xTitle =
      if value.isNil:
        @ns""
      else:
        value
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method setTitleFont*(self: NSBox, font: NSFont) =
    if self.isNil:
      return
    self.xTitleFont = font
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method setContentViewMargins*(self: NSBox, value: NSSize) =
    if self.isNil:
      return
    self.xContentMargins = nsSize(max(value.width, 0.0), max(value.height, 0.0))
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method setTitlePosition*(self: NSBox, value: int) =
    if self.isNil:
      return
    self.xTitlePosition = value
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method setTransparent*(self: NSBox, value: bool) =
    if self.isNil:
      return
    self.xTransparent = value
    self.setNeedsDisplay(true)

  method setBorderWidth*(self: NSBox, value: float32) =
    if self.isNil:
      return
    self.xBorderWidth = max(value, 0.0)
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method setCornerRadius*(self: NSBox, value: float32) =
    if self.isNil:
      return
    self.xCornerRadius = max(value, 0.0)
    self.setNeedsDisplay(true)

  method setBorderColor*(self: NSBox, value: NSColor) =
    if self.isNil:
      return
    self.xBorderColor = value
    self.setNeedsDisplay(true)

  method setFillColor*(self: NSBox, value: NSColor) =
    if self.isNil:
      return
    self.xFillColor = value
    self.setNeedsDisplay(true)

  method setTitleWithMnemonic*(self: NSBox, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method contentView*(self: NSBox): NSView =
    if self.xContentView.isNil:
      return NSView(value: nil)
    retain(self.xContentView)

  method setContentView*(self: NSBox, view: NSView) =
    if self.isNil:
      return
    if self.xContentView.value == view.value:
      boxUpdateContentViewFrame(self)
      return

    if not self.xContentView.isNil:
      clearSuperviewRef(self.xContentView.value)
      var children = self.viewSubviews()
      for i, candidate in children:
        if candidate.value == self.xContentView.value:
          children.del(i)
          self.viewSubviews = children
          break

    if view.isNil:
      self.xContentView = NSView(value: nil)
      return

    let parent = view.viewSuperview()
    if not parent.isNil:
      var siblings = parent.viewSubviews()
      for i, candidate in siblings:
        if candidate.value == view.value:
          siblings.del(i)
          parent.viewSubviews = siblings
          break
      view.viewSuperview = NSView(value: nil)

    var children = self.viewSubviews()
    if view notin children:
      children.add(view)
      self.viewSubviews = children
    view.viewSuperview = retain(asRetainedType[NSView](self))
    view.setNextResponder(asRetainedType[NSResponder](self))
    self.xContentView = retain(view)
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method titleRect*(self: NSBox): NSRect =
    boxTitleRect(self)

  method borderRect*(self: NSBox): NSRect =
    if self.isNil:
      return nsRect(0.0, 0.0, 0.0, 0.0)
    boxGrooveRect(self)

  method titleCell*(self: NSBox): NSObject =
    discard self
    NSObject(value: nil)

  method setFrameFromContentFrame*(self: NSBox, content: NSRect) =
    self.setFrame(
      content.origin.x, content.origin.y, content.size.width, content.size.height
    )

  method sizeToFit*(self: NSBox) =
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method drawTitleWithFrame*(
      self: NSBox, frame: NSRect, view {.kw("inView").}: NSView
  ) =
    boxDrawTitleWithFrame(self, frame, view)

  method drawBorderAndTitleWithFrame*(
      self: NSBox, frame: NSRect, view {.kw("inView").}: NSView
  ) =
    boxDrawBorderAndTitle(self, frame, view)

  method drawRect*(self: NSBox, rect: NSRect) =
    let boxView = ownFromId[NSView](self.value)
    boxDrawBorderAndTitle(self, rect, boxView)

  method setFrame*(
      self: NSBox,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    let boundsOrigin = self.bounds().origin
    let nextWidth = max(width.float32, 0.0)
    let nextHeight = max(height.float32, 0.0)
    self.viewFrame = nsRect(x.float32, y.float32, nextWidth, nextHeight)
    self.viewBounds = nsRect(boundsOrigin.x, boundsOrigin.y, nextWidth, nextHeight)
    boxUpdateContentViewFrame(self)
    self.setNeedsDisplay(true)

  method updateCell*(self: NSBox, cell: NSCell) =
    discard cell
    self.setNeedsDisplay(true)

  method dealloc(self: NSBox) {.used.} =
    self.xContentView = NSView(value: nil)
    self.xTitle = NSString(value: nil)
    self.xBorderColor = nsColor(0.0, 0.0, 0.0, 0.0)
    self.xFillColor = nsColor(0.0, 0.0, 0.0, 0.0)
    self.xTitleFont = NSFont(value: nil)
    discard callSuperIdFrom(NSBox, self, getSelector("dealloc"))

proc new*(t: typedesc[NSBox]): NSBox =
  var allocated = NSBox.alloc()
  result = initOwned(move(allocated))
