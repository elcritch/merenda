import std/[sets, unicode]

import ../foundation/events
import ../foundation/types
import ../responder/keybindings

type
  NativeMenuModifier* = enum
    nmmShift
    nmmControl
    nmmOption
    nmmCommand

  NativeMenuItemState* = enum
    nmisOff
    nmisOn
    nmisMixed

  NativeMenuDescription* = ref object
    identity*: pointer
    title*: string
    items*: seq[NativeMenuItemDescription]
    refresh*: proc(): NativeMenuDescription {.closure.}
    didClose*: proc() {.closure.}

  NativeMenuItemDescription* = object
    title*: string
    separator*: bool
    enabled*: bool
    hidden*: bool
    state*: NativeMenuItemState
    tag*: int
    keyEquivalent*: string
    modifiers*: set[NativeMenuModifier]
    submenu*: NativeMenuDescription
    activate*: proc() {.closure.}

  NativeMenuAdapter*[MenuType, ItemType] = object
    identity*: proc(menu: MenuType): pointer {.closure.}
    title*: proc(menu: MenuType): string {.closure.}
    items*: proc(menu: MenuType): seq[ItemType] {.closure.}
    describeItem*: proc(item: ItemType): NativeMenuItemDescription {.closure.}
    submenu*: proc(item: ItemType): MenuType {.closure.}
    canActivate*: proc(item: ItemType): bool {.closure.}
    refresh*: proc(menu: MenuType) {.closure.}
    close*: proc(menu: MenuType) {.closure.}
    activate*: proc(menu: MenuType, item: ItemType) {.closure.}

proc nativeMenuActivation[MenuType, ItemType](
    adapter: NativeMenuAdapter[MenuType, ItemType], menu: MenuType, item: ItemType
): proc() {.closure.} =
  result = proc() =
    adapter.activate(menu, item)

proc nativeMenuDescription[MenuType, ItemType](
    menu: MenuType,
    adapter: NativeMenuAdapter[MenuType, ItemType],
    building: var HashSet[pointer],
): NativeMenuDescription =
  result =
    NativeMenuDescription(identity: adapter.identity(menu), title: adapter.title(menu))
  let modelMenu = menu
  result.refresh = proc(): NativeMenuDescription =
    adapter.refresh(modelMenu)
    var refreshedMenus = initHashSet[pointer]()
    refreshedMenus.incl adapter.identity(modelMenu)
    nativeMenuDescription(modelMenu, adapter, refreshedMenus)
  result.didClose = proc() =
    adapter.close(modelMenu)

  for item in adapter.items(menu):
    if item != default(ItemType):
      var nativeItem = adapter.describeItem(item)
      let submenu = adapter.submenu(item)
      if submenu != default(MenuType):
        let submenuKey = adapter.identity(submenu)
        if submenuKey notin building:
          building.incl submenuKey
          nativeItem.submenu = nativeMenuDescription(submenu, adapter, building)
          building.excl submenuKey
      elif adapter.canActivate(item):
        nativeItem.activate = nativeMenuActivation(adapter, menu, item)
      result.items.add nativeItem

proc toNativeMenuDescription*[MenuType, ItemType](
    menu: MenuType, adapter: NativeMenuAdapter[MenuType, ItemType]
): NativeMenuDescription =
  if menu == default(MenuType):
    return nil
  var building = initHashSet[pointer]()
  building.incl adapter.identity(menu)
  nativeMenuDescription(menu, adapter, building)

proc toNativeKeyEquivalent*(stroke: KeyStroke): string =
  if stroke.text.len > 0:
    return stroke.text
  case stroke.key
  of keyA .. keyZ:
    $(char(ord('a') + ord(stroke.key) - ord(keyA)))
  of key1 .. key9:
    $(char(ord('1') + ord(stroke.key) - ord(key1)))
  of key0:
    "0"
  of keyTilde:
    "`"
  of keyMinus:
    "-"
  of keyEqual:
    "="
  of keyLeftBracket:
    "["
  of keyRightBracket:
    "]"
  of keySpace:
    " "
  of keyEscape:
    "\e"
  of keyEnter:
    "\r"
  of keyTab:
    "\t"
  of keyBackspace:
    "\x7f"
  of keySlash:
    "/"
  of keyDot:
    "."
  of keyComma:
    ","
  of keySemicolon:
    ";"
  of keyQuote:
    "'"
  of keyBackslash:
    "\\"
  of keyArrowUp:
    $Rune(0xF700)
  of keyArrowDown:
    $Rune(0xF701)
  of keyArrowLeft:
    $Rune(0xF702)
  of keyArrowRight:
    $Rune(0xF703)
  of keyF1 .. keyF15:
    $Rune(0xF704 + ord(stroke.key) - ord(keyF1))
  of keyInsert:
    $Rune(0xF727)
  of keyDelete:
    $Rune(0xF728)
  of keyHome:
    $Rune(0xF729)
  of keyEnd:
    $Rune(0xF72B)
  of keyPageUp:
    $Rune(0xF72C)
  of keyPageDown:
    $Rune(0xF72D)
  else:
    ""

proc toNativeModifiers*(modifiers: set[KeyModifier]): set[NativeMenuModifier] =
  if kmShift in modifiers:
    result.incl nmmShift
  if kmControl in modifiers:
    result.incl nmmControl
  if kmOption in modifiers:
    result.incl nmmOption
  if kmCommand in modifiers:
    result.incl nmmCommand

proc toNativeState*(state: ButtonState): NativeMenuItemState =
  case state
  of bsOff: nmisOff
  of bsOn: nmisOn
  of bsMixed: nmisMixed

when defined(macosx):
  import std/tables

  import darwin/app_kit/[nsapplication, nsevent, nsmenu]
  import darwin/foundation/nsstring
  import darwin/objc/runtime

  {.passL: "-framework AppKit".}

  proc setDelegate(menu: NSMenu, delegate: ID) {.objc: "setDelegate:".}
  proc setAutoenablesItems(menu: NSMenu, enabled: BOOL) {.objc: "setAutoenablesItems:".}
  proc setTitle(menu: NSMenu, title: NSString) {.objc: "setTitle:".}
  proc submenu(item: NSMenuItem): NSMenu {.objc: "submenu".}
  proc setState(item: NSMenuItem, state: NSInteger) {.objc: "setState:".}
  proc setHidden(item: NSMenuItem, hidden: BOOL) {.objc: "setHidden:".}
  proc setTag(item: NSMenuItem, tag: NSInteger) {.objc: "setTag:".}

  var
    nativeMenuTarget: NSObject
    nativeMenuItemBindings: Table[pointer, proc() {.closure.}]
    nativeMenuBindings: Table[pointer, NativeMenuDescription]
    nativeMenuHandles: Table[pointer, NSMenu]
    nativeMenuTablesReady: bool

  proc rebuildNativeMenuContents(nativeMenu: NSMenu, menu: NativeMenuDescription)

  proc ensureNativeMenuTables() =
    if nativeMenuTablesReady:
      return
    nativeMenuItemBindings = initTable[pointer, proc() {.closure.}]()
    nativeMenuBindings = initTable[pointer, NativeMenuDescription]()
    nativeMenuHandles = initTable[pointer, NSMenu]()
    nativeMenuTablesReady = true

  proc nativeModifierMask(modifiers: set[NativeMenuModifier]): NSEventModifierFlags =
    var mask = 0.uint
    if nmmShift in modifiers:
      mask = mask or uint(NSEventModifierFlagShift)
    if nmmControl in modifiers:
      mask = mask or uint(NSEventModifierFlagControl)
    if nmmOption in modifiers:
      mask = mask or uint(NSEventModifierFlagOption)
    if nmmCommand in modifiers:
      mask = mask or uint(NSEventModifierFlagCommand)
    cast[NSEventModifierFlags](mask)

  proc nativeState(state: NativeMenuItemState): NSInteger =
    case state
    of nmisOff: 0
    of nmisOn: 1
    of nmisMixed: -1

  proc forgetNativeMenu(nativeMenu: NSMenu, forgetMenu: bool) =
    if nativeMenu.isNil:
      return
    for index in 0 ..< nativeMenu.numberOfItems().int:
      let nativeItem = nativeMenu.itemAtIndex(index)
      if not nativeItem.isNil:
        let childMenu = nativeItem.submenu()
        if not childMenu.isNil:
          forgetNativeMenu(childMenu, true)
        nativeMenuItemBindings.del(cast[pointer](nativeItem))
    if forgetMenu:
      let nativeKey = cast[pointer](nativeMenu)
      if nativeKey in nativeMenuBindings:
        let menu = nativeMenuBindings[nativeKey]
        if menu.identity in nativeMenuHandles and
            nativeMenuHandles[menu.identity] == nativeMenu:
          nativeMenuHandles.del(menu.identity)
        nativeMenuBindings.del(nativeKey)

  proc populateNativeMenu(nativeMenu: NSMenu, menu: NativeMenuDescription) =
    for item in menu.items:
      if item.separator:
        nativeMenu.addItem(NSMenuItem.separatorItem())
      else:
        let
          hasSubmenu = not item.submenu.isNil
          action =
            if hasSubmenu or item.activate.isNil:
              cast[SEL](nil)
            else:
              sel_registerName("nimkitMenuItemActivated:")
          nativeItem =
            NSMenuItem.alloc().initWithTitle(item.title, action, item.keyEquivalent)

        nativeItem.setEnabled(item.enabled)
        nativeItem.setHidden(item.hidden)
        nativeItem.setState(nativeState(item.state))
        nativeItem.setTag(item.tag)
        nativeItem.setKeyEquivalentModifierMask(nativeModifierMask(item.modifiers))
        if not action.isNil:
          nativeItem.setTarget(cast[ID](nativeMenuTarget))
          nativeMenuItemBindings[cast[pointer](nativeItem)] = item.activate

        if hasSubmenu:
          let nativeSubmenu = NSMenu.alloc().initWithTitle(item.submenu.title)
          nativeSubmenu.setAutoenablesItems(false)
          nativeSubmenu.setDelegate(cast[ID](nativeMenuTarget))
          nativeMenuBindings[cast[pointer](nativeSubmenu)] = item.submenu
          nativeMenuHandles[item.submenu.identity] = nativeSubmenu
          populateNativeMenu(nativeSubmenu, item.submenu)
          nativeItem.setSubmenu(nativeSubmenu)
          nativeSubmenu.release()

        nativeMenu.addItem(nativeItem)
        nativeItem.release()

  proc rebuildNativeMenuContents(nativeMenu: NSMenu, menu: NativeMenuDescription) =
    ensureNativeMenuTables()
    forgetNativeMenu(nativeMenu, false)
    nativeMenu.removeAllItems()
    nativeMenu.setTitle(menu.title)
    nativeMenuBindings[cast[pointer](nativeMenu)] = menu
    nativeMenuHandles[menu.identity] = nativeMenu
    populateNativeMenu(nativeMenu, menu)

  proc nativeMenuItemActivated(
      self: ID, command: SEL, sender: ID
  ) {.cdecl, raises: [].} =
    discard self
    discard command
    try:
      ensureNativeMenuTables()
      let senderKey = cast[pointer](sender)
      if senderKey in nativeMenuItemBindings:
        nativeMenuItemBindings[senderKey]()
    except Exception as error:
      echo "NimKit native menu action failed: ", error.msg

  proc nativeMenuWillOpen(self: ID, command: SEL, sender: ID) {.cdecl, raises: [].} =
    discard self
    discard command
    try:
      ensureNativeMenuTables()
      let senderKey = cast[pointer](sender)
      if senderKey in nativeMenuBindings:
        let menu = nativeMenuBindings[senderKey]
        if not menu.refresh.isNil:
          let refreshed = menu.refresh()
          if not refreshed.isNil:
            rebuildNativeMenuContents(cast[NSMenu](sender), refreshed)
    except Exception as error:
      echo "NimKit native menu update failed: ", error.msg

  proc nativeMenuDidClose(self: ID, command: SEL, sender: ID) {.cdecl, raises: [].} =
    discard self
    discard command
    try:
      ensureNativeMenuTables()
      let senderKey = cast[pointer](sender)
      if senderKey in nativeMenuBindings:
        let menu = nativeMenuBindings[senderKey]
        if not menu.didClose.isNil:
          menu.didClose()
    except Exception as error:
      echo "NimKit native menu close failed: ", error.msg

  proc ensureNativeMenuTarget() =
    if not nativeMenuTarget.isNil:
      return
    const NativeMenuTargetClassName = "NimKitNativeMenuTarget"
    var targetClass = getClass(NativeMenuTargetClassName)
    if targetClass.isNil:
      targetClass =
        allocateClassPair(getClass("NSObject"), NativeMenuTargetClassName, 0)
      discard targetClass.addMethod(
        sel_registerName("nimkitMenuItemActivated:"), nativeMenuItemActivated
      )
      discard
        targetClass.addMethod(sel_registerName("menuWillOpen:"), nativeMenuWillOpen)
      discard
        targetClass.addMethod(sel_registerName("menuDidClose:"), nativeMenuDidClose)
      targetClass.registerClassPair()
    nativeMenuTarget = cast[NSObject](targetClass.new())

  proc installNativeMenus*(menu: NativeMenuDescription, windowsMenu: pointer) =
    ensureNativeMenuTables()
    ensureNativeMenuTarget()
    let application = NSApplication.sharedApplication()
    if menu.isNil:
      application.setMainMenu(nil)
      application.setWindowsMenu(nil)
      nativeMenuItemBindings.clear()
      nativeMenuBindings.clear()
      nativeMenuHandles.clear()
      return

    let oldMainMenu = application.mainMenu()
    if not oldMainMenu.isNil:
      forgetNativeMenu(oldMainMenu, true)
    nativeMenuItemBindings.clear()
    nativeMenuBindings.clear()
    nativeMenuHandles.clear()

    let nativeRoot = NSMenu.alloc().initWithTitle(menu.title)
    try:
      nativeRoot.setAutoenablesItems(false)
      nativeMenuBindings[cast[pointer](nativeRoot)] = menu
      nativeMenuHandles[menu.identity] = nativeRoot
      populateNativeMenu(nativeRoot, menu)
      application.setMainMenu(nativeRoot)

      if not windowsMenu.isNil and windowsMenu in nativeMenuHandles:
        application.setWindowsMenu(nativeMenuHandles[windowsMenu])
      else:
        application.setWindowsMenu(nil)
    finally:
      nativeRoot.release()

else:
  proc installNativeMenus*(menu: NativeMenuDescription, windowsMenu: pointer) =
    discard menu
    discard windowsMenu
