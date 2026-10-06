import std/[json, monotimes, os, strutils, tempfiles, times, unittest]
import sigils/threads
import merenda/nimkit
import merenda/nimkit/app/diagnostics
import merenda/nimkit/foundation/mainthreadwork
import merenda/kosmo/kosmo

proc waitForMarker(path: string): bool =
  let deadline = getMonoTime() + initDuration(seconds = 10)
  while getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    discard drainMainThreadWork()
    if fileExists(path):
      return true
    sleep(1)

suite "GitHub CLI document integration":
  test "project cwd, JSON fields, state, and kind reach gh as separate arguments":
    let root = createTempDir("kosmo-github-project with spaces-", "")
    let hadRepoOverride = existsEnv("GH_REPO")
    let previousRepoOverride = getEnv("GH_REPO")
    defer:
      if hadRepoOverride:
        putEnv("GH_REPO", previousRepoOverride)
      else:
        delEnv("GH_REPO")
      removeDir(root)
    putEnv("GH_REPO", "another/project")
    writeFile(root / "github-test-mode", "success")
    let snapshot = readGitHubSnapshot(
      root, ghsClosed, {ghikPullRequest}, itemLimit = 1, executable = getAppFilename()
    )
    check snapshot.errors[ghikPullRequest] == ""
    check snapshot.items.len == 1
    check snapshot.limitReached == {ghikPullRequest}
    check not fileExists(root / "issue-request.json")
    let request = parseJson(readFile(root / "pr-request.json"))
    check request["root"].getStr() == expandFilename(root)
    check request["promptDisabled"].getStr() == "1"
    check request["repoOverride"].getStr() == ""
    check request["args"][3].getStr() == "closed"
    check request["args"][5].getStr() == "1"
    check "statusCheckRollup" in request["args"][7].getStr()
    require snapshot.items[0].jobs.len == 1
    check snapshot.items[0].jobs[0].state == ghjsRunning

  test "partial failures, bad JSON, missing gh, and authentication errors are snapshots":
    let root = createTempDir("kosmo-github-errors-", "")
    defer:
      removeDir(root)
    writeFile(root / "github-test-mode", "partial")
    let partial = readGitHubSnapshot(root, executable = getAppFilename())
    check partial.items.len == 1
    check partial.items[0].kind == ghikPullRequest
    check partial.errors[ghikIssue] == "Issues are disabled for this repository"
    for mode in ["invalid", "auth", "large"]:
      writeFile(root / "github-test-mode", mode)
      let failed = readGitHubSnapshot(
        root, kinds = {ghikIssue}, executable = getAppFilename(), maxOutputBytes = 4096
      )
      check failed.items.len == 0
      check failed.errors[ghikIssue].len > 0
    let beforeDirectory = getCurrentDir()
    let beforeResources = processResourceUsage()
    let missing =
      readGitHubSnapshot(root, kinds = {ghikIssue}, executable = root / "absent-gh")
    check missing.errors[ghikIssue].len > 0
    check getCurrentDir() == beforeDirectory
    when defined(macosx) or defined(linux):
      check processResourceUsage().fileDescriptors == beforeResources.fileDescriptors

  test "timed out gh commands are terminated and reaped":
    let root = createTempDir("kosmo-github-timeout-", "")
    defer:
      removeDir(root)
    writeFile(root / "github-test-mode", "block")
    let before = processResourceUsage()
    let snapshot = readGitHubSnapshot(
      root,
      kinds = {ghikIssue},
      executable = getAppFilename(),
      timeoutMilliseconds = 200,
    )
    check snapshot.errors[ghikIssue] == "GitHub CLI timed out"
    when defined(macosx) or defined(linux):
      check processResourceUsage().childProcesses == before.childProcesses

  test "filter changes cancel stale reads and closing reaps an active gh":
    let root = createTempDir("kosmo-github-cancel-", "")
    defer:
      removeDir(root)
    writeFile(root / "github-test-mode", "block")
    let panel = newKosmoGitHubPanel(root, executable = getAppFilename())
    defer:
      panel.close()
    require waitForMarker(root / "github-started")
    panel.autoRefreshSwitch.on = true
    panel.scheduleRepositoryRefresh()
    check not panel.pollRepositoryRefresh()
    check readFile(root / "issue-request-count") == "1"
    writeFile(root / "github-test-mode", "success")
    panel.selectFilter(ghsClosed, {ghikPullRequest})
    require panel.waitForGitHub()
    check panel.snapshot.state == ghsClosed
    check panel.snapshot.kinds == {ghikPullRequest}
    require panel.snapshot.items.len == 1
    check panel.snapshot.items[0].title == "pr closed"
    check panel.refreshButton.enabled
    writeFile(root / "github-test-mode", "empty")
    require panel.refreshButton.tryToPerform(
      performClick(), DynamicAgent(panel.refreshButton)
    )
    require panel.waitForGitHub()
    check panel.snapshot.items.len == 0
    removeFile(root / "github-started")
    let before = processResourceUsage()
    writeFile(root / "github-test-mode", "block")
    panel.refresh()
    require waitForMarker(root / "github-started")
    panel.close()
    check panel.closed
    check not panel.loading
    when defined(macosx) or defined(linux):
      check processResourceUsage().childProcesses == before.childProcesses

  test "automatic refresh polls remote job changes and stops when disabled":
    let root = createTempDir("kosmo-github-periodic-", "")
    defer:
      removeDir(root)
    writeFile(root / "github-test-mode", "success")
    let panel = newKosmoGitHubPanel(
      root, executable = getAppFilename(), refreshIntervalMilliseconds = 80
    )
    defer:
      panel.close()
    require panel.waitForGitHub()
    require panel.snapshot.items.len == 2
    require panel.snapshot.items[1].jobs[0].state == ghjsRunning
    check not panel.autoRefreshSwitch.on
    require panel.autoRefreshSwitch.tryToPerform(
      performClick(), DynamicAgent(panel.autoRefreshSwitch)
    )
    check panel.autoRefreshSwitch.on
    writeFile(root / "github-job-state", "SUCCESS")
    let deadline = getMonoTime() + initDuration(seconds = 10)
    while getMonoTime() < deadline and
        panel.snapshot.items[1].jobs[0].state != ghjsPassed:
      discard panel.pollRepositoryRefresh()
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard drainMainThreadWork()
      sleep(1)
    check panel.snapshot.items[1].jobs[0].state == ghjsPassed
    require panel.autoRefreshSwitch.tryToPerform(
      performClick(), DynamicAgent(panel.autoRefreshSwitch)
    )
    require panel.waitForGitHub()
    check "1 passed" in panel.markdownView.markdown()
    let reads = readFile(root / "pr-request-count")
    writeFile(root / "github-job-state", "FAILURE")
    let disabledDeadline = getMonoTime() + initDuration(milliseconds = 200)
    while getMonoTime() < disabledDeadline:
      check not panel.pollRepositoryRefresh()
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard drainMainThreadWork()
      sleep(1)
    check readFile(root / "pr-request-count") == reads
    check panel.snapshot.items[1].jobs[0].state == ghjsPassed
    panel.close()
    check not panel.pollRepositoryRefresh()

  test "workspace refresh notifications coalesce and disabling clears pending work":
    let root = createTempDir("kosmo-github-debounce-", "")
    defer:
      removeDir(root)
    writeFile(root / "github-test-mode", "success")
    let panel = newKosmoGitHubPanel(root, executable = getAppFilename())
    defer:
      panel.close()
    require panel.waitForGitHub()
    let reads = parseInt(readFile(root / "pr-request-count"))
    writeFile(root / "github-job-state", "FAILURE")
    panel.autoRefreshSwitch.on = true
    for index in 0 ..< 8:
      panel.scheduleRepositoryRefresh()
    check not panel.pollRepositoryRefresh()
    require panel.waitForGitHub()
    check parseInt(readFile(root / "pr-request-count")) == reads + 1
    require panel.snapshot.items.len == 2
    check panel.snapshot.items[1].jobs[0].state == ghjsFailed
    panel.scheduleRepositoryRefresh()
    require panel.autoRefreshSwitch.tryToPerform(
      performClick(), DynamicAgent(panel.autoRefreshSwitch)
    )
    check not panel.pollRepositoryRefresh()
    require panel.waitForGitHub()
    check parseInt(readFile(root / "pr-request-count")) == reads + 1

  when defined(posix):
    test "menu opens one reusable project tab and closing releases its worker":
      let root = createTempDir("kosmo-github-menu-", "")
      let previousPath = getEnv("PATH")
      defer:
        putEnv("PATH", previousPath)
        removeDir(root)
      createSymlink(getAppFilename(), root / "gh")
      putEnv("PATH", root & PathSep & previousPath)
      writeFile(root / "github-test-mode", "success")
      let app = newApplication("GitHub menu")
      let frontend =
        newKosmoApplication(app, filePath = root, monitorsGitStatus = false)
      defer:
        frontend.close()
      app.addWindow(frontend.window)
      frontend.window.setContentView(frontend.contentView)
      app.activateWindow(frontend.window)
      let item =
        app.mainMenu()[1].submenu().menuItemWithIdentifier(KosmoShowGitHubAction)
      require not item.isNil
      require item.perform(frontend.window)
      let panel = frontend.gitHubPanel
      require not panel.isNil
      require panel.waitForGitHub()
      check panel.snapshot.rootPath == root
      check panel.snapshot.items.len == 2
      check frontend.documentTabs.selectedDocumentTabIdentifier ==
        KosmoGitHubTabIdentifier
      require frontend.showGitHub(root)
      check frontend.gitHubPanel == panel
      require panel.waitForGitHub()
      require app.performMenuKeyEquivalent(
        KeyEvent(
          key: keyH,
          keyCode: keyH.ord,
          modifiers: shortcutModifiers() + {nimkit.kmShift},
        )
      )
      check frontend.gitHubPanel == panel
      require panel.waitForGitHub()
      require panel.autoRefreshSwitch.tryToPerform(
        performClick(), DynamicAgent(panel.autoRefreshSwitch)
      )
      writeFile(root / "github-job-state", "SUCCESS")
      let automaticDeadline = getMonoTime() + initDuration(seconds = 10)
      while getMonoTime() < automaticDeadline and
          panel.snapshot.items[1].jobs[0].state != ghjsPassed:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        discard drainMainThreadWork()
        sleep(1)
      check panel.snapshot.items[1].jobs[0].state == ghjsPassed
      require panel.autoRefreshSwitch.tryToPerform(
        performClick(), DynamicAgent(panel.autoRefreshSwitch)
      )
      require panel.waitForGitHub()
      app.setAppearance(initAppearance(initMacOSDarkTheme()))
      let expectedStyle =
        frontend.editorPane.markdownControls.markdownPresentationStyle()
      check panel.markdownView.markdownStyle().backgroundColor ==
        expectedStyle.backgroundColor
      check panel.markdownView.markdownStyle().textColor == expectedStyle.textColor
      let closeItem =
        app.mainMenu()[1].submenu().menuItemWithIdentifier(KosmoCloseTabAction)
      require closeItem.perform(frontend.window)
      check panel.closed
      check frontend.gitHubPanel.isNil
