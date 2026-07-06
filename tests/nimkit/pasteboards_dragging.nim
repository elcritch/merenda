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

  DragTableSource = ref object of Responder
    items: seq[string]

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

protocol DragTableSourceMethods of TableViewDataSource:
  method numberOfRows(source: DragTableSource, tableView: TableView): int =
    source.items.len

  method textForCell(
      source: DragTableSource, tableView: TableView, row: int, column: TableColumn
  ): string =
    if row < 0 or row >= source.items.len:
      ""
    else:
      source.items[row]

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

proc replaceProviderItem(
    provider: TypedPasteboardProvider, kind: string, item: PasteboardItem
) =
  provider.types.setLen(0)
  provider.items.clear()
  provider.addType(kind)
  provider.items[kind] = item.copyPasteboardItem()
  inc provider.changeCount

proc newPromisedFileSource(): PromisedFileSource =
  result = PromisedFileSource()
  discard result.withProtocol(PromisedFileSourceProtocol)

proc newDragTableSource(values: openArray[string]): DragTableSource =
  result = DragTableSource(items: @values)
  initResponder(result)
  discard result.withProtocol(DragTableSourceMethods)

proc newDropDestination(): DropDestination =
  result = DropDestination()
  discard result.withProtocol(DropDestinationProtocol)

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
      color = color(0.2, 0.4, 0.7, 1.0)
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

  test "pasteboard reads invalidate provider cache after change counts move":
    let
      provider = newTypedPasteboardProvider()
      pasteboard = newPasteboard("provider-cache")

    pasteboard.provider = provider
    provider.replaceProviderItem(
      PasteboardTypeString, initPasteboardStringItem("first")
    )

    check pasteboard.types() == @[PasteboardTypeString]
    check pasteboard.stringForType(PasteboardTypeString) == "first"

    provider.replaceProviderItem(
      PasteboardTypeString, initPasteboardStringItem("second")
    )
    check pasteboard.stringForType(PasteboardTypeString) == "second"

    provider.replaceProviderItem(PasteboardTypeData, initPasteboardDataItem("blob"))
    check pasteboard.availableTypeFromArray([PasteboardTypeString, PasteboardTypeData]) ==
      PasteboardTypeData
    check PasteboardTypeString notin pasteboard.types()
    check pasteboard.dataForType(PasteboardTypeData) == "blob"

  test "provider assignment discards stale local pasteboard cache":
    let
      provider = newTypedPasteboardProvider()
      pasteboard = newPasteboard("provider-assignment-cache")

    check pasteboard.setString(PasteboardTypeString, "local")
    provider.replaceProviderItem(PasteboardTypeData, initPasteboardDataItem("provider"))

    pasteboard.provider = provider

    check pasteboard.stringForType(PasteboardTypeString) == ""
    check pasteboard.availableTypeFromArray([PasteboardTypeString, PasteboardTypeData]) ==
      PasteboardTypeData
    check pasteboard.dataForType(PasteboardTypeData) == "provider"
    check PasteboardTypeString notin pasteboard.types()

  test "text transfer contracts map to pasteboard payloads":
    let contracts = pasteboardTextContracts()

    check contracts.len == 7
    check pasteboardTypeForTextFormat(ttfPlainText) == PasteboardTypePlainText
    check pasteboardTypeForTextFormat(ttfAttributedText) == PasteboardTypeAttributedText
    check pasteboardTextContract(ttfRTF).pasteboardType == PasteboardTypeRTF
    check pasteboardTextContract(ttfRTFD).allowsAttachments
    check textTransferContract(ttfHTML).preservesAttributes

  test "pasteboards store text interchange formats without platform objects":
    let pasteboard = newPasteboard("text-transfer")
    var attributes = defaultTextAttributes(color(0.1, 0.2, 0.3), 14.0)
    attributes.link = "https://example.com"
    attributes.underlineStyle = tldsSingle
    let attributed = newAttributedString("link", attributes)

    check pasteboard.setPlainText("plain")
    check pasteboard.setAttributedString(attributed)
    check pasteboard.setRtfData("{\\rtf1 link}")
    check pasteboard.setRtfdData("rtfd-package-bytes")
    check pasteboard.setHtml("<a href=\"https://example.com\">link</a>")
    check pasteboard.setUrl(PasteboardTypeUrl, "https://example.com")
    check pasteboard.setFile(PasteboardTypeFilePromise, "export.txt")

    check pasteboard.plainText == "plain"
    check pasteboard.attributedString().stringValue == "link"
    check pasteboard.attributedString().attributesAtIndex(0).link ==
      "https://example.com"
    check pasteboard.rtfData == "{\\rtf1 link}"
    check pasteboard.rtfdData == "rtfd-package-bytes"
    check pasteboard.html == "<a href=\"https://example.com\">link</a>"
    check pasteboard.urlForType(PasteboardTypeUrl) == "https://example.com"
    check pasteboard.fileForType(PasteboardTypeFilePromise) == "export.txt"

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

  test "table and outline delegates can refine drop targets":
    let
      tableSource = newDragTableSource(["one", "two"])
      tableView = newTableView(frame = rect(0, 0, 120, 80))
      tableDelegate = newTableDropDelegate()
      nameColumn = newTableColumn("value", "Value", width = 120.0)

    tableView.showsHeader = false
    tableView.rowCount = 2
    tableView.addColumn(nameColumn)
    tableView.dataSource = tableSource
    tableView.delegate = tableDelegate

    let
      tableRowRect = tableView.rowItemRect(0)
      tableTarget = tableView.dropTargetForDraggingLocation(
        initPoint(tableRowRect.origin.x + 8.0'f32, tableRowRect.origin.y + 4.0'f32)
      )
    check tableDelegate.proposedKind == ddtCell
    check tableDelegate.proposedColumn == "value"
    check tableTarget.column == "override"

    let
      outlineView = newOutlineView(frame = rect(0, 0, 180, 80))
      outlineDelegate = newOutlineDropDelegate()

    outlineView.outlineItems = [initOutlineItem("root", "Root")]
    outlineView.outlineDelegate = outlineDelegate
    let
      outlineRowRect = TableView(outlineView).rowItemRect(0)
      outlineTarget = outlineView.dropTargetForDraggingLocation(
        initPoint(outlineRowRect.origin.x + 8.0'f32, outlineRowRect.origin.y + 4.0'f32)
      )
    check outlineDelegate.identifier == "root"
    check outlineTarget.kind == ddtItem
    check outlineTarget.itemIdentifier == "root:child"
