import std/[monotimes, os, osproc, strutils, tempfiles, times, unicode, unittest]
import figdraw
import sigils/[core, threads]
import merenda/nimkit
import merenda/kosmo/kosmo
from merenda/nimkit/foundation/mainthreadwork import drainMainThreadWork

proc git(root: string, args: varargs[string]) =
  var arguments = @["-C", root]
  arguments.add args
  let process = startProcess("git", args = arguments, options = {poUsePath})
  defer:
    process.close()
  doAssert process.waitForExit() == 0

proc initRepository(root: string) =
  git(root, "init", "-q")
  git(root, "config", "core.autocrlf", "false")
  git(root, "config", "user.name", "Kosmo Diff Test")
  git(root, "config", "user.email", "kosmo-test@example.invalid")

proc firstResponderIs(window: Window, expected: Responder): bool =
  window.firstResponder == expected

proc rendersDisclosureArrow(view: View, expanded: bool): bool =
  let renders = view.buildRenders()
  if DefaultDrawLevel notin renders:
    return
  var bars: set[1 .. 3]
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind != nkRectangle:
      continue
    let
      length = if expanded: node.screenBox.w else: node.screenBox.h
      thickness = if expanded: node.screenBox.h else: node.screenBox.w
    if abs(thickness - 1.0'f32) < 0.01'f32:
      if abs(length - 7.0'f32) < 0.01'f32:
        bars.incl 1
      elif abs(length - 5.0'f32) < 0.01'f32:
        bars.incl 2
      elif abs(length - 3.0'f32) < 0.01'f32:
        bars.incl 3
  bars == {1, 2, 3}

proc visibleLoadedDiffTextViewCount(panel: KosmoGitDiffPanel): int =
  for child in panel.documentView.subviews():
    if child of TextView and not child.visibleRect().isEmpty and
        TextView(child).textStorage().len > 100:
      inc result

suite "Kosmo Git diff":
  test "piped Git output becomes static per-file diff sections":
    let snapshot = parseGitDiff(
      "diff --git a/src/main.nim b/src/main.nim\n" & "index 1234567..abcdef0 100644\n" &
        "--- a/src/main.nim\n+++ b/src/main.nim\n" &
        "@@ -1,2 +1,2 @@\n-let value = 1\n+let value = 2\n unchanged\n" &
        "diff --git a/assets/logo.bin b/assets/logo.bin\n" &
        "Binary files a/assets/logo.bin and b/assets/logo.bin differ\n",
      getCurrentDir(),
    )
    check snapshot.source == gdsStandardInput
    check snapshot.rootPath == getCurrentDir()
    check snapshot.errorMessage.len == 0
    require snapshot.files.len == 2
    check snapshot.files[0].path == "src/main.nim"
    check snapshot.files[0].additions == 1
    check snapshot.files[0].deletions == 1
    check snapshot.files[0].syntaxPatch == snapshot.files[0].patch
    check snapshot.files[1].path == "assets/logo.bin"
    check snapshot.files[1].binary

    let malformed = parseGitDiff("not a diff\n", getCurrentDir())
    check malformed.files.len == 0
    check malformed.errorMessage == "Standard input is not a unified Git diff."

  test "summary and expanded files share wheel scrolling":
    let root = createTempDir("kosmo-diff-scroll-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "one.nim", "let value = 1\n".repeat(100))
    writeFile(root / "two.nim", "let other = 2\n")
    let window = newWindow("Git Diff Scrolling", frame = rect(0, 0, 700, 280))
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
      window.close()
    panel.frame = rect(0, 0, 700, 280)
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    require panel.snapshot.errorMessage == ""
    require panel.snapshot.files.len == 2
    panel.layoutSubtreeIfNeeded()
    check not panel.markdownView.scrollView().hasVerticalScroller()
    check panel.markdownView.scrollView().maximumContentOffset().y == 0
    require panel.scrollView.maximumContentOffset().y > 0
    require window.scrollWheelAt(initPoint(100, 150), deltaY = -3)
    check panel.scrollView.contentOffset().y > 0
    check panel.markdownView.scrollView().contentOffset().y == 0
    panel.toggleFile(0)
    require panel.waitForDiff()
    panel.layoutSubtreeIfNeeded()
    let code = panel.textViewForFile(0)
    panel.scrollView.contentOffset = initPoint(0, code.frame().origin.y)
    let before = panel.scrollView.contentOffset().y
    require window.scrollWheelAt(initPoint(100, 150), deltaY = -3)
    check panel.scrollView.contentOffset().y > before
    let after = panel.scrollView.contentOffset().y
    require window.scrollWheelAt(initPoint(100, 150), deltaY = 2)
    check panel.scrollView.contentOffset().y < after
    let momentumStart = panel.scrollView.contentOffset().y
    require window.dispatchScrollWheel(
      ScrollEvent(location: initPoint(100, 150), deltaY: -2, momentumPhase: sepBegan)
    )
    require window.dispatchScrollWheel(
      ScrollEvent(location: initPoint(100, 150), deltaY: -2, momentumPhase: sepChanged)
    )
    discard window.dispatchScrollWheel(
      ScrollEvent(location: initPoint(100, 150), momentumPhase: sepEnded)
    )
    check panel.scrollView.contentOffset().y > momentumStart
    panel.scrollView.contentOffset = initPoint(0, 0)
    require window.scrollWheelAt(initPoint(100, 150), deltaY = -3)
    check panel.scrollView.contentOffset().y > 0
    check panel.markdownView.scrollView().contentOffset().y == 0

  test "repository diffs load patches lazily and keep visible views bounded":
    let root = createTempDir("kosmo-diff-lazy-views-", "")
    defer:
      removeDir(root)
    initRepository(root)
    for index in 0 ..< 80:
      writeFile(root / ("file" & $index & ".txt"), "value " & $index & "\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 600, 400)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    panel.layoutSubtreeIfNeeded()
    require panel.snapshot.files.len == 80
    for file in panel.snapshot.files:
      check file.patchState == gdpsUnloaded
      check file.patch.len == 0
      check file.syntaxPatch.len == 0
    check panel.materializedViewCount() < panel.snapshot.files.len
    panel.toggleFile(0)
    require panel.waitForDiff()
    check panel.snapshot.files[0].patchState == gdpsLoaded
    check panel.snapshot.files[0].patch.len > 0
    panel.toggleFile(0)
    require panel.waitForDiff()
    panel.layoutSubtreeIfNeeded()
    panel.scrollView.contentOffset = panel.scrollView.maximumContentOffset()
    panel.layoutSubtreeIfNeeded()
    check panel.materializedViewCount() < panel.snapshot.files.len

  test "Git diff metadata caps file rows":
    let root = createTempDir("kosmo-diff-file-limit-", "")
    defer:
      removeDir(root)
    initRepository(root)
    for index in 0 ..< 5:
      writeFile(root / ("file" & $index & ".txt"), "value\n")

    let snapshot = readGitDiff(root, fileLimit = 3)
    check snapshot.errorMessage == ""
    check snapshot.files.len == 3
    check snapshot.fileLimitReached
    for file in snapshot.files:
      check file.patchState == gdpsUnloaded
      check file.patch.len == 0

    let panel = newKosmoGitDiffPanel(snapshot)
    defer:
      panel.close()
    check "Only the first listed files are shown." in panel.markdownView.markdown()

  test "expanding many files keeps views bounded and generated diffs unloaded":
    let root = createTempDir("kosmo-diff-expand-limit-", "")
    defer:
      removeDir(root)
    initRepository(root)
    for index in 0 ..< 80:
      writeFile(root / ("normal-" & $index & ".txt"), "value " & $index & "\n")
    createDir(root / "nifcache")
    writeFile(root / "nifcache" / "generated.nim.c", "generated output\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 600, 400)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    require panel.snapshot.files.len == 81

    require panel.expandButton.sendAction()
    panel.layoutSubtreeIfNeeded()
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while panel.materializedViewCount() == 0 and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard drainMainThreadWork()
      panel.layoutSubtreeIfNeeded()
      sleep(1)
    require panel.materializedViewCount() > 0
    check panel.materializedViewCount() <= GitDiffMaterializedSectionLimit * 2
    var foundGenerated = false
    for file in panel.snapshot.files:
      if file.path == "nifcache/generated.nim.c":
        foundGenerated = true
        check file.patchState == gdpsUnloaded
    check foundGenerated

  test "scrolling expanded diffs materializes visible panels":
    let root = createTempDir("kosmo-diff-scroll-lazy-", "")
    defer:
      removeDir(root)
    initRepository(root)
    for index in 0 ..< 48:
      writeFile(root / ("file" & $index & ".txt"), "old line\n".repeat(90))
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    for index in 0 ..< 48:
      writeFile(
        root / ("file" & $index & ".txt"), ("new line " & $index & "\n").repeat(90)
      )

    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 700, 500)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    require panel.expandButton.sendAction()
    require panel.waitForDiff()
    panel.layoutSubtreeIfNeeded()
    discard panel.buildRenders()

    panel.scrollView.contentOffset = panel.scrollView.maximumContentOffset()
    var visibleCount: int
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard drainMainThreadWork()
      panel.layoutSubtreeIfNeeded()
      discard panel.buildRenders()
      visibleCount = panel.visibleLoadedDiffTextViewCount()
      if visibleCount > 0:
        break
      sleep(1)
    require visibleCount > 0

  test "Expand All redraws completed background diff layouts":
    let panel = newKosmoGitDiffPanel(
      parseGitDiff(
        "diff --git a/one.nim b/one.nim\n" & "--- a/one.nim\n+++ b/one.nim\n" &
          "@@ -1 +1 @@\n-let one = 1\n+let one = 2\n" &
          "diff --git a/two.nim b/two.nim\n" & "--- a/two.nim\n+++ b/two.nim\n" &
          "@@ -1 +1 @@\n-let two = 1\n+let two = 2\n"
      )
    )
    defer:
      panel.close()
    panel.frame = rect(0, 0, 700, 600)
    panel.layoutSubtreeIfNeeded()
    require panel.expandButton.sendAction()
    require panel.waitForDiff()

    let textView = panel.textViewForFile(1)
    require panel.waitForDiff()
    let manager = textView.layoutManager()
    panel.layoutSubtreeIfNeeded()
    discard manager.layoutSnapshot()
    panel.layoutSubtreeIfNeeded()
    discard panel.buildRenders()
    let viewportRevision = textView.renderSlotRevision(TextViewportRenderSlot)
    manager.invalidateLayout()
    textView.needsDisplay = false
    manager.requestBackgroundLayout(allowUncachedLayout = true)

    require panel.waitForDiff()
    check textView.renderSlotRevision(TextViewportRenderSlot) > viewportRevision

  test "lazy patch loading uses the canonical repository root":
    let
      root = createTempDir("kosmo-diff-nested-root-", "")
      nested = root / "nested"
      filePath = nested / "source.txt"
    defer:
      removeDir(root)
    createDir(nested)
    initRepository(root)
    writeFile(filePath, "old value\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(filePath, "new value\n")

    let panel = newKosmoGitDiffPanel(nested)
    defer:
      panel.close()
    require panel.waitForDiff()
    require sameFile(panel.snapshot.rootPath, root)
    require panel.snapshot.files.len == 1
    require panel.requestFilePatch(0)
    require panel.waitForDiff()
    check "+new value" in panel.snapshot.files[0].patch

  test "replacing a piped diff refreshes an already materialized section":
    let initial = parseGitDiff(
      "diff --git a/source.nim b/source.nim\n" & "--- a/source.nim\n+++ b/source.nim\n" &
        "@@ -1 +1 @@\n-old value\n+first value\n"
    )
    let updated = parseGitDiff(
      "diff --git a/source.nim b/source.nim\n" & "--- a/source.nim\n+++ b/source.nim\n" &
        "@@ -1 +1 @@\n-old value\n+second value\n"
    )
    let panel = newKosmoGitDiffPanel(initial)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 600, 400)
    panel.layoutSubtreeIfNeeded()
    panel.toggleFile(0)
    require panel.waitForDiff()
    check "+first value" in panel.textViewForFile(0).textStorage().stringValue()

    panel.displayDiff(updated)
    require panel.waitForDiff()
    let rendered = panel.textViewForFile(0).textStorage().stringValue()
    check "+second value" in rendered
    check "+first value" notin rendered

  test "generated diffs require an explicit patch request":
    let root = createTempDir("kosmo-diff-generated-", "")
    defer:
      removeDir(root)
    initRepository(root)
    createDir(root / "nifcache")
    writeFile(root / "nifcache" / "generated.nim.c", "generated output\n")
    let snapshot = readGitDiff(root)
    var generatedIndex = -1
    for index, file in snapshot.files:
      if file.path == "nifcache/generated.nim.c":
        generatedIndex = index
        check file.requiresExplicitLoad
        check file.patchState == gdpsUnloaded
        check file.patch.len == 0
    require generatedIndex >= 0
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    require panel.waitForDiff()
    check panel.snapshot.files[generatedIndex].patchState == gdpsUnloaded
    require panel.requestFilePatch(generatedIndex)
    require panel.waitForDiff()
    check panel.snapshot.files[generatedIndex].patchState == gdpsLoaded
    check "+generated output" in panel.snapshot.files[generatedIndex].patch

  test "repository patch loading enforces per-file and total byte limits":
    let root = createTempDir("kosmo-diff-limits-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "large.txt", "line\n".repeat(100))
    let perFilePanel = newKosmoGitDiffPanel(
      root, patchLimits = initGitDiffPatchLimits(perFileBytes = 64, totalBytes = 4096)
    )
    defer:
      perFilePanel.close()
    require perFilePanel.waitForDiff()
    require perFilePanel.snapshot.files.len == 1
    perFilePanel.toggleFile(0)
    require perFilePanel.waitForDiff()
    check perFilePanel.snapshot.files[0].patchState == gdpsSkipped
    check "per-file limit" in perFilePanel.snapshot.files[0].errorMessage

    let totalPanel = newKosmoGitDiffPanel(
      root, patchLimits = initGitDiffPatchLimits(perFileBytes = 4096, totalBytes = 1)
    )
    defer:
      totalPanel.close()
    require totalPanel.waitForDiff()
    totalPanel.toggleFile(0)
    require totalPanel.waitForDiff()
    check totalPanel.snapshot.files[0].patchState == gdpsSkipped
    check "byte limit" in totalPanel.snapshot.files[0].errorMessage

  test "Git diff header keeps its height while manually refreshing":
    let root = createTempDir("kosmo-diff-header-height-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "source.txt", "old text\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(root / "source.txt", "new text\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 700, 400)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    panel.layoutSubtreeIfNeeded()
    let settledHeight = panel.markdownView.frame().size.height
    let settledMarkdown = panel.markdownView.markdown()
    let settledStorage = panel.markdownView.textView().textStorage()
    let reads = panel.repositoryReadCount()
    panel.refresh()
    require panel.waitForDiff()
    check panel.repositoryReadCount() == reads + 1
    check panel.refreshButton.enabled()
    check panel.markdownView.markdown() == settledMarkdown
    check panel.markdownView.textView().textStorage() == settledStorage
    panel.refresh()
    check panel.refreshButton.enabled()
    check panel.markdownView.markdown() == settledMarkdown
    require panel.waitForDiff()
    check panel.markdownView.textView().textStorage() == settledStorage

    writeFile(root / "source.txt", "refreshed text\n")
    panel.refresh()
    check panel.refreshButton.enabled()
    check panel.markdownView.markdown() == settledMarkdown
    require panel.markdownView.waitForMarkdownParsing()
    require panel.markdownView.waitForMarkdownLayout()
    panel.layoutSubtreeIfNeeded()
    check abs(panel.markdownView.frame().size.height - settledHeight) < 0.01'f32

    require panel.waitForDiff()
    panel.layoutSubtreeIfNeeded()
    check abs(panel.markdownView.frame().size.height - settledHeight) < 0.01'f32

  test "standard hunks retain syntax from omitted full-file context":
    let root = createTempDir("kosmo-diff-hunks-", "")
    defer:
      removeDir(root)
    initRepository(root)
    var original = "#[\n"
    for index in 0 ..< 60:
      original.add "comment line " & $index & "\n"
    original.add "]#\n"
    writeFile(root / "source.nim", original)
    git(root, "add", ".")
    git(root, "commit", "-qm", "base")
    writeFile(
      root / "source.nim",
      original.replace("comment line 20\n", "changed twenty\n").replace(
        "comment line 45\n", "changed forty five\n"
      ),
    )
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 700, 500)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    require panel.snapshot.files.len == 1
    check panel.isFileCollapsed(0)
    check panel.snapshot.files[0].patchState == gdpsUnloaded
    panel.toggleFile(0)
    require panel.waitForDiff()
    let storage = panel.textViewForFile(0).textStorage()
    let shown = storage.stringValue()
    check "comment line 0\n" notin shown
    check " #[\n" notin shown
    check "+changed twenty" in shown
    check "+changed forty five" in shown
    let at = shown[0 ..< shown.find("changed twenty")].runeLen
    check storage.attributesAt(at).foregroundColor ==
      panel.markdownView.markdownStyle().syntaxTokenColors[stcComment]
    panel.toggleFile(0)
    require panel.waitForDiff()
    check panel.textViewForFile(0).layoutManager().snapshotBuildThreadId() !=
      getThreadId()

  test "file sections are retained independently and new files start collapsed":
    let root = createTempDir("kosmo-diff-sections-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "one.nim", "let one = 1\n")
    writeFile(root / "two.nim", "let two = 2\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 700, 500)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    check panel.isFileCollapsed(0)
    check panel.isFileCollapsed(1)
    require panel.requestFilePatch(1)
    require panel.waitForDiff()
    let retainedAdditions = panel.snapshot.files[1].additions
    require retainedAdditions > 0
    discard panel.textViewForFile(1)
    require panel.waitForDiff()
    let retained = panel.textViewForFile(1).textStorage().stringValue()
    panel.toggleFile(0)
    require panel.waitForDiff()
    writeFile(root / "one.nim", "let one = 3\n")
    panel.refresh()
    require panel.waitForDiff()
    check not panel.isFileCollapsed(0)
    check panel.isFileCollapsed(1)
    check panel.snapshot.files[1].additions == retainedAdditions
    discard panel.textViewForFile(1)
    require panel.waitForDiff()
    check panel.textViewForFile(1).textStorage().stringValue() == retained
  test "closing one diff does not stop shared Markdown and highlighting workers":
    let root = createTempDir("kosmo-diff-shared-workers-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "one.nim", "let one = 1\n")
    let closedPanel = newKosmoGitDiffPanel(root)
    closedPanel.close()
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    let markdown = newMarkdownView("```go\nfunc main() {}\n```")
    require panel.waitForDiff()
    require panel.snapshot.files.len == 1
    panel.toggleFile(0)
    require panel.waitForDiff()
    require markdown.waitForMarkdownParsing()
    check panel.highlightBuildCount() == 1
    check panel.highlightThreadId() != getThreadId()
    check markdown.markdownParseWorkerThreadId() != getThreadId()
    check closedPanel.snapshot.files.len == 0

  test "diff highlighting is reused across collapse theme and unchanged refresh":
    let root = createTempDir("kosmo-diff-cache-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "one.nim", "let one = 1\n")
    writeFile(root / "two.nim", "let two = 2\r\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 600, 400)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    let initialCount = panel.highlightBuildCount()
    check initialCount == 0
    check panel.highlightQueuedBytes() == 0
    check panel.highlightCachedBytes() == 0
    check panel.highlightThreadId() == 0
    check panel.highlightThreadId() != getThreadId()
    panel.toggleFile(0)
    require panel.waitForDiff()
    let loadedCount = panel.highlightBuildCount()
    check loadedCount == 1
    check panel.highlightQueuedBytes() == 0
    check panel.highlightCachedBytes() > 0
    check panel.highlightThreadId() != 0
    panel.toggleFile(0)
    require panel.waitForDiff()
    panel.toggleFile(0)
    require panel.waitForDiff()
    check panel.highlightBuildCount() == loadedCount
    var style = panel.markdownView.markdownStyle()
    style.syntaxTokenColors[stcKeyword] = color(0.2, 0.7, 0.3, 1)
    panel.markdownStyle = style
    require panel.waitForDiff()
    check panel.highlightBuildCount() == loadedCount
    panel.refresh()
    require panel.waitForDiff()
    check panel.highlightBuildCount() == loadedCount
    writeFile(root / "one.nim", "let one = 10\n")
    panel.refresh()
    require panel.waitForDiff()
    check panel.highlightBuildCount() == loadedCount + 1

  test "reapplying the current style preserves rendered diff storage":
    let panel = newKosmoGitDiffPanel(
      parseGitDiff(
        "diff --git a/source.nim b/source.nim\n" & "--- a/source.nim\n+++ b/source.nim\n" &
          "@@ -1 +1 @@\n-let value = 1\n+let value = 2\n"
      )
    )
    defer:
      panel.close()
    panel.frame = rect(0, 0, 600, 400)
    panel.layoutSubtreeIfNeeded()
    panel.toggleFile(0)
    require panel.waitForDiff()
    let
      textView = panel.textViewForFile(0)
      storage = textView.textStorage()

    panel.markdownStyle = panel.markdownView.markdownStyle()
    require panel.waitForDiff()

    check textView.textStorage() == storage

  test "closing active highlighting releases request and cache accounting":
    let
      syntaxPatch = "@@ -1,50000 +1,50000 @@\n" & "+let value = 1\n".repeat(50000)
      panel = newKosmoGitDiffPanel(
        GitDiffSnapshot(
          source: gdsStandardInput,
          rootPath: getCurrentDir(),
          files:
            @[
              GitFileDiff(
                path: "active.nim",
                patch: "@@ -1,1 +1,1 @@\n-old\n+new\n",
                syntaxPatch: syntaxPatch,
              )
            ],
        )
      )

    discard panel.textViewForFile(0)
    panel.close()
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while (panel.highlightQueuedBytes() > 0 or panel.highlightCachedBytes() > 0) and
        getMonoTime() < deadline:
      sleep(1)

    check panel.highlightQueuedBytes() == 0
    check panel.highlightCachedBytes() == 0

  test "pending highlighting follows the latest visible patch":
    let
      syntaxPatch = "@@ -1,60000 +1,60000 @@\n" & "+let value = 1\n".repeat(60000)
      first = GitDiffSnapshot(
        source: gdsStandardInput,
        rootPath: getCurrentDir(),
        files:
          @[
            GitFileDiff(
              path: "source.txt",
              patch: "@@ -1,1 +1,1 @@\n-old\n+first\n",
              syntaxPatch: syntaxPatch,
            )
          ],
      )
      latestPatch = "@@ -1,1 +1,1 @@\n-old\n+latest\n"
      latest = GitDiffSnapshot(
        source: gdsStandardInput,
        rootPath: getCurrentDir(),
        files:
          @[
            GitFileDiff(
              path: "source.txt", patch: latestPatch, syntaxPatch: syntaxPatch
            )
          ],
      )
      panel = newKosmoGitDiffPanel(first)
    defer:
      panel.close()

    discard panel.textViewForFile(0)
    panel.displayDiff(latest)
    require panel.waitForDiff()
    check panel.textViewForFile(0).textStorage().stringValue() == latestPatch

  test "oversized diffs keep configured plain code attributes":
    let
      patch = "@@ -1,1 +1,1 @@\n+" & "x".repeat(1_100_000) & "\n"
      panel = newKosmoGitDiffPanel(
        GitDiffSnapshot(
          source: gdsStandardInput,
          rootPath: getCurrentDir(),
          files: @[GitFileDiff(path: "source.txt", patch: patch, syntaxPatch: patch)],
        )
      )
    defer:
      panel.close()
    require panel.waitForDiff()
    let attributes = panel.textViewForFile(0).textStorage().attributesAt(0)
    check attributes.fontName == panel.markdownView.markdownStyle().codeFontName
    check attributes.foregroundColor == panel.markdownView.markdownStyle().codeColor

  test "new Nim files retain syntax highlighting":
    let panel = newKosmoGitDiffPanel(
      parseGitDiff(
        "diff --git a/windows.nim b/windows.nim\n" &
          "new file mode 100644\n--- /dev/null\n+++ b/windows.nim\n" &
          "@@ -0,0 +1,2 @@\n+import os\n+let answer = 42\n"
      )
    )
    defer:
      panel.close()
    require panel.waitForDiff()
    discard panel.textViewForFile(0)
    require panel.waitForDiff()
    check panel.highlightBuildCount() == 1
    let
      storage = panel.textViewForFile(0).textStorage()
      rendered = storage.stringValue()
      location = rendered.find("+import")
    require location >= 0
    let importIndex = rendered[0 ..< location].runeLen + 1
    check storage.attributesAt(importIndex).foregroundColor ==
      panel.markdownView.markdownStyle().syntaxTokenColors[stcKeyword]

  test "repository changes wait for an explicit refresh by default":
    let root = createTempDir("kosmo-diff-manual-refresh-", "")
    defer:
      removeDir(root)
    initRepository(root)
    for index in 0 ..< 8:
      writeFile(root / ("file" & $index & ".nim"), "let value = 0\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "base")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    require panel.waitForDiff()
    let initialReads = panel.repositoryReadCount()
    check initialReads == 1
    check not panel.autoRefreshSwitch.on

    for index in 0 ..< 8:
      writeFile(root / ("file" & $index & ".nim"), "let value = " & $(index + 1) & "\n")
    check panel.repositoryReadCount() == initialReads
    check panel.snapshot.files.len == 0

    panel.refresh()
    require panel.waitForDiff()
    check panel.repositoryReadCount() == initialReads + 1
    check panel.snapshot.files.len == 8

  test "Matter highlights both file versions independently beneath diff tints":
    let root = createTempDir("kosmo-diff-matter-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "source.nim", "let text = \"\"\"\nold café\n\"\"\"\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(root / "source.nim", "let text = 42\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 600, 500)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    panel.toggleFile(0)
    require panel.waitForDiff()
    let
      storage = panel.textViewForFile(0).textStorage()
      text = storage.stringValue()
      style = panel.markdownView.markdownStyle()
    for (needle, token) in [
      ("+let", stcKeyword), ("42", stcNumber), ("old café", stcString)
    ]:
      let location = text.find(needle)
      require location >= 0
      let index = text[0 ..< location].runeLen + (if needle[0] == '+': 1 else: 0)
      check storage.attributesAt(index).foregroundColor == style.syntaxTokenColors[
        token
      ]
      check storage.attributesAt(index).lineBackgroundColor.a > 0

  test "Terraform HCL changes use Matter syntax highlighting":
    let root = createTempDir("kosmo-diff-terraform-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(
      root / "main.hcl", "resource \"aws_instance\" \"web\" {\n  ami = \"ami-old\"\n}\n"
    )
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(
      root / "main.hcl", "resource \"aws_instance\" \"web\" {\n  ami = \"ami-new\"\n}\n"
    )
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    require panel.waitForDiff()
    panel.toggleFile(0)
    require panel.waitForDiff()
    let
      storage = panel.textViewForFile(0).textStorage()
      text = storage.stringValue()
      location = text.find("ami-new")
    require location >= 0
    let index = text[0 ..< location].runeLen
    check storage.attributesAt(index).foregroundColor ==
      panel.markdownView.markdownStyle().syntaxTokenColors[stcString]
    check storage.attributesAt(index).lineBackgroundColor.a > 0

  test "standard hunks include staged unstaged untracked deleted and binary files":
    let root = createTempDir("kosmo-git-diff-", "")
    defer:
      removeDir(root)
    initRepository(root)
    let original = "first line\n" & "context\n".repeat(30) & "old value\nlast line\n"
    writeFile(root / "source.nim", original)
    writeFile(root / "deleted.txt", "deleted content\n")
    writeFile(root / "binary.dat", "\0before")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    git(root, "branch", "-M", "diff-preview")
    writeFile(root / "source.nim", original.replace("old value", "new value"))
    writeFile(root / "staged.txt", "staged content\n")
    git(root, "add", "staged.txt")
    writeFile(root / "new [file].txt", "untracked\n```\n# not a heading\n")
    writeFile(root / "binary.dat", "\0after")
    removeFile(root / "deleted.txt")
    let snapshot = readGitDiff(root)
    check snapshot.errorMessage == ""
    check snapshot.files.len == 5
    check snapshot.branch == "diff-preview"
    for file in snapshot.files:
      check file.patchState == gdpsUnloaded
      check file.patch.len == 0
      check file.syntaxPatch.len == 0
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    require panel.waitForDiff()
    for index in 0 ..< panel.snapshot.files.len:
      require panel.requestFilePatch(index)
    require panel.waitForDiff()
    for file in panel.snapshot.files:
      case file.path
      of "source.nim":
        check file.additions == 1
        check file.deletions == 1
        check " first line" notin file.patch
        check " first line" in file.syntaxPatch
        check " last line" in file.patch
        check "-old value" in file.patch
        check "+new value" in file.patch
      of "deleted.txt":
        check "-deleted content" in file.patch
      of "staged.txt":
        check "+staged content" in file.patch
      of "new [file].txt":
        check file.additions == 3
        check file.deletions == 0
        check "+untracked" in file.patch
      of "binary.dat":
        check file.binary
        check file.additions == 0
        check "Binary files" in file.patch
      else:
        check false

  test "empty clean and non-repository states are explicit":
    let root = createTempDir("kosmo-git-diff-empty-", "")
    defer:
      removeDir(root)
    check readGitDiff(root).errorMessage.len > 0
    initRepository(root)
    check readGitDiff(root).files.len == 0
    writeFile(root / "first.txt", "first commit content\n")
    git(root, "add", ".")
    let initial = readGitDiff(root)
    check initial.errorMessage == ""
    require initial.files.len == 1
    check initial.files[0].patchState == gdpsUnloaded
    check initial.files[0].patch.len == 0
    check initial.branch.len > 0
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    require panel.waitForDiff()
    require panel.requestFilePatch(0)
    require panel.waitForDiff()
    check "+first commit content" in panel.snapshot.files[0].patch
    check panel.snapshot.files[0].additions == 1
    git(root, "commit", "-qm", "Initial")
    let clean = readGitDiff(root)
    check clean.errorMessage == ""
    check clean.files.len == 0
    git(root, "checkout", "--detach", "-q")
    check readGitDiff(root).branch.startsWith("Detached HEAD · ")

  test "native file headings collapse and expand retained highlighted sections":
    let root = createTempDir("kosmo-git-diff-panel-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "source.txt", "old text\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(root / "source.txt", "new text\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 800, 600)
    panel.layoutSubtreeIfNeeded()
    panel.frame = rect(0, 0, 300, 600)
    panel.layoutSubtreeIfNeeded()
    check panel.collapseButton.frame().maxX <= panel.bounds().maxX
    require panel.waitForDiff()
    check panel.snapshot.errorMessage == ""
    require panel.snapshot.files.len == 1
    check panel.isFileCollapsed(0)
    check panel.disclosureButtonForFile(0).rendersDisclosureArrow(expanded = false)
    panel.toggleFile(0)
    require panel.waitForDiff()
    check panel.disclosureButtonForFile(0).rendersDisclosureArrow(expanded = true)
    let rendered = panel.textViewForFile(0).textStorage().stringValue()
    check "-old text" in rendered
    check "+new text" in rendered
    let addedIndex = rendered[0 ..< rendered.find("+new text")].runeLen
    let deletedIndex = rendered[0 ..< rendered.find("-old text")].runeLen
    let addedTint = panel
      .textViewForFile(0)
      .textStorage()
      .attributesAt(addedIndex).lineBackgroundColor
    let deletedTint = panel
      .textViewForFile(0)
      .textStorage()
      .attributesAt(deletedIndex).lineBackgroundColor
    check addedTint.a > 0
    check addedTint.g > addedTint.r
    check deletedTint.a > 0
    check deletedTint.r > deletedTint.g
    check panel.disclosureButtonForFile(0).accessibilityPerformAction(
      AccessibilityActionPress
    )
    require panel.waitForDiff()
    check panel.isFileCollapsed(0)
    check panel.textViewForFile(0).hidden
    let collapsedDisclosure = panel.disclosureButtonForFile(0)
    require not collapsedDisclosure.isNil
    check collapsedDisclosure.accessibilityRole() == arDisclosureButton
    check collapsedDisclosure.accessibilityLabel() == "source.txt"
    check collapsedDisclosure.accessibilityValue() == "collapsed"
    check collapsedDisclosure.accessibilitySupportsAction(AccessibilityActionPress)
    check collapsedDisclosure.accessibilitySupportsAction(AccessibilityActionExpand)
    check collapsedDisclosure.accessibilityPerformAction(AccessibilityActionExpand)
    require panel.waitForDiff()
    check not panel.isFileCollapsed(0)
    check "+new text" in panel.textViewForFile(0).textStorage().stringValue()
    let expandedDisclosure = panel.disclosureButtonForFile(0)
    require not expandedDisclosure.isNil
    check expandedDisclosure.accessibilityValue() == "expanded"
    check expandedDisclosure.accessibilitySupportsAction(AccessibilityActionCollapse)
    check expandedDisclosure.performKeyEquivalentInChain(
      KeyEvent(key: keySpace, keyCode: keySpace.ord)
    )
    require panel.waitForDiff()
    check panel.isFileCollapsed(0)
    let keyboardDisclosure = panel.disclosureButtonForFile(0)
    require not keyboardDisclosure.isNil
    check keyboardDisclosure.performKeyEquivalentInChain(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    require panel.waitForDiff()
    check not panel.isFileCollapsed(0)
    writeFile(root / "source.txt", "refreshed text\n")
    panel.refresh()
    require panel.waitForDiff()
    check "+refreshed text" in panel.snapshot.files[0].patch

  test "File menu exposes the Git diff action":
    let root = createTempDir("kosmo-git-diff-menu-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "menu.txt", "menu diff\n")
    let
      app = newApplication("Kosmo Diff Menu")
      frontend = newKosmoApplication(app, filePath = root, monitorsGitStatus = false)
    defer:
      frontend.close()
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 1000, 700)
    frontend.contentView.layoutSubtreeIfNeeded()
    app.activateWindow(frontend.window)
    let item =
      app.mainMenu()[1].submenu().menuItemWithIdentifier(KosmoShowGitDiffAction)
    require not item.isNil
    check item.title == "Show Git Diff"
    check item.keyEquivalent().key == keyD
    check item.modifierMask() == shortcutModifiers() + {nimkit.kmShift}
    check not item.target.isNil
    check item.perform(frontend.window)
    require not frontend.gitDiffPanel.isNil
    require frontend.gitDiffPanel.waitForDiff()

    check frontend.documentTabs.selectedDocumentTabIdentifier ==
      KosmoGitDiffTabIdentifier
    check frontend.editorPane.contentView == View(frontend.gitDiffPanel)
    check frontend.gitDiffPanel.snapshot.files.len == 1
    let diffTabIndex =
      frontend.documentTabs.indexOfDocumentTabIdentifier(KosmoGitDiffTabIdentifier)
    require diffTabIndex >= 0
    check frontend.documentTabs.documentTabModels()[diffTabIndex].title ==
      "Git Diff · " & root.lastPathPart()
    require frontend.showPipedGitDiff("", root)
    require frontend.gitDiffPanel.waitForDiff()
    check frontend.documentTabs.documentTabModels()[diffTabIndex].title ==
      "Git Diff · stdin"
    require frontend.showGitDiff()
    require frontend.gitDiffPanel.waitForDiff()
    check frontend.documentTabs.documentTabModels()[diffTabIndex].title ==
      "Git Diff · " & root.lastPathPart()
    require frontend.showGitDiff(root / "menu.txt")
    require frontend.gitDiffPanel.waitForDiff()
    check frontend.documentTabs.documentTabModels()[diffTabIndex].title ==
      "Git Diff · menu.txt"
    check frontend.gitDiffPanel.snapshot.scopePath == root / "menu.txt"
    require frontend.showGitDiff()
    require frontend.gitDiffPanel.waitForDiff()
    let
      originalPanel = frontend.gitDiffPanel
      expectedStyle = frontend.editorPane.markdownControls.markdownPresentationStyle()
      actualStyle = originalPanel.markdownView.markdownStyle()
    check actualStyle.backgroundColor == expectedStyle.backgroundColor
    check actualStyle.textColor == expectedStyle.textColor
    check actualStyle.headingFontSizes[1] == expectedStyle.bodyFontSize
    check actualStyle.syntaxTokenColors[stcString] ==
      expectedStyle.syntaxTokenColors[stcString]
    check actualStyle.syntaxTokenColors[stcKeyword] ==
      expectedStyle.syntaxTokenColors[stcKeyword]
    app.setAppearance(initAppearance(initMacOSDarkTheme()))
    let darkStyle = frontend.editorPane.markdownControls.markdownPresentationStyle()
    check originalPanel.markdownView.markdownStyle().backgroundColor ==
      darkStyle.backgroundColor
    check originalPanel.markdownView.markdownStyle().headingFontSizes[1] ==
      darkStyle.bodyFontSize
    check originalPanel.markdownView.markdownStyle().syntaxTokenColors[stcString] ==
      darkStyle.syntaxTokenColors[stcString]
    check item.perform(frontend.window)
    check frontend.gitDiffPanel == originalPanel
    require frontend.gitDiffPanel.waitForDiff()
    let closeItem =
      app.mainMenu()[1].submenu().menuItemWithIdentifier(KosmoCloseTabAction)
    check closeItem.perform(frontend.window)
    check frontend.gitDiffPanel.isNil
    check not frontend.window.isClosed()
    check frontend.window.dispatchKeyDown(
      KeyEvent(
        key: keyD, keyCode: keyD.ord, modifiers: shortcutModifiers() + {nimkit.kmShift}
      )
    )
    require not frontend.gitDiffPanel.isNil
    check frontend.gitDiffPanel != originalPanel
    check frontend.documentTabs.selectedDocumentTabIdentifier ==
      KosmoGitDiffTabIdentifier
    require frontend.gitDiffPanel.waitForDiff()

    let tabIndex =
      frontend.documentTabs.indexOfDocumentTabIdentifier(KosmoGitDiffTabIdentifier)
    require tabIndex >= 0
    let
      tabBounds = frontend.documentTabs.documentTabRect(tabIndex)
      dragStart = frontend.documentTabs.pointToWindow(
        initPoint(tabBounds.minX + 30, tabBounds.minY + 12)
      )
      dragEnd = initPoint(
        frontend.window.frame().size.width + 180,
        frontend.window.frame().size.height + 180,
      )
      detachedPanel = frontend.gitDiffPanel
    require frontend.window.mouseDownAt(dragStart)
    require frontend.window.mouseDraggedAt(dragEnd)
    require frontend.window.mouseUpAt(dragEnd)
    require frontend.detachedEditorWindows().len == 1
    let detachedWindow = frontend.detachedEditorWindows()[0]
    app.activateWindow(frontend.window)
    check item.perform(frontend.window)
    check app.keyWindow() == detachedWindow
    check frontend.gitDiffPanel == detachedPanel
    detachedWindow.close()
    check frontend.gitDiffPanel.isNil
    check frontend.detachedEditorWindows().len == 0
    app.activateWindow(frontend.window)
    check item.perform(frontend.window)
    require not frontend.gitDiffPanel.isNil
    check frontend.gitDiffPanel != detachedPanel
    check frontend.documentTabs.selectedDocumentTabIdentifier ==
      KosmoGitDiffTabIdentifier
    require frontend.gitDiffPanel.waitForDiff()

  test "Git diff tab participates in control-W pane navigation":
    let root = createTempDir("kosmo-git-diff-pane-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "pane.txt", "pane diff\n")
    let
      app = newApplication("Kosmo Diff Pane Navigation")
      frontend = newKosmoApplication(app, filePath = root, monitorsGitStatus = false)
    defer:
      frontend.close()
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    app.activateWindow(frontend.window)
    require frontend.window.makeFirstResponder(frontend.editorView)
    require frontend.window.sendAction(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.editorGroups().len == 2
    require frontend.showGitDiff()
    let groups = frontend.editorGroups()
    var
      diffGroup: KosmoEditorGroup
      otherGroup: KosmoEditorGroup
    for group in groups:
      if group.pane.contentView == View(frontend.gitDiffPanel):
        diffGroup = group
      else:
        otherGroup = group
    require not diffGroup.isNil
    require not otherGroup.isNil
    require frontend.window.makeFirstResponder(
      frontend.gitDiffPanel.markdownView.textView()
    )
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    check frontend.window.firstResponder == otherGroup.editorView

  test "keyboard focus reveals disclosure headings in long diffs":
    let root = createTempDir("kosmo-git-diff-disclosure-focus-", "")
    defer:
      removeDir(root)
    initRepository(root)
    let original = "old value\n" & "context line\n".repeat(160)
    writeFile(root / "aardvark.txt", "unchanged first\n")
    writeFile(root / "first.txt", original)
    writeFile(root / "second.txt", "old second\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(root / "first.txt", original.replace("old value", "new value"))
    writeFile(root / "second.txt", "new second\n")
    let
      window = newWindow("Git Diff Disclosure Focus", frame = rect(0, 0, 600, 280))
      panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
      window.close()
    panel.frame = rect(0, 0, 600, 280)
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    require panel.snapshot.files.len == 2
    panel.toggleFile(0)
    require panel.waitForDiff()
    let
      firstDisclosure = panel.disclosureButtonForFile(0)
      secondDisclosure = panel.disclosureButtonForFile(1)
      textView = panel.markdownView.textView()
    require not firstDisclosure.isNil
    require not secondDisclosure.isNil
    check secondDisclosure
    .frame()
    .intersection(panel.documentView.visibleRect()).isEmpty
    window.recalculateKeyViewLoop()
    require window.makeFirstResponder(firstDisclosure)
    require window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponderIs(secondDisclosure)
    check not secondDisclosure
    .frame()
    .intersection(panel.documentView.visibleRect()).isEmpty
    writeFile(root / "aardvark.txt", "new first\n")
    panel.refresh()
    require panel.waitForDiff()
    check window.firstResponderIs(secondDisclosure)
    require panel.snapshot.files.len == 3
    check panel.snapshot.files[0].path == "aardvark.txt"
    let newFirstDisclosure = panel.disclosureButtonForFile(0)
    require not newFirstDisclosure.isNil
    require window.makeFirstResponder(textView)
    window.recalculateKeyViewLoop()
    require window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponderIs(newFirstDisclosure)

  when defined(posix):
    test "closing interrupts an in-flight Git process":
      let
        root = createTempDir("kosmo-git-diff-cancel-", "")
        marker = root / "started"
        originalPath = getEnv("PATH")
      defer:
        putEnv("PATH", originalPath)
        removeDir(root)
      putEnv("PATH", root & ":" & originalPath)
      for closeOutput in [false, true]:
        if fileExists(marker):
          removeFile(marker)
        writeFile(
          root / "git",
          "#!/bin/sh\nprintf started > " & quoteShell(marker) & "\n" &
            (if closeOutput: "exec 1>&- 2>&-\n" else: "") & "exec /bin/sleep 30\n",
        )
        setFilePermissions(root / "git", {fpUserRead, fpUserWrite, fpUserExec})
        let panel = newKosmoGitDiffPanel(root)
        defer:
          panel.close()
        let deadline = getMonoTime() + initDuration(seconds = 5)
        while not fileExists(marker) and getMonoTime() < deadline:
          sleep(5)
        require fileExists(marker)
        let started = getMonoTime()
        panel.close()
        check (getMonoTime() - started).inMilliseconds < 2000

suite "Kosmo scoped Git diff":
  test "file and folder scopes survive manual refreshes":
    let root = createTempDir("kosmo-scoped-diff-", "")
    defer:
      removeDir(root)
    initRepository(root)
    createDir(root / "folder")
    createDir(root / "folder-other")
    writeFile(root / "folder" / "one.txt", "old\n")
    writeFile(root / "folder-other" / "other.txt", "old\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(root / "folder" / "one.txt", "new\n")
    writeFile(root / "folder-other" / "other.txt", "new\n")
    let panel = newKosmoGitDiffPanel(root, scopePath = root / "folder")
    defer:
      panel.close()
    require panel.waitForDiff()
    check panel.snapshot.scopePath == root / "folder"
    require panel.snapshot.files.len == 1
    check panel.snapshot.files[0].path == "folder/one.txt"
    writeFile(root / "folder" / "untracked.txt", "added\n")
    panel.refresh()
    require panel.waitForDiff()
    check panel.snapshot.files.len == 2
    panel.displayRepositoryDiff(root, root / "folder" / "one.txt")
    require panel.waitForDiff()
    require panel.snapshot.files.len == 1
    removeFile(root / "folder" / "one.txt")
    panel.refresh()
    require panel.waitForDiff()
    require panel.snapshot.files.len == 1
    check panel.snapshot.files[0].path == "folder/one.txt"
    require panel.requestFilePatch(0)
    require panel.waitForDiff()
    check panel.snapshot.files[0].deletions == 1
    panel.displayRepositoryDiff(root)
    require panel.waitForDiff()
    check panel.snapshot.files.len == 3

suite "Kosmo editor repository diff":
  test "diff shortcut finds the nearest repository of the selected editor file":
    let workspace = createTempDir("kosmo-active-repository-", "")
    defer:
      removeDir(workspace)
    let
      first = workspace / "first"
      second = workspace / "second"
      nested = second / "nested"
      linked = workspace / "linked"
    for root in [first, second, nested, linked]:
      createDir(root)
      initRepository(root)
      createDir(root / "src")
      writeFile(root / "src" / "file.txt", "file\n")
      writeFile(root / "sibling.txt", "sibling\n")
    writeFile(second / ".git" / "info" / "exclude", "nested/\n")
    git(linked, "init", "-q", "--separate-git-dir", workspace / "metadata")
    require fileExists(linked / ".git")
    let
      app = newApplication("Active Repository Diff")
      frontend = newKosmoApplication(app, first, monitorsGitStatus = false)
    defer:
      frontend.close()
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    app.activateWindow(frontend.window)
    require frontend.openPath(second)
    for root in [second, first, nested, linked]:
      require frontend.openPath(root / "src" / "file.txt")
      require frontend.window.makeFirstResponder(frontend.editorView)
      require frontend.window.dispatchKeyDown(
        KeyEvent(
          key: keyD,
          keyCode: keyD.ord,
          modifiers: shortcutModifiers() + {nimkit.kmShift},
        )
      )
      require not frontend.gitDiffPanel.isNil
      require frontend.gitDiffPanel.waitForDiff()
      check sameFile(frontend.gitDiffPanel.snapshot.rootPath, root)
      check frontend.gitDiffPanel.snapshot.scopePath.len == 0
      var siblingIncluded = false
      for file in frontend.gitDiffPanel.snapshot.files:
        if file.path == "sibling.txt":
          siblingIncluded = true
      check siblingIncluded
      let index =
        frontend.documentTabs.indexOfDocumentTabIdentifier(KosmoGitDiffTabIdentifier)
      require index >= 0
      check frontend.documentTabs.documentTabModels()[index].title ==
        "Git Diff · " & root.lastPathPart()
