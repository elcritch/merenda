import ./runtime
import ./controls

objcImpl:
  type NSTextField* = object of NSControl
    xxStringValue {.set: setStringValue, get: stringValue.}: NSString
    xxDelegate {.set: setDelegate, get: delegate.}: ID
    xxErrorAction: SEL
    editable {.set: setEditable, get: isEditable.}: bool
    selectable {.set: setSelectable, get: isSelectable.}: bool
    bordered {.set: setBordered, get: isBordered.}: bool
    bezeled {.set: setBezeled, get: isBezeled.}: bool
    txtColor {.set: setTextColor, get: textColor.}: NSColor
    bgColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    drawsBg {.set: setDrawsBackground, get: drawsBackground.}: bool
    scrollable {.set: setScrollable, get: isScrollable.}: bool
    xxPreviousText {.set: setPreviousText, get: previousText.}: ID
    xxNextText {.set: setNextText, get: nextText.}: ID

  method init*(self: var NSTextField): NSTextField =
    result =
      asType[NSTextField](callSuperIdFrom(NSTextField, self, getSelector("init")))
    if result.isNil:
      return
    result.setEnabled(true)
    result.editable = true
    result.selectable = true
    result.scrollable = true
    result.bordered = true
    result.bezeled = true
    result.alignment = NSNaturalTextAlignment
    result.xxStringValue = @ns""
    result.xxDelegate = nil
    result.xxErrorAction = nil
    result.txtColor = nsColor(0.08, 0.08, 0.08, 1.0)
    result.bgColor = nsColor(0.98, 0.99, 1.0, 1.0)
    result.drawsBg = true
    result.xxPreviousText = nil
    result.xxNextText = nil

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
    discard self
    discard sender

  method setTitleWithMnemonic*(self: NSTextField, value: NSString) =
    self.setStringValue(stripMnemonicMarkers(value))

  method dealloc(self: NSTextField) {.used.} =
    self.xxPreviousText = nil
    self.xxNextText = nil
    self.xxStringValue = NSString(value: nil)
    self.xxDelegate = nil
    discard callSuperIdFrom(NSTextField, self, getSelector("dealloc"))

objcImpl:
  type NSSecureTextField* = object of NSTextField
    echosBullets {.set: setEchosBullets, get: echosBullets.}: bool

  method init*(self: var NSSecureTextField): NSSecureTextField =
    result = asType[NSSecureTextField](
      callSuperIdFrom(NSSecureTextField, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.echosBullets = true

objcImpl:
  type NSSearchField* = object of NSTextField
    xxRecentSearches {.set: setRecentSearches, get: recentSearches.}: NSArray[NSString]
    xxRecentsAutosaveName {.set: setRecentsAutosaveName, get: recentsAutosaveName.}:
      NSString

  method init*(self: var NSSearchField): NSSearchField =
    result =
      asType[NSSearchField](callSuperIdFrom(NSSearchField, self, getSelector("init")))
    if result.isNil:
      return
    result.xxRecentSearches = nsArray[NSString]()
    result.xxRecentsAutosaveName = @ns""

  method dealloc(self: NSSearchField) {.used.} =
    self.xxRecentSearches = NSArray[NSString](value: nil)
    self.xxRecentsAutosaveName = NSString(value: nil)
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
