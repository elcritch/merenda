import
  std/[
    importutils, locks, monotimes, os, sequtils, strutils, tables, tempfiles, times,
    unittest,
  ]
import dmon
import sigils/[core, threads]
import merenda/nimkit
import merenda/nimkit/foundation/gitprocesses
import merenda/kosmo/[kosmo, workspacefiles, workspacewatch, workspacechanges]

privateAccess(WorkspaceFiles)
privateAccess(WorkspaceWatch)

type InventorySpy = ref object of Agent
  changes: int

proc changed(spy: InventorySpy) {.slot.} =
  inc spy.changes

template eventually(condition: untyped) =
  block:
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while not (condition) and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(10)
    check condition

proc pumpFor(milliseconds: int) =
  let deadline = getMonoTime() + initDuration(milliseconds = milliseconds)
  while getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    sleep(10)

suite "Kosmo shared workspace inventory":
  test "repository notifications respect ignore rules and tracked descendants":
    let root = createTempDir("kosmo-ignore-notifications-", "")
    defer:
      removeDir(root)
    require runGitCommand(root, ["init", "-q"]).exitCode == 0
    writeFile(root / ".gitignore", "build/\n*.log\n!keep.log\n")
    createDir(root / "build")
    let ignored = root / "build" / "output.txt"
    writeFile(ignored, "output")
    check not hasRelevantRepositoryChanges([ignored], [root], [])
    check not hasRelevantRepositoryChanges([expandFilename(ignored)], [root], [])
    check not hasRelevantRepositoryChanges([root / "build"], [root], [])
    check hasRelevantRepositoryChanges([root / "build" / ".gitignore"], [root], [])
    check not hasRelevantRepositoryChanges([root / "odd\nname.log"], [root], [])
    check hasRelevantRepositoryChanges([ignored, root / "keep.log"], [root], [])
    check hasRelevantRepositoryChanges([root / "deleted.txt"], [root], [])
    check hasRelevantRepositoryChanges([root / ".gitignore"], [root], [])
    # Both sides of a move must be checked: visible -> ignored and vice versa.
    check hasRelevantRepositoryChanges([root / "source.txt", ignored], [root], [])
    check hasRelevantRepositoryChanges([ignored, root / "source.txt"], [root], [])

    require runGitCommand(root, ["add", "-f", "build/output.txt"]).exitCode == 0
    check hasRelevantRepositoryChanges([ignored], [root], [])
    check hasRelevantRepositoryChanges([root / "build"], [root], [])
    removeFile(ignored)
    check hasRelevantRepositoryChanges([ignored], [root], [])
    check hasRelevantRepositoryChanges([root / "build"], [root], [])

    createDir(root / "nested")
    writeFile(root / "nested" / ".gitignore", "*.tmp\n!keep.tmp\n")
    check not hasRelevantRepositoryChanges([root / "nested" / "out.tmp"], [root], [])
    check hasRelevantRepositoryChanges([root / "nested" / "keep.tmp"], [root], [])
    let metadata = root / "build" / "git-dir"
    check hasRelevantRepositoryChanges([metadata / "HEAD"], [root], [metadata])
    check hasRelevantRepositoryChanges([root.parentDir / "external"], [root], [])

  test "non-Git notification filtering retains ordinary changes":
    let root = createTempDir("kosmo-nongit-notifications-", "")
    defer:
      removeDir(root)
    writeFile(root / ".gitignore", "build/\n")
    check hasRelevantRepositoryChanges([root / "build" / "out.txt"], [root], [])

  test "non-Git discovery limits depth and entries while browsing stays lazy":
    let root = createTempDir("kosmo-bounded-inventory-", "")
    defer:
      removeDir(root)
    writeFile(root / "top.txt", "top")
    var deep = root
    for index in 0 ..< DefaultWorkspaceDepth + 2:
      deep = deep / "nested"
      createDir(deep)
    writeFile(deep / "deep.txt", "deep")
    check "top.txt" in projectFiles(root)
    check relativePath(deep / "deep.txt", root) notin projectFiles(root)
    check relativePath(deep / "deep.txt", root) in
      projectFiles(root, maxDepth = DefaultWorkspaceDepth + 2)
    check projectFiles(root, maxDepth = 0) == @["top.txt"]

    let files = newWorkspaceFiles()
    defer:
      files.close()
    files.reload([root])
    check files.fallback.cachedDirectoryCount() == 0
    check files.entries(deep).len == 1
    check files.entries(deep)[0].path == deep / "deep.txt"
    check files.fallback.cachedDirectoryCount() == 1

    let flat = root / "flat"
    createDir(flat)
    for index in 0 ..< 12:
      writeFile(flat / ($index & ".txt"), "file")
    check projectFiles(flat, maxEntries = 3).len == 3
    # Directories count toward the budget even when they contain no files.
    check projectFiles(root / "nested", maxEntries = 3).len == 0

  test "filesystem roots are shallow and have no native workspace watches":
    var root = getCurrentDir()
    while root.parentDir().len > 0 and root.parentDir() != root:
      root = root.parentDir()
    check root.isFilesystemRoot()
    for path in projectFiles(root, maxEntries = 20):
      check path.extractFilename() == path
    let watch = newWorkspaceWatch()
    defer:
      watch.close()
    watch.setRoots([root], [root])
    check watch.directories.len == 0
    check watch.watches.len == 0
    check not watch.usesPollingFallback()

  test "workspace directory watches are shallow and capped":
    let root = createTempDir("kosmo-bounded-watches-", "")
    defer:
      removeDir(root)
    var folders: seq[string]
    for index in 0 ..< 70:
      let folder = root / $index
      createDir(folder)
      folders.add folder
    let watch = newWorkspaceWatch()
    defer:
      watch.close()
    watch.setRoots([root], folders)
    check watch.directories.len == 64
    check watch.metadata.len == 0
    check watch.watches.len <= 64
    let rootHandle = watch.handles.getOrDefault(root)
    createDir(root / ".git" / "objects" / "pack")
    createDir(root / ".git" / "refs" / "heads" / "feature")
    watch.setRoots([root], folders)
    check root / ".git" in watch.metadata
    check root / ".git" / "refs" / "heads" / "feature" in watch.metadata
    check root / ".git" / "objects" notin watch.directories
    when not defined(linux):
      check uint32(watch.handles[root]) == uint32(rootHandle)

  test "browser and quick open share updates and keep their visibility policies":
    let root = createTempDir("kosmo-shared-inventory-", "")
    defer:
      removeDir(root)
    createDir(root / "build")
    createDir(root / ".hidden")
    writeFile(root / ".gitignore", "build/\n")
    writeFile(root / "main.nim", "discard\n")
    writeFile(root / "build" / "ignored.nim", "discard\n")
    writeFile(root / ".hidden" / "secret.nim", "discard\n")
    require runGitCommand(root, ["init", "-q"]).exitCode == 0
    let frontend = newKosmoApplication(newApplication("Shared inventory"), root)
    defer:
      frontend.close()
    let files = frontend.fileTree.workspaceFiles
    check files == frontend.quickOpenPanel.workspaceFiles
    require files.waitForFiles()
    check "main.nim" in frontend.quickOpenPanel.projectFiles()
    check "build/ignored.nim" notin frontend.quickOpenPanel.projectFiles()
    require frontend.fileTree.waitForGitStatus()
    check frontend.fileTree.displayMode == FileTreeDisplayMode.VisibleFiles
    check frontend.fileTree.rowForItem(root / "build") < 0
    check frontend.fileTree.rowForItem(root / ".hidden") < 0
    frontend.fileTree.displayMode = FileTreeDisplayMode.AllFiles
    frontend.fileTree.expandItem(root / "build")
    check frontend.fileTree.rowForItem(root / "build" / "ignored.nim") >= 0
    frontend.fileTree.expandItem(root / ".hidden")
    check frontend.fileTree.rowForItem(root / ".hidden" / "secret.nim") >= 0
    frontend.fileTree.displayMode = FileTreeDisplayMode.VisibleFiles
    check frontend.fileTree.rowForItem(root / "main.nim") >= 0
    check frontend.fileTree.rowForItem(root / ".hidden") < 0
    check frontend.fileTree.rowForItem(root / "build") < 0
    writeFile(root / "new.nim", "discard\n")
    files.refresh()
    require files.waitForFiles()
    check "new.nim" in frontend.quickOpenPanel.projectFiles()
    check frontend.fileTree.rowForItem(root / "new.nim") >= 0
    check frontend.fileTree.rowForItem(root / ".hidden") < 0
    frontend.fileTree.displayMode = FileTreeDisplayMode.AllFiles
    check frontend.fileTree.rowForItem(root / ".hidden") >= 0
    check frontend.fileTree.rowForItem(root / "build" / "ignored.nim") >= 0

  test "Git refresh hides stale deleted files outside the changed-files scope":
    let
      root = createTempDir("kosmo-stale-browser-listing-", "")
      folder = root / "source"
      deletedFile = folder / "deleted.nim"
    defer:
      removeDir(root)
    createDir(folder)
    writeFile(deletedFile, "discard\n")
    let tree = newKosmoFileTree(root)
    defer:
      tree.workspaceFiles.close()
    require tree.workspaceFiles.waitForFiles()

    removeFile(deletedFile)
    tree.applyGitStatus(
      GitStatusSnapshot(
        rootPath: absolutePath(root),
        isRepository: true,
        entries: @[GitStatusEntry(path: deletedFile, state: gfsDeleted)],
      )
    )
    tree.expandItem(folder)
    check tree.rowForItem(deletedFile) < 0
    tree.displayMode = FileTreeDisplayMode.VisibleFiles
    check tree.rowForItem(deletedFile) < 0
    tree.displayMode = FileTreeDisplayMode.SourceControlChanges
    check tree.rowForItem(deletedFile) >= 0

  test "root replacement rejects queued snapshots and coalesces refreshes":
    let first = createTempDir("kosmo-inventory-first-", "")
    let second = createTempDir("kosmo-inventory-second-", "")
    defer:
      removeDir(first)
      removeDir(second)
    writeFile(first / "old.nim", "discard")
    writeFile(second / "new.nim", "discard")
    let files = newWorkspaceFiles()
    defer:
      files.close()
    let spy = InventorySpy()
    files.connect(workspaceFilesDidChange, spy, changed)
    files.setRoots([first])
    files.setRoots([second])
    for index in 0 ..< 20:
      files.refresh()
    require files.waitForFiles()
    check files.snapshot().roots == @[second]
    check files.snapshot().labels == @["new.nim"]
    check spy.changes == 1
    files.close()
    files.close()
    files.refresh()
    check not files.isLoading()

  test "missed events recover through recurring workspace reconciliation":
    let root = createTempDir("kosmo-periodic-reconciliation-", "")
    defer:
      removeDir(root)
    writeFile(root / "main.nim", "discard\n")
    let files =
      newWorkspaceFiles(reconciliationInterval = initDuration(milliseconds = 500))
    defer:
      files.close()
    let
      inventorySpy = InventorySpy()
      repositorySpy = InventorySpy()
    files.connect(workspaceFilesDidChange, inventorySpy, changed)
    files.connect(workspaceRepositoryDidChange, repositorySpy, changed)
    files.setRoots([root])
    files.startMonitoring()
    require files.waitForFiles()

    # Drain the initial dirty notification, then detach native coverage to model
    # filesystem notifications that never arrive.
    let settle = getMonoTime() + initDuration(milliseconds = 300)
    while getMonoTime() < settle:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(10)
    require files.waitForFiles()
    require not files.watch.isNil
    for id in files.watch.watches:
      unwatch(id)
    files.watch.watches.setLen(0)
    files.watch.fallback = false
    files.watch.markReconciled()

    # A suspend-inclusive wall deadline recovers the first missed change even
    # when little monotonic time has passed, as after waking from sleep.
    files.watch.lastReconciledMonoTime = getMonoTime() + initDuration(seconds = 10)
    files.watch.lastReconciledTime = getTime() - initDuration(seconds = 1)
    let
      firstInventoryBaseline = inventorySpy.changes
      firstRepositoryBaseline = repositorySpy.changes
      firstPath = root / "missed-first.nim"
    writeFile(firstPath, "discard\n")
    let firstDeadline = getMonoTime() + initDuration(seconds = 2)
    while (
      "missed-first.nim" notin files.snapshot().labels or
      repositorySpy.changes == firstRepositoryBaseline
    ) and getMonoTime() < firstDeadline
    :
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(10)
    check "missed-first.nim" in files.snapshot().labels
    check inventorySpy.changes > firstInventoryBaseline
    check repositorySpy.changes > firstRepositoryBaseline
    require files.waitForFiles()

    # Acceptance rearms the latch, allowing a later missed change to recover too.
    let
      secondInventoryBaseline = inventorySpy.changes
      secondRepositoryBaseline = repositorySpy.changes
      secondPath = root / "missed-second.nim"
    writeFile(secondPath, "discard\n")
    let secondDeadline = getMonoTime() + initDuration(seconds = 2)
    while (
      "missed-second.nim" notin files.snapshot().labels or
      repositorySpy.changes == secondRepositoryBaseline
    ) and getMonoTime() < secondDeadline
    :
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(10)
    check "missed-second.nim" in files.snapshot().labels
    check inventorySpy.changes > secondInventoryBaseline
    check repositorySpy.changes > secondRepositoryBaseline

  test "filesystem notifications update both views and Moe without typing":
    let root = createTempDir("kosmo-watched-inventory-", "")
    defer:
      removeDir(root)
    writeFile(root / "main.nim", "discard\n")
    require runGitCommand(root, ["init", "-q"]).exitCode == 0
    require runGitCommand(root, ["add", "."]).exitCode == 0
    require runGitCommand(
      root,
      [
        "-c", "user.name=Kosmo Tests", "-c", "user.email=tests@example.invalid",
        "commit", "-qm", "initial",
      ],
    ).exitCode == 0
    let frontend = newKosmoApplication(newApplication("Watched inventory"), root)
    defer:
      frontend.close()
    require frontend.openPath(root / "main.nim")
    require frontend.fileTree.workspaceFiles.waitForFiles()
    createDir(root / "nested")
    writeFile(root / "nested" / "created.nim", "discard\n")
    eventually("nested/created.nim" in frontend.quickOpenPanel.projectFiles())
    frontend.fileTree.expandItem(root / "nested")
    check frontend.fileTree.rowForItem(root / "nested" / "created.nim") >= 0
    moveFile(root / "nested" / "created.nim", root / "nested" / "renamed.nim")
    eventually(
      "nested/renamed.nim" in frontend.quickOpenPanel.projectFiles() and
        "nested/created.nim" notin frontend.quickOpenPanel.projectFiles()
    )
    require runGitCommand(root, ["checkout", "-qb", "watch-test"]).exitCode == 0
    eventually(frontend.editorView.editor.status().gitBranch == "watch-test")
    removeFile(root / "nested" / "renamed.nim")
    eventually("nested/renamed.nim" notin frontend.quickOpenPanel.projectFiles())

  test "linked worktree metadata changes refresh Moe status":
    let
      repository = createTempDir("kosmo-worktree-repository-", "")
      linked = createTempDir("kosmo-linked-parent-", "") / "checkout"
    defer:
      removeDir(linked.parentDir())
      removeDir(repository)
    writeFile(repository / "main.nim", "discard\n")
    require runGitCommand(repository, ["init", "-q"]).exitCode == 0
    require runGitCommand(repository, ["add", "."]).exitCode == 0
    require runGitCommand(
      repository,
      [
        "-c", "user.name=Kosmo Tests", "-c", "user.email=tests@example.invalid",
        "commit", "-qm", "initial",
      ],
    ).exitCode == 0
    require runGitCommand(
      repository, ["worktree", "add", "-qb", "linked-start", linked]
    ).exitCode == 0
    let frontend = newKosmoApplication(newApplication("Linked worktree"), linked)
    defer:
      frontend.close()
    require frontend.openPath(linked / "main.nim")
    require frontend.fileTree.workspaceFiles.waitForFiles()
    eventually(frontend.editorView.editor.status().gitBranch == "linked-start")

    require runGitCommand(linked, ["checkout", "-qb", "linked-next"]).exitCode == 0
    eventually(frontend.editorView.editor.status().gitBranch == "linked-next")

  test "an open buffer outside project roots keeps its Git metadata watched":
    let
      projectRoot = createTempDir("kosmo-project-root-", "")
      externalRoot = createTempDir("kosmo-external-buffer-", "")
    defer:
      removeDir(projectRoot)
      removeDir(externalRoot)
    writeFile(externalRoot / "external.nim", "discard\n")
    require runGitCommand(externalRoot, ["init", "-q"]).exitCode == 0
    require runGitCommand(externalRoot, ["add", "."]).exitCode == 0
    require runGitCommand(
      externalRoot,
      [
        "-c", "user.name=Kosmo Tests", "-c", "user.email=tests@example.invalid",
        "commit", "-qm", "initial",
      ],
    ).exitCode == 0
    require runGitCommand(externalRoot, ["checkout", "-qb", "external-start"]).exitCode ==
      0
    let frontend = newKosmoApplication(newApplication("External buffer"), projectRoot)
    defer:
      frontend.close()
    require frontend.openPath(externalRoot / "external.nim")
    eventually(frontend.editorView.editor.status().gitBranch == "external-start")
    eventually(externalRoot in frontend.fileTree.workspaceFiles.gitRoots)

    # The root list is published before the watcher backend finishes registering
    # every Git metadata directory. Native backends need all handles before
    # changing HEAD; Linux intentionally uses the polling fallback instead.
    # Drain the initial dirty pulse so the checkout event cannot be coalesced
    # with watcher setup.
    eventually(
      not frontend.fileTree.workspaceFiles.watch.isNil and
        externalRoot in frontend.fileTree.workspaceFiles.watch.directories and
        externalRoot / ".git" in frontend.fileTree.workspaceFiles.watch.metadata and (
        frontend.fileTree.workspaceFiles.watch.fallback or
        frontend.fileTree.workspaceFiles.watch.handles.len ==
        frontend.fileTree.workspaceFiles.watch.directories.len
      )
    )
    pumpFor(500)

    require runGitCommand(externalRoot, ["checkout", "-qb", "external-next"]).exitCode ==
      0
    eventually(frontend.editorView.editor.status().gitBranch == "external-next")

  test "closing one project leaves another workspace watcher active":
    let
      firstRoot = createTempDir("kosmo-first-window-watch-", "")
      secondRoot = createTempDir("kosmo-second-window-watch-", "")
      manager = newKosmoWindowManager(newApplication("Multiple watchers"))
      first = newKosmoApplication(manager, firstRoot, monitorsGitStatus = false)
      second = newKosmoApplication(manager, secondRoot, monitorsGitStatus = false)
      secondFiles = second.fileTree.workspaceFiles
      spy = InventorySpy()
    defer:
      first.close()
      second.close()
      removeDir(firstRoot)
      removeDir(secondRoot)
    first.fileTree.workspaceFiles.startMonitoring()
    secondFiles.connect(workspaceFilesDidChange, spy, changed)
    secondFiles.startMonitoring()
    require first.fileTree.workspaceFiles.waitForFiles()
    require secondFiles.waitForFiles()
    require not secondFiles.watch.isNil
    require secondRoot in secondFiles.watch.directories
    let secondWatch = secondFiles.watch
    first.close()
    check secondFiles.watch == secondWatch
    check secondWatch.active
    check secondRoot in secondWatch.directories

    writeFile(secondRoot / "survives.nim", "discard\n")
    when defined(linux):
      require secondWatch.fallback
    else:
      eventually(secondWatch.nativeReady)
      require secondWatch.nativeReady
      require not secondWatch.fallback
    eventually("survives.nim" in second.quickOpenPanel.projectFiles())
    require "survives.nim" in second.quickOpenPanel.projectFiles()
    require secondFiles.waitForFiles()

    # The setup refresh above closes the registration gap. A second change now
    # has to arrive through the surviving native watch (or Linux fallback), not
    # through that deferred refresh or the two-minute reconciliation deadline.
    let
      nativePath = secondRoot / "after-ready.nim"
      changesBeforeNativeEvent = spy.changes
    writeFile(nativePath, "discard\n")
    eventually(
      "after-ready.nim" in second.quickOpenPanel.projectFiles() and
        spy.changes > changesBeforeNativeEvent
    )
    require secondFiles.waitForFiles()
    let changesBeforeDelete = spy.changes
    removeFile(nativePath)
    eventually(
      "after-ready.nim" notin second.quickOpenPanel.projectFiles() and
        spy.changes > changesBeforeDelete
    )
    when not defined(linux):
      require not secondWatch.fallback

  when defined(macosx):
    test "failed FSEvents startup activates polling fallback":
      let root = createTempDir("kosmo-failed-native-watch-", "")
      defer:
        removeDir(root)
      let watch = newWorkspaceWatch()
      defer:
        watch.close()
      watch.setRoots([root])
      eventually(watch.nativeReady)
      require watch.nativeReady
      require watch.watches.len == 1

      withLock dmonInst.threadLock:
        let index = int(uint32(watch.watches[0])) - 1
        require index >= 0
        require index < dmonInst.watches.len
        require not dmonInst.watches[index].isNil
        dmonInst.watches[index].started = false
      watch.nativeReady = false

      eventually(watch.usesPollingFallback())
      require watch.usesPollingFallback()

  when not defined(linux):
    test "repository changes refresh Git diff only when the toolbar switch is on":
      let root = createTempDir("kosmo-diff-read-watch-", "")
      defer:
        removeDir(root)
      require runGitCommand(root, ["init", "-q"]).exitCode == 0
      let path = root / "source.txt"
      writeFile(path, "startup text\n")
      writeFile(root / ".gitignore", "build/\n")
      createDir(root / "build")
      let ignored = root / "build" / "output.txt"
      writeFile(ignored, "initial\n")
      let frontend = newKosmoApplication(newApplication("Diff read watch"), root)
      defer:
        frontend.close()
      let files = frontend.fileTree.workspaceFiles
      require files.waitForFiles()
      require not files.watch.isNil
      eventually(files.watch.nativeReady)
      require files.watch.nativeReady
      require not files.watch.usesPollingFallback()
      # This test measures native notifications, not periodic reconciliation.
      files.watch.reconciliationInterval = initDuration(seconds = 0)
      require frontend.showGitDiff()
      let panel = frontend.gitDiffPanel
      require panel.waitForDiff(timeoutMilliseconds = 60_000)
      check not panel.autoRefreshSwitch.on
      let repositorySpy = InventorySpy()
      files.connect(workspaceRepositoryDidChange, repositorySpy, changed)

      # Prove the complete native notification path is ready before asserting
      # that the Git diff remains unchanged.
      writeFile(path, "original text\n")
      eventually(repositorySpy.changes > 0)

      let
        baseline = panel.repositoryReadCount()
        quietDeadline = getMonoTime() + initDuration(milliseconds = 1000)
      let settleDeadline = getMonoTime() + initDuration(seconds = 60)
      while getMonoTime() < quietDeadline and getMonoTime() < settleDeadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(10)
      require getMonoTime() >= quietDeadline
      check panel.repositoryReadCount() == baseline
      check panel.snapshot.files.anyIt(
        it.path == "source.txt" and "+startup text" in it.patch
      )

      let readDeadline = getMonoTime() + initDuration(milliseconds = 3500)
      while getMonoTime() < readDeadline:
        check readFile(path) == "original text\n"
        discard getFileInfo(path)
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(10)
      check panel.repositoryReadCount() == baseline

      let ignoredSpy = InventorySpy()
      files.watch.connect(workspaceWatchIgnoredChange, ignoredSpy, changed)
      require files.entries(root / "build").len == 1
      writeFile(ignored, "rebuilt\n")
      writeFile(root / "build" / "new.txt", "new output\n")
      eventually(ignoredSpy.changes > 0)
      require ignoredSpy.changes > 0
      eventually(files.entries(root / "build").len == 2)
      # Let the owning loop process several native event/debounce periods.
      # A quiet observation window is intentional: any refresh is a failure.
      let ignoredDeadline = getMonoTime() + initDuration(milliseconds = 3500)
      while getMonoTime() < ignoredDeadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(10)
      check panel.repositoryReadCount() == baseline

      check panel.autoRefreshSwitch.tryToPerform(
        performClick(), DynamicAgent(panel.autoRefreshSwitch)
      )
      check panel.autoRefreshSwitch.on
      let notificationBaseline = repositorySpy.changes
      writeFile(path, "changed text\n")
      eventually(repositorySpy.changes > notificationBaseline)
      require panel.waitForDiff(timeoutMilliseconds = 60_000)
      check panel.repositoryReadCount() == baseline + 1
      check panel.snapshot.files.anyIt(
        it.path == "source.txt" and "+changed text" in it.patch
      )
      check not panel.snapshot.files.anyIt(it.path.startsWith("build/"))

    test "idle monitoring does not repeatedly scan the workspace":
      let root = createTempDir("kosmo-idle-inventory-", "")
      defer:
        removeDir(root)
      let frontend = newKosmoApplication(newApplication("Idle inventory"), root)
      defer:
        frontend.close()
      let
        spy = InventorySpy()
        files = frontend.fileTree.workspaceFiles
      files.connect(workspaceFilesDidChange, spy, changed)
      require files.waitForFiles()
      require not files.watch.isNil
      eventually(files.watch.nativeReady)
      require files.watch.nativeReady

      # Wait for the startup notification and its scan to become observably
      # quiet before measuring a full old polling period.
      var
        observedChanges = spy.changes
        quietDeadline = getMonoTime() + initDuration(milliseconds = 500)
      let settleDeadline = getMonoTime() + initDuration(seconds = 10)
      while getMonoTime() < quietDeadline and getMonoTime() < settleDeadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        if files.isLoading() or spy.changes != observedChanges:
          observedChanges = spy.changes
          quietDeadline = getMonoTime() + initDuration(milliseconds = 500)
        sleep(10)
      require not files.isLoading()
      require getMonoTime() >= quietDeadline
      let baseline = spy.changes
      let deadline = getMonoTime() + initDuration(milliseconds = 3500)
      while getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(10)
      check spy.changes == baseline
