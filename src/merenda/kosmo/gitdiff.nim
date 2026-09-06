## Full-context Git patches presented as collapsible Markdown code blocks.

import std/[atomics, monotimes, os, osproc, sets, streams, strutils, times, unicode]
import sigils/[core, threadProxies, threads]
import threading/smartptrs
when defined(posix):
  import std/posix
import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout

const KosmoGitDiffTabIdentifier* = "kosmo.gitDiff"

type
  GitFileDiff* = object
    path*: string
    patch*: string

  GitDiffSnapshot* = object
    rootPath*: string
    files*: seq[GitFileDiff]
    errorMessage*: string

  GitDiffWorker = ref object of AgentActor

  GitDiffControl = object
    cancelled: Atomic[bool]

  GitDiffLinkDelegate = ref object of nimkit.Responder
    panel: WeakRef[KosmoGitDiffPanel]

  KosmoGitDiffPanel* = ref object of nimkit.View
    markdownView*: nimkit.MarkdownView
    refreshButton*: nimkit.Button
    expandButton*: nimkit.Button
    collapseButton*: nimkit.Button
    snapshot*: GitDiffSnapshot
    collapsed: HashSet[string]
    pool: SigilThreadPoolPtr
    worker: AgentProxy[GitDiffWorker]
    loading: bool
    closed: bool
    control: SharedPtr[GitDiffControl]

proc executeGit(
    root: string, args: openArray[string], control: SharedPtr[GitDiffControl]
): tuple[output: string, code: int] =
  if control[].cancelled.load(moAcquire):
    raise newException(IOError, "Git diff cancelled")
  var arguments = @["--no-optional-locks", "--literal-pathspecs", "-C", root]
  arguments.add args
  let process =
    startProcess("git", args = arguments, options = {poUsePath, poStdErrToStdOut})
  defer:
    if process.peekExitCode() == -1:
      process.kill()
      discard process.waitForExit()
    process.close()
  var buffer: array[16384, char]
  while true:
    if control[].cancelled.load(moAcquire):
      raise newException(IOError, "Git diff cancelled")
    when defined(posix):
      var ready = TPollfd(fd: process.outputHandle(), events: POLLIN)
      if posix.poll(addr ready, 1, 25) > 0:
        let count = posix.read(process.outputHandle(), addr buffer[0], buffer.len)
        if count == 0:
          break
        if count < 0:
          raise newException(IOError, "Could not read Git output")
        let offset = result.output.len
        result.output.setLen(offset + count)
        copyMem(addr result.output[offset], addr buffer[0], count)
    else:
      if process.hasData():
        let count = process.outputStream().readData(addr buffer[0], buffer.len)
        if count > 0:
          let offset = result.output.len
          result.output.setLen(offset + count)
          copyMem(addr result.output[offset], addr buffer[0], count)
      elif process.peekExitCode() != -1:
        break
      else:
        sleep(25)
  while process.peekExitCode() == -1:
    if control[].cancelled.load(moAcquire):
      raise newException(IOError, "Git diff cancelled")
    sleep(25)
  result.code = process.peekExitCode()

proc readGitDiff(
    rootPath: string, control: SharedPtr[GitDiffControl]
): GitDiffSnapshot =
  ## Read staged and unstaged changes against HEAD, plus untracked files.
  ## Unborn repositories treat their files as additions. Git runs without shell,
  ## external diff drivers, text conversion, or modifications to the index.
  result.rootPath = rootPath
  proc runGit(root: string, args: openArray[string]): tuple[output: string, code: int] =
    executeGit(root, args, control)

  try:
    let repository = runGit(rootPath, ["rev-parse", "--show-toplevel"])
    if repository.code != 0:
      result.errorMessage =
        "This folder is not a Git working tree.\n" & repository.output.strip()
      return
    result.rootPath = repository.output.strip()
    let hasHead = runGit(result.rootPath, ["rev-parse", "--verify", "HEAD"]).code == 0
    let names =
      if hasHead:
        runGit(
          result.rootPath,
          [
            "diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-only",
            "-z", "HEAD", "--",
          ],
        )
      else:
        runGit(result.rootPath, ["ls-files", "--cached", "-z"])
    let untracked =
      runGit(result.rootPath, ["ls-files", "--others", "--exclude-standard", "-z"])
    if names.code != 0 or untracked.code != 0:
      result.errorMessage =
        "Could not list changed files.\n" & names.output & untracked.output
      return
    let untrackedPaths = untracked.output.split('\0').toHashSet()
    var seen = initHashSet[string]()
    for group in [names.output, untracked.output]:
      for path in group.split('\0'):
        if path.len > 0 and path notin seen:
          seen.incl path
          let isAddition = not hasHead or path in untrackedPaths
          var args =
            @[
              "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames",
              "--unified=2147483647",
            ]
          if isAddition:
            args.add ["--no-index", "--", "/dev/null", path]
          else:
            args.add ["HEAD", "--", path]
          let patch = runGit(result.rootPath, args)
          if patch.code == 0 or (isAddition and patch.code == 1):
            if patch.output.len > 0:
              result.files.add GitFileDiff(path: path, patch: patch.output)
          else:
            result.errorMessage =
              "Could not read diff for " & path & ":\n" & patch.output
            return
  except CatchableError:
    result.errorMessage = getCurrentExceptionMsg()

proc readGitDiff*(rootPath: string): GitDiffSnapshot =
  ## Read the saved working tree against HEAD with full-file context.
  readGitDiff(rootPath, newSharedPtr(GitDiffControl))

proc markdownLabel(value: string): string =
  for ch in value:
    case ch
    of '\\', '[', ']', '*', '_', '`', '<', '>':
      result.add '\\'
      result.add ch
    of '\n', '\r':
      result.add ' '
    else:
      result.add ch

proc fencedPatch(patch: string): string =
  var fence = "```"
  while fence in patch:
    fence.add '`'
  fence & "diff\n" & patch & "\n" & fence & "\n\n"

proc diffHighlight(source, language: string): seq[nimkit.SyntaxTokenSpan] =
  discard language
  var offset = 0
  for line in source.splitLines(keepEol = true):
    let length = line.runeLen
    if line.len > 0 and line[0] in {'+', '-', '@'}:
      let token =
        case line[0]
        of '+': nimkit.stcString
        of '-': nimkit.stcKeyword
        else: nimkit.stcComment
      if result.len > 0 and result[^1].tokenClass == token and
          result[^1].range.location + result[^1].range.length == offset:
        result[^1].range.length += length
      else:
        result.add nimkit.SyntaxTokenSpan(
          range: nimkit.initTextRange(offset, length), tokenClass: token
        )
    offset += length

proc renderDiff(panel: KosmoGitDiffPanel) =
  var document = "# Git Diff\n\n"
  document.add panel.snapshot.rootPath.markdownLabel() & "\n\n"
  if panel.loading:
    document.add "Loading changes…\n"
  elif panel.snapshot.errorMessage.len > 0:
    document.add "Could not load Git diff.\n\n" &
      panel.snapshot.errorMessage.fencedPatch()
  elif panel.snapshot.files.len == 0:
    document.add "No changes. Your working tree matches HEAD.\n"
  else:
    document.add "Staged and unstaged changes against HEAD, including untracked files. " &
      "Full-file context using the current Markdown syntax colors.\n\n"
    for index, file in panel.snapshot.files:
      let collapsed = file.path in panel.collapsed
      document.add "## [" & (if collapsed: "▸ " else: "▾ ") &
        file.path.markdownLabel() & "](kosmo-diff:" & $index & ")\n\n"
      if not collapsed:
        document.add file.patch.fencedPatch()
  panel.markdownView.markdown = document

proc toggleFile*(panel: KosmoGitDiffPanel, index: int) =
  ## Toggle a file section without rereading Git.
  if index in 0 ..< panel.snapshot.files.len:
    let path = panel.snapshot.files[index].path
    if path in panel.collapsed:
      panel.collapsed.excl path
    else:
      panel.collapsed.incl path
    panel.renderDiff()

proc isFileCollapsed*(panel: KosmoGitDiffPanel, index: int): bool =
  index in 0 ..< panel.snapshot.files.len and
    panel.snapshot.files[index].path in panel.collapsed

protocol GitDiffLinks of nimkit.TextViewDelegateProtocol:
  method tvClickedLink(
      delegate: GitDiffLinkDelegate,
      view: nimkit.TextView,
      link: string,
      range: nimkit.TextRange,
  ): bool =
    discard view
    discard range
    if link.startsWith("kosmo-diff:") and not delegate.panel.isNil:
      try:
        delegate.panel[].toggleFile(parseInt(link[11 .. ^1]))
      except ValueError:
        discard
      return true

proc executeDiff(
  worker: AgentProxy[GitDiffWorker], root: string, control: SharedPtr[GitDiffControl]
) {.signal.}

proc diffFinished(worker: GitDiffWorker, snapshot: GitDiffSnapshot) {.signal.}
proc executeDiff(
    worker: GitDiffWorker, root: string, control: SharedPtr[GitDiffControl]
) {.slot.} =
  emit worker.diffFinished(readGitDiff(root, control))

proc applyDiff(panel: KosmoGitDiffPanel, snapshot: GitDiffSnapshot) {.slot.} =
  if not panel.closed:
    panel.loading = false
    panel.snapshot = snapshot
    panel.refreshButton.enabled = true
    panel.renderDiff()

proc refresh*(panel: KosmoGitDiffPanel) =
  ## Refresh the current repository on a worker thread.
  if not panel.closed and not panel.loading:
    panel.loading = true
    panel.refreshButton.enabled = false
    panel.renderDiff()
    emit panel.worker.executeDiff(panel.snapshot.rootPath, panel.control)

proc waitForDiff*(panel: KosmoGitDiffPanel, timeoutMilliseconds = 10000): bool =
  ## Deliver worker results until the diff finishes, for callers without an event loop.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while panel.loading and getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    if panel.loading:
      sleep(1)
  not panel.loading

proc close*(panel: KosmoGitDiffPanel) {.slot.} =
  if not panel.closed:
    panel.closed = true
    panel.control[].cancelled.store(true, moRelease)
    panel.pool.stop(immediate = true)
    panel.pool.join()
    discard getCurrentSigilThread().pollAll(NonBlocking)

protocol GitDiffLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(panel: KosmoGitDiffPanel) =
    let
      bounds = panel.bounds()
      inset = min(12.0'f32, bounds.size.width * 0.05'f32)
      gap = min(8.0'f32, bounds.size.width * 0.03'f32)
      availableWidth = max(bounds.size.width - inset * 2.0'f32 - gap * 2.0'f32, 0)
      scale = min(availableWidth / 310.0'f32, 1.0'f32)
      refreshWidth = 90.0'f32 * scale
      actionWidth = 110.0'f32 * scale
      expandX = inset + refreshWidth + gap
      collapseX = expandX + actionWidth + gap
    panel.refreshButton.setFrameFromLayout(nimkit.rect(inset, 8, refreshWidth, 28))
    panel.expandButton.setFrameFromLayout(nimkit.rect(expandX, 8, actionWidth, 28))
    panel.collapseButton.setFrameFromLayout(nimkit.rect(collapseX, 8, actionWidth, 28))
    panel.markdownView.setFrameFromLayout(
      nimkit.rect(0, 44, bounds.size.width, max(bounds.size.height - 44, 0))
    )

proc newKosmoGitDiffPanel*(
    rootPath: string, markdownStyle = nimkit.initMarkdownStyle()
): KosmoGitDiffPanel =
  ## Construct a full-file diff reader with collapsible file headings.
  startLocalThreadDefault()
  result = KosmoGitDiffPanel(
    markdownView: nimkit.newMarkdownView(syntaxHighlighter = diffHighlight),
    refreshButton: nimkit.newButton("Refresh"),
    expandButton: nimkit.newButton("Expand All"),
    collapseButton: nimkit.newButton("Collapse All"),
    snapshot: GitDiffSnapshot(rootPath: rootPath),
    pool: newSigilThreadPool(workers = 1),
    control: newSharedPtr(GitDiffControl),
  )
  result.initViewFields()
  result.clipsToBounds = true
  discard result.withProtocol(GitDiffLayout)
  let linkDelegate = GitDiffLinkDelegate(panel: result.unsafeWeakRef())
  linkDelegate.initResponder()
  discard linkDelegate.withProtocol(GitDiffLinks)
  result.markdownView.textView().delegate = linkDelegate
  result.markdownView.markdownStyle = markdownStyle
  for view in [
    nimkit.View(result.refreshButton), result.expandButton, result.collapseButton,
    result.markdownView,
  ]:
    result.addSubview(view)
  let panel = result.unsafeWeakRef()
  let refreshAction = nimkit.actionSelector("kosmo.refreshGitDiff")
  result.refreshButton.action = refreshAction
  result.refreshButton.target = nimkit.newActionTarget(refreshAction) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not panel.isNil:
      panel[].refresh()
  let expandAction = nimkit.actionSelector("kosmo.expandGitDiff")
  result.expandButton.action = expandAction
  result.expandButton.target = nimkit.newActionTarget(expandAction) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not panel.isNil:
      panel[].collapsed.clear()
      panel[].renderDiff()
  let collapseAction = nimkit.actionSelector("kosmo.collapseGitDiff")
  result.collapseButton.action = collapseAction
  result.collapseButton.target = nimkit.newActionTarget(collapseAction) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not panel.isNil:
      for file in panel[].snapshot.files:
        panel[].collapsed.incl file.path
      panel[].renderDiff()
  result.pool.start()
  var worker = GitDiffWorker()
  result.worker = worker.moveToThread(result.pool)
  connectThreaded(result.worker, executeDiff, result.worker, executeDiff)
  connectThreaded(result.worker, diffFinished, result, KosmoGitDiffPanel.applyDiff())
  result.refresh()
