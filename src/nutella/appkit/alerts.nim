import ./runtime
import ./views
import ./buttons
import ./windows

objcImpl:
  type NSAlert* = object of NSObject
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

  method init*(self: var NSAlert): NSAlert =
    result = asType[NSAlert](callSuperIdFrom(NSAlert, self, getSelector("init")))
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
    result.alertButtonsId = retainId(nsArray[NSButton]().value)
    result.suppressionButtonId = nil
    result.alertWindowId = nil
    result.needsLayout = true
    result.sheetDelegateId = nil
    result.sheetDidEnd = nil

  proc alertWithError*(t: typedesc[NSAlert], err {.kw("error").}: NSObject): NSAlert =
    result = NSAlert.new()
    if result.isNil:
      return
    if err.isNil:
      result.setMessageText(@ns"Error")
      result.setInformativeText(@ns"Unknown error")
    else:
      result.setMessageText(@ns"Error")
      result.setInformativeText(ns($err))

  proc alertWithMessageText*(
      t: typedesc[NSAlert],
      messageText: NSString,
      defaultButton {.kw("defaultButton").}: NSString,
      alternateButton {.kw("alternateButton").}: NSString,
      otherButton {.kw("otherButton").}: NSString,
      informativeText {.kw("informativeTextWithFormat").}: NSString,
  ): NSAlert =
    result = NSAlert.new()
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

  method delegate*(self: NSAlert): NSObject =
    if self.delegateId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.delegateId)

  method setDelegate*(self: NSAlert, value: NSObject) =
    self.delegateId = replacedOwnedId(self.delegateId, value.value)

  method icon*(self: NSAlert): NSObject =
    if self.iconId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.iconId)

  method setIcon*(self: NSAlert, value: NSObject) =
    self.iconId = replacedOwnedId(self.iconId, value.value)

  method messageText*(self: NSAlert): NSString =
    if self.messageTextId.isNil:
      return @ns""
    ownFromId[NSString](self.messageTextId)

  method setMessageText*(self: NSAlert, value: NSString) =
    self.messageTextId = replacedOwnedId(self.messageTextId, value.value)
    self.needsLayout = true

  method informativeText*(self: NSAlert): NSString =
    if self.informativeTextId.isNil:
      return @ns""
    ownFromId[NSString](self.informativeTextId)

  method setInformativeText*(self: NSAlert, value: NSString) =
    self.informativeTextId = replacedOwnedId(self.informativeTextId, value.value)
    self.needsLayout = true

  method accessoryView*(self: NSAlert): NSView =
    if self.accessoryViewId.isNil:
      return NSView(value: nil)
    ownFromId[NSView](self.accessoryViewId)

  method setAccessoryView*(self: NSAlert, value: NSView) =
    self.accessoryViewId = replacedOwnedId(self.accessoryViewId, value.value)
    self.needsLayout = true

  method helpAnchor*(self: NSAlert): NSString =
    if self.helpAnchorId.isNil:
      return @ns""
    ownFromId[NSString](self.helpAnchorId)

  method setHelpAnchor*(self: NSAlert, value: NSString) =
    self.helpAnchorId = replacedOwnedId(self.helpAnchorId, value.value)

  method suppressionButton*(self: NSAlert): NSButton =
    if self.suppressionButtonId.isNil:
      return NSButton(value: nil)
    ownFromId[NSButton](self.suppressionButtonId)

  method showsSuppressionButton*(self: NSAlert): bool =
    self.showsSuppression

  method setShowsSuppressionButton*(self: NSAlert, value: bool) =
    self.showsSuppression = value
    if value and self.suppressionButtonId.isNil:
      var button = NSButton.new()
      button.setTitle(@ns"Do not show again")
      self.suppressionButtonId = replacedOwnedId(self.suppressionButtonId, button.value)

  method buttons*(self: NSAlert): NSArray[NSButton] =
    if self.alertButtonsId.isNil:
      return nsArray[NSButton]()
    ownFromId[NSArray[NSButton]](self.alertButtonsId)

  method addButtonWithTitle*(self: NSAlert, title: NSString): NSButton =
    result = NSButton.new()
    if result.isNil:
      return
    result.setTitle(title)
    var buttons = self.buttons()
    buttons.add(result)
    self.alertButtonsId = replacedOwnedId(self.alertButtonsId, buttons.value)
    self.needsLayout = true

  method window*(self: NSAlert): NSWindow =
    if self.alertWindowId.isNil:
      return NSWindow(value: nil)
    ownFromId[NSWindow](self.alertWindowId)

  method layout*(self: NSAlert) =
    self.needsLayout = false

  method beginSheetModalForWindow*(
      self: NSAlert,
      window: NSWindow,
      modalDelegate {.kw("modalDelegate").}: NSObject,
      didEndSelector {.kw("didEndSelector").}: SEL,
      contextInfo {.kw("contextInfo").}: pointer,
  ) =
    discard contextInfo
    self.alertWindowId = replacedOwnedId(self.alertWindowId, window.value)
    self.sheetDelegateId = replacedOwnedId(self.sheetDelegateId, modalDelegate.value)
    self.sheetDidEnd = didEndSelector

  method runModal*(self: NSAlert): int =
    let count = self.buttons().len
    if count <= 1:
      return NSAlertFirstButtonReturn
    if count == 2:
      return NSAlertSecondButtonReturn
    NSAlertThirdButtonReturn

  method dealloc(self: NSAlert) {.used.} =
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
    discard callSuperIdFrom(NSAlert, self, getSelector("dealloc"))

proc new*(t: typedesc[NSAlert]): NSAlert =
  var allocated = NSAlert.alloc()
  result = initOwned(move(allocated))
