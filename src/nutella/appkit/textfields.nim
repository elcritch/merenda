import ../runtime

objcImpl:

  type NXTextField* = object of NXControl
    strValueId: ID
    txtColor {.set: setTextColor, get: textColor.}: NSColor
    bgColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    drawsBg {.set: setDrawsBackground, get: drawsBackground.}: bool
    prevTxt: ID
    nextTxt: ID

  method init*(self: var NXTextField): NXTextField =
    result =
      asType[NXTextField](callSuperIdFrom(NXTextField, self, getSelector("init")))
    if result.isNil:
      return
    result.enabled = true
    result.editable = true
    result.selectable = true
    result.scrollable = true
    result.bordered = true
    result.bezeled = true
    result.align = NSNaturalTextAlignment
    result.strValueId = retainId(@ns"".value)
    result.txtColor = nsColor(0.08, 0.08, 0.08, 1.0)
    result.bgColor = nsColor(0.98, 0.99, 1.0, 1.0)
    result.drawsBg = true
    result.prevTxt = nil
    result.nextTxt = nil

  method setTextColor*(
      self: NXTextField,
      r: cfloat,
      g {.kw("green").}: cfloat,
      b {.kw("blue").}: cfloat,
      a {.kw("alpha").}: cfloat,
  ) =
    self.txtColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setBackgroundColor*(
      self: NXTextField,
      r: cfloat,
      g {.kw("green").}: cfloat,
      b {.kw("blue").}: cfloat,
      a {.kw("alpha").}: cfloat,
  ) =
    self.bgColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method stringValue*(self: NXTextField): NSString =
    if self.strValueId.isNil:
      return @ns""
    ownFromId[NSString](self.strValueId)

  method setStringValue*(self: NXTextField, value: NSString) =
    let next = value.value
    if self.strValueId == next:
      return
    self.strValueId = replacedOwnedId(self.strValueId, next)

  method previousText*(self: NXTextField): NXTextField =
    if self.prevTxt.isNil:
      return NXTextField(value: nil)
    ownFromId[NXTextField](self.prevTxt)

  method nextText*(self: NXTextField): NXTextField =
    if self.nextTxt.isNil:
      return NXTextField(value: nil)
    ownFromId[NXTextField](self.nextTxt)

  method setPreviousText*(self: NXTextField, text: NXTextField) =
    self.prevTxt = replacedOwnedId(self.prevTxt, text.value)

  method setNextText*(self: NXTextField, text: NXTextField) =
    self.nextTxt = replacedOwnedId(self.nextTxt, text.value)

  method selectText*(self: NXTextField, sender: NXResponder) =
    discard self
    discard sender

  method setTitleWithMnemonic*(self: NXTextField, value: NSString) =
    self.setStringValue(stripMnemonicMarkers(value))

  method dealloc(self: NXTextField) {.used.} =
    self.prevTxt = replacedOwnedId(self.prevTxt, nil)
    self.nextTxt = replacedOwnedId(self.nextTxt, nil)
    self.strValueId = replacedOwnedId(self.strValueId, nil)
    discard callSuperIdFrom(NXTextField, self, getSelector("dealloc"))


objcImpl:
  type NXSecureTextField* = object of NXTextField
    echosBullets {.set: setEchosBullets, get: echosBullets.}: bool

  method init*(self: var NXSecureTextField): NXSecureTextField =
    result = asType[NXSecureTextField](
      callSuperIdFrom(NXSecureTextField, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.echosBullets = true

objcImpl:
  type NXSearchField* = object of NXTextField
    recentSearchesId: ID
    recentsAutosaveNameId: ID

  method init*(self: var NXSearchField): NXSearchField =
    result =
      asType[NXSearchField](callSuperIdFrom(NXSearchField, self, getSelector("init")))
    if result.isNil:
      return
    result.recentSearchesId = retainId(nsArray[NSString]().value)
    result.recentsAutosaveNameId = retainId(@ns"".value)

  method recentSearches*(self: NXSearchField): NSArray[NSString] =
    if self.recentSearchesId.isNil:
      return nsArray[NSString]()
    ownFromId[NSArray[NSString]](self.recentSearchesId)

  method setRecentSearches*(self: NXSearchField, searches: NSArray[NSString]) =
    self.recentSearchesId = replacedOwnedId(self.recentSearchesId, searches.value)

  method recentsAutosaveName*(self: NXSearchField): NSString =
    if self.recentsAutosaveNameId.isNil:
      return @ns""
    ownFromId[NSString](self.recentsAutosaveNameId)

  method setRecentsAutosaveName*(self: NXSearchField, name: NSString) =
    self.recentsAutosaveNameId = replacedOwnedId(self.recentsAutosaveNameId, name.value)

  method dealloc(self: NXSearchField) {.used.} =
    self.recentSearchesId = replacedOwnedId(self.recentSearchesId, nil)
    self.recentsAutosaveNameId = replacedOwnedId(self.recentsAutosaveNameId, nil)
    discard callSuperIdFrom(NXSearchField, self, getSelector("dealloc"))

proc new*(t: typedesc[NSTextField]): NSTextField =
  var allocated = NSTextField.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSSecureTextField]): NSSecureTextField =
  var allocated = NSSecureTextField.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSSearchField]): NSSearchField =
  var allocated = NSSearchField.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

