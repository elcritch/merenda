## UI assertions describe what is visible without depending on child order.
import std/unittest

import merenda/nimkit

proc buttonWithLabel*(view: View, label: string): Button =
  if view of Button and view.accessibilityLabel() == label:
    return Button(view)
  for child in view.subviews():
    let button = child.buttonWithLabel(label)
    if not button.isNil:
      return button

template checkVisibleIn*(view, container: View) =
  block:
    let frame = view.rectToView(view.bounds(), container)
    check not view.isHidden
    check not frame.isEmpty
    check frame.minX >= container.bounds().minX - 1
    check frame.minY >= container.bounds().minY - 1
    check frame.maxX <= container.bounds().maxX + 1
    check frame.maxY <= container.bounds().maxY + 1

proc selectPage*(tabs: TabView, identifier: string): bool =
  for index in 0 ..< tabs.len:
    if tabs[index].identifier == identifier:
      return tabs.selectTabViewItemAtIndex(index)

proc menuItemForAction*(menu: Menu, action: string): MenuItem =
  for item in menu.items():
    if item.action().name == actionSelector(action).name:
      return item
    if not item.submenu().isNil:
      let found = item.submenu().menuItemForAction(action)
      if not found.isNil:
        return found

proc popupIn*(view: View): PopupListView =
  for child in view.subviews():
    if child of PopupListView:
      return PopupListView(child)

proc choiceIndex*(popup: PopupListView, title: string): int =
  for index in 0 ..< popup.itemCount():
    if popup.itemText(index) == title:
      return index
  -1
