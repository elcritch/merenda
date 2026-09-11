## Standard Git hunks in retained native sections with full-context syntax highlighting.

import std/[atomics, isolation, monotimes, os, sets, strutils, tables, times, unicode]
import sigils/[core, threadProxies, threads]
import threading/smartptrs
import ../nimkit as nimkit
import ../nimkit/foundation/backgroundworkers
import ../nimkit/foundation/gitprocesses
import ../nimkit/foundation/selectors as nimkitSelectors
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ../nimkit/foundation/mainthreadwork

const
  KosmoGitDiffTabIdentifier* = "kosmo.gitDiff"
  GitDiffRefreshDebounceInterval = initDuration(milliseconds = 300)
  GitDiffReservedSummaryHeight = 240.0'f32

type
  GitDiffHighlightKey = tuple[source, language: string]

  GitDiffSource* = enum
    gdsRepository
    gdsStandardInput

  GitFileDiff* = object
    path*: string
    patch*: string ## Standard three-line-context patch displayed by the viewer.
    syntaxPatch*: string ## Full-context patch used only for language highlighting.
    additions*, deletions*: int
    binary*: bool

  GitDiffSnapshot* = object
    source*: GitDiffSource
    rootPath*: string
    scopePath*: string ## Absolute file or folder path; empty for the whole repository.
    branch*: string
    hasHead*: bool
    files*: seq[GitFileDiff]
    errorMessage*: string

  GitDiffWorker = ref object of AgentActor

  GitDiffHighlightWorker = ref object of AgentActor
    key: GitDiffHighlightKey
    spans: seq[nimkit.SyntaxTokenSpan]
    cached: bool

  GitDiffHighlightResult = object
    path: string
    source: string
    runs: seq[nimkit.TextAttributeRun]
    errorMessage: string
    generation: uint64
    built: bool
    threadId: int

  GitDiffControl = object
    cancelled: Atomic[bool]

  GitDiffDisclosureButton = ref object of nimkit.Button
    panel: WeakRef[KosmoGitDiffPanel]
    fileIndex: int
    filePath: string

  GitDiffTextView = ref object of nimkit.TextView

  GitDiffDocumentView = ref object of nimkit.View
    panel: WeakRef[KosmoGitDiffPanel]

  GitDiffSection = object
    worker: AgentProxy[GitDiffHighlightWorker]
    textView: GitDiffTextView
    patch: string
    syntaxPatch: string
    generation: uint64
    pending: bool
    ready: bool
    layoutStarted: bool

  GitDiffKeyEquivalentHandler* = proc(event: nimkit.KeyEvent): bool {.closure.}

  KosmoGitDiffPanel* = ref object of nimkit.View
    markdownView*: nimkit.MarkdownView
    scrollView*: nimkit.ScrollView
    documentView*: nimkit.View
    refreshButton*: nimkit.Button
    expandButton*: nimkit.Button
    collapseButton*: nimkit.Button
    autoRefreshLabel: nimkit.Label
    autoRefreshSwitch*: nimkit.SwitchButton
    snapshot*: GitDiffSnapshot
    collapsed: HashSet[string]
    pool: SigilThreadPoolPtr
    worker: AgentProxy[GitDiffWorker]
    sections: Table[string, GitDiffSection]
    hasSnapshot: bool
    readingGit: bool
    refreshPending: bool
    refreshDeadline: MonoTime
    refreshDebounce: Duration
    repositoryBacked: bool
    repositoryRootPath: string
    repositoryScopePath: string
    relayoutPending: bool
    generation: uint64
    readGeneration: uint64
    loading: bool
    closed: bool
    control: SharedPtr[GitDiffControl]
    disclosureButtons: Table[string, GitDiffDisclosureButton]
    keyEquivalentHandler: GitDiffKeyEquivalentHandler
    xHighlightBuildCount: int
    xHighlightThreadId: int
    xRepositoryReadCount: int

proc newGitDiffControl(): SharedPtr[GitDiffControl] =
  result = newSharedPtr(GitDiffControl)
  result[].cancelled.store(false, moRelaxed)

proc executeGit(
    root: string, args: openArray[string], control: SharedPtr[GitDiffControl]
): tuple[output: string, code: int] =
  var arguments = @["--literal-pathspecs"]
  arguments.add args
  let command = runGitCommand(
    root,
    arguments,
    cancelled = proc(): bool =
      control[].cancelled.load(moAcquire),
  )
  (command.output, command.exitCode)

proc sameGitPath(left, right: string): bool =
  when defined(windows):
    cmpIgnoreCase(left, right) == 0
  else:
    left == right

proc gitScopeRelativePath(
    repositoryRoot, scopePath: string, control: SharedPtr[GitDiffControl]
): tuple[path: string, valid: bool] =
  if scopePath.len == 0:
    return (path: "", valid: true)
  var scope = absolutePath(scopePath)
  var leaf = ""
  if not dirExists(scope):
    leaf = lastPathPart(scope)
    scope = parentDir(scope)
  let scopeRepository = executeGit(scope, ["rev-parse", "--show-toplevel"], control)
  if scopeRepository.code != 0:
    return
  let canonicalScopeRepository = normalizedPath(scopeRepository.output.strip())
  if not sameGitPath(canonicalScopeRepository, repositoryRoot):
    return
  let prefix = executeGit(scope, ["rev-parse", "--show-prefix"], control)
  if prefix.code != 0:
    return
  result.valid = true
  result.path = prefix.output.strip().replace('\\', '/').strip(chars = {'/'})
  if leaf.len > 0:
    if result.path.len > 0:
      result.path.add '/'
    result.path.add leaf.replace('\\', '/')

proc readGitDiff(
    rootPath: string, control: SharedPtr[GitDiffControl], scopePath = ""
): GitDiffSnapshot =
  ## Read staged and unstaged changes against HEAD, plus untracked files.
  ## Unborn repositories treat their files as additions. Git runs without shell,
  ## external diff drivers, text conversion, or modifications to the index.
  result.rootPath = rootPath
  result.scopePath = scopePath
  proc runGit(root: string, args: openArray[string]): tuple[output: string, code: int] =
    executeGit(root, args, control)

  try:
    let repository = runGit(rootPath, ["rev-parse", "--show-toplevel"])
    if repository.code != 0:
      result.errorMessage =
        "This folder is not a Git working tree.\n" & repository.output.strip()
      return
    result.rootPath = normalizedPath(repository.output.strip())
    if dirExists(result.rootPath):
      try:
        result.rootPath = normalizedPath(expandFilename(result.rootPath))
      except CatchableError:
        discard
    let hasHead = runGit(result.rootPath, ["rev-parse", "--verify", "HEAD"]).code == 0
    result.hasHead = hasHead
    let branch = runGit(result.rootPath, ["symbolic-ref", "--quiet", "--short", "HEAD"])
    if branch.code == 0:
      result.branch = branch.output.strip()
    elif hasHead:
      let commit = runGit(result.rootPath, ["rev-parse", "--short", "HEAD"])
      result.branch = "Detached HEAD · " & commit.output.strip()
    let scopeResult = gitScopeRelativePath(result.rootPath, scopePath, control)
    if not scopeResult.valid:
      return
    let scopeRelativePath = scopeResult.path
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
        runGit(result.rootPath, ["ls-files", "--cached", "-z", "--"])
    let untracked = runGit(
      result.rootPath, ["ls-files", "--others", "--exclude-standard", "-z", "--"]
    )
    if names.code != 0 or untracked.code != 0:
      result.errorMessage =
        "Could not list changed files.\n" & names.output & untracked.output
      return
    var untrackedPaths = initHashSet[string]()
    for path in untracked.output.split('\0'):
      untrackedPaths.incl path.replace('\\', '/')
    var seen = initHashSet[string]()
    for group in [names.output, untracked.output]:
      for rawPath in group.split('\0'):
        let path = rawPath.replace('\\', '/')
        let inScope =
          scopeRelativePath.len == 0 or path == scopeRelativePath or
          path.startsWith(scopeRelativePath & "/")
        if path.len > 0 and path notin seen and inScope:
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
              var file = GitFileDiff(path: path, patch: patch.output)
              file.syntaxPatch = patch.output
              if not isAddition:
                args[5] = "--unified=3"
                let visible = runGit(result.rootPath, args)
                if visible.code != 0:
                  raise newException(IOError, "Could not read diff hunks for " & path)
                file.patch = visible.output
              var inHunk = false
              for line in patch.output.splitLines():
                if line.startsWith("@@ "):
                  inHunk = true
                elif inHunk and line.startsWith("+"):
                  inc file.additions
                elif inHunk and line.startsWith("-"):
                  inc file.deletions
                elif line.startsWith("Binary files "):
                  file.binary = true
              result.files.add file
          else:
            result.errorMessage =
              "Could not read diff for " & path & ":\n" & patch.output
            return
  except CatchableError:
    result.errorMessage = getCurrentExceptionMsg()

proc readGitDiff*(rootPath: string, scopePath = ""): GitDiffSnapshot =
  ## Read standard diff hunks plus full-file patches for syntax classification.
  readGitDiff(rootPath, newGitDiffControl(), scopePath)

func normalizedPipedDiffPath(rawPath: string): string =
  var path = rawPath.strip()
  let tab = path.find('\t')
  if tab >= 0:
    path.setLen(tab)
  if path.len >= 2 and path[0] == '"' and path[^1] == '"':
    path = path[1 .. ^2]
  if path.startsWith("a/") or path.startsWith("b/"):
    path = path[2 .. ^1]
  if path != "/dev/null":
    result = path

func pathFromGitDiffHeader(line: string): string =
  var marker = line.rfind(" \"b/")
  if marker >= 0:
    return normalizedPipedDiffPath(line[marker + 1 .. ^1])
  marker = line.rfind(" b/")
  if marker >= 0:
    result = normalizedPipedDiffPath(line[marker + 1 .. ^1])

func withoutLineEnd(value: string): string =
  result = value
  result.stripLineEnd()

proc summarizePipedFile(file: var GitFileDiff) =
  file.syntaxPatch = file.patch
  var inHunk: bool
  for line in file.patch.splitLines():
    if line.startsWith("@@ "):
      inHunk = true
    elif inHunk and line.startsWith("+"):
      inc file.additions
    elif inHunk and line.startsWith("-"):
      inc file.deletions
    elif line.startsWith("Binary files ") or line.startsWith("GIT binary patch"):
      file.binary = true

proc finishPipedFile(
    snapshot: var GitDiffSnapshot,
    current: var GitFileDiff,
    oldPath: var string,
    active: var bool,
) =
  if not active:
    return
  if current.path.len == 0:
    current.path = oldPath
  if current.path.len == 0:
    current.path = "Patch " & $(snapshot.files.len + 1)
  current.summarizePipedFile()
  snapshot.files.add current
  current = GitFileDiff()
  oldPath.setLen(0)
  active = false

proc parseGitDiff*(
    content: string, workingDirectory = getCurrentDir()
): GitDiffSnapshot =
  ## Parse ordinary `git diff` output into the retained Git Diff view model.
  result.source = gdsStandardInput
  result.rootPath = normalizedPath(absolutePath(workingDirectory))
  var
    current: GitFileDiff
    oldPath: string
    active: bool

  for line in content.splitLines(keepEol = true):
    if line.startsWith("diff --git "):
      result.finishPipedFile(current, oldPath, active)
      active = true
      current.path = pathFromGitDiffHeader(line.withoutLineEnd())
    elif not active and line.startsWith("--- "):
      active = true
    if not active:
      continue
    current.patch.add line
    if line.startsWith("--- "):
      oldPath = normalizedPipedDiffPath(line[4 .. ^1].withoutLineEnd())
    elif line.startsWith("+++ "):
      let newPath = normalizedPipedDiffPath(line[4 .. ^1].withoutLineEnd())
      if newPath.len > 0:
        current.path = newPath
  result.finishPipedFile(current, oldPath, active)
  if content.strip().len > 0 and result.files.len == 0:
    result.errorMessage = "Standard input is not a unified Git diff."

proc markdownLabel(value: string): string =
  for ch in value:
    case ch
    of '\\', '[', ']', '*', '_', '`', '<', '>', '|':
      result.add '\\'
      result.add ch
    of '\n', '\r':
      result.add ' '
    else:
      result.add ch

proc fencedPatch(patch: string, language = ""): string =
  var fence = "```"
  while fence in patch:
    fence.add '`'
  fence & "diff" & (if language.len > 0: ":" & language else: "") & "\n" & patch & "\n" &
    fence & "\n\n"

proc diffLanguage(path: string): string =
  if path.lastPathPart().toLowerAscii() == "dockerfile":
    "dockerfile"
  else:
    path.splitFile().ext.strip(chars = {'.'}).toLowerAscii()

proc diffHighlight(source, language: string): seq[nimkit.SyntaxTokenSpan] =
  type DiffRow = object
    start, length, oldStart, newStart: int
    kind: char

  var
    rows: seq[DiffRow]
    oldSource, newSource: string
    oldOffset, newOffset, offset: int
    inHunk: bool
  for line in source.splitLines(keepEol = true):
    let length = line.runeLen
    if line.startsWith("@@ "):
      inHunk = true
    let kind =
      if inHunk and line.len > 0 and line[0] in {' ', '+', '-'}:
        line[0]
      else:
        '@'
    rows.add DiffRow(
      start: offset,
      length: length,
      oldStart: oldOffset,
      newStart: newOffset,
      kind: kind,
    )
    if kind in {' ', '+', '-'}:
      if kind != '+':
        oldSource.add line[1 .. ^1]
        oldOffset += length - 1
      if kind != '-':
        newSource.add line[1 .. ^1]
        newOffset += length - 1
    offset += length
  let sourceLanguage =
    if language.startsWith("diff:"):
      language[5 .. ^1]
    else:
      ""
  var
    oldClasses = newSeq[nimkit.SyntaxTokenClass](oldOffset)
    newClasses = newSeq[nimkit.SyntaxTokenClass](newOffset)
  for classes in [addr oldClasses, addr newClasses]:
    for token in classes[].mitems:
      token = nimkit.stcOther
  for span in nimkit.matterSyntaxHighlighter(oldSource, sourceLanguage):
    for index in int(span.range.location) ..< span.range.maxIndex:
      oldClasses[index] = span.tokenClass
  for span in nimkit.matterSyntaxHighlighter(newSource, sourceLanguage):
    for index in int(span.range.location) ..< span.range.maxIndex:
      newClasses[index] = span.tokenClass
  for row in rows:
    let change =
      case row.kind
      of '+': nimkit.sckAdded
      of '-': nimkit.sckDeleted
      else: nimkit.sckUnchanged
    if row.kind == '@':
      result.add nimkit.SyntaxTokenSpan(
        range: nimkit.initTextRange(row.start, row.length),
        tokenClass: nimkit.stcComment,
      )
    elif row.length > 0:
      result.add nimkit.SyntaxTokenSpan(
        range: nimkit.initTextRange(row.start, 1),
        tokenClass: nimkit.stcOther,
        changeKind: change,
        changeMarker: true,
      )
      var index = 1
      while index < row.length:
        let token =
          if row.kind == '-':
            oldClasses[row.oldStart + index - 1]
          else:
            newClasses[row.newStart + index - 1]
        let start = index
        inc index
        while index < row.length and
            (
              if row.kind == '-':
                oldClasses[row.oldStart + index - 1]
              else:
                newClasses[row.newStart + index - 1]
            ) == token
        :
          inc index
        result.add nimkit.SyntaxTokenSpan(
          range: nimkit.initTextRange(row.start + start, index - start),
          tokenClass: token,
          changeKind: change,
        )

iterator patchRows(
    source: string
): tuple[key: tuple[kind: char, oldLine, newLine: int], start, length: int] =
  var oldLine, newLine, offset: int
  var inHunk = false
  for line in source.splitLines(keepEol = true):
    if line.startsWith("@@ "):
      let parts = strutils.splitWhitespace(line)
      oldLine = parseInt(parts[1][1 .. ^1].split(',')[0])
      newLine = parseInt(parts[2][1 .. ^1].split(',')[0])
      inHunk = true
    let kind =
      if inHunk and line.len > 0 and line[0] in {' ', '+', '-'}:
        line[0]
      else:
        '@'
    let length = line.runeLen
    yield ((kind, oldLine, newLine), offset, length)
    if kind in {' ', '-'}:
      inc oldLine
    if kind in {' ', '+'}:
      inc newLine
    offset += length

proc visibleSpans(
    fullSource, visibleSource: string, spans: seq[nimkit.SyntaxTokenSpan]
): seq[nimkit.SyntaxTokenSpan] =
  var positions = initTable[tuple[kind: char, oldLine, newLine: int], int]()
  for row in fullSource.patchRows():
    if row.key.kind != '@':
      positions[row.key] = row.start
  for row in visibleSource.patchRows():
    if row.key.kind == '@' or not positions.hasKey(row.key):
      result.add nimkit.SyntaxTokenSpan(
        range: nimkit.initTextRange(row.start, row.length),
        tokenClass: nimkit.stcComment,
      )
    else:
      let start = positions[row.key]
      let stop = start + row.length
      var low = 0
      var high = spans.len
      while low < high:
        let middle = (low + high) div 2
        if spans[middle].range.maxIndex <= start:
          low = middle + 1
        else:
          high = middle
      while low < spans.len and int(spans[low].range.location) < stop:
        var span = spans[low]
        let a = max(start, int(span.range.location))
        let b = min(stop, span.range.maxIndex)
        span.range = nimkit.initTextRange(row.start + a - start, b - a)
        result.add span
        inc low

proc clearDisclosureButtons(panel: KosmoGitDiffPanel) =
  for button in panel.disclosureButtons.values:
    button.removeFromSuperview()
  panel.disclosureButtons.clear()

proc syncDisclosureButtons(panel: KosmoGitDiffPanel)
proc scheduleSectionLayout(panel: KosmoGitDiffPanel)
proc handleSharedKeys(panel: KosmoGitDiffPanel, event: nimkit.KeyEvent): bool

proc renderDiff(panel: KosmoGitDiffPanel) =
  var document = "# Git Diff\n\n"
  var additions, deletions, binaries: int
  for file in panel.snapshot.files:
    additions += file.additions
    deletions += file.deletions
    if file.binary:
      inc binaries
  if panel.snapshot.source == gdsStandardInput:
    document.add "| Source | Standard input |\n| --- | --- |\n"
  else:
    document.add "| Repository | " &
      panel.snapshot.rootPath.lastPathPart().markdownLabel() & " |\n| --- | --- |\n"
    if panel.snapshot.branch.len > 0:
      document.add "| Branch | " & panel.snapshot.branch.markdownLabel() & " |\n"
  if panel.snapshot.scopePath.len > 0:
    document.add "| Path | " & panel.snapshot.scopePath.markdownLabel() & " |\n"
  document.add "| Location | " & panel.snapshot.rootPath.markdownLabel() & " |\n"
  if (panel.hasSnapshot or not panel.readingGit) and panel.snapshot.errorMessage.len == 0:
    document.add "| Changes | " & $panel.snapshot.files.len & " files · +" & $additions &
      " / −" & $deletions
    if binaries > 0:
      document.add " · " & $binaries & " binary"
    if panel.snapshot.source == gdsStandardInput:
      document.add " |\n| Compare | Piped unified diff |\n"
    else:
      document.add " |\n| Compare | Working tree ↔ " &
        (if panel.snapshot.hasHead: "HEAD" else: "empty tree") &
        " · includes untracked files |\n"
  document.add "\n"
  if panel.readingGit and not panel.hasSnapshot:
    document.add "Loading changes…\n"
  elif panel.snapshot.errorMessage.len > 0:
    document.add "Could not load Git diff.\n\n" &
      panel.snapshot.errorMessage.fencedPatch()
  elif panel.snapshot.files.len == 0:
    if panel.snapshot.source == gdsStandardInput:
      document.add "The piped diff contains no changes.\n"
    elif panel.snapshot.scopePath.len > 0:
      document.add "No changes in this path.\n"
    else:
      document.add "No changes. Your working tree matches HEAD.\n"
  panel.markdownView.markdown = document
  panel.scheduleSectionLayout()

proc toggleFile*(panel: KosmoGitDiffPanel, index: int) =
  ## Toggle a file section without rereading Git.
  if index in 0 ..< panel.snapshot.files.len:
    let path = panel.snapshot.files[index].path
    if path in panel.collapsed:
      panel.collapsed.excl path
    else:
      panel.collapsed.incl path
      let owner = panel.window()
      if owner of nimkit.Window and
          nimkit.Window(owner).firstResponder == panel.sections[path].textView:
        discard nimkit.Window(owner).makeFirstResponder(panel.disclosureButtons[path])
    panel.scheduleSectionLayout()

proc isFileCollapsed*(panel: KosmoGitDiffPanel, index: int): bool =
  index in 0 ..< panel.snapshot.files.len and
    panel.snapshot.files[index].path in panel.collapsed

proc activateDisclosure(button: GitDiffDisclosureButton): bool =
  if button.isNil or button.panel.isNil:
    return
  for fileIndex, file in button.panel[].snapshot.files:
    if file.path == button.filePath:
      button.panel[].toggleFile(fileIndex)
      return true

protocol GitDiffDisclosureDrawing of nimkit.ViewDrawingProtocol:
  method draw(button: GitDiffDisclosureButton, context: nimkit.DrawContext) =
    let style = context.appearance.resolveButtonStyle(
      nimkit.controlStyle(
        nimkit.srButton,
        button.widgetStateSet(),
        id = button.styleId(),
        classes = button.styleClasses(),
      )
    )
    let frame = context.renderRectFor(button.bounds())
    if button.panel.isNil:
      return
    let palette = button.panel[].markdownView.markdownStyle()
    discard context.addRenderRectangle(frame, palette.backgroundColor)
    let disclosure = nimkit.rect(0, (button.bounds().size.height - 16) / 2, 16, 16)
    context.drawDisclosureAffordance(
      disclosure,
      not button.panel[].isFileCollapsed(button.fileIndex),
      button.highlighted(),
    )
    let textRect = nimkit.rect(
      24, 0, max(button.bounds().size.width - 24, 0), button.bounds().size.height
    )
    let textStyle = nimkit.TextStyle(
      color: palette.headingColor,
      fontName: palette.emphasisFontName,
      fontSize: palette.bodyFontSize,
    )
    context.addText(
      textRect, button.title.clippedText(textRect.size.width, textStyle), textStyle
    )
    if button.isFocusVisible():
      context.addFocusRing(frame, style.box)

protocol GitDiffDisclosureFocus of nimkit.ResponderProtocol:
  method didBecomeFirstResponder(button: GitDiffDisclosureButton) =
    if not button.panel.isNil:
      let scrollView = button.panel[].scrollView
      if not scrollView.isNil:
        discard
          scrollView.scrollRectToVisible(button.frame().inset(nimkit.insets(-8.0'f32)))

protocol GitDiffDisclosureAccessibility of nimkit.AccessibilityProtocol:
  method accessibilityRole(button: GitDiffDisclosureButton): nimkit.AccessibilityRole =
    nimkit.arDisclosureButton

  method accessibilityLabel(button: GitDiffDisclosureButton): string =
    if button.filePath.len > 0: button.filePath else: "Git diff file"

  method accessibilityValue(button: GitDiffDisclosureButton): string =
    if not button.panel.isNil and button.panel[].isFileCollapsed(button.fileIndex):
      "collapsed"
    else:
      "expanded"

  method accessibilityTraits(
      button: GitDiffDisclosureButton
  ): nimkit.AccessibilityTraits =
    result = {nimkit.atButton}
    if button.focused():
      result.incl nimkit.atFocused

  method isAccessibilityElement(button: GitDiffDisclosureButton): bool =
    not button.isNil

  method accessibilityActionNames(button: GitDiffDisclosureButton): seq[string] =
    result = @[nimkit.AccessibilityActionPress]
    if not button.panel.isNil and button.panel[].isFileCollapsed(button.fileIndex):
      result.add nimkit.AccessibilityActionExpand
    else:
      result.add nimkit.AccessibilityActionCollapse

  method accessibilityPerformAction(
      button: GitDiffDisclosureButton, action: string
  ): bool =
    if action == nimkit.AccessibilityActionPress:
      return button.activateDisclosure()
    if button.panel.isNil:
      return
    let collapsed = button.panel[].isFileCollapsed(button.fileIndex)
    if action == nimkit.AccessibilityActionExpand and collapsed or
        action == nimkit.AccessibilityActionCollapse and not collapsed:
      return button.activateDisclosure()

proc newDisclosureButton(
    panel: KosmoGitDiffPanel, fileIndex: int, filePath: string, frame: nimkit.Rect
): GitDiffDisclosureButton =
  result = GitDiffDisclosureButton(
    panel: panel.unsafeWeakRef(), fileIndex: fileIndex, filePath: filePath
  )
  result.initButtonFields("", frame)
  discard result.withProtocol(GitDiffDisclosureDrawing)
  discard result.withProtocol(GitDiffDisclosureFocus)
  discard result.withProtocol(GitDiffDisclosureAccessibility)
  let weakButton = result.unsafeWeakRef()
  let toggleAction = nimkit.actionSelector("kosmo.toggleGitDiffFile")
  result.action = toggleAction
  result.target = nimkit.newActionTarget(toggleAction) do(sender: nimkit.DynamicAgent):
    discard sender
    if not weakButton.isNil:
      discard weakButton[].activateDisclosure()
  let keyEquivalentMethod: nimkit.DynamicMethod = proc(
      self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
  ) =
    let
      button = GitDiffDisclosureButton(self)
      event = invocation.argsAs(nimkit.KeyEvent)
    if event.modifiers == {} and event.key in {nimkit.keyEnter, nimkit.keySpace}:
      invocation.setResult(button.activateDisclosure())
    elif event.key == nimkit.keyTab and event.modifiers in [{}, {nimkit.kmShift}]:
      let owner = button.window()
      if owner of nimkit.Window and not button.panel.isNil:
        let window = nimkit.Window(owner)
        let panel = button.panel[]
        let next = button.fileIndex + (if nimkit.kmShift in event.modifiers: -1 else: 1)
        let target: nimkit.Responder =
          if next < 0:
            panel.markdownView.textView()
          elif next >= panel.snapshot.files.len:
            panel.refreshButton
          else:
            panel.disclosureButtons[panel.snapshot.files[next].path]
        invocation.setResult(window.makeFirstResponder(target))
      else:
        invocation.setResult(false)
    else:
      invocation.setResult(
        not button.panel.isNil and button.panel[].handleSharedKeys(event)
      )
  discard
    result.replaceMethod(nimkitSelectors.performKeyEquivalent(), keyEquivalentMethod)
  result.accessibilityIdentifier = "kosmo.gitDiff.file." & $fileIndex
  result.toolTip =
    (if panel.isFileCollapsed(fileIndex): "Expand " else: "Collapse ") &
    panel.snapshot.files[fileIndex].path

proc syncDisclosureButtons(panel: KosmoGitDiffPanel) =
  if panel.closed or panel.scrollView.isNil:
    return
  let viewport = panel.scrollView.viewportSize()
  let width = max(viewport.width - 48, 1)
  let summary = panel.markdownView.textView().layoutManager().layoutSnapshot()
  let summaryHeight = max(
    summary.contentSize.height + panel.markdownView.textInsets().vertical,
    GitDiffReservedSummaryHeight,
  )
  panel.markdownView.setFrameFromLayout(
    nimkit.rect(0, 0, viewport.width, summaryHeight)
  )
  var y = summaryHeight + 16
  var documentWidth = viewport.width
  for index, file in panel.snapshot.files:
    if panel.sections.hasKey(file.path):
      let section = addr panel.sections[file.path]
      let button = panel.disclosureButtons[file.path]
      button.fileIndex = index
      button.title =
        file.path & (
          if file.binary: "   binary"
          else: "   +" & $file.additions & " / −" & $file.deletions
        ) & (if section[].pending: "   preparing…" else: "")
      button.setFrameFromLayout(nimkit.rect(24, y, width, 30))
      button.hidden = false
      button.needsDisplay = true
      let collapsed = file.path in panel.collapsed
      button.toolTip = (if collapsed: "Expand " else: "Collapse ") & file.path
      y += 38
      section[].textView.setHiddenFromLayout(collapsed)
      if not collapsed:
        if section[].ready and not section[].layoutStarted:
          section[].textView.setFrameFromLayout(
            nimkit.rect(34, y, max(width - 20, 1), 1)
          )
          section[].textView.layoutManager().requestBackgroundLayout(
            allowUncachedLayout = true
          )
          section[].layoutStarted = true
        let snapshot = section[].textView.layoutManager().layoutSnapshot()
        let size = nimkit.initSize(
          max(snapshot.contentSize.width, snapshot.usedRect.maxX),
          max(snapshot.contentSize.height, snapshot.usedRect.maxY),
        )
        let codeWidth = max(max(width - 20, size.width), 1)
        section[].textView.setFrameFromLayout(
          nimkit.rect(34, y, codeWidth, max(size.height, 24))
        )
        documentWidth = max(documentWidth, codeWidth + 68)
        y += max(size.height, 24) + 24
      else:
        y += 8
  panel.documentView.setFrameFromLayout(
    nimkit.rect(0, 0, documentWidth, max(y, viewport.height))
  )
  panel.documentView.needsDisplay = true
  panel.scrollView.tile()

proc scheduleSectionLayout(panel: KosmoGitDiffPanel) =
  if panel.closed or panel.relayoutPending:
    return
  panel.relayoutPending = true
  let retainedPanel = panel
  scheduleMainThreadWork(
    proc(): bool =
      if not retainedPanel.closed:
        retainedPanel.relayoutPending = false
        retainedPanel.syncDisclosureButtons()
  )

protocol GitDiffTextDrawing of nimkit.ViewDrawingProtocol:
  method drawUnderlay(view: GitDiffTextView, context: nimkit.DrawContext) =
    view.drawTextViewUnderlayInViewport(context)

  method draw(view: GitDiffTextView, context: nimkit.DrawContext) =
    view.drawTextViewTextInViewport(context)

  method drawOverlay(view: GitDiffTextView, context: nimkit.DrawContext) =
    view.drawTextViewOverlay(context)

protocol GitDiffDocumentDrawing of nimkit.ViewDrawingProtocol:
  method draw(view: GitDiffDocumentView, context: nimkit.DrawContext) =
    if view.panel.isNil:
      return
    let panel = view.panel[]
    let visible = context.visibleRect()
    discard context.addRenderRectangle(
      context.renderRectFor(view.bounds()),
      panel.markdownView.markdownStyle().backgroundColor,
    )
    let style = panel.markdownView.markdownStyle().codeBlockStyle
    for path, section in panel.sections:
      if path notin panel.collapsed:
        let frame = section.textView.frame().inset(nimkit.insets(-8.0'f32, -10.0'f32))
        if not frame.intersection(visible).isEmpty:
          discard context.addRenderRectangle(
            context.renderRectFor(frame),
            style.backgroundColor,
            style.outlineColor,
            style.outlineWidth,
            style.cornerRadius,
          )

proc layoutDisclosureButtons(
    panel: KosmoGitDiffPanel, snapshot: nimkit.TextLayoutSnapshot
) {.slot.} =
  discard snapshot
  panel.scheduleSectionLayout()

proc markdownParsingFinished(panel: KosmoGitDiffPanel, workerThreadId: int) {.slot.} =
  discard workerThreadId
  panel.scheduleSectionLayout()

proc disclosureButtonForFile*(panel: KosmoGitDiffPanel, fileIndex: int): nimkit.Button =
  ## Return the keyboard and accessibility disclosure control for a rendered file.
  panel.syncDisclosureButtons()
  if fileIndex in 0 ..< panel.snapshot.files.len:
    return panel.disclosureButtons.getOrDefault(panel.snapshot.files[fileIndex].path)

proc focusFirstDisclosure(panel: KosmoGitDiffPanel): bool =
  panel.syncDisclosureButtons()
  for file in panel.snapshot.files:
    let button = panel.disclosureButtons.getOrDefault(file.path)
    if not button.isNil and not button.hidden:
      let owner = button.window()
      if owner of nimkit.Window:
        return nimkit.Window(owner).makeFirstResponder(button)
      return

proc `keyEquivalentHandler=`*(
    panel: KosmoGitDiffPanel, handler: GitDiffKeyEquivalentHandler
) =
  ## Route application-specific key equivalents before Markdown navigation.
  panel.keyEquivalentHandler = handler

proc handleSharedKeys(panel: KosmoGitDiffPanel, event: nimkit.KeyEvent): bool =
  if not panel.keyEquivalentHandler.isNil and panel.keyEquivalentHandler(event):
    return true
  if event.key == nimkit.keyTab and event.modifiers == {}:
    return panel.focusFirstDisclosure()
  if event.modifiers == {}:
    var delta: float32
    case event.key
    of nimkit.keyArrowDown:
      delta = 32
    of nimkit.keyArrowUp:
      delta = -32
    of nimkit.keyPageDown, nimkit.keySpace:
      delta = panel.scrollView.viewportSize().height * 0.85
    of nimkit.keyPageUp:
      delta = -panel.scrollView.viewportSize().height * 0.85
    else:
      return false
    let offset = panel.scrollView.contentOffset()
    panel.scrollView.contentOffset = nimkit.initPoint(offset.x, offset.y + delta)
    return true

proc executeDiff(
  worker: AgentProxy[GitDiffWorker],
  root: string,
  scopePath: string,
  generation: uint64,
  control: SharedPtr[GitDiffControl],
) {.signal.}

proc diffFinished(
  worker: GitDiffWorker, snapshot: GitDiffSnapshot, generation: uint64
) {.signal.}

proc executeDiff(
    worker: GitDiffWorker,
    root: string,
    scopePath: string,
    generation: uint64,
    control: SharedPtr[GitDiffControl],
) {.slot.} =
  emit worker.diffFinished(readGitDiff(root, control, scopePath), generation)

proc highlightDiff(
  worker: AgentProxy[GitDiffHighlightWorker],
  path: string,
  key: GitDiffHighlightKey,
  visibleSource: string,
  style: nimkit.MarkdownStyle,
  generation: uint64,
  control: SharedPtr[GitDiffControl],
) {.signal.}

proc highlightingFinished(
  worker: GitDiffHighlightWorker, highlighted: SharedPtr[GitDiffHighlightResult]
) {.signal.}

proc highlightDiff(
    worker: GitDiffHighlightWorker,
    path: string,
    key: GitDiffHighlightKey,
    visibleSource: string,
    style: nimkit.MarkdownStyle,
    generation: uint64,
    control: SharedPtr[GitDiffControl],
) {.slot.} =
  if control[].cancelled.load(moAcquire):
    return
  var prepared = GitDiffHighlightResult(
    path: path, source: visibleSource, generation: generation, threadId: getThreadId()
  )
  try:
    if not worker.cached or worker.key != key:
      worker.spans = diffHighlight(key.source, key.language)
      worker.key = key
      worker.cached = true
      prepared.built = true
    var attributes = nimkit.defaultTextAttributes()
    attributes.fontName = style.codeFontName
    attributes.fontSize = style.bodyFontSize
    attributes.foregroundColor = style.codeColor
    attributes.paragraphStyle.lineBreakMode = nimkit.tlbmClipping
    for span in visibleSpans(key.source, visibleSource, worker.spans):
      var token = attributes
      token.foregroundColor = style.syntaxTokenColors[span.tokenClass]
      if span.changeKind != nimkit.sckUnchanged:
        let tint = (
          if span.changeKind == nimkit.sckAdded:
            nimkit.color(0.20, 0.65, 0.35, 1)
          else: nimkit.color(0.85, 0.25, 0.30, 1)
        )
        token.lineBackgroundColor = tint
        token.lineBackgroundColor.a = 0.13
        if span.changeMarker:
          token.foregroundColor = tint
      prepared.runs.add nimkit.TextAttributeRun(range: span.range, attributes: token)
  except CatchableError as error:
    prepared.errorMessage = error.msg
  if not control[].cancelled.load(moAcquire):
    emit worker.highlightingFinished(newSharedPtr(unsafeIsolate(move prepared)))

proc updateLoading(panel: KosmoGitDiffPanel) =
  panel.loading = panel.readingGit
  var preparing = panel.readingGit and not panel.hasSnapshot
  for section in panel.sections.values:
    panel.loading = panel.loading or section.pending
    preparing = preparing or section.pending
  panel.refreshButton.enabled = not preparing and panel.repositoryBacked
  panel.autoRefreshSwitch.enabled = panel.repositoryBacked

proc applyHighlighting(
    panel: KosmoGitDiffPanel, highlighted: SharedPtr[GitDiffHighlightResult]
) {.slot.} =
  if panel.closed or not panel.sections.hasKey(highlighted[].path):
    return
  var section = addr panel.sections[highlighted[].path]
  if section[].generation != highlighted[].generation or not section[].pending:
    return
  var prepared = move highlighted[]
  section[].pending = false
  section[].ready = true
  section[].layoutStarted = false
  if prepared.built:
    inc panel.xHighlightBuildCount
  panel.xHighlightThreadId = prepared.threadId
  if prepared.errorMessage.len > 0:
    section[].textView.textStorage =
      nimkit.newTextStorage("Could not prepare this diff: " & prepared.errorMessage)
  else:
    section[].textView.textStorage =
      nimkit.newTextStorage(move prepared.source, move prepared.runs)
  panel.updateLoading()
  panel.scheduleSectionLayout()

proc queueSection(panel: KosmoGitDiffPanel, path: string) =
  inc panel.generation
  panel.sections[path].generation = panel.generation
  panel.sections[path].pending = true
  let key = (
    source: panel.sections[path].syntaxPatch.replace("\r\n", "\n"),
    language: "diff:" & path.diffLanguage(),
  )
  emit panel.sections[path].worker.highlightDiff(
    path,
    key,
    panel.sections[path].patch.replace("\r\n", "\n"),
    panel.markdownView.markdownStyle(),
    panel.generation,
    panel.control,
  )

proc applyDiff(panel: KosmoGitDiffPanel, snapshot: GitDiffSnapshot) {.slot.} =
  if panel.closed:
    return
  panel.readingGit = false
  if panel.hasSnapshot and panel.snapshot == snapshot:
    panel.updateLoading()
    return
  panel.hasSnapshot = true
  panel.snapshot = snapshot
  var retained = initHashSet[string]()
  for index, file in snapshot.files:
    retained.incl file.path
    if not panel.sections.hasKey(file.path):
      var highlighter = GitDiffHighlightWorker()
      let worker = highlighter.moveToThread(nimkitWorkerPool())
      connectThreaded(worker, highlightDiff, worker, highlightDiff)
      connectThreaded(
        worker, highlightingFinished, panel, KosmoGitDiffPanel.applyHighlighting()
      )
      let code = GitDiffTextView()
      code.initTextViewFields()
      code.editable = false
      code.selectable = true
      code.propagatesIntrinsicContentSizeChanges = false
      code.textContainer =
        nimkit.initTextContainer(wraps = false, widthTracksTextView = true)
      code.layoutManager().usesBackgroundLayout = true
      code.accessibilityLabel = "Diff for " & file.path
      discard code.withProtocol(GitDiffTextDrawing)
      let weakPanel = panel.unsafeWeakRef()
      let keys: nimkit.DynamicMethod = proc(
          self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
      ) =
        invocation.setResult(
          not weakPanel.isNil and
            weakPanel[].handleSharedKeys(invocation.argsAs(nimkit.KeyEvent))
        )
      discard code.replaceMethod(nimkitSelectors.performKeyEquivalent(), keys)
      code.layoutManager().connect(
        nimkit.layoutDidComplete, panel, layoutDisclosureButtons
      )
      panel.sections[file.path] = GitDiffSection(worker: worker, textView: code)
      let button =
        panel.newDisclosureButton(index, file.path, nimkit.rect(0, 0, 100, 30))
      panel.disclosureButtons[file.path] = button
      panel.documentView.addSubview(button)
      panel.documentView.addSubview(code)
      panel.collapsed.incl file.path
      code.setHiddenFromLayout(true)
    if panel.sections[file.path].patch != file.patch or
        panel.sections[file.path].syntaxPatch != file.syntaxPatch or
        not panel.sections[file.path].ready:
      panel.sections[file.path].patch = file.patch
      panel.sections[file.path].syntaxPatch = file.syntaxPatch
      panel.queueSection(file.path)
  var stale: seq[string]
  for path in panel.sections.keys:
    if path notin retained:
      stale.add path
  for path in stale:
    let owner = panel.window()
    if owner of nimkit.Window and
        nimkit.Window(owner).firstResponder in [
          nimkit.Responder(panel.sections[path].textView),
          nimkit.Responder(panel.disclosureButtons[path]),
        ]:
      discard nimkit.Window(owner).makeFirstResponder(panel.markdownView.textView())
    panel.sections[path].textView.removeFromSuperview()
    panel.disclosureButtons[path].removeFromSuperview()
    panel.sections.del path
    panel.disclosureButtons.del path
    panel.collapsed.excl path
  panel.updateLoading()
  panel.renderDiff()

proc repositoryDiffFinished(
    panel: KosmoGitDiffPanel, snapshot: GitDiffSnapshot, generation: uint64
) {.slot.} =
  if not panel.closed and generation == panel.readGeneration:
    panel.applyDiff(snapshot)

proc displayDiff*(panel: KosmoGitDiffPanel, snapshot: GitDiffSnapshot) =
  ## Replace the current contents with an already prepared, static snapshot.
  if panel.isNil or panel.closed:
    return
  panel.repositoryBacked = false
  panel.repositoryRootPath = ""
  panel.repositoryScopePath = ""
  inc panel.readGeneration
  panel.readingGit = false
  panel.applyDiff(snapshot)

proc refresh*(panel: KosmoGitDiffPanel)

proc pollRepositoryRefresh*(panel: KosmoGitDiffPanel): bool {.discardable.} =
  ## Start a trailing repository refresh once its quiet period has elapsed.
  if panel.isNil or panel.closed or panel.autoRefreshSwitch.isNil:
    return
  if not panel.autoRefreshSwitch.on:
    panel.refreshPending = false
    return
  if not panel.repositoryBacked or not panel.refreshPending or panel.loading:
    return
  if getMonoTime() >= panel.refreshDeadline:
    panel.refreshPending = false
    panel.refresh()
    result = true

proc scheduleRepositoryRefresh*(panel: KosmoGitDiffPanel) =
  ## Coalesce repository notifications until the workspace has been quiet.
  if panel.isNil or panel.closed or panel.autoRefreshSwitch.isNil or
      not panel.autoRefreshSwitch.on or not panel.repositoryBacked:
    return
  panel.refreshPending = true
  panel.refreshDeadline = getMonoTime() + panel.refreshDebounce

proc displayRepositoryDiff*(
    panel: KosmoGitDiffPanel, rootPath: string, scopePath = ""
) =
  ## Refresh a repository or path without clearing the displayed snapshot.
  if panel.isNil or panel.closed:
    return
  let changed =
    not panel.repositoryBacked or panel.repositoryRootPath != rootPath or
    panel.repositoryScopePath != scopePath
  panel.repositoryBacked = true
  panel.repositoryRootPath = rootPath
  panel.repositoryScopePath = scopePath
  if changed and panel.readingGit:
    inc panel.readGeneration
    panel.readingGit = false
    panel.updateLoading()
  panel.refresh()

proc refresh*(panel: KosmoGitDiffPanel) =
  ## Refresh the current repository on a worker thread.
  if not panel.closed and not panel.readingGit and panel.repositoryBacked:
    panel.refreshPending = false
    inc panel.readGeneration
    inc panel.xRepositoryReadCount
    panel.loading = true
    panel.readingGit = true
    if not panel.hasSnapshot:
      panel.refreshButton.enabled = false
      panel.renderDiff()
    emit panel.worker.executeDiff(
      panel.repositoryRootPath, panel.repositoryScopePath, panel.readGeneration,
      panel.control,
    )

proc waitForDiff*(panel: KosmoGitDiffPanel, timeoutMilliseconds = 10000): bool =
  ## Deliver worker results until the diff finishes, for callers without an event loop.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMilliseconds)
  while getMonoTime() < deadline:
    discard panel.pollRepositoryRefresh()
    discard getCurrentSigilThread().pollAll(NonBlocking)
    discard drainMainThreadWork()
    var pending =
      panel.loading or panel.refreshPending or panel.relayoutPending or
      panel.markdownView.isMarkdownParsing() or panel.markdownView.isMarkdownRendering() or
      panel.markdownView.textView().layoutManager().isBackgroundLayoutPending()
    for path, section in panel.sections:
      if path notin panel.collapsed:
        pending =
          pending or section.textView.layoutManager().isBackgroundLayoutPending()
    if not pending:
      return true
    sleep(1)

proc close*(panel: KosmoGitDiffPanel) {.slot.} =
  if not panel.closed:
    panel.closed = true
    inc panel.generation
    panel.loading = false
    panel.refreshPending = false
    for section in panel.sections.values:
      section.textView.removeFromSuperview()
    panel.sections.clear()
    panel.clearDisclosureButtons()
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
      availableWidth =
        max(bounds.size.width - inset * 2.0'f32 - gap * 3.0'f32 - 4.0'f32, 0)
      scale = min(availableWidth / 446.0'f32, 1.0'f32)
      refreshWidth = 90.0'f32 * scale
      actionWidth = 110.0'f32 * scale
      autoRefreshLabelWidth = 82.0'f32 * scale
      autoRefreshWidth = 54.0'f32 * scale
      expandX = inset + refreshWidth + gap
      collapseX = expandX + actionWidth + gap
      autoRefreshLabelX = collapseX + actionWidth + gap
      autoRefreshX = autoRefreshLabelX + autoRefreshLabelWidth + 4.0'f32
    panel.refreshButton.setFrameFromLayout(nimkit.rect(inset, 8, refreshWidth, 28))
    panel.expandButton.setFrameFromLayout(nimkit.rect(expandX, 8, actionWidth, 28))
    panel.collapseButton.setFrameFromLayout(nimkit.rect(collapseX, 8, actionWidth, 28))
    panel.autoRefreshLabel.setFrameFromLayout(
      nimkit.rect(autoRefreshLabelX, 8, autoRefreshLabelWidth, 28)
    )
    panel.autoRefreshSwitch.setFrameFromLayout(
      nimkit.rect(autoRefreshX, 8, autoRefreshWidth, 28)
    )
    panel.scrollView.setFrameFromLayout(
      nimkit.rect(0, 44, bounds.size.width, max(bounds.size.height - 44, 0))
    )
    panel.syncDisclosureButtons()

proc `markdownStyle=`*(panel: KosmoGitDiffPanel, style: nimkit.MarkdownStyle) =
  ## Apply the shared Markdown palette while keeping file controls compact.
  var diffStyle = style
  diffStyle.headingFontSizes[1] = style.bodyFontSize
  panel.markdownView.markdownStyle = diffStyle
  for path in panel.sections.keys:
    panel.queueSection(path)
  panel.updateLoading()

proc highlightBuildCount*(panel: KosmoGitDiffPanel): int =
  ## Number of uncached diff highlighting passes, for performance diagnostics.
  panel.xHighlightBuildCount

proc highlightThreadId*(panel: KosmoGitDiffPanel): int =
  ## Thread that prepared the latest highlighted snapshot; zero before completion.
  panel.xHighlightThreadId

proc repositoryReadCount*(panel: KosmoGitDiffPanel): int =
  ## Number of repository snapshots requested, for refresh diagnostics.
  panel.xRepositoryReadCount

proc textViewForFile*(panel: KosmoGitDiffPanel, index: int): nimkit.TextView =
  ## Retained per-file text; collapsed sections keep their prepared storage.
  if index in 0 ..< panel.snapshot.files.len:
    return panel.sections[panel.snapshot.files[index].path].textView

proc newKosmoGitDiffPanel(
    rootPath: string,
    markdownStyle: nimkit.MarkdownStyle,
    refreshesRepository: bool,
    scopePath = "",
): KosmoGitDiffPanel =
  ## Construct a syntax-highlighted hunk reader with initially collapsed files.
  startLocalThreadDefault()
  result = KosmoGitDiffPanel(
    markdownView: nimkit.newMarkdownView(),
    refreshButton: nimkit.newButton("Refresh"),
    expandButton: nimkit.newButton("Expand All"),
    collapseButton: nimkit.newButton("Collapse All"),
    autoRefreshLabel: nimkit.newLabel("Auto-refresh"),
    autoRefreshSwitch: nimkit.newSwitchButton(),
    snapshot: GitDiffSnapshot(rootPath: rootPath, scopePath: scopePath),
    refreshDebounce: GitDiffRefreshDebounceInterval,
    repositoryBacked: refreshesRepository,
    repositoryRootPath: if refreshesRepository: rootPath else: "",
    repositoryScopePath: if refreshesRepository: scopePath else: "",
    disclosureButtons: initTable[string, GitDiffDisclosureButton](),
    pool: newSigilThreadPool(workers = 1),
    control: newGitDiffControl(),
  )
  result.initViewFields()
  let document = GitDiffDocumentView(panel: result.unsafeWeakRef())
  document.initViewFields()
  discard document.withProtocol(GitDiffDocumentDrawing)
  result.documentView = document
  result.scrollView = nimkit.newScrollView(documentView = document)
  result.scrollView.hasVerticalScroller = true
  result.scrollView.hasHorizontalScroller = true
  document.addSubview(result.markdownView)
  let summaryScroll = result.markdownView.scrollView()
  summaryScroll.hasVerticalScroller = false
  summaryScroll.hasHorizontalScroller = false
  let forwardSummaryScroll: nimkit.DynamicMethod = proc(
      self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
  ) =
    invocation.setResult(true)
  discard summaryScroll.replaceMethod(
    nimkitSelectors.wantsForwardedScrollEvents(), forwardSummaryScroll
  )
  result.clipsToBounds = true
  discard result.withProtocol(GitDiffLayout)
  result.markdownStyle = markdownStyle
  result.markdownView.toolTip = rootPath
  result.autoRefreshSwitch.accessibilityLabel = "Automatically refresh Git diff"
  result.autoRefreshSwitch.toolTip = "Automatically refresh Git diff when files change"
  result.autoRefreshSwitch.accessibilityIdentifier = "kosmo.gitDiff.autoRefresh"
  let weakPanel = result.unsafeWeakRef()
  let keyEquivalentMethod: nimkit.DynamicMethod = proc(
      self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
  ) =
    let
      event = invocation.argsAs(nimkit.KeyEvent)
      markdownView = nimkit.MarkdownView(self)
    if event.key == nimkit.keyTab and event.modifiers == {} and not weakPanel.isNil and
        weakPanel[].focusFirstDisclosure():
      invocation.setResult(true)
    elif event.key == nimkit.keyTab and event.modifiers == {nimkit.kmShift} and
        markdownView.window() of nimkit.Window:
      invocation.setResult(
        nimkit.Window(markdownView.window()).selectKeyViewPrecedingView(markdownView)
      )
    elif not weakPanel.isNil and not weakPanel[].keyEquivalentHandler.isNil and
        weakPanel[].keyEquivalentHandler(event):
      invocation.setResult(true)
    else:
      invocation.setResult(not weakPanel.isNil and weakPanel[].handleSharedKeys(event))
  discard result.markdownView.replaceMethod(
    nimkitSelectors.performKeyEquivalent(), keyEquivalentMethod
  )
  result.markdownView.textView().layoutManager().connect(
    nimkit.layoutDidComplete, result, layoutDisclosureButtons
  )
  result.markdownView.connect(
    nimkit.markdownDidFinishParsing, result, markdownParsingFinished
  )
  for view in [
    nimkit.View(result.refreshButton), result.expandButton, result.collapseButton,
    result.autoRefreshLabel, result.autoRefreshSwitch, result.scrollView,
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
  let autoRefreshAction = nimkit.actionSelector("kosmo.toggleGitDiffAutoRefresh")
  result.autoRefreshSwitch.action = autoRefreshAction
  result.autoRefreshSwitch.target = nimkit.newActionTarget(autoRefreshAction) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not panel.isNil and not panel[].autoRefreshSwitch.on:
      panel[].refreshPending = false
  let expandAction = nimkit.actionSelector("kosmo.expandGitDiff")
  result.expandButton.action = expandAction
  result.expandButton.target = nimkit.newActionTarget(expandAction) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not panel.isNil:
      panel[].collapsed.clear()
      panel[].scheduleSectionLayout()
  let collapseAction = nimkit.actionSelector("kosmo.collapseGitDiff")
  result.collapseButton.action = collapseAction
  result.collapseButton.target = nimkit.newActionTarget(collapseAction) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not panel.isNil:
      for file in panel[].snapshot.files:
        panel[].collapsed.incl file.path
        let owner = panel[].window()
        if owner of nimkit.Window and
            nimkit.Window(owner).firstResponder == panel[].sections[file.path].textView:
          discard nimkit.Window(owner).makeFirstResponder(
              panel[].disclosureButtons[file.path]
            )
      panel[].scheduleSectionLayout()
  result.pool.start()
  var worker = GitDiffWorker()
  result.worker = worker.moveToThread(result.pool)
  connectThreaded(result.worker, executeDiff, result.worker, executeDiff)
  connectThreaded(
    result.worker, diffFinished, result, KosmoGitDiffPanel.repositoryDiffFinished()
  )
  if refreshesRepository:
    result.refresh()
  else:
    result.renderDiff()

proc newKosmoGitDiffPanel*(
    rootPath: string, markdownStyle = nimkit.initMarkdownStyle(), scopePath = ""
): KosmoGitDiffPanel =
  ## Construct a repository-backed Git Diff view.
  newKosmoGitDiffPanel(
    rootPath, markdownStyle, refreshesRepository = true, scopePath = scopePath
  )

proc newKosmoGitDiffPanel*(
    snapshot: GitDiffSnapshot, markdownStyle = nimkit.initMarkdownStyle()
): KosmoGitDiffPanel =
  ## Construct a Git Diff view from a static snapshot such as piped input.
  result =
    newKosmoGitDiffPanel(snapshot.rootPath, markdownStyle, refreshesRepository = false)
  result.displayDiff(snapshot)

var gitDiffWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
