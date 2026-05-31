import std/[tables, unittest]

import merenda/nimkit

type
  ComboDataSource = ref object of Responder
    items: seq[string]

  ComboDelegate = ref object of Responder
    changingCount: int
    changedCount: int
    lastSender: DynamicAgent

protocol ComboDataSourceMethods of ComboBoxDataSource:
  method numberOfItemsInComboBox(source: ComboDataSource, comboBox: ComboBox): int =
    source.items.len

  method comboBoxObjectValueForItemAtIndex(
      source: ComboDataSource, comboBox: ComboBox, index: int
  ): string =
    if index < 0 or index >= source.items.len:
      return ""
    source.items[index]

protocol ComboDelegateMethods of ComboBoxDelegate:
  method comboBoxSelectionIsChanging(delegate: ComboDelegate, args: ActionArgs) =
    inc delegate.changingCount
    delegate.lastSender = args.sender

  method comboBoxSelectionDidChange(delegate: ComboDelegate, args: ActionArgs) =
    inc delegate.changedCount
    delegate.lastSender = args.sender

proc newComboDataSource(items: openArray[string]): ComboDataSource =
  result = ComboDataSource(items: @items)
  initResponder(result)
  discard result.withProtocol(ComboDataSourceMethods)

proc newComboDelegate(): ComboDelegate =
  result = ComboDelegate()
  initResponder(result)
  discard result.withProtocol(ComboDelegateMethods)

suite "nimkit comboboxes":
  test "combo box stores local items and syncs selected string":
    let combo = newComboBox(["Small", "Medium"], frame = initRect(0, 0, 140, 26))

    check combo.conformsTo(ComboBoxProtocol)
    check combo.numberOfItems == 2
    check combo.itemAtIndex(1) == "Medium"
    check combo.indexOfItem("Small") == 0
    check combo.indexOfSelectedItem() == -1

    combo.selectItemAtIndex(1)
    check combo.selectedIndex == 1
    check combo.stringValue == "Medium"

    combo.setStringValue("Custom")
    check combo.stringValue == "Custom"
    check combo.indexOfSelectedItem() == -1

    combo.insertItem("Large", 2)
    check combo.numberOfItems == 3
    check combo.itemAtIndex(2) == "Large"

    combo.removeItemAtIndex(0)
    check combo.numberOfItems == 2
    combo.removeAllItems()
    check combo.numberOfItems == 0
    check combo.stringValue == ""

  test "combo box resolves items from data source and notifies delegate on activation":
    let
      combo = newComboBox(frame = initRect(0, 0, 140, 26))
      source = newComboDataSource(["Red", "Green", "Blue"])
      delegate = newComboDelegate()
      action = actionSelector("comboSelectionChanged")

    var
      actionCount = 0
      actionSender: DynamicAgent

    proc onChanged(sender: DynamicAgent) =
      inc actionCount
      actionSender = sender

    combo.setDataSource(source)
    combo.setDelegate(delegate)
    combo.setTarget(newActionTarget(action, onChanged))
    combo.setAction(action)

    check combo.numberOfItems == 3
    check combo.itemAtIndex(2) == "Blue"

    combo.setStringValue("Green")
    check combo.indexOfSelectedItem() == 1

    combo.activateItemAtIndex(2)
    check combo.stringValue == "Blue"
    check combo.indexOfSelectedItem() == 2
    check delegate.changedCount == 1
    check delegate.lastSender == DynamicAgent(combo)
    check actionCount == 1
    check actionSender == DynamicAgent(combo)

  test "mouse opens popup and selects clicked item":
    let
      window = newWindow("Combo mouse", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      combo = newComboBox(["Low", "Medium", "High"], frame = initRect(10, 10, 120, 24))

    combo.setItemHeight(20.0)
    root.addSubview(combo)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(20, 20))
    check combo.popupOpen
    check combo.popupHighlightedIndex == 0
    check window.mouseUpAt(initPoint(20, 20))
    check combo.popupOpen

    let mediumPoint = initPoint(20, 10 + 24 + 1 + 20 + 10)
    check window.mouseDownAt(mediumPoint)
    check combo.popupHighlightedIndex == 1
    check window.mouseUpAt(mediumPoint)
    check not combo.popupOpen
    check combo.indexOfSelectedItem() == 1
    check combo.stringValue == "Medium"

  test "popup presentation can force inline or window rendering":
    let
      window = newWindow("Combo popup presentation", frame = initRect(0, 0, 220, 150))
      root = newView(frame = initRect(0, 0, 220, 150))
      combo = newComboBox(["Low", "Medium", "High"], frame = initRect(10, 20, 120, 26))

    root.addSubview(combo)
    window.setContentView(root)

    check combo.popupPresentation == ppAutomatic
    check window.popupPresentation == ppAutomatic

    combo.setPopupPresentation(ppWindow)
    combo.openPopup()
    check combo.popupOpen
    check PopupDrawLevel notin window.buildRenders().layers

    combo.closePopup()
    combo.setPopupPresentation(ppInline)
    combo.openPopup()
    check combo.popupOpen
    check PopupDrawLevel in window.buildRenders().layers

    combo.closePopup()
    combo.setPopupPresentation(ppAutomatic)
    window.setPopupPresentation(ppInline)
    combo.openPopup()
    check combo.popupPresentation == ppAutomatic
    check window.effectivePopupPresentation == ppInline
    check PopupDrawLevel in window.buildRenders().layers

  test "open popup wins hit testing over overlapping sibling controls":
    let
      window = newWindow("Combo popup", frame = initRect(0, 0, 240, 180))
      root = newView(frame = initRect(0, 0, 240, 180))
      priority =
        newComboBox(["Low", "Medium", "High"], frame = initRect(10, 10, 140, 24))
      color = newComboBox(["Red", "Green", "Blue"], frame = initRect(10, 48, 140, 24))

    priority.setItemHeight(20.0)
    color.setItemHeight(20.0)
    root.addSubview(priority)
    root.addSubview(color)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(20, 20))
    check priority.popupOpen
    check window.mouseUpAt(initPoint(20, 20))
    check priority.popupOpen

    let mediumPoint = initPoint(20, 10 + 24 + 1 + 20 + 10)
    check color.bounds().contains(color.pointFromView(mediumPoint, root))
    check root.hitTest(mediumPoint) == priority
    check window.mouseDownAt(mediumPoint)
    check priority.popupHighlightedIndex == 1
    check window.mouseUpAt(mediumPoint)
    check priority.indexOfSelectedItem() == 1
    check priority.stringValue == "Medium"
    check not priority.popupOpen
    check not color.popupOpen
    check color.indexOfSelectedItem() == -1

  test "keyboard opens navigates confirms and cancels popup":
    let
      window = newWindow("Combo keys", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      combo = newComboBox(["Low", "Medium", "High"], frame = initRect(10, 10, 120, 24))
      action = actionSelector("comboKeyboardChanged")

    var actionCount = 0

    proc onChanged(sender: DynamicAgent) =
      if sender == DynamicAgent(combo):
        inc actionCount

    combo.setTarget(newActionTarget(action, onChanged))
    combo.setAction(action)
    root.addSubview(combo)
    window.setContentView(root)

    check window.makeFirstResponder(combo)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupOpen
    check combo.popupHighlightedIndex == 0

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupHighlightedIndex == 1

    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check not combo.popupOpen
    check combo.indexOfSelectedItem() == 1
    check combo.stringValue == "Medium"
    check actionCount == 1

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupOpen
    check combo.popupHighlightedIndex == 1
    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not combo.popupOpen
    check combo.indexOfSelectedItem() == 1
