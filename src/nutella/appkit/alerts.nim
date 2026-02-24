import ./runtime
import ./views
import ./buttons
import ./windows

objcImpl:
  type NSAlert* = object of NSObject
    xxDelegate {.set: setDelegate, get: delegate.}: ID
    xxStyle {.set: setAlertStyle, get: alertStyle.}: int
    xxIcon {.set: setIcon, get: icon.}: NSObject
    xxMessageText {.get: messageText.}: NSString
    xxInformativeText {.get: informativeText.}: NSString
    xxAccessoryView {.get: accessoryView.}: NSView
    xxShowsHelp {.set: setShowsHelp, get: showsHelp.}: bool
    xxShowsSuppressionButton {.get: showsSuppressionButton.}: bool
    xxHelpAnchor {.set: setHelpAnchor, get: helpAnchor.}: NSString
    xxButtons {.get: buttons.}: NSArray[NSButton]
    xxSuppressionButton {.get: suppressionButton.}: NSButton
    xxWindow {.get: window.}: NSWindow
    xxNeedsLayout: bool
    xxSheetDelegate: ID
    xxSheetDidEnd: SEL

  method init*(self: var NSAlert): NSAlert =
    result = asType[NSAlert](callSuperIdFrom(NSAlert, self, getSelector("init")))
    if result.isNil:
      return
    result.xxDelegate = nil
    result.xxStyle = NSWarningAlertStyle
    result.xxIcon = NSObject(value: nil)
    result.xxMessageText = @ns""
    result.xxInformativeText = @ns""
    result.xxAccessoryView = NSView(value: nil)
    result.xxShowsHelp = false
    result.xxShowsSuppressionButton = false
    result.xxHelpAnchor = @ns""
    result.xxButtons = nsArray[NSButton]()
    result.xxSuppressionButton = NSButton(value: nil)
    result.xxWindow = NSWindow(value: nil)
    result.xxNeedsLayout = true
    result.xxSheetDelegate = nil
    result.xxSheetDidEnd = nil

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
    self.xxMessageText = value
    self.xxNeedsLayout = true

  method setInformativeText*(self: NSAlert, value: NSString) =
    self.xxInformativeText = value
    self.xxNeedsLayout = true

  method setAccessoryView*(self: NSAlert, value: NSView) =
    self.xxAccessoryView = value
    self.xxNeedsLayout = true

  method setShowsSuppressionButton*(self: NSAlert, value: bool) =
    self.xxShowsSuppressionButton = value
    if value and self.xxSuppressionButton.isNil:
      var button = NSButton.new()
      button.setTitle(@ns"Do not show again")
      self.xxSuppressionButton = button

  method addButtonWithTitle*(self: NSAlert, title: NSString): NSButton =
    result = NSButton.new()
    if result.isNil:
      return
    result.setTitle(title)
    var buttons = self.buttons()
    buttons.add(result)
    self.xxButtons = buttons
    self.xxNeedsLayout = true

  method layout*(self: NSAlert) =
    self.xxNeedsLayout = false

  method beginSheetModalForWindow*(
      self: NSAlert,
      window: NSWindow,
      modalDelegate {.kw("modalDelegate").}: ID,
      didEndSelector {.kw("didEndSelector").}: SEL,
      contextInfo {.kw("contextInfo").}: pointer,
  ) =
    discard contextInfo
    self.xxWindow = window
    self.xxSheetDelegate = modalDelegate
    self.xxSheetDidEnd = didEndSelector

  method runModal*(self: NSAlert): int =
    let count = self.buttons().len
    if count <= 1:
      return NSAlertFirstButtonReturn
    if count == 2:
      return NSAlertSecondButtonReturn
    NSAlertThirdButtonReturn

  method dealloc(self: NSAlert) {.used.} =
    self.xxDelegate = nil
    self.xxIcon = NSObject(value: nil)
    self.xxMessageText = @ns""
    self.xxInformativeText = @ns""
    self.xxAccessoryView = NSView(value: nil)
    self.xxHelpAnchor = @ns""
    self.xxSuppressionButton = NSButton(value: nil)
    self.xxButtons = NSArray[NSButton](value: nil)
    self.xxWindow = NSWindow(value: nil)
    self.xxSheetDelegate = nil
    discard callSuperIdFrom(NSAlert, self, getSelector("dealloc"))

proc new*(t: typedesc[NSAlert]): NSAlert =
  var allocated = NSAlert.alloc()
  result = initOwned(move(allocated))
