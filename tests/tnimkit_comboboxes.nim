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

    combo.maxVisibleItems = 3
    combo.itemHeight = 18.0
    combo.editable = false
    check combo.maxVisibleItems == 3
    check combo.itemHeight == 18.0
    check not combo.editable

    combo.selectedIndex = 1
    check combo.selectedIndex == 1
    check combo.stringValue == "Medium"

    combo.text = "Custom"
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

    combo.dataSource = source
    combo.delegate = delegate
    combo.target = newActionTarget(action, onChanged)
    combo.action = action

    check combo.numberOfItems == 3
    check combo.itemAtIndex(2) == "Blue"

    combo.text = "Green"
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

    combo.itemHeight = 20.0
    root.addSubview(combo)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(20, 20))
    check combo.popupOpen
    check combo.highlightedIndex == 0
    check window.mouseUpAt(initPoint(20, 20))
    check combo.popupOpen

    let mediumPoint = initPoint(20, 10 + 24 + 1 + 20 + 10)
    check window.mouseDownAt(mediumPoint)
    check combo.highlightedIndex == 1
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

    combo.popupPresentation = ppWindow
    combo.popupOpen = true
    check combo.popupOpen
    check PopupDrawLevel notin window.buildRenders().layers

    combo.closePopup()
    combo.popupPresentation = ppInline
    combo.popupOpen = true
    check combo.popupOpen
    check PopupDrawLevel in window.buildRenders().layers

    combo.closePopup()
    combo.popupPresentation = ppAutomatic
    window.setPopupPresentation(ppInline)
    combo.popupOpen = true
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

    priority.itemHeight = 20.0
    color.itemHeight = 20.0
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
    check priority.highlightedIndex == 1
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

    combo.target = newActionTarget(action, onChanged)
    combo.action = action
    root.addSubview(combo)
    window.setContentView(root)

    check window.makeFirstResponder(combo)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupOpen
    check combo.highlightedIndex == 0

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.highlightedIndex == 1

    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check not combo.popupOpen
    check combo.indexOfSelectedItem() == 1
    check combo.stringValue == "Medium"
    check actionCount == 1

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupOpen
    check combo.highlightedIndex == 1
    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not combo.popupOpen
    check combo.indexOfSelectedItem() == 1

  test "inline popup session handles escape and outside click dismissal":
    let
      window = newWindow("Combo transient", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      combo = newComboBox(["Low", "Medium", "High"], frame = initRect(10, 10, 120, 24))

    combo.popupPresentation = ppInline
    root.addSubview(combo)
    window.setContentView(root)

    check window.makeFirstResponder(combo)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupOpen
    check window.hasActiveTransientSession()

    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not combo.popupOpen
    check not window.hasActiveTransientSession()
    check window.transientDismissReason() == tdrEscape
    check window.firstResponder == combo

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupOpen
    check window.hasActiveTransientSession()

    check window.mouseDownAt(initPoint(220, 140))
    check not combo.popupOpen
    check not window.hasActiveTransientSession()
    check window.transientDismissReason() == tdrOutsideClick
    check window.firstResponder == combo

  test "keyboard navigation scrolls popup rows into view":
    let
      window = newWindow("Combo scroll keys", frame = initRect(0, 0, 240, 180))
      root = newView(frame = initRect(0, 0, 240, 180))
      combo = newComboBox(
        ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"],
        frame = initRect(10, 10, 120, 24),
      )

    combo.popupPresentation = ppInline
    combo.maxVisibleItems = 3
    combo.itemHeight = 20.0
    root.addSubview(combo)
    window.setContentView(root)

    check window.makeFirstResponder(combo)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupOpen
    check combo.highlightedIndex == 0
    check combo.popupFirstItemIndex() == 0

    let popup = combo.popupRect(combo.bounds())
    check popup.size.height == 62.0'f32

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))

    check combo.highlightedIndex == 4
    check combo.popupFirstItemIndex() == 2
    check combo.popupItemRect(combo.bounds(), 1).isEmpty
    check not combo.popupItemRect(combo.bounds(), 2).isEmpty
    check combo.popupItemIndexAtPoint(
      combo.bounds(), initPoint(0.5'f32, combo.bounds().maxY + 10.0'f32)
    ) == -1
    check combo.popupItemIndexAtPoint(
      combo.bounds(), initPoint(8.0'f32, combo.bounds().maxY + 0.5'f32)
    ) == -1
    check combo.popupItemIndexAtPoint(
      combo.bounds(), initPoint(8.0, combo.bounds().maxY + 10.0)
    ) == 2

    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check not combo.popupOpen
    check combo.indexOfSelectedItem() == 4
    check combo.stringValue == "Five"

  test "popup page home and end keys move highlight through row windows":
    let
      window = newWindow("Combo page keys", frame = initRect(0, 0, 240, 180))
      root = newView(frame = initRect(0, 0, 240, 180))
      combo = newComboBox(
        ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"],
        frame = initRect(10, 10, 120, 24),
      )

    combo.popupPresentation = ppInline
    combo.maxVisibleItems = 3
    combo.itemHeight = 20.0
    root.addSubview(combo)
    window.setContentView(root)

    check window.makeFirstResponder(combo)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.popupOpen
    check combo.highlightedIndex == 0
    check combo.popupFirstItemIndex() == 0

    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check combo.highlightedIndex == 3
    check combo.popupFirstItemIndex() == 3

    let
      popup = combo.popupRect(combo.bounds())
      knob = combo.popupScrollerKnobRect(combo.bounds())
    check popup.size.height == 62.0'f32
    check not knob.isEmpty
    check knob.origin.x > popup.origin.x
    check knob.maxX <= popup.maxX
    check knob.origin.y > popup.origin.y
    check listScrollerKnobRect(popup, 0, 3, 3).isEmpty

    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check combo.highlightedIndex == 6
    check combo.popupFirstItemIndex() == 5

    check window.dispatchKeyDown(KeyEvent(key: keyPageUp, keyCode: keyPageUp.ord))
    check combo.highlightedIndex == 3
    check combo.popupFirstItemIndex() == 3

    check window.dispatchKeyDown(KeyEvent(key: keyEnd, keyCode: keyEnd.ord))
    check combo.highlightedIndex == 7
    check combo.popupFirstItemIndex() == 5

    check window.dispatchKeyDown(KeyEvent(key: keyHome, keyCode: keyHome.ord))
    check combo.highlightedIndex == 0
    check combo.popupFirstItemIndex() == 0

  test "popup border hover keeps keyboard highlight without delegate noise":
    let
      window = newWindow("Combo hover border", frame = initRect(0, 0, 240, 180))
      root = newView(frame = initRect(0, 0, 240, 180))
      combo =
        newComboBox(["One", "Two", "Three", "Four"], frame = initRect(10, 10, 120, 24))
      delegate = newComboDelegate()

    combo.popupPresentation = ppInline
    combo.maxVisibleItems = 3
    combo.itemHeight = 20.0
    combo.delegate = delegate
    root.addSubview(combo)
    window.setContentView(root)

    check window.makeFirstResponder(combo)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check combo.highlightedIndex == 1
    let changingCount = delegate.changingCount

    check window.mouseMovedAt(initPoint(20.0'f32, 34.5'f32))
    check combo.highlightedIndex == 1
    check delegate.changingCount == changingCount

    check window.mouseMovedAt(
      initPoint(20.0'f32, 10.0'f32 + 24.0'f32 + 1.0'f32 + 45.0'f32)
    )
    check combo.highlightedIndex == 2
    check delegate.changingCount == changingCount + 1

  test "mouse wheel scrolls open inline popup viewport":
    let
      window = newWindow("Combo wheel", frame = initRect(0, 0, 240, 180))
      root = newView(frame = initRect(0, 0, 240, 180))
      combo = newComboBox(
        ["One", "Two", "Three", "Four", "Five", "Six"],
        frame = initRect(10, 10, 120, 24),
      )

    combo.popupPresentation = ppInline
    combo.maxVisibleItems = 3
    combo.itemHeight = 20.0
    root.addSubview(combo)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(20, 20))
    check combo.popupOpen
    check window.mouseUpAt(initPoint(20, 20))
    check combo.popupOpen
    check combo.popupFirstItemIndex() == 0

    let firstRowPoint = initPoint(20.0, 10.0 + 24.0 + 10.0)
    check window.scrollWheelAt(firstRowPoint, deltaY = -1.0'f32)
    check combo.popupFirstItemIndex() == 1
    check combo.popupItemIndexAtPoint(
      combo.bounds(), initPoint(8.0, combo.bounds().maxY + 10.0)
    ) == 1

    check window.scrollWheelAt(firstRowPoint, deltaY = 1.0'f32)
    check combo.popupFirstItemIndex() == 0
