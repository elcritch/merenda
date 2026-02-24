import ./runtime
import ./controls

objcImpl:
  type NSTextField* = object of NSControl
    strValueId: ID
    editable {.set: setEditable, get: isEditable.}: bool
    selectable {.set: setSelectable, get: isSelectable.}: bool
    bordered {.set: setBordered, get: isBordered.}: bool
    bezeled {.set: setBezeled, get: isBezeled.}: bool
    txtColor {.set: setTextColor, get: textColor.}: NSColor
    bgColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    drawsBg {.set: setDrawsBackground, get: drawsBackground.}: bool
    scrollable {.set: setScrollable, get: isScrollable.}: bool
    prevTxt: ID
    nextTxt: ID

  method init*(self: var NSTextField): NSTextField =
    result =
      asType[NSTextField](callSuperIdFrom(NSTextField, self, getSelector("init")))
    if result.isNil:
      return
    result.setEnabled(true)
    result.setEditable(true)
    result.setSelectable(true)
    result.setScrollable(true)
    result.setBordered(true)
    result.setBezeled(true)
    result.setAlignment(NSNaturalTextAlignment)
    result.strValueId = retainId(@ns"".value)
    result.txtColor = nsColor(0.08, 0.08, 0.08, 1.0)
    result.bgColor = nsColor(0.98, 0.99, 1.0, 1.0)
    result.drawsBg = true
    result.prevTxt = nil
    result.nextTxt = nil

  method setTextColor*(
      self: NSTextField,
      r: cfloat,
      g {.kw("green").}: cfloat,
      b {.kw("blue").}: cfloat,
      a {.kw("alpha").}: cfloat,
  ) =
    self.txtColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setBackgroundColor*(
      self: NSTextField,
      r: cfloat,
      g {.kw("green").}: cfloat,
      b {.kw("blue").}: cfloat,
      a {.kw("alpha").}: cfloat,
  ) =
    self.bgColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method stringValue*(self: NSTextField): NSString =
    if self.strValueId.isNil:
      return @ns""
    ownFromId[NSString](self.strValueId)

  method setStringValue*(self: NSTextField, value: NSString) =
    let next = value.value
    if self.strValueId == next:
      return
    self.strValueId = replacedOwnedId(self.strValueId, next)

  method previousText*(self: NSTextField): NSTextField =
    if self.prevTxt.isNil:
      return NSTextField(value: nil)
    ownFromId[NSTextField](self.prevTxt)

  method nextText*(self: NSTextField): NSTextField =
    if self.nextTxt.isNil:
      return NSTextField(value: nil)
    ownFromId[NSTextField](self.nextTxt)

  method setPreviousText*(self: NSTextField, text: NSTextField) =
    self.prevTxt = replacedOwnedId(self.prevTxt, text.value)

  method setNextText*(self: NSTextField, text: NSTextField) =
    self.nextTxt = replacedOwnedId(self.nextTxt, text.value)

  method selectText*(self: NSTextField, sender: NSResponder) =
    discard self
    discard sender

  method setTitleWithMnemonic*(self: NSTextField, value: NSString) =
    self.setStringValue(stripMnemonicMarkers(value))

  method dealloc(self: NSTextField) {.used.} =
    self.prevTxt = replacedOwnedId(self.prevTxt, nil)
    self.nextTxt = replacedOwnedId(self.nextTxt, nil)
    self.strValueId = replacedOwnedId(self.strValueId, nil)
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
    recentSearchesId: ID
    recentsAutosaveNameId: ID

  method init*(self: var NSSearchField): NSSearchField =
    result =
      asType[NSSearchField](callSuperIdFrom(NSSearchField, self, getSelector("init")))
    if result.isNil:
      return
    result.recentSearchesId = retainId(nsArray[NSString]().value)
    result.recentsAutosaveNameId = retainId(@ns"".value)

  method recentSearches*(self: NSSearchField): NSArray[NSString] =
    if self.recentSearchesId.isNil:
      return nsArray[NSString]()
    ownFromId[NSArray[NSString]](self.recentSearchesId)

  method setRecentSearches*(self: NSSearchField, searches: NSArray[NSString]) =
    self.recentSearchesId = replacedOwnedId(self.recentSearchesId, searches.value)

  method recentsAutosaveName*(self: NSSearchField): NSString =
    if self.recentsAutosaveNameId.isNil:
      return @ns""
    ownFromId[NSString](self.recentsAutosaveNameId)

  method setRecentsAutosaveName*(self: NSSearchField, name: NSString) =
    self.recentsAutosaveNameId = replacedOwnedId(self.recentsAutosaveNameId, name.value)

  method dealloc(self: NSSearchField) {.used.} =
    self.recentSearchesId = replacedOwnedId(self.recentSearchesId, nil)
    self.recentsAutosaveNameId = replacedOwnedId(self.recentsAutosaveNameId, nil)
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
