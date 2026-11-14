## A small form policy shared by direct and declarative hosts.
## Draft identity is explicit: pass the same FormDraft to share an edit session.
import sigils/[core, reactive]
import merenda/nimkit

type
  FormDocument* = ref object of Document
    value*: int
    savedValue*: int
    accepted*: Sigil[int]
    revision*: int

  FormDraft* = ref object of Responder
    document*: FormDocument
    raw*: Sigil[string]
    baseRevision*: int
    generation*: int
    disposed*: bool
    status*: Sigil[string]

  FormValidation* = object
    owner: BackRef[FormDraft]
    generation, revision: int
    raw: string

proc newFormDocument*(value: int): FormDocument =
  result = FormDocument(value: value, savedValue: value, accepted: newSigil(value))
  initDocument(result)

proc newFormDraft*(document: FormDocument): FormDraft =
  result = FormDraft(
    document: document,
    raw: newSigil($document.value),
    baseRevision: document.revision,
    generation: 1,
    status: newSigil("Ready"),
  )
  initResponder(result)

proc edit*(draft: FormDraft, raw: string) =
  if not draft.disposed and not draft.document.isClosed and draft.raw{} != raw:
    inc draft.generation
    draft.raw <- raw
    draft.status <- "Edited"

proc rawText*(draft: FormDraft, context: int): string =
  draft.raw{}

proc editText*(draft: FormDraft, context: int, value: string) =
  draft.edit(value)

proc dirty*(draft: FormDraft): bool =
  draft.raw{} != $draft.document.value or draft.baseRevision != draft.document.revision

proc conflict*(draft: FormDraft): bool =
  draft.baseRevision != draft.document.revision

proc setAccepted(document: FormDocument, value: int) =
  if not document.isClosed and document.value != value:
    document.value = value
    inc document.revision
    document.accepted <- value

proc replaceAccepted(document: FormDocument, value: int) =
  let previous = document.value
  if previous != value:
    var weak: BackRef[FormDocument]
    weak.target = document
    document.undoManagerFor().registerValueChange(
      proc(old: int) =
        let owner = weak{}
        if not owner.isNil:
          owner.replaceAccepted(old)
      ,
      previous,
      "Apply form",
    )
    document.setAccepted(value)

proc accept*(document: FormDocument, value: int) =
  ## An external accepted update also advances the conflict revision.
  if not document.isClosed and document.value != value:
    document.undoManagerFor().clearAll()
    document.undoManagerFor().clearCleanState()
    document.setAccepted(value)

proc cancel*(draft: FormDraft) =
  if not draft.disposed and not draft.document.isClosed:
    inc draft.generation
    draft.baseRevision = draft.document.revision
    draft.raw <- $draft.document.value
    draft.status <- "Cancelled"

proc apply*(draft: FormDraft): bool =
  if draft.disposed or draft.document.isClosed:
    return
  if draft.conflict:
    draft.status <- "Conflict: cancel to reload"
    return
  let parsed = parseObjectValue(
    draft.raw{}, initObjectParseContext(expectedKind = ovInt, emptyPolicy = oepInvalid)
  )
  if parsed.failed:
    draft.status <- parsed.error.displayMessage()
    return
  let document = draft.document
  let value = parsed.value.requireInt()
  let generation = draft.generation
  let expectedRevision = document.revision + (if value == document.value: 0 else: 1)
  document.replaceAccepted(value)
  if draft.disposed or document.isClosed or draft.generation != generation or
      document.revision != expectedRevision:
    draft.status <- "Changed while applying; review the draft"
    return
  inc draft.generation
  draft.baseRevision = document.revision
  draft.raw <- $value
  draft.status <- "Applied"
  result = true

proc saveAndClose*(draft: FormDraft): bool =
  ## Save rejects invalid or conflicting drafts. Cancel explicitly discards first.
  if draft.apply():
    draft.document.savedValue = draft.document.value
    draft.document.undoManagerFor().markCleanState()
    draft.disposed = true
    inc draft.generation
    draft.status <- "Saved / Closed"
    result = true

proc dispose*(draft: FormDraft) =
  ## Disposing a session invalidates requests; merely hiding its view does not.
  draft.disposed = true
  inc draft.generation

proc requestValidation*(draft: FormDraft): FormValidation =
  result.owner.target = draft
  result.generation = draft.generation
  result.revision = draft.document.revision
  result.raw = draft.raw{}

proc complete*(request: FormValidation): bool =
  let draft = request.owner{}
  if draft.isNil or draft.disposed or draft.document.isClosed or
      draft.generation != request.generation or
      draft.document.revision != request.revision:
    return
  let parsed = parseObjectValue(
    request.raw, initObjectParseContext(expectedKind = ovInt, emptyPolicy = oepInvalid)
  )
  draft.status <- (if parsed.valid: "Valid"
  else: parsed.error.displayMessage())
  result = true
