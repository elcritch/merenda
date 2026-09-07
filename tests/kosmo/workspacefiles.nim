import std/[monotimes, os, tempfiles, times, unittest]
import sigils/[core, threads]
import merenda/nimkit
import merenda/nimkit/foundation/gitprocesses
import merenda/kosmo/[kosmo, workspacefiles]

type InventorySpy = ref object of Agent
  changes: int

proc changed(spy: InventorySpy) {.slot.} =
  inc spy.changes

template eventually(condition: untyped) =
  block:
    let deadline = getMonoTime() + initDuration(seconds = 10)
    while not (condition) and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(10)
    check condition

suite "Kosmo shared workspace inventory":
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
    let frontend = newKosmoApplication(
      newApplication("Shared inventory"), root, monitorsGitStatus = false
    )
    defer:
      frontend.close()
    let files = frontend.fileTree.workspaceFiles
    check files == frontend.quickOpenPanel.workspaceFiles
    require files.waitForFiles()
    check "main.nim" in frontend.quickOpenPanel.projectFiles()
    check "build/ignored.nim" notin frontend.quickOpenPanel.projectFiles()
    frontend.fileTree.expandItem(root / "build")
    check frontend.fileTree.rowForItem(root / "build" / "ignored.nim") >= 0
    frontend.fileTree.expandItem(root / ".hidden")
    check frontend.fileTree.rowForItem(root / ".hidden" / "secret.nim") >= 0
    frontend.fileTree.displayMode = FileTreeDisplayMode.VisibleFiles
    check frontend.fileTree.rowForItem(root / "main.nim") >= 0
    check frontend.fileTree.rowForItem(root / ".hidden") < 0
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
    defer:
      first.close()
      second.close()
      removeDir(firstRoot)
      removeDir(secondRoot)
    first.fileTree.workspaceFiles.startMonitoring()
    second.fileTree.workspaceFiles.startMonitoring()
    require first.fileTree.workspaceFiles.waitForFiles()
    require second.fileTree.workspaceFiles.waitForFiles()
    first.close()

    writeFile(secondRoot / "survives.nim", "discard\n")
    eventually("survives.nim" in second.quickOpenPanel.projectFiles())

  when not defined(linux):
    test "idle monitoring does not repeatedly scan the workspace":
      let root = createTempDir("kosmo-idle-inventory-", "")
      defer:
        removeDir(root)
      let frontend = newKosmoApplication(newApplication("Idle inventory"), root)
      defer:
        frontend.close()
      let spy = InventorySpy()
      frontend.fileTree.workspaceFiles.connect(workspaceFilesDidChange, spy, changed)
      require frontend.fileTree.workspaceFiles.waitForFiles()
      # Drain the initial dmon notification and then observe a full old poll period.
      let settle = getMonoTime() + initDuration(seconds = 1)
      while getMonoTime() < settle:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(10)
      let baseline = spy.changes
      let deadline = getMonoTime() + initDuration(milliseconds = 3500)
      while getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(10)
      check spy.changes == baseline
