import sigils/core

import ../accessibility/accessibility
import ../containers/scrollviews
import ../drawing
import ../foundation/selectors
import ../foundation/types
import ../responder/responders
import ../themes
import ../view/viewgeometry
import ../view/views
import ./textlayout
import ./textstorage
import ./texttypes
import ./textviews

export scrollviews
export textlayout
export textstorage
export texttypes
export textviews

type TextEditor* = ref object of View
  xScrollView: ScrollView
  xTextView: TextView
  xTextInsets: EdgeInsets
  xWraps: bool
  xMinimumDocumentSize: Size

const
  DefaultTextEditorWidth = 320.0'f32
  DefaultTextEditorHeight = 160.0'f32
  DefaultTextEditorMeasureWidth = 100000.0'f32
  DefaultTextEditorMeasureHeight = 100000.0'f32

proc updateTextEditorLayout(editor: TextEditor)

protocol TextEditorEvents:
  proc textDidChange*(editor: TextEditor, sender: DynamicAgent) {.signal.}

proc textEditorTextDidChange(editor: TextEditor, sender: DynamicAgent) {.slot.} =
  discard sender
  editor.updateTextEditorLayout()
  emit editor.textDidChange(DynamicAgent(editor))

func normalizedTextInsets(insets: EdgeInsets): EdgeInsets =
  insets(
    max(insets.top, 0.0'f32),
    max(insets.left, 0.0'f32),
    max(insets.bottom, 0.0'f32),
    max(insets.right, 0.0'f32),
  )

func normalizedDocumentSize(size: Size): Size =
  initSize(max(size.width, 0.0'f32), max(size.height, 0.0'f32))

proc textView*(editor: TextEditor): TextView =
  if editor.isNil: nil else: editor.xTextView

proc scrollView*(editor: TextEditor): ScrollView =
  if editor.isNil: nil else: editor.xScrollView

proc textInsets*(editor: TextEditor): EdgeInsets =
  if editor.isNil:
    insets(0.0)
  else:
    editor.xTextInsets

proc `textInsets=`*(editor: TextEditor, insets: EdgeInsets) =
  let normalized = insets.normalizedTextInsets()
  if editor.isNil or editor.xTextInsets == normalized:
    return
  editor.xTextInsets = normalized
  editor.updateTextEditorLayout()
  editor.setNeedsDisplay(true)

proc wraps*(editor: TextEditor): bool =
  (not editor.isNil) and editor.xWraps

proc `wraps=`*(editor: TextEditor, wraps: bool) =
  if editor.isNil or editor.xWraps == wraps:
    return
  editor.xWraps = wraps
  editor.xScrollView.hasHorizontalScroller = not wraps
  editor.updateTextEditorLayout()

proc minimumDocumentSize*(editor: TextEditor): Size =
  if editor.isNil:
    initSize(0.0, 0.0)
  else:
    editor.xMinimumDocumentSize

proc `minimumDocumentSize=`*(editor: TextEditor, size: Size) =
  let normalized = size.normalizedDocumentSize()
  if editor.isNil or editor.xMinimumDocumentSize == normalized:
    return
  editor.xMinimumDocumentSize = normalized
  editor.updateTextEditorLayout()

proc textStorage*(editor: TextEditor): TextStorage =
  if editor.isNil:
    nil
  else:
    editor.xTextView.textStorage()

proc `textStorage=`*(editor: TextEditor, storage: TextStorage) =
  if editor.isNil:
    return
  editor.xTextView.textStorage = storage
  editor.updateTextEditorLayout()

proc attributedText*(editor: TextEditor): TextStorage =
  editor.textStorage()

proc `attributedText=`*(editor: TextEditor, storage: TextStorage) =
  editor.textStorage = storage

proc stringValue*(editor: TextEditor): string =
  if editor.isNil:
    ""
  else:
    editor.xTextView.stringValue()

proc `stringValue=`*(editor: TextEditor, value: string) =
  if editor.isNil:
    return
  editor.xTextView.stringValue = value
  editor.updateTextEditorLayout()

proc text*(editor: TextEditor): string =
  editor.stringValue()

proc `text=`*(editor: TextEditor, value: string) =
  editor.stringValue = value

proc selectedRange*(editor: TextEditor): TextRange =
  if editor.isNil:
    initTextRange(0, 0)
  else:
    editor.xTextView.selectedRange()

proc `selectedRange=`*(editor: TextEditor, range: TextRange) =
  if not editor.isNil:
    editor.xTextView.selectedRange = range

proc editable*(editor: TextEditor): bool =
  (not editor.isNil) and editor.xTextView.editable()

proc `editable=`*(editor: TextEditor, editable: bool) =
  if not editor.isNil:
    editor.xTextView.editable = editable

proc selectable*(editor: TextEditor): bool =
  (not editor.isNil) and editor.xTextView.selectable()

proc `selectable=`*(editor: TextEditor, selectable: bool) =
  if not editor.isNil:
    editor.xTextView.selectable = selectable

proc richText*(editor: TextEditor): bool =
  (not editor.isNil) and editor.xTextView.richText()

proc `richText=`*(editor: TextEditor, richText: bool) =
  if not editor.isNil:
    editor.xTextView.richText = richText

proc allowsUndo*(editor: TextEditor): bool =
  (not editor.isNil) and editor.xTextView.allowsUndo()

proc `allowsUndo=`*(editor: TextEditor, allowsUndo: bool) =
  if not editor.isNil:
    editor.xTextView.allowsUndo = allowsUndo

proc alignment*(editor: TextEditor): TextAlignment =
  if editor.isNil:
    taLeft
  else:
    editor.xTextView.alignment()

proc `alignment=`*(editor: TextEditor, alignment: TextAlignment) =
  if not editor.isNil:
    editor.xTextView.alignment = alignment

proc textColor*(editor: TextEditor): Color =
  if editor.isNil:
    color(0.08, 0.09, 0.11, 1.0)
  else:
    editor.xTextView.textColor()

proc `textColor=`*(editor: TextEditor, color: Color) =
  if not editor.isNil:
    editor.xTextView.textColor = color

proc selectionColor*(editor: TextEditor): Color =
  if editor.isNil:
    color(0.24, 0.56, 1.0, 0.34)
  else:
    editor.xTextView.selectionColor()

proc `selectionColor=`*(editor: TextEditor, color: Color) =
  if not editor.isNil:
    editor.xTextView.selectionColor = color

proc typingAttributes*(editor: TextEditor): TextAttributes =
  if editor.isNil:
    defaultTextAttributes()
  else:
    editor.xTextView.typingAttributes()

proc `typingAttributes=`*(editor: TextEditor, attributes: TextAttributes) =
  if not editor.isNil:
    editor.xTextView.typingAttributes = attributes

proc setAttributes*(editor: TextEditor, range: TextRange, attributes: TextAttributes) =
  if editor.isNil or editor.xTextView.textStorage().isNil:
    return
  editor.xTextView.textStorage().setAttributes(range, attributes)
  editor.xTextView.layoutManager().invalidateLayout()
  editor.updateTextEditorLayout()
  editor.xTextView.setNeedsDisplay(true)

proc selectAllText*(editor: TextEditor) =
  if not editor.isNil:
    editor.xTextView.selectAllText()

proc measuredTextLayout(editor: TextEditor, width: float32): auto =
  let
    insets = editor.xTextInsets
    measuringWidth = max(width, insets.horizontal + 1.0'f32)
    measuringRect =
      rect(0.0, 0.0, measuringWidth, DefaultTextEditorMeasureHeight).inset(insets)
  textLayout(
    measuringRect,
    editor.xTextView.textStorage(),
    editor.xTextView.alignment(),
    editor.xWraps,
  )

proc textDocumentSize(
    editor: TextEditor, viewportWidth, viewportHeight: float32
): Size =
  if editor.isNil or editor.xTextView.isNil:
    return initSize(viewportWidth, viewportHeight)

  let
    insets = editor.xTextInsets
    width = if editor.xWraps: viewportWidth else: DefaultTextEditorMeasureWidth
    layout = editor.measuredTextLayout(width)
    textWidth =
      if layout.selectionRects.len > 0:
        layout.bounding.w + insets.horizontal
      else:
        insets.horizontal + 1.0'f32
    textHeight =
      if layout.selectionRects.len > 0:
        layout.bounding.h
      else:
        defaultFontSize()
    documentWidth =
      if editor.xWraps:
        viewportWidth
      else:
        max(max(textWidth, viewportWidth), editor.xMinimumDocumentSize.width)
  initSize(
    documentWidth,
    max(
      max(textHeight + insets.vertical, viewportHeight),
      editor.xMinimumDocumentSize.height,
    ),
  )

proc updateTextEditorLayout(editor: TextEditor) =
  if editor.isNil or editor.xScrollView.isNil or editor.xTextView.isNil:
    return

  let
    bounds = editor.bounds()
    viewportWidth = max(bounds.size.width, 0.0'f32)
    viewportHeight = max(bounds.size.height, 0.0'f32)
    documentSize = editor.textDocumentSize(viewportWidth, viewportHeight)

  editor.xScrollView.frame = bounds
  editor.xTextView.frame = rect(0.0, 0.0, documentSize.width, documentSize.height)
  editor.xTextView.textContainer =
    initTextContainer(documentSize, editor.xTextInsets, editor.xWraps)

protocol DefaultTextEditorLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(editor: TextEditor): IntrinsicSize =
    initIntrinsicSize(DefaultTextEditorWidth, DefaultTextEditorHeight)

  method layoutSubviews(editor: TextEditor) =
    editor.updateTextEditorLayout()

protocol DefaultTextEditorResponder of ResponderProtocol:
  method acceptsFirstResponder(editor: TextEditor): bool =
    not editor.xTextView.isNil and
      (editor.xTextView.editable() or editor.xTextView.selectable())

  method becomeFirstResponder(editor: TextEditor): bool =
    if editor.xTextView.isNil:
      return false
    editor.xTextView.focused = true
    true

  method resignFirstResponder(editor: TextEditor): bool =
    if not editor.xTextView.isNil:
      editor.xTextView.focused = false
    true

protocol DefaultTextEditorView of ViewProtocol:
  method canBecomeKeyView(editor: TextEditor): bool =
    not editor.xTextView.isNil and editor.xTextView.canBecomeKeyView()

method textEditorInputHasMarkedText(editor: TextEditor): bool {.selector.} =
  (not editor.xTextView.isNil) and textviews.hasMarkedText(editor.xTextView)

method textEditorInputMarkedRange(editor: TextEditor): TextRange {.selector.} =
  if editor.xTextView.isNil:
    initTextRange(0, 0)
  else:
    textviews.markedRange(editor.xTextView)

method textEditorInputSelectedRange(editor: TextEditor): TextRange {.selector.} =
  if editor.xTextView.isNil:
    initTextRange(0, 0)
  else:
    textviews.selectedRange(editor.xTextView)

method textEditorInputAttributedSubstringForRange(
    editor: TextEditor, range: TextRange
): AttributedString {.selector.} =
  if editor.xTextView.isNil:
    return newTextStorage()
  textviews.attributedSubstringForRange(editor.xTextView, range)

method textEditorInputValidAttributesForMarkedText(
    editor: TextEditor
): seq[string] {.selector.} =
  if editor.xTextView.isNil:
    @ValidMarkedTextAttributes
  else:
    textviews.validAttributesForMarkedText(editor.xTextView)

method textEditorInputFirstRectForCharacterRange(
    editor: TextEditor, range: TextRange
): Rect {.selector.} =
  if editor.xTextView.isNil:
    return rect(0, 0, 0, 0)
  textviews.firstRectForCharacterRange(editor.xTextView, range)

method textEditorInputCharacterIndexForPoint(
    editor: TextEditor, point: Point
): int {.selector.} =
  if editor.xTextView.isNil:
    return -1
  textviews.characterIndexForPoint(editor.xTextView, point)

proc installTextEditorInputClientMethods(editor: TextEditor) =
  if editor.isNil:
    return
  discard
    editor.addMethod(selectors.textInputHasMarkedText, textEditorInputHasMarkedText)
  discard editor.addMethod(selectors.textInputMarkedRange, textEditorInputMarkedRange)
  discard
    editor.addMethod(selectors.textInputSelectedRange, textEditorInputSelectedRange)
  discard editor.addMethod(
    selectors.textInputAttributedSubstringForRange,
    textEditorInputAttributedSubstringForRange,
  )
  discard editor.addMethod(
    selectors.textInputValidAttributesForMarkedText,
    textEditorInputValidAttributesForMarkedText,
  )
  discard editor.addMethod(
    selectors.textInputFirstRectForCharacterRange,
    textEditorInputFirstRectForCharacterRange,
  )
  discard editor.addMethod(
    selectors.textInputCharacterIndexForPoint, textEditorInputCharacterIndexForPoint
  )

protocol DefaultTextEditorInput of TextInputProtocol:
  method insertText(editor: TextEditor, text: string) =
    if not editor.xTextView.isNil:
      editor.xTextView.insertTextValue(text)

  method setMarkedText(
      editor: TextEditor, text: string, selectedRange, replacementRange: TextRange
  ) =
    if not editor.xTextView.isNil:
      editor.xTextView.setMarkedTextValue(text, selectedRange, replacementRange)

  method unmarkText(editor: TextEditor) =
    if not editor.xTextView.isNil:
      editor.xTextView.unmarkMarkedText()

protocol DefaultTextEditorCommands of TextEditingCommandProtocol:
  method selectText(editor: TextEditor, args: ActionArgs) =
    editor.selectAllText()

  method selectAll(editor: TextEditor, args: ActionArgs) =
    editor.selectAllText()

  method copy(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      discard editor.xTextView.copyText()

  method cut(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      discard editor.xTextView.cutText()

  method paste(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      discard editor.xTextView.pasteText()

  method undo(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      discard editor.xTextView.undoText()

  method redo(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      discard editor.xTextView.redoText()

  method deleteBackward(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.deleteBackwardText()

  method deleteForward(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.deleteForwardText()

  method deleteWordBackward(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.deleteWordBackwardText()

  method deleteWordForward(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.deleteWordForwardText()

  method deleteToBeginningOfLine(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.deleteToBeginningOfLineText()

  method deleteToEndOfLine(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.deleteToEndOfLineText()

  method insertLineBreak(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.insertLineBreakText()

  method insertParagraphSeparator(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.insertParagraphSeparatorText()

  method moveLeft(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveLeftText()

  method moveRight(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveRightText()

  method moveUp(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveUpText()

  method moveDown(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveDownText()

  method moveWordLeft(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveWordLeftText()

  method moveWordRight(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveWordRightText()

  method moveWordBackward(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveWordLeftText()

  method moveWordForward(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveWordRightText()

  method moveToBeginningOfLine(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveToBeginningOfLineText()

  method moveToEndOfLine(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveToEndOfLineText()

  method moveToBeginningOfDocument(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveToBeginningOfDocumentText()

  method moveToEndOfDocument(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveToEndOfDocumentText()

  method moveLeftAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveLeftText(extending = true)

  method moveRightAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveRightText(extending = true)

  method moveUpAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveUpText(extending = true)

  method moveDownAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveDownText(extending = true)

  method moveWordLeftAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveWordLeftText(extending = true)

  method moveWordRightAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveWordRightText(extending = true)

  method moveWordBackwardAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveWordLeftText(extending = true)

  method moveWordForwardAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveWordRightText(extending = true)

  method moveToBeginningOfLineAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveToBeginningOfLineText(extending = true)

  method moveToEndOfLineAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveToEndOfLineText(extending = true)

  method moveToBeginningOfDocumentAndModifySelection(
      editor: TextEditor, args: ActionArgs
  ) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveToBeginningOfDocumentText(extending = true)

  method moveToEndOfDocumentAndModifySelection(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.moveToEndOfDocumentText(extending = true)

protocol DefaultTextEditorKeyCommands of KeyViewCommandProtocol:
  method insertNewline(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.insertTextValue("\n")

  method insertTab(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.insertTextValue("\t")

  method insertBacktab(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.insertTextValue("\t")

  method insertNewlineIgnoringFieldEditor(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.insertTextValue("\n")

  method insertTabIgnoringFieldEditor(editor: TextEditor, args: ActionArgs) =
    if not editor.xTextView.isNil:
      editor.xTextView.insertTextValue("\t")

protocol DefaultTextEditorAccessibility of AccessibilityProtocol:
  method accessibilityRole(editor: TextEditor): AccessibilityRole =
    arScrollArea

  method accessibilityChildren(editor: TextEditor): seq[View] =
    if editor.xTextView.isNil:
      @[]
    else:
      @[View(editor.xTextView)]

  method isAccessibilityElement(editor: TextEditor): bool =
    false

proc initTextEditorFields*(
    editor: TextEditor,
    value = "",
    frame: Rect = AutoRect,
    richText = true,
    wraps = true,
) =
  initViewFields(editor, frame)
  editor.background = color(0.0, 0.0, 0.0, 0.0)
  editor.xTextInsets = insets(6.0, 7.0, 6.0, 7.0)
  editor.xWraps = wraps
  editor.xMinimumDocumentSize =
    initSize(DefaultTextEditorWidth, DefaultTextEditorHeight)
  editor.setAcceptsFirstResponder(true)
  editor.xTextView = newTextView(value)
  editor.xTextView.richText = richText
  editor.xTextView.textContainer =
    initTextContainer(initSize(0.0, 0.0), editor.xTextInsets, wraps)
  editor.xScrollView = newScrollView(documentView = editor.xTextView)
  editor.xScrollView.hasVerticalScroller = true
  editor.xScrollView.hasHorizontalScroller = not wraps
  editor.xScrollView.autohidePolicy = sapWhenNeeded
  editor.xScrollView.borderType = svbBezelBorder
  editor.xScrollView.drawsBackground = true
  editor.addSubview(editor.xScrollView)
  editor.xTextView.connect(textDidChange, editor, textEditorTextDidChange)
  discard editor.withProtocol(DefaultTextEditorLayout)
  discard editor.withProtocol(DefaultTextEditorResponder)
  discard editor.withProtocol(DefaultTextEditorView)
  discard editor.withProtocol(DefaultTextEditorInput)
  discard editor.withProtocol(DefaultTextEditorCommands)
  discard editor.withProtocol(DefaultTextEditorKeyCommands)
  discard editor.withProtocol(DefaultTextEditorAccessibility)
  editor.installTextEditorInputClientMethods()
  editor.applyInitialFrame(frame)
  editor.updateTextEditorLayout()

proc newTextEditor*(
    value = "", frame: Rect = AutoRect, richText = true, wraps = true
): TextEditor =
  result = TextEditor()
  initTextEditorFields(result, value, frame, richText, wraps)
