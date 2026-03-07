import ./runtime
import ./views
import ./controls
import ./textfields
import ./graphics
import ./colors
import ./attributedstrings
import ./events

const
  ComboBoxArrowZoneMinWidth = 16.0'f32
  ComboBoxArrowZoneMaxWidth = 22.0'f32

proc comboBoxArrowZoneRect*(controlBox: NSRect): NSRect =
  let arrowWidth = clamp(
    controlBox.size.height * 0.8, ComboBoxArrowZoneMinWidth, ComboBoxArrowZoneMaxWidth
  )
  let zoneWidth = min(arrowWidth, max(controlBox.size.width, 0.0))
  nsRect(
    controlBox.origin.x + controlBox.size.width - zoneWidth,
    controlBox.origin.y,
    zoneWidth,
    controlBox.size.height,
  )

proc comboBoxPopupItemHeight*[T](comboBox: T): float32 =
  max(comboBox.itemHeight() + 6.0, 18.0)

proc comboBoxVisiblePopupItems*[T](comboBox: T): int =
  let count = comboBox.numberOfItems()
  if count <= 0:
    return 0
  let requested = comboBox.numberOfVisibleItems()
  if requested <= 0:
    return count
  min(count, requested)

proc comboBoxPopupFirstItemIndex*[T](comboBox: T): int =
  let total = comboBox.numberOfItems()
  let visible = comboBoxVisiblePopupItems(comboBox)
  if total <= 0 or visible <= 0:
    return 0
  if total <= visible:
    return 0
  let selected = comboBox.indexOfSelectedItem()
  if selected < 0:
    return 0
  clamp(selected - visible + 1, 0, total - visible)

proc comboBoxPopupFrame*[T](comboBox: T, controlBox: NSRect): NSRect =
  let itemCount = comboBoxVisiblePopupItems(comboBox)
  if itemCount <= 0:
    return nsRect(controlBox.origin.x, controlBox.origin.y, 0.0, 0.0)
  let popupHeight = comboBoxPopupItemHeight(comboBox) * itemCount.float32 + 2.0
  nsRect(
    controlBox.origin.x,
    controlBox.origin.y + controlBox.size.height,
    max(controlBox.size.width, 0.0),
    popupHeight,
  )

proc comboBoxPopupItemIndexAtPoint*(
  comboBox: auto, controlBox: NSRect, x: float32, y: float32
): int

proc comboBoxPopupItemRect*(
    comboBox: auto, controlBox: NSRect, itemIndex: int
): NSRect =
  let firstIndex = comboBoxPopupFirstItemIndex(comboBox)
  let visibleIndex = itemIndex - firstIndex
  if visibleIndex < 0 or visibleIndex >= comboBoxVisiblePopupItems(comboBox):
    return nsRect(controlBox.origin.x, controlBox.origin.y, 0.0, 0.0)
  let popupBox = comboBoxPopupFrame(comboBox, controlBox)
  let itemHeight = comboBoxPopupItemHeight(comboBox)
  let yTop =
    popupBox.origin.y + popupBox.size.height - 1.0 - visibleIndex.float32 * itemHeight
  nsRect(
    popupBox.origin.x + 1.0,
    yTop - itemHeight,
    max(popupBox.size.width - 2.0, 0.0),
    max(itemHeight, 0.0),
  )

objcImpl:
  type NSComboBox* = object of NSTextField
    xObjectValues: seq[NSString]
    xSelectedIndex: int
    xDataSource: ID
    xUsesDataSource {.set: setUsesDataSource, get: usesDataSource.}: bool
    xButtonBordered {.set: setButtonBordered, get: isButtonBordered.}: bool
    xItemHeight {.set: setItemHeight, get: itemHeight.}: float32
    xHasVerticalScroller {.set: setHasVerticalScroller, get: hasVerticalScroller.}: bool
    xIntercellSpacing {.set: setIntercellSpacing, get: intercellSpacing.}: NSSize
    xCompletes {.set: setCompletes, get: completes.}: bool
    xNumberOfVisibleItems {.set: setNumberOfVisibleItems, get: numberOfVisibleItems.}:
      int
    xPopupOpen {.set: setPopupOpen, get: popupOpen.}: bool
    xPopupHoveredIndex {.set: setPopupHoveredIndex, get: popupHoveredIndex.}: int

  method init*(self: var NSComboBox): NSComboBox =
    result =
      asTypeRaw[NSComboBox](callSuperIdFrom(NSComboBox, self, getSelector("init")))
    if result.isNil:
      return
    result.xObjectValues = @[]
    result.xSelectedIndex = -1
    result.xDataSource.value = nil
    result.xUsesDataSource = false
    result.xButtonBordered = true
    result.xItemHeight = 16.0
    result.xHasVerticalScroller = false
    result.xIntercellSpacing = nsSize(3.0, 2.0)
    result.xCompletes = false
    result.xNumberOfVisibleItems = 5
    result.xPopupOpen = false
    result.xPopupHoveredIndex = -1
    result.setEditable(true)

  method initWithFrame*(
      self: var NSComboBox,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSComboBox =
    result = self.init()
    if result.isNil:
      return
    result.to(NSView).setFrame(
      nsRect(
        x.float32, y.float32, max(width.float32, 0.0'f32), max(height.float32, 0.0'f32)
      )
    )

  method drawRect*(self: NSComboBox, rect: NSRect) =
    discard rect
    if self.isNil:
      return

    let bounds = self.bounds()
    var valueRect = nsRect(
      bounds.origin.x + 3.0,
      bounds.origin.y + 3.0,
      max(bounds.size.width - 6.0, 0.0),
      max(bounds.size.height - 6.0, 0.0),
    )
    if self.isBezeled():
      NSDrawWhiteBezel(bounds, bounds)
      valueRect = nsRect(
        valueRect.origin.x - 1.0,
        valueRect.origin.y - 1.0,
        valueRect.size.width + 2.0,
        valueRect.size.height + 2.0,
      )
    elif self.isBordered():
      NSFrameRect(bounds)
      valueRect = nsRect(
        valueRect.origin.x - 1.0,
        valueRect.origin.y - 1.0,
        valueRect.size.width + 2.0,
        valueRect.size.height + 2.0,
      )
    if self.drawsBackground():
      self.backgroundColor().setFill()
      NSRectFill(valueRect)

    let arrowZone = comboBoxArrowZoneRect(bounds)
    let leftInset = 10.0'f32
    let rightInset = max((arrowZone.origin.x - bounds.origin.x) + 4.0, leftInset + 4.0)
    let textRect = nsRect(
      bounds.origin.x + leftInset,
      bounds.origin.y + 4.0,
      max(bounds.size.width - rightInset - leftInset, 0.0),
      max(bounds.size.height - 8.0, 0.0),
    )
    var currentValueAlloc = NSAttributedString.alloc()
    let currentValue = currentValueAlloc.initWithString(self.stringValue())
    currentValueAlloc.value = nil
    if not currentValue.isNil:
      currentValue.drawInRect(textRect)

    if arrowZone.size.width > 0.0 and arrowZone.size.height > 0.0:
      NSColor.colorWithCalibratedWhite(0.95, 1.0).setFill()
      NSRectFill(arrowZone)
      NSColor.colorWithCalibratedWhite(0.66, 1.0).setFill()
      NSRectFill(
        nsRect(
          arrowZone.origin.x,
          arrowZone.origin.y + 1.0,
          1.0,
          max(arrowZone.size.height - 2.0, 0.0),
        )
      )

      let triangleWidth = max(min(arrowZone.size.width * 0.28, 6.0), 4.0)
      let centerX = arrowZone.origin.x + arrowZone.size.width * 0.5
      let centerY = arrowZone.origin.y + arrowZone.size.height * 0.5
      NSColor.colorWithCalibratedWhite(0.26, 1.0).setFill()
      NSRectFill(
        nsRect(centerX - triangleWidth * 0.5, centerY + 1.0, triangleWidth, 1.0)
      )
      NSRectFill(
        nsRect(centerX - triangleWidth * 0.35, centerY, triangleWidth * 0.7, 1.0)
      )
      NSRectFill(
        nsRect(centerX - triangleWidth * 0.2, centerY - 1.0, triangleWidth * 0.4, 1.0)
      )

    if self.popupOpen():
      let popupBox = comboBoxPopupFrame(self, bounds)
      if popupBox.size.width <= 0.0 or popupBox.size.height <= 0.0:
        return
      NSColor.colorWithCalibratedWhite(0.99, 1.0).setFill()
      NSRectFill(popupBox)
      NSColor.colorWithCalibratedWhite(0.60, 1.0).setStroke()
      NSFrameRect(popupBox)

      let firstItem = comboBoxPopupFirstItemIndex(self)
      let lastItem = firstItem + comboBoxVisiblePopupItems(self)
      let selectedItem = self.indexOfSelectedItem()
      let hoveredItem = self.popupHoveredIndex()
      for itemIndex in firstItem ..< lastItem:
        let itemBox = comboBoxPopupItemRect(self, bounds, itemIndex)
        if itemBox.size.width <= 0.0 or itemBox.size.height <= 0.0:
          continue
        if itemIndex == selectedItem:
          NSColor.colorWithCalibratedRed(0.88, 0.93, 1.0, 1.0).setFill()
          NSRectFill(itemBox)
        elif itemIndex == hoveredItem:
          NSColor.colorWithCalibratedRed(0.78, 0.87, 1.0, 1.0).setFill()
          NSRectFill(itemBox)

        let itemValue = self.itemObjectValueAtIndex(itemIndex)
        if itemValue.isNil:
          continue
        let itemText = $itemValue
        if itemText.len == 0:
          continue
        let textBox = nsRect(
          itemBox.origin.x + 6.0,
          itemBox.origin.y + 2.0,
          max(itemBox.size.width - 12.0, 0.0),
          max(itemBox.size.height - 4.0, 0.0),
        )
        var itemAlloc = NSAttributedString.alloc()
        let itemString = itemAlloc.initWithString(itemValue)
        itemAlloc.value = nil
        if itemString.isNil:
          continue
        itemString.drawInRect(textBox)

  method dataSource*(self: NSComboBox): ID =
    retainId(self.xDataSource)

  method setDataSource*(self: NSComboBox, value: ID) =
    self.xDataSource.value = replacedOwnedId(self.xDataSource.value, value.value)

  method numberOfItems*(self: NSComboBox): int =
    self.xObjectValues.len

  method objectValues*(self: NSComboBox): NSArray[NSString] =
    nsArray[NSString](self.xObjectValues)

  method itemObjectValueAtIndex*(self: NSComboBox, index: int): NSString =
    if index < 0 or index >= self.xObjectValues.len:
      return NSString(value: nil)
    retain(self.xObjectValues[index])

  method indexOfItemWithObjectValue*(self: NSComboBox, value: NSObject): int =
    if value.isNil:
      return -1
    let needle = $value
    for idx, candidate in self.xObjectValues:
      if $candidate == needle:
        return idx
    -1

  method addItemWithObjectValue*(self: NSComboBox, value: NSObject) =
    if value.isNil:
      return
    if value.isKindOfClass(NSString):
      self.xObjectValues.add(value.NSString)
    else:
      self.xObjectValues.add(ns($value))
    self.noteNumberOfItemsChanged()

  method addItemsWithObjectValues*(self: NSComboBox, values: NSArray[NSObject]) =
    for item in values:
      self.addItemWithObjectValue(item)

  method removeAllItems*(self: NSComboBox) =
    self.xObjectValues = @[]
    self.xSelectedIndex = -1
    self.xPopupOpen = false
    self.xPopupHoveredIndex = -1
    self.setStringValue(@ns"")
    self.noteNumberOfItemsChanged()

  method removeItemAtIndex*(self: NSComboBox, index: int) =
    if index < 0 or index >= self.xObjectValues.len:
      return
    self.xObjectValues.del(index)
    if self.xObjectValues.len == 0:
      self.xSelectedIndex = -1
      self.xPopupOpen = false
      self.xPopupHoveredIndex = -1
      self.setStringValue(@ns"")
    elif self.xSelectedIndex == index:
      let nextIdx = min(index, self.xObjectValues.len - 1)
      self.selectItemAtIndex(nextIdx)
    elif index < self.xSelectedIndex:
      dec self.xSelectedIndex
    self.noteNumberOfItemsChanged()

  method removeItemWithObjectValue*(self: NSComboBox, value: NSObject) =
    let idx = self.indexOfItemWithObjectValue(value)
    if idx >= 0:
      self.removeItemAtIndex(idx)

  method insertItemWithObjectValue*(
      self: NSComboBox, value: NSObject, index {.kw("atIndex").}: int
  ) =
    if value.isNil:
      return
    let boundedIndex =
      if index < 0:
        0
      elif index > self.xObjectValues.len:
        self.xObjectValues.len
      else:
        index
    var objectValue = NSString(value: nil)
    if value.isKindOfClass(NSString):
      objectValue = value.NSString
    else:
      objectValue = ns($value)
    self.xObjectValues.insert(objectValue, boundedIndex)
    if self.xSelectedIndex >= boundedIndex:
      inc self.xSelectedIndex
    self.noteNumberOfItemsChanged()

  method indexOfSelectedItem*(self: NSComboBox): int =
    if self.xSelectedIndex < 0 or self.xSelectedIndex >= self.xObjectValues.len:
      return -1
    self.xSelectedIndex

  method hitTest*(self: NSComboBox, point: NSPoint): NSView =
    if self.isHiddenOrHasHiddenAncestor():
      return NSView(value: nil)
    if self.popupOpen():
      let popupBox = comboBoxPopupFrame(self, self.bounds())
      if popupBox.contains(point.x, point.y):
        return self.NSView
    if self.mouse(point, inRect = self.bounds()):
      return self.NSView
    NSView(value: nil)

  method objectValueOfSelectedItem*(self: NSComboBox): NSString =
    let idx = self.indexOfSelectedItem()
    if idx < 0:
      return NSString(value: nil)
    retain(self.xObjectValues[idx])

  method selectItemAtIndex*(self: NSComboBox, index: int) =
    if index < 0 or index >= self.xObjectValues.len:
      self.xSelectedIndex = -1
      self.xPopupHoveredIndex = -1
      self.setStringValue(@ns"")
      return
    self.xSelectedIndex = index
    self.xPopupHoveredIndex = index
    self.setStringValue(self.xObjectValues[index])

  method selectItemWithObjectValue*(self: NSComboBox, value: NSObject) =
    let idx = self.indexOfItemWithObjectValue(value)
    self.selectItemAtIndex(idx)

  method deselectItemAtIndex*(self: NSComboBox, index: int) =
    if self.xSelectedIndex != index:
      return
    self.xSelectedIndex = -1
    self.xPopupHoveredIndex = -1
    self.setStringValue(@ns"")

  method openPopup*(self: NSComboBox) =
    if self.numberOfItems() <= 0:
      self.xPopupOpen = false
      self.xPopupHoveredIndex = -1
      return
    self.xPopupOpen = true
    if self.xPopupHoveredIndex < 0:
      self.xPopupHoveredIndex = self.indexOfSelectedItem()

  method closePopup*(self: NSComboBox) =
    self.xPopupOpen = false
    self.xPopupHoveredIndex = -1

  method togglePopup*(self: NSComboBox) =
    if self.xPopupOpen:
      self.closePopup()
      return
    self.openPopup()

  method mouseDown*(self: NSComboBox, event: NSEvent) =
    if self.isNil or event.isNil or not self.isEnabled():
      return
    let localPoint =
      self.NSView.convertPoint(event.locationInWindow(), NSView(value: nil))
    if self.popupOpen():
      let itemIndex =
        comboBoxPopupItemIndexAtPoint(self, self.bounds(), localPoint.x, localPoint.y)
      self.setPopupHoveredIndex(itemIndex)
      if itemIndex < 0 and not self.bounds().contains(localPoint.x, localPoint.y):
        self.closePopup()
      self.setNeedsDisplay(true)
      return
    self.openPopup()
    self.setPopupHoveredIndex(self.indexOfSelectedItem())
    self.setNeedsDisplay(true)

  method mouseMoved*(self: NSComboBox, event: NSEvent) =
    if self.isNil or event.isNil or not self.popupOpen():
      return
    let localPoint =
      self.NSView.convertPoint(event.locationInWindow(), NSView(value: nil))
    let itemIndex =
      comboBoxPopupItemIndexAtPoint(self, self.bounds(), localPoint.x, localPoint.y)
    if self.popupHoveredIndex() == itemIndex:
      return
    self.setPopupHoveredIndex(itemIndex)
    self.setNeedsDisplay(true)

  method mouseDragged*(self: NSComboBox, event: NSEvent) =
    self.mouseMoved(event)

  method mouseUp*(self: NSComboBox, event: NSEvent) =
    if self.isNil or event.isNil or not self.popupOpen():
      return
    let localPoint =
      self.NSView.convertPoint(event.locationInWindow(), NSView(value: nil))
    let itemIndex =
      comboBoxPopupItemIndexAtPoint(self, self.bounds(), localPoint.x, localPoint.y)
    if itemIndex >= 0 and not siwinGenerated(event):
      self.activateItemAtIndex(itemIndex)
    self.closePopup()
    self.setNeedsDisplay(true)

  method activateItemAtIndex*(self: NSComboBox, index: int) =
    if index < 0 or index >= self.numberOfItems():
      return
    self.selectItemAtIndex(index)
    let control = self.NSControl
    discard control.sendAction(control.action(), control.target())

  method scrollItemAtIndexToTop*(self: NSComboBox, index: int) =
    discard

  method scrollItemAtIndexToVisible*(self: NSComboBox, index: int) =
    discard

  method noteNumberOfItemsChanged*(self: NSComboBox) =
    if self.xSelectedIndex >= self.xObjectValues.len:
      self.xSelectedIndex = -1
      self.setStringValue(@ns"")
    if self.xPopupOpen and self.xObjectValues.len == 0:
      self.xPopupOpen = false
      self.xPopupHoveredIndex = -1

  method reloadData*(self: NSComboBox) =
    discard

  method dealloc(self: NSComboBox) {.used.} =
    self.xObjectValues = @[]
    self.xDataSource.value = replacedOwnedId(self.xDataSource.value, nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSComboBox, self, getSelector("dealloc"))

proc new*(t: typedesc[NSComboBox]): NSComboBox =
  var allocated = NSComboBox.alloc()
  result = initOwned(move(allocated))

proc comboBoxPopupItemIndexAtPoint*(
    comboBox: auto, controlBox: NSRect, x: float32, y: float32
): int =
  let popupBox = comboBoxPopupFrame(comboBox, controlBox)
  if popupBox.size.width <= 0.0 or popupBox.size.height <= 0.0:
    return -1
  if not popupBox.contains(x, y):
    return -1
  let itemHeight = comboBoxPopupItemHeight(comboBox)
  if itemHeight <= 0.0:
    return -1
  let fromTop = popupBox.origin.y + popupBox.size.height - y - 1.0
  let visibleIndex = int(fromTop / itemHeight)
  if visibleIndex < 0 or visibleIndex >= comboBoxVisiblePopupItems(comboBox):
    return -1
  let itemIndex = comboBoxPopupFirstItemIndex(comboBox) + visibleIndex
  if itemIndex < 0 or itemIndex >= comboBox.numberOfItems():
    return -1
  itemIndex
