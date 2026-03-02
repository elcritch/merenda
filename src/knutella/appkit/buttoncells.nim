import std/[math, parseutils, strutils]

import ./runtime
import ./valueproviders
import ./graphics
import ./graphicscontexts
import ./images
import ./attributedstrings
import ./formatters
import ./cells

objcImpl:

  type NSButtonCell* = object of NSActionCell
    xButtonTitle {.get: title.}: NSString
    xAlternateTitle {.set: setAlternateTitle, get: alternateTitle.}: NSString
    xAlternateImage {.set: setAlternateImage, get: alternateImage.}: NSImage
    xTransparent {.set: setTransparent, get: isTransparent.}: bool
    xKeyEquivalent {.set: setKeyEquivalent, get: keyEquivalent.}: NSString
    xImagePosition {.set: setImagePosition, get: imagePosition.}: NSCellImagePosition
    xHighlightsByMask {.set: setHighlightsBy, get: highlightsBy.}: set[NSCellMask]
    xShowsStateByMask {.set: setShowsStateBy, get: showsStateBy.}: set[NSCellMask]
    xImageDimsWhenDisabled {.set: setImageDimsWhenDisabled, get: imageDimsWhenDisabled.}:
      bool
    xKeyEquivalentModifierMask {.
      set: setKeyEquivalentModifierMask, get: keyEquivalentModifierMask
    .}: int
    xBezelStyle {.set: setBezelStyle, get: bezelStyle.}: NSBezelStyle
    xShowsBorderOnlyWhileMouseInside {.
      set: setShowsBorderOnlyWhileMouseInside, get: showsBorderOnlyWhileMouseInside
    .}: bool
    xGradientType {.set: setGradientType, get: gradientType.}: set[NSGradientType]
    xImageScaling {.set: setImageScaling, get: imageScaling.}: NSImageScaling
    xBackgroundColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    xPeriodicDelaySec: float32
    xPeriodicIntervalSec: float32

  method init*(self: var NSButtonCell): NSButtonCell =
    result =
      asTypeRaw[NSButtonCell](callSuperIdFrom(NSButtonCell, self, getSelector("init")))
    if result.isNil:
      return
    result.setEnabled(true)
    result.setAllowsMixedState(false)
    result.xButtonTitle = @ns"Button"
    result.xAlternateTitle = @ns""
    result.xAlternateImage = NSImage(value: nil)
    result.xKeyEquivalent = @ns""
    result.xImagePosition = NSNoImage
    result.xHighlightsByMask = {NSPushInCell}
    result.xShowsStateByMask = {}
    result.xImageDimsWhenDisabled = true
    result.xGradientType = {}
    result.xImageScaling = NSImageScaleProportionallyDown
    result.xBezelStyle = NSRoundedBezelStyle
    result.xBackgroundColor = nsColor(0.0, 0.0, 0.0, 0.0)
    result.setBordered(true)
    result.setBezeled(true)
    result.setAlignment(NSCenterTextAlignment)
    result.setObjectValue(result.xButtonTitle.NSObject)

  method setTitle*(self: NSButtonCell, value: NSString) =
    self.xButtonTitle = value
    self.xObjectValue = value.NSObject
    self.xTitleOrAttributedTitle = value.NSObject
    self.xHasValidObjectValue = true

  method setButtonType*(self: NSButtonCell, buttonType: cint) =
    case buttonType.int
    of NSMomentaryLightButton:
      self.xHighlightsByMask = {NSChangeBackgroundCell}
      self.xShowsStateByMask = {}
      self.xImageDimsWhenDisabled = true
    of NSMomentaryPushInButton:
      self.xHighlightsByMask = {NSPushInCell, NSChangeGrayCell}
      self.xShowsStateByMask = {}
      self.xImageDimsWhenDisabled = true
    of NSMomentaryChangeButton:
      self.xHighlightsByMask = {NSContentsCell}
      self.xShowsStateByMask = NSNoCellMask
      self.xImageDimsWhenDisabled = true
    of NSPushOnPushOffButton:
      self.xHighlightsByMask = {NSPushInCell, NSChangeGrayCell}
      self.xShowsStateByMask = {NSChangeBackgroundCell}
      self.xImageDimsWhenDisabled = true
    of NSOnOffButton:
      self.xHighlightsByMask = {NSChangeBackgroundCell, NSChangeGrayCell}
      self.xShowsStateByMask = {NSChangeBackgroundCell, NSChangeGrayCell}
      self.xImageDimsWhenDisabled = true
    of NSToggleButton:
      self.xHighlightsByMask = {NSPushInCell, NSContentsCell}
      self.xShowsStateByMask = {NSContentsCell}
      self.xImageDimsWhenDisabled = true
    of NSSwitchButton, NSRadioButton:
      self.xHighlightsByMask = {NSContentsCell}
      self.xShowsStateByMask = {NSContentsCell}
      self.xImagePosition = NSImageLeft
      self.xImageDimsWhenDisabled = false
      self.setBordered(false)
      self.setBezeled(false)
      self.setAlignment(NSLeftTextAlignment)
    else:
      discard

  method setPeriodicDelay*(
      self: NSButtonCell, delay: float32, interval {.kw("interval").}: float32
  ) =
    self.xPeriodicDelaySec = max(delay, 0.0)
    self.xPeriodicIntervalSec = max(interval, 0.0)

  method getPeriodicDelay*(
      self: NSButtonCell, delay: ptr float32, interval {.kw("interval").}: ptr float32
  ) =
    if not delay.isNil:
      delay[] = self.xPeriodicDelaySec
    if not interval.isNil:
      interval[] = self.xPeriodicIntervalSec

  method setState*(self: NSButtonCell, value: NSCellState) =
    self.xState = normalizeButtonState(value, self.allowsMixedState())

  method attributedTitle*(self: NSButtonCell): NSAttributedString =
    makeAttributedString(self.title())

  method attributedAlternateTitle*(self: NSButtonCell): NSAttributedString =
    makeAttributedString(self.alternateTitle())

  method titleForHighlight*(self: NSButtonCell): NSAttributedString =
    if (self.highlightsBy().contains(NSContentsCell) and self.isHighlighted()) or
       (self.showsStateBy().contains(NSContentsCell) and boolState(self.state())):
      let alternate = self.attributedAlternateTitle()
      if not alternate.isNil and self.alternateTitle().len > 0:
        return alternate
    self.attributedTitle()

  method imageForHighlight*(self: NSButtonCell): NSImage =
    if self.bezelStyle() == NSDisclosureBezelStyle:
      if self.highlightsBy().contains(NSContentsCell) and self.isHighlighted():
        return NSImage.imageNamed(@ns"NSButtonCell_disclosure_highlighted")
      elif boolState(self.state()):
        return NSImage.imageNamed(@ns"NSButtonCell_disclosure_selected")
      return NSImage.imageNamed(@ns"NSButtonCell_disclosure_normal")

    if (self.highlightsBy().contains(NSContentsCell) and self.isHighlighted()) or
       (self.showsStateBy().contains(NSContentsCell) and boolState(self.state())):
      let alternate = self.alternateImage()
      if not alternate.isNil:
        return alternate
    self.image()

  method imageRectForBounds*(self: NSButtonCell, rect: NSRect): NSRect =
    let image = self.imageForHighlight()
    if image.isNil:
      return nsRect(rect.origin.x, rect.origin.y, 0.0, 0.0)
    let imageSize = image.size()
    nsRect(rect.origin.x, rect.origin.y, imageSize.width, imageSize.height)

  method isVisuallyHighlighted*(self: NSButtonCell): bool =
    (self.highlightsBy().contains(NSChangeGrayCell) and self.isHighlighted()) or
      (self.showsStateBy().contains(NSChangeGrayCell)) and boolState(self.state())

  method getControlSizeAdjustment*(self: NSButtonCell, flipped: bool): NSRect =
    result = nsRect(0.0, 0.0, 0.0, 0.0)
    if (
      self.bezelStyle() == NSRoundedBezelStyle and
      self.highlightsBy().contains(NSPushInCell) and
      self.highlightsBy().contains(NSChangeGrayCell) and
      self.showsStateBy() == {}
    ):
      let controlSize = self.controlSize().int
      if self.controlSize() != NSMiniControlSize:
        result.size.width = (10 - controlSize * 2).float32
        result.size.height = (10 - controlSize * 2).float32
        result.origin.x = (5 - controlSize).float32
        result.origin.y = (
          if flipped:
            controlSize * 2 - 3
          else:
            7 - controlSize * 2
        ).float32

  method titleRectForBounds*(self: NSButtonCell, rect: NSRect): NSRect =
    if self.isBordered() or self.isBezeled():
      return insetRect(rect, 4.0, 2.0)
    nsRect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)

  method drawBezelWithFrame*(
      self: NSButtonCell, frame: NSRect, controlView {.kw("inView").}: NSView
  ) =
    if controlView.isNil:
      return
    let contextFlipped =
      if NSGraphicsContext.currentContext().isNil:
        false
      else:
        NSGraphicsContext.currentContext().isFlipped()
    let adjustment = self.getControlSizeAdjustment(contextFlipped)
    var drawFrame = frame
    drawFrame.size.width = max(drawFrame.size.width - adjustment.size.width, 0.0)
    drawFrame.size.height = max(drawFrame.size.height - adjustment.size.height, 0.0)
    drawFrame.origin.x += adjustment.origin.x
    drawFrame.origin.y += adjustment.origin.y

    if self.isTransparent():
      return

    case self.bezelStyle()
    of NSDisclosureBezelStyle:
      discard
    of NSRegularSquareBezelStyle:
      if not self.isBordered():
        return
      var top = drawFrame
      var bottom = drawFrame
      top.size.height = floor(drawFrame.size.height * 0.5)
      bottom.size.height = drawFrame.size.height - top.size.height
      let flipped =
        if NSGraphicsContext.currentContext().isNil:
          false
        else:
          NSGraphicsContext.currentContext().isFlipped()
      if not flipped:
        top.origin.y += bottom.size.height
      else:
        bottom.origin.y += top.size.height
      let highlighted =
        self.highlightsBy().contains(NSPushInCell) and self.isHighlighted()
      let topGray = if highlighted: 0.80 else: 0.90
      let bottomGray = if highlighted: 0.70 else: 0.80
      setCurrentFillColor(nsColor(topGray, topGray, topGray, 1.0))
      NSRectFill(top)
      setCurrentFillColor(nsColor(bottomGray, bottomGray, bottomGray, 1.0))
      NSRectFill(bottom)
      setCurrentStrokeColor(nsColor(0.83, 0.83, 0.83, 1.0))
      NSFrameRectWithWidth(drawFrame, 1.0)
    of NSTexturedSquareBezelStyle, NSTexturedRoundedBezelStyle,
        NSShadowlessSquareBezelStyle:
      if not self.isBordered():
        return
      let highlighted = self.isHighlighted()
      let pressed =
        boolState(self.state()) and
        self.showsStateBy().contains(NSChangeBackgroundCell)
      let topGray = if pressed: 0.40 else: 0.98
      let bottomGray = if pressed: 0.30 else: 0.76
      var topHalf = drawFrame
      var bottomHalf = drawFrame
      topHalf.size.height = floor(drawFrame.size.height * 0.5)
      bottomHalf.size.height = drawFrame.size.height - topHalf.size.height
      if contextFlipped:
        bottomHalf.origin.y += topHalf.size.height
      else:
        topHalf.origin.y += bottomHalf.size.height
      setCurrentFillColor(nsColor(topGray, topGray, topGray, 1.0))
      NSRectFill(topHalf)
      setCurrentFillColor(nsColor(bottomGray, bottomGray, bottomGray, 1.0))
      NSRectFill(bottomHalf)
      setCurrentStrokeColor(nsColor(0.4, 0.4, 0.4, 1.0))
      NSFrameRectWithWidth(drawFrame, 1.0)
      if highlighted:
        setCurrentFillColor(nsColor(0.0, 0.0, 0.0, 0.15))
        NSRectFill(insetRect(drawFrame, 1.0, 1.0))
    of NSRecessedBezelStyle:
      if self.isBordered() and self.isVisuallyHighlighted():
        var recessed = drawFrame
        recessed.size.height = max(recessed.size.height - 1.0, 0.0)
        if contextFlipped:
          recessed.origin.y += 1.0
        setCurrentFillColor(nsColor(0.83, 0.83, 0.83, 1.0))
        NSDrawWhiteBezel(recessed, recessed)
        if contextFlipped:
          recessed.origin.y -= 1.0
        else:
          recessed.origin.y += 1.0
        setCurrentFillColor(nsColor(0.33, 0.33, 0.33, 1.0))
        NSDrawGrayBezel(recessed, recessed)
    else:
      if not self.isBordered():
        if self.isVisuallyHighlighted():
          setCurrentFillColor(nsColor(1.0, 1.0, 1.0, 1.0))
          NSRectFill(drawFrame)
      else:
        if self.highlightsBy().contains(NSPushInCell) and self.isHighlighted():
          NSDrawGrayBezel(drawFrame, drawFrame)
        elif self.isVisuallyHighlighted():
          NSDrawGrayBezel(drawFrame, drawFrame)
        else:
          NSDrawButton(drawFrame, drawFrame)

  method drawImage*(
      self: NSButtonCell,
      image: NSImage,
      frame {.kw("withFrame").}: NSRect,
      controlView {.kw("inView").}: NSView,
  ) =
    discard self
    discard controlView
    if image.isNil:
      return
    image.drawInRect(frame, nsRect(0.0, 0.0, 0.0, 0.0), NSCompositeSourceOver.int, 1.0)

  method drawTitle*(
      self: NSButtonCell,
      title: NSAttributedString,
      titleRect {.kw("withFrame").}: NSRect,
      controlView {.kw("inView").}: NSView,
  ): NSRect =
    discard self
    discard controlView
    if not title.isNil:
      title.drawInRect(titleRect)
    titleRect

  method drawInteriorWithFrame*(
      self: NSButtonCell, frame: NSRect, controlView {.kw("inView").}: NSView
  ) =
    if controlView.isNil:
      return
    if self.isTransparent():
      return
    var contentFrame = frame
    let adjustment = self.getControlSizeAdjustment(false)
    contentFrame.size.width = max(contentFrame.size.width - adjustment.size.width, 0.0)
    contentFrame.size.height =
      max(contentFrame.size.height - adjustment.size.height, 0.0)
    contentFrame.origin.x += adjustment.origin.x
    contentFrame.origin.y += adjustment.origin.y
    if self.isBordered():
      contentFrame = insetRect(contentFrame, 2.0, 2.0)

    let image = self.imageForHighlight()
    let title = self.titleForHighlight()
    var imagePosition = self.imagePosition()
    if self.bezelStyle() == NSDisclosureBezelStyle:
      imagePosition = NSImageOnly
    var imageRect = self.imageRectForBounds(contentFrame)
    var titleRect = self.titleRectForBounds(contentFrame)

    var drawImage = not image.isNil
    var drawTitle = (not title.isNil) and self.title().len > 0

    let imageSize =
      if drawImage:
        scaledImageSizeInFrameSize(
          imageRect.size, contentFrame.size, self.imageScaling()
        )
      else:
        nsSize(0.0, 0.0)
    imageRect.size = imageSize
    imageRect.origin.x += floor((contentFrame.size.width - imageRect.size.width) * 0.5)
    imageRect.origin.y += floor(
      (contentFrame.size.height - imageRect.size.height) * 0.5
    )
    let titleSize =
      if drawTitle:
        title.size()
      else:
        nsSize(0.0, 0.0)
    titleRect.origin.y += floor((titleRect.size.height - titleSize.height) * 0.5)
    titleRect.size.height = titleSize.height

    case imagePosition
    of NSNoImage:
      drawImage = false
    of NSImageOnly:
      drawTitle = false
      imageRect.origin.x =
        contentFrame.origin.x + (contentFrame.size.width - imageRect.size.width) * 0.5
      imageRect.origin.y =
        contentFrame.origin.y + (contentFrame.size.height - imageRect.size.height) * 0.5
    of NSImageLeft:
      imageRect.origin.x = contentFrame.origin.x + 2.0
      imageRect.origin.y =
        contentFrame.origin.y + (contentFrame.size.height - imageRect.size.height) * 0.5
      titleRect.origin.x = imageRect.origin.x + imageRect.size.width + 4.0
      titleRect.size.width =
        max(contentFrame.origin.x + contentFrame.size.width - titleRect.origin.x, 0.0)
    of NSImageRight:
      imageRect.origin.x =
        contentFrame.origin.x + contentFrame.size.width - imageRect.size.width - 2.0
      imageRect.origin.y =
        contentFrame.origin.y + (contentFrame.size.height - imageRect.size.height) * 0.5
      titleRect.size.width = max(imageRect.origin.x - titleRect.origin.x - 4.0, 0.0)
    of NSImageBelow:
      imageRect.origin.y = contentFrame.origin.y
      titleRect.origin.y += imageRect.size.height
      imageRect.origin.y = max(contentFrame.origin.y, imageRect.origin.y)
      titleRect.origin.y = min(
        contentFrame.origin.y + contentFrame.size.height - titleRect.size.height,
        titleRect.origin.y,
      )
    of NSImageAbove:
      imageRect.origin.y =
        contentFrame.origin.y + contentFrame.size.height - imageRect.size.height
      titleRect.origin.y -= imageRect.size.height
      imageRect.origin.y = min(
        contentFrame.origin.y + contentFrame.size.height - imageRect.size.height,
        imageRect.origin.y,
      )
      titleRect.origin.y = max(contentFrame.origin.y, titleRect.origin.y)
    of NSImageOverlaps:
      discard
    else:
      discard

    if not self.isBordered():
      if self.isVisuallyHighlighted():
        setCurrentFillColor(nsColor(1.0, 1.0, 1.0, 1.0))
        NSRectFill(contentFrame)

    let isTextured =
      self.bezelStyle() in {NSTexturedSquareBezelStyle, NSTexturedRoundedBezelStyle}
    if self.isBordered() and
        not isTextured and
        self.highlightsBy().contains(NSPushInCell) and
        self.isHighlighted():
      imageRect.origin.x += 1.0
      titleRect.origin.x += 1.0
      let flipped =
        if NSGraphicsContext.currentContext().isNil:
          false
        else:
          NSGraphicsContext.currentContext().isFlipped()
      if not flipped:
        imageRect.origin.y -= 1.0
        titleRect.origin.y -= 1.0
      else:
        imageRect.origin.y += 1.0
        titleRect.origin.y += 1.0

    if drawImage:
      self.drawImage(image, imageRect, controlView)
    if drawTitle:
      discard self.drawTitle(title, titleRect, controlView)

  method drawWithFrame*(
      self: NSButtonCell, frame: NSRect, control {.kw("inView").}: NSView
  ) =
    self.setControlView(control)
    if self.isTransparent():
      return
    self.drawBezelWithFrame(frame, control)
    self.drawInteriorWithFrame(frame, control)

  method cellSize*(self: NSButtonCell): NSSize =
    let title = self.attributedTitle()
    let image = self.image()
    let enabled = self.isEnabled() or (not self.imageDimsWhenDisabled())
    let mixed = self.state() == NSMixedState
    var imageSize = nsSize(0.0, 0.0)
    var titleSize = nsSize(0.0, 0.0)
    if not image.isNil:
      imageSize = image.size()
    if not title.isNil:
      titleSize = title.size()
    var resultSize = nsSize(0.0, 0.0)
    case self.imagePosition()
    of NSNoImage:
      resultSize = titleSize
    of NSImageOnly:
      resultSize = imageSize
    of NSImageLeft, NSImageRight:
      resultSize.width = imageSize.width + 4.0 + titleSize.width
      resultSize.height = max(imageSize.height, titleSize.height)
    of NSImageBelow, NSImageAbove:
      resultSize.width = max(imageSize.width, titleSize.width)
      resultSize.height = imageSize.height + 4.0 + titleSize.height
    of NSImageOverlaps:
      resultSize.width = max(imageSize.width, titleSize.width)
      resultSize.height = max(imageSize.height, titleSize.height)
    else:
      discard
    resultSize.width += 4.0
    if self.isBordered() or self.isBezeled():
      resultSize.width += 4.0
      resultSize.height += 4.0
    let adjustment = self.getControlSizeAdjustment(false)
    resultSize.width += adjustment.size.width
    resultSize.height += adjustment.size.height
    resultSize

  method stringValue*(self: NSButtonCell): NSString =
    self.title()

  method setStringValue*(self: NSButtonCell, value: NSString) =
    self.setTitle(value)

  method intValue*(self: NSButtonCell): cint =
    self.state().cint

  method integerValue*(self: NSButtonCell): int =
    self.state().int

  method floatValue*(self: NSButtonCell): float32 =
    self.state().float32

  method doubleValue*(self: NSButtonCell): float =
    self.state().float

  method setIntValue*(self: NSButtonCell, value: cint) =
    let val = min(value, 1).max(-1)
    self.setState(val.NSCellState)

  method setIntegerValue*(self: NSButtonCell, value: int) =
    let val = min(value, 1).max(-1)
    self.setState(value.NSCellState)

  method setFloatValue*(self: NSButtonCell, value: float32) =
    self.setState(value.int)

  method setDoubleValue*(self: NSButtonCell, value: float) =
    self.setState(value.int)

  method performClick*(self: NSButtonCell, sender: NSObject) =
    if self.isNil or not self.isEnabled():
      return
    if self.allowsMixedState():
      case self.state()
      of NSOffState:
        self.setState(NSOnState)
      of NSOnState:
        self.setState(NSMixedState)
      else:
        self.setState(NSOffState)
    else:
      if self.state() == NSOnState:
        self.setState(NSOffState)
      else:
        self.setState(NSOnState)
    let targetId = self.target()
    let action = self.action()
    if targetId.isNil or cast[pointer](action).isNil:
      return
    let target = targetId.NSObject
    discard performResponderSelector(target, action, self.NSObject)

  method dealloc(self: NSButtonCell) {.used.} =
    destroyIvarFields(self)
    discard callSuperIdFrom(NSButtonCell, self, getSelector("dealloc"))

proc new*(t: typedesc[NSButtonCell]): NSButtonCell =
  var allocated = NSButtonCell.alloc()
  result = initOwned(move(allocated))
