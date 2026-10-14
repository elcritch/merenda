## Internal adapters from neutral item sources to existing widget selectors.

import std/options
import sigils/core
import sigils/selectors
import ../itemproviders
import ../types
import ../../drawing/images

proc installItemProvider*(
    source: DynamicAgent, implementation: ProtocolImplementation
) =
  ## Add only missing legacy methods so per-view overrides retain precedence.
  if not source.localMethod(numberOfProvidedItems()).isNil:
    if source.localMethod(providedItemAtIndex()).isNil:
      raise newException(
        ProtocolConformanceError,
        "item providers require a local providedItemAtIndex implementation",
      )
    discard source.adopt(ItemProviderProtocol)
    var missing: seq[SelectorMethod]
    for binding in implementation.methods:
      if source.localMethod(binding.selector).isNil:
        missing.add binding
    discard source.addMethods(missing)

template defineItemProviderBridge*(
    Name, Parent, Widget, Payload, Count, Item, Index, widgetArg, project, findIndex:
      untyped
) =
  protocol Name of Parent:
    method Count(source: DynamicAgent, widgetArg: Widget): int =
      source.trySendLocal(numberOfProvidedItems(), DynamicAgent(widgetArg)).get()

    method Item(source: DynamicAgent, widgetArg: Widget, index: int): Payload =
      let item = source
        .trySendLocal(
          providedItemAtIndex(), (context: DynamicAgent(widgetArg), index: index)
        )
        .get()
      project(source, widgetArg, item)

    method Index(source: DynamicAgent, widgetArg: Widget, identifier: string): int =
      findIndex(source, widgetArg, identifier)

proc projectedProviderIndex*[T](
    source, context: DynamicAgent,
    identifier: string,
    project: proc(item: ModelItem): T {.closure.},
): int =
  if identifier.len == 0:
    return -1
  var visible = 0
  let count = source.trySendLocal(numberOfProvidedItems(), context).get()
  for index in 0 ..< count:
    let item =
      source.trySendLocal(providedItemAtIndex(), (context: context, index: index)).get()
    let model = project(item)
    if not model.hidden:
      if model.identifier == identifier:
        return visible
      inc visible
  -1

proc modelBoolField*(item: ModelItem, key: string, fallback: bool): bool =
  let value = item.getValue(key)
  if value.isSome and value.get().kind == ovBool:
    value.get().boolValue
  else:
    fallback

proc modelStringField*(item: ModelItem, key: string): string =
  let value = item.getValue(key)
  if value.isSome and value.get().kind == ovString:
    value.get().text
  else:
    ""

proc modelIntField*(item: ModelItem, key: string, fallback: int): int =
  let value = item.getValue(key)
  if value.isSome and value.get().kind == ovInt:
    value.get().intValue
  else:
    fallback

proc modelColorField*(item: ModelItem, key: string, fallback: Color): Color =
  let value = item.getValue(key)
  if value.isSome and value.get().kind == ovColor:
    value.get().colorValue
  else:
    fallback

proc modelImageField*(item: ModelItem, key: string): ImageResource =
  let value = item.getValue(key)
  if value.isSome and value.get().kind == ovImage:
    value.get().imageValue.resource
  else:
    nil
