import std/[math, parseutils, strutils]

import ./runtime
import ./valueproviders
import ./graphics
import ./graphicscontexts
import ./images
import ./attributedstrings
import ./formatters

proc defaultFocusRingType*(t: typedesc[NSCell]): NSFocusRingType =
  NSFocusRingTypeExterior

proc defaultMenu*(t: typedesc[NSCell]): NSMenu =
  NSMenu(value: nil)

proc prefersTrackingUntilMouseUp*(t: typedesc[NSCell]): bool =
  false

proc sendId(obj: ID, op: SEL): ID {.inline.} =
  ID(
    value: cast[proc(self: IDPtr, op: SEL): IDPtr {.cdecl, varargs.}](objc_msgSend)(
      obj.value, op
    )
  )

proc sendId(obj: ID, op: SEL, arg0: ID): ID {.inline.} =
  ID(
    value: cast[proc(self: IDPtr, op: SEL, arg0: IDPtr): IDPtr {.cdecl, varargs.}](objc_msgSend)(
      obj.value, op, arg0.value
    )
  )

proc parseIntegerPrefix(text: string): int =
  var offset = 0
  while offset < text.len and text[offset].isSpaceAscii:
    inc offset
  var parsed = 0
  if parseInt(text, parsed, offset) > 0:
    return parsed
  0

proc parseFloatPrefix(text: string): float =
  var offset = 0
  while offset < text.len and text[offset].isSpaceAscii:
    inc offset
  var parsed = 0.0
  if parseFloat(text, parsed, offset) > 0:
    return parsed
  0.0

proc cellTypeName(cellType: NSCellType): string =
  case cellType
  of NSNullCellType:
    "NSNullCellType"
  of NSTextCellType:
    "NSTextCellType"
  of NSImageCellType:
    "NSImageCellType"
  else:
    "Unknown: " & $cellType.int

proc insetRect(rect: NSRect, dx: float32, dy: float32): NSRect {.inline.} =
  nsRect(
    rect.origin.x + dx,
    rect.origin.y + dy,
    max(rect.size.width - dx * 2.0, 0.0),
    max(rect.size.height - dy * 2.0, 0.0),
  )

proc boolState(value: int): bool {.inline.} =
  value != NSOffState

proc hasMask(value: int, mask: int): bool {.inline.} =
  (value and mask) != 0

proc scaledImageSizeInFrameSize(
    imageSize: NSSize, frameSize: NSSize, scaling: int
): NSSize {.inline.} =
  if imageSize.width <= 0.0 or imageSize.height <= 0.0:
    return nsSize(0.0, 0.0)
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

proc makeAttributedString(text: NSString): NSAttributedString =
  var allocated = NSAttributedString.alloc()
  result = allocated.initWithString(
    if text.isNil:
      @ns""
    else:
      text
  )
  allocated.value = nil

objcImpl:
  type NSCell* {.
    impl: (
      NSObjectValueProvider, NSStringValueProvider, NSIntValueProvider,
      NSIntegerValueProvider, NSFloatValueProvider, NSDoubleValueProvider,
    )
  .} = object of NSObject
    xState: int
    xFont {.set: setFont, get: font.}: NSFont
    xEntryType {.get: entryType.}: int
    xObjectValue: ID
    xImage {.get: image.}: NSImage
    xTextAlignment {.set: setAlignment, get: alignment.}: NSTextAlignment
    xWritingDirection {.set: setBaseWritingDirection, get: baseWritingDirection.}:
      NSWritingDirection
    xCellType {.get: `type`.}: NSCellType
    xFormatter {.set: setFormatter, get: formatter.}: NSFormatter
    xTitleOrAttributedTitle: ID
    xRepresentedObject: ID
    xControlSize {.set: setControlSize, get: controlSize.}: NSControlSize
    xFocusRingType {.set: setFocusRingType, get: focusRingType.}: NSFocusRingType
    xLineBreakMode {.set: setLineBreakMode, get: lineBreakMode.}: NSLineBreakMode
    xBackgroundStyle {.set: setBackgroundStyle, get: backgroundStyle.}:
      NSBackgroundStyle
    xControlView {.set: setControlView, get: controlView.}: NSView

    xEnabled {.set: setEnabled, get: isEnabled.}: bool
    xEditable {.set: setEditable, get: isEditable.}: bool
    xRichText: bool
    xSelectable {.set: setSelectable, get: isSelectable.}: bool
    xScrollable {.set: setScrollable, get: isScrollable.}: bool
    xBordered {.get: isBordered.}: bool
    xBezeled {.set: setBezeled, get: isBezeled.}: bool
    xHighlighted {.set: setHighlighted, get: isHighlighted.}: bool
    xShowsFirstResponder {.set: setShowsFirstResponder, get: showsFirstResponder.}: bool
    xRefusesFirstResponder {.set: setRefusesFirstResponder, get: refusesFirstResponder.}:
      bool
    xContinuous {.set: setContinuous, get: isContinuous.}: bool
    xAllowsMixedState {.set: setAllowsMixedState, get: allowsMixedState.}: bool
    xSendsActionOnEndEditing {.
      set: setSendsActionOnEndEditing, get: sendsActionOnEndEditing
    .}: bool
    xHasValidObjectValue {.get: hasValidObjectValue.}: bool

  method initTextCell*(self: var NSCell, string: NSString): NSCell =
    result = asTypeRaw[NSCell](callSuperIdFrom(NSCell, self, getSelector("init")))
    if result.isNil:
      return
    initIvarFields(result)

    result.xFocusRingType = NSCell.defaultFocusRingType()
    result.xObjectValue = string
    result.xCellType = NSTextCellType
    result.xEnabled = true
    result.xHasValidObjectValue = true
    result.xWritingDirection = NSWritingDirectionNatural
    result.xLineBreakMode = NSLineBreakByWordWrapping

  method initImageCell*(self: var NSCell, image: NSImage): NSCell =
    result = asTypeRaw[NSCell](callSuperIdFrom(NSCell, self, getSelector("init")))
    if result.isNil:
      return
    initIvarFields(result)

    result.xFocusRingType = NSCell.defaultFocusRingType()
    result.xImage = image
    result.xCellType = NSImageCellType
    result.xEnabled = true
    result.xHasValidObjectValue = true
    result.xLineBreakMode = NSLineBreakByWordWrapping

  method init*(self: var NSCell): NSCell =
    result = self.initImageCell(NSImage(value: nil))

  method initWithCoder*(self: var NSCell, coder: ID): NSCell =
    result = self.init()

  method encodeWithCoder*(self: NSCell, coder: ID) =
    return

  method state*(self: NSCell): int =
    if self.xAllowsMixedState:
      if self.xState < 0:
        return NSMixedState
      if self.xState > 0:
        return NSOnState
      return NSOffState
    (abs(self.xState) > 0).int

  method target*(self: NSCell): ID =
    ID(value: nil)

  method action*(self: NSCell): SEL =
    nil

  method tag*(self: NSCell): int =
    -1

  method wraps*(self: NSCell): bool =
    self.xLineBreakMode in {NSLineBreakByWordWrapping, NSLineBreakByCharWrapping}

  method title*(self: NSCell): NSString =
    self.stringValue()

  method objectValue*(self: NSCell): NSObject =
    if not self.xHasValidObjectValue or self.xObjectValue.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.xObjectValue)

  method stringValue*(self: NSCell): NSString =
    echo "NSCell:stringValue:"
    if not self.xFormatter.isNil:
      let formatted = self.xFormatter.stringForObjectValue(self.xObjectValue.NSObject)
      if not formatted.isNil:
        return formatted

    if self.xObjectValue.isNil:
      return retain(@ns"")

    let valueObj = self.xObjectValue.NSObject
    if valueObj.isKindOfClass(NSAttributedString):
      return valueObj.to(NSAttributedString).string()

    if valueObj.isKindOfClass(NSString):
      return valueObj.to(NSString)

    if valueObj.respondsLike(DescriptionValue):
      return valueObj.castWrapper(DescriptionValue).descripton()

    retain(@ns"")

  method intValue*(self: NSCell): cint =
    let valueObj = self.xObjectValue.NSObject
    if valueObj.isKindOfClass(NSAttributedString):
      return parseIntegerPrefix($self.stringValue()).cint
    if valueObj.isKindOfClass(NSString):
      return parseIntegerPrefix($ownFromId[NSString](self.xObjectValue)).cint
    let intProvider = asProto[NSIntValueProvider](self.xObjectValue)
    if intProvider.notNil:
      return intProvider.intValue()
    if (let intLike = valueObj.asWrapper(IntValue); intLike.notNil):
      return intLike.intValue().cint
    0.cint

  method floatValue*(self: NSCell): float32 =
    if self.xObjectValue.isNil:
      return 0.0
    let valueObj = self.xObjectValue.NSObject
    if valueObj.isKindOfClass(NSAttributedString) or valueObj.isKindOfClass(NSString):
      return parseFloatPrefix($self.stringValue()).float32
    let floatProvider = asProto[NSFloatValueProvider](self.xObjectValue)
    if not floatProvider.isNil:
      return floatProvider.floatValue()
    if (let fv = self.xObjectValue.asWrapper(FloatValue); not fv.isNil):
      return fv.floatValue().float32
    0.0

  method doubleValue*(self: NSCell): float =
    if self.xObjectValue.isNil:
      return 0.0
    let valueObj = self.xObjectValue.NSObject
    if valueObj.isKindOfClass(NSAttributedString) or valueObj.isKindOfClass(NSString):
      return parseFloatPrefix($self.stringValue())
    let doubleProvider = asProto[NSDoubleValueProvider](self.xObjectValue)
    if not doubleProvider.isNil:
      return doubleProvider.doubleValue()
    if (let vo = self.xObjectValue.asWrapper(DoubleValue); not vo.isNil):
      return vo.doubleValue()
    0.0

  method integerValue*(self: NSCell): int =
    let valueObj = self.xObjectValue.NSObject
    if valueObj.isKindOfClass(NSAttributedString) or valueObj.isKindOfClass(NSString):
      return parseIntegerPrefix($self.stringValue())
    let integerProvider = asProto[NSIntegerValueProvider](self.xObjectValue)
    if not integerProvider.isNil:
      return integerProvider.integerValue()
    if (let vo = valueObj.asWrapper(IntegerValue); not vo.isNil):
      return vo.integerValue()
    0

  method attributedStringValue*(self: NSCell): NSAttributedString =
    if self.xObjectValue.isNil:
      return NSAttributedString(value: nil)
    let valueObj = self.xObjectValue.NSObject
    if valueObj.isKindOfClass(NSAttributedString):
      return ownFromId[NSAttributedString](self.xObjectValue)
    NSAttributedString(value: nil)

  method representedObject*(self: NSCell): NSObject =
    if self.xRepresentedObject.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.xRepresentedObject)

  method setType*(self: NSCell, cellType: NSCellType) =
    if self.xCellType != cellType:
      self.xCellType = cellType
      if cellType == NSTextCellType:
        self.setTitle(@ns"Cell")
        self.setFont(NSFont(value: nil))

  method setState*(self: NSCell, value: int) =
    if self.xAllowsMixedState:
      if value < 0:
        self.xState = NSMixedState
      elif value > 0:
        self.xState = NSOnState
      else:
        self.xState = NSOffState
    else:
      self.xState = (abs(value) > 0).int

  method nextState*(self: NSCell): int =
    if self.xAllowsMixedState:
      let value = self.state()
      return value - (if value == NSMixedState: -2 else: 1)
    1 - self.state()

  method setNextState*(self: NSCell) =
    self.xState = self.nextState()

  method setTarget*(self: NSCell, target: ID) =
    raise newException(CatchableError, "-[NSCell setTarget:] is unimplemented")

  method setAction*(self: NSCell, action: SEL) =
    raise newException(CatchableError, "-[NSCell setAction:] is unimplemented")

  method setTag*(self: NSCell, tag: int) =
    raise newException(CatchableError, "-[NSCell setTag:] is unimplemented")

  method setEntryType*(self: NSCell, entryType: int) =
    self.xEntryType = entryType
    self.setType(NSTextCellType)

  method setImage*(self: NSCell, image: NSImage) =
    if not image.isNil:
      self.setType(NSImageCellType)
    self.xImage = image

  method setWraps*(self: NSCell, wraps: bool) =
    self.xLineBreakMode =
      if wraps: NSLineBreakByWordWrapping else: NSLineBreakByClipping

  method setTitle*(self: NSCell, title: NSString) =
    self.setStringValue(title)

  method setBordered*(self: NSCell, flag: bool) =
    self.xBordered = flag
    self.xBezeled = false

  method setFloatingPointFormat*(
      self: NSCell, fpp: bool, left {.kw("left").}: uint, right {.kw("right").}: uint
  ) =
    return

  method setObjectValue*(self: NSCell, value: NSObject) =
    let controlView = self.controlView()
    if not controlView.isNil:
      willChangeValueForKey(controlView.NSObject, "objectValue")
    self.xObjectValue = value
    self.xTitleOrAttributedTitle = value
    self.xHasValidObjectValue = true
    if not controlView.isNil:
      didChangeValueForKey(controlView.NSObject, "objectValue")

  method setStringValue*(self: NSCell, value: NSString) =
    if value.isNil:
      raise newException(CatchableError, "-[NSCell setStringValue:] value==nil")

    self.setType(NSTextCellType)

    if not self.xFormatter.isNil:
      let formatterObj = self.xFormatter.NSObject
      if formatterObj.respondsToSelector("getObjectValue:forString:errorDescription:"):
        var formatted: IDPtr = nil
        var errorDesc: IDPtr = nil
        let ok = cast[proc(
          self: IDPtr,
          op: SEL,
          objectValue: ptr IDPtr,
          stringValue: IDPtr,
          errorDescription: ptr IDPtr,
        ): bool {.cdecl, varargs.}](objc_msgSend)(
          self.xFormatter.value,
          getSelector("getObjectValue:forString:errorDescription:"),
          addr formatted,
          value.value,
          addr errorDesc,
        )
        if not ok:
          self.xHasValidObjectValue = false
          return
        self.setObjectValue(ownFromId[NSObject](formatted))
        return

    self.setObjectValue(value)

  method setIntValue*(self: NSCell, value: cint) =
    self.setObjectValue(ownFromId[NSObject](ns(value).value))

  method setFloatValue*(self: NSCell, value: float32) =
    self.setObjectValue(ownFromId[NSObject](ns(value).value))

  method setDoubleValue*(self: NSCell, value: float) =
    self.setObjectValue(ownFromId[NSObject](ns(value).value))

  method setIntegerValue*(self: NSCell, value: int) =
    self.setObjectValue(ownFromId[NSObject](ns(value).value))

  method setAttributedStringValue*(self: NSCell, value: NSAttributedString) =
    self.xObjectValue = value.NSObject
    self.xTitleOrAttributedTitle = value.NSObject
    self.xHasValidObjectValue = true

  method setRepresentedObject*(self: NSCell, representedObject: NSObject) =
    self.xRepresentedObject = representedObject

  method takeObjectValueFrom*(self: NSCell, sender: NSObject) =
    let provider = asProto[NSObjectValueProvider](sender)
    if provider.isNil:
      return
    self.setObjectValue(provider.objectValue())

  method takeStringValueFrom*(self: NSCell, sender: NSObject) =
    let provider = asProto[NSStringValueProvider](sender)
    if provider.isNil:
      return
    self.setStringValue(provider.stringValue())

  method takeIntValueFrom*(self: NSCell, sender: NSObject) =
    let provider = asProto[NSIntValueProvider](sender)
    if provider.isNil:
      return
    self.setIntValue(provider.intValue())

  method takeFloatValueFrom*(self: NSCell, sender: NSObject) =
    let provider = asProto[NSFloatValueProvider](sender)
    if provider.isNil:
      return
    self.setFloatValue(provider.floatValue())

  method takeDoubleValueFrom*(self: NSCell, sender: NSObject) =
    let provider = asProto[NSDoubleValueProvider](sender)
    if provider.isNil:
      return
    self.setDoubleValue(provider.doubleValue())

  method takeIntegerValueFrom*(self: NSCell, sender: NSObject) =
    let provider = asProto[NSIntegerValueProvider](sender)
    if provider.isNil:
      return
    self.setIntegerValue(provider.integerValue())

  method cellSize*(self: NSCell): NSSize =
    nsSize(10000, 10000)

  method cellSizeForBounds*(self: NSCell, rect: NSRect): NSSize =
    let size = self.cellSize()
    nsSize(min(rect.size.width, size.width), min(rect.size.height, size.height))

  method imageRectForBounds*(self: NSCell, rect: NSRect): NSRect =
    rect

  method titleRectForBounds*(self: NSCell, rect: NSRect): NSRect =
    rect

  method drawingRectForBounds*(self: NSCell, rect: NSRect): NSRect =
    rect

  method drawInteriorWithFrame*(
      self: NSCell, frame: NSRect, view {.kw("inView").}: NSView
  ) =
    return

  method drawWithFrame*(self: NSCell, frame: NSRect, view {.kw("inView").}: NSView) =
    if self.`type`() == NSTextCellType and self.isBezeled():
      NSDrawWhiteBezel(frame, frame)
    self.drawInteriorWithFrame(self.drawingRectForBounds(frame), view)

  method highlight*(
      self: NSCell,
      highlight: bool,
      frame {.kw("withFrame").}: NSRect,
      view {.kw("inView").}: NSView,
  ) =
    self.xHighlighted = highlight

  method startTrackingAt*(
      self: NSCell, startPoint: NSPoint, view {.kw("inView").}: NSView
  ): bool =
    true

  method continueTracking*(
      self: NSCell,
      lastPoint: NSPoint,
      currentPoint {.kw("at").}: NSPoint,
      view {.kw("inView").}: NSView,
  ): bool =
    true

  method stopTracking*(
      self: NSCell,
      lastPoint: NSPoint,
      stopPoint {.kw("at").}: NSPoint,
      view {.kw("inView").}: NSView,
      mouseIsUp {.kw("mouseIsUp").}: bool,
  ) =
    return

  method trackMouse*(
      self: NSCell,
      event: NSEvent,
      frame {.kw("inRect").}: NSRect,
      view {.kw("ofView").}: NSView,
      untilMouseUp {.kw("untilMouseUp").}: bool,
  ): bool =
    if event.isNil or view.isNil:
      return false
    if not self.startTrackingAt(nsPoint(0, 0), view):
      return false
    self.stopTracking(nsPoint(0, 0), nsPoint(0, 0), view, true)
    true

  method setUpFieldEditorAttributes*(self: NSCell, editor: NSText): NSText =
    editor

  method editWithFrame*(
      self: NSCell,
      frame: NSRect,
      view {.kw("inView").}: NSView,
      editor {.kw("editor").}: NSText,
      delegate {.kw("delegate").}: ID,
      event {.kw("event").}: NSEvent,
  ) =
    return

  method selectWithFrame*(
      self: NSCell,
      frame: NSRect,
      view {.kw("inView").}: NSView,
      editor {.kw("editor").}: NSText,
      delegate {.kw("delegate").}: ID,
      location {.kw("start").}: int,
      length {.kw("length").}: int,
  ) =
    return

  method endEditing*(self: NSCell, editor: NSText) =
    if editor.isNil:
      return
    let editorObj = editor.NSObject
    if editorObj.respondsToSelector("string"):
      self.setStringValue(ownFromId[NSString](sendId(editor, getSelector("string"))))

  method resetCursorRect*(self: NSCell, rect: NSRect, view {.kw("inView").}: NSView) =
    return

  method description*(self: NSCell): NSString =
    let details =
      "type: " & cellTypeName(self.xCellType) & ", objectValue: " & $self.stringValue()
    ns(details)

  method dealloc(self: NSCell) {.used.} =
    self.xFont = NSFont(value: nil)
    self.xObjectValue = NSObject(value: nil)
    self.xImage = NSImage(value: nil)
    self.xFormatter = NSFormatter(value: nil)
    self.xTitleOrAttributedTitle = NSObject(value: nil)
    self.xRepresentedObject = NSObject(value: nil)
    self.xControlView = NSView(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSCell, self, getSelector("dealloc"))

objcImpl:
  type NSActionCell* = object of NSCell
    xActionControlView {.set: setControlView, get: controlView.}: NSView
    xActionTarget {.set: setTarget, get: target.}: ID
    xActionSelector {.set: setAction, get: action.}: SEL
    xActionTag {.set: setTag, get: tag.}: int

  method init*(self: var NSActionCell): NSActionCell =
    result =
      asTypeRaw[NSActionCell](callSuperIdFrom(NSActionCell, self, getSelector("init")))
    if result.isNil:
      return
    result.setEnabled(true)
    result.xActionControlView = NSView(value: nil)
    result.xActionTarget.value = nil
    result.xActionSelector = nil
    result.xActionTag = -1

  method dealloc(self: NSActionCell) {.used.} =
    self.xActionControlView = NSView(value: nil)
    self.xActionTarget.value = nil
    discard callSuperIdFrom(NSActionCell, self, getSelector("dealloc"))

objcImpl:
  type NSButtonCell* = object of NSActionCell
    xButtonTitle {.get: title.}: NSString
    xAlternateTitle {.set: setAlternateTitle, get: alternateTitle.}: NSString
    xAlternateImage {.set: setAlternateImage, get: alternateImage.}: NSImage
    xTransparent {.set: setTransparent, get: isTransparent.}: bool
    xKeyEquivalent {.set: setKeyEquivalent, get: keyEquivalent.}: NSString
    xImagePosition {.set: setImagePosition, get: imagePosition.}: int
    xHighlightsByMask {.set: setHighlightsBy, get: highlightsBy.}: int
    xShowsStateByMask {.set: setShowsStateBy, get: showsStateBy.}: int
    xImageDimsWhenDisabled {.set: setImageDimsWhenDisabled, get: imageDimsWhenDisabled.}:
      bool
    xKeyEquivalentModifierMask {.
      set: setKeyEquivalentModifierMask, get: keyEquivalentModifierMask
    .}: int
    xBezelStyle {.set: setBezelStyle, get: bezelStyle.}: int
    xShowsBorderOnlyWhileMouseInside {.
      set: setShowsBorderOnlyWhileMouseInside, get: showsBorderOnlyWhileMouseInside
    .}: bool
    xGradientType {.set: setGradientType, get: gradientType.}: int
    xImageScaling {.set: setImageScaling, get: imageScaling.}: int
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
    result.xHighlightsByMask = NSPushInCellMask
    result.xShowsStateByMask = NSNoCellMask
    result.xImageDimsWhenDisabled = true
    result.xGradientType = NSGradientNone
    result.xImageScaling = NSImageScaleProportionallyDown
    result.xBezelStyle = NSRoundedBezelStyle.int
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
      self.xHighlightsByMask = NSChangeBackgroundCellMask
      self.xShowsStateByMask = NSNoCellMask
      self.xImageDimsWhenDisabled = true
    of NSMomentaryPushInButton:
      self.xHighlightsByMask = NSPushInCellMask or NSChangeGrayCellMask
      self.xShowsStateByMask = NSNoCellMask
      self.xImageDimsWhenDisabled = true
    of NSMomentaryChangeButton:
      self.xHighlightsByMask = NSContentsCellMask
      self.xShowsStateByMask = NSNoCellMask
      self.xImageDimsWhenDisabled = true
    of NSPushOnPushOffButton:
      self.xHighlightsByMask = NSPushInCellMask or NSChangeGrayCellMask
      self.xShowsStateByMask = NSChangeBackgroundCellMask
      self.xImageDimsWhenDisabled = true
    of NSOnOffButton:
      self.xHighlightsByMask = NSChangeBackgroundCellMask or NSChangeGrayCellMask
      self.xShowsStateByMask = NSChangeBackgroundCellMask or NSChangeGrayCellMask
      self.xImageDimsWhenDisabled = true
    of NSToggleButton:
      self.xHighlightsByMask = NSPushInCellMask or NSContentsCellMask
      self.xShowsStateByMask = NSContentsCellMask
      self.xImageDimsWhenDisabled = true
    of NSSwitchButton, NSRadioButton:
      self.xHighlightsByMask = NSContentsCellMask
      self.xShowsStateByMask = NSContentsCellMask
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

  method setState*(self: NSButtonCell, value: int) =
    self.xState = normalizeButtonState(value, self.allowsMixedState())

  method attributedTitle*(self: NSButtonCell): NSAttributedString =
    makeAttributedString(self.title())

  method attributedAlternateTitle*(self: NSButtonCell): NSAttributedString =
    makeAttributedString(self.alternateTitle())

  method titleForHighlight*(self: NSButtonCell): NSAttributedString =
    if (
      (hasMask(self.highlightsBy(), NSContentsCellMask) and self.isHighlighted()) or
      (hasMask(self.showsStateBy(), NSContentsCellMask) and boolState(self.state()))
    ):
      let alternate = self.attributedAlternateTitle()
      if not alternate.isNil and self.alternateTitle().len > 0:
        return alternate
    self.attributedTitle()

  method imageForHighlight*(self: NSButtonCell): NSImage =
    if self.bezelStyle() == NSDisclosureBezelStyle.int:
      if hasMask(self.highlightsBy(), NSContentsCellMask) and self.isHighlighted():
        return NSImage.imageNamed(@ns"NSButtonCell_disclosure_highlighted")
      elif boolState(self.state()):
        return NSImage.imageNamed(@ns"NSButtonCell_disclosure_selected")
      return NSImage.imageNamed(@ns"NSButtonCell_disclosure_normal")

    if (
      (hasMask(self.highlightsBy(), NSContentsCellMask) and self.isHighlighted()) or
      (hasMask(self.showsStateBy(), NSContentsCellMask) and boolState(self.state()))
    ):
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
    (hasMask(self.highlightsBy(), NSChangeGrayCellMask) and self.isHighlighted()) or
      (hasMask(self.showsStateBy(), NSChangeGrayCellMask) and boolState(self.state()))

  method getControlSizeAdjustment*(self: NSButtonCell, flipped: bool): NSRect =
    result = nsRect(0.0, 0.0, 0.0, 0.0)
    if (
      self.bezelStyle() == NSRoundedBezelStyle.int and
      hasMask(self.highlightsBy(), NSPushInCellMask) and
      hasMask(self.highlightsBy(), NSChangeGrayCellMask) and
      self.showsStateBy() == NSNoCellMask
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
    of NSDisclosureBezelStyle.int:
      discard
    of NSRegularSquareBezelStyle.int:
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
        hasMask(self.highlightsBy(), NSPushInCellMask) and self.isHighlighted()
      let topGray = if highlighted: 0.80 else: 0.90
      let bottomGray = if highlighted: 0.70 else: 0.80
      setCurrentFillColor(nsColor(topGray, topGray, topGray, 1.0))
      NSRectFill(top)
      setCurrentFillColor(nsColor(bottomGray, bottomGray, bottomGray, 1.0))
      NSRectFill(bottom)
      setCurrentStrokeColor(nsColor(0.83, 0.83, 0.83, 1.0))
      NSFrameRectWithWidth(drawFrame, 1.0)
    of NSTexturedSquareBezelStyle.int, NSTexturedRoundedBezelStyle.int,
        NSShadowlessSquareBezelStyle.int:
      if not self.isBordered():
        return
      let highlighted = self.isHighlighted()
      let pressed =
        boolState(self.state()) and
        hasMask(self.showsStateBy(), NSChangeBackgroundCellMask)
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
    of NSRecessedBezelStyle.int:
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
        if hasMask(self.highlightsBy(), NSPushInCellMask) and self.isHighlighted():
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
    if self.bezelStyle() == NSDisclosureBezelStyle.int:
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
      self.bezelStyle() in
      [NSTexturedSquareBezelStyle.int, NSTexturedRoundedBezelStyle.int]
    if self.isBordered() and (not isTextured) and
        hasMask(self.highlightsBy(), NSPushInCellMask) and self.isHighlighted():
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
    self.state()

  method floatValue*(self: NSButtonCell): float32 =
    self.state().float32

  method doubleValue*(self: NSButtonCell): float =
    self.state().float

  method setIntValue*(self: NSButtonCell, value: cint) =
    self.setState(value.int)

  method setIntegerValue*(self: NSButtonCell, value: int) =
    self.setState(value)

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
    discard
      performResponderSelector(target, action, self.NSObject)

  method dealloc(self: NSButtonCell) {.used.} =
    self.xButtonTitle = NSString(value: nil)
    self.xAlternateTitle = NSString(value: nil)
    self.xAlternateImage = NSImage(value: nil)
    self.xKeyEquivalent = NSString(value: nil)
    discard callSuperIdFrom(NSButtonCell, self, getSelector("dealloc"))

proc NSDrawThreePartImage*(
    frame: NSRect,
    startCap: NSImage,
    centerFill: NSImage,
    endCap: NSImage,
    vertical: bool,
    operation: int,
    alpha: float32,
    flipped: bool,
) =
  return

proc new*(t: typedesc[NSCell]): NSCell =
  var allocated = NSCell.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSActionCell]): NSActionCell =
  var allocated = NSActionCell.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSButtonCell]): NSButtonCell =
  var allocated = NSButtonCell.alloc()
  result = initOwned(move(allocated))
