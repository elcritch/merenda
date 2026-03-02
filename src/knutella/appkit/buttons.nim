import ./runtime

import ./controls
import ./cells
import ./buttoncells

export controls

type NSButtonCallbackProc = proc(sender: IDPtr)

objcImpl:
  type NSButton* = object of NSControl

  method resignFirstResponder*(self: NSButton): bool =
    self.setNeedsDisplay()
    return callSuperAs[NSControl, bool](self, getSelector("resignFirstResponder"))

  method setTitle*(self: NSButton, value: NSString) =
    self.setTitle(value)
    self.setNeedsDisplay(true)

  method setState*(self: NSButton, value: int) =
    self.xCell.setState(value)
    self.setNeedsDisplay(true)

  method setNextState*(self: NSButton) =
    self.xCell.setNextState()
    self.setNeedsDisplay(true)

  method setAllowsMixedState*(self: NSButton, value: bool) =
    self.xCell.setAllowsMixedState()

  method setBezelStyle*(self: NSButton, value: NSBezelStyle) =
    self.xCell.setBezelStyle(value)
    self.setNeedsDisplay(true)

  method setAlternateTitle*(self: NSButton, value: NSString) =
    self.xCell.setAlternateTitle(value)
    self.setNeedsDisplay(true)

  method setAlternateImage*(self: NSButton, value: NSString) =
    self.xCell.setAlternateImage(value)
    self.setNeedsDisplay(true)

  method setAttributedTitle*(self: NSButton, value: NSAttributedString) =
    self.xCell.setAttributedTitle(value)
    self.setNeedsDisplay(true)

  method setAttributedAlternateTitle*(self: NSButton, value: NSAttributedString) =
    self.xCell.setAttributedAlternateTitle(value)
    self.setNeedsDisplay(true)

  method performClick*(self: NSButton, sender: NSResponder) =
    self.highlight(true)
    self.xCell.setState(self.xCell.nextState())
    self.sendAction(self.action, to = self.target())
    self.highlight(false)

    #if not self.isEnabled():
    #  return
    #self.setNextState()
    #let control = self.NSControl
    #discard control.sendAction(control.action(), control.target())
    #let cb = self.onClick()
    #if cb.isNil:
    #  return
    #cb(self.value)

  method keyDown*(self: NSButton, event: NSEvent) =
    if event.charactersIgnoringModifiers().isEqualToString(@ns" "):
      self.performClick(nil)
    else:
      self.interpretKeyEvents(@ns[event])

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

  method setTitleWithMnemonic*(self: NSButton, value: NSString) =
    raise newException(NSException, "unimplemented")

  method xSetFontFamilyName*(self: NSButton, familyName: NSString) =
    if familyName.isNil or
        familyName == NSNoSelectionMarker
        familyName == NSMultipleValuesMarker
        familyName == NSNotApplicableMarker:
      return
    
    let currentFont = self.font()
    let size = currentFont.pointSize()

    let newFont = NSFont.fontWithName(familyName, size = size)
    if newFont.notNil:
      self.setFont(newFont)
  
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
  let control = button.NSControl
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
