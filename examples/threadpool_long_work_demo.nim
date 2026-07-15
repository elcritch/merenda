## Runs CPU-heavy prime searches without blocking Merenda's application thread.
## Each worker processes one batch per cross-thread Sigils signal.

import merenda/nimkit

import std/[monotimes, times]
import sigils

const
  TaskCount = 8
  CandidatesPerBatch = 2_000_000
  ResultsLayoutInset = 12.0'f32
  ResultsRowSpacing = 12.0'f32
  ResultsTaskHeight = 90.0'f32
  ResultsDocumentHeight =
    ResultsLayoutInset * 2.0'f32 + ResultsTaskHeight * float32(TaskCount) +
    ResultsRowSpacing * float32(TaskCount - 1)
  FirstCandidate = 400_000
  BaseCandidatesPerTask = CandidatesPerBatch

type
  WorkDispatcher = ref object of Agent

  PrimeSearchWorker = ref object of AgentActor

  LongWorkController = ref object of Responder
    dispatchers: array[TaskCount, WorkDispatcher]
    progressIndicators: array[TaskCount, ProgressIndicator]
    resultLabels: array[TaskCount, Label]
    stopButtons: array[TaskCount, Button]
    stopRequested: array[TaskCount, bool]
    primeCounts: array[TaskCount, int]
    largestPrimes: array[TaskCount, int]
    elapsedMilliseconds: array[TaskCount, int]
    runButton: Button
    overallStatus: Label
    completed: array[TaskCount, bool]
    completedCount: int
    running: bool

proc workRequested*(
  dispatcher: WorkDispatcher,
  taskIndex: int,
  batchIndex: int,
  firstCandidate: int,
  candidateCount: int,
) {.signal.}

proc workStopRequested*(controller: LongWorkController, taskIndex: int) {.signal.}

proc workBatchFinished*(
  worker: PrimeSearchWorker,
  taskIndex: int,
  batchIndex: int,
  primeCount: int,
  largestPrime: int,
  elapsedMilliseconds: int,
  workerThreadId: int,
) {.signal.}

func isPrime(candidate: int): bool =
  if candidate < 2:
    return false
  if candidate == 2:
    return true
  if candidate mod 2 == 0:
    return false

  var divisor = 3
  while divisor * divisor <= candidate:
    if candidate mod divisor == 0:
      return false
    divisor += 2
  true

func candidateCount(taskIndex: int): int =
  BaseCandidatesPerTask * (1 shl taskIndex)

func firstCandidate(taskIndex: int): int =
  FirstCandidate + BaseCandidatesPerTask * ((1 shl taskIndex) - 1)

func batchCount(taskIndex: int): int =
  (taskIndex.candidateCount() + CandidatesPerBatch - 1) div CandidatesPerBatch

func batchFirstCandidate(taskIndex, batchIndex: int): int =
  taskIndex.firstCandidate() + batchIndex * CandidatesPerBatch

func batchCandidateCount(taskIndex, batchIndex: int): int =
  min(CandidatesPerBatch, taskIndex.candidateCount() - batchIndex * CandidatesPerBatch)

proc searchPrimeBatch(
    worker: PrimeSearchWorker,
    taskIndex: int,
    batchIndex: int,
    firstCandidate: int,
    candidateCount: int,
) {.slot.} =
  let startedAt = getMonoTime()
  var
    primeCount = 0
    largestPrime = 0

  for candidate in firstCandidate ..< firstCandidate + candidateCount:
    if candidate.isPrime():
      inc primeCount
      largestPrime = candidate

  let elapsedMilliseconds = (getMonoTime() - startedAt).inMilliseconds.int
  emit worker.workBatchFinished(
    taskIndex, batchIndex, primeCount, largestPrime, elapsedMilliseconds, getThreadId()
  )

proc requestWorkStop(controller: LongWorkController, taskIndex: int) {.slot.} =
  if taskIndex notin 0 ..< TaskCount or not controller.running or
      controller.completed[taskIndex]:
    return
  controller.stopRequested[taskIndex] = true
  controller.stopButtons[taskIndex].enabled = false
  controller.resultLabels[taskIndex].text = "Stopping after the current batch..."

proc finishWork(
    controller: LongWorkController, taskIndex: int, stopped: bool, workerThreadId: int
) =
  controller.completed[taskIndex] = true
  inc controller.completedCount
  controller.stopButtons[taskIndex].enabled = false
  controller.resultLabels[taskIndex].text =
    (if stopped: "Stopped after finding " else: "Found ") &
    $controller.primeCounts[taskIndex] & " primes; largest: " &
    $controller.largestPrimes[taskIndex] & " · " &
    $controller.elapsedMilliseconds[taskIndex] & " ms on worker thread " &
    $workerThreadId
  if not stopped:
    controller.progressIndicators[taskIndex].value = 100.0

  if controller.completedCount == TaskCount:
    controller.running = false
    controller.runButton.enabled = true
    controller.overallStatus.text =
      "All tasks finished. Run them again or keep interacting with the window."

proc requestNextBatch(controller: LongWorkController, taskIndex, batchIndex: int) =
  emit controller.dispatchers[taskIndex].workRequested(
    taskIndex,
    batchIndex,
    taskIndex.batchFirstCandidate(batchIndex),
    taskIndex.batchCandidateCount(batchIndex),
  )

proc didFinishPrimeBatch(
    controller: LongWorkController,
    taskIndex: int,
    batchIndex: int,
    primeCount: int,
    largestPrime: int,
    elapsedMilliseconds: int,
    workerThreadId: int,
) {.slot.} =
  if taskIndex notin 0 ..< TaskCount or batchIndex notin 0 ..< taskIndex.batchCount() or
      controller.completed[taskIndex]:
    return

  controller.primeCounts[taskIndex] += primeCount
  controller.largestPrimes[taskIndex] =
    max(controller.largestPrimes[taskIndex], largestPrime)
  controller.elapsedMilliseconds[taskIndex] += elapsedMilliseconds
  if batchIndex + 1 == taskIndex.batchCount():
    controller.finishWork(taskIndex, stopped = false, workerThreadId)
  elif controller.stopRequested[taskIndex]:
    controller.finishWork(taskIndex, stopped = true, workerThreadId)
  else:
    let percentComplete = min(
      100, (batchIndex + 1) * CandidatesPerBatch * 100 div taskIndex.candidateCount()
    )
    controller.progressIndicators[taskIndex].value = percentComplete.float32
    controller.resultLabels[taskIndex].text =
      "Running — " & $percentComplete & "% complete"
    controller.requestNextBatch(taskIndex, batchIndex + 1)

proc startWork(controller: LongWorkController) =
  if controller.running:
    return

  controller.running = true
  controller.completedCount = 0
  controller.runButton.enabled = false
  controller.overallStatus.text =
    "Working in parallel — try moving or resizing the window."

  for taskIndex in 0 ..< TaskCount:
    controller.completed[taskIndex] = false
    controller.stopRequested[taskIndex] = false
    controller.primeCounts[taskIndex] = 0
    controller.largestPrimes[taskIndex] = 0
    controller.elapsedMilliseconds[taskIndex] = 0
    controller.progressIndicators[taskIndex].value = 0.0
    controller.resultLabels[taskIndex].text = "Queued"
    controller.stopButtons[taskIndex].enabled = true
    controller.requestNextBatch(taskIndex, 0)

proc newStopWorkTarget(controller: LongWorkController, taskIndex: int): ClosureTarget =
  result = newActionTarget(actionSelector("stopPrimeSearch")) do(sender: DynamicAgent):
    discard sender
    emit controller.workStopRequested(taskIndex)

let
  app = sharedApplication()
  window = newWindow("Sigils Thread Pool", frame = rect(120, 120, 680, 520))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Long-running work with Sigils")
  explanation = newLabel(
    "Each batch tests " & $CandidatesPerBatch & " candidates, so longer " &
      "searches schedule more batches while workers remain available to the pool."
  )
  overallStatus = newStatusLabel("Ready to search four number ranges.")
  runButton = newButton("Run prime searches")
  resultsLayout =
    newStackView(laVertical, frame = rect(0, 0, 620, ResultsDocumentHeight))
  resultsScrollView = newScrollView(documentView = resultsLayout)
  controller = LongWorkController(runButton: runButton, overallStatus: overallStatus)

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(title, explanation, overallStatus, resultsScrollView)

resultsLayout.spacing = ResultsRowSpacing
resultsLayout.edgeInsets = insets(ResultsLayoutInset)
resultsLayout.alignment = svaFill
resultsScrollView.hasVerticalScroller = true
resultsScrollView.hasHorizontalScroller = false
resultsScrollView.autohidePolicy = sapWhenNeeded
resultsScrollView.borderType = svbLineBorder
resultsScrollView.drawsBackground = true
resultsScrollView.verticalLineScroll = 24.0
resultsScrollView.verticalPageScroll = 180.0

for taskIndex in 0 ..< TaskCount:
  let
    firstCandidate = taskIndex.firstCandidate()
    candidateCount = taskIndex.candidateCount()
    lastCandidate = firstCandidate + candidateCount - 1
    taskLayout = newStackView(laVertical)
    taskLabel = newHeadingLabel(
      "Task " & $(taskIndex + 1) & ": " & $firstCandidate & "–" & $lastCandidate & " (" &
        $candidateCount & " candidates, " & $taskIndex.batchCount() & " batches)"
    )
    progress = newProgressIndicator(0.0, 100.0, 0.0)
    resultLabel = newStatusLabel("Waiting")
    stopButton = newButton("Stop")
    taskHeader = newStackView(laHorizontal)

  taskLayout.spacing = 4.0
  taskLayout.alignment = svaFill
  taskHeader.spacing = 8.0
  taskHeader.alignment = svaCenter
  stopButton.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  taskHeader.addArrangedSubview(taskLabel, stopButton)
  taskLayout.addArrangedSubview(taskHeader, progress, resultLabel)
  resultsLayout.addArrangedSubview(taskLayout)
  controller.progressIndicators[taskIndex] = progress
  controller.resultLabels[taskIndex] = resultLabel
  controller.stopButtons[taskIndex] = stopButton
  stopButton.action = actionSelector("stopPrimeSearch")
  stopButton.target = controller.newStopWorkTarget(taskIndex)

layout.addArrangedSubview(runButton)
root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

runButton.action = actionSelector("runLongWork")
runButton.target = newActionTarget(runButton.action) do(sender: DynamicAgent):
  discard sender
  controller.startWork()

let pool = newSigilThreadPool(workers = TaskCount)
pool.start()

# Stop requests stay on the application thread and suppress the next batch.
connect(controller, workStopRequested, controller, LongWorkController.requestWorkStop())

# A pool may execute different actors concurrently, while calls to one actor
# remain serialized. Each completion signal schedules one more batch, yielding
# the actor between batches. Give each independent task its own actor and dispatcher.
var workerProxies: array[TaskCount, AgentProxy[PrimeSearchWorker]]
for taskIndex in 0 ..< TaskCount:
  controller.dispatchers[taskIndex] = WorkDispatcher()
  var worker = PrimeSearchWorker()
  workerProxies[taskIndex] = worker.moveToThread(pool)
  connectThreaded(
    controller.dispatchers[taskIndex],
    workRequested,
    workerProxies[taskIndex],
    searchPrimeBatch,
  )
  connectThreaded(
    workerProxies[taskIndex],
    workBatchFinished,
    controller,
    LongWorkController.didFinishPrimeBatch(),
  )

controller.startWork()
try:
  app.runWindow(window, root, runButton)
finally:
  pool.stop()
  pool.join()
