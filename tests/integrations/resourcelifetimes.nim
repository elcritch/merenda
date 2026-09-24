## Repeated workspace and terminal lifetimes, including worker and native handles.
import std/[monotimes, os, strutils, tempfiles, times, unittest]
import sigils/[core, threads]
import merenda/nimkit
import merenda/nimkit/app/diagnostics
import merenda/nimkit/foundation/gitprocesses
import merenda/kosmo/kosmo
import merenda/kosmo/workspacefiles

proc exerciseWorkspace(app: Application, root: string) =
  let manager = newKosmoWindowManager(app)
  defer:
    manager.close()
  let first = newKosmoApplication(manager, filePath = root)
  let second = newKosmoApplication(manager, filePath = root)
  first.show()
  second.show()
  discard app.runForFrames(1)
  for index in 0 ..< 5:
    let frontend = if index mod 2 == 0: first else: second
    doAssert frontend.openTerminal(
      initTerminalSpawnOptions(
        command = "printf 'terminal-ready\\n'; IFS= read -r value",
        workingDirectory = root,
      )
    )
    let session = KosmoTerminalView(frontend.editorPane.contentView).session()
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while "terminal-ready" notin session.screen().plainText() and
        getMonoTime() < deadline:
      discard session.poll()
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(1)
    doAssert "terminal-ready" in session.screen().plainText()
  when defined(macosx) or defined(linux):
    doAssert processResourceUsage().childProcesses >= 5
  for _ in 0 ..< 8:
    doAssert runGitCommand(root, ["status", "--porcelain"]).exitCode == 0
  let preview = newMarkdownView("# Lifecycle\n\n**Text** and `code`.")
  doAssert preview.waitForMarkdownParsing()
  doAssert preview.waitForMarkdownLayout()
  discard preview.buildRenders()
  first.fileTree.workspaceFiles.refresh()
  second.fileTree.workspaceFiles.refresh()
  doAssert first.fileTree.workspaceFiles.waitForFiles()
  doAssert second.fileTree.workspaceFiles.waitForFiles()

proc settledUsage(
    app: Application, baseline: ProcessResourceUsage
): ProcessResourceUsage =
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while true:
    discard app.runForFrames(1)
    discard getCurrentSigilThread().pollAll(NonBlocking)
    result = processResourceUsage()
    if result.childProcesses <= baseline.childProcesses and
        result.fileDescriptors <= baseline.fileDescriptors + 2:
      return
    if getMonoTime() >= deadline:
      return
    sleep(5)

suite "Workspace resource lifetimes":
  when defined(macosx) or defined(linux):
    test "repeated two-window five-terminal sessions release process resources":
      let root = createTempDir("merenda-resource-lifetimes-", "")
      defer:
        removeDir(root)
      require runGitCommand(root, ["init", "-q"]).exitCode == 0
      writeFile(root / "example.md", "# Example\n")
      let app = newApplication("Resource lifetime test")
      # Warm native font, watcher, renderer, and shared-worker infrastructure.
      exerciseWorkspace(app, root)
      discard getCurrentSigilThread().pollAll(NonBlocking)
      let baseline = processResourceUsage()
      require baseline.fileDescriptors >= 0
      require baseline.childProcesses >= 0
      require baseline.threads > 0
      let deadline = getMonoTime() + initDuration(seconds = 60)
      for _ in 0 ..< 6:
        require getMonoTime() < deadline
        exerciseWorkspace(app, root)
        let current = settledUsage(app, baseline)
        checkpoint "baseline: " & $baseline & "; after close: " & $current
        require current.childProcesses >= 0
        require current.fileDescriptors >= 0
        require current.threads > 0
        check current.childProcesses <= baseline.childProcesses
        check current.fileDescriptors <= baseline.fileDescriptors + 2
        # Native drivers create housekeeping threads lazily; record their count
        # rather than treating it as an owned-worker count.
