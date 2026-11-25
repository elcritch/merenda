## Run `nim ic -r examples/form_editors_procs.nim` to compare named callbacks
## in DirectView and ViewSpec toolbars around the same FormView.
## Async Save writes only accepted data into a private temporary directory.
## Save / Close is the separate in-memory draft checkpoint.
import std/[os, tempfiles]
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/declarative
import merenda/nimkit/directviews
import ./form_drafts
from ./form_editors import newDraftForm

type FormPanel = ref object of Responder
  draft: FormDraft
  savePath: string
  scope: BindingScope
  form: FormView
  pending: FormValidation

proc newFormPanel(draft: FormDraft, savePath: string): FormPanel =
  result = FormPanel(draft: draft, savePath: savePath)
  initResponder(result)

proc apply(_: Responder, panel: FormPanel) =
  discard panel.draft.apply()

proc cancel(_: Responder, panel: FormPanel) =
  panel.draft.cancel()

proc queue(_: Responder, panel: FormPanel) =
  panel.pending = panel.draft.requestValidation()

proc complete(_: Responder, panel: FormPanel) =
  discard panel.pending.complete()

proc external(_: Responder, panel: FormPanel) =
  panel.draft.document.accept(99)

proc undo(_: Responder, panel: FormPanel) =
  discard panel.draft.document.undoManagerFor().performUndo()

proc saveFile(_: Responder, panel: FormPanel) =
  discard panel.draft.document.startSave(panel.savePath)

proc save(_: Responder, panel: FormPanel) =
  discard panel.draft.saveAndClose()

proc directActions(panel: FormPanel): DirectView =
  result = newDirectView()
  result.viewBody:
    VStack:
      HStack:
        Button("Apply", acceptsFirstResponder = false):
          onAction(panel, apply)
        Button("Undo", acceptsFirstResponder = false):
          onAction(panel, undo)
        Button("Cancel", acceptsFirstResponder = false):
          onAction(panel, cancel)
        Button("Async Save accepted", acceptsFirstResponder = false):
          onAction(panel, saveFile)
        Button("Save / Close", acceptsFirstResponder = false):
          onAction(panel, save)
      HStack:
        Button("Queue validation", acceptsFirstResponder = false):
          onAction(panel, queue)
        Button("Complete", acceptsFirstResponder = false):
          onAction(panel, complete)
        Button("External 99", acceptsFirstResponder = false):
          onAction(panel, external)

type FormAction = proc(sender: Responder, panel: FormPanel) {.nimcall.}

proc specAction(panel: FormPanel, handler: FormAction): ViewAction =
  viewAction(panel, handler) do(p: FormPanel, action: FormAction, sender: DynamicAgent):
    if sender of Responder:
      action(Responder(sender), p)

proc specActions(panel: FormPanel): DeclarativeView =
  let body = viewBody:
    VStack:
      HStack:
        Button("Apply", focusable = false, onAction = specAction(panel, apply))
        Button("Undo", focusable = false, onAction = specAction(panel, undo))
        Button("Cancel", focusable = false, onAction = specAction(panel, cancel))
        Button(
          "Async Save accepted",
          focusable = false,
          onAction = specAction(panel, saveFile),
        )
        Button("Save / Close", focusable = false, onAction = specAction(panel, save))
      HStack:
        Button(
          "Queue validation", focusable = false, onAction = specAction(panel, queue)
        )
        Button("Complete", focusable = false, onAction = specAction(panel, complete))
        Button("External 99", focusable = false, onAction = specAction(panel, external))
  newDeclarativeView(body)

proc runFormEditorsProcs*() =
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
  runFormEditorsProcs()
