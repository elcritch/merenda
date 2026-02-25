import ./runtime
import ./views
import ./buttons
import ./windows

objcImpl:
  type NSAlert* = object of NSObject
    xDelegate {.set: setDelegate, get: delegate.}: ID
    xStyle {.set: setAlertStyle, get: alertStyle.}: int
    xIcon {.set: setIcon, get: icon.}: NSObject
    xMessageText {.get: messageText.}: NSString
    xInformativeText {.get: informativeText.}: NSString
    xAccessoryView {.get: accessoryView.}: NSView
    xShowsHelp {.set: setShowsHelp, get: showsHelp.}: bool
    xShowsSuppressionButton {.get: showsSuppressionButton.}: bool
    xHelpAnchor {.set: setHelpAnchor, get: helpAnchor.}: NSString
    xButtons {.get: buttons.}: NSArray[NSButton]
    xSuppressionButton {.get: suppressionButton.}: NSButton
    xWindow {.get: window.}: NSWindow
    xNeedsLayout: bool
    xSheetDelegate: ID
    xSheetDidEnd: SEL

  method init*(self: var NSAlert): NSAlert =
    result = asType[NSAlert](callSuperIdFrom(NSAlert, self, getSelector("init")))
    if result.isNil:
      return
    result.xDelegate = ID(value: nil)
    result.xStyle = NSWarningAlertStyle
    result.xIcon = NSObject(value: nil)
    result.xMessageText = @ns""
    result.xInformativeText = @ns""
    result.xAccessoryView = NSView(value: nil)
    result.xShowsHelp = false
    result.xShowsSuppressionButton = false
    result.xHelpAnchor = @ns""
    result.xButtons = nsArray[NSButton]()
    result.xSuppressionButton = NSButton(value: nil)
    result.xWindow = NSWindow(value: nil)
    result.xNeedsLayout = true
    result.xSheetDelegate = ID(value: nil)
    result.xSheetDidEnd = nil

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

  method setMessageText*(self: NSAlert, value: NSString) =
    self.xMessageText = value
    self.xNeedsLayout = true

  method setInformativeText*(self: NSAlert, value: NSString) =
    self.xInformativeText = value
    self.xNeedsLayout = true

  method setAccessoryView*(self: NSAlert, value: NSView) =
    self.xAccessoryView = value
    self.xNeedsLayout = true

  method setShowsSuppressionButton*(self: NSAlert, value: bool) =
    self.xShowsSuppressionButton = value
    if value and self.xSuppressionButton.isNil:
      var button = NSButton.new()
      button.setTitle(@ns"Do not show again")
      self.xSuppressionButton = button

  method addButtonWithTitle*(self: NSAlert, title: NSString): NSButton =
    result = NSButton.new()
    if result.isNil:
      return
    result.setTitle(title)
    var buttons = self.buttons()
    buttons.add(result)
    self.xButtons = buttons
    self.xNeedsLayout = true

  method layout*(self: NSAlert) =
    self.xNeedsLayout = false

  method beginSheetModalForWindow*(
      self: NSAlert,
      window: NSWindow,
      modalDelegate {.kw("modalDelegate").}: ID,
      didEndSelector {.kw("didEndSelector").}: SEL,
      contextInfo {.kw("contextInfo").}: pointer,
  ) =
    discard contextInfo
    self.xWindow = window
    self.xSheetDelegate = modalDelegate
    self.xSheetDidEnd = didEndSelector

  method runModal*(self: NSAlert): int =
    let count = self.buttons().len
    if count <= 1:
      return NSAlertFirstButtonReturn
    if count == 2:
      return NSAlertSecondButtonReturn
    NSAlertThirdButtonReturn

  method dealloc(self: NSAlert) {.used.} =
    self.xDelegate = ID(value: nil)
    self.xIcon = NSObject(value: nil)
    self.xMessageText = @ns""
    self.xInformativeText = @ns""
    self.xAccessoryView = NSView(value: nil)
    self.xHelpAnchor = @ns""
    self.xSuppressionButton = NSButton(value: nil)
    self.xButtons = NSArray[NSButton](value: nil)
    self.xWindow = NSWindow(value: nil)
    self.xSheetDelegate = ID(value: nil)
    discard callSuperIdFrom(NSAlert, self, getSelector("dealloc"))

proc new*(t: typedesc[NSAlert]): NSAlert =
  var allocated = NSAlert.alloc()
  result = initOwned(move(allocated))
