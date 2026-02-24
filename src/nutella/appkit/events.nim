import std/times

import siwin/window as siwin

import ./runtime

type NSEventType* = cint

const
  NSLeftMouseDown* = 1.NSEventType
  NSLeftMouseUp* = 2.NSEventType
  NSRightMouseDown* = 3.NSEventType
  NSRightMouseUp* = 4.NSEventType
  NSMouseMoved* = 5.NSEventType
  NSLeftMouseDragged* = 6.NSEventType
  NSRightMouseDragged* = 7.NSEventType
  NSMouseEntered* = 8.NSEventType
  NSMouseExited* = 9.NSEventType
  NSKeyDown* = 10.NSEventType
  NSKeyUp* = 11.NSEventType
  NSFlagsChanged* = 12.NSEventType
  NSPeriodic* = 13.NSEventType
  NSCursorUpdate* = 14.NSEventType
  NSPlatformSpecific* = 15.NSEventType
  NSPlatformSpecificDisplayEvent* = 16.NSEventType
  NSAppKitSystem* = 17.NSEventType
  NSScrollWheel* = 18.NSEventType
  NSApplicationDefined* = 19.NSEventType
  NSAppKitDefined* = 20.NSEventType

  NSLeftMouseDownMask* = 1'u shl NSLeftMouseDown.int
  NSLeftMouseUpMask* = 1'u shl NSLeftMouseUp.int
  NSRightMouseDownMask* = 1'u shl NSRightMouseDown.int
  NSRightMouseUpMask* = 1'u shl NSRightMouseUp.int
  NSMouseMovedMask* = 1'u shl NSMouseMoved.int
  NSLeftMouseDraggedMask* = 1'u shl NSLeftMouseDragged.int
  NSRightMouseDraggedMask* = 1'u shl NSRightMouseDragged.int
  NSMouseEnteredMask* = 1'u shl NSMouseEntered.int
  NSMouseExitedMask* = 1'u shl NSMouseExited.int
  NSKeyDownMask* = 1'u shl NSKeyDown.int
  NSKeyUpMask* = 1'u shl NSKeyUp.int
  NSFlagsChangedMask* = 1'u shl NSFlagsChanged.int
  NSPeriodicMask* = 1'u shl NSPeriodic.int
  NSCursorUpdateMask* = 1'u shl NSCursorUpdate.int
  NSScrollWheelMask* = 1'u shl NSScrollWheel.int
  NSApplicationDefinedMask* = 1'u shl NSApplicationDefined.int
  NSAppKitDefinedMask* = 1'u shl NSAppKitDefined.int
  NSAnyEventMask* = 0xffff_ffff'u
  NSPlatformSpecificDisplayMask* = 1'u shl NSPlatformSpecificDisplayEvent.int

  NSAlphaShiftKeyMask* = 1'u shl 16
  NSShiftKeyMask* = 1'u shl 17
  NSControlKeyMask* = 1'u shl 18
  NSAlternateKeyMask* = 1'u shl 19
  NSCommandKeyMask* = 1'u shl 20
  NSNumericPadKeyMask* = 1'u shl 21
  NSHelpKeyMask* = 1'u shl 22
  NSFunctionKeyMask* = 1'u shl 23
  NSDeviceIndependentModifierFlagsMask* = 0xffff_0000'u

  NSUpArrowFunctionKey* = 0xF700'u16
  NSDownArrowFunctionKey* = 0xF701'u16
  NSLeftArrowFunctionKey* = 0xF702'u16
  NSRightArrowFunctionKey* = 0xF703'u16
  NSF1FunctionKey* = 0xF704'u16
  NSF2FunctionKey* = 0xF705'u16
  NSF3FunctionKey* = 0xF706'u16
  NSF4FunctionKey* = 0xF707'u16
  NSF5FunctionKey* = 0xF708'u16
  NSF6FunctionKey* = 0xF709'u16
  NSF7FunctionKey* = 0xF70A'u16
  NSF8FunctionKey* = 0xF70B'u16
  NSF9FunctionKey* = 0xF70C'u16
  NSF10FunctionKey* = 0xF70D'u16
  NSF11FunctionKey* = 0xF70E'u16
  NSF12FunctionKey* = 0xF70F'u16
  NSF13FunctionKey* = 0xF710'u16
  NSF14FunctionKey* = 0xF711'u16
  NSF15FunctionKey* = 0xF712'u16
  NSF16FunctionKey* = 0xF713'u16
  NSF17FunctionKey* = 0xF714'u16
  NSF18FunctionKey* = 0xF715'u16
  NSF19FunctionKey* = 0xF716'u16
  NSF20FunctionKey* = 0xF717'u16
  NSF21FunctionKey* = 0xF718'u16
  NSF22FunctionKey* = 0xF719'u16
  NSF23FunctionKey* = 0xF71A'u16
  NSF24FunctionKey* = 0xF71B'u16
  NSF25FunctionKey* = 0xF71C'u16
  NSF26FunctionKey* = 0xF71D'u16
  NSF27FunctionKey* = 0xF71E'u16
  NSF28FunctionKey* = 0xF71F'u16
  NSF29FunctionKey* = 0xF720'u16
  NSF30FunctionKey* = 0xF721'u16
  NSF31FunctionKey* = 0xF722'u16
  NSF32FunctionKey* = 0xF723'u16
  NSF33FunctionKey* = 0xF724'u16
  NSF34FunctionKey* = 0xF725'u16
  NSF35FunctionKey* = 0xF726'u16
  NSInsertFunctionKey* = 0xF727'u16
  NSDeleteFunctionKey* = 0xF728'u16
  NSHomeFunctionKey* = 0xF729'u16
  NSBeginFunctionKey* = 0xF72A'u16
  NSEndFunctionKey* = 0xF72B'u16
  NSPageUpFunctionKey* = 0xF72C'u16
  NSPageDownFunctionKey* = 0xF72D'u16
  NSPrintScreenFunctionKey* = 0xF72E'u16
  NSScrollLockFunctionKey* = 0xF72F'u16
  NSPauseFunctionKey* = 0xF730'u16
  NSSysReqFunctionKey* = 0xF731'u16
  NSBreakFunctionKey* = 0xF732'u16
  NSResetFunctionKey* = 0xF733'u16
  NSStopFunctionKey* = 0xF734'u16
  NSMenuFunctionKey* = 0xF735'u16
  NSUserFunctionKey* = 0xF736'u16
  NSSystemFunctionKey* = 0xF737'u16
  NSPrintFunctionKey* = 0xF738'u16
  NSClearLineFunctionKey* = 0xF739'u16
  NSClearDisplayFunctionKey* = 0xF73A'u16
  NSInsertLineFunctionKey* = 0xF73B'u16
  NSDeleteLineFunctionKey* = 0xF73C'u16
  NSInsertCharFunctionKey* = 0xF73D'u16
  NSDeleteCharFunctionKey* = 0xF73E'u16
  NSPrevFunctionKey* = 0xF73F'u16
  NSNextFunctionKey* = 0xF740'u16
  NSSelectFunctionKey* = 0xF741'u16
  NSExecuteFunctionKey* = 0xF742'u16
  NSUndoFunctionKey* = 0xF743'u16
  NSRedoFunctionKey* = 0xF744'u16
  NSFindFunctionKey* = 0xF745'u16
  NSHelpFunctionKey* = 0xF746'u16
  NSModeSwitchFunctionKey* = 0xF747'u16

  NSApplicationActivated* = 0
  NSApplicationDeactivated* = 1

var currentMouseLocation {.threadvar.}: NSPoint
var currentModifierFlags {.threadvar.}: NSUInteger
var periodicEventsEnabledState {.threadvar.}: bool
var periodicEventsDelaySeconds {.threadvar.}: cdouble
var periodicEventsPeriodSeconds {.threadvar.}: cdouble

proc timeIntervalSinceReferenceDate(): cdouble =
  (epochTime() - 978_307_200.0).cdouble

proc isModifierSiwinKey(key: siwin.Key): bool =
  key in {
    siwin.Key.lcontrol, siwin.Key.rcontrol, siwin.Key.lshift, siwin.Key.rshift,
    siwin.Key.lalt, siwin.Key.ralt, siwin.Key.lsystem, siwin.Key.rsystem,
    siwin.Key.capsLock, siwin.Key.numLock,
  }

proc modifierFlagsFromSiwin*(modifiers: set[siwin.ModifierKey]): NSUInteger =
  result = 0
  if siwin.ModifierKey.shift in modifiers:
    result = result or NSShiftKeyMask
  if siwin.ModifierKey.control in modifiers:
    result = result or NSControlKeyMask
  if siwin.ModifierKey.alt in modifiers:
    result = result or NSAlternateKeyMask
  if siwin.ModifierKey.system in modifiers:
    result = result or NSCommandKeyMask
  if siwin.ModifierKey.capsLock in modifiers:
    result = result or NSAlphaShiftKeyMask
  if siwin.ModifierKey.numLock in modifiers:
    result = result or NSNumericPadKeyMask

proc nsEventTypeFromSiwin*(event: siwin.KeyEvent): NSEventType =
  if isModifierSiwinKey(event.key):
    return NSFlagsChanged
  if event.pressed:
    return NSKeyDown
  NSKeyUp

proc nsEventTypeFromSiwin*(event: siwin.MouseButtonEvent): NSEventType =
  case event.button
  of siwin.MouseButton.left:
    if event.pressed:
      return NSLeftMouseDown
    NSLeftMouseUp
  of siwin.MouseButton.right:
    if event.pressed:
      return NSRightMouseDown
    NSRightMouseUp
  else:
    if event.pressed:
      return NSAppKitDefined
    NSApplicationDefined

proc siwinKeyCode*(key: siwin.Key): cushort =
  key.ord.cushort

objcImpl:
  type NSEvent* = object of NSObject
    xxType {.get: `type`.}: NSEventType
    xxTimestamp {.get: timestamp.}: cdouble
    xxLocationInWindow {.get: locationInWindow.}: NSPoint
    xxModifierFlags {.get: modifierFlags.}: NSUInteger
    xxWindowNumber {.get: windowNumber.}: NSInteger

    xxClickCount {.get: clickCount.}: int
    xxDeltaX {.get: deltaX.}: cfloat
    xxDeltaY {.get: deltaY.}: cfloat
    xxDeltaZ {.get: deltaZ.}: cfloat
    xxKeyCode {.get: keyCode.}: cushort

    xxSubtype: cshort
    xxData1: NSInteger
    xxData2: NSInteger
    xxTrackingNumber: NSInteger
    xxUserData: pointer
    xxHasOtherData: bool
    xxHasTrackingData: bool

    xxCharactersId: ID
    xxCharactersIgnoringModifiersId: ID

    xxSiwinKey: siwin.Key
    xxSiwinModifiers: set[siwin.ModifierKey]
    xxSiwinMouseButton: siwin.MouseButton
    xxSiwinMouseButtons: set[siwin.MouseButton]
    xxSiwinRepeated: bool
    xxSiwinGenerated: bool
    xxSiwinPressed: bool

  method init*(self: var NSEvent): NSEvent =
    result = asType[NSEvent](callSuperIdFrom(NSEvent, self, getSelector("init")))
    if result.isNil:
      return
    result.xxType = NSApplicationDefined
    result.xxTimestamp = timeIntervalSinceReferenceDate()
    result.xxLocationInWindow = nsPoint(0.0, 0.0)
    result.xxModifierFlags = 0
    result.xxWindowNumber = 0
    result.xxClickCount = 0
    result.xxDeltaX = 0
    result.xxDeltaY = 0
    result.xxDeltaZ = 0
    result.xxKeyCode = 0xFFFF'u16
    result.xxSubtype = 0
    result.xxData1 = 0
    result.xxData2 = 0
    result.xxTrackingNumber = 0
    result.xxUserData = nil
    result.xxHasOtherData = false
    result.xxHasTrackingData = false
    result.xxCharactersId = nil
    result.xxCharactersIgnoringModifiersId = nil
    result.xxSiwinKey = siwin.Key.unknown
    result.xxSiwinModifiers = {}
    result.xxSiwinMouseButton = siwin.MouseButton.left
    result.xxSiwinMouseButtons = {}
    result.xxSiwinRepeated = false
    result.xxSiwinGenerated = false
    result.xxSiwinPressed = false

  method initWithType*(
      self: var NSEvent,
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      modifierFlags {.kw("modifierFlags").}: NSUInteger,
      timestamp {.kw("timestamp").}: cdouble,
      windowNumber {.kw("windowNumber").}: NSInteger,
  ): NSEvent =
    result = self.init()
    if result.isNil:
      return
    result.xxType = eventType
    result.xxLocationInWindow = location
    result.xxModifierFlags = modifierFlags
    result.xxTimestamp = timestamp
    result.xxWindowNumber = windowNumber
    currentMouseLocation = location
    currentModifierFlags = modifierFlags

  proc mouseLocation*(t: typedesc[NSEvent]): NSPoint =
    when false:
      discard t
    currentMouseLocation

  proc modifierFlags*(t: typedesc[NSEvent]): NSUInteger =
    when false:
      discard t
    currentModifierFlags

  proc enterExitEventWithType*(
      t: typedesc[NSEvent],
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      flags {.kw("modifierFlags").}: NSUInteger,
      timestamp {.kw("timestamp").}: cdouble,
      windowNumber {.kw("windowNumber").}: NSInteger,
      context {.kw("context").}: NSObject,
      eventNumber {.kw("eventNumber").}: NSInteger,
      trackingNumber {.kw("trackingNumber").}: NSInteger,
      userData {.kw("userData").}: pointer,
  ): NSEvent =
    when false:
      discard t
    discard context
    discard eventNumber

    var allocated = NSEvent.alloc()
    result = allocated.initWithType(eventType, location, flags, timestamp, windowNumber)
    allocated.value = nil
    if result.isNil:
      return
    result.xxTrackingNumber = trackingNumber
    result.xxUserData = userData
    result.xxHasTrackingData = true

  proc mouseEventWithType*(
      t: typedesc[NSEvent],
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      flags {.kw("modifierFlags").}: NSUInteger,
      timestamp {.kw("timestamp").}: cdouble,
      windowNumber {.kw("windowNumber").}: NSInteger,
      context {.kw("context").}: NSObject,
      eventNumber {.kw("eventNumber").}: NSInteger,
      clickCount {.kw("clickCount").}: NSInteger,
      pressure {.kw("pressure").}: cfloat,
  ): NSEvent =
    when false:
      discard t
    discard context
    discard eventNumber
    discard pressure

    var allocated = NSEvent.alloc()
    result = allocated.initWithType(eventType, location, flags, timestamp, windowNumber)
    allocated.value = nil
    if result.isNil:
      return
    result.xxClickCount = clickCount.int

  proc keyEventWithType*(
      t: typedesc[NSEvent],
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      modifierFlags {.kw("modifierFlags").}: cuint,
      timestamp {.kw("timestamp").}: cdouble,
      windowNumber {.kw("windowNumber").}: cint,
      context {.kw("context").}: NSObject,
      characters {.kw("characters").}: NSString,
      charactersIgnoringModifiers {.kw("charactersIgnoringModifiers").}: NSString,
      isARepeat {.kw("isARepeat").}: bool,
      keyCode {.kw("keyCode").}: cushort,
  ): NSEvent =
    when false:
      discard t
    discard context

    var allocated = NSEvent.alloc()
    result = allocated.initWithType(
      eventType, location, modifierFlags.NSUInteger, timestamp, windowNumber.NSInteger
    )
    allocated.value = nil
    if result.isNil:
      return
    result.xxCharactersId = replacedOwnedId(result.xxCharactersId, characters.value)
    result.xxCharactersIgnoringModifiersId = replacedOwnedId(
      result.xxCharactersIgnoringModifiersId, charactersIgnoringModifiers.value
    )
    result.xxKeyCode = keyCode
    result.xxSiwinRepeated = isARepeat

  proc otherEventWithType*(
      t: typedesc[NSEvent],
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      flags {.kw("modifierFlags").}: NSUInteger,
      timestamp {.kw("timestamp").}: cdouble,
      windowNum {.kw("windowNumber").}: NSInteger,
      context {.kw("context").}: NSObject,
      subtype {.kw("subtype").}: cshort,
      data1 {.kw("data1").}: NSInteger,
      data2 {.kw("data2").}: NSInteger,
  ): NSEvent =
    when false:
      discard t
    discard context

    var allocated = NSEvent.alloc()
    result = allocated.initWithType(eventType, location, flags, timestamp, windowNum)
    allocated.value = nil
    if result.isNil:
      return
    result.xxSubtype = subtype
    result.xxData1 = data1
    result.xxData2 = data2
    result.xxHasOtherData = true

  method characters*(self: NSEvent): NSString =
    if self.xxCharactersId.isNil:
      return NSString(value: nil)
    ownFromId[NSString](self.xxCharactersId)

  method charactersIgnoringModifiers*(self: NSEvent): NSString =
    if self.xxCharactersIgnoringModifiersId.isNil:
      return NSString(value: nil)
    ownFromId[NSString](self.xxCharactersIgnoringModifiersId)

  proc startPeriodicEventsAfterDelay*(
      t: typedesc[NSEvent], delay: cdouble, period {.kw("withPeriod").}: cdouble
  ) =
    when false:
      discard t
    if periodicEventsEnabledState:
      raise newException(ValueError, "periodic events already enabled")
    periodicEventsEnabledState = true
    periodicEventsDelaySeconds = delay
    periodicEventsPeriodSeconds = period

  proc stopPeriodicEvents*(t: typedesc[NSEvent]) =
    when false:
      discard t
    periodicEventsEnabledState = false
    periodicEventsDelaySeconds = 0
    periodicEventsPeriodSeconds = 0

  method subtype*(self: NSEvent): cshort =
    if not self.xxHasOtherData:
      raise newException(ValueError, "No event subtype in NSEvent")
    self.xxSubtype

  method data1*(self: NSEvent): NSInteger =
    if not self.xxHasOtherData:
      raise newException(ValueError, "No event data1 in NSEvent")
    self.xxData1

  method data2*(self: NSEvent): NSInteger =
    if not self.xxHasOtherData:
      raise newException(ValueError, "No event data2 in NSEvent")
    self.xxData2

  method trackingNumber*(self: NSEvent): NSInteger =
    if not self.xxHasTrackingData:
      raise newException(ValueError, "No trackingNumber in NSEvent")
    self.xxTrackingNumber

  method trackingArea*(self: NSEvent): NSObject =
    if not self.xxHasTrackingData:
      raise newException(ValueError, "No trackingArea in NSEvent")
    NSObject(value: cast[ID](self.xxTrackingNumber.uint))

  method userData*(self: NSEvent): pointer =
    if not self.xxHasTrackingData:
      raise newException(ValueError, "No userData in NSEvent")
    if self.xxType notin [NSMouseEntered, NSMouseExited]:
      raise newException(
        ValueError, "userData is only valid for NSMouseEntered/NSMouseExited"
      )
    self.xxUserData

  method dealloc(self: NSEvent) {.used.} =
    self.xxCharactersId = replacedOwnedId(self.xxCharactersId, nil)
    self.xxCharactersIgnoringModifiersId =
      replacedOwnedId(self.xxCharactersIgnoringModifiersId, nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NSEvent, self, getSelector("dealloc"))

proc newEvent*(
    eventType: NSEventType,
    location: NSPoint,
    modifierFlags: NSUInteger,
    timestamp: cdouble = timeIntervalSinceReferenceDate(),
    windowNumber: NSInteger = 0,
): NSEvent =
  var allocated = NSEvent.alloc()
  result =
    allocated.initWithType(eventType, location, modifierFlags, timestamp, windowNumber)
  allocated.value = nil

proc newKeyEvent*(
    eventType: NSEventType,
    location: NSPoint,
    modifierFlags: cuint,
    timestamp: cdouble,
    windowNumber: cint,
    characters: NSString,
    charactersIgnoringModifiers: NSString,
    isARepeat: bool,
    keyCode: cushort,
): NSEvent =
  result = newEvent(
    eventType, location, modifierFlags.NSUInteger, timestamp, windowNumber.NSInteger
  )
  if result.isNil:
    return
  result.xxCharactersId = replacedOwnedId(result.xxCharactersId, characters.value)
  result.xxCharactersIgnoringModifiersId = replacedOwnedId(
    result.xxCharactersIgnoringModifiersId, charactersIgnoringModifiers.value
  )
  result.xxKeyCode = keyCode
  result.xxSiwinRepeated = isARepeat

proc newOtherEvent*(
    eventType: NSEventType,
    location: NSPoint,
    flags: NSUInteger,
    timestamp: cdouble,
    windowNum: NSInteger,
    subtype: cshort,
    data1: NSInteger,
    data2: NSInteger,
): NSEvent =
  result = newEvent(eventType, location, flags, timestamp, windowNum)
  if result.isNil:
    return
  result.xxSubtype = subtype
  result.xxData1 = data1
  result.xxData2 = data2
  result.xxHasOtherData = true

proc newEnterExitEvent*(
    eventType: NSEventType,
    location: NSPoint,
    flags: NSUInteger,
    timestamp: cdouble,
    windowNumber: NSInteger,
    trackingNumber: NSInteger,
    userData: pointer,
): NSEvent =
  result = newEvent(eventType, location, flags, timestamp, windowNumber)
  if result.isNil:
    return
  result.xxTrackingNumber = trackingNumber
  result.xxUserData = userData
  result.xxHasTrackingData = true

proc newMouseEvent*(
    eventType: NSEventType,
    location: NSPoint,
    flags: NSUInteger,
    timestamp: cdouble,
    windowNumber: NSInteger,
    clickCount: NSInteger,
): NSEvent =
  result = newEvent(eventType, location, flags, timestamp, windowNumber)
  if result.isNil:
    return
  result.xxClickCount = clickCount.int

proc NSEventMaskFromType*(eventType: NSEventType): cuint =
  (1'u shl eventType.int).cuint

proc periodicEventsEnabled*(): bool =
  periodicEventsEnabledState

proc periodicEventsDelay*(): cdouble =
  periodicEventsDelaySeconds

proc periodicEventsPeriod*(): cdouble =
  periodicEventsPeriodSeconds

proc siwinKey*(event: NSEvent): siwin.Key =
  if event.isNil:
    return siwin.Key.unknown
  event.xxSiwinKey

proc siwinModifiers*(event: NSEvent): set[siwin.ModifierKey] =
  if event.isNil:
    return {}
  event.xxSiwinModifiers

proc siwinMouseButton*(event: NSEvent): siwin.MouseButton =
  if event.isNil:
    return siwin.MouseButton.left
  event.xxSiwinMouseButton

proc siwinMouseButtons*(event: NSEvent): set[siwin.MouseButton] =
  if event.isNil:
    return {}
  event.xxSiwinMouseButtons

proc siwinRepeated*(event: NSEvent): bool =
  (not event.isNil) and event.xxSiwinRepeated

proc siwinGenerated*(event: NSEvent): bool =
  (not event.isNil) and event.xxSiwinGenerated

proc siwinPressed*(event: NSEvent): bool =
  (not event.isNil) and event.xxSiwinPressed

proc keyEventFromSiwin*(
    windowNumber: NSInteger,
    location: NSPoint,
    event: siwin.KeyEvent,
    characters: NSString = @ns"",
    charactersIgnoringModifiers: NSString = @ns"",
): NSEvent =
  result = newKeyEvent(
    nsEventTypeFromSiwin(event),
    location,
    modifierFlagsFromSiwin(event.modifiers).cuint,
    timeIntervalSinceReferenceDate(),
    windowNumber.cint,
    characters,
    charactersIgnoringModifiers,
    event.repeated,
    siwinKeyCode(event.key),
  )
  if result.isNil:
    return
  result.xxSiwinKey = event.key
  result.xxSiwinModifiers = event.modifiers
  result.xxSiwinRepeated = event.repeated
  result.xxSiwinGenerated = event.generated
  result.xxSiwinPressed = event.pressed

proc mouseButtonEventFromSiwin*(
    windowNumber: NSInteger,
    location: NSPoint,
    event: siwin.MouseButtonEvent,
    modifiers: set[siwin.ModifierKey] = {},
): NSEvent =
  result = newEvent(
    nsEventTypeFromSiwin(event),
    location,
    modifierFlagsFromSiwin(modifiers),
    timeIntervalSinceReferenceDate(),
    windowNumber,
  )
  if result.isNil:
    return
  result.xxClickCount = (if event.pressed and not event.generated: 1 else: 0)
  result.xxSiwinMouseButton = event.button
  result.xxSiwinModifiers = modifiers
  result.xxSiwinGenerated = event.generated
  result.xxSiwinPressed = event.pressed
  if event.pressed:
    result.xxSiwinMouseButtons = {event.button}
  else:
    result.xxSiwinMouseButtons = {}

proc scrollEventFromSiwin*(
    windowNumber: NSInteger,
    location: NSPoint,
    event: siwin.ScrollEvent,
    modifiers: set[siwin.ModifierKey] = {},
): NSEvent =
  result = newEvent(
    NSScrollWheel,
    location,
    modifierFlagsFromSiwin(modifiers),
    timeIntervalSinceReferenceDate(),
    windowNumber,
  )
  if result.isNil:
    return
  result.xxDeltaX = event.deltaX.cfloat
  result.xxDeltaY = event.delta.cfloat
  result.xxSiwinModifiers = modifiers
