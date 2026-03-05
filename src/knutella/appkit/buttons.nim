import ./runtime

import ./controls
import ./cells
import ./buttoncells
import ./events
import ./fonts

export controls

type NSButtonCallbackProc = proc(sender: IDPtr)

template buttonCell(self: untyped): NSButtonCell =
  NSButtonCell(self.cell())

objcImpl:
  type NSButton* = object of NSControl
    xButtonType {.get: buttonType.}: NSButtonType
    xOnClick: NSButtonCallbackProc

  method init*(self: var NSButton): NSButton =
    result = asTypeRaw[NSButton](callSuperIdFrom(NSButton, self, getSelector("init")))
    if result.isNil:
      return
    let cell = NSButtonCell.new()
    result.setCell(NSCell(cell))
    result.xButtonType = NSMomentaryLightButton

  method resignFirstResponder*(self: NSButton): bool =
    self.setNeedsDisplay(true)
    return callSuperAs[bool](self, getSelector("resignFirstResponder"))

  method isOpaque*(self: NSButton): bool =
    self.buttonCell().isOpaque()

  method isTransparent*(self: NSButton): bool =
    self.buttonCell().isTransparent()

  method keyEquivalent*(self: NSButton): NSString =
    self.buttonCell().keyEquivalent()

  method keyEquivalentModifierMask*(self: NSButton): int =
    self.buttonCell().keyEquivalentModifierMask()

  method image*(self: NSButton): NSImage =
    self.buttonCell().image()

  method imagePosition*(self: NSButton): NSCellImagePosition =
    self.buttonCell().imagePosition()

  method highlightsBy*(self: NSButton): set[NSCellMask] =
    self.buttonCell().highlightsBy()

  method showsStateBy*(self: NSButton): set[NSCellMask] =
    self.buttonCell().showsStateBy()

  method title*(self: NSButton): NSString =
    self.buttonCell().title()

  method state*(self: NSButton): NSCellState =
    self.buttonCell().state()

  method allowsMixedState*(self: NSButton): bool =
    self.buttonCell().allowsMixedState()

  method bezelStyle*(self: NSButton): NSBezelStyle =
    self.buttonCell().bezelStyle()

  method alternateTitle*(self: NSButton): NSString =
    self.buttonCell().alternateTitle()

  method alternateImage*(self: NSButton): NSImage =
    self.buttonCell().alternateImage()

  method attributedTitle*(self: NSButton): NSAttributedString =
    self.buttonCell().attributedTitle()

  method attributedAlternateTitle*(self: NSButton): NSAttributedString =
    self.buttonCell().attributedAlternateTitle()

  method showsBorderOnlyWhileMouseInside*(self: NSButton): bool =
    self.buttonCell().showsBorderOnlyWhileMouseInside()

  method setTransparent*(self: NSButton, value: bool) =
    self.buttonCell().setTransparent(value)
    self.setNeedsDisplay(true)

  method setKeyEquivalent*(self: NSButton, value: NSString) =
    self.buttonCell().setKeyEquivalent(value)
    self.setNeedsDisplay(true)

  method setKeyEquivalentModifierMask*(self: NSButton, value: int) =
    self.buttonCell().setKeyEquivalentModifierMask(value)

  method setImage*(self: NSButton, value: NSImage) =
    self.buttonCell().setImage(value)
    self.setNeedsDisplay(true)

  method setImagePosition*(self: NSButton, value: NSCellImagePosition) =
    self.buttonCell().setImagePosition(value)
    self.setNeedsDisplay(true)

  method setHighlightsBy*(self: NSButton, value: set[NSCellMask]) =
    self.buttonCell().setHighlightsBy(value)

  method setShowsStateBy*(self: NSButton, value: set[NSCellMask]) =
    self.buttonCell().setShowsStateBy(value)

  method setTitle*(self: NSButton, value: NSString) =
    self.buttonCell().setTitle(value)
    self.setNeedsDisplay(true)

  method font*(self: NSButton): NSFont =
    self.buttonCell().font()

  method setFont*(self: NSButton, value: NSFont) =
    self.buttonCell().setFont(value)
    self.setNeedsDisplay(true)

  method setState*(self: NSButton, value: int) =
    self.buttonCell().setState(value.NSCellState)
    self.setNeedsDisplay(true)

  method isHighlighted*(self: NSButton): bool =
    self.buttonCell().isHighlighted()

  method setHighlighted*(self: NSButton, value: bool) =
    self.buttonCell().setHighlighted(value)
    self.setNeedsDisplay(true)

  method setNextState*(self: NSButton) =
    self.buttonCell().setNextState()
    self.setNeedsDisplay(true)

  method setAllowsMixedState*(self: NSButton, value: bool) =
    self.buttonCell().setAllowsMixedState(value)

  method setBezelStyle*(self: NSButton, value: NSBezelStyle) =
    self.buttonCell().setBezelStyle(value)
    self.setNeedsDisplay(true)

  method setAlternateTitle*(self: NSButton, value: NSString) =
    self.buttonCell().setAlternateTitle(value)
    self.setNeedsDisplay(true)

  method setAlternateImage*(self: NSButton, value: NSImage) =
    self.buttonCell().setAlternateImage(value)
    self.setNeedsDisplay(true)

  method setAttributedTitle*(self: NSButton, value: NSAttributedString) =
    self.buttonCell().setAttributedTitle(value)
    self.setNeedsDisplay(true)

  method setAttributedAlternateTitle*(self: NSButton, value: NSAttributedString) =
    self.buttonCell().setAttributedAlternateTitle(value)
    self.setNeedsDisplay(true)

  method setShowsBorderOnlyWhileMouseInside*(self: NSButton, value: bool) =
    self.buttonCell().setShowsBorderOnlyWhileMouseInside(value)
    self.setNeedsDisplay(true)

  method performClick*(self: NSButton, sender: NSResponder) =
    self.highlight(true)
    let cell = self.buttonCell()
    cell.setState(cell.nextState())
    discard self.sendAction(self.action, self.target())
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
    if event.charactersIgnoringModifiers() == @ns" ":
      self.performClick(NSResponder(value: nil))
    else:
      discard callSuperAs[IDPtr, NSEvent](self, getSelector("keyDown:"), event)

  method onClick*(self: NSButton, sender: NSObject) =
    discard sender
    let cb = self.xOnClick
    if not cb.isNil:
      cb(self.value)

  method setPeriodicDelay*(
      self: NSButton, delay: float32, interval {.kw("interval").}: float32
  ) =
    self.buttonCell().setPeriodicDelay(max(delay, 0.0), interval = max(interval, 0.0))

  method periodicDelay*(self: NSButton): float32 =
    var delay = 0.0'f32
    self.buttonCell().getPeriodicDelay(addr delay, interval = nil)
    delay

  method periodicInterval*(self: NSButton): float32 =
    var interval = 0.0'f32
    self.buttonCell().getPeriodicDelay(nil, interval = addr interval)
    interval

  method setButtonType*(self: NSButton, value: NSButtonType) =
    self.xButtonType = value
    self.buttonCell().setButtonType(value)
    self.setNeedsDisplay(true)

  method highlight*(self: NSButton, value: bool) =
    self.buttonCell().highlight(value, self.bounds(), self.NSView)
    self.setNeedsDisplay(true)

  method setTitleWithMnemonic*(self: NSButton, value: NSString) =
    self.setTitle(value)

  method xSetFontFamilyName*(self: NSButton, familyName: NSString) =
    if familyName.isNil or familyName == NSNoSelectionMarker or
        familyName == NSMultipleValuesMarker or familyName == NSNotApplicableMarker:
      return

    let currentFont = self.font()
    let size = currentFont.pointSize()

    let newFont = NSFont.fontWithName(familyName, size = size)
    if newFont.notNil:
      self.setFont(newFont)

  method dealloc(self: NSButton) {.used.} =
    self.xOnClick = nil
    discard callSuperIdFrom(NSButton, self, getSelector("dealloc"))

proc new*(t: typedesc[NSButton]): NSButton =
  var allocated = NSButton.alloc()
  result = initOwned(move(allocated))

proc setTitle*(button: NSButton, value: string) =
  button.setTitle(ns(value))

proc setOnClick*(button: NSButton, cb: proc(sender: NSButton)) =
  if cb.isNil:
    button.xOnClick = nil
    button.setTarget(ID(value: nil))
    button.setAction(nil)
  else:
    button.xOnClick = proc(sender: IDPtr) =
      cb(NSButton(value: sender))
    button.setTarget(ID(value: button.value))
    button.setAction(getSelector("onClick:"))

proc click*(button: NSButton) =
  if not button.isEnabled():
    return
  button.performClick(NSResponder(value: nil))

proc getPeriodicDelay*(button: NSButton, delay: var float32, interval: var float32) =
  if button.isNil:
    delay = 0.0
    interval = 0.0
    return
  delay = button.periodicDelay()
  interval = button.periodicInterval()
