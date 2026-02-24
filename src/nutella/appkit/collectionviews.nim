import ./runtime
import ./views

objcImpl:
  type NSCollectionView* = object of NSView
    xxContent {.set: setContent, get: content.}: NSArray[NSObject]
    xxItemPrototype {.set: setItemPrototype, get: itemPrototype.}: NSObject
    selectable {.set: setSelectable, get: isSelectable.}: bool
    minItem {.set: setMinItemSize, get: minItemSize.}: NSSize
    maxItem {.set: setMaxItemSize, get: maxItemSize.}: NSSize
    maxRows {.set: setMaxNumberOfRows, get: maxNumberOfRows.}: int
    maxCols {.set: setMaxNumberOfColumns, get: maxNumberOfColumns.}: int
    xxBackgroundColors {.set: setBackgroundColors, get: backgroundColors.}:
      NSArray[NSObject]
    allowsMulti {.set: setAllowsMultipleSelection, get: allowsMultipleSelection.}: bool
    xxSelectionIndexes {.set: setSelectionIndexes, get: selectionIndexes.}: NSObject

  method init*(self: var NSCollectionView): NSCollectionView =
    result = asType[NSCollectionView](
      callSuperIdFrom(NSCollectionView, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xxContent = nsArray[NSObject]()
    result.xxItemPrototype = NSObject(value: nil)
    result.selectable = true
    result.minItem = nsSize(120, 120)
    result.maxItem = nsSize(120, 120)
    result.maxRows = 0
    result.maxCols = 0
    result.xxBackgroundColors = nsArray[NSObject]()
    result.allowsMulti = false
    result.xxSelectionIndexes = NSObject(value: nil)

  method isFirstResponder*(self: NSCollectionView): bool =
    false

  method newItemForRepresentedObject*(
      self: NSCollectionView, representedObject {.kw("object").}: NSObject
  ): NSObject =
    discard representedObject
    let prototype = self.itemPrototype()
    if prototype.isNil:
      return NSObject(value: nil)
    prototype

  method dealloc(self: NSCollectionView) {.used.} =
    self.xxContent = NSArray[NSObject](value: nil)
    self.xxItemPrototype = NSObject(value: nil)
    self.xxBackgroundColors = NSArray[NSObject](value: nil)
    self.xxSelectionIndexes = NSObject(value: nil)
    discard callSuperIdFrom(NSCollectionView, self, getSelector("dealloc"))

proc new*(t: typedesc[NSCollectionView]): NSCollectionView =
  var allocated = NSCollectionView.alloc()
  result = initOwned(move(allocated))
