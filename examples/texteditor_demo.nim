import merenda/nimkit

import std/[strutils, unicode]

import sigils/core
import sigils/selectors

type
  DemoTextDelegate = ref object of DynamicAgent
    serviceCount: int

  DemoDocument = ref object of Document

const
  IntroText =
    "NimKit Text Editor\n\n" &
    "This is a multi-line editor built like Cocoa: a scroll view owns a text view document.\n\n" &
    "It supports selection, undo, pasteboard rich text, wrapping, insets, and attributed runs.\n\n" &
    "The same text view can expose selected text services, contextual links, image attachment cells, file promises, document hooks, accessibility text parameters, and page snapshots."
  TitleText = "NimKit Text Editor"
  LinkText = "view document."
  LeadText = "It supports"
  EmphasisText = "attributed runs"
  AttachmentText = "image attachment"

proc setFeatureStatus(message: string)

proc runeIndexOf(text, needle: string): int =
  let
    total = text.runeLen
    length = needle.runeLen
  if length == 0:
    return 0
  if length > total:
    return -1
  for index in 0 .. total - length:
    if text.runeSubStr(index, length) == needle:
      return index
  -1

proc textRangeOf(text, needle: string): TextRange =
  let start = runeIndexOf(text, needle)
  doAssert start >= 0, "missing text editor demo fragment: " & needle
  initTextRange(start, needle.runeLen)

proc makeIntroStorage(): TextStorage =
  result = newTextStorage(IntroText)
  result.setAttributes(
    textRangeOf(IntroText, TitleText),
    defaultTextAttributes(initColor(0.95, 0.42, 0.78, 1.0), 18.0),
  )
  result.setAttributes(
    textRangeOf(IntroText, LinkText),
    defaultTextAttributes(initColor(0.1, 0.58, 0.95, 1.0), 13.0),
  )
  result.setAttributes(
    textRangeOf(IntroText, LeadText),
    defaultTextAttributes(initColor(0.1, 0.58, 0.95, 1.0), 13.0),
  )
  var emphasis = defaultTextAttributes(initColor(0.95, 0.56, 0.24, 1.0), 13.0)
  emphasis.underline = true
  result.setAttributes(textRangeOf(IntroText, EmphasisText), emphasis)

  var linkAttributes = defaultTextAttributes(initColor(0.1, 0.58, 0.95, 1.0), 13.0)
  linkAttributes.link = "https://github.com/nim-lang/Nim"
  linkAttributes.underlineStyle = tldsSingle
  result.setAttributes(textRangeOf(IntroText, LinkText), linkAttributes)

  var attachmentAttributes =
    defaultTextAttributes(initColor(0.58, 0.27, 0.85, 1.0), 13.0)
  attachmentAttributes.attachment = initTextAttachment(
    identifier = "demo-image",
    contentType = "image/png",
    fileName = "text-editor-demo.png",
    fileUrl = "file:///tmp/text-editor-demo.png",
    size = initSize(96.0, 64.0),
  )
  attachmentAttributes.backgroundColor = initColor(0.58, 0.27, 0.85, 0.1)
  result.setAttributes(textRangeOf(IntroText, AttachmentText), attachmentAttributes)

protocol DemoTextDelegateProtocol of TextViewDelegateProtocol:
  method tvClickedLink(
      delegate: DemoTextDelegate, textView: TextView, link: string, range: TextRange
  ): bool =
    discard delegate
    discard textView
    setFeatureStatus("Opened link: " & link & " @ " & $range.location)
    true

  method tvPerformService(
      delegate: DemoTextDelegate, textView: TextView, request: TextServiceRequest
  ): TextServiceResponse =
    discard textView
    inc delegate.serviceCount
    if request.stringValue.len == 0:
      return TextServiceResponse()
    var attributes = defaultTextAttributes(initColor(0.0, 0.62, 0.7, 1.0), 14.0)
    attributes.underline = true
    setFeatureStatus(
      "Service " & $delegate.serviceCount & ": " & request.stringValue.toUpperAscii()
    )
    TextServiceResponse(
      handled: true,
      replacementRange: request.range,
      replacement: newAttributedString(request.stringValue.toUpperAscii(), attributes),
    )

protocol DemoDocumentWindows of DocumentWindowProtocol:
  method makeWindowControllers(document: DemoDocument): seq[WindowController] =
    @[]

proc newDemoTextDelegate(): DemoTextDelegate =
  result = DemoTextDelegate()
  discard result.withProtocol(DemoTextDelegateProtocol)

proc newDemoDocument(fileUrl, fileType: string): DemoDocument =
  result = DemoDocument()
  result.initDocument(fileUrl = fileUrl, fileType = fileType)
  discard result.withProtocol(DemoDocumentWindows)

let
  app = sharedApplication()
  documentController = newDocumentController(app)
  attachmentDocument = newDemoDocument("file:///tmp/text-editor-demo.png", "png")
  textDelegate = newDemoTextDelegate()
  window = newWindow("NimKit Text Editor Demo", frame = initRect(130, 110, 720, 520))
  root = newView()
  layout = newStackView(laVertical)
  header = newTitleLabel("Text Editor Demo")
  summary = newStatusLabel("")
  featureStatus = newStatusLabel("")
  editor = newTextEditor(frame = initRect(0, 0, 640, 280))
  controls = newStackView(laHorizontal)
  featureControls = newStackView(laHorizontal)
  wrapCheck = newCheckBox("Wrap text")
  richCheck = newCheckBox("Rich text")
  insetChoice = newComboBox(["Compact inset", "Cocoa inset", "Roomy inset"])
  tintButton = newButton("Style Selection")
  resetButton = newButton("Reset Text")
  serviceButton = newButton("Service")
  copyButton = newButton("Copy Rich")
  dragButton = newButton("Drag Items")
  linkButton = newButton("Open Link")
  pagesButton = newButton("Pages")
  documentButton = newButton("Document Hook")
  wrapAction = actionSelector("toggleTextWrap")
  richAction = actionSelector("toggleRichText")
  insetAction = actionSelector("selectTextInset")
  tintAction = actionSelector("styleSelection")
  resetAction = actionSelector("resetTextEditor")
  serviceAction = actionSelector("runTextService")
  copyAction = actionSelector("copyRichSelection")
  dragAction = actionSelector("buildTextDragItems")
  linkAction = actionSelector("openDemoLink")
  pagesAction = actionSelector("snapshotTextPages")
  documentAction = actionSelector("openAttachmentDocument")
  contextWrapAction = actionSelector("contextToggleTextWrap")

documentController.addDocument(attachmentDocument)

proc setFeatureStatus(message: string) =
  featureStatus.text = message

proc updateSummary() =
  let selected = editor.selectedRange()
  summary.text =
    "Characters: " & $editor.stringValue().runeLen & " / Selection: " &
    $selected.location & ":" & $selected.length & " / Wrap: " & $editor.wraps &
    " / Rich text: " & $editor.richText

proc selectDemoRange(needle: string) =
  editor.selectedRange = textRangeOf(editor.stringValue(), needle)

proc applyInsetChoice() =
  case insetChoice.indexOfSelectedItem()
  of 0:
    editor.textInsets = insets(3.0, 5.0, 3.0, 5.0)
  of 2:
    editor.textInsets = insets(14.0, 18.0, 14.0, 18.0)
  else:
    editor.textInsets = insets(6.0, 7.0, 6.0, 7.0)

proc resetDocument() =
  editor.attributedText = makeIntroStorage()
  editor.selectedRange = initTextRange(0, 0)
  updateSummary()
  setFeatureStatus(
    "Ready: " & $editor.textView().attachmentPresentations().len & " attachment / " &
      $editor.textView().paginateTextView().len & " page"
  )

proc editorChanged(textEditor: TextEditor, sender: DynamicAgent) {.slot.} =
  discard textEditor
  discard sender
  updateSummary()

proc toggleWrap(sender: DynamicAgent) =
  discard sender
  editor.wraps = wrapCheck.state == bsOn
  updateSummary()

proc toggleRichText(sender: DynamicAgent) =
  discard sender
  editor.richText = richCheck.state == bsOn
  updateSummary()

proc selectInset(sender: DynamicAgent) =
  discard sender
  applyInsetChoice()
  updateSummary()

proc styleSelection(sender: DynamicAgent) =
  discard sender
  let selected = editor.selectedRange()
  if selected.length == 0:
    return
  var attributes = defaultTextAttributes(initColor(0.0, 0.85, 0.95, 1.0), 14.0)
  attributes.underline = true
  editor.setAttributes(selected, attributes)
  updateSummary()

proc resetText(sender: DynamicAgent) =
  discard sender
  resetDocument()

proc runService(sender: DynamicAgent) =
  discard sender
  if editor.selectedRange().length == 0:
    selectDemoRange(LeadText)
  discard editor.textView().performSelectedTextService()
  updateSummary()

proc copyRichSelection(sender: DynamicAgent) =
  discard sender
  if editor.selectedRange().length == 0:
    selectDemoRange(EmphasisText)
  let pasteboard = pasteboardWithUniqueName()
  discard editor.textView().writeSelectionToPasteboard(
      pasteboard, [ttfAttributedText, ttfPlainText, ttfHTML, ttfURL, ttfFilePromise]
    )
  setFeatureStatus("Pasteboard: " & pasteboard.types().join(", "))
  updateSummary()

proc buildTextDragItems(sender: DynamicAgent) =
  discard sender
  selectDemoRange(AttachmentText)
  let session = editor.beginDraggingSelectedText(
    {dgoCopy}, pasteboardWithUniqueName().pasteboardName()
  )
  if session.isNil:
    setFeatureStatus("Drag items: none")
  else:
    setFeatureStatus(
      "Drag items: " & $session.items().len & " / promises: " &
        $session.promisedFileItems().len
    )
  updateSummary()

proc openDemoLink(sender: DynamicAgent) =
  discard sender
  let range = textRangeOf(editor.stringValue(), LinkText)
  editor.selectedRange = range
  discard editor.textView().openLinkAtIndex(int(range.location))
  updateSummary()

proc snapshotTextPages(sender: DynamicAgent) =
  discard sender
  let
    options = initTextPageLayoutOptions(
      pageSize = initSize(320.0, 120.0), contentInsets = insets(8.0)
    )
    pages = editor.textView().paginateTextView(options)
    visible = editor.textView().accessibilityVisibleCharacterRange()
    line = editor.textView().accessibilityInsertionPointLine()
    snapshot = editor.textView().layoutStabilitySnapshot(
        TextLayoutStabilityOptions(
          displayScale: 2.0, fontSize: 13.0, pageOptions: options
        )
      )
  setFeatureStatus(
    "Pages: " & $pages.len & " / visible: " & $visible.location & ":" & $visible.length &
      " / line: " & $line & " / height: " & $snapshot.contentSize.height
  )

proc openAttachmentDocument(sender: DynamicAgent) =
  discard sender
  let range = textRangeOf(editor.stringValue(), AttachmentText)
  editor.selectedRange = range
  let document = editor.textView().openAttachmentDocumentAtIndex(
      int(range.location), documentController, app
    )
  if document.isNil:
    setFeatureStatus("Document hook: no attachment document")
  else:
    setFeatureStatus("Document hook: " & document.fileUrl())
  updateSummary()

proc toggleWrapFromMenu(sender: DynamicAgent) =
  discard sender
  wrapCheck.state = if wrapCheck.state == bsOn: bsOff else: bsOn
  toggleWrap(sender)

let
  contextMenu = newMenu("Text Editor Context")
  contextStyleItem = newMenuItem("Style Selection", tintAction)
  contextWrapItem = newMenuItem("Toggle Wrap", contextWrapAction)
  contextResetItem = newMenuItem("Reset Text", resetAction)

contextStyleItem.target = newActionTarget(tintAction, styleSelection)
contextWrapItem.target = newActionTarget(contextWrapAction, toggleWrapFromMenu)
contextResetItem.target = newActionTarget(resetAction, resetText)
discard contextMenu.addItem(contextStyleItem)
discard contextMenu.addItem(contextWrapItem)
discard contextMenu.addSeparator()
discard contextMenu.addItem(contextResetItem)

layout.spacing = 12.0
layout.alignment = svaFill
layout.edgeInsets = insets(22.0, 24.0)

editor.wraps = true
editor.richText = true
editor.menu = contextMenu
editor.textView().delegate = DynamicAgent(textDelegate)
editor.minimumDocumentSize = initSize(640.0, 280.0)
editor.setHuggingPriority(LayoutPriorityLow, laVertical)
editor.setCompressionPriority(LayoutPriorityRequired, laVertical)

wrapCheck.state = bsOn
richCheck.state = bsOn
insetChoice.selectItemAtIndex(1)

controls.spacing = 8.0
controls.alignment = svaCenter
controls.distribution = svdNatural
controls.setHuggingPriority(LayoutPriorityRequired, laVertical)
controls.setCompressionPriority(LayoutPriorityRequired, laVertical)

featureControls.spacing = 8.0
featureControls.alignment = svaCenter
featureControls.distribution = svdNatural
featureControls.setHuggingPriority(LayoutPriorityRequired, laVertical)
featureControls.setCompressionPriority(LayoutPriorityRequired, laVertical)

wrapCheck.target = newActionTarget(wrapAction, toggleWrap)
wrapCheck.action = wrapAction
richCheck.target = newActionTarget(richAction, toggleRichText)
richCheck.action = richAction
insetChoice.target = newActionTarget(insetAction, selectInset)
insetChoice.action = insetAction
tintButton.target = newActionTarget(tintAction, styleSelection)
tintButton.action = tintAction
resetButton.target = newActionTarget(resetAction, resetText)
resetButton.action = resetAction
serviceButton.target = newActionTarget(serviceAction, runService)
serviceButton.action = serviceAction
copyButton.target = newActionTarget(copyAction, copyRichSelection)
copyButton.action = copyAction
dragButton.target = newActionTarget(dragAction, buildTextDragItems)
dragButton.action = dragAction
linkButton.target = newActionTarget(linkAction, openDemoLink)
linkButton.action = linkAction
pagesButton.target = newActionTarget(pagesAction, snapshotTextPages)
pagesButton.action = pagesAction
documentButton.target = newActionTarget(documentAction, openAttachmentDocument)
documentButton.action = documentAction

editor.connect(textDidChange, editor, editorChanged)

controls.addArrangedSubview(wrapCheck, richCheck, insetChoice, tintButton, resetButton)
controls.addFlexibleSpacer()
featureControls.addArrangedSubview(
  serviceButton, copyButton, dragButton, linkButton, pagesButton, documentButton
)
featureControls.addFlexibleSpacer()
layout.addArrangedSubview(
  header, summary, editor, controls, featureControls, featureStatus
)
layout.addFlexibleSpacer()
root.addSubview(layout)
discard layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(0.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

resetDocument()
window.setContentView(root)
discard window.makeFirstResponder(editor)
app.addWindow(window)
window.makeKeyAndOrderFront()
app.run()
