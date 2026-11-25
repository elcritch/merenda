## Editable, virtualized DirectView rows with stable model identifiers.
import merenda/nimkit
import merenda/nimkit/directviews

proc rowTitle(controller: ArrayController, id: string): string =
  controller.valueForItem(id, "title").requireString()

proc editRowTitle(controller: ArrayController, id, value: string) =
  controller.setValue(id, "title", toObj(value))

proc buildCollectionRow*(row: DirectView, controller: ArrayController, id: string) =
  row.viewBody:
    HStack:
      this.spacing = 8
      Label:
        this.stringValue = "#" & id
      TextField:
        this.arrangedSizing = svspFillAvailableWidth
        this.bindTextField(
          "title", controller, arrayControllerDidChange, id, rowTitle, editRowTitle
        )
      Button("Remove", focusable = false):
        this.onAction(controller, id) do(
          this: Button, receiver: ArrayController, key: string
        ):
          discard receiver.removeItem(key)

proc newDirectCollectionDemo*(
    count = 5000, rowBuilder: CollectionRowBuilder = nil
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
  var builder = rowBuilder
  if builder.isNil:
    builder = buildCollectionRow
  let rows = newCollectionRows(collection, controller, builder)
  (collection, rows)

when isMainModule:
  let demo = newDirectCollectionDemo()
  sharedApplication().runWindow(
    newWindow("Editable virtualized rows", frame = rect(100, 100, 640, 480)), demo.view
  )
  demo.rows.close()
