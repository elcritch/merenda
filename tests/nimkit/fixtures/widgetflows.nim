## Drive controls through their laid-out window coordinates.
import merenda/nimkit

proc pressKey*(window: Window, key: Key): bool =
  window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord))

proc clickRect*(window: Window, view: View, area: Rect): bool =
  let point = view.pointToWindow(
    initPoint(area.minX + area.size.width / 2, area.minY + area.size.height / 2)
  )
  # Text fields handle mouse-down; buttons activate on mouse-up. Send both even
  # when one phase is unhandled, and assert the feature's outcome at the call site.
  let down = window.mouseDownAt(point)
  let up = window.mouseUpAt(point)
  down or up

proc clickView*(window: Window, view: View): bool =
  doAssert not window.contentView().isNil,
    "attach the content before sending window events"
  window.contentView().layoutSubtreeIfNeeded()
  window.clickRect(view, view.bounds())

proc replaceText*(window: Window, field: TextField, text: string): bool =
  if not window.clickView(field):
    return
  if not window.dispatchKeyDown(
    KeyEvent(key: keyA, keyCode: keyA.ord, modifiers: shortcutModifiers())
  ):
    return
  window.dispatchTextInput(text)

proc chooseItem*(window: Window, combo: ComboBox, title: string): bool =
  ## Select an enabled item from a flat combo through its popup and keyboard.
  let index = combo.indexOfItem(title)
  if index < 0:
    return
  combo.popupPresentation = ppInline
  if not window.clickView(combo) or not combo.popupOpen():
    return
  if not window.pressKey(keyHome):
    return
  for _ in 0 ..< index:
    if not window.pressKey(keyArrowDown):
      return
  if window.pressKey(keyEnter):
    result = combo.stringValue == title and not combo.popupOpen()

proc clickTab*(window: Window, tabs: TabView, identifier: string): bool =
  doAssert not window.contentView().isNil,
    "attach the content before sending window events"
  window.contentView().layoutSubtreeIfNeeded()
  for index, item in tabs.items():
    if item.identifier == identifier:
      return
        window.clickRect(tabs, tabs.tabRect(index)) and
        tabs.selectedTabViewItem().identifier == identifier
