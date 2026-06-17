import std/options

import sigils/selectors

import ./controls
import ./drawing
import ./events
import ./keybindings
import ./listbasics
import ./popuplists
import ./responders
import ./selectors as nimkitSelectors
import ./theme
import ./types
import ./windows

type
  MenuItem* = ref object of Responder
    xTitle: string
    xAction: ActionSelector
    xTarget: DynamicAgent
    xState: ButtonState
    xEnabled: bool
    xKeyEquivalent: KeyStroke
    xHasKeyEquivalent: bool
    xSubmenu: Menu
    xSeparator: bool
    xTag: int
    xRepresentedObject: DynamicAgent
    xUserInfo: DynamicAgent

  Menu* = ref object of Responder
    xTitle: string
    xItems: seq[MenuItem]
    xDelegate: DynamicAgent
    xOpen: bool

  PopupMenuButton* = ref object of Control
    xTitle: string
    xMenu: Menu
    xPopupList: PopupListView
    xPopupWindow: Window
    xPopupOpen: bool
    xHighlightedIndex: int
    xViewport: ListViewport
    xMaxVisibleItems: int
    xItemHeight: float32
    xPopupPresentation: PopupPresentation
    xParentPopup: PopupMenuButton
    xChildPopup: PopupMenuButton
    xChildPopupOwnerIndex: int
    xCascadeFrame: Rect
    xUsesCascadeFrame: bool

  MenuBar* = ref object of View
    xMenu: Menu
    xButtons: seq[PopupMenuButton]
    xOpenButton: PopupMenuButton

proc openImpl(menu: Menu)
proc closeImpl(menu: Menu)
proc updateImpl(menu: Menu, start: Responder)
proc performKeyEquivalentImpl(menu: Menu, event: KeyEvent, start: Responder): bool
proc openPopupImpl(button: PopupMenuButton)
proc closePopupImpl(button: PopupMenuButton)
proc reloadImpl(menuBar: MenuBar)
proc popupList(button: PopupMenuButton): PopupListView
proc closeChildPopup(button: PopupMenuButton)
proc openSubmenuPopup(button: PopupMenuButton, index: int)
proc openRelativeMenuBarButton(button: PopupMenuButton, delta: int): bool
proc handlePopupKeyDown(button: PopupMenuButton, event: KeyEvent): bool

protocol MenuProtocol {.selectorScope: protocol.} from Menu:
  method openMenu*(menu: Menu) =
    menu.openImpl()

  method closeMenu*(menu: Menu) =
    menu.closeImpl()

  method updateMenu*(menu: Menu, start: Responder = nil) =
    menu.updateImpl(start)

  method performMenuKeyEquivalent*(
      menu: Menu, event: KeyEvent, start: Responder
  ): bool =
    menu.performKeyEquivalentImpl(event, start)

protocol PopupMenuButtonProtocol {.selectorScope: protocol.} from PopupMenuButton:
  method openPopupMenu*(button: PopupMenuButton) =
    button.openPopupImpl()

  method closePopupMenu*(button: PopupMenuButton) =
    button.closePopupImpl()

protocol MenuBarProtocol {.selectorScope: protocol.} from MenuBar:
  method reloadMenuBar*(menuBar: MenuBar) =
    menuBar.reloadImpl()

proc open*(menu: Menu) =
  menu.openMenu()

proc close*(menu: Menu) =
  menu.closeMenu()

proc update*(menu: Menu, start: Responder = nil) =
  menu.updateMenu(start)

proc performKeyEquivalent*(menu: Menu, event: KeyEvent, start: Responder): bool =
  menu.performMenuKeyEquivalent(event, start)

proc openPopup*(button: PopupMenuButton) =
  button.openPopupMenu()

proc closePopup*(button: PopupMenuButton) =
  button.closePopupMenu()

proc reload*(menuBar: MenuBar) =
  menuBar.reloadMenuBar()

proc newMenu*(title = ""): Menu =
  result = Menu(xTitle: title)
  initResponder(result)
  discard result.withProto()

proc newMenuItem*(
    title = "",
    action: ActionSelector = ActionSelector(),
    keyEquivalent = "",
    modifiers: set[KeyModifier] = {},
): MenuItem =
  result = MenuItem(xTitle: title, xAction: action, xEnabled: true)
  initResponder(result)
  if keyEquivalent.len > 0:
    result.xKeyEquivalent = initKeyStroke(keyEquivalent, modifiers)
    result.xHasKeyEquivalent = true

proc separatorMenuItem*(): MenuItem =
  result = newMenuItem()
  result.xSeparator = true
  result.xEnabled = false

proc title*(item: MenuItem): string =
  if item.isNil: "" else: item.xTitle

proc `title=`*(item: MenuItem, title: string) =
  if not item.isNil:
    item.xTitle = title

proc action*(item: MenuItem): ActionSelector =
  if item.isNil:
    ActionSelector()
  else:
    item.xAction

proc `action=`*(item: MenuItem, action: ActionSelector) =
  if not item.isNil:
    item.xAction = action

proc target*(item: MenuItem): DynamicAgent =
  if item.isNil: nil else: item.xTarget

proc `target=`*(item: MenuItem, target: DynamicAgent) =
  if not item.isNil:
    item.xTarget = target

proc `target=`*(item: MenuItem, target: Responder) =
  item.target = DynamicAgent(target)

proc state*(item: MenuItem): ButtonState =
  if item.isNil: bsOff else: item.xState

proc `state=`*(item: MenuItem, state: ButtonState) =
  if not item.isNil:
    item.xState = state

proc enabled*(item: MenuItem): bool =
  (not item.isNil) and item.xEnabled

proc `enabled=`*(item: MenuItem, enabled: bool) =
  if not item.isNil:
    item.xEnabled = enabled

proc keyEquivalent*(item: MenuItem): KeyStroke =
  if item.isNil:
    KeyStroke()
  else:
    item.xKeyEquivalent

proc hasKeyEquivalent*(item: MenuItem): bool =
  (not item.isNil) and item.xHasKeyEquivalent

proc setKeyEquivalent*(item: MenuItem, text: string, modifiers: set[KeyModifier] = {}) =
  if item.isNil:
    return
  if text.len == 0:
    item.xKeyEquivalent = KeyStroke()
    item.xHasKeyEquivalent = false
  else:
    item.xKeyEquivalent = initKeyStroke(text, modifiers)
    item.xHasKeyEquivalent = true

proc setKeyEquivalent*(item: MenuItem, key: Key, modifiers: set[KeyModifier] = {}) =
  if not item.isNil:
    item.xKeyEquivalent = initKeyStroke(key, modifiers)
    item.xHasKeyEquivalent = true

proc modifierMask*(item: MenuItem): set[KeyModifier] =
  if item.isNil:
    {}
  else:
    item.xKeyEquivalent.modifiers

proc `modifierMask=`*(item: MenuItem, modifiers: set[KeyModifier]) =
  if item.isNil:
    return
  item.xKeyEquivalent.modifiers = modifiers
  item.xHasKeyEquivalent = true

proc submenu*(item: MenuItem): Menu =
  if item.isNil: nil else: item.xSubmenu

proc `submenu=`*(item: MenuItem, submenu: Menu) =
  if item.isNil:
    return
  item.xSubmenu = submenu
  if not submenu.isNil:
    submenu.setNextResponder(item)

proc isSeparatorItem*(item: MenuItem): bool =
  (not item.isNil) and item.xSeparator

proc tag*(item: MenuItem): int =
  if item.isNil: 0 else: item.xTag

proc `tag=`*(item: MenuItem, tag: int) =
  if not item.isNil:
    item.xTag = tag

proc representedObject*(item: MenuItem): DynamicAgent =
  if item.isNil: nil else: item.xRepresentedObject

proc `representedObject=`*(item: MenuItem, value: DynamicAgent) =
  if not item.isNil:
    item.xRepresentedObject = value

proc userInfo*(item: MenuItem): DynamicAgent =
  if item.isNil: nil else: item.xUserInfo

proc `userInfo=`*(item: MenuItem, value: DynamicAgent) =
  if not item.isNil:
    item.xUserInfo = value

proc title*(menu: Menu): string =
  if menu.isNil: "" else: menu.xTitle

proc `title=`*(menu: Menu, title: string) =
  if not menu.isNil:
    menu.xTitle = title

proc delegate*(menu: Menu): DynamicAgent =
  if menu.isNil: nil else: menu.xDelegate

proc `delegate=`*(menu: Menu, delegate: DynamicAgent) =
  if not menu.isNil:
    menu.xDelegate = delegate

proc `delegate=`*(menu: Menu, delegate: Responder) =
  menu.delegate = DynamicAgent(delegate)

proc items*(menu: Menu): lent seq[MenuItem] =
  menu.xItems

proc len*(menu: Menu): int =
  if menu.isNil: 0 else: menu.xItems.len

proc `[]`*(menu: Menu, index: Natural): MenuItem =
  menu.xItems[index]

proc addItem*(menu: Menu, item: MenuItem): MenuItem {.discardable.} =
  if menu.isNil or item.isNil:
    return nil
  menu.xItems.add item
  item.setNextResponder(menu)
  item

proc addItem*(
    menu: Menu,
    title: string,
    action: ActionSelector = ActionSelector(),
    keyEquivalent = "",
    modifiers: set[KeyModifier] = {},
): MenuItem {.discardable.} =
  menu.addItem(newMenuItem(title, action, keyEquivalent, modifiers))

proc addSeparator*(menu: Menu): MenuItem {.discardable.} =
  menu.addItem(separatorMenuItem())

proc removeItem*(menu: Menu, item: MenuItem): bool {.discardable.} =
  if menu.isNil or item.isNil:
    return false
  let idx = menu.xItems.find(item)
  if idx < 0:
    return false
  if item.nextResponder() == Responder(menu):
    item.clearNextResponder()
  menu.xItems.delete(idx)
  true

proc menuNeedsUpdate*(menu: Menu) =
  if not menu.isNil and not menu.xDelegate.isNil:
    discard menu.xDelegate.sendLocalIfHandled(menuNeedsUpdate(), DynamicAgent(menu))

proc openImpl(menu: Menu) =
  if menu.isNil:
    return
  menu.menuNeedsUpdate()
  menu.xOpen = true
  if not menu.xDelegate.isNil:
    discard menu.xDelegate.sendLocalIfHandled(menuWillOpen(), DynamicAgent(menu))

proc closeImpl(menu: Menu) =
  if menu.isNil:
    return
  menu.xOpen = false
  if not menu.xDelegate.isNil:
    discard menu.xDelegate.sendLocalIfHandled(menuDidClose(), DynamicAgent(menu))

proc isOpen*(menu: Menu): bool =
  (not menu.isNil) and menu.xOpen

proc validate*(item: MenuItem, target: DynamicAgent): bool =
  if item.isNil or item.xSeparator or not item.xEnabled:
    return false
  if not item.xSubmenu.isNil:
    return true
  if item.xAction.name.len == 0:
    return false
  if target.isNil:
    return false
  let validated =
    target.trySendLocal(validateUserInterfaceItem(), ValidationArgs(item: item))
  if validated.isSome:
    return validated.get()
  target.respondsTo(item.xAction.name)

proc findActionTarget*(start: Responder, selector: ActionSelector): DynamicAgent =
  var current = start
  while not current.isNil:
    if current.respondsTo(selector.name):
      return DynamicAgent(current)
    current = current.nextResponder()

proc validate*(item: MenuItem, start: Responder): bool =
  let target =
    if item.isNil:
      nil
    elif not item.xTarget.isNil:
      item.xTarget
    else:
      findActionTarget(start, item.xAction)
  item.validate(target)

proc updateImpl(menu: Menu, start: Responder) =
  if menu.isNil:
    return
  menu.menuNeedsUpdate()
  for item in menu.xItems:
    if not item.isNil:
      if item.xSubmenu.isNil:
        item.xEnabled = item.validate(start)
      else:
        item.xSubmenu.update(start)

proc perform*(item: MenuItem, start: Responder, sender: DynamicAgent = nil): bool =
  if item.isNil or item.xSeparator or not item.xEnabled:
    return false
  if not item.xTarget.isNil:
    if not item.validate(item.xTarget):
      return false
    return item.xTarget.sendLocalIfHandled(
      item.xAction,
      ActionArgs(
        sender:
          if sender.isNil:
            DynamicAgent(item)
          else:
            sender
      ),
    )
  let target = findActionTarget(start, item.xAction)
  if not item.validate(target):
    return false
  target.sendLocalIfHandled(
    item.xAction,
    ActionArgs(
      sender:
        if sender.isNil:
          DynamicAgent(item)
        else:
          sender
    ),
  )

proc findKeyEquivalentItem*(menu: Menu, event: KeyEvent): MenuItem =
  if menu.isNil:
    return nil
  for item in menu.xItems:
    if item.isNil or item.xSeparator:
      discard
    elif item.xHasKeyEquivalent and item.xKeyEquivalent.matches(event):
      return item
    elif not item.xSubmenu.isNil:
      let found = item.xSubmenu.findKeyEquivalentItem(event)
      if not found.isNil:
        return found

proc performKeyEquivalentImpl(menu: Menu, event: KeyEvent, start: Responder): bool =
  let item = menu.findKeyEquivalentItem(event)
  if item.isNil:
    return false
  item.perform(start)

func popupMenuDefaultItemHeight*(): float32 =
  24.0'f32

func popupMenuDefaultMaxVisibleItems*(): int =
  12

func menuBarDefaultHeight*(): float32 =
  28.0'f32

func menuBarHorizontalInset(): float32 =
  8.0'f32

func menuBarItemGap(): float32 =
  2.0'f32

func menuBarItemPadding(): float32 =
  24.0'f32

proc title*(button: PopupMenuButton): string =
  if button.isNil: "" else: button.xTitle

proc `title=`*(button: PopupMenuButton, title: string) =
  if button.isNil or button.xTitle == title:
    return
  button.xTitle = title
  button.invalidateIntrinsicContentSize()
  button.setNeedsDisplay(true)

proc menu*(button: PopupMenuButton): Menu =
  if button.isNil: nil else: button.xMenu

proc `menu=`*(button: PopupMenuButton, menu: Menu) =
  if button.isNil or button.xMenu == menu:
    return
  button.xMenu = menu
  if not menu.isNil:
    menu.setNextResponder(button)
  button.xViewport.reset()
  button.xHighlightedIndex = -1
  button.setNeedsDisplay(true)

proc popupOpen*(button: PopupMenuButton): bool =
  (not button.isNil) and button.xPopupOpen

proc highlightedIndex*(button: PopupMenuButton): int =
  if button.isNil: -1 else: button.xHighlightedIndex

proc activeSubmenuButton*(button: PopupMenuButton): PopupMenuButton =
  if button.isNil: nil else: button.xChildPopup

proc dispatchPopupKeyDown*(button: PopupMenuButton, event: KeyEvent): bool =
  button.handlePopupKeyDown(event)

proc maxVisibleItems*(button: PopupMenuButton): int =
  if button.isNil: 0 else: button.xMaxVisibleItems

proc `maxVisibleItems=`*(button: PopupMenuButton, value: int) =
  if button.isNil:
    return
  button.xMaxVisibleItems = max(value, 1)
  button.setNeedsDisplay(true)

proc itemHeight*(button: PopupMenuButton): float32 =
  if button.isNil:
    popupMenuDefaultItemHeight()
  else:
    button.xItemHeight

proc `itemHeight=`*(button: PopupMenuButton, value: float32) =
  if button.isNil:
    return
  button.xItemHeight = value.normalizedRowHeight()
  button.setNeedsDisplay(true)

proc popupPresentation*(button: PopupMenuButton): PopupPresentation =
  if button.isNil: ppAutomatic else: button.xPopupPresentation

proc `popupPresentation=`*(button: PopupMenuButton, value: PopupPresentation) =
  if button.isNil or button.xPopupPresentation == value:
    return
  button.xPopupPresentation = value
  if button.popupOpen():
    button.closePopup()

proc menuItemCount(button: PopupMenuButton): int =
  if button.isNil or button.xMenu.isNil:
    return 0
  button.xMenu.len

proc visibleItemCount(button: PopupMenuButton): int =
  visibleListItemCount(button.menuItemCount(), button.xMaxVisibleItems)

proc popupFirstItemIndex(button: PopupMenuButton): int =
  button.xViewport.firstIndex.clampFirstIndex(
    button.menuItemCount(), button.visibleItemCount()
  )

proc popupSize(button: PopupMenuButton): Size =
  initSize(
    max(button.bounds.size.width, 180.0'f32),
    max(button.itemHeight() * button.visibleItemCount().float32 + 2.0'f32, 1.0'f32),
  )

proc popupFrameInSuperview(button: PopupMenuButton): Rect =
  let size = button.popupSize()
  if button.xUsesCascadeFrame:
    return initRect(
      button.xCascadeFrame.origin.x, button.xCascadeFrame.origin.y, size.width,
      size.height,
    )
  initRect(button.frame.origin.x, button.frame.maxY, size.width, size.height)

proc rootPopup(button: PopupMenuButton): PopupMenuButton =
  result = button
  while not result.isNil and not result.xParentPopup.isNil:
    result = result.xParentPopup

proc cascadeSuperview(button: PopupMenuButton): View =
  if button.isNil:
    return nil
  if not button.xParentPopup.isNil:
    return View(button.xParentPopup.popupList())
  button.superview()

proc ownerWindow(button: PopupMenuButton): Window =
  if not button.xParentPopup.isNil:
    return button.xParentPopup.ownerWindow()
  let owner = button.window()
  if owner of Window:
    Window(owner)
  else:
    nil

proc menuItem(button: PopupMenuButton, index: int): MenuItem =
  if button.isNil or button.xMenu.isNil or index < 0 or index >= button.xMenu.len:
    return nil
  button.xMenu[index]

proc menuItemText(button: PopupMenuButton, index: int): string =
  let item = button.menuItem(index)
  if item.isNil:
    return ""
  if item.isSeparatorItem():
    return ""
  item.title()

proc menuItemKeyEquivalentText(button: PopupMenuButton, index: int): string =
  let item = button.menuItem(index)
  if item.isNil:
    return ""
  if item.hasKeyEquivalent():
    let key = item.keyEquivalent()
    if key.text.len > 0:
      var text = ""
      if kmShift in key.modifiers:
        text.add "Shift-"
      if kmControl in key.modifiers:
        text.add "Ctrl-"
      if kmOption in key.modifiers:
        text.add "Opt-"
      if kmCommand in key.modifiers:
        text.add "Cmd-"
      text.add key.text
      return text
  ""

proc menuItemIsSelectable(button: PopupMenuButton, index: int): bool =
  let item = button.menuItem(index)
  not item.isNil and not item.isSeparatorItem() and item.enabled()

proc firstSelectableItemIndex(button: PopupMenuButton): int =
  if button.isNil:
    return -1
  for index in 0 ..< button.menuItemCount():
    if button.menuItemIsSelectable(index):
      return index
  -1

proc lastSelectableItemIndex(button: PopupMenuButton): int =
  if button.isNil:
    return -1
  let count = button.menuItemCount()
  if count <= 0:
    return -1
  for index in countdown(count - 1, 0):
    if button.menuItemIsSelectable(index):
      return index
  -1

proc nextSelectableItemIndex(button: PopupMenuButton, startIndex, delta: int): int =
  if button.isNil or delta == 0:
    return -1
  let count = button.menuItemCount()
  if count <= 0:
    return -1
  var index =
    if startIndex < 0:
      if delta > 0:
        0
      else:
        count - 1
    else:
      startIndex
  for _ in 0 ..< count:
    if index < 0:
      index = count - 1
    elif index >= count:
      index = 0
    if button.menuItemIsSelectable(index):
      return index
    index += delta
  -1

proc setPopupNeedsDisplay(button: PopupMenuButton) =
  button.setNeedsDisplay(true)
  if not button.xPopupList.isNil:
    button.xPopupList.setNeedsDisplay(true)
  if not button.xPopupWindow.isNil and not button.xPopupWindow.contentView().isNil:
    button.xPopupWindow.contentView().setNeedsDisplay(true)

proc setHighlightedIndex(button: PopupMenuButton, index: int, openSubmenu = false) =
  var boundedIndex = if index < 0 or index >= button.menuItemCount(): -1 else: index
  if boundedIndex >= 0 and not button.menuItemIsSelectable(boundedIndex):
    boundedIndex = -1
  if button.xHighlightedIndex == boundedIndex:
    if openSubmenu and boundedIndex >= 0:
      button.openSubmenuPopup(boundedIndex)
    return
  button.xHighlightedIndex = boundedIndex
  if boundedIndex >= 0:
    button.xViewport.scrollToVisible(
      boundedIndex, button.menuItemCount(), button.visibleItemCount()
    )
  if openSubmenu and boundedIndex >= 0:
    button.openSubmenuPopup(boundedIndex)
  elif button.xChildPopupOwnerIndex != boundedIndex:
    button.closeChildPopup()
  button.setPopupNeedsDisplay()

proc scrollPopupRows(button: PopupMenuButton, delta: int) =
  if button.isNil or delta == 0:
    return
  let oldFirst = button.popupFirstItemIndex()
  button.xViewport.scrollBy(delta, button.menuItemCount(), button.visibleItemCount())
  if button.popupFirstItemIndex() != oldFirst:
    button.setPopupNeedsDisplay()

proc activateItem(button: PopupMenuButton, index: int) =
  let item = button.menuItem(index)
  if item.isNil or item.isSeparatorItem() or not item.enabled():
    return
  if not item.submenu().isNil:
    button.openSubmenuPopup(index)
    return
  let owner = button.ownerWindow()
  let start =
    if owner.isNil or owner.firstResponder().isNil:
      Responder(button)
    else:
      owner.firstResponder()
  discard item.perform(start, DynamicAgent(button))
  let root = button.rootPopup()
  if root.isNil:
    button.closePopup()
  else:
    root.closePopup()

proc popupListData(button: PopupMenuButton): PopupListData =
  PopupListData(
    itemCount: proc(): int =
      button.menuItemCount(),
    visibleCount: proc(): int =
      button.visibleItemCount(),
    firstIndex: proc(): int =
      button.popupFirstItemIndex(),
    selectedIndex: proc(): int =
      -1,
    highlightedIndex: proc(): int =
      button.xHighlightedIndex,
    rowHeight: proc(): float32 =
      button.itemHeight(),
    itemText: proc(index: int): string =
      button.menuItemText(index),
    itemKeyEquivalentText: proc(index: int): string =
      button.menuItemKeyEquivalentText(index),
    itemIsSeparator: proc(index: int): bool =
      let item = button.menuItem(index)
      not item.isNil and item.isSeparatorItem(),
    itemHasSubmenu: proc(index: int): bool =
      let item = button.menuItem(index)
      not item.isNil and not item.submenu().isNil,
    itemIsEnabled: proc(index: int): bool =
      let item = button.menuItem(index)
      not item.isNil and item.enabled(),
    itemState: proc(index: int): ButtonState =
      let item = button.menuItem(index)
      if item.isNil:
        bsOff
      else:
        item.state(),
    enabled: proc(): bool =
      button.enabled(),
    focused: proc(): bool =
      button.isFocused(),
    opened: proc(): bool =
      button.popupOpen(),
  )

proc closePopupRoot(button: PopupMenuButton) =
  let root = button.rootPopup()
  if root.isNil:
    button.closePopup()
  else:
    root.closePopup()

proc handlePopupKeyDown(button: PopupMenuButton, event: KeyEvent): bool =
  if button.isNil:
    return false
  case event.key
  of keyEscape:
    button.closePopupRoot()
  of keyArrowDown:
    let nextIndex = button.nextSelectableItemIndex(button.xHighlightedIndex + 1, 1)
    button.setHighlightedIndex(nextIndex)
  of keyArrowUp:
    let nextIndex = button.nextSelectableItemIndex(button.xHighlightedIndex - 1, -1)
    button.setHighlightedIndex(nextIndex)
  of keyHome:
    button.setHighlightedIndex(button.firstSelectableItemIndex())
  of keyEnd:
    button.setHighlightedIndex(button.lastSelectableItemIndex())
  of keyArrowRight:
    let item = button.menuItem(button.xHighlightedIndex)
    if not item.isNil and not item.submenu().isNil and item.enabled():
      button.openSubmenuPopup(button.xHighlightedIndex)
    else:
      discard button.openRelativeMenuBarButton(1)
  of keyArrowLeft:
    if not button.xParentPopup.isNil:
      let parent = button.xParentPopup
      button.closePopup()
      parent.setPopupNeedsDisplay()
    else:
      discard button.openRelativeMenuBarButton(-1)
  of keyEnter:
    button.activateItem(button.xHighlightedIndex)
  else:
    return false
  true

proc popupListActions(button: PopupMenuButton): PopupListActions =
  PopupListActions(
    highlight: proc(index: int) =
      button.setHighlightedIndex(index, openSubmenu = true),
    activate: proc(index: int) =
      button.activateItem(index),
    close: proc() =
      button.closePopupRoot(),
    scroll: proc(delta: int) =
      button.scrollPopupRows(delta),
    keyDown: proc(event: KeyEvent) =
      discard button.handlePopupKeyDown(event),
  )

proc popupList(button: PopupMenuButton): PopupListView =
  if button.xPopupList.isNil:
    button.xPopupList =
      newPopupListView(button.popupListData(), button.popupListActions())
  button.xPopupList

proc popupPresentationPreference(button: PopupMenuButton): PopupPresentation =
  if button.xPopupPresentation == ppAutomatic:
    let owner = button.ownerWindow()
    if owner.isNil:
      return platformDefaultPopupPresentation()
    return owner.effectivePopupPresentation()
  button.xPopupPresentation

proc canUseWindowPopup(button: PopupMenuButton): bool =
  if button.isNil or not button.xParentPopup.isNil or not nativePopupWindowsSupported():
    return false
  let owner = button.ownerWindow()
  not owner.isNil and owner.nativeReady

proc shouldUseWindowPopup(button: PopupMenuButton): bool =
  case button.popupPresentationPreference()
  of ppAutomatic:
    nativePopupWindowsSupported() and button.canUseWindowPopup()
  of ppWindow:
    button.canUseWindowPopup()
  of ppInline:
    false

proc closePopupWindow(button: PopupMenuButton) =
  let popupWindow = button.xPopupWindow
  button.xPopupWindow = nil
  if not popupWindow.isNil and not popupWindow.isClosed:
    popupWindow.close()

proc closeInlinePopup(button: PopupMenuButton) =
  if not button.xPopupList.isNil and not button.xPopupList.superview().isNil:
    button.xPopupList.removeFromSuperview()

proc closeChildPopup(button: PopupMenuButton) =
  let child = button.xChildPopup
  button.xChildPopup = nil
  button.xChildPopupOwnerIndex = -1
  if not child.isNil and child.popupOpen():
    child.closePopup()

proc dismissPopupFromSession(button: PopupMenuButton, reason: DismissReason) =
  case reason
  of tdrProgrammatic, tdrOutsideClick, tdrEscape, tdrFocusChange, tdrOwnerClosed,
      tdrNativeDone:
    if button.popupOpen():
      button.closePopup()

proc beginPopupSession(button: PopupMenuButton) =
  if not button.xParentPopup.isNil:
    return
  let owner = button.ownerWindow()
  if owner.isNil:
    return
  let transient = if button.xPopupWindow.isNil: nil else: button.xPopupWindow
  owner.beginTransientSession(
    owner = Responder(button.popupList()),
    transientWindow = transient,
    restoreResponder = Responder(button),
    onDismiss = proc(reason: DismissReason) =
      button.dismissPopupFromSession(reason),
  )

proc endPopupSession(button: PopupMenuButton) =
  if not button.xParentPopup.isNil:
    return
  let owner = button.ownerWindow()
  if not owner.isNil and owner.hasActiveTransientSession():
    discard owner.endTransientSession()

proc openInlinePopup(button: PopupMenuButton) =
  let parent = button.cascadeSuperview()
  if button.isNil or parent.isNil:
    return
  let popup = button.popupList()
  popup.frame = button.popupFrameInSuperview()
  if popup.superview() != parent:
    parent.addSubview(popup)
  popup.setNeedsDisplay(true)

proc openPopupWindow(button: PopupMenuButton) =
  if button.isNil or not button.shouldUseWindowPopup():
    return
  let owner = button.ownerWindow()
  if owner.isNil or not owner.nativeReady:
    return
  let
    anchorFrame = button.rectToWindow(button.bounds)
    size = button.popupSize()
    popupWindow = owner.newPopupWindow(anchorFrame, size, button.title & " Menu")
    popupView = button.popupList()
  popupView.frame = initRect(0.0, 0.0, size.width, size.height)
  popupWindow.setContentView(popupView)
  popupWindow.setPopupDoneHandler(
    proc() =
      if owner.hasActiveTransientSession():
        discard owner.dismissTransientSession(tdrNativeDone)
  )
  button.xPopupWindow = popupWindow
  popupWindow.makeKeyAndOrderFront()
  popupWindow.ensureNativeWindow()
  if popupWindow.nativeReady:
    discard popupWindow.makeFirstResponder(popupView)
  else:
    button.xPopupWindow = nil
    popupWindow.close()

proc owningMenuBar(button: PopupMenuButton): MenuBar =
  if button.isNil:
    return nil
  let parent = button.superview()
  if parent of MenuBar:
    MenuBar(parent)
  else:
    nil

proc noteMenuBarPopupOpened(button: PopupMenuButton) =
  let menuBar = button.owningMenuBar()
  if not menuBar.isNil:
    menuBar.xOpenButton = button

proc noteMenuBarPopupClosed(button: PopupMenuButton) =
  let menuBar = button.owningMenuBar()
  if not menuBar.isNil and menuBar.xOpenButton == button:
    menuBar.xOpenButton = nil

proc openPopupImpl(button: PopupMenuButton) =
  if button.isNil or button.xMenu.isNil or button.menuItemCount() == 0:
    return
  if button.popupOpen():
    return
  button.xPopupOpen = true
  button.xHighlightedIndex = button.firstSelectableItemIndex()
  button.xViewport.normalize(button.menuItemCount(), button.visibleItemCount())
  if button.xHighlightedIndex >= 0:
    button.xViewport.scrollToVisible(
      button.xHighlightedIndex, button.menuItemCount(), button.visibleItemCount()
    )
  button.xMenu.open()
  if button.shouldUseWindowPopup():
    button.openPopupWindow()
  else:
    button.openInlinePopup()
  button.beginPopupSession()
  button.noteMenuBarPopupOpened()
  button.setWidgetState(ssOpen, true)
  button.setNeedsDisplay(true)

proc closePopupImpl(button: PopupMenuButton) =
  if button.isNil or not button.popupOpen():
    return
  button.closeChildPopup()
  button.xPopupOpen = false
  button.xHighlightedIndex = -1
  button.endPopupSession()
  button.closePopupWindow()
  button.closeInlinePopup()
  if not button.xMenu.isNil:
    button.xMenu.close()
  if not button.xParentPopup.isNil and button.xParentPopup.xChildPopup == button:
    button.xParentPopup.xChildPopup = nil
    button.xParentPopup.xChildPopupOwnerIndex = -1
  button.noteMenuBarPopupClosed()
  button.setWidgetState(ssOpen, false)
  button.setNeedsDisplay(true)

protocol PopupMenuButtonDrawing of ViewDrawingProtocol:
  method draw(button: PopupMenuButton, context: DrawContext) =
    let states = button.widgetStateSet()
    let isPullDown = button.hasStyleClass("pullDown")
    let fillColor =
      if isPullDown and (ssOpen in states or ssActive in states):
        initColor(0.58, 0.66, 0.82)
      elif isPullDown and ssHovered in states:
        initColor(0.76, 0.81, 0.91)
      elif ssOpen in states or ssActive in states:
        initColor(0.78, 0.84, 0.96)
      elif ssHovered in states:
        initColor(0.88, 0.91, 0.97)
      else:
        initColor(0.0, 0.0, 0.0, 0.0)
    let borderColor =
      if isPullDown and (ssOpen in states or ssActive in states):
        initColor(0.30, 0.36, 0.48)
      elif isPullDown and ssHovered in states:
        initColor(0.45, 0.50, 0.62)
      elif ssOpen in states or ssHovered in states:
        initColor(0.50, 0.54, 0.62)
      else:
        initColor(0.0, 0.0, 0.0, 0.0)
    discard context.addRenderRectangle(
      context.renderRectFor(button.bounds),
      fill(fillColor),
      borderColor,
      if ssOpen in states or ssHovered in states: 1.0'f32 else: 0.0'f32,
      4.0'f32,
    )
    context.addText(
      button.bounds.inset(initEdgeInsets(6.0, 10.0, 2.0, 10.0)),
      button.title(),
      initColor(0.08, 0.09, 0.11),
    )

protocol PopupMenuButtonEvents of ResponderEventProtocol:
  method mouseEntered(button: PopupMenuButton, event: MouseEvent): bool =
    button.hovered = true
    let menuBar = button.owningMenuBar()
    if not menuBar.isNil and not menuBar.xOpenButton.isNil and
        menuBar.xOpenButton != button and button.enabled():
      menuBar.xOpenButton.closePopup()
      button.openPopup()
    true

  method mouseExited(button: PopupMenuButton, event: MouseEvent): bool =
    button.hovered = false
    button.active = false
    true

  method mouseDown(button: PopupMenuButton, event: MouseEvent): bool =
    if button.enabled() and event.button == mbPrimary:
      button.active = true
      return true

  method mouseUp(button: PopupMenuButton, event: MouseEvent): bool =
    if button.enabled() and event.button == mbPrimary:
      let clicked = button.bounds.contains(event.location)
      button.active = false
      if clicked:
        if button.popupOpen():
          button.closePopup()
        else:
          button.openPopup()
      return true

  method keyDown(button: PopupMenuButton, event: KeyEvent): bool =
    case event.key
    of keyEscape:
      let root = button.rootPopup()
      if root.isNil:
        button.closePopup()
      else:
        root.closePopup()
      true
    of keyEnter, keyArrowDown:
      button.openPopup()
      true
    of keyArrowLeft:
      button.openRelativeMenuBarButton(-1)
    of keyArrowRight:
      button.openRelativeMenuBarButton(1)
    else:
      false

proc initPopupMenuButtonFields*(
    button: PopupMenuButton, title = "", menu: Menu = nil, frame: Rect = AutoRect
) =
  initControlFields(button, frame, newActionCell())
  button.xTitle = title
  button.xMaxVisibleItems = popupMenuDefaultMaxVisibleItems()
  button.xItemHeight = popupMenuDefaultItemHeight()
  button.xHighlightedIndex = -1
  button.xChildPopupOwnerIndex = -1
  button.xPopupPresentation = ppAutomatic
  button.background = initColor(0.0, 0.0, 0.0, 0.0)
  button.menu = menu
  button.setAcceptsFirstResponder(true)
  discard button.withProto()
  discard button.withProtocol(PopupMenuButtonDrawing)
  discard button.withProtocol(PopupMenuButtonEvents)
  button.applyInitialFrame(frame)

proc newPopupMenuButton*(
    title = "", menu: Menu = nil, frame: Rect = AutoRect
): PopupMenuButton =
  result = PopupMenuButton()
  initPopupMenuButtonFields(result, title, menu, frame)

proc newPullDownButton*(
    title = "", menu: Menu = nil, frame: Rect = AutoRect
): PopupMenuButton =
  result = newPopupMenuButton(title, menu, frame)
  result.addStyleClass("pullDown")

proc submenuCascadeFrame(button: PopupMenuButton, index: int): Rect =
  let
    parentList = button.popupList()
    itemRect = parentList.popupListItemRect(parentList.bounds(), index)
  initRect(
    max(itemRect.maxX - 1.0'f32, 0.0'f32),
    itemRect.origin.y,
    180.0'f32,
    itemRect.size.height,
  )

proc openSubmenuPopup(button: PopupMenuButton, index: int) =
  let item = button.menuItem(index)
  if item.isNil or item.submenu().isNil or not item.enabled():
    button.closeChildPopup()
    return
  if not button.xChildPopup.isNil and button.xChildPopupOwnerIndex == index and
      button.xChildPopup.popupOpen():
    return

  button.closeChildPopup()
  let child = newPopupMenuButton(item.title(), item.submenu())
  child.xParentPopup = button
  child.xCascadeFrame = button.submenuCascadeFrame(index)
  child.xUsesCascadeFrame = true
  child.xPopupPresentation = ppInline
  child.xMaxVisibleItems = button.xMaxVisibleItems
  child.xItemHeight = button.xItemHeight
  child.setInheritedAppearance(button.effectiveAppearance())
  button.xChildPopup = child
  button.xChildPopupOwnerIndex = index
  child.openPopup()
  button.setPopupNeedsDisplay()

proc openRelativeMenuBarButton(button: PopupMenuButton, delta: int): bool =
  let menuBar = button.owningMenuBar()
  if menuBar.isNil or menuBar.xButtons.len == 0 or delta == 0:
    return false
  let currentIndex = menuBar.xButtons.find(button)
  if currentIndex < 0:
    return false

  var index = currentIndex + delta
  for _ in 0 ..< menuBar.xButtons.len:
    if index < 0:
      index = menuBar.xButtons.len - 1
    elif index >= menuBar.xButtons.len:
      index = 0
    let candidate = menuBar.xButtons[index]
    if not candidate.isNil and candidate.enabled():
      if menuBar.xOpenButton != candidate:
        if not menuBar.xOpenButton.isNil:
          menuBar.xOpenButton.closePopup()
        candidate.openPopup()
      return true
    index += delta
  false

proc menu*(menuBar: MenuBar): Menu =
  if menuBar.isNil: nil else: menuBar.xMenu

proc menuBarItemWidth(item: MenuItem): float32 =
  if item.isNil:
    return 0.0'f32
  max(textNaturalSize(item.title()).width + menuBarItemPadding(), 44.0'f32)

proc menuBarNaturalSize(menuBar: MenuBar): Size =
  var width = menuBarHorizontalInset()
  if not menuBar.isNil and not menuBar.xMenu.isNil:
    for item in menuBar.xMenu.items:
      width += menuBarItemWidth(item) + menuBarItemGap()
  initSize(width + menuBarHorizontalInset(), menuBarDefaultHeight())

proc clearMenuBarButtons(menuBar: MenuBar) =
  for button in menuBar.xButtons:
    button.closePopup()
    button.removeFromSuperview()
  menuBar.xButtons.setLen(0)
  menuBar.xOpenButton = nil

proc reloadImpl(menuBar: MenuBar) =
  if menuBar.isNil:
    return
  menuBar.clearMenuBarButtons()
  if menuBar.xMenu.isNil:
    menuBar.setNeedsLayout()
    menuBar.setNeedsDisplay(true)
    return
  for item in menuBar.xMenu.items:
    let button = newPullDownButton(item.title(), item.submenu())
    button.enabled = not item.submenu().isNil
    button.popupPresentation = ppAutomatic
    menuBar.addSubview(button)
    menuBar.xButtons.add button
  menuBar.setNeedsLayout()
  menuBar.setNeedsDisplay(true)

proc `menu=`*(menuBar: MenuBar, menu: Menu) =
  if menuBar.isNil or menuBar.xMenu == menu:
    return
  menuBar.xMenu = menu
  menuBar.reload()

proc tileMenuBarItems(menuBar: MenuBar) =
  if menuBar.isNil:
    return
  var x = menuBarHorizontalInset()
  let
    bounds = menuBar.bounds()
    buttonHeight = min(max(bounds.size.height - 4.0'f32, 0.0'f32), 24.0'f32)
    buttonY = max((bounds.size.height - buttonHeight) / 2.0'f32, 0.0'f32)
  if menuBar.xMenu.isNil:
    return
  for index, button in menuBar.xButtons:
    if index < menuBar.xMenu.len:
      let
        item = menuBar.xMenu[index]
        width = menuBarItemWidth(item)
      button.title = item.title()
      button.menu = item.submenu()
      button.enabled = not item.submenu().isNil
      button.frame = initRect(x, buttonY, width, buttonHeight)
      x += width + menuBarItemGap()

protocol MenuBarDrawing of ViewDrawingProtocol:
  method draw(menuBar: MenuBar, context: DrawContext) =
    let bounds = menuBar.bounds()
    if bounds.isEmpty:
      return
    discard context.addRenderRectangle(
      initRect(0.0'f32, bounds.maxY - 1.0'f32, bounds.size.width, 1.0'f32),
      fill(initColor(0.76, 0.78, 0.82)),
    )

protocol MenuBarLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(menuBar: MenuBar): IntrinsicSize =
    initIntrinsicSize(menuBar.menuBarNaturalSize())

  method layoutSubviews(menuBar: MenuBar) =
    menuBar.tileMenuBarItems()

proc initMenuBarFields*(menuBar: MenuBar, menu: Menu = nil, frame: Rect = AutoRect) =
  initViewFields(menuBar, frame)
  menuBar.background = initColor(0.91, 0.92, 0.94)
  discard menuBar.withProto()
  discard menuBar.withProtocol(MenuBarDrawing)
  discard menuBar.withProtocol(MenuBarLayout)
  menuBar.menu = menu
  menuBar.applyInitialFrame(frame)

proc newMenuBar*(menu: Menu = nil, frame: Rect = AutoRect): MenuBar =
  result = MenuBar()
  initMenuBarFields(result, menu, frame)
