import ./events
import ./responders
import ./selectors

type FieldEditor* = ref object of Responder
  xClient: Responder

protocol FieldEditorClient {.selectorScope: protocol.}:
  method usesFieldEditor*(editor: FieldEditor): bool {.optional.}
  method shouldBeginEditing*(editor: FieldEditor): bool {.optional.}
  method didBeginEditing*(editor: FieldEditor) {.optional.}
  method shouldEndEditing*(editor: FieldEditor): bool {.optional.}
  method didEndEditing*(editor: FieldEditor) {.optional.}

proc client*(editor: FieldEditor): Responder =
  if editor.isNil: nil else: editor.xClient

proc wantsFieldEditor*(client: Responder, editor: FieldEditor): bool =
  if client.isNil:
    return false
  let wants = client.trySendLocal(usesFieldEditor(), editor)
  wants.isSome and wants.get()

proc clientShouldBeginEditing(client: Responder, editor: FieldEditor): bool =
  let shouldBegin = client.trySendLocal(shouldBeginEditing(), editor)
  shouldBegin.isNone or shouldBegin.get()

proc clientShouldEndEditing(client: Responder, editor: FieldEditor): bool =
  let shouldEnd = client.trySendLocal(shouldEndEditing(), editor)
  shouldEnd.isNone or shouldEnd.get()

proc canEdit*(editor: FieldEditor, client: Responder): bool =
  (not editor.isNil) and client.wantsFieldEditor(editor) and
    client.clientShouldBeginEditing(editor)

proc beginEditing*(editor: FieldEditor, client: Responder): bool =
  if editor.isNil or client.isNil:
    return false
  if editor.xClient == client:
    return true
  if not editor.canEdit(client):
    return false
  editor.xClient = client
  discard client.sendLocalIfHandled(didBeginEditing(), editor)
  true

proc endEditing*(editor: FieldEditor): bool =
  if editor.isNil or editor.xClient.isNil:
    return true
  let client = editor.xClient
  if not client.clientShouldEndEditing(editor):
    return false
  editor.xClient = nil
  discard client.sendLocalIfHandled(didEndEditing(), editor)
  true

proc sendCommandToClient(
    editor: FieldEditor, selector: CommandSelector, args: ActionArgs
) =
  let client = editor.client()
  if not client.isNil:
    discard client.sendLocalIfHandled(selector, args)

protocol DefaultFieldEditorResponder of ResponderProtocol:
  method acceptsFirstResponder(editor: FieldEditor): bool =
    true

  method shouldResignFirstResponder(editor: FieldEditor): bool =
    editor.endEditing()

  method resignFirstResponder(editor: FieldEditor): bool =
    editor.endEditing()

protocol DefaultFieldEditorEvents of ResponderEventProtocol:
  method keyDown(editor: FieldEditor, event: KeyEvent) =
    let client = editor.client()
    if not client.isNil:
      discard client.sendLocalIfHandled(keyDown(), event)

protocol DefaultFieldEditorInput of TextInputProtocol:
  method insertText(editor: FieldEditor, text: string) =
    let client = editor.client()
    if not client.isNil:
      discard client.sendLocalIfHandled(insertText(), text)

protocol DefaultFieldEditorCommands of TextEditingCommandProtocol:
  method selectText(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(selectText(), args)

  method selectAll(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(selectAll(), args)

  method deleteBackward(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(deleteBackward(), args)

  method deleteForward(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(deleteForward(), args)

  method deleteWordBackward(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(deleteWordBackward(), args)

  method deleteWordForward(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(deleteWordForward(), args)

  method moveLeft(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveLeft(), args)

  method moveRight(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveRight(), args)

  method moveWordLeft(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveWordLeft(), args)

  method moveWordRight(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveWordRight(), args)

  method moveToBeginningOfLine(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveToBeginningOfLine(), args)

  method moveToEndOfLine(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveToEndOfLine(), args)

  method moveLeftAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveLeftAndModifySelection(), args)

  method moveRightAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveRightAndModifySelection(), args)

  method moveWordLeftAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveWordLeftAndModifySelection(), args)

  method moveWordRightAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveWordRightAndModifySelection(), args)

  method moveToBeginningOfLineAndModifySelection(
      editor: FieldEditor, args: ActionArgs
  ) =
    editor.sendCommandToClient(moveToBeginningOfLineAndModifySelection(), args)

  method moveToEndOfLineAndModifySelection(editor: FieldEditor, args: ActionArgs) =
    editor.sendCommandToClient(moveToEndOfLineAndModifySelection(), args)

proc initFieldEditorFields*(editor: FieldEditor) =
  initResponder(editor)
  editor.setAcceptsFirstResponder(true)
  discard editor.withProtocol(DefaultFieldEditorResponder)
  discard editor.withProtocol(DefaultFieldEditorEvents)
  discard editor.withProtocol(DefaultFieldEditorInput)
  discard editor.withProtocol(DefaultFieldEditorCommands)

proc newFieldEditor*(): FieldEditor =
  result = FieldEditor()
  initFieldEditorFields(result)
