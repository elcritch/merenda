import std/math

import ./runtime
import ./controls

proc scrollerRound(value: float32): float32 {.inline.} =
  floor(value + 0.5)

objcImpl:
  type NSScroller* = object of NSControl
    xTarget {.set: setTarget, get: target.}: ID
    xAction {.set: setAction, get: action.}: SEL
    xIsHoriz: bool
    xUsableParts {.get: usableParts.}: NSUsableScrollerParts
    xFloatValue {.get: floatValue.}: float32
    xKnobProportion {.get: knobProportion.}: float32
    xArrowsPosition {.set: setArrowsPosition, get: arrowsPosition.}:
      NSScrollArrowPosition
    xControlSize {.set: setControlSize, get: controlSize.}: NSControlSize
    xHitPart {.set: setHitPart, get: hitPart.}: NSScrollerPart
    xEnabled: bool
    xHighlighted: bool

  method init*(self: var NSScroller): NSScroller =
    result =
      asTypeRaw[NSScroller](callSuperIdFrom(NSScroller, self, getSelector("init")))
    if result.isNil:
      return
    result.xTarget.value = nil
    result.xAction = nil
    result.xFloatValue = 0.0
    result.xKnobProportion = 0.0
    result.xArrowsPosition = NSScrollerArrowsDefaultSetting
    result.xControlSize = NSRegularControlSize
    result.xHitPart = NSScrollerNoPart
    result.xEnabled = true
    result.xHighlighted = false
    result.xUsableParts = NSAllScrollerParts
    let bounds = result.bounds()
    result.xIsHoriz = bounds.size.width >= bounds.size.height

  method initWithFrame*(
      self: var NSScroller,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSScroller =
    result =
      asTypeRaw[NSScroller](callSuperIdFrom(NSScroller, self, getSelector("init")))
    if result.isNil:
      return
    result.setFrame(
      x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0)
    )
    result.xTarget.value = nil
    result.xAction = nil
    result.xFloatValue = 0.0
    result.xKnobProportion = 0.0
    result.xArrowsPosition = NSScrollerArrowsDefaultSetting
    result.xControlSize = NSRegularControlSize
    result.xHitPart = NSScrollerNoPart
    result.xEnabled = true
    result.xHighlighted = false
    result.xUsableParts = NSAllScrollerParts
    let bounds = result.bounds()
    result.xIsHoriz = bounds.size.width >= bounds.size.height

  method isFlipped*(self: NSScroller): bool =
    true

  method refusesFirstResponder*(self: NSScroller): bool =
    true

  method acceptsFirstResponder*(self: NSScroller): bool =
    false

  method setFrame*(
      self: NSScroller,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    var superObj =
      ObjcSuper(receiver: self.value, superClass: getClass(NSScroller).getSuperclass())
    cast[proc(
      superObj: var ObjcSuper,
      op: SEL,
      x: float32,
      y: float32,
      width: float32,
      height: float32,
    ) {.cdecl, varargs.}](objc_msgSendSuper)(
      superObj,
      getSelector("setFrame:y:width:height:"),
      x.float32,
      y.float32,
      max(width.float32, 0.0),
      max(height.float32, 0.0),
    )
    let bounds = self.bounds()
    self.xIsHoriz = bounds.size.width >= bounds.size.height
    self.checkSpaceForParts()

  method isVertical*(self: NSScroller): bool =
    not self.xIsHoriz

  method isEnabled*(self: NSScroller): bool =
    self.xEnabled

  method isHighlighted*(self: NSScroller): bool =
    self.xHighlighted

  method setFloatValue*(
      self: NSScroller,
      zeroToOneValue: float32,
      zeroToOneKnob {.kw("knobProportion").}: float32,
  ) =
    self.xFloatValue = clamp(zeroToOneValue, 0.0, 1.0)
    self.xKnobProportion = clamp(zeroToOneKnob, 0.0, 1.0)
    self.setNeedsDisplay(true)

  method doubleValue*(self: NSScroller): cdouble =
    self.xFloatValue.cdouble

  method setDoubleValue*(self: NSScroller, zeroToOneValue: cdouble) =
    self.xFloatValue = clamp(zeroToOneValue.float32, 0.0, 1.0)
    self.setNeedsDisplay(true)

  method frameOfDecrementPage*(self: NSScroller): NSRect =
    let knobSlot = self.rectForPart(NSScrollerKnobSlot)
    let knob = self.rectForPart(NSScrollerKnob)
    if knob.size.width <= 0.0 or knob.size.height <= 0.0:
      return nsRect(0.0, 0.0, 0.0, 0.0)
    result = knobSlot
    if self.isVertical():
      result.size.height = knob.origin.y - knobSlot.origin.y
      if result.size.height <= 0.0:
        result = nsRect(0.0, 0.0, 0.0, 0.0)
    else:
      result.size.width = knob.origin.x - knobSlot.origin.x
      if result.size.width <= 0.0:
        result = nsRect(0.0, 0.0, 0.0, 0.0)

  method frameOfIncrementPage*(self: NSScroller): NSRect =
    let knobSlot = self.rectForPart(NSScrollerKnobSlot)
    let knob = self.rectForPart(NSScrollerKnob)
    if knob.size.width <= 0.0 or knob.size.height <= 0.0:
      return nsRect(0.0, 0.0, 0.0, 0.0)
    result = knobSlot
    if self.isVertical():
      result.origin.y = knob.origin.y + knob.size.height
      result.size.height = (knobSlot.origin.y + knobSlot.size.height) - result.origin.y
      if result.size.height <= 0.0:
        result = nsRect(0.0, 0.0, 0.0, 0.0)
    else:
      result.origin.x = knob.origin.x + knob.size.width
      result.size.width = (knobSlot.origin.x + knobSlot.size.width) - result.origin.x
      if result.size.width <= 0.0:
        result = nsRect(0.0, 0.0, 0.0, 0.0)

  method rectForPart*(self: NSScroller, part: NSScrollerPart): NSRect =
    let bounds = self.bounds()
    var decLine = bounds
    var incLine = bounds
    var knobSlot = bounds
    var knob = nsRect(0.0, 0.0, 0.0, 0.0)

    if self.isVertical():
      if self.xArrowsPosition == NSScrollerArrowsNone:
        decLine = nsRect(0.0, 0.0, 0.0, 0.0)
        incLine = nsRect(0.0, 0.0, 0.0, 0.0)
      else:
        decLine.size.height = decLine.size.width
        if decLine.size.height * 2.0 > bounds.size.height:
          decLine.size.height = floor(bounds.size.height / 2.0)
        incLine = decLine
        incLine.origin.y = bounds.size.height - incLine.size.height
      knobSlot.origin.y += decLine.size.height
      knobSlot.size.height -= decLine.size.height + incLine.size.height

      knob = knobSlot
      knob.size.height = scrollerRound(knobSlot.size.height * self.xKnobProportion)
      if knob.size.height < knob.size.width:
        knob.size.height = knob.size.width
      knob.origin.y +=
        floor((knobSlot.size.height - knob.size.height) * self.xFloatValue)
      if floor(knob.size.height) >= floor(knobSlot.size.height):
        knob = nsRect(0.0, 0.0, 0.0, 0.0)
    else:
      if self.xArrowsPosition == NSScrollerArrowsNone:
        decLine = nsRect(0.0, 0.0, 0.0, 0.0)
        incLine = nsRect(0.0, 0.0, 0.0, 0.0)
      else:
        decLine.size.width = decLine.size.height
        if decLine.size.width * 2.0 > bounds.size.width:
          decLine.size.width = floor(bounds.size.width / 2.0)
        incLine = decLine
        incLine.origin.x = bounds.size.width - incLine.size.width
      knobSlot.origin.x += decLine.size.width
      knobSlot.size.width -= decLine.size.width + incLine.size.width

      knob = knobSlot
      knob.size.width = scrollerRound(knobSlot.size.width * self.xKnobProportion)
      if knob.size.width < knob.size.height:
        knob.size.width = knob.size.height
      knob.origin.x += floor((knobSlot.size.width - knob.size.width) * self.xFloatValue)
      if floor(knob.size.width) >= floor(knobSlot.size.width):
        knob = nsRect(0.0, 0.0, 0.0, 0.0)

    result =
      case part
      of NSScrollerNoPart:
        nsRect(0.0, 0.0, 0.0, 0.0)
      of NSScrollerKnob:
        if self.isEnabled():
          knob
        else:
          nsRect(0.0, 0.0, 0.0, 0.0)
      of NSScrollerKnobSlot:
        knobSlot
      of NSScrollerIncrementLine:
        incLine
      of NSScrollerDecrementLine:
        decLine
      of NSScrollerIncrementPage:
        self.frameOfIncrementPage()
      of NSScrollerDecrementPage:
        self.frameOfDecrementPage()

  method checkSpaceForParts*(self: NSScroller) =
    self.xUsableParts = NSAllScrollerParts

  method setEnabled*(self: NSScroller, flag: bool) =
    self.xEnabled = flag
    self.setNeedsDisplay(true)

  method highlight*(self: NSScroller, flag: bool) =
    if self.xHighlighted != flag:
      self.xHighlighted = flag
      self.setNeedsDisplay(true)

  method drawKnobSlotInRect*(
      self: NSScroller, rect: NSRect, flag {.kw("highlight").}: bool
  ) =
    discard self
    discard rect
    discard flag

  method drawParts*(self: NSScroller) =
    discard

  method drawArrow*(
      self: NSScroller, arrow: NSScrollerArrow, flag {.kw("highlight").}: bool
  ) =
    discard self
    discard arrow
    discard flag

  method drawKnob*(self: NSScroller) =
    discard

  method testPart*(self: NSScroller, point: NSPoint): NSScrollerPart =
    for candidate in [
      NSScrollerDecrementLine, NSScrollerIncrementLine, NSScrollerDecrementPage,
      NSScrollerIncrementPage, NSScrollerKnob, NSScrollerKnobSlot,
    ]:
      if self.rectForPart(candidate).contains(point.x, point.y):
        return candidate
    NSScrollerNoPart

  method trackKnob*(self: NSScroller, event: NSEvent) =
    discard self
    discard event

  method trackScrollButtons*(self: NSScroller, event: NSEvent) =
    discard self
    discard event

  method dealloc(self: NSScroller) {.used.} =
    self.xTarget.value = nil
    self.xAction = nil
    destroyIvarFields(self)
    discard callSuperIdFrom(NSScroller, self, getSelector("dealloc"))

proc scrollerWidth*(t: typedesc[NSScroller]): float32 =
  discard
  result = 15.0

proc new*(t: typedesc[NSScroller]): NSScroller =
  var allocated = NSScroller.alloc()
  result = initOwned(move(allocated))
