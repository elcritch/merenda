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
  GitDiffDefaultPerFileByteLimit* = 2 * 1024 * 1024
  GitDiffDefaultTotalByteLimit* = 32 * 1024 * 1024
  GitDiffDefaultFileLimit* = 10_000
  GitDiffMetadataOutputByteLimit = 16 * 1024 * 1024
  GitDiffMaterializedSectionLimit* = 32
  GitDiffViewPoolLimit = GitDiffMaterializedSectionLimit

type
  GitDiffHighlightKey = tuple[source, language: string]

  GitDiffSource* = enum
    gdsRepository
    gdsStandardInput

  GitDiffFileStatus* = enum
    gdfsModified
    gdfsAdded
    gdfsDeleted
    gdfsRenamed
    gdfsCopied
    gdfsTypeChanged
    gdfsConflicted
    gdfsUntracked

  GitDiffPatchState* = enum
    gdpsUnloaded
    gdpsLoaded
    gdpsSkipped
    gdpsFailed

  GitDiffPatchLimits* = object
    perFileBytes*: int
    totalBytes*: int

  GitDiffPatchRequest = object
    path: string
    generation: uint64
    explicit: bool

  GitFileDiff* = object
    path*: string
    patch*: string ## Standard three-line-context patch displayed by the viewer.
    syntaxPatch*: string ## Full-context patch used only for language highlighting.
    additions*, deletions*: int
    binary*: bool
    status*: GitDiffFileStatus
    patchState*: GitDiffPatchState
    requiresExplicitLoad*: bool
    patchBytes*: int
    errorMessage*: string
    revision*: string

  GitDiffSnapshot* = object
    source*: GitDiffSource
    rootPath*: string
    scopePath*: string ## Absolute file or folder path; empty for the whole repository.
    branch*: string
    hasHead*: bool
    files*: seq[GitFileDiff]
    fileLimitReached*: bool
    errorMessage*: string
    revision*: string

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

  GitDiffFileLoadResult = object
    file: GitFileDiff
    generation: uint64
    threadId: int

  GitDiffDisclosureButton = ref object of nimkit.Button
    panel: WeakRef[KosmoGitDiffPanel]
    fileIndex: int
    filePath: string

  GitDiffTextView = ref object of nimkit.TextView

  GitDiffDocumentView = ref object of nimkit.View
    panel: WeakRef[KosmoGitDiffPanel]

  GitDiffSection = object
    textView: GitDiffTextView
    disclosureButton: GitDiffDisclosureButton
    status: GitDiffFileStatus
    revision: string
    patch: string
    syntaxPatch: string
    patchState: GitDiffPatchState
    requiresExplicitLoad: bool
    patchError: string
    patchBytes: int
    additions: int
    deletions: int
    binary: bool
    generation: uint64
    loadGeneration: uint64
    patchPending: bool
    pending: bool
    ready: bool
    layoutStarted: bool
    contentHeight: float32

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
    highlightWorker: AgentProxy[GitDiffHighlightWorker]
    sections: Table[string, GitDiffSection]
    snapshotFileIndexes: Table[string, int]
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
    textViewPool: seq[GitDiffTextView]
    disclosureButtonPool: seq[GitDiffDisclosureButton]
    forcedDisclosurePaths: HashSet[string]
    forcedTextPaths: HashSet[string]
    explicitPatchPaths: HashSet[string]
    patchLimits*: GitDiffPatchLimits
    patchBytesUsed: int
    activePatchPath: string
    patchQueue: seq[GitDiffPatchRequest]
    patchGeneration: uint64
    keyEquivalentHandler: GitDiffKeyEquivalentHandler
    xHighlightBuildCount: int
    xHighlightThreadId: int
    xRepositoryReadCount: int

proc newGitDiffControl(): SharedPtr[GitDiffControl] =
  result = newSharedPtr(GitDiffControl)
  result[].cancelled.store(false, moRelaxed)

proc executeGit(
    root: string,
    args: openArray[string],
    control: SharedPtr[GitDiffControl],
    maxOutputBytes: Natural = 128 * 1024 * 1024,
): tuple[output: string, code: int, limitExceeded: bool] =
  var arguments = @["--literal-pathspecs"]
  arguments.add args
  let command = runGitCommand(
    root,
    arguments,
    maxOutputBytes = maxOutputBytes,
    cancelled = proc(): bool =
      control[].cancelled.load(moAcquire),
  )
  (command.output, command.exitCode, command.outputLimitExceeded)

proc initGitDiffPatchLimits*(
    perFileBytes = GitDiffDefaultPerFileByteLimit,
    totalBytes = GitDiffDefaultTotalByteLimit,
): GitDiffPatchLimits =
  ## Return bounded patch storage limits for repository-backed diffs.
  result.perFileBytes = max(perFileBytes, 1)
  result.totalBytes = max(totalBytes, 1)

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

func generatedDiffPath(path: string): bool =
  let normalized = path.replace('\\', '/').toLowerAscii()
  (normalized.startsWith("nifcache/") or normalized.startsWith("nimcache/")) and
    normalized.endsWith(".nim.c")

func inGitDiffScope(path, scopePath, scopePrefix: string): bool =
  scopePath.len == 0 or path == scopePath or path.startsWith(scopePrefix)

func gitDiffFileStatus(code: string): GitDiffFileStatus =
  if code.len == 0:
    return gdfsModified
  case code[0]
  of 'A': gdfsAdded
  of 'D': gdfsDeleted
  of 'R': gdfsRenamed
  of 'C': gdfsCopied
  of 'T': gdfsTypeChanged
  of 'U': gdfsConflicted
  else: gdfsModified

proc nextGitField(value: string, cursor: var int): string =
  if cursor >= value.len:
    return
  let fieldEnd = value.find('\0', cursor)
  if fieldEnd < 0:
    result = value[cursor ..^ 1]
    cursor = value.len
  else:
    result = value[cursor ..< fieldEnd]
    cursor = fieldEnd + 1

proc untrackedFileRevision(rootPath, path: string): string =
  result = "untracked:" & path
  try:
    let info = getFileInfo(rootPath / path)
    result.add ":" & $info.size & ":" & $info.lastWriteTime.toUnix() & ":" &
      $info.lastWriteTime.nanosecond
  except CatchableError:
    discard

proc fileMetadataRevision(rootPath, path: string): string =
  result = "file:" & path
  try:
    let info = getFileInfo(rootPath / path)
    result.add ":" & $info.size & ":" & $info.lastWriteTime.toUnix() & ":" &
      $info.lastWriteTime.nanosecond & ":" & $info.permissions
  except CatchableError:
    result.add ":missing"

proc appendGitDiffFile(
    snapshot: var GitDiffSnapshot,
    seen: var HashSet[string],
    path: string,
    status: GitDiffFileStatus,
    revision: string,
    fileLimit: int,
): bool =
  if snapshot.files.len >= fileLimit:
    snapshot.fileLimitReached = true
    return
  seen.incl path
  snapshot.files.add GitFileDiff(
    path: path,
    status: status,
    patchState: gdpsUnloaded,
    requiresExplicitLoad: generatedDiffPath(path),
    revision: revision,
  )
  true

proc readGitDiff(
    rootPath: string,
    control: SharedPtr[GitDiffControl],
    scopePath = "",
    fileLimit: Positive = GitDiffDefaultFileLimit,
): GitDiffSnapshot =
  ## Read changed filenames and status against HEAD, plus untracked files.
  ## Patch contents are fetched only after a file is explicitly expanded.
  result.rootPath = rootPath
  result.scopePath = scopePath
  proc runGit(
      root: string, args: openArray[string]
  ): tuple[output: string, code: int, limitExceeded: bool] =
    executeGit(root, args, control, maxOutputBytes = GitDiffMetadataOutputByteLimit)

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
    let
      scopeRelativePath = scopeResult.path
      scopePrefix = scopeRelativePath & "/"
      pathspec =
        if scopeRelativePath.len > 0:
          @[scopeRelativePath]
        else:
          @[]
    var namesArguments: seq[string]
    if hasHead:
      namesArguments =
        @[
          "diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--name-status",
          "-z", "HEAD", "--",
        ]
    else:
      namesArguments = @["ls-files", "--cached", "-z", "--"]
    namesArguments.add pathspec
    let names = runGit(result.rootPath, namesArguments)
    var untrackedArguments = @["ls-files", "--others", "--exclude-standard", "-z", "--"]
    untrackedArguments.add pathspec
    let untracked = runGit(result.rootPath, untrackedArguments)
    if names.limitExceeded or untracked.limitExceeded:
      result.errorMessage =
        "The changed-file listing exceeded the safety limit. " &
        "Narrow the Git Diff path and try again."
      return
    if names.code != 0 or untracked.code != 0:
      result.errorMessage =
        "Could not list changed files.\n" & names.output & untracked.output
      return
    var seen = initHashSet[string]()
    if hasHead:
      var cursor: int
      while cursor < names.output.len:
        let statusCode = nextGitField(names.output, cursor)
        let path = nextGitField(names.output, cursor).replace('\\', '/')
        if statusCode.len > 0 and path.len > 0 and path notin seen and
            path.inGitDiffScope(scopeRelativePath, scopePrefix):
          if not appendGitDiffFile(
            result,
            seen,
            path,
            gitDiffFileStatus(statusCode),
            statusCode & "|" & fileMetadataRevision(result.rootPath, path),
            fileLimit.int,
          ):
            break
    else:
      for rawPath in names.output.split('\0'):
        let path = rawPath.replace('\\', '/')
        if path.len > 0 and path notin seen and
            path.inGitDiffScope(scopeRelativePath, scopePrefix):
          if not appendGitDiffFile(
            result,
            seen,
            path,
            gdfsAdded,
            "index:" & path & "|" & fileMetadataRevision(result.rootPath, path),
            fileLimit.int,
          ):
            break
    if not result.fileLimitReached:
      for rawPath in untracked.output.split('\0'):
        let path = rawPath.replace('\\', '/')
        if path.len > 0 and path notin seen and
            path.inGitDiffScope(scopeRelativePath, scopePrefix):
          if not appendGitDiffFile(
            result,
            seen,
            path,
            gdfsUntracked,
            untrackedFileRevision(result.rootPath, path),
            fileLimit.int,
          ):
            break
    if result.fileLimitReached:
      result.revision.add "file-limit\0"
    for file in result.files:
      result.revision.add file.path
      result.revision.add '\0'
      result.revision.add $file.status
      result.revision.add '\0'
      result.revision.add file.revision
      result.revision.add '\0'
  except CatchableError:
    result.errorMessage = getCurrentExceptionMsg()

proc readGitDiff*(
    rootPath: string, scopePath = "", fileLimit: Positive = GitDiffDefaultFileLimit
): GitDiffSnapshot =
  ## Read changed filenames and status without loading patch contents.
  readGitDiff(rootPath, newGitDiffControl(), scopePath, fileLimit)

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

proc summarizePatch(file: var GitFileDiff, source: string) =
  file.patchState = gdpsLoaded
  file.patchBytes = file.patch.len + file.syntaxPatch.len
  var inHunk: bool
  for line in source.splitLines():
    if line.startsWith("@@ "):
      inHunk = true
    elif inHunk and line.startsWith("+"):
      inc file.additions
    elif inHunk and line.startsWith("-"):
      inc file.deletions
    elif line.startsWith("Binary files ") or line.startsWith("GIT binary patch"):
      file.binary = true

proc summarizePipedFile(file: var GitFileDiff) =
  file.syntaxPatch = file.patch
  file.status = gdfsModified
  file.summarizePatch(file.patch)

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

proc gitDiffArguments(file: GitFileDiff, hasHead: bool, unified: int): seq[string] =
  result =
    @[
      "diff",
      "--no-ext-diff",
      "--no-textconv",
      "--no-color",
      "--no-renames",
      "--unified=" & $unified,
    ]
  if not hasHead or file.status == gdfsUntracked:
    result.add ["--no-index", "--", "/dev/null", file.path]
  else:
    result.add ["HEAD", "--", file.path]

proc patchLimitError(path: string, limit: int, total: bool): string =
  if total:
    return
      "The Git diff byte limit for this panel was reached before " & path &
      " could be loaded."
  "The diff for " & path & " exceeds the per-file limit of " & $limit & " bytes."

proc loadGitDiffFile(
    rootPath: string,
    hasHead: bool,
    file: GitFileDiff,
    limits: GitDiffPatchLimits,
    usedBytes: int,
    explicit: bool,
    control: SharedPtr[GitDiffControl],
): GitDiffFileLoadResult =
  result.file = file
  result.file.patch.setLen(0)
  result.file.syntaxPatch.setLen(0)
  result.file.additions = 0
  result.file.deletions = 0
  result.file.binary = false
  result.file.errorMessage.setLen(0)
  let
    perFileLimit = max(limits.perFileBytes, 1)
    remaining = limits.totalBytes - usedBytes
  if file.requiresExplicitLoad and not explicit:
    result.file.patchState = gdpsSkipped
    result.file.errorMessage =
      "Large generated files are not loaded automatically. Expand this file to request its diff."
    return
  if remaining <= 0:
    result.file.patchState = gdpsSkipped
    result.file.errorMessage = patchLimitError(file.path, perFileLimit, total = true)
    return
  let syntax = executeGit(
    rootPath,
    file.gitDiffArguments(hasHead, 2_147_483_647),
    control,
    maxOutputBytes = min(perFileLimit, remaining),
  )
  if syntax.limitExceeded:
    result.file.patchState = gdpsSkipped
    result.file.errorMessage =
      patchLimitError(file.path, perFileLimit, total = remaining <= perFileLimit)
    return
  if syntax.code != 0 and
      not ((not hasHead or file.status == gdfsUntracked) and syntax.code == 1):
    result.file.patchState = gdpsFailed
    result.file.errorMessage =
      "Could not read diff for " & file.path & ":\n" & syntax.output
    return
  if syntax.output.len == 0:
    result.file.patchState = gdpsLoaded
    result.file.patchBytes = 0
    result.threadId = getThreadId()
    return
  let
    visibleRemaining = remaining - syntax.output.len
    perFileRemaining = perFileLimit - syntax.output.len
  if visibleRemaining <= 0:
    result.file.patchState = gdpsSkipped
    result.file.errorMessage = patchLimitError(file.path, perFileLimit, total = true)
    return
  if perFileRemaining <= 0:
    result.file.patchState = gdpsSkipped
    result.file.errorMessage = patchLimitError(file.path, perFileLimit, total = false)
    return
  let visible = executeGit(
    rootPath,
    file.gitDiffArguments(hasHead, 3),
    control,
    maxOutputBytes = min(perFileRemaining, visibleRemaining),
  )
  if visible.limitExceeded:
    result.file.patchState = gdpsSkipped
    result.file.errorMessage = patchLimitError(
      file.path, perFileLimit, total = visibleRemaining <= perFileRemaining
    )
    return
  if visible.code != 0 and
      not ((not hasHead or file.status == gdfsUntracked) and visible.code == 1):
    result.file.patchState = gdpsFailed
    result.file.errorMessage =
      "Could not read diff hunks for " & file.path & ":\n" & visible.output
    return
  result.file.patch = visible.output
  result.file.syntaxPatch = syntax.output
  result.file.summarizePatch(syntax.output)
  result.threadId = getThreadId()

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

proc includeMaterializedPath(paths: var HashSet[string], path: string): bool =
  if path in paths:
    return true
  if paths.len >= GitDiffMaterializedSectionLimit:
    return
  paths.incl path
  true

proc includeMaterializedTextView(
    buttons, textViews: var HashSet[string], path: string
): bool =
  if path notin textViews and textViews.len >= GitDiffMaterializedSectionLimit:
    return
  if not buttons.includeMaterializedPath(path):
    return
  textViews.incl path
  true

proc syncDisclosureButtons(panel: KosmoGitDiffPanel)
proc scheduleSectionLayout(panel: KosmoGitDiffPanel)
proc handleSharedKeys(panel: KosmoGitDiffPanel, event: nimkit.KeyEvent): bool
proc ensureFileMaterialized(panel: KosmoGitDiffPanel, index: int, forceText = false)
proc queueFilePatch(
  panel: KosmoGitDiffPanel, path: string, explicit: bool, retry = false
)

proc queueSection(panel: KosmoGitDiffPanel, path: string)
proc layoutDisclosureButtons(
  panel: KosmoGitDiffPanel, snapshot: nimkit.TextLayoutSnapshot
) {.slot.}

func gitDiffStatusLabel(status: GitDiffFileStatus): string =
  case status
  of gdfsModified: "modified"
  of gdfsAdded: "added"
  of gdfsDeleted: "deleted"
  of gdfsRenamed: "renamed"
  of gdfsCopied: "copied"
  of gdfsTypeChanged: "type changed"
  of gdfsConflicted: "conflicted"
  of gdfsUntracked: "untracked"

proc renderDiff(panel: KosmoGitDiffPanel) =
  var document = "# Git Diff\n\n"
  var additions, deletions, binaries, loadedFiles: int
  for file in panel.snapshot.files:
    if file.patchState == gdpsLoaded:
      inc loadedFiles
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
    document.add "| Changes | " & $panel.snapshot.files.len & " files"
    if panel.snapshot.fileLimitReached:
      document.add " · showing the first " & $panel.snapshot.files.len
    if loadedFiles > 0:
      document.add " · " & $loadedFiles & " loaded · +" & $additions & " / −" &
        $deletions
      if binaries > 0:
        document.add " · " & $binaries & " binary"
    if panel.snapshot.source == gdsStandardInput:
      document.add " |\n| Compare | Piped unified diff |\n"
    else:
      document.add " |\n| Compare | Working tree ↔ " &
        (if panel.snapshot.hasHead: "HEAD" else: "empty tree") &
        " · includes untracked files |\n"
  document.add "\n"
  if panel.snapshot.fileLimitReached:
    document.add "Only the first listed files are shown. " &
      "Narrow the Git Diff path to inspect more changes.\n\n"
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
  ## Toggle a file section and request its patch when it is expanded.
  if index in 0 ..< panel.snapshot.files.len:
    let path = panel.snapshot.files[index].path
    if path in panel.collapsed:
      panel.collapsed.excl path
      panel.forcedDisclosurePaths.clear()
      panel.forcedDisclosurePaths.incl path
      panel.forcedTextPaths.clear()
      panel.forcedTextPaths.incl path
      panel.explicitPatchPaths.incl path
      panel.ensureFileMaterialized(index, forceText = true)
      panel.queueFilePatch(path, explicit = true, retry = true)
    else:
      panel.collapsed.incl path
      panel.forcedTextPaths.excl path
      let section = addr panel.sections[path]
      let owner = panel.window()
      if owner of nimkit.Window and not section[].textView.isNil and
          nimkit.Window(owner).firstResponder == section[].textView:
        panel.ensureFileMaterialized(index)
        if not section[].disclosureButton.isNil:
          discard nimkit.Window(owner).makeFirstResponder(section[].disclosureButton)
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
        var target: nimkit.Responder
        if next < 0:
          panel.forcedDisclosurePaths.clear()
          panel.syncDisclosureButtons()
          target = panel.markdownView.textView()
        elif next >= panel.snapshot.files.len:
          panel.forcedDisclosurePaths.clear()
          panel.syncDisclosureButtons()
          target = panel.refreshButton
        else:
          let path = panel.snapshot.files[next].path
          panel.forcedDisclosurePaths.clear()
          panel.forcedDisclosurePaths.incl path
          panel.ensureFileMaterialized(next)
          panel.syncDisclosureButtons()
          target = panel.disclosureButtons.getOrDefault(path)
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

proc bindDisclosureButton(
    panel: KosmoGitDiffPanel,
    button: GitDiffDisclosureButton,
    fileIndex: int,
    filePath: string,
) =
  button.panel = panel.unsafeWeakRef()
  button.fileIndex = fileIndex
  button.filePath = filePath
  button.accessibilityIdentifier = "kosmo.gitDiff.file." & $fileIndex

protocol GitDiffTextDrawing of nimkit.ViewDrawingProtocol:
  method drawUnderlay(view: GitDiffTextView, context: nimkit.DrawContext) =
    view.drawTextViewUnderlayInViewport(context)

  method draw(view: GitDiffTextView, context: nimkit.DrawContext) =
    view.drawTextViewTextInViewport(context)

  method drawOverlay(view: GitDiffTextView, context: nimkit.DrawContext) =
    view.drawTextViewOverlay(context)

proc newGitDiffTextView(panel: KosmoGitDiffPanel): GitDiffTextView =
  var fresh = false
  if panel.textViewPool.len > 0:
    result = panel.textViewPool[^1]
    panel.textViewPool.setLen(panel.textViewPool.len - 1)
  else:
    fresh = true
    result = GitDiffTextView()
    result.initTextViewFields()
  result.editable = false
  result.selectable = true
  result.propagatesIntrinsicContentSizeChanges = false
  result.textContainer =
    nimkit.initTextContainer(wraps = false, widthTracksTextView = true)
  result.layoutManager().usesBackgroundLayout = true
  if fresh:
    let weakPanel = panel.unsafeWeakRef()
    let keys: nimkit.DynamicMethod = proc(
        self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
    ) =
      invocation.setResult(
        not weakPanel.isNil and
          weakPanel[].handleSharedKeys(invocation.argsAs(nimkit.KeyEvent))
      )
    discard result.withProtocol(GitDiffTextDrawing)
    discard result.replaceMethod(nimkitSelectors.performKeyEquivalent(), keys)
    result.layoutManager().connect(
      nimkit.layoutDidComplete, panel, layoutDisclosureButtons
    )
  result.textStorage = nimkit.newTextStorage()

proc releaseFileTextView(panel: KosmoGitDiffPanel, path: string) =
  if not panel.sections.hasKey(path):
    return
  let section = addr panel.sections[path]
  if section[].textView.isNil:
    return
  let textView = section[].textView
  textView.removeFromSuperview()
  textView.setHiddenFromLayout(true)
  section[].textView = nil
  section[].ready = false
  section[].layoutStarted = false
  if panel.textViewPool.len < GitDiffViewPoolLimit:
    panel.textViewPool.add textView

proc releaseFileDisclosureButton(panel: KosmoGitDiffPanel, path: string) =
  if not panel.sections.hasKey(path):
    return
  let section = addr panel.sections[path]
  if section[].disclosureButton.isNil:
    return
  let button = section[].disclosureButton
  button.removeFromSuperview()
  button.setHiddenFromLayout(true)
  section[].disclosureButton = nil
  panel.disclosureButtons.del path
  if panel.disclosureButtonPool.len < GitDiffViewPoolLimit:
    panel.disclosureButtonPool.add button

proc ensureFileMaterialized(panel: KosmoGitDiffPanel, index: int, forceText = false) =
  if panel.closed or index notin 0 ..< panel.snapshot.files.len:
    return
  let
    file = panel.snapshot.files[index]
    path = file.path
  if not panel.sections.hasKey(path):
    return
  let section = addr panel.sections[path]
  if section[].disclosureButton.isNil:
    let button =
      if panel.disclosureButtonPool.len > 0:
        let next = panel.disclosureButtonPool[^1]
        panel.disclosureButtonPool.setLen(panel.disclosureButtonPool.len - 1)
        next
      else:
        panel.newDisclosureButton(index, path, nimkit.rect(0, 0, 100, 30))
    panel.bindDisclosureButton(button, index, path)
    section[].disclosureButton = button
    panel.disclosureButtons[path] = button
    panel.documentView.addSubview(button)
  if forceText or path notin panel.collapsed:
    if section[].textView.isNil:
      let textView = panel.newGitDiffTextView()
      textView.accessibilityLabel = "Diff for " & path
      section[].textView = textView
      panel.documentView.addSubview(textView)
      if section[].patchState in {gdpsSkipped, gdpsFailed}:
        textView.textStorage = nimkit.newTextStorage(
          if section[].patchError.len > 0:
            section[].patchError
          else:
            "This diff could not be loaded."
        )
        section[].ready = true
      elif section[].patchState == gdpsLoaded and not section[].pending:
        section[].ready = false
        panel.queueSection(path)
      else:
        textView.textStorage = nimkit.newTextStorage("Loading diff…")

proc syncDisclosureButtons(panel: KosmoGitDiffPanel) =
  if panel.closed or panel.scrollView.isNil:
    return
  let
    viewport = panel.scrollView.viewportSize()
    width = max(viewport.width - 48, 1)
    offset = panel.scrollView.contentOffset()
    visible = nimkit.rect(nimkit.initPoint(offset.x, offset.y), viewport)
    buffer = max(viewport.height, 120.0'f32)
    materializedRect = nimkit.rect(
      0,
      max(visible.minY - buffer, 0.0'f32),
      max(viewport.width, 1.0'f32),
      visible.size.height + buffer * 2,
    )
  let summary = panel.markdownView.textView().layoutManager().layoutSnapshot()
  let summaryHeight = max(
    summary.contentSize.height + panel.markdownView.textInsets().vertical,
    GitDiffReservedSummaryHeight,
  )
  panel.markdownView.setFrameFromLayout(
    nimkit.rect(0, 0, viewport.width, summaryHeight)
  )
  var
    desiredButtons = initHashSet[string]()
    desiredTextViews = initHashSet[string]()
    y = summaryHeight + 16
    documentWidth = viewport.width
    focusedDisclosurePath: string
  let owner = panel.window()
  if owner of nimkit.Window:
    for path, section in panel.sections:
      if nimkit.Window(owner).firstResponder == section.disclosureButton:
        focusedDisclosurePath = path
        break
  if focusedDisclosurePath.len > 0:
    discard desiredButtons.includeMaterializedPath(focusedDisclosurePath)
  for path in panel.forcedDisclosurePaths:
    if panel.sections.hasKey(path):
      discard desiredButtons.includeMaterializedPath(path)
  for path in panel.forcedTextPaths:
    if panel.sections.hasKey(path):
      discard includeMaterializedTextView(desiredButtons, desiredTextViews, path)
  for file in panel.snapshot.files:
    let
      path = file.path
      section = addr panel.sections[path]
      headingFrame = nimkit.rect(24, y, width, 30)
      expanded = path notin panel.collapsed
      contentHeight = max(section[].contentHeight, 24.0'f32)
      contentFrame = nimkit.rect(34, y + 38, max(width - 20, 1), contentHeight)
    if not headingFrame.intersection(materializedRect).isEmpty:
      discard desiredButtons.includeMaterializedPath(path)
    if expanded and not contentFrame.intersection(materializedRect).isEmpty:
      discard includeMaterializedTextView(desiredButtons, desiredTextViews, path)
    if expanded:
      y += 38 + contentHeight + 24
    else:
      y += 46
  for path in desiredTextViews:
    let section = addr panel.sections[path]
    if section[].patchState == gdpsUnloaded and not section[].patchPending:
      let explicit = path in panel.explicitPatchPaths
      if not section[].requiresExplicitLoad or explicit:
        panel.queueFilePatch(path, explicit)
  for path, section in panel.sections:
    if not desiredTextViews.contains(path) and not section.textView.isNil:
      panel.releaseFileTextView(path)
    if not desiredButtons.contains(path) and not section.disclosureButton.isNil:
      panel.releaseFileDisclosureButton(path)
  y = summaryHeight + 16
  for index, file in panel.snapshot.files:
    let path = file.path
    let section = addr panel.sections[path]
    if path in desiredButtons:
      panel.ensureFileMaterialized(index, forceText = path in desiredTextViews)
    let button = section[].disclosureButton
    if not button.isNil:
      button.fileIndex = index
      button.title =
        file.path & (
          if section[].patchState == gdpsLoaded:
            if file.binary: "   binary"
            else:
              "   +" & $file.additions & " / −" & $file.deletions
          elif section[].patchPending:
            "   preparing…"
          elif section[].patchState in {gdpsSkipped, gdpsFailed}:
            "   diff unavailable"
          else:
            "   " & gitDiffStatusLabel(file.status)
        )
      button.setFrameFromLayout(nimkit.rect(24, y, width, 30))
      button.hidden = false
      button.needsDisplay = true
      let collapsed = file.path in panel.collapsed
      button.toolTip = (if collapsed: "Expand " else: "Collapse ") & file.path
    let expanded = path notin panel.collapsed
    y += 38
    if expanded:
      let textView = section[].textView
      if not textView.isNil:
        textView.setHiddenFromLayout(false)
        if section[].ready and not section[].layoutStarted:
          textView.setFrameFromLayout(nimkit.rect(34, y, max(width - 20, 1), 1))
          textView.layoutManager().requestBackgroundLayout(allowUncachedLayout = true)
          section[].layoutStarted = true
        let snapshot = textView.layoutManager().layoutSnapshot()
        let size = nimkit.initSize(
          max(snapshot.contentSize.width, snapshot.usedRect.maxX),
          max(snapshot.contentSize.height, snapshot.usedRect.maxY),
        )
        let codeHeight = max(size.height, 24.0'f32)
        let codeWidth = max(max(width - 20, size.width), 1.0'f32)
        textView.setFrameFromLayout(nimkit.rect(34, y, codeWidth, codeHeight))
        section[].contentHeight = codeHeight
        documentWidth = max(documentWidth, codeWidth + 68)
        y += codeHeight + 24
      else:
        y += max(section[].contentHeight, 24.0'f32) + 24
    else:
      let textView = section[].textView
      if not textView.isNil:
        textView.setHiddenFromLayout(true)
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

proc diffScrollGeometryChanged(panel: KosmoGitDiffPanel) {.slot.} =
  panel.scheduleSectionLayout()

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
      if path notin panel.collapsed and not section.textView.isNil:
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
  ## Return a disclosure control, materializing that row when necessary.
  if fileIndex in 0 ..< panel.snapshot.files.len:
    let path = panel.snapshot.files[fileIndex].path
    panel.forcedDisclosurePaths.clear()
    panel.forcedDisclosurePaths.incl path
    panel.ensureFileMaterialized(fileIndex)
    panel.syncDisclosureButtons()
    return panel.disclosureButtons.getOrDefault(path)

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

proc executeFileDiff(
  worker: AgentProxy[GitDiffWorker],
  root: string,
  path: string,
  status: GitDiffFileStatus,
  requiresExplicitLoad: bool,
  hasHead: bool,
  limits: GitDiffPatchLimits,
  usedBytes: int,
  explicit: bool,
  generation: uint64,
  control: SharedPtr[GitDiffControl],
) {.signal.}

proc fileDiffFinished(
  worker: GitDiffWorker, loaded: SharedPtr[GitDiffFileLoadResult]
) {.signal.}

proc executeDiff(
    worker: GitDiffWorker,
    root: string,
    scopePath: string,
    generation: uint64,
    control: SharedPtr[GitDiffControl],
) {.slot.} =
  emit worker.diffFinished(readGitDiff(root, control, scopePath), generation)

proc executeFileDiff(
    worker: GitDiffWorker,
    root: string,
    path: string,
    status: GitDiffFileStatus,
    requiresExplicitLoad: bool,
    hasHead: bool,
    limits: GitDiffPatchLimits,
    usedBytes: int,
    explicit: bool,
    generation: uint64,
    control: SharedPtr[GitDiffControl],
) {.slot.} =
  let file =
    GitFileDiff(path: path, status: status, requiresExplicitLoad: requiresExplicitLoad)
  var loaded =
    loadGitDiffFile(root, hasHead, file, limits, usedBytes, explicit, control)
  loaded.generation = generation
  loaded.threadId = getThreadId()
  emit worker.fileDiffFinished(newSharedPtr(unsafeIsolate(move loaded)))

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
    panel.loading = panel.loading or section.patchPending or section.pending
    preparing = preparing or section.patchPending or section.pending
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
  section[].ready = not section[].textView.isNil
  section[].layoutStarted = false
  if prepared.built:
    inc panel.xHighlightBuildCount
  panel.xHighlightThreadId = prepared.threadId
  if not section[].textView.isNil:
    if prepared.errorMessage.len > 0:
      section[].textView.textStorage =
        nimkit.newTextStorage("Could not prepare this diff: " & prepared.errorMessage)
    else:
      section[].textView.textStorage =
        nimkit.newTextStorage(move prepared.source, move prepared.runs)
  panel.updateLoading()
  panel.scheduleSectionLayout()

proc queueSection(panel: KosmoGitDiffPanel, path: string) =
  if not panel.sections.hasKey(path) or panel.sections[path].textView.isNil:
    return
  inc panel.generation
  panel.sections[path].generation = panel.generation
  panel.sections[path].pending = true
  let key = (
    source: panel.sections[path].syntaxPatch.replace("\r\n", "\n"),
    language: "diff:" & path.diffLanguage(),
  )
  emit panel.highlightWorker.highlightDiff(
    path,
    key,
    panel.sections[path].patch.replace("\r\n", "\n"),
    panel.markdownView.markdownStyle(),
    panel.generation,
    panel.control,
  )
  panel.updateLoading()

proc updateSnapshotFile(panel: KosmoGitDiffPanel, file: GitFileDiff) =
  let index = panel.snapshotFileIndexes.getOrDefault(file.path, -1)
  if index >= 0:
    panel.snapshot.files[index] = file

func snapshotFileIndex(panel: KosmoGitDiffPanel, path: string): int =
  panel.snapshotFileIndexes.getOrDefault(path, -1)

proc skipQueuedPatch(panel: KosmoGitDiffPanel, path, message: string) =
  if not panel.sections.hasKey(path):
    return
  var section = addr panel.sections[path]
  section[].patchPending = false
  section[].patchState = gdpsSkipped
  section[].patchError = message
  let index = panel.snapshotFileIndex(path)
  if index >= 0:
    panel.snapshot.files[index].patchState = gdpsSkipped
    panel.snapshot.files[index].errorMessage = message
    panel.snapshot.files[index].patchBytes = 0

proc startNextPatch(panel: KosmoGitDiffPanel) =
  if panel.closed or panel.activePatchPath.len > 0:
    return
  while panel.patchQueue.len > 0:
    let request = panel.patchQueue.pop()
    if not panel.sections.hasKey(request.path):
      continue
    let section = addr panel.sections[request.path]
    if section[].loadGeneration != request.generation or not section[].patchPending:
      continue
    if not panel.repositoryBacked:
      section[].patchPending = false
      continue
    if panel.patchBytesUsed >= panel.patchLimits.totalBytes:
      panel.skipQueuedPatch(
        request.path,
        patchLimitError(request.path, panel.patchLimits.perFileBytes, total = true),
      )
      continue
    panel.activePatchPath = request.path
    let fileIndex = panel.snapshotFileIndex(request.path)
    if fileIndex < 0:
      section[].patchPending = false
      panel.activePatchPath.setLen(0)
      continue
    let file = panel.snapshot.files[fileIndex]
    let rootPath =
      if panel.snapshot.rootPath.len > 0:
        panel.snapshot.rootPath
      else:
        panel.repositoryRootPath
    emit panel.worker.executeFileDiff(
      rootPath, request.path, file.status, file.requiresExplicitLoad,
      panel.snapshot.hasHead, panel.patchLimits, panel.patchBytesUsed, request.explicit,
      request.generation, panel.control,
    )
    return
  panel.updateLoading()
  panel.renderDiff()
  panel.scheduleSectionLayout()

proc queueFilePatch(
    panel: KosmoGitDiffPanel, path: string, explicit: bool, retry = false
) =
  if panel.closed or not panel.sections.hasKey(path) or not panel.repositoryBacked:
    return
  let section = addr panel.sections[path]
  if section[].patchPending or section[].patchState == gdpsLoaded:
    return
  if section[].patchState in {gdpsSkipped, gdpsFailed} and not retry:
    return
  inc panel.patchGeneration
  section[].patchPending = true
  section[].loadGeneration = panel.patchGeneration
  panel.patchQueue.add GitDiffPatchRequest(
    path: path, generation: panel.patchGeneration, explicit: explicit
  )
  panel.updateLoading()
  panel.startNextPatch()

proc repositoryFileDiffFinished(
    panel: KosmoGitDiffPanel, loaded: SharedPtr[GitDiffFileLoadResult]
) {.slot.} =
  if panel.closed:
    return
  let path = loaded[].file.path
  if panel.activePatchPath == path:
    panel.activePatchPath.setLen(0)
  if not panel.sections.hasKey(path):
    panel.startNextPatch()
    return
  let section = addr panel.sections[path]
  if section[].loadGeneration != loaded[].generation:
    panel.startNextPatch()
    return
  let previousBytes = section[].patchBytes
  section[].patchPending = false
  section[].patchState = loaded[].file.patchState
  section[].patchError = loaded[].file.errorMessage
  section[].patchBytes = loaded[].file.patchBytes
  section[].additions = loaded[].file.additions
  section[].deletions = loaded[].file.deletions
  section[].binary = loaded[].file.binary
  if previousBytes > 0:
    panel.patchBytesUsed -= previousBytes
  if loaded[].file.patchState == gdpsLoaded:
    section[].patch = move loaded[].file.patch
    section[].syntaxPatch = move loaded[].file.syntaxPatch
    section[].requiresExplicitLoad = loaded[].file.requiresExplicitLoad
    panel.patchBytesUsed += section[].patchBytes
  else:
    section[].patch.setLen(0)
    section[].syntaxPatch.setLen(0)
  var snapshotFile = loaded[].file
  snapshotFile.revision = section[].revision
  snapshotFile.patch = section[].patch
  snapshotFile.syntaxPatch = section[].syntaxPatch
  snapshotFile.patchState = section[].patchState
  snapshotFile.patchBytes = section[].patchBytes
  snapshotFile.errorMessage = section[].patchError
  snapshotFile.additions = section[].additions
  snapshotFile.deletions = section[].deletions
  snapshotFile.binary = section[].binary
  panel.updateSnapshotFile(snapshotFile)
  if not section[].textView.isNil:
    if section[].patchState == gdpsLoaded:
      section[].ready = false
      section[].layoutStarted = false
      panel.queueSection(path)
    else:
      section[].textView.textStorage = nimkit.newTextStorage(
        if section[].patchError.len > 0:
          section[].patchError
        else:
          "This diff could not be loaded."
      )
      section[].ready = true
      section[].layoutStarted = false
  panel.updateLoading()
  panel.renderDiff()
  panel.scheduleSectionLayout()
  panel.startNextPatch()

func sameGitDiffMetadata(left, right: GitDiffSnapshot): bool =
  if left.source != right.source or left.rootPath != right.rootPath or
      left.scopePath != right.scopePath or left.branch != right.branch or
      left.hasHead != right.hasHead or left.errorMessage != right.errorMessage or
      left.revision != right.revision or left.fileLimitReached != right.fileLimitReached or
      left.files.len != right.files.len:
    return false
  for index, file in left.files:
    let other = right.files[index]
    if file.path != other.path or file.status != other.status or
        file.requiresExplicitLoad != other.requiresExplicitLoad:
      return false
  true

proc clearSectionContent(panel: KosmoGitDiffPanel, path: string) =
  if not panel.sections.hasKey(path):
    return
  let section = addr panel.sections[path]
  if section[].patchBytes > 0:
    panel.patchBytesUsed = max(panel.patchBytesUsed - section[].patchBytes, 0)
  section[].patch.setLen(0)
  section[].syntaxPatch.setLen(0)
  section[].patchState = gdpsUnloaded
  section[].patchError.setLen(0)
  section[].patchBytes = 0
  section[].additions = 0
  section[].deletions = 0
  section[].binary = false
  section[].loadGeneration = 0
  section[].patchPending = false
  section[].pending = false
  section[].ready = false
  section[].layoutStarted = false
  if not section[].textView.isNil:
    section[].textView.textStorage = nimkit.newTextStorage("Loading diff…")

func sameGitDiffFileMetadata(left, right: GitFileDiff): bool =
  left.path == right.path and left.status == right.status and
    left.requiresExplicitLoad == right.requiresExplicitLoad and left.revision.len > 0 and
    left.revision == right.revision

proc rebuildSnapshotFileIndexes(panel: KosmoGitDiffPanel) =
  panel.snapshotFileIndexes.clear()
  for index, file in panel.snapshot.files:
    panel.snapshotFileIndexes[file.path] = index

proc mergeSectionIntoSnapshot(panel: KosmoGitDiffPanel, index: int, path: string) =
  let section = addr panel.sections[path]
  if index notin 0 ..< panel.snapshot.files.len:
    return
  panel.snapshot.files[index].patch = section[].patch
  panel.snapshot.files[index].syntaxPatch = section[].syntaxPatch
  panel.snapshot.files[index].patchState = section[].patchState
  panel.snapshot.files[index].patchBytes = section[].patchBytes
  panel.snapshot.files[index].errorMessage = section[].patchError
  panel.snapshot.files[index].additions = section[].additions
  panel.snapshot.files[index].deletions = section[].deletions
  panel.snapshot.files[index].binary = section[].binary

proc applyDiff(panel: KosmoGitDiffPanel, snapshot: GitDiffSnapshot) {.slot.} =
  if panel.closed:
    return
  panel.readingGit = false
  if panel.hasSnapshot and (
    if snapshot.source == gdsRepository:
      sameGitDiffMetadata(panel.snapshot, snapshot)
    else:
      panel.snapshot == snapshot
  ):
    panel.updateLoading()
    panel.scheduleSectionLayout()
    return
  let
    previousSnapshot = panel.snapshot
    revisionChanged =
      panel.hasSnapshot and snapshot.source == gdsRepository and (
        previousSnapshot.source != gdsRepository or
        previousSnapshot.rootPath != snapshot.rootPath or
        previousSnapshot.revision != snapshot.revision
      )
  if revisionChanged:
    panel.patchQueue.setLen(0)
  panel.hasSnapshot = true
  panel.snapshot = snapshot
  panel.rebuildSnapshotFileIndexes()
  var previousFileIndexes = initTable[string, int]()
  if revisionChanged and previousSnapshot.source == gdsRepository:
    for index, file in previousSnapshot.files:
      previousFileIndexes[file.path] = index
  var retained = initHashSet[string]()
  for index, file in snapshot.files:
    retained.incl file.path
    if not panel.sections.hasKey(file.path):
      panel.sections[file.path] = GitDiffSection(contentHeight: 24.0'f32)
      panel.collapsed.incl file.path
    let section = addr panel.sections[file.path]
    var previousFile: GitFileDiff
    var foundPreviousFile: bool
    if revisionChanged and previousSnapshot.source == gdsRepository and
        previousFileIndexes.hasKey(file.path):
      previousFile = previousSnapshot.files[previousFileIndexes[file.path]]
      foundPreviousFile = true
    let preservePatch =
      revisionChanged and foundPreviousFile and
      sameGitDiffFileMetadata(previousFile, file) and section[].patchState == gdpsLoaded and
      not section[].patchPending
    if revisionChanged and not preservePatch:
      panel.clearSectionContent(file.path)
    let incomingLoaded = file.patchState == gdpsLoaded or file.patch.len > 0
    var contentChanged: bool
    if incomingLoaded:
      contentChanged =
        section[].patchState != gdpsLoaded or section[].patch != file.patch or
        section[].syntaxPatch != file.syntaxPatch
      if contentChanged:
        panel.clearSectionContent(file.path)
        section[].patch = file.patch
        section[].syntaxPatch = file.syntaxPatch
        section[].patchState = gdpsLoaded
        section[].patchBytes =
          if file.patchBytes > 0:
            file.patchBytes
          else:
            file.patch.len + file.syntaxPatch.len
        panel.patchBytesUsed += section[].patchBytes
      section[].additions = file.additions
      section[].deletions = file.deletions
      section[].binary = file.binary
    section[].requiresExplicitLoad = file.requiresExplicitLoad
    section[].revision = file.revision
    if file.status != section[].status:
      section[].status = file.status
    section[].patchError = file.errorMessage
    if file.patchState in {gdpsSkipped, gdpsFailed}:
      section[].patchState = file.patchState
      section[].additions = file.additions
      section[].deletions = file.deletions
      section[].binary = file.binary
    panel.mergeSectionIntoSnapshot(index, file.path)
    if contentChanged and not section[].textView.isNil:
      section[].ready = false
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
          nimkit.Responder(panel.sections[path].disclosureButton),
        ]:
      discard nimkit.Window(owner).makeFirstResponder(panel.markdownView.textView())
    panel.releaseFileTextView(path)
    panel.releaseFileDisclosureButton(path)
    panel.clearSectionContent(path)
    panel.sections.del path
    panel.collapsed.excl path
    panel.forcedDisclosurePaths.excl path
    panel.forcedTextPaths.excl path
    panel.explicitPatchPaths.excl path
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
      pending = pending or section.patchPending or section.pending
      if path notin panel.collapsed and not section.textView.isNil:
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
    var paths: seq[string]
    for path in panel.sections.keys:
      paths.add path
    for path in paths:
      panel.releaseFileTextView(path)
      panel.releaseFileDisclosureButton(path)
    panel.sections.clear()
    panel.snapshotFileIndexes.clear()
    panel.disclosureButtons.clear()
    panel.textViewPool.setLen(0)
    panel.disclosureButtonPool.setLen(0)
    panel.forcedDisclosurePaths.clear()
    panel.forcedTextPaths.clear()
    panel.explicitPatchPaths.clear()
    panel.patchQueue.setLen(0)
    panel.activePatchPath.setLen(0)
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
  for path, section in panel.sections:
    if not section.textView.isNil:
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

proc materializedViewCount*(panel: KosmoGitDiffPanel): int =
  ## Number of file controls currently attached to the document view.
  for section in panel.sections.values:
    if not section.disclosureButton.isNil:
      inc result
    if not section.textView.isNil:
      inc result

proc requestFilePatch*(panel: KosmoGitDiffPanel, index: int): bool =
  ## Explicitly request a repository file patch without expanding its row.
  if panel.isNil or panel.closed or index notin 0 ..< panel.snapshot.files.len:
    return
  if not panel.repositoryBacked:
    return
  let path = panel.snapshot.files[index].path
  panel.explicitPatchPaths.incl path
  panel.queueFilePatch(path, explicit = true, retry = true)
  result = true

proc textViewForFile*(panel: KosmoGitDiffPanel, index: int): nimkit.TextView =
  ## Return a requested file's text view, materializing and loading it as needed.
  if index in 0 ..< panel.snapshot.files.len:
    let path = panel.snapshot.files[index].path
    panel.forcedDisclosurePaths.clear()
    panel.forcedDisclosurePaths.incl path
    panel.forcedTextPaths.clear()
    panel.forcedTextPaths.incl path
    panel.explicitPatchPaths.incl path
    panel.ensureFileMaterialized(index, forceText = true)
    panel.syncDisclosureButtons()
    return panel.sections[path].textView

proc newKosmoGitDiffPanel(
    rootPath: string,
    markdownStyle: nimkit.MarkdownStyle,
    refreshesRepository: bool,
    scopePath = "",
    patchLimits = initGitDiffPatchLimits(),
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
    snapshotFileIndexes: initTable[string, int](),
    forcedDisclosurePaths: initHashSet[string](),
    forcedTextPaths: initHashSet[string](),
    explicitPatchPaths: initHashSet[string](),
    patchLimits:
      initGitDiffPatchLimits(patchLimits.perFileBytes, patchLimits.totalBytes),
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
  result.scrollView.clipView().connect(
    nimkit.geometryDidChange, result, diffScrollGeometryChanged
  )
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
      for index, file in panel[].snapshot.files:
        panel[].collapsed.incl file.path
        let owner = panel[].window()
        if owner of nimkit.Window and not panel[].sections[file.path].textView.isNil and
            nimkit.Window(owner).firstResponder == panel[].sections[file.path].textView:
          panel[].forcedDisclosurePaths.clear()
          panel[].forcedDisclosurePaths.incl file.path
          panel[].ensureFileMaterialized(index)
          discard nimkit.Window(owner).makeFirstResponder(
              panel[].sections[file.path].disclosureButton
            )
      panel[].scheduleSectionLayout()
  result.pool.start()
  var worker = GitDiffWorker()
  result.worker = worker.moveToThread(result.pool)
  connectThreaded(result.worker, executeDiff, result.worker, executeDiff)
  connectThreaded(result.worker, executeFileDiff, result.worker, executeFileDiff)
  connectThreaded(
    result.worker, diffFinished, result, KosmoGitDiffPanel.repositoryDiffFinished()
  )
  connectThreaded(
    result.worker,
    fileDiffFinished,
    result,
    KosmoGitDiffPanel.repositoryFileDiffFinished(),
  )
  var highlighter = GitDiffHighlightWorker()
  result.highlightWorker = highlighter.moveToThread(nimkitWorkerPool())
  connectThreaded(
    result.highlightWorker, highlightDiff, result.highlightWorker, highlightDiff
  )
  connectThreaded(
    result.highlightWorker,
    highlightingFinished,
    result,
    KosmoGitDiffPanel.applyHighlighting(),
  )
  if refreshesRepository:
    result.refresh()
  else:
    result.renderDiff()

proc newKosmoGitDiffPanel*(
    rootPath: string,
    markdownStyle = nimkit.initMarkdownStyle(),
    scopePath = "",
    patchLimits = initGitDiffPatchLimits(),
): KosmoGitDiffPanel =
  ## Construct a repository-backed Git Diff view.
  newKosmoGitDiffPanel(
    rootPath,
    markdownStyle,
    refreshesRepository = true,
    scopePath = scopePath,
    patchLimits = patchLimits,
  )

proc newKosmoGitDiffPanel*(
    snapshot: GitDiffSnapshot, markdownStyle = nimkit.initMarkdownStyle()
): KosmoGitDiffPanel =
  ## Construct a Git Diff view from a static snapshot such as piped input.
  result =
    newKosmoGitDiffPanel(snapshot.rootPath, markdownStyle, refreshesRepository = false)
  result.displayDiff(snapshot)

var gitDiffWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
