## FormView is an ordinary leaf composed alongside either declarative host.
## Async Save writes only accepted data into a private temporary directory.
## Save / Close is the separate in-memory draft checkpoint.
import std/[os, tempfiles]
import sigils/[core, reactive]
import merenda/nimkit
import ./form_drafts

type FormPanel = ref object of Responder
  draft: FormDraft
  savePath: string
  scope: BindingScope
  form: FormView
  pending: FormValidation

proc newFormPanel(draft: FormDraft, savePath: string): FormPanel =
  result = FormPanel(draft: draft, savePath: savePath)
  initResponder(result)

proc configureForm(form: FormView, scope: BindingScope, draft: FormDraft) =
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
  scope.bindTextField("number", draft.raw, draft, 0, rawText, field, editText)
  scope.bindValue("accepted", draft.document.accepted, Label(form.rows[2].field)) do(
    label: Label, value: int
  ):
    label.stringValue = $value
  scope.bindValue("saveStatus", draft.document.saveStatus, Label(form.rows[3].field)) do(
    label: Label, value: string
  ):
    label.stringValue = value
  scope.bindValue("status", draft.status, status) do(label: Label, value: string):
    label.stringValue = value

proc newDraftForm*(draft: FormDraft): DirectView =
  ## The FormView node owns its subscriptions; the draft outlives this widget.
  result = newDirectView()
  result.viewBody:
    FormView:
      configureForm(this, bindingScope, draft)

proc apply(panel: FormPanel) =
  discard panel.draft.apply()

proc cancel(panel: FormPanel) =
  panel.draft.cancel()

proc queue(panel: FormPanel) =
  panel.pending = panel.draft.requestValidation()

proc complete(panel: FormPanel) =
  discard panel.pending.complete()

proc external(panel: FormPanel) =
  panel.draft.document.accept(99)

proc undo(panel: FormPanel) =
  discard panel.draft.document.undoManagerFor().performUndo()

proc saveFile(panel: FormPanel) =
  discard panel.draft.document.startSave(panel.savePath)

proc save(panel: FormPanel) =
  discard panel.draft.saveAndClose()

proc directActions(panel: FormPanel): DirectView =
  result = newDirectView()
  result.viewBody:
    VStack:
      HStack:
        Button("Apply", acceptsFirstResponder = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.apply()
        Button("Undo", acceptsFirstResponder = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.undo()
        Button("Cancel", acceptsFirstResponder = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.cancel()
        Button("Async Save accepted", acceptsFirstResponder = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.saveFile()
        Button("Save / Close", acceptsFirstResponder = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.save()
      HStack:
        Button("Queue validation", acceptsFirstResponder = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.queue()
        Button("Complete", acceptsFirstResponder = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.complete()
        Button("External 99", acceptsFirstResponder = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.external()

proc specActions(panel: FormPanel): DeclarativeView =
  let body = viewBody:
    VStack:
      HStack:
        Button("Apply", focusable = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.apply()
        Button("Undo", focusable = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.undo()
        Button("Cancel", focusable = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.cancel()
        Button("Async Save accepted", focusable = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.saveFile()
        Button("Save / Close", focusable = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.save()
      HStack:
        Button("Queue validation", focusable = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.queue()
        Button("Complete", focusable = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.complete()
        Button("External 99", focusable = false):
          onAction(panel) do(p: FormPanel, sender: DynamicAgent):
            p.external()
  newDeclarativeView(body)

proc runFormEditors*() =
  let savePath = createTempDir("merenda-form-save-", "") / "accepted.txt"
  let document = newFormDocument(12)
  # Use the same draft here for shared edits; make a second draft for local edits.
  let shared = newFormDraft(document)
  let first = newFormPanel(shared, savePath)
  let second = newFormPanel(shared, savePath)
  let local = newFormPanel(newFormDraft(document), savePath)
  let root = newStackView(laVertical)
  root.spacing = 12
  root.edgeInsets = insets(12)
  root.addArrangedSubview(newLabel("Async Save writes accepted data to: " & savePath))
  root.addArrangedSubview(
    newLabel("Shared draft: DirectView"),
    newDraftForm(first.draft),
    directActions(first),
  )
  root.addArrangedSubview(
    newLabel("Shared draft: ViewSpec toolbar + DirectView form"),
    newDraftForm(second.draft),
    specActions(second),
  )
  root.addArrangedSubview(
    newLabel("Independent local draft"), newDraftForm(local.draft), directActions(local)
  )
  sharedApplication().runWindow(
    newWindow("Form drafts", frame = rect(80, 80, 850, 650)), root
  )
  shared.dispose()
  local.draft.dispose()

when isMainModule and not defined(merendaTests):
  runFormEditors()
