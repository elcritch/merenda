import std/unicode

import ./runtime
import ./events
import siwin/window as siwin

proc responderBeep() =
  stdout.write('\a')
  stdout.flushFile()

proc firstRuneCode(text: NSString): int =
  if text.isNil:
    return -1
  let value = $text
  if value.len == 0:
    return -1
  for rune in value.runes:
    return rune.int
  -1

proc keyCommandSelector(event: NSEvent): SEL =
  if event.isNil:
    return nil
  let flags = event.modifierFlags()
  let extendsSelection = NSShiftKeyMask in flags
  let key = siwinKey(event)
  case key
  of siwin.Key.left:
    if extendsSelection:
      return getSelector("moveLeftAndModifySelection:")
    return getSelector("moveLeft:")
  of siwin.Key.right:
    if extendsSelection:
      return getSelector("moveRightAndModifySelection:")
    return getSelector("moveRight:")
  of siwin.Key.up:
    return getSelector("moveUp:")
  of siwin.Key.down:
    return getSelector("moveDown:")
  of siwin.Key.home:
    if extendsSelection:
      return getSelector("moveToBeginningOfLineAndModifySelection:")
    return getSelector("moveToBeginningOfLine:")
  of siwin.Key.End:
    if extendsSelection:
      return getSelector("moveToEndOfLineAndModifySelection:")
    return getSelector("moveToEndOfLine:")
  of siwin.Key.backspace:
    return getSelector("deleteBackward:")
  of siwin.Key.del:
    return getSelector("deleteForward:")
  of siwin.Key.enter:
    return getSelector("insertNewline:")
  of siwin.Key.tab:
    return getSelector("insertTab:")
  else:
    discard

  # Fallback for key events that arrive with function-key characters but
  # without a stable siwin key mapping (for example some repeat paths).
  let runeCode = block:
    let ignoringModifiers = firstRuneCode(event.charactersIgnoringModifiers())
    if ignoringModifiers >= 0:
      ignoringModifiers
    else:
      firstRuneCode(event.characters())
  case runeCode
  of 0xF700:
    getSelector("moveUp:")
  of 0xF701:
    getSelector("moveDown:")
  of 0xF702:
    if extendsSelection:
      getSelector("moveLeftAndModifySelection:")
    else:
      getSelector("moveLeft:")
  of 0xF703:
    if extendsSelection:
      getSelector("moveRightAndModifySelection:")
    else:
      getSelector("moveRight:")
  of 0xF729:
    if extendsSelection:
      getSelector("moveToBeginningOfLineAndModifySelection:")
    else:
      getSelector("moveToBeginningOfLine:")
  of 0xF72B:
    if extendsSelection:
      getSelector("moveToEndOfLineAndModifySelection:")
    else:
      getSelector("moveToEndOfLine:")
  of 0x08, 0x7F:
    getSelector("deleteBackward:")
  of 0x09:
    getSelector("insertTab:")
  of 0x0A, 0x0D:
    getSelector("insertNewline:")
  of 0xF728:
    getSelector("deleteForward:")
  else:
    nil

objcImpl:
  type NSResponder* = object of NSObject
    nextResp: NSResponder

  method init*(self: var NSResponder): NSResponder =
    result =
      asTypeRaw[NSResponder](callSuperIdFrom(NSResponder, self, getSelector("init")))
    if result.isNil:
      return
    result.nextResp = NSResponder(value: nil)

  method nextResponder*(self: NSResponder): NSResponder =
    if self.nextResp.isNil:
      return NSResponder(value: nil)
    retain(self.nextResp)

  method setNextResponder*(self: NSResponder, next: NSResponder) =
    if self.isNil:
      return
    self.nextResp = retain(next)

  method acceptsFirstResponder*(self: NSResponder): bool =
    false

  method becomeFirstResponder*(self: NSResponder): bool =
    true

  method resignFirstResponder*(self: NSResponder): bool =
    true

  method tryToPerform*(
      self: NSResponder, action: SEL, sender {.kw("with").}: NSObject
  ): bool =
    if self.isNil:
      return false
    var current = self
    var hopCount = 0
    while not current.isNil and hopCount < 4096:
      if performResponderSelector(current, action, sender):
        return true
      current = current.nextResponder()
      inc hopCount
    false

  method doCommandBySelector*(self: NSResponder, action: SEL) =
    if performResponderSelector(self.NSObject, action, self.NSObject):
      return
    let next = self.nextResponder()
    if not next.isNil and next.tryToPerform(action, self):
      return
    self.noResponderFor(action)

  method noResponderFor*(self: NSResponder, action: SEL) =
    if cast[pointer](action) == cast[pointer](getSelector("keyDown:")):
      responderBeep()

  method performKeyEquivalent*(self: NSResponder, event: NSEvent): bool =
    false

  method insertText*(self: NSResponder, text: NSObject) =
    let next = self.nextResponder()
    if not next.isNil:
      next.insertText(text)
      return
    self.noResponderFor(getSelector("insertText:"))

  method interpretKeyEvents*(self: NSResponder, events: seq[NSEvent]) =
    for event in events:
      if event.isNil:
        continue
      let command = keyCommandSelector(event)
      if cast[pointer](command) != nil:
        self.doCommandBySelector(command)
        continue
      let characters = event.characters()
      if not characters.isNil and ($characters).len > 0:
        self.insertText(characters.NSObject)
        continue
      let next = self.nextResponder()
      if not next.isNil:
        next.keyDown(event)
      else:
        self.noResponderFor(getSelector("keyDown:"))

  method mouseDown*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseDown(event)
      return
    self.noResponderFor(getSelector("mouseDown:"))

  method mouseUp*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseUp(event)
      return
    self.noResponderFor(getSelector("mouseUp:"))

  method rightMouseDown*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.rightMouseDown(event)
      return
    self.noResponderFor(getSelector("rightMouseDown:"))

  method rightMouseUp*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.rightMouseUp(event)
      return
    self.noResponderFor(getSelector("rightMouseUp:"))

  method otherMouseDown*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.otherMouseDown(event)
      return
    self.noResponderFor(getSelector("otherMouseDown:"))

  method otherMouseUp*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.otherMouseUp(event)
      return
    self.noResponderFor(getSelector("otherMouseUp:"))

  method mouseMoved*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseMoved(event)
      return
    self.noResponderFor(getSelector("mouseMoved:"))

  method mouseDragged*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseDragged(event)
      return
    self.noResponderFor(getSelector("mouseDragged:"))

  method rightMouseDragged*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.rightMouseDragged(event)
      return
    self.noResponderFor(getSelector("rightMouseDragged:"))

  method otherMouseDragged*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.otherMouseDragged(event)
      return
    self.noResponderFor(getSelector("otherMouseDragged:"))

  method mouseEntered*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseEntered(event)
      return
    self.noResponderFor(getSelector("mouseEntered:"))

  method mouseExited*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.mouseExited(event)
      return
    self.noResponderFor(getSelector("mouseExited:"))

  method cursorUpdate*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.cursorUpdate(event)
      return
    self.noResponderFor(getSelector("cursorUpdate:"))

  method keyDown*(self: NSResponder, event: NSEvent) =
    if event.isNil:
      self.noResponderFor(getSelector("keyDown:"))
      return
    self.interpretKeyEvents(@[event])

  method keyUp*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.keyUp(event)
      return
    self.noResponderFor(getSelector("keyUp:"))

  method flagsChanged*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.flagsChanged(event)
      return
    self.noResponderFor(getSelector("flagsChanged:"))

  method scrollWheel*(self: NSResponder, event: NSEvent) =
    let next = self.nextResponder()
    if not next.isNil:
      next.scrollWheel(event)
      return
    self.noResponderFor(getSelector("scrollWheel:"))

  method dealloc(self: NSResponder) {.used.} =
    self.nextResp = NSResponder(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSResponder, self, getSelector("dealloc"))
