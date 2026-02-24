import std/times

import siwin/window as siwin

import ./runtime

type
  NSEventType* = enum
    NSLeftMouseDown = 1
    NSLeftMouseUp = 2
    NSRightMouseDown = 3
    NSRightMouseUp = 4
    NSMouseMoved = 5
    NSLeftMouseDragged = 6
    NSRightMouseDragged = 7
    NSMouseEntered = 8
    NSMouseExited = 9
    NSKeyDown = 10
    NSKeyUp = 11
    NSFlagsChanged = 12
    NSPeriodic = 13
    NSCursorUpdate = 14
    NSPlatformSpecific = 15
    NSPlatformSpecificDisplayEvent = 16
    NSAppKitSystem = 17
    NSScrollWheel = 18
    NSApplicationDefined = 19
    NSAppKitDefined = 20

  NSEventMask* = set[NSEventType]

  NSModifierFlag* = enum
    NSAlphaShiftKeyMask = 16
    NSShiftKeyMask = 17
    NSControlKeyMask = 18
    NSAlternateKeyMask = 19
    NSCommandKeyMask = 20
    NSNumericPadKeyMask = 21
    NSHelpKeyMask = 22
    NSFunctionKeyMask = 23

  NSModifierFlags* = set[NSModifierFlag]

  NSFunctionKey* = enum
    NSUpArrowFunctionKey = 0xF700
    NSDownArrowFunctionKey = 0xF701
    NSLeftArrowFunctionKey = 0xF702
    NSRightArrowFunctionKey = 0xF703
    NSF1FunctionKey = 0xF704
    NSF2FunctionKey = 0xF705
    NSF3FunctionKey = 0xF706
    NSF4FunctionKey = 0xF707
    NSF5FunctionKey = 0xF708
    NSF6FunctionKey = 0xF709
    NSF7FunctionKey = 0xF70A
    NSF8FunctionKey = 0xF70B
    NSF9FunctionKey = 0xF70C
    NSF10FunctionKey = 0xF70D
    NSF11FunctionKey = 0xF70E
    NSF12FunctionKey = 0xF70F
    NSF13FunctionKey = 0xF710
    NSF14FunctionKey = 0xF711
    NSF15FunctionKey = 0xF712
    NSF16FunctionKey = 0xF713
    NSF17FunctionKey = 0xF714
    NSF18FunctionKey = 0xF715
    NSF19FunctionKey = 0xF716
    NSF20FunctionKey = 0xF717
    NSF21FunctionKey = 0xF718
    NSF22FunctionKey = 0xF719
    NSF23FunctionKey = 0xF71A
    NSF24FunctionKey = 0xF71B
    NSF25FunctionKey = 0xF71C
    NSF26FunctionKey = 0xF71D
    NSF27FunctionKey = 0xF71E
    NSF28FunctionKey = 0xF71F
    NSF29FunctionKey = 0xF720
    NSF30FunctionKey = 0xF721
    NSF31FunctionKey = 0xF722
    NSF32FunctionKey = 0xF723
    NSF33FunctionKey = 0xF724
    NSF34FunctionKey = 0xF725
    NSF35FunctionKey = 0xF726
    NSInsertFunctionKey = 0xF727
    NSDeleteFunctionKey = 0xF728
    NSHomeFunctionKey = 0xF729
    NSBeginFunctionKey = 0xF72A
    NSEndFunctionKey = 0xF72B
    NSPageUpFunctionKey = 0xF72C
    NSPageDownFunctionKey = 0xF72D
    NSPrintScreenFunctionKey = 0xF72E
    NSScrollLockFunctionKey = 0xF72F
    NSPauseFunctionKey = 0xF730
    NSSysReqFunctionKey = 0xF731
    NSBreakFunctionKey = 0xF732
    NSResetFunctionKey = 0xF733
    NSStopFunctionKey = 0xF734
    NSMenuFunctionKey = 0xF735
    NSUserFunctionKey = 0xF736
    NSSystemFunctionKey = 0xF737
    NSPrintFunctionKey = 0xF738
    NSClearLineFunctionKey = 0xF739
    NSClearDisplayFunctionKey = 0xF73A
    NSInsertLineFunctionKey = 0xF73B
    NSDeleteLineFunctionKey = 0xF73C
    NSInsertCharFunctionKey = 0xF73D
    NSDeleteCharFunctionKey = 0xF73E
    NSPrevFunctionKey = 0xF73F
    NSNextFunctionKey = 0xF740
    NSSelectFunctionKey = 0xF741
    NSExecuteFunctionKey = 0xF742
    NSUndoFunctionKey = 0xF743
    NSRedoFunctionKey = 0xF744
    NSFindFunctionKey = 0xF745
    NSHelpFunctionKey = 0xF746
    NSModeSwitchFunctionKey = 0xF747

  NSApplicationActivationType* = enum
    NSApplicationActivated = 0
    NSApplicationDeactivated = 1

const
  NSLeftMouseDownMask*: NSEventMask = {NSLeftMouseDown}
  NSLeftMouseUpMask*: NSEventMask = {NSLeftMouseUp}
  NSRightMouseDownMask*: NSEventMask = {NSRightMouseDown}
  NSRightMouseUpMask*: NSEventMask = {NSRightMouseUp}
  NSMouseMovedMask*: NSEventMask = {NSMouseMoved}
  NSLeftMouseDraggedMask*: NSEventMask = {NSLeftMouseDragged}
  NSRightMouseDraggedMask*: NSEventMask = {NSRightMouseDragged}
  NSMouseEnteredMask*: NSEventMask = {NSMouseEntered}
  NSMouseExitedMask*: NSEventMask = {NSMouseExited}
  NSKeyDownMask*: NSEventMask = {NSKeyDown}
  NSKeyUpMask*: NSEventMask = {NSKeyUp}
  NSFlagsChangedMask*: NSEventMask = {NSFlagsChanged}
  NSPeriodicMask*: NSEventMask = {NSPeriodic}
  NSCursorUpdateMask*: NSEventMask = {NSCursorUpdate}
  NSScrollWheelMask*: NSEventMask = {NSScrollWheel}
  NSApplicationDefinedMask*: NSEventMask = {NSApplicationDefined}
  NSAppKitDefinedMask*: NSEventMask = {NSAppKitDefined}
  NSAnyEventMask*: NSEventMask = {NSLeftMouseDown .. NSAppKitDefined}
  NSPlatformSpecificDisplayMask*: NSEventMask = {NSPlatformSpecificDisplayEvent}

  NSDeviceIndependentModifierFlagsMask*: NSModifierFlags =
    {NSAlphaShiftKeyMask .. NSFunctionKeyMask}

var currentMouseLocation {.threadvar.}: NSPoint
var currentModifierFlags {.threadvar.}: NSUInteger
var periodicEventsEnabledState {.threadvar.}: bool
var periodicEventsDelaySeconds {.threadvar.}: float
var periodicEventsPeriodSeconds {.threadvar.}: float

proc timeIntervalSinceReferenceDate(): float =
  (epochTime() - 978_307_200.0).float

proc isModifierSiwinKey(key: siwin.Key): bool =
  key in {
    siwin.Key.lcontrol, siwin.Key.rcontrol, siwin.Key.lshift, siwin.Key.rshift,
    siwin.Key.lalt, siwin.Key.ralt, siwin.Key.lsystem, siwin.Key.rsystem,
    siwin.Key.capsLock, siwin.Key.numLock,
  }

proc nsModifierFlagsMask*(flags: NSModifierFlags): NSUInteger =
  result = 0.NSUInteger
  for flag in flags:
    result = result or ((1'u shl flag.ord).NSUInteger)

proc nsModifierFlagsFromMask*(mask: NSUInteger): NSModifierFlags =
  result = {}
  for flag in low(NSModifierFlag) .. high(NSModifierFlag):
    if (mask and ((1'u shl flag.ord).NSUInteger)) != 0:
      result.incl(flag)

proc modifierFlagsFromSiwin*(modifiers: set[siwin.ModifierKey]): NSModifierFlags =
  result = {}
  if siwin.ModifierKey.shift in modifiers:
    result.incl(NSShiftKeyMask)
  if siwin.ModifierKey.control in modifiers:
    result.incl(NSControlKeyMask)
  if siwin.ModifierKey.alt in modifiers:
    result.incl(NSAlternateKeyMask)
  if siwin.ModifierKey.system in modifiers:
    result.incl(NSCommandKeyMask)
  if siwin.ModifierKey.capsLock in modifiers:
    result.incl(NSAlphaShiftKeyMask)
  if siwin.ModifierKey.numLock in modifiers:
    result.incl(NSNumericPadKeyMask)

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
    xxTimestamp {.get: timestamp.}: float
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
      timestamp {.kw("timestamp").}: float,
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
      timestamp {.kw("timestamp").}: float,
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
      timestamp {.kw("timestamp").}: float,
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
      timestamp {.kw("timestamp").}: float,
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
      timestamp {.kw("timestamp").}: float,
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
      t: typedesc[NSEvent], delay: float, period {.kw("withPeriod").}: float
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

objcImpl:
  type NSEvent_keyboard* = object of NSEvent

objcImpl:
  type NSEvent_mouse* = object of NSEvent
    xxSerialNumber {.get: serialNumber, set: setSerialNumber.}: NSInteger

objcImpl:
  type NSEvent_other* = object of NSEvent

objcImpl:
  type NSEvent_periodic* = object of NSEvent

objcImpl:
  type NSEvent_CoreGraphics* = object of NSEvent
    xxCoreGraphicsEvent {.get: coreGraphicsEvent.}: pointer

  method initWithDisplayEvent*(
      self: var NSEvent_CoreGraphics, event: pointer
  ): NSEvent_CoreGraphics =
    var initialized = self.initWithType(
      NSPlatformSpecificDisplayEvent,
      nsPoint(0, 0),
      0,
      timeIntervalSinceReferenceDate(),
      0,
    )
    result = asType[NSEvent_CoreGraphics](initialized.value)
    initialized.value = nil
    if result.isNil:
      return
    result.xxCoreGraphicsEvent = event

proc newEvent*(
    eventType: NSEventType,
    location: NSPoint,
    modifierFlags: NSUInteger,
    timestamp: float = timeIntervalSinceReferenceDate(),
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
    timestamp: float,
    windowNumber: cint,
    characters: NSString,
    charactersIgnoringModifiers: NSString,
    isARepeat: bool,
    keyCode: cushort,
): NSEvent =
  var allocated = NSEvent_keyboard.alloc()
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

proc newOtherEvent*(
    eventType: NSEventType,
    location: NSPoint,
    flags: NSUInteger,
    timestamp: float,
    windowNum: NSInteger,
    subtype: cshort,
    data1: NSInteger,
    data2: NSInteger,
): NSEvent =
  var allocated = NSEvent_other.alloc()
  result = allocated.initWithType(eventType, location, flags, timestamp, windowNum)
  allocated.value = nil
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
    timestamp: float,
    windowNumber: NSInteger,
    trackingNumber: NSInteger,
    userData: pointer,
): NSEvent =
  var allocated = NSEvent_mouse.alloc()
  result = allocated.initWithType(eventType, location, flags, timestamp, windowNumber)
  allocated.value = nil
  if result.isNil:
    return
  result.xxTrackingNumber = trackingNumber
  result.xxUserData = userData
  result.xxHasTrackingData = true

proc newMouseEvent*(
    eventType: NSEventType,
    location: NSPoint,
    flags: NSUInteger,
    timestamp: float,
    windowNumber: NSInteger,
    clickCount: NSInteger,
): NSEvent =
  var allocated = NSEvent_mouse.alloc()
  result = allocated.initWithType(eventType, location, flags, timestamp, windowNumber)
  allocated.value = nil
  if result.isNil:
    return
  result.xxClickCount = clickCount.int

proc newPeriodicEvent*(
    timestamp: float = timeIntervalSinceReferenceDate()
): NSEvent_periodic =
  var allocated = NSEvent_periodic.alloc()
  var initialized = allocated.initWithType(NSPeriodic, nsPoint(0, 0), 0, timestamp, 0)
  result = asType[NSEvent_periodic](initialized.value)
  initialized.value = nil
  allocated.value = nil

proc newDisplayEvent*(
    event: pointer, timestamp: float = timeIntervalSinceReferenceDate()
): NSEvent_CoreGraphics =
  var allocated = NSEvent_CoreGraphics.alloc()
  var initialized = allocated.initWithType(
    NSPlatformSpecificDisplayEvent, nsPoint(0, 0), 0, timestamp, 0
  )
  result = asType[NSEvent_CoreGraphics](initialized.value)
  initialized.value = nil
  allocated.value = nil
  if result.isNil:
    return
  result.xxCoreGraphicsEvent = event

proc NSEventMaskFromType*(eventType: NSEventType): NSEventMask =
  {eventType}

proc periodicEventsEnabled*(): bool =
  periodicEventsEnabledState

proc periodicEventsDelay*(): float =
  periodicEventsDelaySeconds

proc periodicEventsPeriod*(): float =
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
    nsModifierFlagsMask(modifierFlagsFromSiwin(event.modifiers)).cuint,
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
  let clickCount = (if event.pressed and not event.generated: 1 else: 0)
  result = newEvent(
    nsEventTypeFromSiwin(event),
    location,
    nsModifierFlagsMask(modifierFlagsFromSiwin(modifiers)),
    timeIntervalSinceReferenceDate(),
    windowNumber,
  )
  if result.isNil:
    return
  if not result.isKindOfClass(NSEvent_mouse):
    var allocated = NSEvent_mouse.alloc()
    var initialized = allocated.initWithType(
      result.`type`(),
      result.locationInWindow(),
      result.modifierFlags(),
      result.timestamp(),
      result.windowNumber(),
    )
    allocated.value = nil
    if not initialized.isNil:
      result = initialized
  result.xxClickCount = clickCount
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
    nsModifierFlagsMask(modifierFlagsFromSiwin(modifiers)),
    timeIntervalSinceReferenceDate(),
    windowNumber,
  )
  if result.isNil:
    return
  result.xxDeltaX = event.deltaX.cfloat
  result.xxDeltaY = event.delta.cfloat
  result.xxSiwinModifiers = modifiers
