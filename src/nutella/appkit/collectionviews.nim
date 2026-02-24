import ./runtime
import ./views

objcImpl:
  type NSCollectionView* = object of NSView
    contentId: ID
    itemPrototypeId: ID
    selectable {.set: setSelectable, get: isSelectable.}: bool
    minItem {.set: setMinItemSize, get: minItemSize.}: NSSize
    maxItem {.set: setMaxItemSize, get: maxItemSize.}: NSSize
    maxRows {.set: setMaxNumberOfRows, get: maxNumberOfRows.}: int
    maxCols {.set: setMaxNumberOfColumns, get: maxNumberOfColumns.}: int
    backgroundColorsId: ID
    allowsMulti {.set: setAllowsMultipleSelection, get: allowsMultipleSelection.}: bool
    selectionIndexesId: ID

  method init*(self: var NSCollectionView): NSCollectionView =
    result = asType[NSCollectionView](
      callSuperIdFrom(NSCollectionView, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.contentId = retainId(nsArray[NSObject]().value)
    result.itemPrototypeId = nil
    result.selectable = true
    result.minItem = nsSize(120, 120)
    result.maxItem = nsSize(120, 120)
    result.maxRows = 0
    result.maxCols = 0
    result.backgroundColorsId = retainId(nsArray[NSObject]().value)
    result.allowsMulti = false
    result.selectionIndexesId = nil

  method content*(self: NSCollectionView): NSArray[NSObject] =
    if self.contentId.isNil:
      return nsArray[NSObject]()
    ownFromId[NSArray[NSObject]](self.contentId)

  method setContent*(self: NSCollectionView, value: NSArray[NSObject]) =
    self.contentId = replacedOwnedId(self.contentId, value.value)

  method itemPrototype*(self: NSCollectionView): NSObject =
    if self.itemPrototypeId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.itemPrototypeId)

  method setItemPrototype*(self: NSCollectionView, value: NSObject) =
    self.itemPrototypeId = replacedOwnedId(self.itemPrototypeId, value.value)

  method backgroundColors*(self: NSCollectionView): NSArray[NSObject] =
    if self.backgroundColorsId.isNil:
      return nsArray[NSObject]()
    ownFromId[NSArray[NSObject]](self.backgroundColorsId)

  method setBackgroundColors*(self: NSCollectionView, value: NSArray[NSObject]) =
    self.backgroundColorsId = replacedOwnedId(self.backgroundColorsId, value.value)

  method selectionIndexes*(self: NSCollectionView): NSObject =
    if self.selectionIndexesId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.selectionIndexesId)

  method setSelectionIndexes*(self: NSCollectionView, value: NSObject) =
    self.selectionIndexesId = replacedOwnedId(self.selectionIndexesId, value.value)

  method isFirstResponder*(self: NSCollectionView): bool =
    false

  method newItemForRepresentedObject*(
      self: NSCollectionView, representedObject {.kw("object").}: NSObject
  ): NSObject =
    discard representedObject
    if self.itemPrototypeId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.itemPrototypeId)

  method dealloc(self: NSCollectionView) {.used.} =
    self.contentId = replacedOwnedId(self.contentId, nil)
    self.itemPrototypeId = replacedOwnedId(self.itemPrototypeId, nil)
    self.backgroundColorsId = replacedOwnedId(self.backgroundColorsId, nil)
    self.selectionIndexesId = replacedOwnedId(self.selectionIndexesId, nil)
    discard callSuperIdFrom(NSCollectionView, self, getSelector("dealloc"))

proc new*(t: typedesc[NSCollectionView]): NSCollectionView =
  var allocated = NSCollectionView.alloc()
  result = initOwned(move(allocated))
