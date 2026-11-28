## A searchable GitHub document backed by a cancellable gh worker.

import std/[atomics, monotimes, options, os, strutils, tables, times]
import sigils/[core, threadProxies, threads]
import threading/smartptrs
import ../nimkit as nimkit
import ../nimkit/foundation/mainthreadwork
import ../nimkit/foundation/selectors as nimkitSelectors
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./readerpresentation
import ./themetargets
import ./scrolling

import ./[github, hintsmode, searchbar, viewerbuttons, viewersearch, vscodegrammars]

export github

const
  KosmoGitHubTabIdentifier* = "kosmo.github"
  GitHubDefaultRefreshIntervalMilliseconds* = 180_000
  GitHubRefreshDebounceInterval = initDuration(milliseconds = 300)

type
  GitHubRequestControl = object
    cancelled: Atomic[bool]

  GitHubWorker = ref object of AgentActor

  GitHubLinkDelegate = ref object of nimkit.DynamicAgent
    panel: WeakRef[KosmoGitHubPanel]

  GitHubLinkHandler* = proc(link: string): bool {.closure.}

  GitHubDiffHandler* = proc(rootPath: string, item: GitHubItem): bool {.closure.}

  GitHubKeyEquivalentHandler* = proc(event: nimkit.KeyEvent): bool {.closure.}

  KosmoGitHubPanel* = ref object of nimkit.View
    markdownView*: nimkit.MarkdownView
    refreshButton*: nimkit.Button
    kindButton*: nimkit.PopupMenuButton
    stateButton*: nimkit.PopupMenuButton
    autoRefreshSwitch*: nimkit.SwitchButton
    autoRefreshLabel: nimkit.Label
    mergeStatusLabel: nimkit.Label
    mergeButtons: Table[int, array[GitHubMergeMethod, nimkit.Button]]
    snapshot*: GitHubSnapshot
    search: KosmoViewerSearch
    pool: SigilThreadPoolPtr
    worker: AgentProxy[GitHubWorker]
    control: SharedPtr[GitHubRequestControl]
    rootPath: string
    executable: string
    state: GitHubState
    kinds: set[GitHubItemKind]
    openPullRequests: seq[int]
    pullRequestSectionCollapsed: bool
    generation: uint64
    loading*: bool
    merging: bool
    closed*: bool
    repositoryBacked: bool
    refreshPending: bool
    refreshDeadline, nextRefresh: MonoTime
    refreshInterval: Duration
    keyEquivalentHandler: GitHubKeyEquivalentHandler
    linkHandler: GitHubLinkHandler
    diffHandler: GitHubDiffHandler
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
  openPullRequests: seq[int],
  generation: uint64,
  previousSnapshot: GitHubSnapshot,
  detailsOnly: bool,
  control: SharedPtr[GitHubRequestControl],
) {.signal.}

proc repositoryFinished(
  worker: GitHubWorker, snapshot: GitHubSnapshot, generation: uint64
) {.signal.}

proc mergePullRequest(
  worker: AgentProxy[GitHubWorker],
  root, executable: string,
  item: GitHubItem,
  mergeMethod: GitHubMergeMethod,
  control: SharedPtr[GitHubRequestControl],
) {.signal.}

proc mergeFinished(
  worker: GitHubWorker, root: string, number: int, error: string
) {.signal.}

proc mergePullRequest(
    worker: GitHubWorker,
    root, executable: string,
    item: GitHubItem,
    mergeMethod: GitHubMergeMethod,
    control: SharedPtr[GitHubRequestControl],
) {.slot.} =
  let cancelled = proc(): bool {.gcsafe.} =
    control[].cancelled.load(moAcquire)
  let error = mergeGitHubPullRequest(root, item, mergeMethod, executable, cancelled)
  if not cancelled():
    emit worker.mergeFinished(root, item.number, error)

proc readRepository(
    worker: GitHubWorker,
    root, executable: string,
    state: GitHubState,
    kinds: set[GitHubItemKind],
    openPullRequests: seq[int],
    generation: uint64,
    previousSnapshot: GitHubSnapshot,
    detailsOnly: bool,
    control: SharedPtr[GitHubRequestControl],
) {.slot.} =
  let cancelled = proc(): bool {.gcsafe.} =
    control[].cancelled.load(moAcquire)
  let snapshot = readGitHubSnapshot(
    root,
    state,
    kinds,
    executable = executable,
    cancelled = cancelled,
    openPullRequests = openPullRequests,
    previousSnapshot = previousSnapshot,
    detailsOnly = detailsOnly,
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
    panel.repositoryBacked and not panel.loading and not panel.merging and
    not panel.closed
  panel.autoRefreshSwitch.enabled = panel.repositoryBacked and not panel.closed
  for buttons in panel.mergeButtons.values:
    for button in buttons:
      button.enabled = not panel.loading and not panel.merging and not panel.closed

proc setMergeStatus(panel: KosmoGitHubPanel, status: string) =
  panel.mergeStatusLabel.text = status.splitWhitespace().join(" ")
  panel.mergeStatusLabel.toolTip = status
  panel.mergeStatusLabel.hidden = status.len == 0
  panel.needsLayout = true

proc applySnapshot(panel: KosmoGitHubPanel, snapshot: GitHubSnapshot) =
  ## Show an already prepared snapshot, including offline fixtures.
  if panel.isNil or panel.closed:
    return
  let preserveHeadingState = panel.snapshot.rootPath == snapshot.rootPath
  let headingIdentifiers = snapshot.gitHubHeadingIdentifiers()
  var collapsedItems: seq[string]
  for identifier in headingIdentifiers:
    if identifier notin ["github-project", "github-issues", "github-pull-requests"]:
      collapsedItems.add identifier
  panel.snapshot = snapshot
  panel.markdownView.updateMarkdown(
    snapshot.gitHubMarkdown(mergeActions = panel.repositoryBacked),
    headingIdentifiers,
    preserveHeadingState = preserveHeadingState,
    initiallyCollapsedHeadings = collapsedItems,
  )
  panel.syncControls()

proc repositoryFinished(
    panel: KosmoGitHubPanel, snapshot: GitHubSnapshot, generation: uint64
) {.slot.} =
  if not panel.closed and generation == panel.generation:
    panel.loading = false
    panel.nextRefresh = getMonoTime() + panel.refreshInterval
    panel.applySnapshot(snapshot)

proc replaceRequestControl(panel: KosmoGitHubPanel) =
  if not panel.control.isNil:
    panel.control[].cancelled.store(true, moRelease)
  panel.control = newSharedPtr(GitHubRequestControl)
  panel.control[].cancelled.store(false, moRelaxed)
  inc panel.generation

proc startRefresh(panel: KosmoGitHubPanel, details: seq[int] = @[]) =
  ## Cancel obsolete requests and load the current repository off the UI thread.
  if panel.isNil or panel.closed or not panel.repositoryBacked or panel.merging:
    return
  panel.replaceRequestControl()
  panel.refreshPending = false
  panel.nextRefresh = getMonoTime() + panel.refreshInterval
  panel.loading = true
  panel.syncControls()
  emit panel.worker.readRepository(
    panel.rootPath,
    panel.executable,
    panel.state,
    panel.kinds,
    (
      if details.len > 0: details
      elif panel.pullRequestSectionCollapsed: @[]
      else: panel.openPullRequests
    ),
    panel.generation,
    panel.snapshot,
    details.len > 0,
    panel.control,
  )

proc refresh*(panel: KosmoGitHubPanel) =
  panel.startRefresh()

proc mergeFinished(
    panel: KosmoGitHubPanel, root: string, number: int, error: string
) {.slot.} =
  if not panel.closed:
    panel.merging = false
    if root == panel.rootPath:
      panel.setMergeStatus(
        if error.len == 0:
          "Merged pull request #" & $number & "."
        else:
          "Could not merge pull request #" & $number & ". " & error
      )
    panel.refresh()

proc mergeItem(panel: KosmoGitHubPanel, number: int): Option[GitHubItem] =
  if not panel.closed and panel.repositoryBacked and not panel.merging and
      panel.state != ghsClosed and ghikPullRequest in panel.kinds and
      not panel.pullRequestSectionCollapsed and number in panel.openPullRequests:
    for item in panel.snapshot.items:
      if item.number == number and item.canMergePullRequest():
        return some(item)

proc startMerge(
    panel: KosmoGitHubPanel,
    root: string,
    confirmed: GitHubItem,
    mergeMethod: GitHubMergeMethod,
) =
  let current = panel.mergeItem(confirmed.number)
  if root != panel.rootPath or current.isNone:
    return
  let item = current.get()
  if item.url != confirmed.url or item.headSha != confirmed.headSha or
      item.baseBranch != confirmed.baseBranch:
    panel.setMergeStatus(
      "Pull request #" & $item.number & " changed. Review it and try again."
    )
    return
  panel.replaceRequestControl()
  panel.loading = false
  panel.refreshPending = false
  panel.merging = true
  panel.setMergeStatus("Merging pull request #" & $item.number & "…")
  panel.syncControls()
  emit panel.worker.mergePullRequest(
    root, panel.executable, item, mergeMethod, panel.control
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
  if panel.loading or panel.merging:
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
    panel.openPullRequests.setLen(0)
    panel.pullRequestSectionCollapsed = false
    panel.rootPath = rootPath
    panel.setMergeStatus("")
    panel.applySnapshot(
      GitHubSnapshot(rootPath: rootPath, state: panel.state, kinds: panel.kinds)
    )
  panel.repositoryBacked = true
  panel.refresh()

proc githubHeadingToggled(
    panel: KosmoGitHubPanel, identifier: string, collapsed: bool
) {.slot.} =
  const prefix = "github-pull-requests-"
  if panel.isNil or panel.closed or not panel.repositoryBacked:
    return
  if identifier == "github-pull-requests":
    panel.pullRequestSectionCollapsed = collapsed
    if not collapsed and panel.openPullRequests.len > 0:
      panel.refresh()
    return
  if not identifier.startsWith(prefix):
    return
  var number: int
  try:
    number = parseInt(identifier[prefix.len .. ^1])
  except ValueError:
    return
  let index = panel.openPullRequests.find(number)
  if collapsed:
    if index >= 0:
      panel.openPullRequests.delete(index)
  elif index < 0:
    panel.openPullRequests.add number
    if panel.loading:
      panel.refresh()
    else:
      panel.startRefresh(@[number])

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
    if not panel.loading and not panel.merging and not panel.refreshPending and
        not panel.markdownView.isMarkdownParsing() and
        not panel.markdownView.isMarkdownRendering() and
        not panel.markdownView.textView().layoutManager().isBackgroundLayoutPending():
      return true
    sleep(1)

func gitHubReaderStyle*(style: nimkit.MarkdownStyle): nimkit.MarkdownStyle =
  ## A compact heading scale relative to body text. Item titles (H3) read as
  ## list rows, and demoted description headings (H4-H6) stay near body size.
  const scale = [1.5'f32, 1.25'f32, 1.15'f32, 1.08'f32, 1.0'f32, 0.93'f32]
  result = style
  for index, factor in scale:
    result.headingFontSizes[index] = style.bodyFontSize * factor

proc `markdownStyle=`*(panel: KosmoGitHubPanel, style: nimkit.MarkdownStyle) =
  panel.markdownView.markdownStyle = style.gitHubReaderStyle()

proc `keyEquivalentHandler=`*(
    panel: KosmoGitHubPanel, handler: GitHubKeyEquivalentHandler
) =
  panel.keyEquivalentHandler = handler

proc showSearch*(panel: KosmoGitHubPanel): bool {.discardable.} =
  panel.search.showSearch()

proc toggleToolbarFocus*(panel: KosmoGitHubPanel, focused: nimkit.Responder): bool =
  ## Toggle keyboard focus between the GitHub content and the panel toolbar.
  ## The toolbar target is the first visible, enabled control.
  if panel.isNil or panel.markdownView.isNil:
    return false
  let owner = panel.window()
  if not (owner of nimkit.Window):
    return false
  let window = nimkit.Window(owner)
  for control in [
    nimkit.Control(panel.refreshButton), panel.kindButton, panel.stateButton,
    panel.autoRefreshSwitch,
  ]:
    if not control.isNil and not control.hidden():
      if focused == nimkit.Responder(control):
        return window.makeFirstResponder(panel.markdownView.textView())
      if control.enabled:
        return window.makeFirstResponder(control)
  false

protocol GitHubToolbarFocus of nimkit.ToolbarFocusProtocol:
  method requestToolbarFocus(
      panel: KosmoGitHubPanel, focused: nimkit.Responder
  ): Option[bool] =
    some(panel.toggleToolbarFocus(focused))

proc searchField*(panel: KosmoGitHubPanel): nimkit.TextField =
  panel.search.bar.queryField()

proc searchMatchCount*(panel: KosmoGitHubPanel): int =
  panel.search.searchMatchCount()

proc `linkHandler=`*(panel: KosmoGitHubPanel, handler: GitHubLinkHandler) =
  ## Handle external HTTP links using the host application's workspace service.
  panel.linkHandler = handler

proc `diffHandler=`*(panel: KosmoGitHubPanel, handler: GitHubDiffHandler) =
  ## Open a PR comparison in the host application's Git diff viewer.
  panel.diffHandler = handler

func mergeTitle(mergeMethod: GitHubMergeMethod): string =
  case mergeMethod
  of GitHubMergeMethod.Merge: "Create a merge commit"
  of GitHubMergeMethod.Squash: "Squash and merge"
  of GitHubMergeMethod.Rebase: "Rebase and merge"

proc confirmMerge(
    panel: KosmoGitHubPanel, number: int, mergeMethod: GitHubMergeMethod
) =
  let selected = panel.mergeItem(number)
  let owner = panel.window()
  if selected.isNone or not (owner of nimkit.Window):
    return
  let parent = nimkit.Window(owner)
  let responder = parent.nextResponder()
  if not (responder of nimkit.Application):
    return
  let app = nimkit.Application(responder)
  if app.windowBlockedByModal(parent):
    return
  let
    item = selected.get()
    root = panel.rootPath
    title = mergeMethod.mergeTitle()
    destination =
      if item.baseBranch.len > 0:
        " into " & item.baseBranch
      else:
        ""
    alert = nimkit.newAlert(
      title & "?",
      "Merge #" & $item.number & " " & item.title & destination & "?\n" & item.url,
      style = nimkit.asWarning,
      buttons = ["Cancel", title],
    )
    weakPanel = panel.unsafeWeakRef()
    mergeResponse = alert.buttonResponse(1)
  alert.window.setInheritedAppearance(parent.effectiveAppearance())
  var session: nimkit.ModalSession
  alert.prepareForModal(
    proc(response: int) =
      app.endModalSession(session)
      alert.window.close()
      if response == mergeResponse and not weakPanel.isNil:
        weakPanel[].startMerge(root, item, mergeMethod)
  )
  session = app.beginModalSheet(parent, alert.window)

proc newMergeButton(
    panel: KosmoGitHubPanel, number: int, mergeMethod: GitHubMergeMethod
): nimkit.Button =
  result = nimkit.newButton(mergeMethod.mergeTitle())
  result.accessibilityIdentifier = "kosmo.github.merge." & $number & "." & $mergeMethod
  result.enabled = not panel.loading and not panel.merging
  let
    action = nimkit.actionSelector("kosmo.mergeGitHubPullRequest")
    weakPanel = panel.unsafeWeakRef()
  result.action = action
  result.target = nimkit.newActionTarget(action) do(sender: nimkit.DynamicAgent):
    if not weakPanel.isNil:
      weakPanel[].confirmMerge(number, mergeMethod)

proc layoutMergeButtons(panel: KosmoGitHubPanel, snapshot: nimkit.TextLayoutSnapshot) =
  if not panel.repositoryBacked:
    return
  let textView = panel.markdownView.textView()
  var previous = move panel.mergeButtons
  var anchors: Table[string, int]
  if not panel.pullRequestSectionCollapsed and panel.state != ghsClosed and
      ghikPullRequest in panel.kinds:
    for item in panel.snapshot.items:
      if item.number in panel.openPullRequests and item.canMergePullRequest():
        anchors[GitHubMergeAnchorPrefix & $item.number] = item.number
  var line = 0
  if anchors.len > 0:
    for run in textView.textStorage().attributeRuns():
      let link = run.attributes.link
      # PR descriptions are rendered as block quotes. Only the generated
      # top-level paragraph can position merge controls.
      if run.attributes.paragraphStyle.headIndent == 0 and link in anchors:
        let location = int(run.range.location)
        while line < snapshot.lineFragments.len and
            snapshot.lineFragments[line].textRange.maxIndex <= location:
          inc line
        if line < snapshot.lineFragments.len and
            int(snapshot.lineFragments[line].textRange.location) == location:
          let
            number = anchors[link]
            fragment = snapshot.lineFragments[line]
            x = fragment.usedRect.minX
            gap = 6.0'f32
          var buttons: array[GitHubMergeMethod, nimkit.Button]
          if number in previous:
            buttons = previous[number]
            previous.del(number)
          else:
            for mergeMethod in GitHubMergeMethod:
              buttons[mergeMethod] = panel.newMergeButton(number, mergeMethod)
              textView.addSubview(buttons[mergeMethod])
          var widths: array[GitHubMergeMethod, float32]
          var totalWidth = 0.0'f32
          for mergeMethod, button in buttons:
            widths[mergeMethod] = button.sizeThatFits().width
            totalWidth += widths[mergeMethod]
          let scale = min(
            1.0'f32,
            max(fragment.fragmentRect.maxX - x - gap * 2, 0) / max(totalWidth, 1),
          )
          var nextX = x
          for mergeMethod, button in buttons:
            let width = widths[mergeMethod] * scale
            button.setFrameFromLayout(
              nimkit.rect(nextX, fragment.usedRect.minY, width, 24)
            )
            nextX += width + gap
          panel.mergeButtons[number] = buttons
          anchors.del(link)
  for buttons in previous.values:
    for button in buttons:
      button.removeFromSuperview()

protocol GitHubLinks of nimkit.TextViewDelegateProtocol:
  method tvClickedLink(
      delegate: GitHubLinkDelegate,
      textView: nimkit.TextView,
      link: string,
      range: nimkit.TextRange,
  ): bool =
    if not delegate.panel.isNil:
      let panel = delegate.panel[]
      if not panel.closed and link.startsWith(GitHubDiffLinkPrefix):
        for item in panel.snapshot.items:
          if item.kind == ghikPullRequest and item.number > 0 and
              link == GitHubDiffLinkPrefix & $item.number and item.baseBranch.len > 0 and
              item.headBranch.len > 0 and not panel.diffHandler.isNil:
            return panel.diffHandler(panel.snapshot.rootPath, item)
        return false
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
  if panel.closed:
    return
  panel.layoutMergeButtons(snapshot)
  if panel.pendingSearchRange.isSome and panel.search.searchVisible():
    let range = panel.pendingSearchRange.get()
    if revealTextMatch(
      panel.markdownView.textView(), panel.markdownView.scrollView(), range
    ):
      panel.markdownView.selectMarkdownRange(range)
      panel.pendingSearchRange = none(nimkit.TextRange)

protocol GitHubLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(panel: KosmoGitHubPanel) =
    let
      bounds = panel.bounds()
      inset = min(12.0'f32, bounds.size.width * 0.05'f32)
      gap = min(8.0'f32, bounds.size.width * 0.03'f32)
      availableWidth = max(bounds.size.width - inset * 2, 0)
      labelGap = min(2.0'f32, availableWidth)
      labelWidth = panel.autoRefreshLabel.sizeThatFits().width
      switchWidth = panel.autoRefreshSwitch.sizeThatFits().width
      contentWidth = 180 + 140 + labelWidth + switchWidth + 44
      scale = min(max(availableWidth - gap * 3 - labelGap, 0) / contentWidth, 1)
      refreshWidth = 44 * scale
      refreshX = bounds.size.width - inset - refreshWidth
      switchX = refreshX - gap - switchWidth * scale
      labelX = switchX - labelGap - labelWidth * scale
    panel.refreshButton.setFrameFromLayout(nimkit.rect(refreshX, 8, refreshWidth, 28))
    panel.kindButton.setFrameFromLayout(nimkit.rect(inset, 8, 180 * scale, 28))
    panel.stateButton.setFrameFromLayout(
      nimkit.rect(inset + 180 * scale + gap, 8, 140 * scale, 28)
    )
    panel.autoRefreshLabel.setFrameFromLayout(
      nimkit.rect(labelX, 8, labelWidth * scale, 28)
    )
    panel.autoRefreshSwitch.setFrameFromLayout(
      nimkit.rect(switchX, 8, switchWidth * scale, 28)
    )
    var contentTop = 44.0'f32
    if not panel.mergeStatusLabel.hidden():
      panel.mergeStatusLabel.setFrameFromLayout(
        nimkit.rect(inset, contentTop, availableWidth, 24)
      )
      contentTop += 24
    panel.markdownView.setFrameFromLayout(
      nimkit.rect(
        0, contentTop, bounds.size.width, max(bounds.size.height - contentTop, 0)
      )
    )

proc newGitHubFilterItem(
    panel: WeakRef[KosmoGitHubPanel],
    title: string,
    kinds: set[GitHubItemKind] = {},
    state = ghsOpen,
): nimkit.MenuItem =
  # A separate call owns each captured selection; loop closures share locals.
  let action = nimkit.actionSelector(sig"kosmo.selectGitHubFilter")
  result = nimkit.newMenuItem(title, action)
  result.validates = false
  result.target = nimkit.newActionTarget(action) do(sender: nimkit.DynamicAgent):
    if not panel.isNil:
      if kinds == {}:
        panel[].selectFilter(state, panel[].kinds)
      else:
        panel[].selectFilter(panel[].state, kinds)

protocol GitHubReaderPresentation of KosmoReaderPresentationProtocol:
  method readerThemeTarget(panel: KosmoGitHubPanel): Option[KosmoThemeTarget] =
    some(KosmoThemeTarget.GitHub)

  method applyReaderStyle(panel: KosmoGitHubPanel, style: nimkit.MarkdownStyle) =
    panel.markdownStyle = style

proc githubHintWorkingDirectory(panel: KosmoGitHubPanel): string =
  ## Resolve hint paths against the repository the reader displays, like the
  ## Git diff panel; readers without a repository fall back to the process
  ## working directory.
  if panel.rootPath.len > 0:
    panel.rootPath
  else:
    getCurrentDir()

protocol KosmoGitHubHintSurface of KosmoHintSurfaceProtocol:
  method showKosmoHintMode(panel: KosmoGitHubPanel, args: KosmoHintModeArgs): bool =
    ## Present hint markers over the reader's rendered Markdown and run the
    ## request's action on the selected snippet. Terminal insertion is
    ## declined; only the focused terminal attaches the insert hook.
    if panel.isNil or panel.closed or not args.kosmoHintActionSupported():
      return false
    let textView = panel.markdownView.textView()
    presentKosmoHints(
      textView,
      textView.collectTextViewHints(args.kind, panel.githubHintWorkingDirectory()),
    ) do(hint: KosmoHint):
      discard runKosmoHintAction(hint, args.action, args.activation)

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
    refreshButton: newViewerRefreshButton("Refresh GitHub"),
    kindButton:
      nimkit.newPopupMenuButton("Issues & PRs", nimkit.newMenu("GitHub Items")),
    stateButton: nimkit.newPopupMenuButton("Open", nimkit.newMenu("GitHub State")),
    autoRefreshLabel: nimkit.newLabel("Auto-refresh"),
    autoRefreshSwitch: nimkit.newSwitchButton(),
    mergeStatusLabel: nimkit.newLabel(),
    rootPath: snapshot.rootPath,
    executable: executable,
    state: snapshot.state,
    kinds: snapshot.kinds,
    repositoryBacked: repositoryBacked,
    refreshInterval: initDuration(milliseconds = refreshIntervalMilliseconds),
  )
  result.initViewFields()
  result.markdownView.scrollView().controlScrollMultiplier =
    KosmoControlScrollMultiplier
  discard result.withProtocol(GitHubReaderPresentation)
  discard result.withProtocol(KosmoGitHubHintSurface)
  discard result.withProtocol(GitHubToolbarFocus)
  result.markdownView.matterGrammarSources =
    installedVscodeGrammars().viewerGrammarSources()
  result.clipsToBounds = true
  result.focusable = true
  discard result.withProtocol(GitHubLayout)
  result.markdownStyle = markdownStyle
  result.markdownView.headingsToggleOnClick = true
  result.mergeStatusLabel.accessibilityIdentifier = "kosmo.github.mergeStatus"
  result.setMergeStatus("")
  for view in [
    nimkit.View(result.refreshButton), result.kindButton, result.stateButton,
    result.autoRefreshLabel, result.autoRefreshSwitch, result.mergeStatusLabel,
    result.markdownView,
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
  result.markdownView.connect(
    nimkit.markdownHeadingDidToggle, result, githubHeadingToggled
  )
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
      elif not weakPanel[].keyEquivalentHandler.isNil and
          weakPanel[].keyEquivalentHandler(event):
        invocation.setResult(true)
      elif self == weakPanel[].markdownView:
        invocation.setResult(
          weakPanel[].markdownView.handleMarkdownNavigationKey(event)
        )
  discard result.markdownView.replaceMethod(
    nimkitSelectors.performKeyEquivalent(), keyHandler
  )
  discard result.replaceMethod(nimkitSelectors.performKeyEquivalent(), keyHandler)
  let refreshAction = nimkit.actionSelector(sig"kosmo.refreshGitHub")
  result.refreshButton.action = refreshAction
  result.refreshButton.target = nimkit.newActionTarget(refreshAction) do(
    sender: nimkit.DynamicAgent
  ):
    if not weakPanel.isNil:
      weakPanel[].refresh()
  let autoRefreshAction = nimkit.actionSelector(sig"kosmo.toggleGitHubAutoRefresh")
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
    discard result.kindButton.menu().add(newGitHubFilterItem(weakPanel, title, kinds))
  for state in GitHubState:
    let title =
      case state
      of ghsOpen: "Open"
      of ghsClosed: "Closed"
      of ghsAll: "All States"
    discard result.stateButton.menu().add(
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
    connectThreaded(result.worker, mergePullRequest, result.worker, mergePullRequest)
    connectThreaded(
      result.worker, mergeFinished, result, KosmoGitHubPanel.mergeFinished()
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
