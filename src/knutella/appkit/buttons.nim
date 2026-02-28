import ./runtime

import ./controls
import ./cells

export controls

type NSButtonCallbackProc = proc(sender: IDPtr)

objcImpl:
  type NSButton* = object of NSControl
    title {.set: setTitle.}: NSString
    alternateTitle {.set: setAlternateTitle.}: NSString
    keyEquivalent {.set: setKeyEquivalent.}: NSString

    bordered {.get: isBordered.}: bool
    bezeled {.get: isBezeled.}: bool
    bezelStyle {.set: setBezelStyle.}: int # NSBezelStyle

    stateValue {.get: state.}: int
    mixedAllowed {.get: allowsMixedState.}: bool
    transparent {.set: setTransparent, get: isTransparent.}: bool
    keyEquivalentModifierMask {.set: setKeyEquivalentModifierMask.}: int
      # NSEventModifierFlags

    imagePos {.set: setImagePosition, get: imagePosition.}: int

    showBorderInside {.
      set: setShowsBorderOnlyWhileMouseInside, get: showsBorderOnlyWhileMouseInside
    .}: bool
    xButtonType: cint
    xHighlighted {.set: setHighlighted, get: isHighlighted.}: bool
    xHighlightsBy {.set: setHighlightsBy, get: highlightsBy.}: int
    xShowsStateBy {.set: setShowsStateBy, get: showsStateBy.}: int
    periodicDelaySec: float32
    periodicIntervalSec: float32
    onClick: NSButtonCallbackProc

  template syncButtonCellFromView(self: NSButton) =
    if self.isNil:
      return
    let control = asRetainedType[NSControl](self)
    var selected = control.cell()
    if selected.isNil or (not selected.isKindOfClass(NSButtonCell)):
      var created = NSButtonCell.new()
      control.setCell(ownFromId[NSCell](created.value))
      selected = ownFromId[NSCell](created.value)
      created.value = nil
    if selected.isNil:
      return
    let cell = asRetainedType[NSButtonCell](selected)
    if cell.isNil:
      return
    cell.setControlView(asRetainedType[NSView](self))
    cell.setTitle(self.title)
    cell.setAlternateTitle(self.alternateTitle)
    cell.setKeyEquivalent(self.keyEquivalent)
    cell.setButtonType(self.xButtonType)
    cell.setBordered(self.bordered)
    cell.setBezeled(self.bezeled)
    cell.setBezelStyle(self.bezelStyle)
    cell.setImagePosition(self.imagePos)
    cell.setTransparent(self.transparent)
    cell.setKeyEquivalentModifierMask(self.keyEquivalentModifierMask)
    cell.setShowsBorderOnlyWhileMouseInside(self.showBorderInside)
    cell.setHighlightsBy(self.xHighlightsBy)
    cell.setShowsStateBy(self.xShowsStateBy)
    cell.setAllowsMixedState(self.mixedAllowed)
    cell.setState(self.stateValue)
    cell.setHighlighted(self.xHighlighted)
    cell.setPeriodicDelay(self.periodicDelaySec, interval = self.periodicIntervalSec)

  method init*(self: var NSButton): NSButton =
    result = asTypeRaw[NSButton](callSuperIdFrom(NSButton, self, getSelector("init")))
    if result.isNil:
      return
    result.setEnabled(true)
    result.setAlignment(NSCenterTextAlignment)
    result.title = @ns"Button"
    result.stateValue = NSOffState
    result.mixedAllowed = false
    result.bordered = true
    result.bezeled = true
    result.transparent = false
    result.keyEquivalent = @ns""
    result.keyEquivalentModifierMask = 0
    result.imagePos = 0
    result.bezelStyle = 0
    result.alternateTitle = @ns""
    result.showBorderInside = false
    result.xButtonType = NSMomentaryPushInButton.cint
    result.xHighlighted = false
    result.xHighlightsBy = NSPushInCellMask
    result.xShowsStateBy = NSNoCellMask
    result.periodicDelaySec = 0.0
    result.periodicIntervalSec = 0.0
    result.onClick = nil
    var buttonCell = NSButtonCell.new()
    asRetainedType[NSControl](result).setCell(ownFromId[NSCell](buttonCell.value))
    buttonCell.value = nil
    result.syncButtonCellFromView()

  method initWithFrame*(
      self: var NSButton,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSButton =
    result = self.init()
    if result.isNil:
      return
    asRetainedType[NSView](result).setFrame(
      x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0)
    )

  method setState*(self: NSButton, value: cint) =
    self.stateValue = normalizeButtonState(value.int, self.mixedAllowed)
    self.syncButtonCellFromView()
    self.setNeedsDisplay(true)

  method setAllowsMixedState*(self: NSButton, value: bool) =
    self.mixedAllowed = value
    self.stateValue = normalizeButtonState(self.stateValue, value)
    self.syncButtonCellFromView()
    self.setNeedsDisplay(true)

  method setNextState*(self: NSButton) =
    if self.mixedAllowed:
      case self.stateValue
      of NSOffState:
        self.stateValue = NSOnState
      of NSOnState:
        self.stateValue = NSMixedState
      else:
        self.stateValue = NSOffState
    else:
      if self.stateValue == NSOnState:
        self.stateValue = NSOffState
      else:
        self.stateValue = NSOnState
    self.syncButtonCellFromView()
    self.setNeedsDisplay(true)

  method stringValue*(self: NSButton): NSString =
    self.title()

  method setStringValue*(self: NSButton, value: NSString) =
    self.setTitle(value)

  method intValue*(self: NSButton): cint =
    self.state().cint

  method integerValue*(self: NSButton): int =
    self.state()

  method floatValue*(self: NSButton): float32 =
    self.state().float32

  method doubleValue*(self: NSButton): float =
    self.state().float

  method setIntValue*(self: NSButton, value: cint) =
    self.setState(value)

  method setIntegerValue*(self: NSButton, value: int) =
    self.setState(value.cint)

  method setFloatValue*(self: NSButton, value: float32) =
    self.setState(value.int.cint)

  method setDoubleValue*(self: NSButton, value: float) =
    self.setState(value.int.cint)

  method performClick*(self: NSButton, sender: NSResponder) =
    if not self.isEnabled():
      return
    self.setNextState()
    let control = asRetainedType[NSControl](self)
    discard control.sendAction(control.action(), control.target())
    let cb = self.onClick()
    if cb.isNil:
      return
    cb(self.value)

  method setPeriodicDelay*(
      self: NSButton, delay: float32, interval {.kw("interval").}: float32
  ) =
    self.periodicDelaySec = max(delay, 0.0)
    self.periodicIntervalSec = max(interval, 0.0)

  method periodicDelay*(self: NSButton): float32 =
    self.periodicDelaySec

  method periodicInterval*(self: NSButton): float32 =
    self.periodicIntervalSec

  method setButtonType*(self: NSButton, value: cint) =
    self.xButtonType = value
    case value.int
    of NSMomentaryLightButton:
      self.xHighlightsBy = NSChangeBackgroundCellMask
      self.xShowsStateBy = NSNoCellMask
    of NSMomentaryPushInButton:
      self.xHighlightsBy = NSPushInCellMask or NSChangeGrayCellMask
      self.xShowsStateBy = NSNoCellMask
    of NSMomentaryChangeButton:
      self.xHighlightsBy = NSContentsCellMask
      self.xShowsStateBy = NSNoCellMask
    of NSPushOnPushOffButton:
      self.xHighlightsBy = NSPushInCellMask or NSChangeGrayCellMask
      self.xShowsStateBy = NSChangeBackgroundCellMask
    of NSOnOffButton:
      self.xHighlightsBy = NSChangeBackgroundCellMask or NSChangeGrayCellMask
      self.xShowsStateBy = NSChangeBackgroundCellMask or NSChangeGrayCellMask
    of NSToggleButton:
      self.xHighlightsBy = NSPushInCellMask or NSContentsCellMask
      self.xShowsStateBy = NSContentsCellMask
    of NSSwitchButton, NSRadioButton:
      self.xHighlightsBy = NSContentsCellMask
      self.xShowsStateBy = NSContentsCellMask
      self.imagePos = NSImageLeft
      self.bordered = false
      self.bezeled = false
      self.setAlignment(NSLeftTextAlignment)
    else:
      discard
    self.syncButtonCellFromView()
    self.setNeedsDisplay(true)

  method buttonType*(self: NSButton): cint =
    self.xButtonType

  method highlight*(self: NSButton, value: bool) =
    self.xHighlighted = value
    self.syncButtonCellFromView()
    self.setNeedsDisplay(true)

  method drawRect*(self: NSButton, rect: NSRect) =
    discard rect
    if self.isNil:
      return
    self.syncButtonCellFromView()
    let selected = asRetainedType[NSControl](self).cell()
    if selected.isNil:
      return
    selected.setControlView(asRetainedType[NSView](self))
    selected.drawWithFrame(self.bounds(), asRetainedType[NSView](self))

  method setTitleWithMnemonic*(self: NSButton, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method dealloc(self: NSButton) {.used.} =
    self.onClick = nil
    discard callSuperIdFrom(NSButton, self, getSelector("dealloc"))

proc new*(t: typedesc[NSButton]): NSButton =
  var allocated = NSButton.alloc()
  result = initOwned(move(allocated))

proc setTitle*(button: NSButton, value: string) =
  button.setTitle(ns(value))

proc setOnClick*(button: NSButton, cb: proc(sender: NSButton)) =
  if cb.isNil:
    button.onClick = nil
  else:
    button.onClick = proc(sender: IDPtr) =
      cb(ownFromId[NSButton](sender))

proc click*(button: NSButton) =
  if not button.isEnabled():
    return
  button.setNextState()
  let control = asRetainedType[NSControl](button)
  discard control.sendAction(control.action(), control.target())
  let cb = button.onClick()
  if not cb.isNil:
    cb(button.value)

proc getPeriodicDelay*(button: NSButton, delay: var float32, interval: var float32) =
  if button.isNil:
    delay = 0.0
    interval = 0.0
    return
  delay = button.periodicDelay()
  interval = button.periodicInterval()
