import std/[tables, unittest]

import pkg/pixie
import sigils/core

import merenda/nimkit

type
  TypedPasteboardProvider = ref object of DynamicAgent
    types: seq[string]
    items: Table[string, PasteboardItem]
    changeCount: int
    clearCount: int
    releaseCount: int

  PromisedFileSource = ref object of DynamicAgent
    fileNames: seq[string]

  DropDestination = ref object of DynamicAgent
    concluded: int

  ListDropDelegate = ref object of Responder
    proposedRow: int

  TableDropDelegate = ref object of Responder
    proposedKind: DraggingDropTargetKind
    proposedColumn: string

  OutlineDropDelegate = ref object of Responder
    identifier: string

proc testImage(width, height: int): Image =
  result = newImage(width, height)
  result.fill(rgba(32, 96, 180, 255))

proc addType(provider: TypedPasteboardProvider, kind: string) =
  if kind.len > 0 and kind notin provider.types:
    provider.types.add kind

protocol TypedPasteboardProviderProtocol of PasteboardProviderProtocol:
  method pasteboardTypes(
      provider: TypedPasteboardProvider, pasteboard: Pasteboard
  ): seq[string] =
    provider.types

  method pasteboardChangeCount(
      provider: TypedPasteboardProvider, pasteboard: Pasteboard
  ): int =
    provider.changeCount

  method pasteboardItemForType(
      provider: TypedPasteboardProvider, request: PasteboardTypeRequest
  ): PasteboardItem =
    if request.kind in provider.items:
      return provider.items[request.kind].copyPasteboardItem()
    PasteboardItem(kind: pikNone)

  method setPasteboardItemForType(
      provider: TypedPasteboardProvider, request: PasteboardItemRequest
  ): bool =
    if request.kind.len == 0 or request.item.kind == pikNone:
      return false
    provider.addType(request.kind)
    provider.items[request.kind] = request.item.copyPasteboardItem()
    inc provider.changeCount
    true

  method clearPasteboardContents(
      provider: TypedPasteboardProvider, pasteboard: Pasteboard
  ): bool =
    provider.types.setLen(0)
    provider.items.clear()
    inc provider.clearCount
    inc provider.changeCount
    true

  method releasePasteboard(
      provider: TypedPasteboardProvider, pasteboard: Pasteboard
  ): bool =
    provider.types.setLen(0)
    provider.items.clear()
    inc provider.releaseCount
    inc provider.changeCount
    true

protocol PromisedFileSourceProtocol of DraggingSourceProtocol:
  method writePromisedFile(
      source: PromisedFileSource, request: DraggingPromisedFileRequest
  ): bool =
    source.fileNames.add request.fileName
    request.item.pasteboardType == PasteboardTypePromisedFile

protocol DropDestinationProtocol of DraggingDestinationProtocol:
  method performDragOperation(destination: DropDestination, info: DraggingInfo): bool =
    true

  method concludeDragOperation(destination: DropDestination, info: DraggingInfo) =
    inc destination.concluded

protocol ListDropDelegateProtocol of ListViewDelegate:
  method listDropTargetForLocation(
      delegate: ListDropDelegate,
      listView: ListView,
      location: Point,
      proposedTarget: DraggingDropTarget,
  ): DraggingDropTarget =
    delegate.proposedRow = proposedTarget.row
    initItemDropTarget("list:" & $proposedTarget.row, proposedTarget.row)

protocol TableDropDelegateProtocol of TableViewDelegate:
  method tableDropTargetForLocation(
      delegate: TableDropDelegate,
      tableView: TableView,
      location: Point,
      proposedTarget: DraggingDropTarget,
  ): DraggingDropTarget =
    delegate.proposedKind = proposedTarget.kind
    delegate.proposedColumn = proposedTarget.column
    initCellDropTarget(proposedTarget.row, "override", proposedTarget.rect)

protocol OutlineDropDelegateProtocol of OutlineViewDelegate:
  method dropTargetForOutlineItem(
      delegate: OutlineDropDelegate,
      outlineView: OutlineView,
      identifier: string,
      row: int,
      proposedTarget: DraggingDropTarget,
  ): DraggingDropTarget =
    delegate.identifier = identifier
    initItemDropTarget(identifier & ":child", row, proposedTarget.rect)

proc newTypedPasteboardProvider(): TypedPasteboardProvider =
  result = TypedPasteboardProvider()
  result.items = initTable[string, PasteboardItem]()
  discard result.withProtocol(TypedPasteboardProviderProtocol)

proc newPromisedFileSource(): PromisedFileSource =
  result = PromisedFileSource()
  discard result.withProtocol(PromisedFileSourceProtocol)

proc newDropDestination(): DropDestination =
  result = DropDestination()
  discard result.withProtocol(DropDestinationProtocol)

proc newListDropDelegate(): ListDropDelegate =
  result = ListDropDelegate(proposedRow: -1)
  discard result.withProtocol(ListDropDelegateProtocol)

proc newTableDropDelegate(): TableDropDelegate =
  result = TableDropDelegate()
  discard result.withProtocol(TableDropDelegateProtocol)

proc newOutlineDropDelegate(): OutlineDropDelegate =
  result = OutlineDropDelegate()
  discard result.withProtocol(OutlineDropDelegateProtocol)

suite "nimkit pasteboards and dragging":
  test "pasteboard providers round trip typed items and expose change counts":
    let
      provider = newTypedPasteboardProvider()
      writer = newPasteboard("typed-writer")
      reader = newPasteboard("typed-reader")
      font = initPasteboardFontDescriptor("Menlo", "Menlo", 13.0, ["monospace"])
      color = initColor(0.2, 0.4, 0.7, 1.0)
      image = newImageResource(testImage(3, 2), name = "provider-image")

    writer.provider = provider
    reader.provider = provider

    check writer.setData(PasteboardTypeData, "blob")
    check writer.setUrl(PasteboardTypeUrl, "https://example.com")
    check writer.setFile(PasteboardTypeFile, "/tmp/report.txt")
    check writer.setColor(PasteboardTypeColor, color)
    check writer.setFont(PasteboardTypeFont, font)
    check writer.setImage(PasteboardTypeImage, image)

    check writer.changeCount == provider.changeCount
    check reader.availableTypeFromArray([PasteboardTypeImage, PasteboardTypeData]) ==
      PasteboardTypeImage
    check reader.dataForType(PasteboardTypeData) == "blob"
    check reader.urlForType(PasteboardTypeUrl) == "https://example.com"
    check reader.fileForType(PasteboardTypeFile) == "/tmp/report.txt"
    check reader.colorForType(PasteboardTypeColor) == color
    check reader.fontForType(PasteboardTypeFont).name == "Menlo"
    check reader.imageForType(PasteboardTypeImage).size == initSize(3, 2)

    check writer.releaseGlobally()
    check provider.releaseCount == 1
    check provider.clearCount == 0

  test "promised file drag sessions call sources after accepted drops":
    let
      source = newPromisedFileSource()
      destination = newDropDestination()
      pasteboard = pasteboardWithUniqueName()
      session = beginDraggingSession(
        DynamicAgent(source),
        [initPromisedFileDraggingItem("report.txt")],
        {dgoCopy},
        pasteboard.pasteboardName(),
      )

    check session.performDraggingOperation(DynamicAgent(destination))
    check source.fileNames == @["report.txt"]
    check destination.concluded == 1

  test "promised file drags keep an in-process pasteboard fallback":
    let
      destination = newDropDestination()
      pasteboard = pasteboardWithUniqueName()
      session = beginDraggingSession(
        nil,
        [initPromisedFileDraggingItem("fallback.txt")],
        {dgoCopy},
        pasteboard.pasteboardName(),
      )

    check session.performDraggingOperation(DynamicAgent(destination))
    let item = session.pasteboard().itemForType(PasteboardTypePromisedFile)
    check item.kind == pikFile
    check item.filePath == "fallback.txt"

  test "list table and outline delegates can refine drop targets":
    let
      listView = newListView(frame = initRect(0, 0, 120, 80))
      listDelegate = newListDropDelegate()

    listView.items = ["one", "two"]
    listView.delegate = listDelegate
    let listTarget = listView.dropTargetForDraggingLocation(initPoint(4, 4))
    check listDelegate.proposedRow == 0
    check listTarget.kind == ddtItem
    check listTarget.itemIdentifier == "list:0"

    let
      tableView = newTableView(frame = initRect(0, 0, 180, 80))
      tableDelegate = newTableDropDelegate()
      nameColumn = newTableColumn("name", "Name", width = 90.0)

    tableView.rowCount = 2
    tableView.addColumn(nameColumn)
    tableView.delegate = tableDelegate
    let
      tableRowRect = tableView.listItemRect(0)
      tableTarget = tableView.dropTargetForDraggingLocation(
        initPoint(tableRowRect.origin.x + 8.0'f32, tableRowRect.origin.y + 4.0'f32)
      )
    check tableDelegate.proposedKind == ddtCell
    check tableDelegate.proposedColumn == "name"
    check tableTarget.column == "override"

    let
      outlineView = newOutlineView(frame = initRect(0, 0, 180, 80))
      outlineDelegate = newOutlineDropDelegate()

    outlineView.outlineItems = [initOutlineItem("root", "Root")]
    outlineView.outlineDelegate = outlineDelegate
    let
      outlineRowRect = TableView(outlineView).listItemRect(0)
      outlineTarget = outlineView.dropTargetForDraggingLocation(
        initPoint(outlineRowRect.origin.x + 8.0'f32, outlineRowRect.origin.y + 4.0'f32)
      )
    check outlineDelegate.identifier == "root"
    check outlineTarget.kind == ddtItem
    check outlineTarget.itemIdentifier == "root:child"
