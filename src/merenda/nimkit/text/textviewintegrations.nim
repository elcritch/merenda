import ../app/application
import ../app/documentcontrollers
import ../app/documents
import ../app/dragging
import ../app/panels
import ../app/pasteboards
import ../controls/menus
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../view/views
import ./texteditors
import ./textviews

export documentcontrollers
export documents
export menus
export texteditors
export textviews

type TextContextMenuRequest* = object
  point*: Point
  characterIndex*: int
  link*: string
  attachment*: TextAttachment
  selectionRange*: TextRange

proc textContextMenuRequest*(
    textView: TextView, point = AutoPoint
): TextContextMenuRequest =
  if textView.isNil:
    return
  let index =
    if point.hasAutoMetric:
      int(textView.selectedRange().location)
    else:
      textView.textIndexAtPoint(point)
  let
    link = textView.linkAtIndex(index)
    attachment = textView.attachmentAtIndex(index)
  TextContextMenuRequest(
    point: point,
    characterIndex: index,
    link: link.link,
    attachment: attachment.attachment,
    selectionRange: textView.selectedRange(),
  )

proc contextualMenuForText*(textView: TextView, point = AutoPoint): Menu =
  result = newMenu("Text")
  if textView.isNil:
    return
  let request = textView.textContextMenuRequest(point)
  if request.link.len > 0:
    let link = textView.linkAtIndex(request.characterIndex)
    textView.selectedRange = link.range
    let item = result.addItem("Open Link", openLink())
    item.target = DynamicAgent(textView)
    result.addSeparator()
  discard result.addItem("Cut", actionSelector("cut"))
  discard result.addItem("Copy", actionSelector("copy"))
  discard result.addItem("Paste", actionSelector("paste"))
  result.addSeparator()
  discard result.addItem("Select All", actionSelector("selectAll"))
  discard result.addItem("Complete", actionSelector("complete"))

proc popUpTextContextMenu*(
    textView: TextView, event: MouseEvent
): PopupMenuButton {.discardable.} =
  if textView.isNil:
    return nil
  let menu = textView.contextualMenuForText(event.location)
  popUpContextMenu(menu, View(textView), event)

proc openAttachmentDocument*(
    controller: DocumentController, attachment: TextAttachment, app: Application = nil
): Document {.discardable.} =
  if controller.isNil or attachment.fileUrl.len == 0:
    return nil
  controller.openDocument(attachment.fileUrl, app = app)

proc openAttachmentDocument*(
    textView: TextView,
    attachment: TextAttachment,
    controller: DocumentController = sharedDocumentController(),
    app: Application = nil,
): Document {.discardable.} =
  if textView.isNil:
    return nil
  controller.openAttachmentDocument(attachment, app)

proc openAttachmentDocumentAtIndex*(
    textView: TextView,
    index: int,
    controller: DocumentController = sharedDocumentController(),
    app: Application = nil,
): Document {.discardable.} =
  if textView.isNil:
    return nil
  let attachment = textView.attachmentAtIndex(index)
  controller.openAttachmentDocument(attachment.attachment, app)

proc saveSelectedTextDocument*(
    textView: TextView,
    document: Document,
    controller: DocumentController = sharedDocumentController(),
    panel: SavePanel = nil,
    app: Application = nil,
): bool {.discardable.} =
  if textView.isNil or document.isNil or controller.isNil:
    return false
  document.documentEdited = true
  controller.saveDocumentWithPanel(document, panel, app)

proc selectedTextDraggingItems*(editor: TextEditor): seq[DraggingItem] =
  if editor.isNil or editor.textView().isNil:
    @[]
  else:
    editor.textView().selectedTextDraggingItems()

proc beginDraggingSelectedText*(
    editor: TextEditor,
    allowedOperations: DragOperations = {dgoCopy, dgoMove},
    pasteboardName = DragPasteboardName,
): DraggingSession =
  if editor.isNil or editor.textView().isNil:
    nil
  else:
    editor.textView().beginDraggingSelectedText(allowedOperations, pasteboardName)

proc contextualMenuForText*(editor: TextEditor, point = AutoPoint): Menu =
  if editor.isNil or editor.textView().isNil:
    newMenu("Text")
  else:
    editor.textView().contextualMenuForText(point)
