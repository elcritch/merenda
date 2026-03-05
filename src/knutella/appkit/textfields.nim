import ./runtime
import ./controls
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

  method selectText*(self: NSTextField, sender: NSResponder) =
    discard

  method setTitleWithMnemonic*(self: NSTextField, value: NSString) =
    self.setStringValue(stripMnemonicMarkers(value))

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
    drawValue.drawInRect(textRect)

  method dealloc(self: NSTextField) {.used.} =
    self.xPreviousText = nil
    self.xNextText = nil
    self.xStringValue = NSString(value: nil)
    self.xDelegate = nil
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
