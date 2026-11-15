## Editable, virtualized DirectView rows with stable model identifiers.
import merenda/nimkit
import merenda/nimkit/directviews

proc rowTitle(controller: ArrayController, id: string): string =
  controller.valueForItem(id, "title").requireString()

proc editRowTitle(controller: ArrayController, id, value: string) =
  controller.setValue(id, "title", toObj(value))

proc buildCollectionRow(
    row: DirectView, controller: ArrayController, id: string, cache: bool
) =
  row.viewBody:
    HStack:
      this.spacing = 8
      Label:
        when defined(merendaIntrinsicCache):
          this{vpCacheIntrinsicSize} = cache
        this.stringValue = "#" & id
      TextField:
        when defined(merendaIntrinsicCache):
          this{vpCacheIntrinsicSize} = cache
        arrangedSizing(svspFillAvailableWidth)
        bindingScope.bindTextField(
          "title", controller, arrayControllerDidChange, id, rowTitle, this,
          editRowTitle,
        )
      Button("Remove", acceptsFirstResponder = false):
        when defined(merendaIntrinsicCache):
          this{vpCacheIntrinsicSize} = cache
        onAction(controller, id) do(
          receiver: ArrayController, key: string, sender: DynamicAgent
        ):
          discard receiver.removeItem(key)

proc newDirectCollectionDemo*(
    count = 5000, cache = true
): tuple[view: CollectionView, rows: CollectionRows] =
  var items: seq[ModelItem]
  for i in 0 ..< count:
    items.add modelItem($i, fields = [modelField("title", toObj("Task " & $i))])
  let controller = newArrayController(items)
  let collection = newCollectionView(frame = rect(0, 0, 640, 480))
  collection.collectionLayout = newCollectionViewLayout(
    clkList,
    itemSize = initSize(620, 40),
    minimumLineSpacing = 2,
    edgeInsets = insets(4),
  )
  let rows = newCollectionRows(
    collection,
    controller,
    proc(row: DirectView, controller: ArrayController, id: string) =
      buildCollectionRow(row, controller, id, cache),
  )
  (collection, rows)

when isMainModule:
  let demo = newDirectCollectionDemo()
  sharedApplication().runWindow(
    newWindow("Editable virtualized rows", frame = rect(100, 100, 640, 480)), demo.view
  )
  demo.rows.close()
