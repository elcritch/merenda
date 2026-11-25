## Run `nim ic -r examples/form_editors.nim` to try form actions
## registered as protocol selectors.
import std/[os, tempfiles]
import merenda/nimkit
import merenda/nimkit/directviews
import ./form_drafts

type FormPanel = ref object of Responder
  draft: FormDraft
  savePath: string
  pending: FormValidation

proc configureForm(form: FormView, draft: FormDraft) =
  if form.rows.len == 0:
    let field = newTextField("")
    field.identifier = "amount"
    field.objectParseContext =
      initObjectParseContext(expectedKind = ovInt, emptyPolicy = oepInvalid)
    let status = newLabel("")
    status.identifier = "status"
    form.minFieldWidth = 180
    form.addRow(newLabel("Amount"), field)
    form.addRow(newLabel("Status"), status)
    form.addRow(newLabel("Accepted"), newLabel(""))
    form.addRow(newLabel("File save"), newLabel(""))
  let field = TextField(form.rows[0].field)
  let status = Label(form.rows[1].field)
  form.bindTextField("number", draft.raw, draft, 0, rawText, field, editText)
  form.bindValue("accepted", draft.document.accepted, Label(form.rows[2].field)) do(
    label: Label, value: int
  ):
    label.stringValue = $value
  form.bindValue("saveStatus", draft.document.saveStatus, Label(form.rows[3].field)) do(
    label: Label, value: string
  ):
    label.stringValue = value
  form.bindValue("status", draft.status, status) do(label: Label, value: string):
    label.stringValue = value

proc newDraftForm*(draft: FormDraft): DirectView =
  ## The FormView node owns the subscriptions, and the draft outlives the widget.
  result = newDirectView()
  result.viewBody:
    FormView:
      configureForm(this, draft)

protocol FormEditorActions from FormPanel:
  method apply(panel: FormPanel, args: ActionArgs) =
    discard panel.draft.apply()

  method undoAccepted(panel: FormPanel, args: ActionArgs) =
    discard panel.draft.document.undoManagerFor().performUndo()

  method cancel(panel: FormPanel, args: ActionArgs) =
    panel.draft.cancel()

  method saveAccepted(panel: FormPanel, args: ActionArgs) =
    discard panel.draft.document.startSave(panel.savePath)

  method saveDraftAndClose(panel: FormPanel, args: ActionArgs) =
    discard panel.draft.saveAndClose()

  method queueValidation(panel: FormPanel, args: ActionArgs) =
    panel.pending = panel.draft.requestValidation()

  method completeValidation(panel: FormPanel, args: ActionArgs) =
    discard panel.pending.complete()

  method acceptExternalValue(panel: FormPanel, args: ActionArgs) =
    panel.draft.document.accept(99)

proc formActions(panel: FormPanel): DirectView =
  result = newDirectView()
  result.viewBody:
    HStack:
      Button("Apply", acceptsFirstResponder = false):
        onAction(panel, apply())
      Button("Undo", acceptsFirstResponder = false):
        onAction(panel, undoAccepted())
      Button("Cancel", acceptsFirstResponder = false):
        onAction(panel, cancel())
      Button("Async Save accepted", acceptsFirstResponder = false):
        onAction(panel, saveAccepted())
      Button("Save / Close", acceptsFirstResponder = false):
        onAction(panel, saveDraftAndClose())
    HStack:
      Button("Queue validation", acceptsFirstResponder = false):
        onAction(panel, queueValidation())
      Button("Complete", acceptsFirstResponder = false):
        onAction(panel, completeValidation())
      Button("External 99", acceptsFirstResponder = false):
        onAction(panel, acceptExternalValue())

proc runFormEditors*() =
  let
    document = newFormDocument(12)
    draft = newFormDraft(document)
    savePath = createTempDir("merenda-form-save-", "") / "accepted.txt"
    panel = FormPanel(draft: draft, savePath: savePath)
  initResponder(panel)
  discard panel.withProto()

  let root = newStackView(laVertical)
  root.spacing = 12
  root.edgeInsets = insets(12)
  root.addArrangedSubview(
    newLabel("Async Save writes accepted data to: " & savePath),
    newDraftForm(draft),
    formActions(panel),
  )
  sharedApplication().runWindow(
    newWindow("Form editor protocol", frame = rect(80, 80, 800, 330)), root
  )
  draft.dispose()

when isMainModule and not defined(merendaTests):
  runFormEditors()
