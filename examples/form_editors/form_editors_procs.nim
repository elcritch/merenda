## Run `nim ic -r examples/form_editors/form_editors_procs.nim` to try named callbacks.
## Async Save writes accepted data to a private temporary directory.
## Save / Close is a separate in-memory draft checkpoint.
import std/[os, tempfiles]
import merenda/nimkit
import merenda/nimkit/directviews
import ./form_drafts
import ./form_editors_shared

type FormPanel = ref object of Responder
  draft: FormDraft
  savePath: string
  pending: FormValidation

proc newFormPanel(draft: FormDraft, savePath: string): FormPanel =
  result = FormPanel(draft: draft, savePath: savePath)
  initResponder(result)

proc apply(_: Responder, panel: FormPanel) =
  discard panel.draft.apply()

proc undoAccepted(_: Responder, panel: FormPanel) =
  discard panel.draft.document.undoManagerFor().performUndo()

proc cancel(_: Responder, panel: FormPanel) =
  panel.draft.cancel()

proc saveAccepted(_: Responder, panel: FormPanel) =
  discard panel.draft.document.startSave(panel.savePath)

proc saveDraftAndClose(_: Responder, panel: FormPanel) =
  discard panel.draft.saveAndClose()

proc queueValidation(_: Responder, panel: FormPanel) =
  panel.pending = panel.draft.requestValidation()

proc completeValidation(_: Responder, panel: FormPanel) =
  discard panel.pending.complete()

proc acceptExternalValue(_: Responder, panel: FormPanel) =
  panel.draft.document.accept(99)

proc formActions(panel: FormPanel): DirectView =
  result = newDirectView()
  result.viewBody:
    VStack:
      HStack:
        Button("Apply", focusable = false):
          this.onAction(panel, apply)
        Button("Undo", focusable = false):
          this.onAction(panel, undoAccepted)
        Button("Cancel", focusable = false):
          this.onAction(panel, cancel)
        Button("Async Save accepted", focusable = false):
          this.onAction(panel, saveAccepted)
        Button("Save / Close", focusable = false):
          this.onAction(panel, saveDraftAndClose)
      HStack:
        Button("Queue validation", focusable = false):
          this.onAction(panel, queueValidation)
        Button("Complete", focusable = false):
          this.onAction(panel, completeValidation)
        Button("External 99", focusable = false):
          this.onAction(panel, acceptExternalValue)

proc runFormEditorsProcs*() =
  let savePath = createTempDir("merenda-form-save-", "") / "accepted.txt"
  let document = newFormDocument(12)
  let shared = newFormDraft(document)
  let local = newFormDraft(document)
  # Button actions refer to these panels weakly. The locals own them while the window runs.
  let first = newFormPanel(shared, savePath)
  let second = newFormPanel(shared, savePath)
  let third = newFormPanel(local, savePath)
  let root = newFormEditorsLayout(
    savePath, shared, local, formActions(first), formActions(second), formActions(third)
  )
  sharedApplication().runWindow(
    newWindow("Form drafts: procs", frame = rect(80, 80, 850, 650)), root
  )
  shared.dispose()
  local.dispose()

when isMainModule and not defined(merendaTests):
  runFormEditorsProcs()
