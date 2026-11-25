## Run `nim ic -r examples/form_editors_protocol.nim` to try protocol selectors.
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

proc newFormPanel(draft: FormDraft, savePath: string): FormPanel =
  result = FormPanel(draft: draft, savePath: savePath)
  initResponder(result)
  discard result.withProto()

proc formActions(panel: FormPanel): DirectView =
  result = newDirectView()
  result.viewBody:
    VStack:
      HStack:
        Button("Apply", focusable = false):
          this.onAction(panel, apply())
        Button("Undo", focusable = false):
          this.onAction(panel, undoAccepted())
        Button("Cancel", focusable = false):
          this.onAction(panel, cancel())
        Button("Async Save accepted", focusable = false):
          this.onAction(panel, saveAccepted())
        Button("Save / Close", focusable = false):
          this.onAction(panel, saveDraftAndClose())
      HStack:
        Button("Queue validation", focusable = false):
          this.onAction(panel, queueValidation())
        Button("Complete", focusable = false):
          this.onAction(panel, completeValidation())
        Button("External 99", focusable = false):
          this.onAction(panel, acceptExternalValue())

proc runFormEditorsProtocol*() =
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
    newWindow("Form drafts: protocol", frame = rect(80, 80, 850, 650)), root
  )
  shared.dispose()
  local.dispose()

when isMainModule and not defined(merendaTests):
  runFormEditorsProtocol()
