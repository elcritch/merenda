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
var currentModifierFlags {.threadvar.}: NSModifierFlags
var periodicEventsEnabledState {.threadvar.}: bool
var periodicEventsDelaySeconds {.threadvar.}: float
var periodicEventsPeriodSeconds {.threadvar.}: float

proc timeIntervalSinceReferenceDate(): float =
  (epochTime() - 978_307_200.0)

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

proc nsEventTypeFromSiwin*(
    event: siwin.MouseMoveEvent, mouseButtons: set[siwin.MouseButton] = {}
): NSEventType =
  case event.kind
  of siwin.MouseMoveKind.enter:
    NSMouseEntered
  of siwin.MouseMoveKind.leave:
    NSMouseExited
  of siwin.MouseMoveKind.moveWhileDragging:
    if siwin.MouseButton.left in mouseButtons:
      NSLeftMouseDragged
    elif siwin.MouseButton.right in mouseButtons:
      NSRightMouseDragged
    else:
      NSMouseMoved
  else:
    NSMouseMoved

proc siwinKeyCode*(key: siwin.Key): cushort =
  key.ord.cushort

objcImpl:
  type NSEvent* = object of NSObject
    xType {.get: `type`.}: NSEventType
    xTimestamp {.get: timestamp.}: float
    xLocationInWindow {.get: locationInWindow.}: NSPoint
    xModifierFlags {.get: modifierFlags.}: NSModifierFlags
    xWindowNumber {.get: windowNumber.}: NSInteger

    xClickCount {.get: clickCount.}: int
    xDeltaX {.get: deltaX.}: float32
    xDeltaY {.get: deltaY.}: float32
    xDeltaZ {.get: deltaZ.}: float32
    xKeyCode {.get: keyCode.}: cushort

    xSubtype: cshort
    xData1: NSInteger
    xData2: NSInteger
    xTrackingNumber: NSInteger
    xUserData: pointer
    xHasOtherData: bool
    xHasTrackingData: bool

    xCharactersId: NSString
    xCharactersIgnoringModifiersId: NSString

    xSiwinKey: siwin.Key
    xSiwinModifiers: set[siwin.ModifierKey]
    xSiwinMouseButton: siwin.MouseButton
    xSiwinMouseButtons: set[siwin.MouseButton]
    xSiwinRepeated: bool
    xSiwinGenerated: bool
    xSiwinPressed: bool

  method init*(self: var NSEvent): NSEvent =
    result = asType[NSEvent](callSuperIdFrom(NSEvent, self, getSelector("init")))
    if result.isNil:
      return
    result.xType = NSApplicationDefined
    result.xTimestamp = timeIntervalSinceReferenceDate()
    result.xLocationInWindow = nsPoint(0.0, 0.0)
    result.xModifierFlags = {}
    result.xWindowNumber = 0
    result.xClickCount = 0
    result.xDeltaX = 0
    result.xDeltaY = 0
    result.xDeltaZ = 0
    result.xKeyCode = 0xFFFF'u16
    result.xSubtype = 0
    result.xData1 = 0
    result.xData2 = 0
    result.xTrackingNumber = 0
    result.xUserData = nil
    result.xHasOtherData = false
    result.xHasTrackingData = false
    result.xCharactersId = NSString(value: nil)
    result.xCharactersIgnoringModifiersId = NSString(value: nil)
    result.xSiwinKey = siwin.Key.unknown
    result.xSiwinModifiers = {}
    result.xSiwinMouseButton = siwin.MouseButton.left
    result.xSiwinMouseButtons = {}
    result.xSiwinRepeated = false
    result.xSiwinGenerated = false
    result.xSiwinPressed = false

  method initWithType*(
      self: var NSEvent,
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      modifierFlags {.kw("modifierFlags").}: NSModifierFlags,
      timestamp {.kw("timestamp").}: float,
      windowNumber {.kw("windowNumber").}: NSInteger,
  ): NSEvent =
    result = self.init()
    if result.isNil:
      return
    result.xType = eventType
    result.xLocationInWindow = location
    result.xModifierFlags = modifierFlags
    result.xTimestamp = timestamp
    result.xWindowNumber = windowNumber
    currentMouseLocation = location
    currentModifierFlags = modifierFlags

  proc mouseLocation*(t: typedesc[NSEvent]): NSPoint =
    currentMouseLocation

  proc modifierFlags*(t: typedesc[NSEvent]): NSModifierFlags =
    currentModifierFlags

  proc enterExitEventWithType*(
      t: typedesc[NSEvent],
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      flags {.kw("modifierFlags").}: NSModifierFlags,
      timestamp {.kw("timestamp").}: float,
      windowNumber {.kw("windowNumber").}: NSInteger,
      context {.kw("context").}: NSObject,
      eventNumber {.kw("eventNumber").}: NSInteger,
      trackingNumber {.kw("trackingNumber").}: NSInteger,
      userData {.kw("userData").}: pointer,
  ): NSEvent =
    discard context
    discard eventNumber

    var allocated = NSEvent.alloc()
    result = allocated.initWithType(eventType, location, flags, timestamp, windowNumber)
    allocated.value = nil
    if result.isNil:
      return
    result.xTrackingNumber = trackingNumber
    result.xUserData = userData
    result.xHasTrackingData = true

  proc mouseEventWithType*(
      t: typedesc[NSEvent],
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      flags {.kw("modifierFlags").}: NSModifierFlags,
      timestamp {.kw("timestamp").}: float,
      windowNumber {.kw("windowNumber").}: NSInteger,
      context {.kw("context").}: NSObject,
      eventNumber {.kw("eventNumber").}: NSInteger,
      clickCount {.kw("clickCount").}: NSInteger,
      pressure {.kw("pressure").}: float32,
  ): NSEvent =
    discard context
    discard eventNumber
    discard pressure

    var allocated = NSEvent.alloc()
    result = allocated.initWithType(eventType, location, flags, timestamp, windowNumber)
    allocated.value = nil
    if result.isNil:
      return
    result.xClickCount = clickCount.int

  proc keyEventWithType*(
      t: typedesc[NSEvent],
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      modifierFlags {.kw("modifierFlags").}: NSModifierFlags,
      timestamp {.kw("timestamp").}: float,
      windowNumber {.kw("windowNumber").}: int,
      context {.kw("context").}: NSObject,
      characters {.kw("characters").}: NSString,
      charactersIgnoringModifiers {.kw("charactersIgnoringModifiers").}: NSString,
      isARepeat {.kw("isARepeat").}: bool,
      keyCode {.kw("keyCode").}: cushort,
  ): NSEvent =
    discard context

    var allocated = NSEvent.alloc()
    result = allocated.initWithType(
      eventType, location, modifierFlags, timestamp, windowNumber.NSInteger
    )
    allocated.value = nil
    if result.isNil:
      return
    result.xCharactersId = retain(characters)
    result.xCharactersIgnoringModifiersId = retain(charactersIgnoringModifiers)
    result.xKeyCode = keyCode
    result.xSiwinRepeated = isARepeat

  proc otherEventWithType*(
      t: typedesc[NSEvent],
      eventType: NSEventType,
      location {.kw("location").}: NSPoint,
      flags {.kw("modifierFlags").}: NSModifierFlags,
      timestamp {.kw("timestamp").}: float,
      windowNum {.kw("windowNumber").}: NSInteger,
      context {.kw("context").}: NSObject,
      subtype {.kw("subtype").}: cshort,
      data1 {.kw("data1").}: NSInteger,
      data2 {.kw("data2").}: NSInteger,
  ): NSEvent =
    discard context

    var allocated = NSEvent.alloc()
    result = allocated.initWithType(eventType, location, flags, timestamp, windowNum)
    allocated.value = nil
    if result.isNil:
      return
    result.xSubtype = subtype
    result.xData1 = data1
    result.xData2 = data2
    result.xHasOtherData = true

  method characters*(self: NSEvent): NSString =
    if self.xCharactersId.isNil:
      return NSString(value: nil)
    retain(self.xCharactersId)

  method charactersIgnoringModifiers*(self: NSEvent): NSString =
    if self.xCharactersIgnoringModifiersId.isNil:
      return NSString(value: nil)
    retain(self.xCharactersIgnoringModifiersId)

  proc startPeriodicEventsAfterDelay*(
      t: typedesc[NSEvent], delay: float, period {.kw("withPeriod").}: float
  ) =
    if periodicEventsEnabledState:
      raise newException(ValueError, "periodic events already enabled")
    periodicEventsEnabledState = true
    periodicEventsDelaySeconds = delay
    periodicEventsPeriodSeconds = period

  proc stopPeriodicEvents*(t: typedesc[NSEvent]) =
    periodicEventsEnabledState = false
    periodicEventsDelaySeconds = 0
    periodicEventsPeriodSeconds = 0

  method subtype*(self: NSEvent): cshort =
    if not self.xHasOtherData:
      raise newException(ValueError, "No event subtype in NSEvent")
    self.xSubtype

  method data1*(self: NSEvent): NSInteger =
    if not self.xHasOtherData:
      raise newException(ValueError, "No event data1 in NSEvent")
    self.xData1

  method data2*(self: NSEvent): NSInteger =
    if not self.xHasOtherData:
      raise newException(ValueError, "No event data2 in NSEvent")
    self.xData2

  method trackingNumber*(self: NSEvent): NSInteger =
    if not self.xHasTrackingData:
      raise newException(ValueError, "No trackingNumber in NSEvent")
    self.xTrackingNumber

  method trackingArea*(self: NSEvent): NSObject =
    if not self.xHasTrackingData:
      raise newException(ValueError, "No trackingArea in NSEvent")
    NSObject(value: cast[IDPtr](self.xTrackingNumber.uint))

  method userData*(self: NSEvent): pointer =
    if not self.xHasTrackingData:
      raise newException(ValueError, "No userData in NSEvent")
    if self.xType notin [NSMouseEntered, NSMouseExited]:
      raise newException(
        ValueError, "userData is only valid for NSMouseEntered/NSMouseExited"
      )
    self.xUserData

  method dealloc(self: NSEvent) {.used.} =
    self.xCharactersId = NSString(value: nil)
    self.xCharactersIgnoringModifiersId = NSString(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSEvent, self, getSelector("dealloc"))

objcImpl:
  type NSEvent_keyboard* = object of NSEvent

objcImpl:
  type NSEvent_mouse* = object of NSEvent
    xSerialNumber {.get: serialNumber, set: setSerialNumber.}: NSInteger

objcImpl:
  type NSEvent_other* = object of NSEvent

objcImpl:
  type NSEvent_periodic* = object of NSEvent

objcImpl:
  type NSEvent_CoreGraphics* = object of NSEvent
    xCoreGraphicsEvent {.get: coreGraphicsEvent.}: pointer

  method initWithDisplayEvent*(
      self: var NSEvent_CoreGraphics, event: pointer
  ): NSEvent_CoreGraphics =
    var initialized = self.initWithType(
      NSPlatformSpecificDisplayEvent,
      nsPoint(0, 0),
      {},
      timeIntervalSinceReferenceDate(),
      0,
    )
    result = asType[NSEvent_CoreGraphics](move(initialized.value))
    if result.isNil:
      return
    result.xCoreGraphicsEvent = event

proc newEvent*(
    eventType: NSEventType,
    location: NSPoint,
    modifierFlags: NSModifierFlags,
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
    modifierFlags: NSModifierFlags,
    timestamp: float,
    windowNumber: int,
    characters: NSString,
    charactersIgnoringModifiers: NSString,
    isARepeat: bool,
    keyCode: cushort,
): NSEvent =
  var allocated = NSEvent_keyboard.alloc()
  result = allocated.initWithType(
    eventType, location, modifierFlags, timestamp, windowNumber.NSInteger
  )
  allocated.value = nil
  if result.isNil:
    return
  result.xCharactersId = retain(characters)
  result.xCharactersIgnoringModifiersId = retain(charactersIgnoringModifiers)
  result.xKeyCode = keyCode
  result.xSiwinRepeated = isARepeat

proc newOtherEvent*(
    eventType: NSEventType,
    location: NSPoint,
    flags: NSModifierFlags,
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
  result.xSubtype = subtype
  result.xData1 = data1
  result.xData2 = data2
  result.xHasOtherData = true

proc newEnterExitEvent*(
    eventType: NSEventType,
    location: NSPoint,
    flags: NSModifierFlags,
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
  result.xTrackingNumber = trackingNumber
  result.xUserData = userData
  result.xHasTrackingData = true

proc newMouseEvent*(
    eventType: NSEventType,
    location: NSPoint,
    flags: NSModifierFlags,
    timestamp: float,
    windowNumber: NSInteger,
    clickCount: NSInteger,
): NSEvent =
  var allocated = NSEvent_mouse.alloc()
  result = allocated.initWithType(eventType, location, flags, timestamp, windowNumber)
  allocated.value = nil
  if result.isNil:
    return
  result.xClickCount = clickCount.int

proc newPeriodicEvent*(
    timestamp: float = timeIntervalSinceReferenceDate()
): NSEvent_periodic =
  var allocated = NSEvent_periodic.alloc()
  var initialized = allocated.initWithType(NSPeriodic, nsPoint(0, 0), {}, timestamp, 0)
  result = asType[NSEvent_periodic](move(initialized.value))
  allocated.value = nil

proc newDisplayEvent*(
    event: pointer, timestamp: float = timeIntervalSinceReferenceDate()
): NSEvent_CoreGraphics =
  var allocated = NSEvent_CoreGraphics.alloc()
  var initialized = allocated.initWithType(
    NSPlatformSpecificDisplayEvent, nsPoint(0, 0), {}, timestamp, 0
  )
  result = asType[NSEvent_CoreGraphics](move(initialized.value))
  allocated.value = nil
  if result.isNil:
    return
  result.xCoreGraphicsEvent = event

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
  event.xSiwinKey

proc siwinModifiers*(event: NSEvent): set[siwin.ModifierKey] =
  if event.isNil:
    return {}
  event.xSiwinModifiers

proc siwinMouseButton*(event: NSEvent): siwin.MouseButton =
  if event.isNil:
    return siwin.MouseButton.left
  event.xSiwinMouseButton

proc siwinMouseButtons*(event: NSEvent): set[siwin.MouseButton] =
  if event.isNil:
    return {}
  event.xSiwinMouseButtons

proc siwinRepeated*(event: NSEvent): bool =
  (not event.isNil) and event.xSiwinRepeated

proc siwinGenerated*(event: NSEvent): bool =
  (not event.isNil) and event.xSiwinGenerated

proc siwinPressed*(event: NSEvent): bool =
  (not event.isNil) and event.xSiwinPressed

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
    modifierFlagsFromSiwin(event.modifiers),
    timeIntervalSinceReferenceDate(),
    windowNumber.int,
    characters,
    charactersIgnoringModifiers,
    event.repeated,
    siwinKeyCode(event.key),
  )
  if result.isNil:
    return
  result.xSiwinKey = event.key
  result.xSiwinModifiers = event.modifiers
  result.xSiwinRepeated = event.repeated
  result.xSiwinGenerated = event.generated
  result.xSiwinPressed = event.pressed

proc mouseButtonEventFromSiwin*(
    windowNumber: NSInteger,
    location: NSPoint,
    event: siwin.MouseButtonEvent,
    modifiers: set[siwin.ModifierKey] = {},
): NSEvent =
  let clickCount = (if event.pressed and not event.generated: 1 else: 0)
  result = newMouseEvent(
    nsEventTypeFromSiwin(event),
    location,
    modifierFlagsFromSiwin(modifiers),
    timeIntervalSinceReferenceDate(),
    windowNumber,
    clickCount,
  )
  if result.isNil:
    return
  result.xSiwinMouseButton = event.button
  result.xSiwinModifiers = modifiers
  result.xSiwinGenerated = event.generated
  result.xSiwinPressed = event.pressed
  if event.pressed:
    result.xSiwinMouseButtons = {event.button}
  else:
    result.xSiwinMouseButtons = {}

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
  result.xDeltaX = event.deltaX.float32
  result.xDeltaY = event.delta.float32
  result.xSiwinModifiers = modifiers

proc mouseMoveEventFromSiwin*(
    windowNumber: NSInteger,
    location: NSPoint,
    event: siwin.MouseMoveEvent,
    modifiers: set[siwin.ModifierKey] = {},
    mouseButtons: set[siwin.MouseButton] = {},
): NSEvent =
  result = newMouseEvent(
    nsEventTypeFromSiwin(event, mouseButtons),
    location,
    modifierFlagsFromSiwin(modifiers),
    timeIntervalSinceReferenceDate(),
    windowNumber,
    0,
  )
  if result.isNil:
    return
  result.xSiwinModifiers = modifiers
  result.xSiwinMouseButtons = mouseButtons
  result.xSiwinPressed = mouseButtons.len > 0
