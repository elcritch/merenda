## Shared value-state storage for model-backed collections. Views and controllers
## retain their public model types, sort policies, and notification boundaries.

import std/[algorithm, options, tables]

import ../objectvalues

type
  ItemIndexes = object
    source: int
    arranged: int
    arrangedGeneration: Natural

  ItemCollection*[T] = object
    items*: seq[T]
    arrangedIndexes*: seq[int]
    xIdentifierIndexes: Table[string, ItemIndexes]
    xSourceIndexesValid: bool
    xArrangedIdentifierIndexesValid: bool
    xArrangedGeneration: Natural
    arrangementValid*: bool
    xIndexesEmptyIdentifiers: bool
    revision*: Natural

proc len*[T](collection: ItemCollection[T]): int {.inline.} =
  ## Returns the source item count, including hidden and filtered-out items.
  collection.items.len

proc `[]`*[T](collection: ItemCollection[T], sourceIndex: int): lent T {.inline.} =
  ## Borrows an item by source position, independent of filtering and sorting.
  collection.items[sourceIndex]

iterator items*[T](collection: ItemCollection[T]): lent T {.inline.} =
  ## Borrows source items in storage order.
  for item in collection.items:
    yield item

iterator pairs*[T](
    collection: ItemCollection[T]
): tuple[index: int, item: lent T] {.inline.} =
  ## Yields source positions and borrowed items in storage order.
  for index in 0 ..< collection.len:
    yield (index, collection[index])

proc itemColumnIdentifier*[T](column: T): string {.inline.} =
  if column.identifier.len > 0: column.identifier else: column.valueKey

proc itemColumnTitle*[T](column: T): string {.inline.} =
  if column.title.len > 0:
    column.title
  else:
    column.itemColumnIdentifier()

proc itemColumnKey*[T](columns: openArray[T], identifier: string): string =
  for column in columns:
    if column.itemColumnIdentifier() == identifier:
      if column.valueKey.len > 0:
        return column.valueKey
      return column.itemColumnIdentifier()
  identifier

proc initItemCollection*[T](
    items: openArray[T] = [], indexEmptyIdentifiers = false
): ItemCollection[T] =
  ItemCollection[T](items: @items, xIndexesEmptyIdentifiers: indexEmptyIdentifiers)

proc invalidate*[T](
    collection: var ItemCollection[T], sourceChanged = false, arrangementChanged = true
) =
  if sourceChanged:
    collection.xSourceIndexesValid = false
    collection.xIdentifierIndexes = default(Table[string, ItemIndexes])
  if sourceChanged or arrangementChanged:
    collection.arrangementValid = false
    collection.xArrangedIdentifierIndexesValid = false
  inc collection.revision

proc replaceItems*[T](collection: var ItemCollection[T], items: openArray[T]) =
  collection.items = @items
  collection.invalidate(sourceChanged = true)

proc fillSourceIndex(indexes: var ItemIndexes, sourceIndex: int) {.inline.} =
  if indexes.source < 0:
    indexes.source = sourceIndex

proc buildSourceIndexes[T](collection: var ItemCollection[T]) =
  # Only identity queries allocate this table. Borrow identifiers directly so
  # building it never copies the other fields of an item.
  for index, item in collection:
    let identifier {.cursor.} = item.identifier
    if identifier.len > 0 or collection.xIndexesEmptyIdentifiers:
      collection.xIdentifierIndexes
      .mgetOrPut(identifier, ItemIndexes(source: -1, arranged: -1))
      .fillSourceIndex(index)
  collection.xSourceIndexesValid = true

proc sourceIndexOfIdentifier*[T](
    collection: var ItemCollection[T], identifier: string
): int {.inline.} =
  if identifier.len == 0 and not collection.xIndexesEmptyIdentifiers:
    return -1
  if not collection.xSourceIndexesValid:
    collection.buildSourceIndexes()
  collection.xIdentifierIndexes.withValue(identifier, indexes):
    return indexes.source
  -1

proc getItemWithIdentifier*[T](
    collection: var ItemCollection[T], identifier: string
): Option[T] =
  let index = collection.sourceIndexOfIdentifier(identifier)
  if index >= 0:
    some(collection[index])
  else:
    none(T)

proc arrange*[T](
    collection: var ItemCollection[T],
    filter: proc(item: T): bool {.closure.},
    compare: proc(left, right: int): int {.closure.} = nil,
) =
  ## The comparator reads source items by index. It is used synchronously and
  ## never retained, so it can refer to the owning model without a retain cycle.
  if collection.arrangementValid:
    return
  # Invalid arrangements are never queried. Reuse their storage even when a
  # predicate or comparator raises; the next attempt clears it and retries.
  collection.xArrangedIdentifierIndexesValid = false
  collection.arrangedIndexes.setLen(0)
  for index, item in collection:
    if not item.hidden and (filter.isNil or filter(item)):
      collection.arrangedIndexes.add index
  if not compare.isNil:
    collection.arrangedIndexes.sort(compare)
  collection.arrangementValid = true

template arrangeWithDescriptors*(
    collection, filter, descriptors, sortedArrangement: untyped
) =
  # Keep closure construction in the owner's separate sorted helper. Nim can
  # otherwise allocate its environment even when the cache guard returns early.
  if not collection.arrangementValid:
    if descriptors.len == 0:
      collection.arrange(filter)
    else:
      sortedArrangement

proc arrangedSourceIndex*[T](
    collection: ItemCollection[T], index: int
): int {.inline.} =
  if index in 0 ..< collection.arrangedIndexes.len:
    collection.arrangedIndexes[index]
  else:
    -1

proc buildArrangedIdentifierIndexes[T](collection: var ItemCollection[T]) =
  # Visible queries index only visible identities. A generation makes old
  # positions stale without scanning hidden/source-only entries on each refresh.
  if collection.xArrangedGeneration == high(Natural):
    for indexes in collection.xIdentifierIndexes.mvalues:
      indexes.arrangedGeneration = 0
    collection.xArrangedGeneration = 0
  inc collection.xArrangedGeneration
  for arrangedIndex, sourceIndex in collection.arrangedIndexes:
    let identifier {.cursor.} = collection[sourceIndex].identifier
    if identifier.len > 0 or collection.xIndexesEmptyIdentifiers:
      collection.xIdentifierIndexes.withValue(identifier, indexes):
        if indexes.arrangedGeneration != collection.xArrangedGeneration:
          indexes.arranged = arrangedIndex
          indexes.arrangedGeneration = collection.xArrangedGeneration
      do:
        collection.xIdentifierIndexes[identifier] = ItemIndexes(
          source: -1,
          arranged: arrangedIndex,
          arrangedGeneration: collection.xArrangedGeneration,
        )
  collection.xArrangedIdentifierIndexesValid = true

proc arrangedIndexOfIdentifier*[T](
    collection: var ItemCollection[T], identifier: string
): int {.inline.} =
  if identifier.len == 0 and not collection.xIndexesEmptyIdentifiers:
    return -1
  if not collection.xArrangedIdentifierIndexesValid:
    collection.buildArrangedIdentifierIndexes()
  collection.xIdentifierIndexes.withValue(identifier, indexes):
    if indexes.arrangedGeneration == collection.xArrangedGeneration:
      return indexes.arranged
  -1

proc indexInsertedItem[T](collection: var ItemCollection[T], index: int) =
  if collection.xSourceIndexesValid:
    let identifier {.cursor.} = collection.items[index].identifier
    if identifier.len > 0 or collection.xIndexesEmptyIdentifiers:
      collection.xIdentifierIndexes.withValue(identifier, indexes):
        indexes.source = min(indexes.source, index)
      do:
        collection.xIdentifierIndexes[identifier] =
          ItemIndexes(source: index, arranged: -1)

proc add*[T](collection: var ItemCollection[T], item: T) =
  collection.items.add item
  collection.indexInsertedItem(collection.items.high)
  collection.invalidate()

proc insert*[T](collection: var ItemCollection[T], item: T, index: int): int =
  result = max(0, min(index, collection.len))
  collection.items.insert(item, result)
  if collection.xSourceIndexesValid and result < collection.items.high:
    for indexes in collection.xIdentifierIndexes.mvalues:
      if indexes.source >= result:
        inc indexes.source
  collection.indexInsertedItem(result)
  collection.invalidate()

proc delete*[T](collection: var ItemCollection[T], index: int) =
  if collection.xSourceIndexesValid:
    let identifier {.cursor.} = collection.items[index].identifier
    var removeIdentifier = false
    collection.xIdentifierIndexes.withValue(identifier, indexes):
      if indexes.source == index:
        indexes.source = -1
        for candidate in index + 1 ..< collection.len:
          if collection.items[candidate].identifier == identifier:
            indexes.source = candidate
            break
        removeIdentifier = indexes.source < 0
    if removeIdentifier:
      collection.xIdentifierIndexes.del(identifier)
    if index < collection.items.high:
      for indexes in collection.xIdentifierIndexes.mvalues:
        if indexes.source > index:
          dec indexes.source
  else:
    # Partial entries have no source positions to shift. Remove the deleted
    # identity so cache keys remain bounded by the current source items.
    collection.xIdentifierIndexes.del(collection.items[index].identifier)
  collection.items.delete(index)
  collection.invalidate()

proc moveItem*[T](collection: var ItemCollection[T], index, toIndex: int): int =
  let item = move collection.items[index]
  collection.items.delete(index)
  result = max(0, min(toIndex, collection.len))
  collection.items.insert(item, result)
  if collection.xSourceIndexesValid:
    for indexes in collection.xIdentifierIndexes.mvalues:
      if indexes.source == index:
        indexes.source = result
      elif index < indexes.source and indexes.source <= result:
        dec indexes.source
      elif result <= indexes.source and indexes.source < index:
        inc indexes.source
    let identifier {.cursor.} = collection.items[result].identifier
    collection.xIdentifierIndexes.withValue(identifier, indexes):
      # Moving one occurrence can change which duplicate is first.
      indexes.source = result
      for candidate in 0 ..< result:
        if collection.items[candidate].identifier == identifier:
          indexes.source = candidate
          break
  collection.invalidate()

proc `[]=`*[T](
    collection: var ItemCollection[T], sourceIndex: int, key: string, value: ObjectValue
) =
  ## Updates a source item's field and invalidates the arrangement.
  mixin setValue
  collection.items[sourceIndex].setValue(key, value)
  collection.invalidate()

proc compareObjectValues*(left, right: ObjectValue, compareIntToFloat = true): int =
  case left.kind
  of ovInt:
    if right.kind == ovInt:
      return cmp(left.intValue, right.intValue)
    if compareIntToFloat and right.kind == ovFloat:
      return cmp(left.intValue.float, right.floatValue)
  of ovFloat:
    if right.kind == ovFloat:
      return cmp(left.floatValue, right.floatValue)
    if right.kind == ovInt:
      return cmp(left.floatValue, right.intValue.float)
  of ovString:
    if right.kind == ovString:
      return cmp(left.text, right.text)
  of ovBool:
    if right.kind == ovBool:
      return cmp(left.boolValue, right.boolValue)
  else:
    discard
  cmp(left.formatObjectValue(), right.formatObjectValue())
