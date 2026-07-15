## Runs CPU-heavy prime searches without blocking Merenda's application thread.
## Each worker reports incremental progress through cross-thread Sigils signals.

import merenda/nimkit

import std/[atomics, monotimes, times]
import sigils

const
  TaskCount = 8
  ProgressStepCount = 20
  StopCheckInterval = 1_024
  ResultsLayoutInset = 12.0'f32
  ResultsRowSpacing = 12.0'f32
  ResultsTaskHeight = 90.0'f32
  ResultsDocumentHeight =
    ResultsLayoutInset * 2.0'f32 + ResultsTaskHeight * float32(TaskCount) +
    ResultsRowSpacing * float32(TaskCount - 1)
  FirstCandidate = 400_000
  BaseCandidatesPerTask = 2_000_000

type
  WorkDispatcher = ref object of Agent

  PrimeSearchWorker = ref object of AgentActor

  LongWorkController = ref object of Responder
    dispatchers: array[TaskCount, WorkDispatcher]
    progressIndicators: array[TaskCount, ProgressIndicator]
    resultLabels: array[TaskCount, Label]
    stopButtons: array[TaskCount, Button]
    stopFlags: array[TaskCount, Atomic[bool]]
    runButton: Button
    overallStatus: Label
    completed: array[TaskCount, bool]
    completedCount: int
    running: bool

proc workRequested*(
  dispatcher: WorkDispatcher,
  taskIndex: int,
  firstCandidate: int,
  candidateCount: int,
  stopFlag: ptr Atomic[bool],
) {.signal.}

proc workStopRequested*(controller: LongWorkController, taskIndex: int) {.signal.}

proc workProgress*(
  worker: PrimeSearchWorker, taskIndex: int, percentComplete: int
) {.signal.}

proc workFinished*(
  worker: PrimeSearchWorker,
  taskIndex: int,
  primeCount: int,
  largestPrime: int,
  stopped: bool,
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

proc searchForPrimes(
    worker: PrimeSearchWorker,
    taskIndex: int,
    firstCandidate: int,
    candidateCount: int,
    stopFlag: ptr Atomic[bool],
) {.slot.} =
  let startedAt = getMonoTime()
  var
    primeCount = 0
    largestPrime = 0
    stopped = false

  for step in 0 ..< ProgressStepCount:
    if stopFlag[].load(moRelaxed):
      stopped = true
      break
    let
      stepStart = firstCandidate + candidateCount * step div ProgressStepCount
      stepEnd = firstCandidate + candidateCount * (step + 1) div ProgressStepCount
    for candidate in stepStart ..< stepEnd:
      if candidate mod StopCheckInterval == 0 and stopFlag[].load(moRelaxed):
        stopped = true
        break
      if candidate.isPrime():
        inc primeCount
        largestPrime = candidate
    if stopped:
      break
    emit worker.workProgress(taskIndex, (step + 1) * 100 div ProgressStepCount)

  let elapsedMilliseconds = (getMonoTime() - startedAt).inMilliseconds.int
  emit worker.workFinished(
    taskIndex, primeCount, largestPrime, stopped, elapsedMilliseconds, getThreadId()
  )

proc requestWorkStop(controller: LongWorkController, taskIndex: int) {.slot.} =
  if taskIndex notin 0 ..< TaskCount or controller.completed[taskIndex]:
    return
  controller.stopFlags[taskIndex].store(true, moRelaxed)
  controller.stopButtons[taskIndex].enabled = false
  controller.resultLabels[taskIndex].text = "Stopping after the current check..."

proc didMakeProgress(
    controller: LongWorkController, taskIndex: int, percentComplete: int
) {.slot.} =
  if taskIndex notin 0 ..< TaskCount:
    return
  controller.progressIndicators[taskIndex].value = percentComplete.float32
  controller.resultLabels[taskIndex].text =
    "Running — " & $percentComplete & "% complete"

proc didFinishWork(
    controller: LongWorkController,
    taskIndex: int,
    primeCount: int,
    largestPrime: int,
    stopped: bool,
    elapsedMilliseconds: int,
    workerThreadId: int,
) {.slot.} =
  if taskIndex notin 0 ..< TaskCount or controller.completed[taskIndex]:
    return

  controller.completed[taskIndex] = true
  inc controller.completedCount
  controller.stopButtons[taskIndex].enabled = false
  controller.resultLabels[taskIndex].text =
    (if stopped: "Stopped after finding " else: "Found ") & $primeCount &
    " primes; largest: " & $largestPrime & " · " & $elapsedMilliseconds &
    " ms on worker thread " & $workerThreadId
  if not stopped:
    controller.progressIndicators[taskIndex].value = 100.0

  if controller.completedCount == TaskCount:
    controller.running = false
    controller.runButton.enabled = true
    controller.overallStatus.text =
      "All tasks finished. Run them again or keep interacting with the window."

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
    controller.stopFlags[taskIndex].store(false, moRelaxed)
    controller.progressIndicators[taskIndex].value = 0.0
    controller.resultLabels[taskIndex].text = "Queued"
    controller.stopButtons[taskIndex].enabled = true
    emit controller.dispatchers[taskIndex].workRequested(
      taskIndex,
      taskIndex.firstCandidate(),
      taskIndex.candidateCount(),
      addr controller.stopFlags[taskIndex],
    )

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
    "Each worker searches twice as many candidates as the previous worker. " &
      "Results return to the UI thread through signals."
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
        $candidateCount & " candidates)"
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

# Keep cancellation local: a stop slot queued on a busy worker would not run
# until its prime search completed. The worker reads the atomic flag directly.
connect(controller, workStopRequested, controller, LongWorkController.requestWorkStop())

# A pool may execute different actors concurrently, while calls to one actor
# remain serialized. Give each independent task its own actor and dispatcher.
var workerProxies: array[TaskCount, AgentProxy[PrimeSearchWorker]]
for taskIndex in 0 ..< TaskCount:
  controller.dispatchers[taskIndex] = WorkDispatcher()
  var worker = PrimeSearchWorker()
  workerProxies[taskIndex] = worker.moveToThread(pool)
  connectThreaded(
    controller.dispatchers[taskIndex],
    workRequested,
    workerProxies[taskIndex],
    searchForPrimes,
  )
  connectThreaded(
    workerProxies[taskIndex],
    workProgress,
    controller,
    LongWorkController.didMakeProgress(),
  )
  connectThreaded(
    workerProxies[taskIndex],
    workFinished,
    controller,
    LongWorkController.didFinishWork(),
  )

controller.startWork()
try:
  app.runWindow(window, root, runButton)
finally:
  pool.stop()
  pool.join()
