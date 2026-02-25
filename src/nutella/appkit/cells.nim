import std/[parseutils, strutils]

import ./runtime
import ./valueproviders

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

proc sendInt(obj: ID, op: SEL): int {.inline.} =
  cast[proc(self: IDPtr, op: SEL): int {.cdecl, varargs.}](objc_msgSend)(obj.value, op)

proc sendFloat(obj: ID, op: SEL): float32 {.inline.} =
  cast[proc(self: IDPtr, op: SEL): float32 {.cdecl, varargs.}](objc_msgSend)(
    obj.value, op
  )

proc sendDouble(obj: ID, op: SEL): cdouble {.inline.} =
  cast[proc(self: IDPtr, op: SEL): cdouble {.cdecl, varargs.}](objc_msgSend)(
    obj.value, op
  )

proc replaceOwned(slot: var ID, next: ID) {.inline.} =
  slot.value = replacedOwnedId(slot.value, next.value)

proc replaceOwned(slot: var ID, next: NSObject) {.inline.} =
  slot.value = replacedOwnedId(slot.value, next.value)

proc clearOwned(slot: var ID) {.inline.} =
  slot.value = replacedOwnedId(slot.value, nil)

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
    result = asType[NSCell](callSuperIdFrom(NSCell, self, getSelector("init")))
    if result.isNil:
      return
    initIvarFields(result)

    result.xFocusRingType = NSCell.defaultFocusRingType()
    result.xFont = NSFont(value: nil)
    result.xObjectValue.value = nil
    replaceOwned(result.xObjectValue, ID(value: string.value))
    result.xImage = NSImage(value: nil)
    result.xCellType = NSTextCellType
    result.xFormatter = NSFormatter(value: nil)
    result.xTitleOrAttributedTitle.value = nil
    result.xRepresentedObject.value = nil
    result.xControlView = NSView(value: nil)
    result.xEnabled = true
    result.xHasValidObjectValue = true
    result.xWritingDirection = NSWritingDirectionNatural
    result.xLineBreakMode = NSLineBreakByWordWrapping

  method initImageCell*(self: var NSCell, image: NSImage): NSCell =
    result = asType[NSCell](callSuperIdFrom(NSCell, self, getSelector("init")))
    if result.isNil:
      return
    initIvarFields(result)

    result.xFocusRingType = NSCell.defaultFocusRingType()
    result.xFont = NSFont(value: nil)
    result.xObjectValue.value = nil
    result.xImage = image
    result.xCellType = NSImageCellType
    result.xFormatter = NSFormatter(value: nil)
    result.xTitleOrAttributedTitle.value = nil
    result.xRepresentedObject.value = nil
    result.xControlView = NSView(value: nil)
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
    if not self.xFormatter.isNil:
      let formatter = asRetainedType[NSObject](self.xFormatter.value)
      if formatter.respondsToSelector("stringForObjectValue:"):
        let formatted = sendId(
          self.xFormatter, getSelector("stringForObjectValue:"), self.xObjectValue
        )
        if not formatted.isNil:
          return ownFromId[NSString](formatted)

    if self.xObjectValue.isNil:
      return retain(@ns"")

    let valueObj = asRetainedType[NSObject](self.xObjectValue.value)
    if valueObj.isKindOfClass(NSAttributedString):
      let strValue = sendId(self.xObjectValue, getSelector("string"))
      if not strValue.isNil:
        return ownFromId[NSString](strValue)
      return retain(@ns"")

    if valueObj.isKindOfClass(NSString):
      return ownFromId[NSString](self.xObjectValue)

    if valueObj.respondsToSelector("description"):
      let descriptionId = sendId(self.xObjectValue, getSelector("description"))
      if not descriptionId.isNil:
        return ownFromId[NSString](descriptionId)
    retain(@ns"")

  method intValue*(self: NSCell): cint =
    let valueObj = asRetainedType[NSObject](self.xObjectValue.value)
    if valueObj.isKindOfClass(NSAttributedString):
      return parseIntegerPrefix($self.stringValue()).cint
    if valueObj.isKindOfClass(NSString):
      return parseIntegerPrefix($ownFromId[NSString](self.xObjectValue)).cint
    let intProvider = asProto[NSIntValueProvider](self.xObjectValue)
    if not intProvider.isNil:
      return intProvider.intValue()
    if valueObj.respondsToSelector("intValue"):
      return sendInt(self.xObjectValue, getSelector("intValue")).cint
    0.cint

  method floatValue*(self: NSCell): float32 =
    if self.xObjectValue.isNil:
      return 0.0
    let valueObj = asRetainedType[NSObject](self.xObjectValue.value)
    if valueObj.isKindOfClass(NSAttributedString) or valueObj.isKindOfClass(NSString):
      return parseFloatPrefix($self.stringValue()).float32
    let floatProvider = asProto[NSFloatValueProvider](self.xObjectValue)
    if not floatProvider.isNil:
      return floatProvider.floatValue()
    if valueObj.respondsToSelector("floatValue"):
      return sendFloat(self.xObjectValue, getSelector("floatValue"))
    0.0

  method doubleValue*(self: NSCell): float =
    if self.xObjectValue.isNil:
      return 0.0
    let valueObj = asRetainedType[NSObject](self.xObjectValue.value)
    if valueObj.isKindOfClass(NSAttributedString) or valueObj.isKindOfClass(NSString):
      return parseFloatPrefix($self.stringValue())
    let doubleProvider = asProto[NSDoubleValueProvider](self.xObjectValue)
    if not doubleProvider.isNil:
      return doubleProvider.doubleValue()
    if valueObj.respondsToSelector("doubleValue"):
      return sendDouble(self.xObjectValue, getSelector("doubleValue")).float
    0.0

  method integerValue*(self: NSCell): int =
    let valueObj = asRetainedType[NSObject](self.xObjectValue.value)
    if valueObj.isKindOfClass(NSAttributedString) or valueObj.isKindOfClass(NSString):
      return parseIntegerPrefix($self.stringValue())
    let integerProvider = asProto[NSIntegerValueProvider](self.xObjectValue)
    if not integerProvider.isNil:
      return integerProvider.integerValue()
    if valueObj.respondsToSelector("integerValue"):
      return sendInt(self.xObjectValue, getSelector("integerValue"))
    0

  method attributedStringValue*(self: NSCell): NSAttributedString =
    if self.xObjectValue.isNil:
      return NSAttributedString(value: nil)
    let valueObj = asRetainedType[NSObject](self.xObjectValue.value)
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
      willChangeValueForKey(asRetainedType[NSObject](controlView), "objectValue")
    replaceOwned(self.xObjectValue, value)
    replaceOwned(self.xTitleOrAttributedTitle, value)
    self.xHasValidObjectValue = true
    if not controlView.isNil:
      didChangeValueForKey(asRetainedType[NSObject](controlView), "objectValue")

  method setStringValue*(self: NSCell, value: NSString) =
    if value.isNil:
      raise newException(CatchableError, "-[NSCell setStringValue:] value==nil")

    self.setType(NSTextCellType)

    if not self.xFormatter.isNil:
      let formatterObj = asRetainedType[NSObject](self.xFormatter.value)
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
    replaceOwned(self.xObjectValue, asRetainedType[NSObject](value.value))
    replaceOwned(self.xTitleOrAttributedTitle, asRetainedType[NSObject](value.value))
    self.xHasValidObjectValue = true

  method setRepresentedObject*(self: NSCell, representedObject: NSObject) =
    replaceOwned(self.xRepresentedObject, representedObject)

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
    let editorObj = asRetainedType[NSObject](editor.value)
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
    clearOwned(self.xObjectValue)
    self.xImage = NSImage(value: nil)
    self.xFormatter = NSFormatter(value: nil)
    clearOwned(self.xTitleOrAttributedTitle)
    clearOwned(self.xRepresentedObject)
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
      asType[NSActionCell](callSuperIdFrom(NSActionCell, self, getSelector("init")))
    if result.isNil:
      return
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
      asType[NSButtonCell](callSuperIdFrom(NSButtonCell, self, getSelector("init")))
    if result.isNil:
      return
    result.xButtonTitle = @ns"Button"
    result.xAlternateTitle = @ns""
    result.xKeyEquivalent = @ns""
    result.xImagePosition = NSNoImage
    result.xImageDimsWhenDisabled = true
    result.xGradientType = NSGradientNone
    result.xImageScaling = NSImageScaleProportionallyDown
    result.xBackgroundColor = nsColor(0.0, 0.0, 0.0, 0.0)
    result.setObjectValue(asRetainedType[NSObject](result.xButtonTitle))

  method setTitle*(self: NSButtonCell, value: NSString) =
    self.xButtonTitle = value
    replaceOwned(self.xObjectValue, asRetainedType[NSObject](value.value))
    replaceOwned(self.xTitleOrAttributedTitle, asRetainedType[NSObject](value.value))
    self.xHasValidObjectValue = true

  method setButtonType*(self: NSButtonCell, buttonType: cint) =
    return

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
    let target = asRetainedType[NSObject](targetId.value)
    discard
      performResponderSelector(target, action, asRetainedType[NSObject](self.value))

  method dealloc(self: NSButtonCell) {.used.} =
    self.xButtonTitle = NSString(value: nil)
    self.xAlternateTitle = NSString(value: nil)
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
