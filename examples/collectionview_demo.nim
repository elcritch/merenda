import merenda/nimkit

type CollectionViewDemo* = ref object
  app*: Application
  window*: Window
  root*: View
  collectionView*: CollectionView
  controller*: ArrayController
  status*: Label

proc demoItems(): seq[ModelItem] =
  @[
    modelItem(
      "assets",
      title = "Assets",
      objectValue = toObj("Assets"),
      fields = [modelField("kind", toObj("Folder"))],
    ),
    modelItem(
      "timeline",
      title = "Timeline",
      objectValue = toObj("Timeline"),
      fields = [modelField("kind", toObj("Panel"))],
    ),
    modelItem(
      "renderer",
      title = "Renderer",
      objectValue = toObj("Renderer"),
      fields = [modelField("kind", toObj("Job"))],
    ),
    modelItem(
      "notes",
      title = "Notes",
      objectValue = toObj("Notes"),
      fields = [modelField("kind", toObj("Document"))],
    ),
    modelItem(
      "exports",
      title = "Exports",
      objectValue = toObj("Exports"),
      fields = [modelField("kind", toObj("Folder"))],
    ),
  ]

proc updateStatus(demo: CollectionViewDemo) =
  let identifier = demo.collectionView.selectedIdentifier()
  if identifier.len == 0:
    demo.status.text = "No item selected"
    return
  let item = demo.controller.itemWithIdentifier(identifier)
  demo.status.text =
    "Selected: " & item.displayTitle() & " (" & item.value("kind").requireString() & ")"

proc newCollectionViewDemo*(app = newApplication()): CollectionViewDemo =
  result = CollectionViewDemo(app: app)
  result.window = newWindow("NimKit Collection View", frame = rect(140, 140, 520, 340))
  result.root = newView(frame = rect(0, 0, 520, 340))
  result.status = newStatusLabel("No item selected", frame = rect(24, 294, 460, 22))
  result.controller = newArrayController(demoItems())
  result.collectionView = newCollectionView(frame = rect(24, 64, 470, 210))
  result.collectionView.collectionLayout = newCollectionViewLayout(
    clkWrapped,
    itemSize = initSize(120.0, 64.0),
    minimumInteritemSpacing = 10.0,
    minimumLineSpacing = 10.0,
    edgeInsets = insets(12.0),
  )
  bindCollectionView(result.collectionView, result.controller)

  let action = actionSelector("collectionViewSelectionChanged")
  let demo = result
  let target = newActionTarget(action) do(sender: DynamicAgent):
    discard sender
    demo.updateStatus()
  result.collectionView.target = target
  result.collectionView.action = action

  result.root.addSubview(
    newTitleLabel("Collection View", frame = rect(24, 20, 300, 28))
  )
  result.root.addSubview(result.collectionView)
  result.root.addSubview(result.status)
  result.window.setContentView(result.root)

proc showCollectionViewDemo*(demo: CollectionViewDemo) =
  if demo.isNil:
    return
  discard demo.app.showWindow(demo.window, demo.root)

when isMainModule:
  let demo = newCollectionViewDemo(sharedApplication())
  demo.app.runWindow(demo.window, demo.root)
