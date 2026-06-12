import ./events
import ./responders
import ./selectors
import ./textstorage
import ./texttypes
import ./textviews
import ./types

type FieldEditor* = ref object of TextView
  xClient: Responder
  xOriginalString: string

protocol FieldEditorClient {.selectorScope: protocol.}:
  method fieldEditorForClient*(defaultEditor: FieldEditor): FieldEditor {.optional.}
  method usesFieldEditor*(editor: FieldEditor): bool {.optional.}
  method stringForFieldEditor*(editor: FieldEditor): string {.optional.}
  method attributedTextForEditor*(editor: FieldEditor): TextStorage {.optional.}
  method setStringFromFieldEditor*(editor: FieldEditor, value: string) {.optional.}
  method setAttributedTextFromEditor*(
    editor: FieldEditor, value: TextStorage
  ) {.optional.}

  method didChangeTextInEditor*(editor: FieldEditor) {.optional.}
  method didChangeFocusInEditor*(editor: FieldEditor) {.optional.}
  method shouldBeginEditing*(editor: FieldEditor): bool {.optional.}
  method didBeginEditing*(editor: FieldEditor) {.optional.}
  method shouldEndEditing*(editor: FieldEditor): bool {.optional.}
  method didEndEditing*(editor: FieldEditor) {.optional.}
  method didEndEditingReason*(editor: FieldEditor, reason: TextEditReason) {.optional.}
  method didEndEditingMovement*(
    editor: FieldEditor, movement: TextEditMovement
  ) {.optional.}

proc client*(editor: FieldEditor): Responder =
  if editor.isNil: nil else: editor.xClient

proc wantsFieldEditor*(client: Responder, editor: FieldEditor): bool =
  if client.isNil:
    return false
  let wants = client.trySendLocal(usesFieldEditor(), editor)
  wants.isSome and wants.get()

proc fieldEditorForClient*(client: Responder, defaultEditor: FieldEditor): FieldEditor =
  if client.isNil:
    return defaultEditor
  let editor = client.trySendLocal(fieldEditorForClient(), defaultEditor)
  if editor.isSome and not editor.get().isNil:
    editor.get()
  else:
    defaultEditor

proc clientShouldBeginEditing(client: Responder, editor: FieldEditor): bool =
  let shouldBegin = client.trySendLocal(shouldBeginEditing(), editor)
  shouldBegin.isNone or shouldBegin.get()

proc clientShouldEndEditing(client: Responder, editor: FieldEditor): bool =
  let shouldEnd = client.trySendLocal(shouldEndEditing(), editor)
  shouldEnd.isNone or shouldEnd.get()

proc canEdit*(editor: FieldEditor, client: Responder): bool =
  (not editor.isNil) and client.wantsFieldEditor(editor) and
    client.clientShouldBeginEditing(editor)

proc loadClientText(editor: FieldEditor, client: Responder) =
  let storage = client.trySendLocal(attributedTextForEditor(), editor)
  if storage.isSome and not storage.get().isNil:
    editor.textStorage = storage.get().copyTextStorage()
  else:
    let text = client.trySendLocal(stringForFieldEditor(), editor)
    editor.stringValue =
      if text.isSome:
        text.get()
      else:
        ""
  editor.xOriginalString = editor.stringValue()

proc notifyClientChanged(editor: FieldEditor) =
  let client = editor.client()
  if client.isNil:
    return
  discard client.sendLocalIfHandled(
    setAttributedTextFromEditor(), (editor: editor, value: editor.textStorage())
  )
  discard client.sendLocalIfHandled(
    setStringFromFieldEditor(), (editor: editor, value: editor.stringValue())
  )
  discard client.sendLocalIfHandled(didChangeTextInEditor(), editor)

proc validateEditing*(editor: FieldEditor): bool =
  if editor.isNil or editor.client().isNil:
    return true
  editor.notifyClientChanged()
  result = true

proc notifyClientFocusChanged(editor: FieldEditor) =
  let client = editor.client()
  if client.isNil:
    return
  discard client.sendLocalIfHandled(didChangeFocusInEditor(), editor)

proc finishEditing(
    editor: FieldEditor, reason: TextEditReason, movement = temNone
): bool =
  if editor.isNil or editor.xClient.isNil:
    return true
  let client = editor.xClient
  if not client.clientShouldEndEditing(editor):
    return false
  if reason == terCancel:
    editor.stringValue = editor.xOriginalString
  else:
    editor.notifyClientChanged()
  editor.xClient = nil
  discard client.sendLocalIfHandled(didEndEditing(), editor)
  discard
    client.sendLocalIfHandled(didEndEditingReason(), (editor: editor, reason: reason))
  discard client.sendLocalIfHandled(
    didEndEditingMovement(), (editor: editor, movement: movement)
  )
  result = true

proc beginEditing*(editor: FieldEditor, client: Responder, focusVisible = true): bool =
  if editor.isNil or client.isNil:
    return false
  if editor.xClient == client:
    return true
  if not editor.canEdit(client):
    return false
  editor.loadClientText(client)
  editor.xClient = client
  editor.focused = true
  editor.focusVisible = focusVisible
  discard client.sendLocalIfHandled(didBeginEditing(), editor)
  editor.notifyClientFocusChanged()
  result = true

proc endEditing*(editor: FieldEditor): bool =
  editor.finishEditing(terFocusChange)

proc commitEditing*(editor: FieldEditor): bool =
  editor.finishEditing(terCommit)

proc cancelEditing*(editor: FieldEditor): bool =
  editor.finishEditing(terCancel)

protocol DefaultFieldEditorResponder of ResponderProtocol:
  method acceptsFirstResponder(editor: FieldEditor): bool =
    true

  method shouldResignFirstResponder(editor: FieldEditor): bool =
    let client = editor.client()
    client.isNil or client.clientShouldEndEditing(editor)

  method resignFirstResponder(editor: FieldEditor): bool =
    editor.endEditing()

  method setFirstResponderFocusState(editor: FieldEditor, focused, focusVisible: bool) =
    if editor.isNil:
      return
    let changed =
      editor.isFocused() != focused or editor.isFocusVisible() != focusVisible
    if not changed:
      return
    editor.focused = focused
    editor.focusVisible = focusVisible
    editor.notifyClientFocusChanged()

protocol DefaultFieldEditorView of ViewProtocol:
  method canBecomeKeyView(editor: FieldEditor): bool =
    false

protocol DefaultFieldEditorEvents of ResponderEventProtocol:
  method mouseDown(editor: FieldEditor, event: MouseEvent): bool =
    if event.button == mbPrimary and (editor.editable or editor.selectable):
      editor.setCursor(editor.textIndexAtPoint(event.location))
      return true

  method keyDown(editor: FieldEditor, event: KeyEvent): bool =
    if editor.editable and event.text.isInsertableText():
      TextView(editor).insertTextValue(event.text)
      editor.notifyClientChanged()
      return true

protocol DefaultFieldEditorInput of TextInputProtocol:
  method insertText(editor: FieldEditor, text: string) =
    if text.isInsertableText():
      TextView(editor).insertTextValue(text)
      editor.notifyClientChanged()

  method setMarkedText(
      editor: FieldEditor, text: string, selectedRange, replacementRange: TextRange
  ) =
    TextView(editor).setMarkedTextValue(text, selectedRange, replacementRange)
    editor.notifyClientChanged()

  method unmarkText(editor: FieldEditor) =
    TextView(editor).unmarkMarkedText()

protocol DefaultFieldEditorCommands of TextEditingCommandProtocol:
  method selectText(editor: FieldEditor, args: ActionArgs) =
    editor.selectAllText()

  method selectAll(editor: FieldEditor, args: ActionArgs) =
    editor.selectAllText()

  method copy(editor: FieldEditor, args: ActionArgs) =
    discard editor.copyText()

  method cut(editor: FieldEditor, args: ActionArgs) =
    if editor.cutText():
      editor.notifyClientChanged()

  method paste(editor: FieldEditor, args: ActionArgs) =
    if editor.pasteText():
      editor.notifyClientChanged()

  method undo(editor: FieldEditor, args: ActionArgs) =
    if editor.undoText():
      editor.notifyClientChanged()

  method redo(editor: FieldEditor, args: ActionArgs) =
    if editor.redoText():
      editor.notifyClientChanged()

  method deleteBackward(editor: FieldEditor, args: ActionArgs) =
    editor.deleteBackwardText()
    editor.notifyClientChanged()

  method deleteForward(editor: FieldEditor, args: ActionArgs) =
    editor.deleteForwardText()
    editor.notifyClientChanged()

  method deleteWordBackward(editor: FieldEditor, args: ActionArgs) =
    editor.deleteWordBackwardText()
    editor.notifyClientChanged()

  method deleteWordForward(editor: FieldEditor, args: ActionArgs) =
    editor.deleteWordForwardText()
    editor.notifyClientChanged()

  method moveLeft(editor: FieldEditor, args: ActionArgs) =
    editor.moveLeftText()

  method moveRight(editor: FieldEditor, args: ActionArgs) =
    editor.moveRightText()

  method moveWordLeft(editor: FieldEditor, args: ActionArgs) =
    editor.moveWordLeftText()

  method moveWordRight(editor: FieldEditor, args: ActionArgs) =
    editor.moveWordRightText()

  method moveToBeginningOfLine(editor: FieldEditor, args: ActionArgs) =
    editor.moveToBeginningOfLineText()

  method moveToEndOfLine(editor: FieldEditor, args: ActionArgs) =
    editor.moveToEndOfLineText()

  method moveLeftAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.moveLeftText(extending = true)

  method moveRightAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.moveRightText(extending = true)

  method moveWordLeftAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.moveWordLeftText(extending = true)

  method moveWordRightAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.moveWordRightText(extending = true)

  method moveToBeginningOfLineAndModifySelection(
      editor: FieldEditor, args: ActionArgs
  ) =
    editor.moveToBeginningOfLineText(extending = true)

  method moveToEndOfLineAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.moveToEndOfLineText(extending = true)

protocol DefaultFieldEditorKeyCommands of KeyViewCommandProtocol:
  method insertNewline(editor: FieldEditor, args: ActionArgs) =
    discard editor.finishEditing(terCommit, temReturn)

  method insertTab(editor: FieldEditor, args: ActionArgs) =
    discard editor.finishEditing(terCommit, temTab)

  method insertBacktab(editor: FieldEditor, args: ActionArgs) =
    discard editor.finishEditing(terCommit, temBacktab)

  method insertNewlineIgnoringFieldEditor(editor: FieldEditor, args: ActionArgs) =
    TextView(editor).insertTextValue("\n")
    editor.notifyClientChanged()

  method insertTabIgnoringFieldEditor(editor: FieldEditor, args: ActionArgs) =
    TextView(editor).insertTextValue("\t")
    editor.notifyClientChanged()

protocol DefaultFieldEditorDrawing of ViewDrawingProtocol:
  method draw(editor: FieldEditor, context: DrawContext) =
    TextView(editor).drawTextViewContents(context)

proc initFieldEditorFields*(editor: FieldEditor) =
  initTextViewFields(editor, installDefaultProtocols = false)
  editor.background = initColor(0.0, 0.0, 0.0, 0.0)
  editor.editable = true
  editor.selectable = true
  editor.richText = true
  editor.fieldEditor = true
  editor.setAcceptsFirstResponder(true)
  discard editor.withProtocol(DefaultFieldEditorResponder)
  discard editor.withProtocol(DefaultFieldEditorView)
  discard editor.withProtocol(DefaultFieldEditorEvents)
  discard editor.withProtocol(DefaultFieldEditorInput)
  discard editor.withProtocol(DefaultFieldEditorCommands)
  discard editor.withProtocol(DefaultFieldEditorKeyCommands)
  discard editor.withProtocol(DefaultFieldEditorDrawing)

proc newFieldEditor*(): FieldEditor =
  result = FieldEditor()
  initFieldEditorFields(result)
