import std/options

import sigils/selectors

import ./events
import ./keybindings
import ./responders
import ./selectors as nimkitSelectors
import ./types

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

proc newMenu*(title = ""): Menu =
  result = Menu(xTitle: title)
  initResponder(result)

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

proc open*(menu: Menu) =
  if menu.isNil:
    return
  menu.menuNeedsUpdate()
  menu.xOpen = true
  if not menu.xDelegate.isNil:
    discard menu.xDelegate.sendLocalIfHandled(menuWillOpen(), DynamicAgent(menu))

proc close*(menu: Menu) =
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

proc update*(menu: Menu, start: Responder = nil) =
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

proc performKeyEquivalent*(menu: Menu, event: KeyEvent, start: Responder): bool =
  let item = menu.findKeyEquivalentItem(event)
  if item.isNil:
    return false
  item.perform(start)
