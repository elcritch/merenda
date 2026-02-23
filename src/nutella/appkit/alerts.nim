import ./runtime

objcImpl:

  type NXAlert* = object of NSObject
    delegateId: ID
    style {.set: setAlertStyle, get: alertStyle.}: int
    iconId: ID
    messageTextId: ID
    informativeTextId: ID
    accessoryViewId: ID
    showsHelpFlag {.set: setShowsHelp, get: showsHelp.}: bool
    showsSuppression: bool
    helpAnchorId: ID
    alertButtonsId: ID
    suppressionButtonId: ID
    alertWindowId: ID
    needsLayout: bool
    sheetDelegateId: ID
    sheetDidEnd: SEL

  method init*(self: var NXAlert): NXAlert =
    result = asType[NXAlert](callSuperIdFrom(NXAlert, self, getSelector("init")))
    if result.isNil:
      return
    result.delegateId = nil
    result.style = NSWarningAlertStyle
    result.iconId = nil
    result.messageTextId = retainId(@ns"".value)
    result.informativeTextId = retainId(@ns"".value)
    result.accessoryViewId = nil
    result.showsHelpFlag = false
    result.showsSuppression = false
    result.helpAnchorId = retainId(@ns"".value)
    result.alertButtonsId = retainId(nsArray[NXButton]().value)
    result.suppressionButtonId = nil
    result.alertWindowId = nil
    result.needsLayout = true
    result.sheetDelegateId = nil
    result.sheetDidEnd = nil

  proc alertWithError*(t: typedesc[NXAlert], err {.kw("error").}: NSObject): NXAlert =
    when false:
      discard t
    result = NXAlert.new()
    if result.isNil:
      return
    if err.isNil:
      result.setMessageText(@ns"Error")
      result.setInformativeText(@ns"Unknown error")
    else:
      result.setMessageText(@ns"Error")
      result.setInformativeText(ns($err))

  proc alertWithMessageText*(
      t: typedesc[NXAlert],
      messageText: NSString,
      defaultButton {.kw("defaultButton").}: NSString,
      alternateButton {.kw("alternateButton").}: NSString,
      otherButton {.kw("otherButton").}: NSString,
      informativeText {.kw("informativeTextWithFormat").}: NSString,
  ): NXAlert =
    when false:
      discard t
    result = NXAlert.new()
    if result.isNil:
      return
    result.setMessageText(messageText)
    result.setInformativeText(informativeText)
    if $defaultButton != "":
      discard result.addButtonWithTitle(defaultButton)
    if $alternateButton != "":
      discard result.addButtonWithTitle(alternateButton)
    if $otherButton != "":
      discard result.addButtonWithTitle(otherButton)

  method delegate*(self: NXAlert): NSObject =
    if self.delegateId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.delegateId)

  method setDelegate*(self: NXAlert, value: NSObject) =
    self.delegateId = replacedOwnedId(self.delegateId, value.value)

  method icon*(self: NXAlert): NSObject =
    if self.iconId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.iconId)

  method setIcon*(self: NXAlert, value: NSObject) =
    self.iconId = replacedOwnedId(self.iconId, value.value)

  method messageText*(self: NXAlert): NSString =
    if self.messageTextId.isNil:
      return @ns""
    ownFromId[NSString](self.messageTextId)

  method setMessageText*(self: NXAlert, value: NSString) =
    self.messageTextId = replacedOwnedId(self.messageTextId, value.value)
    self.needsLayout = true

  method informativeText*(self: NXAlert): NSString =
    if self.informativeTextId.isNil:
      return @ns""
    ownFromId[NSString](self.informativeTextId)

  method setInformativeText*(self: NXAlert, value: NSString) =
    self.informativeTextId = replacedOwnedId(self.informativeTextId, value.value)
    self.needsLayout = true

  method accessoryView*(self: NXAlert): NXView =
    if self.accessoryViewId.isNil:
      return NXView(value: nil)
    ownFromId[NXView](self.accessoryViewId)

  method setAccessoryView*(self: NXAlert, value: NXView) =
    self.accessoryViewId = replacedOwnedId(self.accessoryViewId, value.value)
    self.needsLayout = true

  method helpAnchor*(self: NXAlert): NSString =
    if self.helpAnchorId.isNil:
      return @ns""
    ownFromId[NSString](self.helpAnchorId)

  method setHelpAnchor*(self: NXAlert, value: NSString) =
    self.helpAnchorId = replacedOwnedId(self.helpAnchorId, value.value)

  method suppressionButton*(self: NXAlert): NXButton =
    if self.suppressionButtonId.isNil:
      return NXButton(value: nil)
    ownFromId[NXButton](self.suppressionButtonId)

  method showsSuppressionButton*(self: NXAlert): bool =
    self.showsSuppression

  method setShowsSuppressionButton*(self: NXAlert, value: bool) =
    self.showsSuppression = value
    if value and self.suppressionButtonId.isNil:
      var button = NXButton.new()
      button.setTitle(@ns"Do not show again")
      self.suppressionButtonId = replacedOwnedId(self.suppressionButtonId, button.value)

  method buttons*(self: NXAlert): NSArray[NXButton] =
    if self.alertButtonsId.isNil:
      return nsArray[NXButton]()
    ownFromId[NSArray[NXButton]](self.alertButtonsId)

  method addButtonWithTitle*(self: NXAlert, title: NSString): NXButton =
    result = NXButton.new()
    if result.isNil:
      return
    result.setTitle(title)
    var buttons = self.buttons()
    buttons.add(result)
    self.alertButtonsId = replacedOwnedId(self.alertButtonsId, buttons.value)
    self.needsLayout = true

  method window*(self: NXAlert): NXWindow =
    if self.alertWindowId.isNil:
      return NXWindow(value: nil)
    ownFromId[NXWindow](self.alertWindowId)

  method layout*(self: NXAlert) =
    self.needsLayout = false

  method beginSheetModalForWindow*(
      self: NXAlert,
      window: NXWindow,
      modalDelegate {.kw("modalDelegate").}: NSObject,
      didEndSelector {.kw("didEndSelector").}: SEL,
      contextInfo {.kw("contextInfo").}: pointer,
  ) =
    discard contextInfo
    self.alertWindowId = replacedOwnedId(self.alertWindowId, window.value)
    self.sheetDelegateId = replacedOwnedId(self.sheetDelegateId, modalDelegate.value)
    self.sheetDidEnd = didEndSelector

  method runModal*(self: NXAlert): int =
    let count = self.buttons().len
    if count <= 1:
      return NSAlertFirstButtonReturn
    if count == 2:
      return NSAlertSecondButtonReturn
    NSAlertThirdButtonReturn

  method dealloc(self: NXAlert) {.used.} =
    self.delegateId = replacedOwnedId(self.delegateId, nil)
    self.iconId = replacedOwnedId(self.iconId, nil)
    self.messageTextId = replacedOwnedId(self.messageTextId, nil)
    self.informativeTextId = replacedOwnedId(self.informativeTextId, nil)
    self.accessoryViewId = replacedOwnedId(self.accessoryViewId, nil)
    self.helpAnchorId = replacedOwnedId(self.helpAnchorId, nil)
    self.suppressionButtonId = replacedOwnedId(self.suppressionButtonId, nil)
    self.alertButtonsId = replacedOwnedId(self.alertButtonsId, nil)
    self.alertWindowId = replacedOwnedId(self.alertWindowId, nil)
    self.sheetDelegateId = replacedOwnedId(self.sheetDelegateId, nil)
    discard callSuperIdFrom(NXAlert, self, getSelector("dealloc"))

proc new*(t: typedesc[NSAlert]): NSAlert =
  when false:
    discard t
  var allocated = NSAlert.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

