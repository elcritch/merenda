import std/unittest

import sigils/selectors

import merenda/nimkit

func center(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

type ContextSpyView = ref object of View
  rightDownCount: int
  handlesRightDown: bool
  actionCount: int

type MenuModelSpy = ref object of Responder
  allow: bool
  events: seq[string]

protocol ContextSpyActionProtocol:
  method contextSpyAction*(args: ActionArgs) {.optional.}

protocol ContextSpyEvents of ResponderEventProtocol:
  method rightMouseDown(spy: ContextSpyView, event: MouseEvent): bool =
    discard event
    inc spy.rightDownCount
    spy.handlesRightDown

protocol ContextSpyActions of ContextSpyActionProtocol:
  method contextSpyAction(spy: ContextSpyView, args: ActionArgs) =
    discard args
    inc spy.actionCount

protocol MenuModelSpyActionProtocol:
  method menuModelSpyAction*(args: ActionArgs) {.optional.}

protocol MenuModelSpyActions of MenuModelSpyActionProtocol:
  method menuModelSpyAction(spy: MenuModelSpy, args: ActionArgs) =
    discard args
    spy.events.add "action"

protocol MenuModelSpyValidation of UserInterfaceValidations:
  method validateUserInterfaceItem(spy: MenuModelSpy, args: ValidationArgs): bool =
    let item = MenuItem(args.item)
    spy.events.add "validate:" & item.identifier()
    item.state = bsOn
    item.subtitle = "validated"
    spy.allow

protocol MenuModelSpyMenuEvents from MenuModelSpy:
  includes MenuEvents

  proc menuItemDidActivate(
      spy: MenuModelSpy, sender: DynamicAgent, identifier: string
  ) {.slot.} =
    discard sender
    spy.events.add "activate:" & identifier

proc newContextSpyView(frame: Rect): ContextSpyView =
  result = ContextSpyView()
  initViewFields(result, frame)
  discard result.withProtocol(ContextSpyEvents)
  discard result.withProtocol(ContextSpyActions)

proc newMenuModelSpy(allow = true): MenuModelSpy =
  result = MenuModelSpy(allow: allow)
  initResponder(result)
  discard result.withProto()
  discard result.withProtocol(MenuModelSpyActions)
  discard result.withProtocol(MenuModelSpyValidation)

suite "nimkit menus":
  test "popup list keeps transparent view backing behind rounded chrome":
    let popup = newPopupListView()
    check popup.background() == initColor(0.0, 0.0, 0.0, 0.0)

  test "menu item models back identifiers hidden rows submenus and validation":
    let
      action = actionSelector("menuModelSpyAction")
      target = newMenuModelSpy(allow = false)
      menu = newMenu("Models")

    menu.itemModels = [
      initMenuItemModel(
        identifier = "run",
        title = "Run",
        subtitle = "Cmd-R",
        action = action,
        target = DynamicAgent(target),
        keyEquivalent = initKeyStroke("r", {kmCommand}),
        representedObject = DynamicAgent(target),
      ),
      initMenuItemModel(identifier = "hidden", title = "Hidden", hidden = true),
      initMenuItemModel(
        identifier = "off", title = "Off", enabled = false, validates = false
      ),
      initMenuItemModel(identifier = "line", separator = true),
      initMenuItemModel(
        identifier = "more",
        title = "More",
        children = [initMenuItemModel(identifier = "child", title = "Child")],
      ),
    ]

    check menu.itemModels.len == 5
    check menu.len == 4
    check menu[0.Natural].identifier == "run"
    check menu[0.Natural].subtitle == "Cmd-R"
    check menu[0.Natural].hasKeyEquivalent()
    check menu[0.Natural].keyEquivalent().text == "r"
    check menu[0.Natural].representedObject() == DynamicAgent(target)
    check menu.indexOfMenuItemIdentifier("hidden") == -1
    check menu.menuItemWithIdentifier("off").enabled() == false
    check menu[2.Natural].isSeparatorItem()
    let child =
      menu.menuItemWithIdentifier("more").submenu().menuItemWithIdentifier("child")
    check child.title == "Child"

    menu.update(target)
    check target.events == @["validate:run"]
    check not menu.menuItemWithIdentifier("run").enabled()
    check menu.menuItemWithIdentifier("run").state == bsOn
    check menu.menuItemWithIdentifier("run").subtitle == "validated"
    check not menu.itemModels[0].enabled
    check menu.itemModels[0].state == bsOn
    check menu.itemModels[0].subtitle == "validated"

    target.allow = true
    target.events.setLen(0)
    menu.update(target)
    check target.events == @["validate:run"]
    check menu.menuItemWithIdentifier("run").enabled()
    check menu.itemModels[0].enabled

  test "menu item activation signal reports model identifiers":
    let
      window = newWindow("Menu model activation", frame = initRect(0, 0, 240, 140))
      root = newView(frame = initRect(0, 0, 240, 140))
      menu = newMenu("Choices")
      button = newPopupMenuButton("Choices", menu, initRect(8, 8, 96, 24))
      spy = newMenuModelSpy()

    menu.itemModels = [
      initMenuItemModel(identifier = "one", title = "One", validates = false),
      initMenuItemModel(identifier = "two", title = "Two", validates = false),
    ]
    spy.observeProtocol(menu, MenuEvents)
    button.popupPresentation = ppInline
    root.addSubview(button)
    window.setContentView(root)

    discard window.buildRenders()
    check window.clickAt(button.pointToWindow(button.bounds().center()))
    check button.popupOpen()
    check root.subviews()[1] of PopupListView
    let popupList = PopupListView(root.subviews()[1])
    check window.clickAt(
      popupList.pointToWindow(
        popupList.popupListItemRect(popupList.bounds(), 1).center()
      )
    )
    check spy.events == @["activate:two"]

  test "view context menu opens on secondary click and dispatches item action":
    let
      window = newWindow("Context menu", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      target = newContextSpyView(initRect(20, 20, 80, 40))
      menu = newMenu("Actions")
      action = actionSelector("contextSpyAction")
      item = newMenuItem("Run", action)

    discard menu.addItem(item)
    target.setAcceptsFirstResponder(true)
    target.menu = menu
    root.addSubview(target)
    window.setContentView(root)

    check window.makeFirstResponder(target)
    check target.menu == menu
    check window.rightMouseDownAt(initPoint(30, 30), timestamp = 10.0)
    check menu.isOpen()
    check window.hasActiveTransientSession()
    check root.subviews.len == 3
    check root.subviews[1] of PopupMenuButton
    check root.subviews[2] of PopupListView

    let anchor = PopupMenuButton(root.subviews[1])
    check anchor.popupOpen()
    check anchor.hidden()
    check anchor.frame().origin == initPoint(30, 30)
    check window.firstResponder == anchor

    check window.mouseDownAt(initPoint(40, 42), timestamp = 10.1)
    check window.mouseUpAt(initPoint(40, 42), timestamp = 10.2)
    check target.actionCount == 1
    check not menu.isOpen()
    check not window.hasActiveTransientSession()
    check window.firstResponder == target
    check menu.nextResponder() == target
    check root.subviews.len == 1
    check root.subviews[0] == target

  test "view context menu waits for custom right mouse handling":
    let
      window = newWindow("Context fallback", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      target = newContextSpyView(initRect(20, 20, 80, 40))
      menu = newMenu("Actions")

    discard menu.addItem(newMenuItem("Run"))
    target.menu = menu
    root.addSubview(target)
    window.setContentView(root)

    target.handlesRightDown = true
    check window.rightMouseDownAt(initPoint(30, 30), timestamp = 20.0)
    check target.rightDownCount == 1
    check not menu.isOpen()
    check not window.hasActiveTransientSession()
    check root.subviews.len == 1

    target.handlesRightDown = false
    check window.rightMouseDownAt(initPoint(30, 30), timestamp = 21.0)
    check target.rightDownCount == 2
    check menu.isOpen()
    check window.hasActiveTransientSession()
    check window.firstResponder of PopupMenuButton

    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not menu.isOpen()
    check not window.hasActiveTransientSession()
    check window.firstResponder.isNil
    check menu.nextResponder() == target
    check root.subviews.len == 1
