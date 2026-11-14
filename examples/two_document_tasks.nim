## Shared document, draft, undo, and simulated delayed validation policy.
import std/[algorithm, strutils, tables]
import sigils/[core, reactive]
import merenda/nimkit

type
  EditorTask* = object
    id*: int
    title*: string # Accepted model value.
    draft*: string # Provisional editor value, including invalid input.

  EditorTasks* = seq[EditorTask]
  EditorDocument* = ref object of Document
    id*: int
    tasks*: CollectionSigil[int, EditorTask]
    drafts: Table[int, string]
    removedTitles: Table[int, string]
    revision*: int

  EditorStructure* = tuple[generation: int, ids: seq[int]]
  EditorContext* = tuple[generation, id: int]
  EditorController* = ref object of ViewController
    document*: EditorDocument
    alternate*: EditorDocument
    orderBinding: BindingScope
    structure*: Sigil[EditorStructure]
    status*: Sigil[string]
    documentLabel*: Sigil[string]
    generation*: int
    closed*: bool
    queue*: ValidationQueue

  ValidationRequest = object
    owner: BackRef[EditorController]
    generation, revision, documentId, taskId: int
    text: string

  ValidationQueue* = ref object
    pending: seq[ValidationRequest]
    completed*: int
    applied*: int

proc editorTaskId(task: EditorTask): int =
  task.id

proc documentId*(owner: EditorController): int =
  owner.document.id

proc history*(owner: EditorController): UndoManager =
  owner.document.undoManagerFor()

proc tasks*(owner: EditorController): CollectionSigil[int, EditorTask] =
  owner.document.tasks

proc newEditorDocument*(id: int, tasks: EditorTasks): EditorDocument =
  var initial = tasks
  result = EditorDocument(id: id)
  initDocument(result)
  for task in initial.mitems:
    task.draft = task.title
    result.drafts[task.id] = task.draft
  result.tasks = newCollectionSigil(initial, editorTaskId)

proc updateOrder(owner: EditorController, ids: seq[int]) =
  owner.structure <- (owner.generation, ids)

proc detachEditor*(owner: EditorController)

proc documentDidClose(owner: EditorController) {.slot.} =
  owner.detachEditor()

proc watchDocument(owner: EditorController) =
  owner.orderBinding.bindValue("order", owner.tasks.order, owner, updateOrder)
  owner.document.connect(didCloseDocument, owner, documentDidClose)

proc newEditorController*(document: EditorDocument): EditorController =
  result = EditorController(
    document: document,
    generation: 1,
    orderBinding: newBindingScope(),
    structure: newSigil((0, newSeq[int]())),
    status: newSigil("Ready"),
    documentLabel: newSigil("Document " & $document.id),
  )
  initViewController(result)
  result.watchDocument()

proc newEditorController*(documentId: int, tasks: EditorTasks): EditorController =
  newEditorController(newEditorDocument(documentId, tasks))

proc newValidationQueue*(): ValidationQueue =
  ValidationQueue()

proc pendingCount*(queue: ValidationQueue): int =
  queue.pending.len

proc publish(document: EditorDocument, tasks: EditorTasks) =
  document.tasks <- tasks
  for task in tasks:
    document.drafts[task.id] = task.draft
  inc document.revision

proc replaceTasks*(document: EditorDocument, tasks: EditorTasks, action: string) =
  let previous = document.tasks{}
  if document.isClosed or previous == tasks:
    return
  document.publish(tasks)
  var weak: BackRef[EditorDocument]
  weak.target = document
  document.undoManagerFor().registerValueChange(
    proc(value: EditorTasks) =
      let receiver = weak{}
      if not receiver.isNil:
        var restored = value
        for task in restored.mitems:
          if receiver.drafts.hasKey(task.id):
            task.draft = receiver.drafts[task.id]
        receiver.replaceTasks(restored, action)
    ,
    previous,
    action,
  )

proc taskTitle*(owner: EditorController, id: int): string =
  if id in owner.tasks:
    result = owner.tasks[id].draft

proc editTask*(owner: EditorController, id: int, text: string) =
  if owner.closed or owner.document.isClosed:
    return
  var tasks = owner.tasks{}
  for task in tasks.mitems:
    if task.id == id and task.draft != text:
      task.draft = text
      owner.document.publish(tasks)
      return

proc reverseTasks*(owner: EditorController) =
  if owner.closed or owner.document.isClosed:
    return
  var tasks = owner.tasks{}
  tasks.reverse()
  owner.document.replaceTasks(tasks, "Reverse tasks")

proc removeTask*(owner: EditorController, id: int) =
  if owner.closed or owner.document.isClosed:
    return
  var tasks = owner.tasks{}
  for i, task in tasks:
    if task.id == id:
      owner.document.removedTitles[id] = task.title
      tasks.delete(i)
      owner.document.replaceTasks(tasks, "Remove task")
      return

proc restoreTask*(owner: EditorController, id: int) =
  if not owner.closed and not owner.document.isClosed and id notin owner.tasks and
      owner.document.drafts.hasKey(id):
    var tasks = owner.tasks{}
    tasks.add EditorTask(
      id: id,
      title: owner.document.removedTitles.getOrDefault(id),
      draft: owner.document.drafts[id],
    )
    owner.document.replaceTasks(tasks, "Restore task")

proc bindDocument*(owner: EditorController, document: EditorDocument) =
  if document.isClosed:
    return
  inc owner.generation
  owner.document.disconnect(didCloseDocument, owner, documentDidClose)
  owner.document = document
  owner.closed = false
  owner.watchDocument()
  owner.documentLabel <- "Document " & $document.id
  owner.status <- "Ready"

proc switchDocument*(owner: EditorController) =
  if not owner.alternate.isNil and not owner.alternate.isClosed:
    let previous = owner.document
    owner.bindDocument(owner.alternate)
    owner.alternate = previous

proc detachEditor*(owner: EditorController) =
  inc owner.generation
  owner.closed = true
  owner.document.disconnect(didCloseDocument, owner, documentDidClose)
  owner.orderBinding.dispose()
  owner.orderBinding = newBindingScope()
  owner.structure <- (owner.generation, @[])
  owner.status <- "Detached"

proc taskTitle*(owner: EditorController, context: EditorContext): string =
  if not owner.closed and not owner.document.isClosed and
      owner.generation == context.generation:
    result = owner.taskTitle(context.id)

proc editTask*(owner: EditorController, context: EditorContext, text: string) =
  if not owner.closed and not owner.document.isClosed and
      owner.generation == context.generation:
    owner.editTask(context.id, text)

proc removeTask*(owner: EditorController, context: EditorContext) =
  if not owner.closed and not owner.document.isClosed and
      owner.generation == context.generation:
    owner.removeTask(context.id)

proc undo*(owner: EditorController) =
  if not owner.closed and not owner.document.isClosed:
    discard owner.history.performUndo()

proc closeDocument*(owner: EditorController) =
  if not owner.closed and not owner.document.isClosed:
    discard owner.document.close()

proc queueValidation*(queue: ValidationQueue, owner: EditorController, id: int) =
  if not owner.closed and not owner.document.isClosed and id in owner.tasks:
    var weak: BackRef[EditorController]
    weak.target = owner
    queue.pending.add ValidationRequest(
      owner: weak,
      generation: owner.generation,
      revision: owner.document.revision,
      documentId: owner.documentId,
      taskId: id,
      text: owner.taskTitle(id),
    )
    owner.status <- "Validation queued"

proc queueValidation*(
    queue: ValidationQueue, owner: EditorController, context: EditorContext
) =
  if not owner.closed and not owner.document.isClosed and
      owner.generation == context.generation:
    queue.queueValidation(owner, context.id)

proc flushValidation*(queue: ValidationQueue) =
  ## Deliver simulated delayed results on the owning GUI thread.
  let pending = move(queue.pending)
  for request in pending:
    inc queue.completed
    let owner = request.owner{}
    if not owner.isNil and not owner.closed and not owner.document.isClosed and
        owner.generation == request.generation and
        owner.document.revision == request.revision and
        owner.documentId == request.documentId and request.taskId in owner.tasks:
      if request.text.strip.len == 0:
        owner.status <- "Title is blank"
      else:
        var tasks = owner.tasks{}
        for task in tasks.mitems:
          if task.id == request.taskId:
            task.title = request.text
        owner.document.replaceTasks(tasks, "Validate title")
        owner.status <- "Title is valid"
      inc queue.applied
