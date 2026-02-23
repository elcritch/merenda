import ./runtime

objcImpl:

  type NXCollectionView* = object of NXView
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

  method init*(self: var NXCollectionView): NXCollectionView =
    result = asType[NXCollectionView](
      callSuperIdFrom(NXCollectionView, self, getSelector("init"))
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

  method content*(self: NXCollectionView): NSArray[NSObject] =
    if self.contentId.isNil:
      return nsArray[NSObject]()
    ownFromId[NSArray[NSObject]](self.contentId)

  method setContent*(self: NXCollectionView, value: NSArray[NSObject]) =
    self.contentId = replacedOwnedId(self.contentId, value.value)

  method itemPrototype*(self: NXCollectionView): NSObject =
    if self.itemPrototypeId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.itemPrototypeId)

  method setItemPrototype*(self: NXCollectionView, value: NSObject) =
    self.itemPrototypeId = replacedOwnedId(self.itemPrototypeId, value.value)

  method backgroundColors*(self: NXCollectionView): NSArray[NSObject] =
    if self.backgroundColorsId.isNil:
      return nsArray[NSObject]()
    ownFromId[NSArray[NSObject]](self.backgroundColorsId)

  method setBackgroundColors*(self: NXCollectionView, value: NSArray[NSObject]) =
    self.backgroundColorsId = replacedOwnedId(self.backgroundColorsId, value.value)

  method selectionIndexes*(self: NXCollectionView): NSObject =
    if self.selectionIndexesId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.selectionIndexesId)

  method setSelectionIndexes*(self: NXCollectionView, value: NSObject) =
    self.selectionIndexesId = replacedOwnedId(self.selectionIndexesId, value.value)

  method isFirstResponder*(self: NXCollectionView): bool =
    false

  method newItemForRepresentedObject*(
      self: NXCollectionView, representedObject {.kw("object").}: NSObject
  ): NSObject =
    discard representedObject
    if self.itemPrototypeId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.itemPrototypeId)

  method dealloc(self: NXCollectionView) {.used.} =
    self.contentId = replacedOwnedId(self.contentId, nil)
    self.itemPrototypeId = replacedOwnedId(self.itemPrototypeId, nil)
    self.backgroundColorsId = replacedOwnedId(self.backgroundColorsId, nil)
    self.selectionIndexesId = replacedOwnedId(self.selectionIndexesId, nil)
    discard callSuperIdFrom(NXCollectionView, self, getSelector("dealloc"))


proc new*(t: typedesc[NSCollectionView]): NSCollectionView =
  var allocated = NSCollectionView.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

