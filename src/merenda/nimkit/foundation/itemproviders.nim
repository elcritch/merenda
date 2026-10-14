## Typed item records and the view-independent provider contract.
## Required provider methods are installed locally. Indexes refer to the provider's
## arranged, non-hidden records. Presenters receive their own identity as context;
## sources retain responsibility for invalidation and explicit presenter reloads.

import std/options
import sigils/core
import sigils/selectors
import ./objectvalues

export objectvalues

type
  ModelControllerError* = object of KeyError
  ModelSortDirection* = enum
    msdAscending
    msdDescending

  ModelField* = object
    key*: string
    value*: ObjectValue

  ModelItem* = object
    identifier*: string
    title*: string
    objectValue*: ObjectValue
    fields*: seq[ModelField]
    enabled*: bool
    hidden*: bool
    separator*: bool
    representedObject*: DynamicAgent

  ModelColumn* = object
    identifier*: string
    title*: string
    valueKey*: string
    width*: float32

  ModelSortDescriptor* = object
    key*: string
    direction*: ModelSortDirection

  ModelFilter* = proc(item: ModelItem): bool {.closure.}

  ModelTreeItem* = object
    item*: ModelItem
    parentIdentifier*: string
    leaf*: bool

func modelField*(key: string, value: ObjectValue): ModelField =
  ModelField(key: key, value: value)

func modelColumn*(
    identifier: string, title = "", valueKey = "", width = 120.0'f32
): ModelColumn =
  ModelColumn(identifier: identifier, title: title, valueKey: valueKey, width: width)

func initModelSortDescriptor*(
    key: string, direction = msdAscending
): ModelSortDescriptor =
  ModelSortDescriptor(key: key, direction: direction)

proc modelItem*(
    identifier = "",
    title = "",
    objectValue = emptyObjectValue(),
    fields: openArray[ModelField] = [],
    enabled = true,
    hidden = false,
    separator = false,
    representedObject: DynamicAgent = nil,
): ModelItem =
  ModelItem(
    identifier: identifier,
    title: title,
    objectValue: objectValue,
    fields: @fields,
    enabled: enabled,
    hidden: hidden,
    separator: separator,
    representedObject: representedObject,
  )

proc modelTreeItem*(
    item: ModelItem, parentIdentifier = "", leaf = false
): ModelTreeItem =
  ModelTreeItem(item: item, parentIdentifier: parentIdentifier, leaf: leaf)

proc findFieldIndex(item: ModelItem, key: string): int =
  for index, field in item.fields:
    if field.key == key:
      return index
  -1

proc hasValue*(item: ModelItem, key: string): bool =
  key.len == 0 or item.findFieldIndex(key) >= 0

proc getValue*(item: ModelItem, key: string): Option[ObjectValue] =
  if key.len == 0:
    return some(item.objectValue)
  let index = item.findFieldIndex(key)
  if index >= 0:
    some(item.fields[index].value)
  else:
    none(ObjectValue)

proc value*(item: ModelItem, key = ""): ObjectValue {.raises: [ModelControllerError].} =
  let found = item.getValue(key)
  if found.isSome:
    return found.get()
  raise newException(ModelControllerError, "unknown model value key: " & key)

proc `[]`*(item: ModelItem, key: string): ObjectValue =
  item.value(key)

proc setValue*(item: var ModelItem, key: string, value: ObjectValue) =
  if key.len == 0:
    item.objectValue = value
    return
  let index = item.findFieldIndex(key)
  if index >= 0:
    item.fields[index].value = value
  else:
    item.fields.add modelField(key, value)

proc `[]=`*(item: var ModelItem, key: string, value: ObjectValue) =
  item.setValue(key, value)

proc displayTitle*(item: ModelItem, role = ovrLabel): string =
  if item.title.len > 0:
    item.title
  else:
    item.objectValue.formatObjectValue(initObjectFormatContext(role = role))

protocol ItemProviderProtocol {.selectorScope: protocol.}:
  method numberOfProvidedItems*(context: DynamicAgent): int
  method providedItemAtIndex*(context: DynamicAgent, index: int): ModelItem
  method providedItemIndexForIdentifier*(
    context: DynamicAgent, identifier: string
  ): int {.optional.}

  method providedItemValue*(
    context: DynamicAgent, index: int, key: string
  ): ObjectValue {.optional.}

  method setProvidedItemValue*(
    context: DynamicAgent, index: int, key: string, value: ObjectValue
  ): bool {.optional.}

  method providedItemSelection*(context: DynamicAgent): seq[string] {.optional.}

type ItemSelection* = object
  identifiers*: seq[string]
  preserveEmpty*: bool

protocol ItemSelectionSourceProtocol {.selectorScope: protocol.}:
  method itemSelection*(): ItemSelection

proc providedIndex*(source, context: DynamicAgent, identifier: string): int =
  let found = source.trySendLocal(
    providedItemIndexForIdentifier(), (context: context, identifier: identifier)
  )
  if found.isSome:
    return found.get()
  for index in 0 ..< source.trySendLocal(numberOfProvidedItems(), context).get():
    if source
    .trySendLocal(providedItemAtIndex(), (context: context, index: index))
    .get().identifier == identifier:
      return index
  -1

proc providedValue*(
    source, context: DynamicAgent, index: int, key: string
): ObjectValue =
  let value =
    source.trySendLocal(providedItemValue(), (context: context, index: index, key: key))
  if value.isSome:
    return value.get()
  let item =
    source.trySendLocal(providedItemAtIndex(), (context: context, index: index)).get()
  item.getValue(key).get(item.objectValue)
