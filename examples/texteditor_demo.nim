import merenda/nimkit

import std/[strutils, unicode]

import sigils/core
import sigils/selectors

type
  DemoTextDelegate* = ref object of DynamicAgent
    serviceCount*: int
    statusLabel: Label

  DemoDocument* = ref object of Document

  TextEditorDemo* = ref object of DynamicAgent
    app*: Application
    documentController*: DocumentController
    attachmentDocument*: DemoDocument
    textDelegate*: DemoTextDelegate
    window*: Window
    root*: View
    layout*: StackView
    header*: Label
    summary*: Label
    featureStatus*: Label
    editor*: TextEditor
    controls*: StackView
    featureControls*: StackView
    wrapCheck*: Button
    richCheck*: Button
    insetChoice*: ComboBox
    tintButton*: Button
    resetButton*: Button
    serviceButton*: Button
    copyButton*: Button
    dragButton*: Button
    linkButton*: Button
    pagesButton*: Button
    documentButton*: Button
    contextMenu*: Menu
    lastPasteboard*: Pasteboard
    lastDraggingSession*: DraggingSession
    lastOpenedDocument*: Document

const
  IntroText* =
    "NimKit Text Editor\n\n" &
    "This is a multi-line editor built like Cocoa: a scroll view owns a text view document.\n\n" &
    "It supports selection, undo, pasteboard rich text, wrapping, insets, and attributed runs.\n\n" &
    "The same text view can expose selected text services, contextual links, image attachment cells, file promises, document hooks, accessibility text parameters, and page snapshots."
  TitleText* = "NimKit Text Editor"
  LinkText* = "view document."
  LeadText* = "It supports"
  EmphasisText* = "attributed runs"
  AttachmentText* = "image attachment"
  AttachmentUrl* = "file:///tmp/text-editor-demo.png"

proc updateSummary*(demo: TextEditorDemo)
proc setFeatureStatus*(demo: TextEditorDemo, message: string)
proc selectDemoRange*(demo: TextEditorDemo, needle: string)
proc resetDocument*(demo: TextEditorDemo)

proc runeIndexOf*(text, needle: string): int =
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

proc textRangeOf*(text, needle: string): TextRange =
  let start = runeIndexOf(text, needle)
  doAssert start >= 0, "missing text editor demo fragment: " & needle
  initTextRange(start, needle.runeLen)

proc demoTextRange*(needle: string): TextRange =
  textRangeOf(IntroText, needle)

proc makeIntroStorage*(): TextStorage =
  result = newTextStorage(IntroText)
  result.setAttributes(
    demoTextRange(TitleText), defaultTextAttributes(color(0.95, 0.42, 0.78, 1.0), 18.0)
  )
  result.setAttributes(
    demoTextRange(LinkText), defaultTextAttributes(color(0.1, 0.58, 0.95, 1.0), 13.0)
  )
  result.setAttributes(
    demoTextRange(LeadText), defaultTextAttributes(color(0.1, 0.58, 0.95, 1.0), 13.0)
  )
  var emphasis = defaultTextAttributes(color(0.95, 0.56, 0.24, 1.0), 13.0)
  emphasis.underline = true
  result.setAttributes(demoTextRange(EmphasisText), emphasis)

  var linkAttributes = defaultTextAttributes(color(0.1, 0.58, 0.95, 1.0), 13.0)
  linkAttributes.link = "https://github.com/nim-lang/Nim"
  linkAttributes.underlineStyle = tldsSingle
  result.setAttributes(demoTextRange(LinkText), linkAttributes)

  var attachmentAttributes = defaultTextAttributes(color(0.58, 0.27, 0.85, 1.0), 13.0)
  attachmentAttributes.attachment = initTextAttachment(
    identifier = "demo-image",
    contentType = "image/png",
    fileName = "text-editor-demo.png",
    fileUrl = AttachmentUrl,
    size = initSize(96.0, 64.0),
  )
  attachmentAttributes.backgroundColor = color(0.58, 0.27, 0.85, 0.1)
  result.setAttributes(demoTextRange(AttachmentText), attachmentAttributes)

proc setStatus(delegate: DemoTextDelegate, message: string) =
  if not delegate.isNil and not delegate.statusLabel.isNil:
    delegate.statusLabel.text = message

protocol DemoTextDelegateProtocol of TextViewDelegateProtocol:
  method tvClickedLink(
      delegate: DemoTextDelegate, textView: TextView, link: string, range: TextRange
  ): bool =
    discard textView
    delegate.setStatus("Opened link: " & link & " @ " & $range.location)
    true

  method tvPerformService(
      delegate: DemoTextDelegate, textView: TextView, request: TextServiceRequest
  ): TextServiceResponse =
    discard textView
    inc delegate.serviceCount
    if request.stringValue.len == 0:
      return TextServiceResponse()
    var attributes = defaultTextAttributes(color(0.0, 0.62, 0.7, 1.0), 14.0)
    attributes.underline = true
    delegate.setStatus(
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

proc newDemoTextDelegate*(statusLabel: Label = nil): DemoTextDelegate =
  result = DemoTextDelegate(statusLabel: statusLabel)
  discard result.withProtocol(DemoTextDelegateProtocol)

proc newDemoDocument*(fileUrl, fileType: string): DemoDocument =
  result = DemoDocument()
  result.initDocument(fileUrl = fileUrl, fileType = fileType)
  discard result.withProtocol(DemoDocumentWindows)

proc setFeatureStatus*(demo: TextEditorDemo, message: string) =
  if not demo.isNil and not demo.featureStatus.isNil:
    demo.featureStatus.text = message

proc updateSummary*(demo: TextEditorDemo) =
  if demo.isNil or demo.editor.isNil or demo.summary.isNil:
    return
  let selected = demo.editor.selectedRange()
  demo.summary.text =
    "Characters: " & $demo.editor.stringValue().runeLen & " / Selection: " &
    $selected.location & ":" & $selected.length & " / Wrap: " & $demo.editor.wraps &
    " / Rich text: " & $demo.editor.richText

proc selectDemoRange*(demo: TextEditorDemo, needle: string) =
  demo.editor.selectedRange = textRangeOf(demo.editor.stringValue(), needle)

proc applyInsetChoice(demo: TextEditorDemo) =
  case demo.insetChoice.indexOfSelectedItem()
  of 0:
    demo.editor.textInsets = insets(3.0, 5.0, 3.0, 5.0)
  of 2:
    demo.editor.textInsets = insets(14.0, 18.0, 14.0, 18.0)
  else:
    demo.editor.textInsets = insets(6.0, 7.0, 6.0, 7.0)

proc resetDocument*(demo: TextEditorDemo) =
  demo.editor.attributedText = makeIntroStorage()
  demo.editor.selectedRange = initTextRange(0, 0)
  demo.updateSummary()
  demo.setFeatureStatus(
    "Ready: " & $demo.editor.textView().attachmentPresentations().len & " attachment / " &
      $demo.editor.textView().paginateTextView().len & " page"
  )

proc editorChanged(demo: TextEditorDemo, sender: DynamicAgent) {.slot.} =
  discard sender
  demo.updateSummary()

proc toggleWrap(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  demo.editor.wraps = demo.wrapCheck.state == bsOn
  demo.updateSummary()

proc toggleRichText(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  demo.editor.richText = demo.richCheck.state == bsOn
  demo.updateSummary()

proc selectInset(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  demo.applyInsetChoice()
  demo.updateSummary()

proc styleSelection(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  let selected = demo.editor.selectedRange()
  if selected.length == 0:
    return
  var attributes = defaultTextAttributes(color(0.0, 0.85, 0.95, 1.0), 14.0)
  attributes.underline = true
  demo.editor.setAttributes(selected, attributes)
  demo.updateSummary()

proc resetText(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  demo.resetDocument()

proc runService(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  if demo.editor.selectedRange().length == 0:
    demo.selectDemoRange(LeadText)
  discard demo.editor.textView().performSelectedTextService()
  demo.updateSummary()

proc copyRichSelection(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  if demo.editor.selectedRange().length == 0:
    demo.selectDemoRange(EmphasisText)
  let pasteboard = pasteboardWithUniqueName()
  demo.lastPasteboard = pasteboard
  discard demo.editor.textView().writeSelectionToPasteboard(
      pasteboard, [ttfAttributedText, ttfPlainText, ttfHTML, ttfURL, ttfFilePromise]
    )
  demo.setFeatureStatus("Pasteboard: " & pasteboard.types().join(", "))
  demo.updateSummary()

proc buildTextDragItems(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  demo.selectDemoRange(AttachmentText)
  let session = demo.editor.beginDraggingSelectedText(
    {dgoCopy}, pasteboardWithUniqueName().pasteboardName()
  )
  demo.lastDraggingSession = session
  if session.isNil:
    demo.setFeatureStatus("Drag items: none")
  else:
    demo.setFeatureStatus(
      "Drag items: " & $session.items().len & " / promises: " &
        $session.promisedFileItems().len
    )
  demo.updateSummary()

proc openDemoLink(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  let range = textRangeOf(demo.editor.stringValue(), LinkText)
  demo.editor.selectedRange = range
  discard demo.editor.textView().openLinkAtIndex(int(range.location))
  demo.updateSummary()

proc snapshotTextPages(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  let
    options = initTextPageLayoutOptions(
      pageSize = initSize(320.0, 120.0), contentInsets = insets(8.0)
    )
    pages = demo.editor.textView().paginateTextView(options)
    visible = demo.editor.textView().accessibilityVisibleCharacterRange()
    line = demo.editor.textView().accessibilityInsertionPointLine()
    snapshot = demo.editor.textView().layoutStabilitySnapshot(
        TextLayoutStabilityOptions(
          displayScale: 2.0, fontSize: 13.0, pageOptions: options
        )
      )
  demo.setFeatureStatus(
    "Pages: " & $pages.len & " / visible: " & $visible.location & ":" & $visible.length &
      " / line: " & $line & " / height: " & $snapshot.contentSize.height
  )

proc openAttachmentDocument(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  let range = textRangeOf(demo.editor.stringValue(), AttachmentText)
  demo.editor.selectedRange = range
  let document = demo.editor.textView().openAttachmentDocumentAtIndex(
      int(range.location), demo.documentController, demo.app
    )
  demo.lastOpenedDocument = document
  if document.isNil:
    demo.setFeatureStatus("Document hook: no attachment document")
  else:
    demo.setFeatureStatus("Document hook: " & document.fileUrl())
  demo.updateSummary()

proc toggleWrapFromMenu(demo: TextEditorDemo, sender: DynamicAgent) =
  discard sender
  demo.wrapCheck.state = if demo.wrapCheck.state == bsOn: bsOff else: bsOn
  demo.toggleWrap(sender)

proc configureActions(demo: TextEditorDemo) =
  let
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

  demo.contextMenu = newMenu("Text Editor Context")
  let
    contextStyleItem = newMenuItem("Style Selection", tintAction)
    contextWrapItem = newMenuItem("Toggle Wrap", contextWrapAction)
    contextResetItem = newMenuItem("Reset Text", resetAction)
  contextStyleItem.target = newActionTarget(tintAction) do(sender: DynamicAgent):
    demo.styleSelection(sender)
  contextWrapItem.target = newActionTarget(contextWrapAction) do(sender: DynamicAgent):
    demo.toggleWrapFromMenu(sender)
  contextResetItem.target = newActionTarget(resetAction) do(sender: DynamicAgent):
    demo.resetText(sender)
  discard demo.contextMenu.addItem(contextStyleItem)
  discard demo.contextMenu.addItem(contextWrapItem)
  discard demo.contextMenu.addSeparator()
  discard demo.contextMenu.addItem(contextResetItem)

  demo.wrapCheck.target = newActionTarget(wrapAction) do(sender: DynamicAgent):
    demo.toggleWrap(sender)
  demo.wrapCheck.action = wrapAction
  demo.richCheck.target = newActionTarget(richAction) do(sender: DynamicAgent):
    demo.toggleRichText(sender)
  demo.richCheck.action = richAction
  demo.insetChoice.target = newActionTarget(insetAction) do(sender: DynamicAgent):
    demo.selectInset(sender)
  demo.insetChoice.action = insetAction
  demo.tintButton.target = newActionTarget(tintAction) do(sender: DynamicAgent):
    demo.styleSelection(sender)
  demo.tintButton.action = tintAction
  demo.resetButton.target = newActionTarget(resetAction) do(sender: DynamicAgent):
    demo.resetText(sender)
  demo.resetButton.action = resetAction
  demo.serviceButton.target = newActionTarget(serviceAction) do(sender: DynamicAgent):
    demo.runService(sender)
  demo.serviceButton.action = serviceAction
  demo.copyButton.target = newActionTarget(copyAction) do(sender: DynamicAgent):
    demo.copyRichSelection(sender)
  demo.copyButton.action = copyAction
  demo.dragButton.target = newActionTarget(dragAction) do(sender: DynamicAgent):
    demo.buildTextDragItems(sender)
  demo.dragButton.action = dragAction
  demo.linkButton.target = newActionTarget(linkAction) do(sender: DynamicAgent):
    demo.openDemoLink(sender)
  demo.linkButton.action = linkAction
  demo.pagesButton.target = newActionTarget(pagesAction) do(sender: DynamicAgent):
    demo.snapshotTextPages(sender)
  demo.pagesButton.action = pagesAction
  demo.documentButton.target = newActionTarget(documentAction) do(sender: DynamicAgent):
    demo.openAttachmentDocument(sender)
  demo.documentButton.action = documentAction

proc configureLayout(demo: TextEditorDemo) =
  demo.layout.spacing = 12.0
  demo.layout.alignment = svaFill
  demo.layout.edgeInsets = insets(22.0, 24.0)

  demo.editor.wraps = true
  demo.editor.richText = true
  demo.editor.menu = demo.contextMenu
  demo.editor.textView().delegate = DynamicAgent(demo.textDelegate)
  demo.editor.minimumDocumentSize = initSize(640.0, 280.0)
  demo.editor.setHuggingPriority(LayoutPriorityLow, laVertical)
  demo.editor.setCompressionPriority(LayoutPriorityRequired, laVertical)

  demo.wrapCheck.state = bsOn
  demo.richCheck.state = bsOn
  demo.insetChoice.selectItemAtIndex(1)

  demo.controls.spacing = 8.0
  demo.controls.alignment = svaCenter
  demo.controls.distribution = svdNatural
  demo.controls.setHuggingPriority(LayoutPriorityRequired, laVertical)
  demo.controls.setCompressionPriority(LayoutPriorityRequired, laVertical)

  demo.featureControls.spacing = 8.0
  demo.featureControls.alignment = svaCenter
  demo.featureControls.distribution = svdNatural
  demo.featureControls.setHuggingPriority(LayoutPriorityRequired, laVertical)
  demo.featureControls.setCompressionPriority(LayoutPriorityRequired, laVertical)

  demo.controls.addArrangedSubview(
    demo.wrapCheck, demo.richCheck, demo.insetChoice, demo.tintButton, demo.resetButton
  )
  demo.controls.addFlexibleSpacer()
  demo.featureControls.addArrangedSubview(
    demo.serviceButton, demo.copyButton, demo.dragButton, demo.linkButton,
    demo.pagesButton, demo.documentButton,
  )
  demo.featureControls.addFlexibleSpacer()
  demo.layout.addArrangedSubview(
    demo.header, demo.summary, demo.editor, demo.controls, demo.featureControls,
    demo.featureStatus,
  )
  demo.layout.addFlexibleSpacer()
  demo.root.addSubview(demo.layout)
  discard demo.layout.pinEdges(
    toGuide = demo.root.contentLayoutGuide(insets(0.0)),
    edges = {leLeft, leTop, leRight, leBottom},
  )

proc newTextEditorDemo*(
    app: Application = sharedApplication(), frame = rect(130, 110, 720, 520)
): TextEditorDemo =
  result = TextEditorDemo(
    app: app,
    documentController: newDocumentController(app),
    attachmentDocument: newDemoDocument(AttachmentUrl, "png"),
    window: newWindow("NimKit Text Editor Demo", frame = frame),
    root: newView(),
    layout: newStackView(laVertical),
    header: newTitleLabel("Text Editor Demo"),
    summary: newStatusLabel(""),
    featureStatus: newStatusLabel(""),
    editor: newTextEditor(frame = rect(0, 0, 640, 280)),
    controls: newStackView(laHorizontal),
    featureControls: newStackView(laHorizontal),
    wrapCheck: newCheckBox("Wrap text"),
    richCheck: newCheckBox("Rich text"),
    insetChoice: newComboBox(["Compact inset", "Cocoa inset", "Roomy inset"]),
    tintButton: newButton("Style Selection"),
    resetButton: newButton("Reset Text"),
    serviceButton: newButton("Service"),
    copyButton: newButton("Copy Rich"),
    dragButton: newButton("Drag Items"),
    linkButton: newButton("Open Link"),
    pagesButton: newButton("Pages"),
    documentButton: newButton("Document Hook"),
  )
  result.textDelegate = newDemoTextDelegate(result.featureStatus)
  result.documentController.addDocument(result.attachmentDocument)
  result.configureActions()
  result.configureLayout()
  result.editor.connect(textDidChange, result, editorChanged)
  result.resetDocument()
  result.window.setContentView(result.root)
  discard result.window.makeFirstResponder(result.editor)

proc showTextEditorDemo*(demo: TextEditorDemo) =
  if demo.isNil:
    return
  demo.app.addWindow(demo.window)
  demo.window.makeKeyAndOrderFront()

when isMainModule:
  let demo = newTextEditorDemo()
  demo.showTextEditorDemo()
  demo.app.run()
