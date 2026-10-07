## A read-only, searchable GitHub document backed by a cancellable gh worker.

import std/[atomics, monotimes, options, os, times]
import sigils/[core, threadProxies, threads]
import threading/smartptrs
import ../nimkit as nimkit
import ../nimkit/foundation/mainthreadwork
import ../nimkit/foundation/selectors as nimkitSelectors
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./[github, searchbar, viewersearch]

export github

const
  KosmoGitHubTabIdentifier* = "kosmo.github"
  GitHubDefaultRefreshIntervalMilliseconds* = 30_000
  GitHubRefreshDebounceInterval = initDuration(milliseconds = 300)

type
  GitHubRequestControl = object
    cancelled: Atomic[bool]

  GitHubWorker = ref object of AgentActor

  GitHubLinkDelegate = ref object of nimkit.DynamicAgent
    panel: WeakRef[KosmoGitHubPanel]

  GitHubLinkHandler* = proc(link: string): bool {.closure.}

  GitHubKeyEquivalentHandler* = proc(event: nimkit.KeyEvent): bool {.closure.}

  KosmoGitHubPanel* = ref object of nimkit.View
    markdownView*: nimkit.MarkdownView
    refreshButton*: nimkit.Button
    kindButton*: nimkit.PopupMenuButton
    stateButton*: nimkit.PopupMenuButton
    autoRefreshSwitch*: nimkit.SwitchButton
    autoRefreshLabel: nimkit.Label
    snapshot*: GitHubSnapshot
    search: KosmoViewerSearch
    pool: SigilThreadPoolPtr
    worker: AgentProxy[GitHubWorker]
    control: SharedPtr[GitHubRequestControl]
    rootPath: string
    executable: string
    state: GitHubState
    kinds: set[GitHubItemKind]
    generation: uint64
    loading*: bool
    closed*: bool
    repositoryBacked: bool
    refreshPending: bool
    refreshDeadline, nextRefresh: MonoTime
    refreshInterval: Duration
    keyEquivalentHandler: GitHubKeyEquivalentHandler
    linkHandler: GitHubLinkHandler
    pendingSearchRange: Option[nimkit.TextRange]

proc refresh*(panel: KosmoGitHubPanel)
proc selectFilter*(
  panel: KosmoGitHubPanel, state: GitHubState, kinds: set[GitHubItemKind]
)

proc readRepository(
  worker: AgentProxy[GitHubWorker],
  root, executable: string,
  state: GitHubState,
  kinds: set[GitHubItemKind],
  generation: uint64,
  control: SharedPtr[GitHubRequestControl],
) {.signal.}

proc repositoryFinished(
  worker: GitHubWorker, snapshot: GitHubSnapshot, generation: uint64
) {.signal.}

proc readRepository(
    worker: GitHubWorker,
    root, executable: string,
    state: GitHubState,
    kinds: set[GitHubItemKind],
    generation: uint64,
    control: SharedPtr[GitHubRequestControl],
) {.slot.} =
  let cancelled = proc(): bool {.gcsafe.} =
    control[].cancelled.load(moAcquire)
  let snapshot = readGitHubSnapshot(
    root, state, kinds, executable = executable, cancelled = cancelled
  )
  if not cancelled():
    emit worker.repositoryFinished(snapshot, generation)

proc syncControls(panel: KosmoGitHubPanel) =
  panel.kindButton.title =
    if panel.kinds == {ghikIssue}:
      "Issues"
    elif panel.kinds == {ghikPullRequest}:
      "Pull Requests"
    else:
      "Issues & PRs"
  panel.stateButton.title =
    case panel.state
    of ghsOpen: "Open"
    of ghsClosed: "Closed"
    of ghsAll: "All States"
  panel.refreshButton.title = if panel.loading: "Loading…" else: "Refresh"
  panel.refreshButton.enabled =
    panel.repositoryBacked and not panel.loading and not panel.closed
  panel.autoRefreshSwitch.enabled = panel.repositoryBacked and not panel.closed

proc applySnapshot(panel: KosmoGitHubPanel, snapshot: GitHubSnapshot) =
  ## Show an already prepared snapshot, including offline fixtures.
  if panel.isNil or panel.closed:
    return
  let preserveHeadingState = panel.snapshot.rootPath == snapshot.rootPath
  panel.snapshot = snapshot
  panel.markdownView.updateMarkdown(
    snapshot.gitHubMarkdown(),
    snapshot.gitHubHeadingIdentifiers(),
    preserveHeadingState = preserveHeadingState,
  )
  panel.syncControls()

proc repositoryFinished(
    panel: KosmoGitHubPanel, snapshot: GitHubSnapshot, generation: uint64
) {.slot.} =
  if not panel.closed and generation == panel.generation:
    panel.loading = false
    panel.nextRefresh = getMonoTime() + panel.refreshInterval
    panel.applySnapshot(snapshot)

proc refresh*(panel: KosmoGitHubPanel) =
  ## Cancel obsolete requests and load the current repository off the UI thread.
  if panel.isNil or panel.closed or not panel.repositoryBacked:
    return
  if not panel.control.isNil:
    panel.control[].cancelled.store(true, moRelease)
  panel.control = newSharedPtr(GitHubRequestControl)
  panel.control[].cancelled.store(false, moRelaxed)
  inc panel.generation
  panel.refreshPending = false
  panel.nextRefresh = getMonoTime() + panel.refreshInterval
  panel.loading = true
  panel.syncControls()
  emit panel.worker.readRepository(
    panel.rootPath, panel.executable, panel.state, panel.kinds, panel.generation,
    panel.control,
  )

proc pollRepositoryRefresh*(panel: KosmoGitHubPanel): bool {.discardable.} =
  ## Refresh periodically or after a quiet workspace notification, without overlap.
  if panel.isNil or panel.closed or not panel.repositoryBacked:
    return
  let now = getMonoTime()
  if not panel.autoRefreshSwitch.on:
    panel.refreshPending = false
    panel.nextRefresh = now + panel.refreshInterval
    return
  if panel.loading:
    return
  if (panel.refreshPending and now >= panel.refreshDeadline) or now >= panel.nextRefresh:
    panel.refresh()
    result = true

proc scheduleRepositoryRefresh*(panel: KosmoGitHubPanel) =
  ## Coalesce workspace changes while automatic refresh is enabled.
  if panel.isNil or panel.closed or not panel.repositoryBacked or
      not panel.autoRefreshSwitch.on:
    return
  panel.refreshPending = true
  panel.refreshDeadline = getMonoTime() + GitHubRefreshDebounceInterval

proc selectFilter*(
    panel: KosmoGitHubPanel, state: GitHubState, kinds: set[GitHubItemKind]
) =
  ## Change the server-side item selection; superseded responses are ignored.
  if panel.isNil or panel.closed or kinds == {}:
    return
  panel.state = state
  panel.kinds = kinds
  panel.syncControls()
  if panel.repositoryBacked:
    panel.refresh()
  else:
    var snapshot = panel.snapshot
    snapshot.state = state
    snapshot.kinds = kinds
    panel.applySnapshot(snapshot)

proc displayRepository*(panel: KosmoGitHubPanel, rootPath: string) =
  ## Reuse a document for a different project and clear its previous contents.
  if panel.isNil or panel.closed:
    return
  if panel.rootPath != rootPath:
    panel.rootPath = rootPath
    panel.applySnapshot(
      GitHubSnapshot(rootPath: rootPath, state: panel.state, kinds: panel.kinds)
    )
  panel.repositoryBacked = true
  panel.refresh()

proc close*(panel: KosmoGitHubPanel) {.slot.} =
  ## Cancel, terminate, and reap this document's pending gh command.
  if panel.isNil or panel.closed:
    return
  panel.closed = true
  panel.loading = false
  panel.refreshPending = false
  inc panel.generation
  if not panel.control.isNil:
    panel.control[].cancelled.store(true, moRelease)
  if not panel.pool.isNil:
    panel.pool.stop(immediate = true)
    panel.pool.join()
  panel.syncControls()

proc waitForGitHub*(panel: KosmoGitHubPanel, timeoutMilliseconds = 60_000): bool =
  ## Pump worker results and Markdown work until ready, for hosts without a loop.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while getMonoTime() < deadline:
    discard panel.pollRepositoryRefresh()
    discard getCurrentSigilThread().pollAll(NonBlocking)
    discard drainMainThreadWork()
    if not panel.loading and not panel.refreshPending and
        not panel.markdownView.isMarkdownParsing() and
        not panel.markdownView.isMarkdownRendering() and
        not panel.markdownView.textView().layoutManager().isBackgroundLayoutPending():
      return true
    sleep(1)

proc `markdownStyle=`*(panel: KosmoGitHubPanel, style: nimkit.MarkdownStyle) =
  panel.markdownView.markdownStyle = style

proc `keyEquivalentHandler=`*(
    panel: KosmoGitHubPanel, handler: GitHubKeyEquivalentHandler
) =
  panel.keyEquivalentHandler = handler

proc showSearch*(panel: KosmoGitHubPanel): bool {.discardable.} =
  panel.search.showSearch()

proc searchField*(panel: KosmoGitHubPanel): nimkit.TextField =
  panel.search.bar.queryField()

proc searchMatchCount*(panel: KosmoGitHubPanel): int =
  panel.search.searchMatchCount()

proc `linkHandler=`*(panel: KosmoGitHubPanel, handler: GitHubLinkHandler) =
  ## Handle external HTTP links using the host application's workspace service.
  panel.linkHandler = handler

protocol GitHubLinks of nimkit.TextViewDelegateProtocol:
  method tvClickedLink(
      delegate: GitHubLinkDelegate,
      textView: nimkit.TextView,
      link: string,
      range: nimkit.TextRange,
  ): bool =
    if not delegate.panel.isNil:
      let panel = delegate.panel[]
      if not panel.closed and nimkit.initUrl(link).isHttpUrl() and
          not panel.linkHandler.isNil:
        return panel.linkHandler(link)

proc parsingFinished(panel: KosmoGitHubPanel, workerThreadId: int) {.slot.} =
  discard workerThreadId
  if not panel.closed:
    panel.search.refreshSearch()

proc searchLayoutFinished(
    panel: KosmoGitHubPanel, snapshot: nimkit.TextLayoutSnapshot
) {.slot.} =
  discard snapshot
  if not panel.closed and panel.pendingSearchRange.isSome and
      panel.search.searchVisible():
    let range = panel.pendingSearchRange.get()
    if revealTextMatch(
      panel.markdownView.textView(), panel.markdownView.scrollView(), range
    ):
      panel.markdownView.selectMarkdownRange(range)
      panel.pendingSearchRange = none(nimkit.TextRange)

protocol GitHubLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(panel: KosmoGitHubPanel) =
    let bounds = panel.bounds()
    let scale = min(max((bounds.size.width - 52) / 546, 0), 1)
    panel.refreshButton.setFrameFromLayout(nimkit.rect(12, 8, 90 * scale, 28))
    panel.kindButton.setFrameFromLayout(
      nimkit.rect(20 + 90 * scale, 8, 180 * scale, 28)
    )
    panel.stateButton.setFrameFromLayout(
      nimkit.rect(28 + 270 * scale, 8, 140 * scale, 28)
    )
    panel.autoRefreshLabel.setFrameFromLayout(
      nimkit.rect(36 + 410 * scale, 8, 82 * scale, 28)
    )
    panel.autoRefreshSwitch.setFrameFromLayout(
      nimkit.rect(40 + 492 * scale, 8, 54 * scale, 28)
    )
    panel.markdownView.setFrameFromLayout(
      nimkit.rect(0, 44, bounds.size.width, max(bounds.size.height - 44, 0))
    )
    panel.search.bar.layoutInBounds(bounds)

proc newGitHubFilterItem(
    panel: WeakRef[KosmoGitHubPanel],
    title: string,
    kinds: set[GitHubItemKind] = {},
    state = ghsOpen,
): nimkit.MenuItem =
  # A separate call owns each captured selection; loop closures share locals.
  let action = nimkit.actionSelector("kosmo.selectGitHubFilter")
  result = nimkit.newMenuItem(title, action)
  result.validates = false
  result.target = nimkit.newActionTarget(action) do(sender: nimkit.DynamicAgent):
    if not panel.isNil:
      if kinds == {}:
        panel[].selectFilter(state, panel[].kinds)
      else:
        panel[].selectFilter(panel[].state, kinds)

proc newKosmoGitHubPanel(
    snapshot: GitHubSnapshot,
    executable: string,
    repositoryBacked: bool,
    markdownStyle: nimkit.MarkdownStyle,
    refreshIntervalMilliseconds: Positive,
): KosmoGitHubPanel =
  startLocalThreadDefault()
  result = KosmoGitHubPanel(
    markdownView: nimkit.newMarkdownView(),
    refreshButton: nimkit.newButton("Refresh"),
    kindButton:
      nimkit.newPopupMenuButton("Issues & PRs", nimkit.newMenu("GitHub Items")),
    stateButton: nimkit.newPopupMenuButton("Open", nimkit.newMenu("GitHub State")),
    autoRefreshLabel: nimkit.newLabel("Auto-refresh"),
    autoRefreshSwitch: nimkit.newSwitchButton(),
    rootPath: snapshot.rootPath,
    executable: executable,
    state: snapshot.state,
    kinds: snapshot.kinds,
    repositoryBacked: repositoryBacked,
    refreshInterval: initDuration(milliseconds = refreshIntervalMilliseconds),
  )
  result.initViewFields()
  result.clipsToBounds = true
  result.acceptsFirstResponder = true
  discard result.withProtocol(GitHubLayout)
  result.markdownStyle = markdownStyle
  result.markdownView.headingsToggleOnClick = true
  for view in [
    nimkit.View(result.refreshButton), result.kindButton, result.stateButton,
    result.autoRefreshLabel, result.autoRefreshSwitch, result.markdownView,
  ]:
    result.addSubview(view)
  let weakPanel = result.unsafeWeakRef()
  result.autoRefreshSwitch.accessibilityLabel = "Automatically refresh GitHub"
  result.autoRefreshSwitch.accessibilityIdentifier = "kosmo.github.autoRefresh"
  let intervalSeconds =
    if refreshIntervalMilliseconds mod 1000 == 0:
      $(refreshIntervalMilliseconds div 1000)
    else:
      $(refreshIntervalMilliseconds.float / 1000)
  result.autoRefreshSwitch.toolTip =
    "Refresh every " & intervalSeconds & " seconds and after workspace changes"
  let linkDelegate = GitHubLinkDelegate(panel: weakPanel)
  discard linkDelegate.withProtocol(GitHubLinks)
  result.markdownView.textView().delegate = linkDelegate
  result.search = newKosmoViewerSearch(
    result,
    "GitHub",
    proc(): seq[string] =
      if not weakPanel.isNil:
        result.add weakPanel[].markdownView.textStorage().stringValue()
    ,
    proc(match: KosmoViewerMatch) =
      if not weakPanel.isNil:
        let panel = weakPanel[]
        panel.pendingSearchRange = some(match.range)
        if revealTextMatch(
          panel.markdownView.textView(), panel.markdownView.scrollView(), match.range
        ):
          panel.markdownView.selectMarkdownRange(match.range)
          panel.pendingSearchRange = none(nimkit.TextRange)
    ,
    proc() =
      if not weakPanel.isNil:
        weakPanel[].pendingSearchRange = none(nimkit.TextRange)
        weakPanel[].markdownView.selectMarkdownRange(nimkit.initTextRange(0, 0))
    ,
  )
  result.markdownView.connect(nimkit.markdownDidFinishParsing, result, parsingFinished)
  result.markdownView.textView().layoutManager().connect(
    nimkit.layoutDidComplete, result, searchLayoutFinished
  )
  let keyHandler: nimkit.DynamicMethod = proc(
      self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
  ) =
    let event = invocation.argsAs(nimkit.KeyEvent)
    if not weakPanel.isNil and not weakPanel[].closed:
      if weakPanel[].search.handleSearchKey(event):
        invocation.setResult(true)
      elif not weakPanel[].keyEquivalentHandler.isNil:
        invocation.setResult(weakPanel[].keyEquivalentHandler(event))
  discard result.markdownView.replaceMethod(
    nimkitSelectors.performKeyEquivalent(), keyHandler
  )
  discard result.replaceMethod(nimkitSelectors.performKeyEquivalent(), keyHandler)
  let refreshAction = nimkit.actionSelector("kosmo.refreshGitHub")
  result.refreshButton.action = refreshAction
  result.refreshButton.target = nimkit.newActionTarget(refreshAction) do(
    sender: nimkit.DynamicAgent
  ):
    if not weakPanel.isNil:
      weakPanel[].refresh()
  let autoRefreshAction = nimkit.actionSelector("kosmo.toggleGitHubAutoRefresh")
  result.autoRefreshSwitch.action = autoRefreshAction
  result.autoRefreshSwitch.target = nimkit.newActionTarget(autoRefreshAction) do(
    sender: nimkit.DynamicAgent
  ):
    if not weakPanel.isNil:
      if weakPanel[].autoRefreshSwitch.on:
        weakPanel[].scheduleRepositoryRefresh()
      else:
        weakPanel[].refreshPending = false
  for kinds in [{ghikIssue, ghikPullRequest}, {ghikIssue}, {ghikPullRequest}]:
    let title =
      if kinds == {ghikIssue}:
        "Issues"
      elif kinds == {ghikPullRequest}:
        "Pull Requests"
      else:
        "Issues & PRs"
    discard
      result.kindButton.menu().addItem(newGitHubFilterItem(weakPanel, title, kinds))
  for state in GitHubState:
    let title =
      case state
      of ghsOpen: "Open"
      of ghsClosed: "Closed"
      of ghsAll: "All States"
    discard result.stateButton.menu().addItem(
        newGitHubFilterItem(weakPanel, title, state = state)
      )
  result.applySnapshot(snapshot)
  if repositoryBacked:
    result.pool = newSigilThreadPool(workers = 1)
    result.pool.start()
    var worker = GitHubWorker()
    result.worker = worker.moveToThread(result.pool)
    connectThreaded(result.worker, readRepository, result.worker, readRepository)
    connectThreaded(
      result.worker, repositoryFinished, result, KosmoGitHubPanel.repositoryFinished()
    )
    result.refresh()

proc newKosmoGitHubPanel*(
    rootPath: string,
    markdownStyle = nimkit.initMarkdownStyle(),
    executable = "gh",
    refreshIntervalMilliseconds: Positive = GitHubDefaultRefreshIntervalMilliseconds,
): KosmoGitHubPanel =
  ## Open the project's current issues and PRs using an existing GitHub CLI login.
  newKosmoGitHubPanel(
    GitHubSnapshot(rootPath: rootPath),
    executable,
    true,
    markdownStyle,
    refreshIntervalMilliseconds,
  )

proc newKosmoGitHubPanel*(
    snapshot: GitHubSnapshot, markdownStyle = nimkit.initMarkdownStyle()
): KosmoGitHubPanel =
  ## Construct an offline GitHub document from a snapshot.
  newKosmoGitHubPanel(
    snapshot, "gh", false, markdownStyle, GitHubDefaultRefreshIntervalMilliseconds
  )
