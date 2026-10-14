import ../foundation/private/itemsnapshots
import ../foundation/itemproviders
import ../foundation/private/itemproviderbridges
import std/options

from figdraw import FigIdx

import sigils/core
import sigils/selectors

import ../accessibility/accessibilityprotocols
import ./controls
import ../drawing
import ../foundation/events
import ../responder/keybindings
import ../containers/listbasics
import ../containers/stackviews
import ./popuplists
import ../responder/responders
import ../foundation/selectors as nimkitSelectors
import ../themes
import ../foundation/types
import ../app/windows
import ./nativemenus as nativeMenus

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
    xModel: MenuItemModel
    xSubmenu: Menu

  Menu* = ref object of Responder
    xTitle: string
    xItems: seq[MenuItem]
    xSnapshot: ItemSnapshot[MenuItemModel]
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xOpen: bool
    xPresentedNatively: bool

  PopupMenuButton* = ref object of Control
    xTitle: string
    xMenu: Menu
    xPopupList: PopupListView
    xPopupHost: PopupHost
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

  MenuRootView* = ref object of StackView
    xMenuBar: MenuBar
    xContentView: View

  MenuActionStart* = proc(): Responder {.closure.}

proc openImpl(menu: Menu)
proc closeImpl(menu: Menu)
proc updateImpl(menu: Menu, start: Responder)
proc performKeyEquivalentImpl(menu: Menu, event: KeyEvent, start: Responder): bool
proc openPopupImpl(button: PopupMenuButton)
proc closePopupImpl(button: PopupMenuButton)
proc reloadImpl(menuBar: MenuBar)
proc `title=`*(menu: Menu, title: string)
proc rebuildMenuItemsFromModels(menu: Menu)
proc syncNativeMainMenu()
proc reloadData*(menu: Menu)
proc itemModels*(menu: Menu): seq[MenuItemModel]
proc `itemModels=`*(menu: Menu, models: openArray[MenuItemModel])
proc popupList(button: PopupMenuButton): PopupListView
proc closeChildPopup(button: PopupMenuButton)
proc dismissPopupFromHost(
  button: PopupMenuButton, host: PopupHost, reason: DismissReason
)

proc openSubmenuPopup(button: PopupMenuButton, index: int)
proc selectRelativeMenuBarButton(button: PopupMenuButton, delta: int): bool
proc handlePopupKeyDown(button: PopupMenuButton, event: KeyEvent): bool
proc syncMenuBarPresentation(menuBar: MenuBar)
proc menu*(view: View): Menu
proc `menu=`*(view: View, menu: Menu)
proc popUpContextMenu*(
  menu: Menu, view: View, event: MouseEvent
): PopupMenuButton {.discardable.}

proc installNativeMainMenu*(menu: Menu, actionStart: MenuActionStart = nil)
proc installNativeWindowsMenu*(menu: Menu)
proc installNativeServicesMenu*(menu: Menu)

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
    menu.xTitle

  method accessibilityValue(menu: Menu): string =
    $menu.xItems.len()

  method isAccessibilityElement(menu: Menu): bool =
    true

protocol MenuItemAccessibility of AccessibilityProtocol:
  method accessibilityRole(item: MenuItem): AccessibilityRole =
    arMenuItem

  method accessibilityLabel(item: MenuItem): string =
    item.xModel.title

  method accessibilityValue(item: MenuItem): string =
    case item.xModel.state
    of bsOff: ""
    of bsOn: "on"
    of bsMixed: "mixed"

  method accessibilityTraits(item: MenuItem): AccessibilityTraits =
    if not item.xModel.enabled:
      result.incl atDisabled
    if not item.xSubmenu.isNil:
      result.incl atButton
    if item.xModel.state in {bsOn, bsMixed}:
      result.incl atSelected

  method isAccessibilityElement(item: MenuItem): bool =
    not item.xModel.separator

  method accessibilityActionNames(item: MenuItem): seq[string] =
    if item.xModel.enabled and not item.xModel.separator:
      @[AccessibilityActionPress]
    else:
      @[]

protocol PopupMenuButtonAccessibility of AccessibilityProtocol:
  method accessibilityRole(button: PopupMenuButton): AccessibilityRole =
    arPopupButton

  method accessibilityLabel(button: PopupMenuButton): string =
    if button.xAccessibilityLabel.len > 0: button.xAccessibilityLabel else: button.xTitle

  method accessibilityValue(button: PopupMenuButton): string =
    button.xTitle

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

protocol MenuBarPresentationLifecycle of ViewLifecycleProtocol:
  proc menuBarDidMoveToWindow(menuBar: MenuBar) {.slotFor: viewDidMoveToWindow.} =
    menuBar.syncMenuBarPresentation()

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
  result = MenuItem(xModel: initMenuItemModel(title = title, action = action))
  result.xModel.objectValue = toObj(title)
  initResponder(result)
  if keyEquivalent.len > 0:
    result.xModel.keyEquivalent = initKeyStroke(keyEquivalent, modifiers)
    result.xModel.hasKeyEquivalent = true
  discard result.withProtocol(MenuItemAccessibility)

proc separatorMenuItem*(): MenuItem =
  result = newMenuItem()
  result.xModel.separator = true
  result.xModel.enabled = false

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
  result.xModel.objectValue = value

proc applyMenuItemModel(item: MenuItem, model: MenuItemModel) =
  item.xModel = model
  # The live submenu owns children; serialization reads that tree.
  item.xModel.children = @[]
  item.xModel.title =
    if model.separator:
      ""
    else:
      model.menuItemModelTitle()
  if model.separator:
    item.xModel.action = ActionSelector()
  if not model.hasKeyEquivalent:
    item.xModel.keyEquivalent = KeyStroke()
  item.xModel.enabled = model.enabled and not model.separator
  if model.objectValue.isNilOrEmpty() and item.xModel.title.len > 0:
    item.xModel.objectValue = toObj(item.xModel.title)
  if model.children.len > 0:
    if item.xSubmenu.isNil:
      item.xSubmenu = newMenu(item.xModel.title)
      item.xSubmenu.setNextResponder(item)
    item.xSubmenu.title = item.xModel.title
    item.xSubmenu.itemModels = model.children
  else:
    if not item.xSubmenu.isNil and item.xSubmenu.nextResponder() == Responder(item):
      item.xSubmenu.clearNextResponder()
    item.xSubmenu = nil

proc newMenuItem*(model: MenuItemModel): MenuItem =
  result = newMenuItem()
  result.applyMenuItemModel(model)

proc identifier*(item: MenuItem): string =
  item.xModel.identifier

proc `identifier=`*(item: MenuItem, identifier: string) =
  item.xModel.identifier = identifier

proc title*(item: MenuItem): string =
  item.xModel.title

proc `title=`*(item: MenuItem, title: string) =
  item.xModel.title = title
  item.xModel.objectValue = toObj(title)
  syncNativeMainMenu()

proc subtitle*(item: MenuItem): string =
  item.xModel.subtitle

proc `subtitle=`*(item: MenuItem, subtitle: string) =
  item.xModel.subtitle = subtitle

proc objectValue*(item: MenuItem): ObjectValue =
  item.xModel.objectValue

proc `objectValue=`*(item: MenuItem, value: ObjectValue) =
  item.xModel.objectValue = value
  item.xModel.title = value.formatObjectValue(initObjectFormatContext(role = ovrMenu))
  syncNativeMainMenu()

proc action*(item: MenuItem): ActionSelector =
  item.xModel.action

proc `action=`*(item: MenuItem, action: ActionSelector) =
  item.xModel.action = action
  syncNativeMainMenu()

proc target*(item: MenuItem): DynamicAgent =
  item.xModel.target

proc `target=`*(item: MenuItem, target: DynamicAgent) =
  item.xModel.target = target

proc `target=`*(item: MenuItem, target: Responder) =
  item.target = DynamicAgent(target)

proc state*(item: MenuItem): ButtonState =
  item.xModel.state

proc `state=`*(item: MenuItem, state: ButtonState) =
  item.xModel.state = state
  syncNativeMainMenu()

proc enabled*(item: MenuItem): bool =
  item.xModel.enabled

proc `enabled=`*(item: MenuItem, enabled: bool) =
  item.xModel.enabled = enabled
  syncNativeMainMenu()

proc hidden*(item: MenuItem): bool =
  item.xModel.hidden

proc `hidden=`*(item: MenuItem, hidden: bool) =
  item.xModel.hidden = hidden
  syncNativeMainMenu()

proc validates*(item: MenuItem): bool =
  item.xModel.validates

proc `validates=`*(item: MenuItem, validates: bool) =
  item.xModel.validates = validates

proc keyEquivalent*(item: MenuItem): KeyStroke =
  item.xModel.keyEquivalent

proc hasKeyEquivalent*(item: MenuItem): bool =
  item.xModel.hasKeyEquivalent

proc setKeyEquivalent*(item: MenuItem, text: string, modifiers: set[KeyModifier] = {}) =
  if text.len == 0:
    item.xModel.keyEquivalent = KeyStroke()
    item.xModel.hasKeyEquivalent = false
  else:
    item.xModel.keyEquivalent = initKeyStroke(text, modifiers)
    item.xModel.hasKeyEquivalent = true
  syncNativeMainMenu()

proc setKeyEquivalent*(item: MenuItem, key: Key, modifiers: set[KeyModifier] = {}) =
  item.xModel.keyEquivalent = initKeyStroke(key, modifiers)
  item.xModel.hasKeyEquivalent = true
  syncNativeMainMenu()

proc modifierMask*(item: MenuItem): set[KeyModifier] =
  item.xModel.keyEquivalent.modifiers

proc `modifierMask=`*(item: MenuItem, modifiers: set[KeyModifier]) =
  item.xModel.keyEquivalent.modifiers = modifiers
  item.xModel.hasKeyEquivalent = true
  syncNativeMainMenu()

proc submenu*(item: MenuItem): Menu =
  item.xSubmenu

proc `submenu=`*(item: MenuItem, submenu: Menu) =
  item.xSubmenu = submenu
  if not submenu.isNil:
    submenu.setNextResponder(item)
  syncNativeMainMenu()

proc isSeparatorItem*(item: MenuItem): bool =
  item.xModel.separator

proc image*(item: MenuItem): ImageResource =
  item.xModel.image

proc `image=`*(item: MenuItem, image: ImageResource) =
  item.xModel.image = image

proc tag*(item: MenuItem): int =
  item.xModel.tag

proc `tag=`*(item: MenuItem, tag: int) =
  item.xModel.tag = tag
  syncNativeMainMenu()

proc representedObject*(item: MenuItem): DynamicAgent =
  item.xModel.representedObject

proc `representedObject=`*(item: MenuItem, value: DynamicAgent) =
  item.xModel.representedObject = value

proc userInfo*(item: MenuItem): DynamicAgent =
  item.xModel.userInfo

proc `userInfo=`*(item: MenuItem, value: DynamicAgent) =
  item.xModel.userInfo = value

proc menuItemModel*(item: MenuItem): MenuItemModel =
  if item.isNil:
    return initMenuItemModel()
  result = item.xModel
  result.children = @[]
  if result.objectValue.isNilOrEmpty() and result.title.len > 0:
    result.objectValue = toObj(result.title)
  if not item.xSubmenu.isNil:
    result.children = item.xSubmenu.itemModels()

proc menu*(view: View): Menu =
  if view.xContextMenu.isNil or not (view.xContextMenu of Menu):
    return nil
  Menu(view.xContextMenu)

proc `menu=`*(view: View, menu: Menu) =
  if view.xContextMenu == Responder(menu):
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
  menu.xTitle

proc `title=`*(menu: Menu, title: string) =
  menu.xTitle = title
  syncNativeMainMenu()

proc presentedNatively*(menu: Menu): bool =
  not menu.isNil and menu.xPresentedNatively

proc `presentedNatively=`*(menu: Menu, presentedNatively: bool) =
  if not menu.isNil:
    menu.xPresentedNatively = presentedNatively

proc delegate*(menu: Menu): DynamicAgent =
  menu.xDelegate

proc `delegate=`*(menu: Menu, delegate: DynamicAgent) =
  menu.xDelegate = delegate

proc `delegate=`*(menu: Menu, delegate: Responder) =
  menu.delegate = DynamicAgent(delegate)

proc providedMenuItem(
    source: DynamicAgent, menu: Menu, item: ModelItem
): MenuItemModel =
  initMenuItemModel(
    identifier = item.identifier,
    title = item.displayTitle(ovrMenu),
    objectValue = item.objectValue,
    enabled = item.enabled,
    hidden = item.hidden,
    separator = item.separator,
    representedObject = item.representedObject,
    validates = false,
  )

proc providedMenuIndex(source: DynamicAgent, menu: Menu, identifier: string): int =
  source.providedIndex(DynamicAgent(menu), identifier)

defineItemProviderBridge(
  MenuItemProviderSource, MenuDataSource, Menu, MenuItemModel, menuItemCount,
  menuItemModelAtIndex, indexOfMenuItemModelIdentifier, menu, providedMenuItem,
  providedMenuIndex,
)

proc installMenuItemProvider*(source: DynamicAgent) =
  source.installItemProvider(MenuItemProviderSource.init())

proc dataSource*(menu: Menu): DynamicAgent =
  menu.xDataSource

proc `dataSource=`*(menu: Menu, dataSource: DynamicAgent) =
  if menu.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    dataSource.installMenuItemProvider()
    discard dataSource.adopt(MenuDataSource)
  menu.xDataSource = dataSource
  menu.reloadData()

proc `dataSource=`*(menu: Menu, dataSource: Responder) =
  menu.dataSource = DynamicAgent(dataSource)

proc items*(menu: Menu): lent seq[MenuItem] =
  menu.xItems

proc itemModels*(menu: Menu): seq[MenuItemModel] =
  if menu.xSnapshot.active:
    return menu.xSnapshot.models
  for item in menu.xItems:
    result.add item.menuItemModel()

proc clearMenuItems(menu: Menu) =
  for item in menu.xItems:
    if not item.isNil and item.nextResponder() == Responder(menu):
      item.clearNextResponder()
  menu.xItems.setLen(0)

proc rebuildMenuItemsFromModels(menu: Menu) =
  let apply = proc(item: MenuItem, model: MenuItemModel) =
    item.applyMenuItemModel(model)
    item.setNextResponder(menu)
  let retire = proc(item: MenuItem) =
    if not item.isNil and item.nextResponder() == Responder(menu):
      item.clearNextResponder()
  menu.xItems = menu.xSnapshot.reconcilePresentations(
    menu.xItems,
    proc(item: MenuItem): string =
      item.identifier(),
    proc(model: MenuItemModel): MenuItem =
      newMenuItem(),
    apply,
    retire,
  )

proc `itemModels=`*(menu: Menu, models: openArray[MenuItemModel]) =
  menu.xSnapshot.replace(models)
  menu.rebuildMenuItemsFromModels()
  syncNativeMainMenu()

proc reloadData*(menu: Menu) =
  if menu.xDataSource.isNil:
    if menu.xSnapshot.active:
      menu.rebuildMenuItemsFromModels()
      syncNativeMainMenu()
    return

  let models = readSnapshot(
    menu.xDataSource.trySendLocal(menuItemCount(), menu),
    proc(index: int): Option[MenuItemModel] =
      menu.xDataSource.trySendLocal(menuItemModelAtIndex(), (menu: menu, index: index)),
  )
  if models.isSome:
    menu.itemModels = models.get()

proc len*(menu: Menu): int =
  menu.xItems.len

proc `[]`*(menu: Menu, index: Natural): MenuItem =
  menu.xItems[index]

proc menuItemAtIndex*(menu: Menu, index: int): MenuItem =
  if index < 0 or index >= menu.len():
    nil
  else:
    menu.xItems[index]

proc indexOfMenuItemIdentifier*(menu: Menu, identifier: string): int =
  if identifier.len == 0:
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
  menu.xSnapshot.visibleSourceIndex(visibleIndex)

proc indexOfModelIdentifier(menu: Menu, identifier: string): int =
  menu.xSnapshot.sourceIndex(identifier)

proc addItem*(menu: Menu, item: MenuItem): MenuItem {.discardable.} =
  if item.isNil:
    return nil
  if menu.xSnapshot.active:
    menu.xSnapshot.models.add item.menuItemModel()
  menu.xItems.add item
  item.setNextResponder(menu)
  syncNativeMainMenu()
  item

proc addItem*(menu: Menu, model: MenuItemModel): MenuItem {.discardable.} =
  menu.xSnapshot.active = true
  menu.xSnapshot.models.add model
  if model.hidden:
    syncNativeMainMenu()
    return nil
  let item = newMenuItem(model)
  menu.xItems.add item
  item.setNextResponder(menu)
  syncNativeMainMenu()
  item

proc insertItem*(
    menu: Menu, model: MenuItemModel, index: int
): MenuItem {.discardable.} =
  menu.xSnapshot.active = true
  let modelIndex =
    if menu.xSnapshot.models.len == 0:
      0
    else:
      max(0, min(index, menu.xSnapshot.models.len))
  menu.xSnapshot.models.insert(model, modelIndex)
  menu.rebuildMenuItemsFromModels()
  syncNativeMainMenu()
  if model.identifier.len > 0:
    return menu.menuItemWithIdentifier(model.identifier)
  if model.hidden:
    return nil
  menu.menuItemAtIndex(menu.xSnapshot.visibleIndex(modelIndex))

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
  if item.isNil:
    return false
  let idx = menu.xItems.find(item)
  if idx < 0:
    return false
  if menu.xSnapshot.active:
    let modelIndex =
      if item.identifier().len > 0:
        menu.indexOfModelIdentifier(item.identifier())
      else:
        menu.visibleModelIndex(idx)
    if modelIndex >= 0:
      menu.xSnapshot.models.delete(modelIndex)
  if item.nextResponder() == Responder(menu):
    item.clearNextResponder()
  menu.xItems.delete(idx)
  syncNativeMainMenu()
  true

proc removeItemWithIdentifier*(menu: Menu, identifier: string): bool {.discardable.} =
  if identifier.len == 0:
    return false
  let item = menu.menuItemWithIdentifier(identifier)
  if not item.isNil:
    return menu.removeItem(item)
  if menu.xSnapshot.active:
    let modelIndex = menu.indexOfModelIdentifier(identifier)
    if modelIndex >= 0:
      menu.xSnapshot.models.delete(modelIndex)
      menu.rebuildMenuItemsFromModels()
      syncNativeMainMenu()
      return true
  false

proc removeAllItems*(menu: Menu) =
  menu.xSnapshot.models.setLen(0)
  menu.xSnapshot.active = false
  menu.clearMenuItems()
  syncNativeMainMenu()

proc menuNeedsUpdate*(menu: Menu) =
  if not menu.xDelegate.isNil:
    discard menu.xDelegate.sendLocalIfHandled(menuNeedsUpdate(), DynamicAgent(menu))

proc openImpl(menu: Menu) =
  menu.menuNeedsUpdate()
  if not menu.xDataSource.isNil:
    menu.reloadData()
  menu.xOpen = true
  if not menu.xDelegate.isNil:
    discard menu.xDelegate.sendLocalIfHandled(menuWillOpen(), DynamicAgent(menu))

proc closeImpl(menu: Menu) =
  menu.xOpen = false
  if not menu.xDelegate.isNil:
    discard menu.xDelegate.sendLocalIfHandled(menuDidClose(), DynamicAgent(menu))

proc isOpen*(menu: Menu): bool =
  menu.xOpen

proc validate*(item: MenuItem, target: DynamicAgent): bool =
  if item.xModel.separator or item.xModel.hidden:
    return false
  if not item.xModel.validates:
    return item.xModel.enabled
  if not item.xSubmenu.isNil:
    return true
  if item.xModel.action.name.len == 0:
    return item.xModel.enabled
  if target.isNil:
    return false
  let validated = target.trySendLocal(
    validateUserInterfaceItem(), ValidationArgs(item: item, action: item.xModel.action)
  )
  if validated.isSome:
    return validated.get()
  target.respondsTo(item.xModel.action.name)

proc findActionTarget*(start: Responder, selector: ActionSelector): DynamicAgent =
  var current = start
  while not current.isNil:
    if current.respondsTo(selector.name):
      return DynamicAgent(current)
    current = current.nextResponder()

proc validate*(item: MenuItem, start: Responder): bool =
  let target =
    if not item.xModel.target.isNil:
      item.xModel.target
    else:
      findActionTarget(start, item.xModel.action)
  item.validate(target)

proc syncMenuItemModelFromItem(menu: Menu, item: MenuItem, visibleIndex: int) =
  if item.isNil or not menu.xSnapshot.active:
    return
  let modelIndex =
    if item.identifier().len > 0:
      menu.indexOfModelIdentifier(item.identifier())
    else:
      menu.visibleModelIndex(visibleIndex)
  if modelIndex >= 0:
    menu.xSnapshot.models[modelIndex] = item.menuItemModel()

proc updateImpl(menu: Menu, start: Responder) =
  menu.menuNeedsUpdate()
  if not menu.xDataSource.isNil:
    menu.reloadData()
  for index, item in menu.xItems:
    if not item.isNil:
      if item.xSubmenu.isNil:
        item.xModel.enabled = item.validate(start)
      else:
        item.xSubmenu.update(start)
      menu.syncMenuItemModelFromItem(item, index)
  syncNativeMainMenu()

proc notifyMenuItemDidActivate(menu: Menu, item: MenuItem, sender: DynamicAgent) =
  if item.isNil:
    return
  emit menu.menuItemDidActivate(
    if sender.isNil:
      DynamicAgent(item)
    else:
      sender,
    item.identifier(),
  )

proc perform*(item: MenuItem, start: Responder, sender: DynamicAgent = nil): bool =
  if item.xModel.separator or item.xModel.hidden or not item.xModel.enabled:
    return false
  if not item.xModel.target.isNil:
    if not item.validate(item.xModel.target):
      return false
    return item.xModel.target.sendLocalIfHandled(
      item.xModel.action,
      ActionArgs(
        sender:
          if sender.isNil:
            DynamicAgent(item)
          else:
            sender
      ),
    )
  let target = findActionTarget(start, item.xModel.action)
  if not item.validate(target):
    return false
  target.sendLocalIfHandled(
    item.xModel.action,
    ActionArgs(
      sender:
        if sender.isNil:
          DynamicAgent(item)
        else:
          sender
    ),
  )

proc findKeyEquivalentItem*(menu: Menu, event: KeyEvent): MenuItem =
  for item in menu.xItems:
    if item.isNil or item.xModel.separator or item.xModel.hidden:
      discard
    elif item.xModel.hasKeyEquivalent and item.xModel.keyEquivalent.matches(event):
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

when defined(macosx):
  var
    nativeMainMenu: Menu
    nativeWindowsMenu: Menu
    nativeServicesMenu: Menu
    nativeActionStart: MenuActionStart
    nativeMainMenuInstalled: bool
    nativeSyncSuspended: bool

  proc currentNativeActionStart(): Responder =
    if nativeActionStart.isNil:
      return Responder(nativeMainMenu)
    nativeActionStart()

  proc nativeMenuIdentity(menu: Menu): pointer =
    cast[pointer](menu)

  proc nativeMenuTitle(menu: Menu): string =
    menu.xTitle

  proc nativeMenuItems(menu: Menu): seq[MenuItem] =
    menu.xItems

  proc describeNativeMenuItem(item: MenuItem): nativeMenus.NativeMenuItemDescription =
    result = nativeMenus.NativeMenuItemDescription(
      title: item.xModel.title,
      separator: item.xModel.separator,
      enabled: item.xModel.enabled,
      hidden: item.xModel.hidden,
      state: nativeMenus.toNativeState(item.xModel.state),
      tag: item.xModel.tag,
      modifiers: nativeMenus.toNativeModifiers(item.xModel.keyEquivalent.modifiers),
    )
    if item.xModel.hasKeyEquivalent:
      result.keyEquivalent =
        nativeMenus.toNativeKeyEquivalent(item.xModel.keyEquivalent)

  proc nativeSubmenu(item: MenuItem): Menu =
    item.xSubmenu

  proc canActivateNativeMenuItem(item: MenuItem): bool =
    item.xModel.action.name.len > 0

  proc refreshNativeMenu(menu: Menu) =
    nativeSyncSuspended = true
    try:
      menu.open()
      menu.update(currentNativeActionStart())
    finally:
      nativeSyncSuspended = false

  proc closeNativeMenu(menu: Menu) =
    nativeSyncSuspended = true
    try:
      menu.close()
    finally:
      nativeSyncSuspended = false

  proc activateNativeMenuItem(menu: Menu, item: MenuItem) =
    nativeSyncSuspended = true
    try:
      if item.perform(currentNativeActionStart(), DynamicAgent(item)):
        menu.notifyMenuItemDidActivate(item, DynamicAgent(item))
    finally:
      nativeSyncSuspended = false
    syncNativeMainMenu()

  proc nativeMenuAdapter(): nativeMenus.NativeMenuAdapter[Menu, MenuItem] =
    nativeMenus.NativeMenuAdapter[Menu, MenuItem](
      identity: nativeMenuIdentity,
      title: nativeMenuTitle,
      items: nativeMenuItems,
      describeItem: describeNativeMenuItem,
      submenu: nativeSubmenu,
      canActivate: canActivateNativeMenuItem,
      refresh: refreshNativeMenu,
      close: closeNativeMenu,
      activate: activateNativeMenuItem,
    )

  proc syncNativeMainMenu() =
    if nativeSyncSuspended or not nativeMainMenuInstalled:
      return
    let description =
      nativeMenus.toNativeMenuDescription(nativeMainMenu, nativeMenuAdapter())

    nativeSyncSuspended = true
    try:
      nativeMenus.installNativeMenus(
        description, cast[pointer](nativeWindowsMenu), cast[pointer](nativeServicesMenu)
      )
    finally:
      nativeSyncSuspended = false

  proc installNativeMainMenu*(menu: Menu, actionStart: MenuActionStart = nil) =
    nativeMainMenuInstalled = true
    nativeMainMenu = menu
    nativeWindowsMenu = nil
    nativeServicesMenu = nil
    nativeActionStart = actionStart
    syncNativeMainMenu()

  proc installNativeWindowsMenu*(menu: Menu) =
    nativeWindowsMenu = menu
    syncNativeMainMenu()

  proc installNativeServicesMenu*(menu: Menu) =
    nativeServicesMenu = menu
    syncNativeMainMenu()

else:
  proc syncNativeMainMenu() =
    discard

  proc installNativeMainMenu*(menu: Menu, actionStart: MenuActionStart = nil) =
    discard menu
    discard actionStart.isNil

  proc installNativeWindowsMenu*(menu: Menu) =
    discard menu

  proc installNativeServicesMenu*(menu: Menu) =
    discard menu

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

proc title*(button: PopupMenuButton): string =
  button.xTitle

proc `title=`*(button: PopupMenuButton, title: string) =
  if button.xTitle == title:
    return
  button.xTitle = title
  button.invalidateIntrinsicContentSize()
  button.needsDisplay = true

proc menu*(button: PopupMenuButton): Menu =
  button.xMenu

proc `menu=`*(button: PopupMenuButton, menu: Menu) =
  if button.xMenu == menu:
    return
  button.xMenu = menu
  if not menu.isNil:
    menu.setNextResponder(button)
  button.xViewport.reset()
  button.xHighlightedIndex = -1
  button.needsDisplay = true

proc popupOpen*(button: PopupMenuButton): bool =
  button.xPopupOpen

proc highlightedIndex*(button: PopupMenuButton): int =
  button.xHighlightedIndex

proc activeSubmenuButton*(button: PopupMenuButton): PopupMenuButton =
  button.xChildPopup

proc dispatchPopupKeyDown*(button: PopupMenuButton, event: KeyEvent): bool =
  button.handlePopupKeyDown(event)

proc maxVisibleItems*(button: PopupMenuButton): int =
  button.xMaxVisibleItems

proc `maxVisibleItems=`*(button: PopupMenuButton, value: int) =
  button.xMaxVisibleItems = max(value, 1)
  button.needsDisplay = true

proc itemHeight*(button: PopupMenuButton): float32 =
  button.xItemHeight

proc `itemHeight=`*(button: PopupMenuButton, value: float32) =
  button.xItemHeight = value.normalizedRowHeight()
  button.needsDisplay = true

proc popupPresentation*(button: PopupMenuButton): PopupPresentation =
  button.xPopupPresentation

proc `popupPresentation=`*(button: PopupMenuButton, value: PopupPresentation) =
  if button.xPopupPresentation == value:
    return
  button.xPopupPresentation = value
  if button.popupOpen():
    button.closePopup()

proc menuItemCount(button: PopupMenuButton): int =
  if button.xMenu.isNil:
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

proc rootPopup(button: PopupMenuButton): PopupMenuButton =
  result = button
  while not result.isNil and not result.xParentPopup.isNil:
    result = result.xParentPopup

proc cascadeSuperview(button: PopupMenuButton): View =
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
  if button.xMenu.isNil or index < 0 or index >= button.xMenu.len:
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
  for index in 0 ..< button.menuItemCount():
    if button.menuItemIsSelectable(index):
      return index
  -1

proc lastSelectableItemIndex(button: PopupMenuButton): int =
  let count = button.menuItemCount()
  if count <= 0:
    return -1
  for index in countdown(count - 1, 0):
    if button.menuItemIsSelectable(index):
      return index
  -1

proc nextSelectableItemIndex(button: PopupMenuButton, startIndex, delta: int): int =
  if delta == 0:
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
  button.needsDisplay = true
  if not button.xPopupList.isNil:
    button.xPopupList.needsDisplay = true

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
  if delta == 0:
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

proc owningMenuBar(button: PopupMenuButton): MenuBar

proc dismissPopupAndAdvanceKeyView(button: PopupMenuButton, delta: int) =
  ## Close the whole popup tree, then advance key focus relative to the root
  ## button so Tab cycles through the menu bar and, past its end, through the
  ## remaining key views of the window. A menu bar button that gains focus
  ## opens its popup, mirroring arrow navigation between menus.
  let
    root = button.rootPopup()
    owner = root.ownerWindow()
  button.closePopupRoot()
  if owner.isNil:
    return
  # Context-menu anchors are removed on dismissal. Continue from the restored
  # responder instead of looking up a key view relative to the detached anchor.
  var start = View(root)
  if root.ownerWindow() != owner:
    let restored = owner.firstResponder()
    start =
      if restored of View:
        View(restored)
      else:
        nil
  if delta < 0:
    owner.selectKeyViewPrecedingView(start)
  else:
    owner.selectKeyViewFollowingView(start)
  let next = owner.firstResponder()
  if next.isNil or not (next of PopupMenuButton):
    return
  let nextButton = PopupMenuButton(next)
  if nextButton.owningMenuBar().isNil or nextButton.popupOpen():
    return
  nextButton.openPopup()

proc handlePopupKeyDown(button: PopupMenuButton, event: KeyEvent): bool =
  if not button.xChildPopup.isNil and button.xChildPopup.popupOpen():
    return button.xChildPopup.handlePopupKeyDown(event)
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
      discard button.selectRelativeMenuBarButton(1)
  of keyArrowLeft:
    if not button.xParentPopup.isNil:
      let parent = button.xParentPopup
      button.closePopup()
      parent.setPopupNeedsDisplay()
    else:
      discard button.selectRelativeMenuBarButton(-1)
  of keyEnter:
    button.activateItem(button.xHighlightedIndex)
  of keyTab:
    if kmShift in event.modifiers:
      button.dismissPopupAndAdvanceKeyView(-1)
    else:
      button.dismissPopupAndAdvanceKeyView(1)
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
    tab: proc(delta: int) =
      button.dismissPopupAndAdvanceKeyView(delta),
  )

proc popupList(button: PopupMenuButton): PopupListView =
  if button.xPopupList.isNil:
    button.xPopupList =
      newPopupListView(button.popupListData(), button.popupListActions())
  button.xPopupList

proc resolvedPopupPresentation(button: PopupMenuButton): PopupPresentation =
  if not button.xParentPopup.isNil:
    return ppInline
  let owner = button.ownerWindow()
  owner.resolvedPopupPresentation(button.xPopupPresentation)

proc shouldUseWindowPopup(button: PopupMenuButton): bool =
  button.resolvedPopupPresentation() == ppWindow

proc popupPlaceAbove(button: PopupMenuButton): bool =
  let owner = button.ownerWindow()
  if owner.isNil or owner.contentView().isNil:
    return false
  let
    anchorFrame = button.rectToWindow(button.bounds())
    size = button.popupSize()
    contentBounds = owner.contentView().bounds()
  anchorFrame.maxY + size.height > contentBounds.maxY and
    anchorFrame.minY - size.height >= contentBounds.minY

proc closePopupWindow(button: PopupMenuButton) =
  let host = button.xPopupHost
  button.xPopupHost = nil
  if not host.isNil:
    discard host.dismissPopup()

proc closeChildPopup(button: PopupMenuButton) =
  let child = button.xChildPopup
  button.xChildPopup = nil
  button.xChildPopupOwnerIndex = -1
  if not child.isNil and child.popupOpen():
    child.closePopup()

proc dismissPopupFromHost(
    button: PopupMenuButton, host: PopupHost, reason: DismissReason
) =
  discard reason
  if button.xPopupHost != host:
    return
  button.xPopupHost = nil
  if button.popupOpen():
    button.closePopupImpl()

proc openPopupHost(button: PopupMenuButton): bool =
  let owner = button.ownerWindow()
  if owner.isNil:
    return false
  let host = newPopupHost(
    owner,
    button,
    button.popupList(),
    button.popupSize(),
    title = button.title & " Menu",
    presentation = button.xPopupPresentation,
    restoreResponder =
      if button.xUsesCustomRestoreResponder:
        button.xRestoreResponder
      else:
        Responder(button),
    inlineParent = button.cascadeSuperview(),
    inlineFrame = if button.xUsesCascadeFrame: button.xCascadeFrame else: AutoRect,
    placeAbove = button.popupPlaceAbove(),
    onDismiss = proc(host: PopupHost, reason: DismissReason) =
      button.dismissPopupFromHost(host, reason),
    restoreCurrentResponderIfNil = not button.xUsesCustomRestoreResponder,
    managesTransientSession = button.xParentPopup.isNil,
    focusContent = button.shouldUseWindowPopup(),
    onKeyDown = proc(event: KeyEvent): bool =
      button.handlePopupKeyDown(event),
  )
  button.xPopupHost = host
  if host.presentPopup():
    return true
  button.xPopupHost = nil
  false

proc owningMenuBar(button: PopupMenuButton): MenuBar =
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
  if button.xMenu.isNil:
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
  button.setWidgetState(ssOpen, true)
  if not button.openPopupHost():
    button.xPopupOpen = false
    button.xHighlightedIndex = -1
    button.setWidgetState(ssOpen, false)
    button.xMenu.close()
    return
  button.noteMenuBarPopupOpened()
  button.needsDisplay = true

proc closePopupImpl(button: PopupMenuButton) =
  if not button.popupOpen():
    return
  button.closeChildPopup()
  button.xPopupOpen = false
  button.xHighlightedIndex = -1
  button.closePopupWindow()
  if not button.xMenu.isNil:
    button.xMenu.close()
  if not button.xParentPopup.isNil and button.xParentPopup.xChildPopup == button:
    button.xParentPopup.xChildPopup = nil
    button.xParentPopup.xChildPopupOwnerIndex = -1
  button.noteMenuBarPopupClosed()
  button.setWidgetState(ssOpen, false)
  button.needsDisplay = true
  if button.xRemoveFromSuperviewOnClose and not button.superview().isNil:
    button.removeFromSuperview()

proc drawPopupButtonArrow(
    context: DrawContext, parent: FigIdx, arrowRect: Rect, arrowColor: Color
) =
  if arrowRect.size.width <= 0.0'f32 or arrowRect.size.height <= 0.0'f32:
    return
  let
    width = max(min(arrowRect.size.width * 0.28'f32, 6.0'f32), 4.0'f32)
    centerX = arrowRect.origin.x + arrowRect.size.width * 0.5'f32
    centerY = arrowRect.origin.y + arrowRect.size.height * 0.5'f32
    upY = centerY - 5.0'f32
    downY = centerY + 2.0'f32
  discard context.addRenderRectangle(
    parent, rect(centerX - width * 0.20'f32, upY, width * 0.40'f32, 1.0'f32), arrowColor
  )
  discard context.addRenderRectangle(
    parent,
    rect(centerX - width * 0.35'f32, upY + 1.0'f32, width * 0.70'f32, 1.0'f32),
    arrowColor,
  )
  discard context.addRenderRectangle(
    parent, rect(centerX - width * 0.50'f32, upY + 2.0'f32, width, 1.0'f32), arrowColor
  )
  discard context.addRenderRectangle(
    parent, rect(centerX - width * 0.50'f32, downY, width, 1.0'f32), arrowColor
  )
  discard context.addRenderRectangle(
    parent,
    rect(centerX - width * 0.35'f32, downY + 1.0'f32, width * 0.70'f32, 1.0'f32),
    arrowColor,
  )
  discard context.addRenderRectangle(
    parent,
    rect(centerX - width * 0.20'f32, downY + 2.0'f32, width * 0.40'f32, 1.0'f32),
    arrowColor,
  )

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
      context.drawChromeBacking(
        faceChrome,
        initChromeExtras(
          context.renderParent(),
          absoluteFrame,
          cornerRadius = style.box.cornerRadius,
          cornerRadii = style.box.cornerRadii,
        ),
      )
      let faceRoot = context.addRenderRectangle(
        absoluteFrame,
        context.appearance.chromeFill(faceChrome),
        style.box.borderColor,
        style.box.borderWidth,
        style.box.cornerRadius,
        style.box.shadows,
        lightMaskContent = true,
        cornerRadii = style.box.cornerRadii,
      )
      context.drawChromeExtras(
        faceChrome,
        initChromeExtras(
          faceRoot,
          absoluteFrame,
          cornerRadius = style.box.cornerRadius,
          cornerRadii = style.box.cornerRadii,
        ),
      )
      if button.isFocusVisible:
        context.addFocusRing(absoluteFrame, style.box)

      let
        arrowRect = style.comboBoxArrowRect(button.bounds)
        arrowFrame = context.renderRectFor(arrowRect)
        arrowChrome =
          chromeContext(style.chrome, crComboBox, cpArrow, style.arrowFill, states)
        separatorRect = rect(
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
      context.drawPopupButtonArrow(arrowRoot, arrowFrame, style.arrowColor)
      let textRect = style.comboBoxTextRect(button.bounds)
      context.addText(
        textRect,
        button.title().clippedText(textRect.size.width, style.text),
        style.text,
      )
      return

    let style = context.appearance.resolveButtonStyle(
      controlStyle(
        srMenuBarItem, states, id = button.styleId, classes = button.styleClasses
      )
    )
    let absoluteFrame = context.renderRectFor(button.bounds)
    discard context.addRenderRectangle(
      absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
      style.box.cornerRadius, style.box.shadows,
    )
    if button.isFocusVisible and not button.popupOpen():
      context.addFocusRing(absoluteFrame, style.box)
    context.addText(button.bounds.inset(style.text.insets), button.title(), style.text)

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
    if button.popupOpen():
      return button.handlePopupKeyDown(event)
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
      button.selectRelativeMenuBarButton(-1)
    of keyArrowRight:
      button.selectRelativeMenuBarButton(1)
    of keyTab:
      if kmShift in event.modifiers:
        button.dismissPopupAndAdvanceKeyView(-1)
      else:
        button.dismissPopupAndAdvanceKeyView(1)
      true
    else:
      false

protocol PopupMenuButtonStyleLayout of ViewLayoutProtocol:
  method layoutStyleContext(button: PopupMenuButton): StyleContext =
    controlStyle(
      if button.hasStyleClass("pullDown"): srMenuBarItem else: srComboBox,
      button.widgetStateSet(),
      id = button.styleId,
      classes = button.styleClasses,
    )

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
  button.acceptsFirstResponder = true
  discard button.withProto()
  discard button.withProtocol(PopupMenuButtonDrawing)
  discard button.withProtocol(PopupMenuButtonStyleLayout)
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
  if menu.len == 0 or view.isNil:
    return nil
  let ownerResponder = view.window()
  if not (ownerResponder of Window):
    return nil
  let owner = Window(ownerResponder)
  let content = owner.contentView()
  if content.isNil:
    return nil
  # A secondary click on an inactive window can reach the view before its native
  # focus notification. Make the context-menu owner current before presenting it.
  owner.makeKeyAndOrderFront()

  let
    windowPoint = view.pointToWindow(event.location)
    contentPoint = owner.convertPointToContent(windowPoint)
    anchorFrame = rect(contentPoint.x, contentPoint.y, 0.0'f32, 0.0'f32)

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
  rect(
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

proc selectRelativeMenuBarButton(button: PopupMenuButton, delta: int): bool =
  ## Focus the next (delta > 0) or previous (delta < 0) enabled menu bar
  ## button, wrapping around the ends. Navigation between menus preserves the
  ## open state: when the current button's popup is open, the target menu
  ## opens too; otherwise only the key focus (highlight) moves.
  let menuBar = button.owningMenuBar()
  if menuBar.isNil or menuBar.xButtons.len == 0 or delta == 0:
    return false
  let currentIndex = menuBar.xButtons.find(button)
  if currentIndex < 0:
    return false

  let openPopup = button.popupOpen()
  var index = currentIndex + delta
  for _ in 0 ..< menuBar.xButtons.len:
    if index < 0:
      index = menuBar.xButtons.len - 1
    elif index >= menuBar.xButtons.len:
      index = 0
    let candidate = menuBar.xButtons[index]
    if not candidate.isNil and candidate.enabled():
      if openPopup and menuBar.xOpenButton != candidate:
        if not menuBar.xOpenButton.isNil:
          menuBar.xOpenButton.closePopup()
        candidate.openPopup()
      let owner = candidate.ownerWindow()
      if not owner.isNil:
        discard owner.makeFirstResponder(candidate, focusVisible = true)
      return true
    index += delta
  false

proc menu*(menuBar: MenuBar): Menu =
  menuBar.xMenu

proc syncMenuBarPresentation(menuBar: MenuBar) =
  menuBar.hidden = menuBar.xMenu.presentedNatively()

proc menuBarItemWidth(menuBar: MenuBar, item: MenuItem): float32 =
  let style =
    menuBar.effectiveAppearance().resolveButtonStyle(controlStyle(srMenuBarItem))
  max(
    textNaturalSize(item.title(), style.text).width + style.text.insets.horizontal,
    style.minSize.width,
  )

proc menuBarNaturalSize(menuBar: MenuBar): Size =
  var width = menuBarHorizontalInset()
  if not menuBar.xMenu.isNil:
    for item in menuBar.xMenu.items:
      if not item.hidden():
        width += menuBar.menuBarItemWidth(item) + menuBarItemGap()
  initSize(width + menuBarHorizontalInset(), menuBarDefaultHeight())

proc clearMenuBarButtons(menuBar: MenuBar) =
  for button in menuBar.xButtons:
    button.closePopup()
    button.removeFromSuperview()
  menuBar.xButtons.setLen(0)
  menuBar.xOpenButton = nil

proc reloadImpl(menuBar: MenuBar) =
  menuBar.clearMenuBarButtons()
  if menuBar.xMenu.isNil:
    menuBar.setNeedsLayout()
    menuBar.needsDisplay = true
    return
  for item in menuBar.xMenu.items:
    if not item.hidden():
      let button = newPullDownButton(item.title(), item.submenu())
      button.enabled = not item.submenu().isNil
      button.popupPresentation = ppAutomatic
      menuBar.addSubview(button)
      menuBar.xButtons.add button
  menuBar.setNeedsLayout()
  menuBar.needsDisplay = true

proc `menu=`*(menuBar: MenuBar, menu: Menu) =
  if menuBar.xMenu == menu:
    return
  menuBar.xMenu = menu
  menuBar.syncMenuBarPresentation()
  menuBar.reload()

proc tileMenuBarItems(menuBar: MenuBar) =
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
        let width = menuBar.menuBarItemWidth(item)
        button.title = item.title()
        button.menu = item.submenu()
        button.enabled = not item.submenu().isNil
        button.frame = rect(x, buttonY, width, buttonHeight)
        x += width + menuBarItemGap()
      inc buttonIndex

protocol MenuBarDrawing of ViewDrawingProtocol:
  method drawsStyledBackground(view: View): bool =
    true

  method draw(menuBar: MenuBar, context: DrawContext) =
    let bounds = menuBar.bounds()
    if bounds.isEmpty:
      return
    let style = context.appearance.resolveBoxStyle(
      controlStyle(
        srMenuBar,
        menuBar.widgetStateSet(),
        id = menuBar.styleId,
        classes = menuBar.styleClasses,
      )
    )
    discard context.addRenderRectangle(context.renderRectFor(bounds), style.box.fill)
    if style.box.borderWidth <= 0.0'f32:
      return
    discard context.addRenderRectangle(
      context.renderRectFor(
        rect(
          0.0'f32,
          bounds.maxY - style.box.borderWidth,
          bounds.size.width,
          style.box.borderWidth,
        )
      ),
      fill(style.box.borderColor),
    )

protocol MenuBarLayout of ViewLayoutProtocol:
  method layoutStyleContext(menuBar: MenuBar): StyleContext =
    controlStyle(
      srMenuBar,
      menuBar.widgetStateSet(),
      id = menuBar.styleId,
      classes = menuBar.styleClasses,
    )

  method managesSubviewLayout(menuBar: MenuBar, child: DynamicAgent): bool =
    for button in menuBar.xButtons:
      if child == button:
        return true

  method layoutIntrinsicContentSize(menuBar: MenuBar): IntrinsicSize =
    initIntrinsicSize(menuBar.menuBarNaturalSize())

  method layoutSubviews(menuBar: MenuBar) =
    menuBar.tileMenuBarItems()

proc initMenuBarFields*(menuBar: MenuBar, menu: Menu = nil, frame: Rect = AutoRect) =
  initViewFields(menuBar, frame)
  menuBar.background = color(0.0, 0.0, 0.0, 0.0)
  discard menuBar.withProto()
  discard menuBar.withProtocol(MenuBarDrawing)
  discard menuBar.withProtocol(MenuBarLayout)
  discard menuBar.withProtocol(MenuBarAccessibility)
  discard menuBar.withProtocol(MenuBarPresentationLifecycle)
  menuBar.observeProtocol(menuBar, MenuBarPresentationLifecycle)
  menuBar.menu = menu
  menuBar.applyInitialFrame(frame)

proc newMenuBar*(menu: Menu = nil, frame: Rect = AutoRect): MenuBar =
  result = MenuBar()
  initMenuBarFields(result, menu, frame)

proc menuBar*(root: MenuRootView): MenuBar =
  root.xMenuBar

proc mainMenu*(root: MenuRootView): Menu =
  root.xMenuBar.menu()

proc `mainMenu=`*(root: MenuRootView, menu: Menu) =
  root.xMenuBar.menu = menu

proc contentView*(root: MenuRootView): View =
  root.xContentView

proc `contentView=`*(root: MenuRootView, contentView: View) =
  if root.xContentView == contentView:
    return
  if not root.xContentView.isNil:
    root.removeArrangedSubview(root.xContentView)
    root.xContentView.removeFromSuperview()
  root.xContentView = contentView
  if not contentView.isNil:
    root.addArrangedSubview(contentView)

proc initMenuRootViewFields*(
    root: MenuRootView,
    menu: Menu = nil,
    contentView: View = nil,
    frame: Rect = AutoRect,
) =
  initStackViewFields(root, laVertical, frame)
  root.spacing = 0.0'f32
  root.xMenuBar = newMenuBar(menu)
  root.xMenuBar.setHuggingPriority(LayoutPriorityRequired, laVertical)
  root.xMenuBar.setCompressionPriority(LayoutPriorityRequired, laVertical)
  root.addArrangedSubview(root.xMenuBar)
  root.contentView = contentView

proc newMenuRootView*(
    menu: Menu = nil, contentView: View = nil, frame: Rect = AutoRect
): MenuRootView =
  result = MenuRootView()
  initMenuRootViewFields(result, menu, contentView, frame)
