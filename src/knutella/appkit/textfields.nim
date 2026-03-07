import std/unicode

import ./runtime
import ./controls
import ./windows
import ./graphics
import ./colors
import ./attributedstrings

proc insetRect(rect: NSRect, dx: float32, dy: float32): NSRect {.inline.} =
  nsRect(
    rect.origin.x + dx,
    rect.origin.y + dy,
    max(rect.size.width - dx * 2.0, 0.0),
    max(rect.size.height - dy * 2.0, 0.0),
  )

proc clampInsertionIndex(text: string, index: int): int {.inline.} =
  max(0, min(index, text.runeLen))

proc clampIndex(total: int, index: int): int {.inline.} =
  max(0, min(index, total))

proc selectionBounds(
    total: int, anchor: int, cursor: int
): tuple[start: int, stop: int] =
  let clampedAnchor = clampIndex(total, anchor)
  let clampedCursor = clampIndex(total, cursor)
  result.start = min(clampedAnchor, clampedCursor)
  result.stop = max(clampedAnchor, clampedCursor)

proc insertionPrefixWidth(text: string, insertionIndex: int): float32 =
  let clamped = clampInsertionIndex(text, insertionIndex)
  if clamped <= 0:
    return 0.0
  var prefixAlloc = NSAttributedString.alloc()
  let prefixValue = prefixAlloc.initWithString(ns(text.runeSubStr(0, clamped)))
  prefixAlloc.value = nil
  if prefixValue.isNil:
    return 0.0
  prefixValue.size().width

objcImpl:
  type NSTextField* = object of NSControl
    xStringValue {.set: setStringValue, get: stringValue.}: NSString
    xDelegate {.set: setDelegate, get: delegate.}: IDPtr
    xErrorAction: SEL
    editable {.set: setEditable, get: isEditable.}: bool
    selectable {.set: setSelectable, get: isSelectable.}: bool
    bordered {.set: setBordered, get: isBordered.}: bool
    bezeled {.set: setBezeled, get: isBezeled.}: bool
    txtColor {.set: setTextColor, get: textColor.}: NSColor
    bgColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    drawsBg {.set: setDrawsBackground, get: drawsBackground.}: bool
    scrollable {.set: setScrollable, get: isScrollable.}: bool
    xPreviousText {.set: setPreviousText, get: previousText.}: IDPtr
    xNextText {.set: setNextText, get: nextText.}: IDPtr
    xInsertionPoint {.set: setInsertionPoint, get: insertionPoint.}: NSInteger
    xSelectionAnchor {.set: setSelectionAnchor, get: selectionAnchor.}: NSInteger

  method init*(self: var NSTextField): NSTextField =
    result =
      asTypeRaw[NSTextField](callSuperIdFrom(NSTextField, self, getSelector("init")))
    if result.isNil:
      return
    result.setEnabled(true)
    result.editable = true
    result.selectable = true
    result.scrollable = true
    result.bordered = true
    result.bezeled = true
    result.setAlignment(NSNaturalTextAlignment)
    result.xStringValue = @ns""
    result.xDelegate = nil
    result.xErrorAction = nil
    result.txtColor = nsColor(0.08, 0.08, 0.08, 1.0)
    result.bgColor = nsColor(0.98, 0.99, 1.0, 1.0)
    result.drawsBg = true
    result.xPreviousText = nil
    result.xNextText = nil
    result.xInsertionPoint = 0
    result.xSelectionAnchor = 0

  method initWithFrame*(
      self: var NSTextField,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSTextField =
    result = self.init()
    if result.isNil:
      return
    result.to(NSView).setFrame(
      nsRect(
        x.float32, y.float32, max(width.float32, 0.0'f32), max(height.float32, 0.0'f32)
      )
    )

  method setTextColor*(
      self: NSTextField,
      r: float32,
      g {.kw("green").}: float32,
      b {.kw("blue").}: float32,
      a {.kw("alpha").}: float32,
  ) =
    self.txtColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setBackgroundColor*(
      self: NSTextField,
      r: float32,
      g {.kw("green").}: float32,
      b {.kw("blue").}: float32,
      a {.kw("alpha").}: float32,
  ) =
    self.bgColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method acceptsFirstResponder*(self: NSTextField): bool =
    if self.isNil or not self.isEnabled():
      return false
    (self.isEditable() or self.isSelectable()) and (not self.refusesFirstResponder())

  method becomeFirstResponder*(self: NSTextField): bool =
    if self.isNil:
      return false
    if not callSuperAs[bool](self, getSelector("becomeFirstResponder")):
      return false
    self.selectText(NSResponder(value: nil))
    true

  method resignFirstResponder*(self: NSTextField): bool =
    if self.isNil:
      return false
    let resigned = callSuperAs[bool](self, getSelector("resignFirstResponder"))
    if resigned:
      self.setNeedsDisplay(true)
    resigned

  method mouseDown*(self: NSTextField, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    let window = self.window()
    if not window.isNil:
      discard window.makeFirstResponder(self.NSResponder)
    let cursor = ($self.stringValue()).runeLen
    self.xInsertionPoint = cursor.NSInteger
    self.xSelectionAnchor = cursor.NSInteger
    self.setNeedsDisplay(true)

  method selectText*(self: NSTextField, sender: NSResponder) =
    if self.isNil:
      return
    let total = ($self.stringValue()).runeLen
    self.xSelectionAnchor = 0
    self.xInsertionPoint = total.NSInteger
    self.setNeedsDisplay(true)

  method selectedRange*(self: NSTextField): NSRange =
    if self.isNil:
      return NSMakeRange(0, 0)
    let value = $self.stringValue()
    let total = value.runeLen
    let cursor = clampIndex(total, self.insertionPoint().int)
    let selected = selectionBounds(total, self.selectionAnchor().int, cursor)
    NSMakeRange(selected.start.uint, (selected.stop - selected.start).uint)

  method setSelectedRange*(self: NSTextField, value: NSRange) =
    if self.isNil:
      return
    let total = ($self.stringValue()).runeLen
    let start = clampIndex(total, value.location.int)
    let length = clampIndex(total - start, value.length.int)
    self.xSelectionAnchor = start.NSInteger
    self.xInsertionPoint = (start + length).NSInteger
    self.setNeedsDisplay(true)

  method setTitleWithMnemonic*(self: NSTextField, value: NSString) =
    self.setStringValue(stripMnemonicMarkers(value))

  method insertText*(self: NSTextField, text: NSObject) =
    if self.isNil or not self.isEditable() or text.isNil:
      return
    let insertValue =
      if text.isKindOfClass(NSString):
        NSString(text)
      elif text.isKindOfClass(NSAttributedString):
        NSAttributedString(text).string()
      else:
        ns($text)
    let insertion = $insertValue
    if insertion.len == 0:
      return
    let current = $self.stringValue()
    let total = current.runeLen
    let cursor = clampIndex(total, self.insertionPoint().int)
    let selected = selectionBounds(total, self.selectionAnchor().int, cursor)
    let replaceStart = selected.start
    let replaceStop = selected.stop
    self.xStringValue = ns(
      current.runeSubStr(0, replaceStart) & insertion & current.runeSubStr(replaceStop)
    )
    let nextCursor = replaceStart + insertion.runeLen
    self.xInsertionPoint = nextCursor.NSInteger
    self.xSelectionAnchor = nextCursor.NSInteger
    self.setNeedsDisplay(true)

  method doCommandBySelector*(self: NSTextField, action: SEL) =
    if self.isNil:
      return
    let deleteBackwardSel = getSelector("deleteBackward:")
    let deleteForwardSel = getSelector("deleteForward:")
    let moveLeftSel = getSelector("moveLeft:")
    let moveRightSel = getSelector("moveRight:")
    let moveBeginningSel = getSelector("moveToBeginningOfLine:")
    let moveEndSel = getSelector("moveToEndOfLine:")
    let moveLeftModifySel = getSelector("moveLeftAndModifySelection:")
    let moveRightModifySel = getSelector("moveRightAndModifySelection:")
    let moveBeginningModifySel = getSelector("moveToBeginningOfLineAndModifySelection:")
    let moveEndModifySel = getSelector("moveToEndOfLineAndModifySelection:")

    if action == deleteBackwardSel:
      if not self.isEditable():
        return
      let current = $self.stringValue()
      let total = current.runeLen
      let cursor = clampIndex(total, self.insertionPoint().int)
      let selected = selectionBounds(total, self.selectionAnchor().int, cursor)
      if selected.stop > selected.start:
        self.xStringValue =
          ns(current.runeSubStr(0, selected.start) & current.runeSubStr(selected.stop))
        self.xInsertionPoint = selected.start.NSInteger
        self.xSelectionAnchor = selected.start.NSInteger
        self.setNeedsDisplay(true)
        return
      if cursor <= 0:
        return
      self.xStringValue =
        ns(current.runeSubStr(0, cursor - 1) & current.runeSubStr(cursor))
      self.xInsertionPoint = (cursor - 1).NSInteger
      self.xSelectionAnchor = (cursor - 1).NSInteger
      self.setNeedsDisplay(true)
      return
    if action == deleteForwardSel:
      if not self.isEditable():
        return
      let current = $self.stringValue()
      let total = current.runeLen
      let cursor = clampIndex(total, self.insertionPoint().int)
      let selected = selectionBounds(total, self.selectionAnchor().int, cursor)
      if selected.stop > selected.start:
        self.xStringValue =
          ns(current.runeSubStr(0, selected.start) & current.runeSubStr(selected.stop))
        self.xInsertionPoint = selected.start.NSInteger
        self.xSelectionAnchor = selected.start.NSInteger
        self.setNeedsDisplay(true)
        return
      if cursor >= total:
        return
      self.xStringValue =
        ns(current.runeSubStr(0, cursor) & current.runeSubStr(cursor + 1))
      self.xInsertionPoint = cursor.NSInteger
      self.xSelectionAnchor = cursor.NSInteger
      self.setNeedsDisplay(true)
      return
    if action == moveLeftSel:
      if not self.isEditable() and not self.isSelectable():
        return
      let current = $self.stringValue()
      let total = current.runeLen
      let cursor = clampIndex(total, self.insertionPoint().int)
      let selected = selectionBounds(total, self.selectionAnchor().int, cursor)
      var nextCursor = cursor
      if selected.stop > selected.start:
        nextCursor = selected.start
      elif cursor > 0:
        nextCursor = cursor - 1
      self.xInsertionPoint = nextCursor.NSInteger
      self.xSelectionAnchor = nextCursor.NSInteger
      self.setNeedsDisplay(true)
      return
    if action == moveRightSel:
      if not self.isEditable() and not self.isSelectable():
        return
      let current = $self.stringValue()
      let total = current.runeLen
      let cursor = clampIndex(total, self.insertionPoint().int)
      let selected = selectionBounds(total, self.selectionAnchor().int, cursor)
      var nextCursor = cursor
      if selected.stop > selected.start:
        nextCursor = selected.stop
      elif cursor < total:
        nextCursor = cursor + 1
      self.xInsertionPoint = nextCursor.NSInteger
      self.xSelectionAnchor = nextCursor.NSInteger
      self.setNeedsDisplay(true)
      return
    if action == moveBeginningSel:
      if not self.isEditable() and not self.isSelectable():
        return
      self.xInsertionPoint = 0
      self.xSelectionAnchor = 0
      self.setNeedsDisplay(true)
      return
    if action == moveEndSel:
      if not self.isEditable() and not self.isSelectable():
        return
      let total = ($self.stringValue()).runeLen
      self.xInsertionPoint = total.NSInteger
      self.xSelectionAnchor = total.NSInteger
      self.setNeedsDisplay(true)
      return
    if action == moveLeftModifySel:
      if not self.isEditable() and not self.isSelectable():
        return
      let value = $self.stringValue()
      let total = value.runeLen
      let cursor = clampIndex(total, self.insertionPoint().int)
      let anchor = clampIndex(total, self.selectionAnchor().int)
      if cursor <= 0:
        return
      self.xSelectionAnchor = anchor.NSInteger
      self.xInsertionPoint = (cursor - 1).NSInteger
      self.setNeedsDisplay(true)
      return
    if action == moveRightModifySel:
      if not self.isEditable() and not self.isSelectable():
        return
      let value = $self.stringValue()
      let total = value.runeLen
      let cursor = clampIndex(total, self.insertionPoint().int)
      let anchor = clampIndex(total, self.selectionAnchor().int)
      if cursor >= total:
        return
      self.xSelectionAnchor = anchor.NSInteger
      self.xInsertionPoint = (cursor + 1).NSInteger
      self.setNeedsDisplay(true)
      return
    if action == moveBeginningModifySel:
      if not self.isEditable() and not self.isSelectable():
        return
      let value = $self.stringValue()
      let total = value.runeLen
      let anchor = clampIndex(total, self.selectionAnchor().int)
      self.xSelectionAnchor = anchor.NSInteger
      self.xInsertionPoint = 0
      self.setNeedsDisplay(true)
      return
    if action == moveEndModifySel:
      if not self.isEditable() and not self.isSelectable():
        return
      let value = $self.stringValue()
      let total = value.runeLen
      let anchor = clampIndex(total, self.selectionAnchor().int)
      self.xSelectionAnchor = anchor.NSInteger
      self.xInsertionPoint = total.NSInteger
      self.setNeedsDisplay(true)
      return

    callSuperVoid(self, getSelector("doCommandBySelector:"), action)

  method drawRect*(self: NSTextField, rect: NSRect) =
    discard rect
    if self.isNil:
      return
    let bounds = self.bounds()
    var textRect =
      if self.isBezeled():
        insetRect(bounds, 3.0, 3.0)
      elif self.isBordered():
        insetRect(bounds, 2.0, 2.0)
      else:
        insetRect(bounds, 2.0, 0.0)
    var valueRect = textRect

    if self.isBezeled():
      NSDrawWhiteBezel(bounds, bounds)
      valueRect = insetRect(valueRect, -1.0, -1.0)
    elif self.isBordered():
      NSFrameRect(bounds)
      valueRect = insetRect(valueRect, -1.0, -1.0)

    if self.drawsBackground():
      self.backgroundColor().setFill()
      NSRectFill(valueRect)

    var drawValueAlloc = NSAttributedString.alloc()
    let drawValue = drawValueAlloc.initWithString(self.stringValue())
    drawValueAlloc.value = nil
    if drawValue.isNil:
      return
    let drawSize = drawValue.size()
    let textHeight = max(1.0, min(drawSize.height, textRect.size.height))
    let textY = textRect.origin.y + max((textRect.size.height - textHeight) * 0.5, 0.0)
    let textDrawRect = nsRect(textRect.origin.x, textY, textRect.size.width, textHeight)
    let window = self.window()
    var isFocused = false
    var cursor = 0
    var selected = (start: 0, stop: 0)
    var value = ""
    if not window.isNil:
      let firstResponder = window.firstResponder()
      isFocused = (not firstResponder.isNil) and firstResponder.value == self.value
    value = $self.stringValue()
    cursor = clampInsertionIndex(value, self.insertionPoint().int)
    selected = selectionBounds(value.runeLen, self.selectionAnchor().int, cursor)
    if isFocused and selected.stop > selected.start and
        (self.isEditable() or self.isSelectable()):
      discard drawValue.drawInRectWithSelection(
        textDrawRect,
        NSMakeRange(selected.start.uint, (selected.stop - selected.start).uint),
        NSColor.selectedTextBackgroundColor(),
      )
    else:
      drawValue.drawInRect(textDrawRect)

    if self.isEditable() and isFocused and selected.stop == selected.start:
      self.xInsertionPoint = cursor.NSInteger
      self.xSelectionAnchor = cursor.NSInteger
      var caretX = textRect.origin.x + insertionPrefixWidth(value, cursor)
      let minCaretX = textRect.origin.x
      let maxCaretX = textRect.origin.x + max(textRect.size.width - 1.0, 0.0)
      caretX = min(max(caretX, minCaretX), maxCaretX)
      self.textColor().setFill()
      NSRectFill(nsRect(caretX, textY, 1.0, textHeight))

  method hitTest*(self: NSTextField, point: NSPoint): NSView =
    if self.isHiddenOrHasHiddenAncestor():
      return NSView(value: nil)
    if not self.mouse(point, inRect = self.bounds()):
      return NSView(value: nil)
    if (not self.isEditable()) and (not self.isSelectable()) and
        cast[pointer](self.action()).isNil and self.target().isNil:
      return NSView(value: nil)
    self.NSView

  method dealloc(self: NSTextField) {.used.} =
    self.xPreviousText = nil
    self.xNextText = nil
    self.xStringValue = NSString(value: nil)
    self.xDelegate = nil
    self.xInsertionPoint = 0
    self.xSelectionAnchor = 0
    discard callSuperIdFrom(NSTextField, self, getSelector("dealloc"))

objcImpl:
  type NSSecureTextField* = object of NSTextField
    echosBullets {.set: setEchosBullets, get: echosBullets.}: bool

  method init*(self: var NSSecureTextField): NSSecureTextField =
    result = asTypeRaw[NSSecureTextField](
      callSuperIdFrom(NSSecureTextField, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.echosBullets = true

objcImpl:
  type NSSearchField* = object of NSTextField
    xRecentSearches {.set: setRecentSearches, get: recentSearches.}: NSArray[NSString]
    xRecentsAutosaveName {.set: setRecentsAutosaveName, get: recentsAutosaveName.}:
      NSString

  method init*(self: var NSSearchField): NSSearchField =
    result = asTypeRaw[NSSearchField](
      callSuperIdFrom(NSSearchField, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xRecentSearches = nsArray[NSString]()
    result.xRecentsAutosaveName = @ns""

  method dealloc(self: NSSearchField) {.used.} =
    self.xRecentSearches = NSArray[NSString](value: nil)
    self.xRecentsAutosaveName = NSString(value: nil)
    discard callSuperIdFrom(NSSearchField, self, getSelector("dealloc"))

proc new*(t: typedesc[NSTextField]): NSTextField =
  var allocated = NSTextField.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSSecureTextField]): NSSecureTextField =
  var allocated = NSSecureTextField.alloc()
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSSearchField]): NSSearchField =
  var allocated = NSSearchField.alloc()
  result = initOwned(move(allocated))
