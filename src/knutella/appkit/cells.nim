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

proc insetRect*(rect: NSRect, dx: float32, dy: float32): NSRect {.inline.} =
  nsRect(
    rect.origin.x + dx,
    rect.origin.y + dy,
    max(rect.size.width - dx * 2.0, 0.0),
    max(rect.size.height - dy * 2.0, 0.0),
  )

proc boolState*(value: NSCellState): bool {.inline.} =
  value != NSOffState

proc hasMask*(value: int, mask: int): bool {.inline.} =
  (value and mask) != 0

proc scaledImageSizeInFrameSize*(
    imageSize: NSSize, frameSize: NSSize, scaling: NSImageScaling
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

proc makeAttributedString*(text: NSString): NSAttributedString =
  var allocated = NSAttributedString.alloc()
  result = allocated.initWithString(
    if text.isNil:
      @ns""
    else:
      text
  )

objcImpl:
  type NSCell* {.
    impl: (
      NSObjectValueProvider, NSStringValueProvider, NSIntValueProvider,
      NSIntegerValueProvider, NSFloatValueProvider, NSDoubleValueProvider,
    )
  .} = object of NSObject
    xState: NSCellState
    xFont {.set: setFont, get: font.}: NSFont
    xEntryType {.get: entryType.}: int
    xObjectValue: ID
    xImage {.get: image.}: NSImage
    xTextAlignment {.set: setAlignment, get: alignment.}: NSTextAlignment
    xWritingDirection {.set: setBaseWritingDirection, get: baseWritingDirection.}:
      NSWritingDirection
    xCellType {.get: cellType.}: NSCellType
    xFormatter {.set: setFormatter, get: formatter.}: NSFormatter
    xTitleOrAttributedTitle: ID
    xRepresentedObject: ID
    xControlSize {.set: setControlSize, get: controlSize.}: NSControlSize
    xFocusRingType {.set: setFocusRingType, get: focusRingType.}: NSFocusRingType
    xLineBreakMode {.set: setLineBreakMode, get: lineBreakMode.}: NSLineBreakMode
    xBackgroundStyle {.set: setBackgroundStyle, get: backgroundStyle.}:
      NSBackgroundStyle

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

  method controlView*(self: NSCell): NSView =
    return NSView(value: nil)

  method state*(self: NSCell): NSCellState =
    if self.xAllowsMixedState:
      return self.xState
    (abs(self.xState.cint)).NSCellState

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
    self.xObjectValue.NSObject

  method stringValue*(self: NSCell): NSString =
    if not self.xFormatter.isNil:
      let formatted = self.xFormatter.stringForObjectValue(self.xObjectValue.NSObject)
      if not formatted.isNil:
        return formatted

    if self.xObjectValue.isNil:
      return retain(@ns"")

    let vobj = self.xObjectValue.NSObject
    if vobj.isKindOfClass(NSAttributedString):
      return vobj.to(NSAttributedString).string()

    if vobj.isKindOfClass(NSString):
      return vobj.to(NSString)

    if vobj.isWrapper(DescriptionValue):
      return vobj.castWrapper(DescriptionValue).description()

    retain(@ns"")

  method intValue*(self: NSCell): cint =
    let vobj = self.xObjectValue.NSObject
    if vobj.isKindOfClass(NSAttributedString):
      return parseIntegerPrefix($self.stringValue()).cint
    if vobj.isKindOfClass(NSString):
      return parseIntegerPrefix($NSString(self.xObjectValue)).cint
    if vobj.isWrapper(IntValue):
      return vobj.castWrapper(IntValue).intValue().cint
    0.cint

  method floatValue*(self: NSCell): float32 =
    if self.xObjectValue.isNil:
      return 0.0
    let vobj = self.xObjectValue.NSObject
    if vobj.isKindOfClass(NSAttributedString) or vobj.isKindOfClass(NSString):
      return parseFloatPrefix($self.stringValue()).float32
    if vobj.isWrapper(FloatValue):
      return vobj.castWrapper(FloatValue).floatValue().float32
    0.0

  method doubleValue*(self: NSCell): float =
    if self.xObjectValue.isNil:
      return 0.0
    let vobj = self.xObjectValue.NSObject
    if vobj.isKindOfClass(NSAttributedString) or vobj.isKindOfClass(NSString):
      return parseFloatPrefix($self.stringValue())
    if vobj.isWrapper(DoubleValue):
      return vobj.castWrapper(DoubleValue).doubleValue()
    0.0

  method integerValue*(self: NSCell): int =
    let vobj = self.xObjectValue.NSObject
    if vobj.isKindOfClass(NSAttributedString) or vobj.isKindOfClass(NSString):
      return parseIntegerPrefix($self.stringValue())
    if vobj.isWrapper(IntegerValue):
      return vobj.castWrapper(IntegerValue).integerValue()
    0

  method attributedStringValue*(self: NSCell): NSAttributedString =
    if self.xObjectValue.isNil:
      return NSAttributedString(value: nil)
    let valueObj = self.xObjectValue.NSObject
    if valueObj.isKindOfClass(NSAttributedString):
      return self.xObjectValue.to(NSAttributedString)
    NSAttributedString(value: nil)

  method representedObject*(self: NSCell): NSObject =
    if self.xRepresentedObject.isNil:
      return NSObject(value: nil)
    return self.xRepresentedObject.NSObject

  method setType*(self: NSCell, cellType: NSCellType) =
    if self.xCellType != cellType:
      self.xCellType = cellType
      if cellType == NSTextCellType:
        self.setTitle(@ns"Cell")
        self.setFont(NSFont(value: nil))

  method setState*(self: NSCell, value: NSCellState) =
    if self.xAllowsMixedState:
      self.xState = value
    else:
      self.xState = if value == NSMixedState: NSOnState else: value

  method nextState*(self: NSCell): NSCellState =
    case self.state():
    of NSMixedState:
      if self.xAllowsMixedState:
        return NSOnState
      else:
        return NSOffState
    else:
      return self.state()

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
        self.setObjectValue(formatted.NSObject)
        return

    self.setObjectValue(value)

  method setIntValue*(self: NSCell, value: cint) =
    self.setObjectValue(ns(value).NSObject)

  method setFloatValue*(self: NSCell, value: float32) =
    self.setObjectValue(ns(value).NSObject)

  method setDoubleValue*(self: NSCell, value: float) =
    self.setObjectValue(ns(value).NSObject)

  method setIntegerValue*(self: NSCell, value: int) =
    self.setObjectValue(ns(value).NSObject)

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
      self.setStringValue(NSString(sendId(editor, getSelector("string"))))

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
    xControlView {.set: setControlView, get: controlView.}: NSView
    xTarget {.set: setTarget, get: target.}: ID
    xSelector {.set: setAction, get: action.}: SEL
    xTag {.set: setTag, get: tag.}: int

  method init*(self: var NSActionCell): NSActionCell =
    result =
      asTypeRaw[NSActionCell](callSuperIdFrom(NSActionCell, self, getSelector("init")))
    if result.isNil:
      return
    result.setEnabled(true)
    result.xActionTag = -1

  method dealloc(self: NSActionCell) {.used.} =
    destroyIvarFields(self)
    discard callSuperIdFrom(NSActionCell, self, getSelector("dealloc"))

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

