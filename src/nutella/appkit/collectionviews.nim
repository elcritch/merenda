import ./runtime
import ./views

objcImpl:
  type NSCollectionView* = object of NSView
    xContent {.set: setContent, get: content.}: NSArray[NSObject]
    xItemPrototype {.set: setItemPrototype, get: itemPrototype.}: NSObject
    selectable {.set: setSelectable, get: isSelectable.}: bool
    minItem {.set: setMinItemSize, get: minItemSize.}: NSSize
    maxItem {.set: setMaxItemSize, get: maxItemSize.}: NSSize
    maxRows {.set: setMaxNumberOfRows, get: maxNumberOfRows.}: int
    maxCols {.set: setMaxNumberOfColumns, get: maxNumberOfColumns.}: int
    xBackgroundColors {.set: setBackgroundColors, get: backgroundColors.}:
      NSArray[NSObject]
    allowsMulti {.set: setAllowsMultipleSelection, get: allowsMultipleSelection.}: bool
    xSelectionIndexes {.set: setSelectionIndexes, get: selectionIndexes.}: NSObject

  method init*(self: var NSCollectionView): NSCollectionView =
    result = asType[NSCollectionView](
      callSuperIdFrom(NSCollectionView, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.xContent = nsArray[NSObject]()
    result.xItemPrototype = NSObject(value: nil)
    result.selectable = true
    result.minItem = nsSize(120, 120)
    result.maxItem = nsSize(120, 120)
    result.maxRows = 0
    result.maxCols = 0
    result.xBackgroundColors = nsArray[NSObject]()
    result.allowsMulti = false
    result.xSelectionIndexes = NSObject(value: nil)

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
    self.xContent = NSArray[NSObject](value: nil)
    self.xItemPrototype = NSObject(value: nil)
    self.xBackgroundColors = NSArray[NSObject](value: nil)
    self.xSelectionIndexes = NSObject(value: nil)
    discard callSuperIdFrom(NSCollectionView, self, getSelector("dealloc"))

proc new*(t: typedesc[NSCollectionView]): NSCollectionView =
  var allocated = NSCollectionView.alloc()
  result = initOwned(move(allocated))
