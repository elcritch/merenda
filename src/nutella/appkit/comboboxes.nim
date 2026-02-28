import ./runtime
import ./views
import ./controls
import ./textfields

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
    asRetainedType[NSView](result).setFrame(
      x.float32, y.float32, max(width.float32, 0.0'f32), max(height.float32, 0.0'f32)
    )

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
      self.xObjectValues.add(asRetainedType[NSString](value))
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
      objectValue = asRetainedType[NSString](value)
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

  method activateItemAtIndex*(self: NSComboBox, index: int) =
    if index < 0 or index >= self.numberOfItems():
      return
    self.selectItemAtIndex(index)
    let control = asRetainedType[NSControl](self)
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
