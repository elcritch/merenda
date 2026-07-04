import std/options

import sigils/core
import sigils/selectors

import ../accessibility/accessibilityprotocols
import ./controls
import ../drawing
import ../foundation/events
import ../responder/keybindings
import ../containers/listbasics
import ./popuplists
import ../responder/responders
import ../foundation/selectors as nimkitSelectors
import ../themes
import ../foundation/types
import ../app/windows

type
  MenuItemModel* = object
    identifier*: string
    title*: string
    subtitle*: string
    objectValue*: ObjectValue
    state*: ButtonState
    enabled*: bool
    hidden*: bool
    separator*: bool
    image*: ImageResource
    keyEquivalent*: KeyStroke
    hasKeyEquivalent*: bool
    target*: DynamicAgent
    action*: ActionSelector
    representedObject*: DynamicAgent
    userInfo*: DynamicAgent
    tag*: int
    validates*: bool
    children*: seq[MenuItemModel]

  MenuItem* = ref object of Responder
    xIdentifier: string
    xTitle: string
    xSubtitle: string
    xAction: ActionSelector
    xTarget: DynamicAgent
    xState: ButtonState
    xEnabled: bool
    xHidden: bool
    xKeyEquivalent: KeyStroke
    xHasKeyEquivalent: bool
    xSubmenu: Menu
    xSeparator: bool
    xImage: ImageResource
    xTag: int
    xObjectValue: ObjectValue
    xRepresentedObject: DynamicAgent
    xUserInfo: DynamicAgent
    xValidates: bool

  Menu* = ref object of Responder
    xTitle: string
    xItems: seq[MenuItem]
    xItemModels: seq[MenuItemModel]
    xUsesItemModels: bool
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xOpen: bool

  PopupMenuButton* = ref object of Control
    xTitle: string
    xMenu: Menu
    xPopupList: PopupListView
    xPopupWindow: Window
    xPopupOpen: bool
    xRestoreResponder: Responder
    xActionStartResponder: Responder
    xUsesCustomRestoreResponder: bool
    xRemoveFromSuperviewOnClose: bool
    xHighlightedIndex: int
    xViewport: RowViewport
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
proc rebuildMenuItemsFromModels(menu: Menu)
proc reloadData*(menu: Menu)
proc itemModels*(menu: Menu): seq[MenuItemModel]
proc `itemModels=`*(menu: Menu, models: openArray[MenuItemModel])
proc popupList(button: PopupMenuButton): PopupListView
proc closeChildPopup(button: PopupMenuButton)
proc openSubmenuPopup(button: PopupMenuButton, index: int)
proc openRelativeMenuBarButton(button: PopupMenuButton, delta: int): bool
proc handlePopupKeyDown(button: PopupMenuButton, event: KeyEvent): bool
proc menu*(view: View): Menu
proc `menu=`*(view: View, menu: Menu)
proc popUpContextMenu*(
  menu: Menu, view: View, event: MouseEvent
): PopupMenuButton {.discardable.}

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

protocol MenuDataSource {.selectorScope: protocol.}:
  method menuItemCount*(menu: Menu): int {.optional.}
  method menuItemModelAtIndex*(menu: Menu, index: int): MenuItemModel {.optional.}
  method indexOfMenuItemModelIdentifier*(
    menu: Menu, identifier: string
  ): int {.optional.}

protocol MenuEvents:
  proc menuItemDidActivate*(
    menu: Menu, sender: DynamicAgent, identifier: string
  ) {.signal.}

protocol PopupMenuButtonProtocol {.selectorScope: protocol.} from PopupMenuButton:
  method openPopupMenu*(button: PopupMenuButton) =
    button.openPopupImpl()

  method closePopupMenu*(button: PopupMenuButton) =
    button.closePopupImpl()

protocol MenuBarProtocol {.selectorScope: protocol.} from MenuBar:
  method reloadMenuBar*(menuBar: MenuBar) =
    menuBar.reloadImpl()

protocol MenuAccessibility of AccessibilityProtocol:
  method accessibilityRole(menu: Menu): AccessibilityRole =
    arMenu

  method accessibilityLabel(menu: Menu): string =
    if menu.isNil: "" else: menu.xTitle

  method accessibilityValue(menu: Menu): string =
    if menu.isNil:
      "0"
    else:
      $menu.xItems.len()

  method isAccessibilityElement(menu: Menu): bool =
    true

protocol MenuItemAccessibility of AccessibilityProtocol:
  method accessibilityRole(item: MenuItem): AccessibilityRole =
    arMenuItem

  method accessibilityLabel(item: MenuItem): string =
    if item.isNil: "" else: item.xTitle

  method accessibilityValue(item: MenuItem): string =
    if item.isNil:
      return ""
    case item.xState
    of bsOff: ""
    of bsOn: "on"
    of bsMixed: "mixed"

  method accessibilityTraits(item: MenuItem): AccessibilityTraits =
    if item.isNil or not item.xEnabled:
      result.incl atDisabled
    if not item.isNil and not item.xSubmenu.isNil:
      result.incl atButton
    if not item.isNil and item.xState in {bsOn, bsMixed}:
      result.incl atSelected

  method isAccessibilityElement(item: MenuItem): bool =
    not item.isNil and not item.xSeparator

  method accessibilityActionNames(item: MenuItem): seq[string] =
    if not item.isNil and item.xEnabled and not item.xSeparator:
      @[AccessibilityActionPress]
    else:
      @[]

protocol PopupMenuButtonAccessibility of AccessibilityProtocol:
  method accessibilityRole(button: PopupMenuButton): AccessibilityRole =
    arPopupButton

  method accessibilityLabel(button: PopupMenuButton): string =
    if button.xAccessibilityLabel.len > 0: button.xAccessibilityLabel else: button.xTitle

  method accessibilityValue(button: PopupMenuButton): string =
    if button.popupOpen(): "open" else: "closed"

  method accessibilityTraits(button: PopupMenuButton): AccessibilityTraits =
    result = button.xAccessibilityTraits + {atButton}
    if not button.enabled():
      result.incl atDisabled
    if button.focused():
      result.incl atFocused

  method isAccessibilityElement(button: PopupMenuButton): bool =
    true

  method accessibilityActionNames(button: PopupMenuButton): seq[string] =
    @[AccessibilityActionShowMenu]

  method accessibilityPerformAction(button: PopupMenuButton, action: string): bool =
    if action != AccessibilityActionShowMenu or not button.enabled():
      return false
    button.openPopup()
    true

protocol MenuBarAccessibility of AccessibilityProtocol:
  method accessibilityRole(menuBar: MenuBar): AccessibilityRole =
    arMenu

  method accessibilityValue(menuBar: MenuBar): string =
    if menuBar.xMenu.isNil:
      "0"
    else:
      $menuBar.xMenu.xItems.len()

  method isAccessibilityElement(menuBar: MenuBar): bool =
    true

protocol ViewContextMenuEvents of ResponderEventProtocol:
  method rightMouseDown(view: View, event: MouseEvent): bool =
    let next = view.trySendNext(rightMouseDown(), event)
    if next.isSome and next.get():
      return true
    not view.menu().popUpContextMenu(view, event).isNil

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

proc initMenuItemModel*(
    identifier = "",
    title = "",
    subtitle = "",
    objectValue = emptyObjectValue(),
    state = bsOff,
    enabled = true,
    hidden = false,
    separator = false,
    image: ImageResource = nil,
    action: ActionSelector = ActionSelector(),
    target: DynamicAgent = nil,
    keyEquivalent = KeyStroke(),
    hasKeyEquivalent = false,
    representedObject: DynamicAgent = nil,
    userInfo: DynamicAgent = nil,
    tag = 0,
    validates = true,
    children: openArray[MenuItemModel] = [],
): MenuItemModel =
  let keyIsSet =
    hasKeyEquivalent or keyEquivalent.text.len > 0 or keyEquivalent.key != keyUnknown or
    keyEquivalent.keyCode != 0
  MenuItemModel(
    identifier: identifier,
    title: title,
    subtitle: subtitle,
    objectValue: objectValue,
    state: state,
    enabled: enabled,
    hidden: hidden,
    separator: separator,
    image: image,
    keyEquivalent: keyEquivalent,
    hasKeyEquivalent: keyIsSet,
    target: target,
    action: action,
    representedObject: representedObject,
    userInfo: userInfo,
    tag: tag,
    validates: validates,
    children: @children,
  )

proc menuItemModelTitle(model: MenuItemModel): string =
  if model.title.len > 0:
    model.title
  else:
    model.objectValue.formatObjectValue(initObjectFormatContext(role = ovrMenu))

proc newMenu*(title = ""): Menu =
  result = Menu(xTitle: title)
  initResponder(result)
  discard result.withProto()
  discard result.withProtocol(MenuAccessibility)

proc newMenuItem*(
    title = "",
    action: ActionSelector = ActionSelector(),
    keyEquivalent = "",
    modifiers: set[KeyModifier] = {},
): MenuItem =
  result = MenuItem(xTitle: title, xAction: action, xEnabled: true, xValidates: true)
  result.xObjectValue = toObj(title)
  initResponder(result)
  if keyEquivalent.len > 0:
    result.xKeyEquivalent = initKeyStroke(keyEquivalent, modifiers)
    result.xHasKeyEquivalent = true
  discard result.withProtocol(MenuItemAccessibility)

proc separatorMenuItem*(): MenuItem =
  result = newMenuItem()
  result.xSeparator = true
  result.xEnabled = false

proc newMenuItem*(
    value: ObjectValue,
    action: ActionSelector = ActionSelector(),
    keyEquivalent = "",
    modifiers: set[KeyModifier] = {},
): MenuItem =
  result = newMenuItem(
    value.formatObjectValue(initObjectFormatContext(role = ovrMenu)),
    action,
    keyEquivalent,
    modifiers,
  )
  result.xObjectValue = value

proc newMenuItem*(model: MenuItemModel): MenuItem =
  if model.separator:
    result = separatorMenuItem()
  else:
    result = newMenuItem(model.menuItemModelTitle(), model.action)
  result.xIdentifier = model.identifier
  result.xSubtitle = model.subtitle
  result.xState = model.state
  result.xEnabled = model.enabled and not model.separator
  result.xHidden = model.hidden
  result.xSeparator = model.separator
  result.xImage = model.image
  result.xTarget = model.target
  result.xRepresentedObject = model.representedObject
  result.xUserInfo = model.userInfo
  result.xTag = model.tag
  result.xValidates = model.validates
  if model.objectValue.isNilOrEmpty() and result.xTitle.len > 0:
    result.xObjectValue = toObj(result.xTitle)
  else:
    result.xObjectValue = model.objectValue
  if model.hasKeyEquivalent:
    result.xKeyEquivalent = model.keyEquivalent
    result.xHasKeyEquivalent = true
  if model.children.len > 0:
    let submenu = newMenu(result.xTitle)
    submenu.itemModels = model.children
    result.xSubmenu = submenu
    submenu.setNextResponder(result)

proc identifier*(item: MenuItem): string =
  if item.isNil: "" else: item.xIdentifier

proc `identifier=`*(item: MenuItem, identifier: string) =
  if not item.isNil:
    item.xIdentifier = identifier

proc title*(item: MenuItem): string =
  if item.isNil: "" else: item.xTitle

proc `title=`*(item: MenuItem, title: string) =
  if not item.isNil:
    item.xTitle = title
    item.xObjectValue = toObj(title)

proc subtitle*(item: MenuItem): string =
  if item.isNil: "" else: item.xSubtitle

proc `subtitle=`*(item: MenuItem, subtitle: string) =
  if not item.isNil:
    item.xSubtitle = subtitle

proc objectValue*(item: MenuItem): ObjectValue =
  if item.isNil:
    nilObjectValue()
  else:
    item.xObjectValue

proc `objectValue=`*(item: MenuItem, value: ObjectValue) =
  if item.isNil:
    return
  item.xObjectValue = value
  item.xTitle = value.formatObjectValue(initObjectFormatContext(role = ovrMenu))

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

proc hidden*(item: MenuItem): bool =
  (not item.isNil) and item.xHidden

proc `hidden=`*(item: MenuItem, hidden: bool) =
  if not item.isNil:
    item.xHidden = hidden

proc validates*(item: MenuItem): bool =
  (not item.isNil) and item.xValidates

proc `validates=`*(item: MenuItem, validates: bool) =
  if not item.isNil:
    item.xValidates = validates

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

proc image*(item: MenuItem): ImageResource =
  if item.isNil: nil else: item.xImage

proc `image=`*(item: MenuItem, image: ImageResource) =
  if not item.isNil:
    item.xImage = image

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

proc menuItemModel*(item: MenuItem): MenuItemModel =
  if item.isNil:
    return initMenuItemModel(enabled = false, hidden = true)
  let objectValue =
    if item.xObjectValue.isNilOrEmpty() and item.xTitle.len > 0:
      toObj(item.xTitle)
    else:
      item.xObjectValue
  var children: seq[MenuItemModel]
  if not item.xSubmenu.isNil:
    children = item.xSubmenu.itemModels()
  initMenuItemModel(
    identifier = item.xIdentifier,
    title = item.xTitle,
    subtitle = item.xSubtitle,
    objectValue = objectValue,
    state = item.xState,
    enabled = item.xEnabled,
    hidden = item.xHidden,
    separator = item.xSeparator,
    image = item.xImage,
    action = item.xAction,
    target = item.xTarget,
    keyEquivalent = item.xKeyEquivalent,
    hasKeyEquivalent = item.xHasKeyEquivalent,
    representedObject = item.xRepresentedObject,
    userInfo = item.xUserInfo,
    tag = item.xTag,
    validates = item.xValidates,
    children = children,
  )

proc menu*(view: View): Menu =
  if view.isNil or view.xContextMenu.isNil or not (view.xContextMenu of Menu):
    return nil
  Menu(view.xContextMenu)

proc `menu=`*(view: View, menu: Menu) =
  if view.isNil or view.xContextMenu == Responder(menu):
    return
  if not view.xContextMenu.isNil and view.xContextMenu.nextResponder() == Responder(
    view
  ):
    view.xContextMenu.clearNextResponder()
  view.xContextMenu = Responder(menu)
  if not menu.isNil:
    menu.setNextResponder(view)
    if not view.xContextMenuHandlerInstalled:
      discard view.pushMethods(ViewContextMenuEvents.init())
      view.xContextMenuHandlerInstalled = true

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

proc dataSource*(menu: Menu): DynamicAgent =
  if menu.isNil: nil else: menu.xDataSource

proc `dataSource=`*(menu: Menu, dataSource: DynamicAgent) =
  if menu.isNil or menu.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(MenuDataSource)
  menu.xDataSource = dataSource
  menu.reloadData()

proc `dataSource=`*(menu: Menu, dataSource: Responder) =
  menu.dataSource = DynamicAgent(dataSource)

proc items*(menu: Menu): lent seq[MenuItem] =
  menu.xItems

proc itemModels*(menu: Menu): seq[MenuItemModel] =
  if menu.isNil:
    return
  if menu.xUsesItemModels:
    return menu.xItemModels
  for item in menu.xItems:
    result.add item.menuItemModel()

proc clearMenuItems(menu: Menu) =
  if menu.isNil:
    return
  for item in menu.xItems:
    if not item.isNil and item.nextResponder() == Responder(menu):
      item.clearNextResponder()
  menu.xItems.setLen(0)

proc rebuildMenuItemsFromModels(menu: Menu) =
  if menu.isNil:
    return
  menu.clearMenuItems()
  for model in menu.xItemModels:
    if not model.hidden:
      let item = newMenuItem(model)
      menu.xItems.add item
      item.setNextResponder(menu)

proc `itemModels=`*(menu: Menu, models: openArray[MenuItemModel]) =
  if menu.isNil:
    return
  menu.xItemModels = @models
  menu.xUsesItemModels = true
  menu.rebuildMenuItemsFromModels()

proc reloadData*(menu: Menu) =
  if menu.isNil:
    return
  if menu.xDataSource.isNil:
    if menu.xUsesItemModels:
      menu.rebuildMenuItemsFromModels()
    return

  let count = menu.xDataSource.trySendLocal(menuItemCount(), menu)
  if count.isNone:
    return
  var models: seq[MenuItemModel]
  for index in 0 ..< count.get():
    let model =
      menu.xDataSource.trySendLocal(menuItemModelAtIndex(), (menu: menu, index: index))
    if model.isSome:
      models.add model.get()
  menu.itemModels = models

proc len*(menu: Menu): int =
  if menu.isNil: 0 else: menu.xItems.len

proc `[]`*(menu: Menu, index: Natural): MenuItem =
  menu.xItems[index]

proc menuItemAtIndex*(menu: Menu, index: int): MenuItem =
  if menu.isNil or index < 0 or index >= menu.len():
    nil
  else:
    menu.xItems[index]

proc indexOfMenuItemIdentifier*(menu: Menu, identifier: string): int =
  if menu.isNil or identifier.len == 0:
    return -1
  if not menu.xDataSource.isNil:
    let found = menu.xDataSource.trySendLocal(
      indexOfMenuItemModelIdentifier(), (menu: menu, identifier: identifier)
    )
    if found.isSome:
      return found.get()
  for index, item in menu.xItems:
    if not item.isNil and item.identifier() == identifier:
      return index
  -1

proc menuItemWithIdentifier*(menu: Menu, identifier: string): MenuItem =
  let index = menu.indexOfMenuItemIdentifier(identifier)
  if index >= 0:
    menu.menuItemAtIndex(index)
  else:
    nil

proc visibleModelIndex(menu: Menu, visibleIndex: int): int =
  if menu.isNil or visibleIndex < 0:
    return -1
  var current = 0
  for index, model in menu.xItemModels:
    if not model.hidden:
      if current == visibleIndex:
        return index
      inc current
  -1

proc indexOfModelIdentifier(menu: Menu, identifier: string): int =
  if menu.isNil or identifier.len == 0:
    return -1
  for index, model in menu.xItemModels:
    if model.identifier == identifier:
      return index
  -1

proc addItem*(menu: Menu, item: MenuItem): MenuItem {.discardable.} =
  if menu.isNil or item.isNil:
    return nil
  if menu.xUsesItemModels:
    menu.xItemModels.add item.menuItemModel()
  menu.xItems.add item
  item.setNextResponder(menu)
  item

proc addItem*(menu: Menu, model: MenuItemModel): MenuItem {.discardable.} =
  if menu.isNil:
    return nil
  menu.xUsesItemModels = true
  menu.xItemModels.add model
  if model.hidden:
    return nil
  let item = newMenuItem(model)
  menu.xItems.add item
  item.setNextResponder(menu)
  item

proc insertItem*(
    menu: Menu, model: MenuItemModel, index: int
): MenuItem {.discardable.} =
  if menu.isNil:
    return nil
  menu.xUsesItemModels = true
  let modelIndex =
    if menu.xItemModels.len == 0:
      0
    else:
      max(0, min(index, menu.xItemModels.len))
  menu.xItemModels.insert(model, modelIndex)
  menu.rebuildMenuItemsFromModels()
  if model.identifier.len > 0:
    return menu.menuItemWithIdentifier(model.identifier)
  if model.hidden:
    return nil
  var visibleIndex = 0
  for index in 0 ..< modelIndex:
    if not menu.xItemModels[index].hidden:
      inc visibleIndex
  if visibleIndex >= 0:
    return menu.menuItemAtIndex(visibleIndex)

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
  if menu.xUsesItemModels:
    let modelIndex =
      if item.identifier().len > 0:
        menu.indexOfModelIdentifier(item.identifier())
      else:
        menu.visibleModelIndex(idx)
    if modelIndex >= 0:
      menu.xItemModels.delete(modelIndex)
  if item.nextResponder() == Responder(menu):
    item.clearNextResponder()
  menu.xItems.delete(idx)
  true

proc removeItemWithIdentifier*(menu: Menu, identifier: string): bool {.discardable.} =
  if menu.isNil or identifier.len == 0:
    return false
  let item = menu.menuItemWithIdentifier(identifier)
  if not item.isNil:
    return menu.removeItem(item)
  if menu.xUsesItemModels:
    let modelIndex = menu.indexOfModelIdentifier(identifier)
    if modelIndex >= 0:
      menu.xItemModels.delete(modelIndex)
      menu.rebuildMenuItemsFromModels()
      return true
  false

proc removeAllItems*(menu: Menu) =
  if menu.isNil:
    return
  menu.xItemModels.setLen(0)
  menu.xUsesItemModels = false
  menu.clearMenuItems()

proc menuNeedsUpdate*(menu: Menu) =
  if not menu.isNil and not menu.xDelegate.isNil:
    discard menu.xDelegate.sendLocalIfHandled(menuNeedsUpdate(), DynamicAgent(menu))

proc openImpl(menu: Menu) =
  if menu.isNil:
    return
  menu.menuNeedsUpdate()
  if not menu.xDataSource.isNil:
    menu.reloadData()
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
  if item.isNil or item.xSeparator or item.xHidden:
    return false
  if not item.xValidates:
    return item.xEnabled
  if not item.xSubmenu.isNil:
    return true
  if item.xAction.name.len == 0:
    return item.xEnabled
  if target.isNil:
    return false
  let validated = target.trySendLocal(
    validateUserInterfaceItem(), ValidationArgs(item: item, action: item.xAction)
  )
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

proc syncMenuItemModelFromItem(menu: Menu, item: MenuItem, visibleIndex: int) =
  if menu.isNil or item.isNil or not menu.xUsesItemModels:
    return
  let modelIndex =
    if item.identifier().len > 0:
      menu.indexOfModelIdentifier(item.identifier())
    else:
      menu.visibleModelIndex(visibleIndex)
  if modelIndex >= 0:
    menu.xItemModels[modelIndex] = item.menuItemModel()

proc updateImpl(menu: Menu, start: Responder) =
  if menu.isNil:
    return
  menu.menuNeedsUpdate()
  if not menu.xDataSource.isNil:
    menu.reloadData()
  for index, item in menu.xItems:
    if not item.isNil:
      if item.xSubmenu.isNil:
        item.xEnabled = item.validate(start)
      else:
        item.xSubmenu.update(start)
      menu.syncMenuItemModelFromItem(item, index)

proc notifyMenuItemDidActivate(menu: Menu, item: MenuItem, sender: DynamicAgent) =
  if menu.isNil or item.isNil:
    return
  emit menu.menuItemDidActivate(
    if sender.isNil:
      DynamicAgent(item)
    else:
      sender,
    item.identifier(),
  )

proc perform*(item: MenuItem, start: Responder, sender: DynamicAgent = nil): bool =
  if item.isNil or item.xSeparator or item.xHidden or not item.xEnabled:
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
    if item.isNil or item.xSeparator or item.xHidden:
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
  result = item.perform(start)
  if result:
    menu.notifyMenuItemDidActivate(item, DynamicAgent(item))

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
  visibleRowItemCount(button.menuItemCount(), button.xMaxVisibleItems)

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
  if item.subtitle().len > 0:
    return item.subtitle()
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
  not item.isNil and not item.hidden() and not item.isSeparatorItem() and item.enabled()

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

proc actionStartResponder(button: PopupMenuButton): Responder =
  let root = button.rootPopup()
  if not root.isNil and not root.xActionStartResponder.isNil:
    return root.xActionStartResponder
  let owner = button.ownerWindow()
  if owner.isNil or owner.firstResponder().isNil:
    Responder(button)
  else:
    owner.firstResponder()

proc activateItem(button: PopupMenuButton, index: int) =
  let item = button.menuItem(index)
  if item.isNil or item.hidden() or item.isSeparatorItem() or not item.enabled():
    return
  if not item.submenu().isNil:
    button.openSubmenuPopup(index)
    return
  discard item.perform(button.actionStartResponder(), DynamicAgent(button))
  if not button.xMenu.isNil:
    button.xMenu.notifyMenuItemDidActivate(item, DynamicAgent(button))
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
      not item.isNil and not item.hidden() and not item.submenu().isNil,
    itemIsEnabled: proc(index: int): bool =
      let item = button.menuItem(index)
      not item.isNil and not item.hidden() and item.enabled(),
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
  let restore =
    if button.xUsesCustomRestoreResponder:
      button.xRestoreResponder
    else:
      Responder(button)
  owner.beginTransientSession(
    owner = Responder(button.popupList()),
    transientWindow = transient,
    restoreResponder = restore,
    onDismiss = proc(reason: DismissReason) =
      button.dismissPopupFromSession(reason),
    restoreCurrentResponderIfNil = not button.xUsesCustomRestoreResponder,
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
  if button.isNil or button.xMenu.isNil:
    return
  if button.popupOpen():
    return
  button.xMenu.open()
  button.xMenu.update(button.actionStartResponder())
  if button.menuItemCount() == 0:
    button.xMenu.close()
    return
  button.xPopupOpen = true
  button.xHighlightedIndex = button.firstSelectableItemIndex()
  button.xViewport.normalize(button.menuItemCount(), button.visibleItemCount())
  if button.xHighlightedIndex >= 0:
    button.xViewport.scrollToVisible(
      button.xHighlightedIndex, button.menuItemCount(), button.visibleItemCount()
    )
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
  if button.xRemoveFromSuperviewOnClose and not button.superview().isNil:
    button.removeFromSuperview()

protocol PopupMenuButtonDrawing of ViewDrawingProtocol:
  method draw(button: PopupMenuButton, context: DrawContext) =
    let states = button.widgetStateSet()
    let isPullDown = button.hasStyleClass("pullDown")
    if not isPullDown:
      let
        style = context.appearance.resolveComboBoxStyle(
          controlStyle(
            srComboBox, states, id = button.styleId, classes = button.styleClasses
          )
        )
        absoluteFrame = context.renderRectFor(button.bounds)
        faceChrome =
          chromeContext(style.chrome, crComboBox, cpFace, style.box.fill, states)
        faceRoot = context.addRenderRectangle(
          absoluteFrame,
          context.appearance.chromeFill(faceChrome),
          style.box.borderColor,
          style.box.borderWidth,
          style.box.cornerRadius,
          style.box.shadows,
          lightMaskContent = true,
        )
      context.drawChromeExtras(
        faceChrome,
        initChromeExtras(faceRoot, absoluteFrame, cornerRadius = style.box.cornerRadius),
      )
      if button.isFocusVisible:
        context.addFocusRing(absoluteFrame, style.box)

      let
        arrowRect = style.comboBoxArrowRect(button.bounds)
        arrowFrame = context.renderRectFor(arrowRect)
        arrowChrome =
          chromeContext(style.chrome, crComboBox, cpArrow, style.box.fill, states)
        separatorRect = initRect(
          arrowRect.origin.x,
          arrowRect.origin.y + 2.0'f32,
          1.0'f32,
          max(arrowRect.size.height - 4.0'f32, 0.0'f32),
        )
        separatorChrome = chromeContext(
          style.chrome, crComboBox, cpSeparator, fill(style.box.borderColor), states
        )
        arrowRoot = context.addRenderRectangle(
          faceRoot,
          arrowFrame,
          context.appearance.chromeFill(arrowChrome),
          color(0.0, 0.0, 0.0, 0.0),
          0.0'f32,
        )
      context.drawChromeExtras(
        arrowChrome, initChromeExtras(arrowRoot, arrowFrame, cornerRadius = 0.0'f32)
      )
      discard context.addRenderRectangle(
        faceRoot,
        context.renderRectFor(separatorRect),
        context.appearance.chromeFill(separatorChrome),
      )
      context.addComboBoxDoubleArrow(arrowRoot, arrowFrame, style.arrowColor)
      context.addText(style.comboBoxTextRect(button.bounds), button.title(), style.text)
      return

    let fillColor =
      if isPullDown and (ssOpen in states or ssActive in states):
        color(0.58, 0.66, 0.82)
      elif isPullDown and ssHovered in states:
        color(0.76, 0.81, 0.91)
      elif ssOpen in states or ssActive in states:
        color(0.78, 0.84, 0.96)
      elif ssHovered in states:
        color(0.88, 0.91, 0.97)
      else:
        color(0.0, 0.0, 0.0, 0.0)
    let borderColor =
      if isPullDown and (ssOpen in states or ssActive in states):
        color(0.30, 0.36, 0.48)
      elif isPullDown and ssHovered in states:
        color(0.45, 0.50, 0.62)
      elif ssOpen in states or ssHovered in states:
        color(0.50, 0.54, 0.62)
      else:
        color(0.0, 0.0, 0.0, 0.0)
    discard context.addRenderRectangle(
      context.renderRectFor(button.bounds),
      fill(fillColor),
      borderColor,
      if ssOpen in states or ssHovered in states: 1.0'f32 else: 0.0'f32,
      4.0'f32,
    )
    context.addText(
      button.bounds.inset(insets(6.0, 10.0, 2.0, 10.0)),
      button.title(),
      context.appearance.resolveTextStyle(
        controlStyle(srComboBox), color(0.08, 0.09, 0.11), insets(0.0)
      ),
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
  button.background = color(0.0, 0.0, 0.0, 0.0)
  button.menu = menu
  button.setAcceptsFirstResponder(true)
  discard button.withProto()
  discard button.withProtocol(PopupMenuButtonDrawing)
  discard button.withProtocol(PopupMenuButtonEvents)
  discard button.withProtocol(PopupMenuButtonAccessibility)
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

proc popUpContextMenu*(
    menu: Menu, view: View, event: MouseEvent
): PopupMenuButton {.discardable.} =
  if menu.isNil or menu.len == 0 or view.isNil:
    return nil
  let ownerResponder = view.window()
  if not (ownerResponder of Window):
    return nil
  let owner = Window(ownerResponder)
  let content = owner.contentView()
  if content.isNil:
    return nil

  let
    windowPoint = view.pointToWindow(event.location)
    contentPoint = owner.convertPointToContent(windowPoint)
    anchorFrame = initRect(contentPoint.x, contentPoint.y, 0.0'f32, 0.0'f32)

  result = newPopupMenuButton(menu.title(), menu, anchorFrame)
  menu.setNextResponder(view)
  result.hidden = true
  result.xRestoreResponder = owner.firstResponder()
  result.xActionStartResponder = Responder(view)
  result.xUsesCustomRestoreResponder = true
  result.xRemoveFromSuperviewOnClose = true
  content.addSubview(result)
  discard owner.makeFirstResponder(result, focusVisible = false)
  result.openPopup()
  if not result.popupOpen():
    result.removeFromSuperview()
    result = nil

proc popUpContextMenu*(
    menu: Menu, view: View, point: Point
): PopupMenuButton {.discardable.} =
  menu.popUpContextMenu(
    view, MouseEvent(location: point, button: mbSecondary, clickCount: 1)
  )

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
  if item.isNil or item.hidden() or item.submenu().isNil or not item.enabled():
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
      if not item.hidden():
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
    if not item.hidden():
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
  var buttonIndex = 0
  for item in menuBar.xMenu.items:
    if not item.hidden():
      if buttonIndex < menuBar.xButtons.len:
        let button = menuBar.xButtons[buttonIndex]
        let width = menuBarItemWidth(item)
        button.title = item.title()
        button.menu = item.submenu()
        button.enabled = not item.submenu().isNil
        button.frame = initRect(x, buttonY, width, buttonHeight)
        x += width + menuBarItemGap()
      inc buttonIndex

protocol MenuBarDrawing of ViewDrawingProtocol:
  method draw(menuBar: MenuBar, context: DrawContext) =
    let bounds = menuBar.bounds()
    if bounds.isEmpty:
      return
    discard context.addRenderRectangle(
      initRect(0.0'f32, bounds.maxY - 1.0'f32, bounds.size.width, 1.0'f32),
      fill(color(0.76, 0.78, 0.82)),
    )

protocol MenuBarLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(menuBar: MenuBar): IntrinsicSize =
    initIntrinsicSize(menuBar.menuBarNaturalSize())

  method layoutSubviews(menuBar: MenuBar) =
    menuBar.tileMenuBarItems()

proc initMenuBarFields*(menuBar: MenuBar, menu: Menu = nil, frame: Rect = AutoRect) =
  initViewFields(menuBar, frame)
  menuBar.background = color(0.91, 0.92, 0.94)
  discard menuBar.withProto()
  discard menuBar.withProtocol(MenuBarDrawing)
  discard menuBar.withProtocol(MenuBarLayout)
  discard menuBar.withProtocol(MenuBarAccessibility)
  menuBar.menu = menu
  menuBar.applyInitialFrame(frame)

proc newMenuBar*(menu: Menu = nil, frame: Rect = AutoRect): MenuBar =
  result = MenuBar()
  initMenuBarFields(result, menu, frame)
