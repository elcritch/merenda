import std/[monotimes, os, tempfiles, times, unittest]
import sigils/[core, reactive, threads]
import merenda/nimkit
import merenda/nimkit/directviews
import ../../examples/form_editors/[form_drafts, form_editors_shared]

proc waitForSave(document: FormDocument): bool =
  let deadline = getMonoTime() + initDuration(seconds = 60)
  while document.saveInFlight and getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    if document.saveInFlight:
      sleep(1)
  discard getCurrentSigilThread().pollAll(NonBlocking)
  result = not document.saveInFlight

suite "form draft policy":
  test "independent and explicitly shared drafts retain raw incomplete input":
    let document = newFormDocument(12)
    let first = newFormDraft(document)
    let shared = first
    let local = newFormDraft(document)
    first.edit("-")
    check shared.raw{} == "-"
    check local.raw{} == "12"
    check not first.apply()
    check document.value == 12
    check first.raw{} == "-"
    first.edit("42")
    check first.apply()
    check document.value == 42
    check local.conflict()
    local.cancel()
    check local.raw{} == "42"

  test "external accepted update conflicts until cancel":
    let document = newFormDocument(1)
    let draft = newFormDraft(document)
    draft.edit("2")
    document.accept(3)
    check draft.conflict()
    check not draft.apply()
    check draft.raw{} == "2"
    check document.value == 3
    draft.cancel()
    check draft.raw{} == "3"
    check not draft.conflict()

  test "delayed results belong to the session and snapshot":
    let document = newFormDocument(1)
    let draft = newFormDraft(document)
    draft.edit("-")
    let stale = draft.requestValidation()
    draft.edit("4")
    check not stale.complete()
    let hidden = draft.requestValidation()
    # Hiding a widget does not dispose its draft or its request.
    check hidden.complete()
    check draft.status{} == "Valid"
    let external = draft.requestValidation()
    document.accept(5)
    check not external.complete()
    let disposed = draft.requestValidation()
    draft.dispose()
    check not disposed.complete()

  test "save validates and closes while cancel discards":
    let document = newFormDocument(10)
    let draft = newFormDraft(document)
    draft.edit("-")
    check not draft.saveAndClose()
    check not draft.disposed
    draft.cancel()
    check draft.saveAndClose()
    check draft.disposed
    check draft.status{} == "Saved / Closed"
    draft.edit("20")
    check draft.raw{} == "10"

  test "apply is undoable and undo becomes an external conflict":
    let document = newFormDocument(10)
    let draft = newFormDraft(document)
    draft.edit("20")
    check draft.apply()
    check document.undoManagerFor().performUndo()
    check document.value == 10
    check draft.conflict()
    check document.undoManagerFor().performRedo()
    check document.value == 20

  test "closing the document rejects edits and pending results":
    let document = newFormDocument(10)
    let draft = newFormDraft(document)
    draft.edit("20")
    let pending = draft.requestValidation()
    discard document.close()
    draft.edit("30")
    check draft.raw{} == "20"
    check not draft.apply()
    check not pending.complete()
    check document.value == 10

  test "form field edits stay drafts and programmatic sync never applies":
    let document = newFormDocument(12)
    let draft = newFormDraft(document)
    let form = newDraftForm(draft)
    let window = newWindow("Draft form", frame = rect(0, 0, 320, 160))
    window.setContentView(form)
    let field = TextField(form.viewWithIdentifier("amount"))
    check not field.isNil
    field.setObjectValue(toObj(14))
    check document.value == 12
    check not document.undoManagerFor().canUndo()
    draft.cancel()
    check window.makeFirstResponder(field)
    field.selectedRange = initTextRange(0, field.stringValue.len)
    check window.dispatchKeyDown(KeyEvent(text: "-", key: keyMinus))
    check draft.raw{} == "-"
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check field.currentEditor() == window.fieldEditor()
    check Control(field).hasValidationError()
    check field.stringValue == "-"
    check document.value == 12
    check not document.undoManagerFor().canUndo()
    field.selectedRange = initTextRange(0, field.stringValue.len)
    check window.dispatchKeyDown(KeyEvent(text: "0042"))
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check field.currentEditor().isNil
    check field.stringValue == "42"
    check draft.raw{} == "0042"
    check document.value == 12
    check not document.undoManagerFor().canUndo()
    check draft.apply()
    check document.value == 42
    check document.undoManagerFor().canUndo()
    window.close()

  test "retiring the form detaches its binding without disposing the draft":
    let document = newFormDocument(10)
    let draft = newFormDraft(document)
    let host = newDraftForm(draft)
    let field = TextField(host.viewWithIdentifier("amount"))
    host.viewBody:
      Label("Form removed")
    draft.edit("25")
    check draft.raw{} == "25"
    check field.stringValue == "10"
    check not draft.disposed

suite "document-owned asynchronous form saves":
  test "save survives retiring the initiating form and publishes on its owner thread":
    let directory = createTempDir("merenda-form-test-", "")
    defer:
      removeDir(directory)
    let path = directory / "accepted.txt"
    let document = newFormDocument(12)
    let draft = newFormDraft(document)
    var host = newDraftForm(draft)
    var weakHost: BackRef[DirectView]
    weakHost.target = host
    check document.startSave(path)
    check document.saveInFlight
    check not document.startSave(path)
    host.clear()
    host = nil
    draft.dispose()
    check weakHost.isNil
    require document.waitForSave()
    check document.saveState == fssSaved
    check readFile(path) == "12\n"
    check document.savedValue == 12
    check document.saveCompletionThread == getThreadId()
    check document.saveWorkerThread != document.saveCompletionThread
    check document.undoManagerFor().isAtCleanState()

  test "a later accepted edit stays dirty when an earlier snapshot finishes":
    let directory = createTempDir("merenda-form-test-", "")
    defer:
      removeDir(directory)
    let path = directory / "accepted.txt"
    let document = newFormDocument(12)
    let draft = newFormDraft(document)
    check document.startSave(path)
    draft.edit("30")
    check draft.apply()
    require document.waitForSave()
    check document.saveState == fssSaved
    check readFile(path) == "12\n"
    check document.savedValue == 12
    check document.value == 30
    check not document.undoManagerFor().isAtCleanState()
    check document.saveStatus{} == "Saved 12; newer accepted changes remain"

  test "write failures are reported without changing saved state":
    let directory = createTempDir("merenda-form-test-", "")
    defer:
      removeDir(directory)
    let document = newFormDocument(4)
    let draft = newFormDraft(document)
    draft.edit("5")
    check draft.apply()
    check document.startSave(directory / "missing" / "file")
    require document.waitForSave()
    check document.saveState == fssFailed
    check document.saveError.len > 0
    check document.savedValue == 4
    check not document.undoManagerFor().isAtCleanState()

  test "closing suppresses late publication while an in-flight write finishes":
    let directory = createTempDir("merenda-form-test-", "")
    defer:
      removeDir(directory)
    let path = directory / "accepted.txt"
    let document = newFormDocument(7)
    check document.startSave(path)
    discard document.close()
    check document.saveState == fssClosed
    check not document.startSave(path)
    require document.waitForSave()
    check readFile(path) == "7\n"
    check document.saveState == fssClosed
    check document.saveCompletionThread == 0
    check document.saveStatus{} == "Document closed; an in-flight write may still finish"
