## Shared value-state storage for model-backed collections. Views and controllers
## retain their public model types, sort policies, and notification boundaries.

import std/[algorithm, options, tables]

import ../objectvalues

type ItemCollection*[T] = object
  items*: seq[T]
  xSourceIndexes: Table[string, int]
  arrangedIndexes*: seq[int]
  xArrangedIdentifierIndexes: Table[string, int]
  xSourceIndexesValid: bool
  arrangementValid*: bool
  xIndexesEmptyIdentifiers: bool
  revision*: Natural

proc itemColumnIdentifier*[T](column: T): string =
  if column.identifier.len > 0: column.identifier else: column.valueKey

proc itemColumnTitle*[T](column: T): string =
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
  if sourceChanged or arrangementChanged:
    collection.arrangementValid = false
  inc collection.revision

proc replaceItems*[T](collection: var ItemCollection[T], items: openArray[T]) =
  collection.items = @items
  collection.invalidate(sourceChanged = true)

proc sourceIndexOfIdentifier*[T](
    collection: var ItemCollection[T], identifier: string
): int =
  if identifier.len == 0 and not collection.xIndexesEmptyIdentifiers:
    return -1
  if not collection.xSourceIndexesValid:
    collection.xSourceIndexes.clear()
    for index, item in collection.items:
      if (item.identifier.len > 0 or collection.xIndexesEmptyIdentifiers) and
          item.identifier notin collection.xSourceIndexes:
        collection.xSourceIndexes[item.identifier] = index
    collection.xSourceIndexesValid = true
  collection.xSourceIndexes.getOrDefault(identifier, -1)

proc getItemWithIdentifier*[T](
    collection: var ItemCollection[T], identifier: string
): Option[T] =
  let index = collection.sourceIndexOfIdentifier(identifier)
  if index >= 0:
    some(collection.items[index])
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
  var indexes: seq[int]
  for index, item in collection.items:
    if not item.hidden and (filter.isNil or filter(item)):
      indexes.add index
  if not compare.isNil:
    indexes.sort(compare)
  var identifiers: Table[string, int]
  for arrangedIndex, sourceIndex in indexes:
    let identifier = collection.items[sourceIndex].identifier
    if (identifier.len > 0 or collection.xIndexesEmptyIdentifiers) and
        identifier notin identifiers:
      identifiers[identifier] = arrangedIndex
  collection.arrangedIndexes = move indexes
  collection.xArrangedIdentifierIndexes = move identifiers
  collection.arrangementValid = true

proc arrangedSourceIndex*[T](collection: ItemCollection[T], index: int): int =
  if index in 0 ..< collection.arrangedIndexes.len:
    collection.arrangedIndexes[index]
  else:
    -1

proc arrangedIndexOfIdentifier*[T](
    collection: ItemCollection[T], identifier: string
): int =
  collection.xArrangedIdentifierIndexes.getOrDefault(identifier, -1)

proc add*[T](collection: var ItemCollection[T], item: T) =
  collection.items.add item
  collection.invalidate(sourceChanged = true)

proc insert*[T](collection: var ItemCollection[T], item: T, index: int): int =
  result = max(0, min(index, collection.items.len))
  collection.items.insert(item, result)
  collection.invalidate(sourceChanged = true)

proc delete*[T](collection: var ItemCollection[T], index: int) =
  collection.items.delete(index)
  collection.invalidate(sourceChanged = true)

proc moveItem*[T](collection: var ItemCollection[T], index, toIndex: int): int =
  let item = collection.items[index]
  collection.items.delete(index)
  result = max(0, min(toIndex, collection.items.len))
  collection.items.insert(item, result)
  collection.invalidate(sourceChanged = true)

proc setValue*[T](
    collection: var ItemCollection[T], index: int, key: string, value: ObjectValue
) =
  mixin setValue
  collection.items[index].setValue(key, value)
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
