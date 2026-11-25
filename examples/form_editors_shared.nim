## Shared form construction and layout for the two action-binding examples.
import merenda/nimkit
import merenda/nimkit/directviews
import ./form_drafts

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

proc newFormEditorsLayout*(
    savePath: string,
    shared, local: FormDraft,
    firstActions, secondActions, localActions: DirectView,
): StackView =
  result = newStackView(laVertical)
  result.spacing = 12
  result.edgeInsets = insets(12)
  result.addArrangedSubview(
    newLabel("Async Save writes accepted data to: " & savePath),
    newLabel("Shared draft: first panel"),
    newDraftForm(shared),
    firstActions,
    newLabel("Shared draft: second panel"),
    newDraftForm(shared),
    secondActions,
    newLabel("Independent local draft"),
    newDraftForm(local),
    localActions,
  )
