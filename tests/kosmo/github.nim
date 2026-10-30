import std/[json, strutils, times, unicode, unittest]
import figdraw
import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

const
  issueJson = """
[{"number":7,"title":"Fix **wrapping** [λ]","body":"A **needle** and `code`.\n\n```nim\nlet x = 1\n```","url":"https://github.com/owner/project/issues/7","state":"OPEN","author":{"login":"alice"},"labels":[{"name":"bug"}],"updatedAt":"2026-10-06T12:00:00Z"}]
"""
  prJson = """
[{"number":8,"title":"Improve rendering","body":"Another needle.","url":"https://github.com/owner/project/pull/8","state":"OPEN","author":null,"labels":[],"isDraft":true,"headRefName":"feature/viewer","baseRefName":"main","reviewDecision":"REVIEW_REQUIRED","statusCheckRollup":[{"__typename":"CheckRun","name":"tests | macOS","workflowName":"Build **CI**","status":"IN_PROGRESS","conclusion":"","detailsUrl":"https://github.com/owner/project/actions/runs/12/job/34"}]}]
"""

proc sampleSnapshot(): GitHubSnapshot =
  result = GitHubSnapshot(rootPath: "/projects/project")
  result.items.add parseGitHubItems(issueJson, ghikIssue)
  result.items.add parseGitHubItems(prJson, ghikPullRequest)

proc headingStartingWith(panel: KosmoGitHubPanel, prefix: string): View =
  for child in panel.markdownView.textView().subviews():
    if child.accessibilityRole() == arDisclosureButton and
        child.accessibilityLabel().startsWith(prefix):
      return child

suite "Kosmo GitHub Markdown viewer":
  test "PR diff links dispatch snapshot metadata separately from browser links":
    let panel = newKosmoGitHubPanel(sampleSnapshot())
    defer:
      panel.close()
    require panel.waitForGitHub()
    panel.markdownView.expandMarkdownHeadings()
    require panel.waitForGitHub()
    var openedRoot: string
    var openedItem: GitHubItem
    var browserCalls: int
    panel.diffHandler = proc(rootPath: string, item: GitHubItem): bool =
      openedRoot = rootPath
      openedItem = item
      true
    panel.linkHandler = proc(link: string): bool =
      inc browserCalls
      true
    let rendered = panel.markdownView.textStorage().stringValue()
    let offset = rendered.find("Open diff in Kosmo")
    require offset >= 0
    require panel.markdownView.textView().openLinkAtIndex(
      rendered[0 ..< offset].runeLen
    )
    check openedRoot == "/projects/project"
    check openedItem.number == 8
    check openedItem.baseBranch == "main"
    check openedItem.headBranch == "feature/viewer"
    check openedItem.pullRequestRepository() == "https://github.com/owner/project.git"
    check browserCalls == 0
    check sampleSnapshot().items[0].pullRequestRepository() == ""

  test "refresh uses the Git diff icon at the toolbar's right edge across themes":
    let
      panel = newKosmoGitHubPanel(sampleSnapshot())
      diff = newKosmoGitDiffPanel(parseGitDiff(""))
    defer:
      panel.close()
      diff.close()
    require panel.waitForGitHub()
    require diff.waitForDiff()
    check panel.refreshButton.icon.size == diff.refreshButton.icon.size
    require panel.refreshButton.icon.layers.len == diff.refreshButton.icon.layers.len
    for index, layer in panel.refreshButton.icon.layers:
      let diffLayer = diff.refreshButton.icon.layers[index]
      require layer.kind == diffLayer.kind
      if layer.kind in {slkMtsdfFill, slkMtsdfStroke}:
        check layer.image == diffLayer.image
    check panel.refreshButton.icon.len > 0
    check panel.refreshButton.accessibilityLabel() == "Refresh GitHub"
    for theme in [initAquaTheme(), initPunchTheme()]:
      panel.appearance = initAppearance(theme)
      for width in [1000.0'f32, 600.0'f32, 300.0'f32]:
        panel.frame = rect(0, 0, width, 500)
        panel.layoutSubtreeIfNeeded()
        panel.refreshButton.checkVisibleIn(panel)
        panel.kindButton.checkVisibleIn(panel)
        panel.stateButton.checkVisibleIn(panel)
        panel.autoRefreshSwitch.checkVisibleIn(panel)
        check panel.kindButton.frame().minX == 12
        check panel.kindButton.frame().maxX < panel.stateButton.frame().minX
        check panel.stateButton.frame().maxX < panel.autoRefreshSwitch.frame().minX
        check panel.autoRefreshSwitch.frame().maxX < panel.refreshButton.frame().minX
        check abs(panel.refreshButton.frame().maxX - (width - 12)) <= 0.01'f32
        var icons: int
        for node in buildRenders(panel.refreshButton)[DefaultDrawLevel].nodes:
          if node.kind == nkMtsdfImage:
            inc icons
            check node.screenBox.w > 0
            check node.screenBox.h > 0
          check node.kind != nkText
        check icons > 0

  test "lists start expanded and item choices survive filtering and new arrivals":
    let panel = newKosmoGitHubPanel(sampleSnapshot())
    defer:
      panel.close()
    panel.frame = rect(0, 0, 800, 600)
    require panel.waitForGitHub()
    let initialText = panel.markdownView.textStorage().stringValue()
    check "Fix" in initialText
    check "Improve rendering" in initialText
    check "needle" notin initialText
    check panel.headingStartingWith("Issues (").accessibilityValue() == "expanded"
    check panel.headingStartingWith("Pull Requests (").accessibilityValue() == "expanded"
    check panel.headingStartingWith("#7 ").accessibilityValue() == "collapsed"
    check panel.headingStartingWith("#8 ").accessibilityValue() == "collapsed"
    require panel.headingStartingWith("#7 ").accessibilityPerformAction(
      AccessibilityActionExpand
    )
    require panel.waitForGitHub()
    check "needle" in panel.markdownView.textStorage().stringValue()

    panel.selectFilter(ghsOpen, {ghikPullRequest})
    require panel.waitForGitHub()
    panel.selectFilter(ghsOpen, {ghikIssue, ghikPullRequest})
    require panel.waitForGitHub()
    check panel.headingStartingWith("#7 ").accessibilityValue() == "expanded"
    check panel.headingStartingWith("#8 ").accessibilityValue() == "collapsed"

    panel.snapshot.items[0].title = "Renamed issue"
    var newIssue = panel.snapshot.items[0]
    newIssue.number = 9
    newIssue.title = "New issue"
    panel.snapshot.items.insert(newIssue, 0)
    panel.selectFilter(ghsOpen, {ghikIssue, ghikPullRequest})
    require panel.waitForGitHub()
    check panel.headingStartingWith("#7 Renamed").accessibilityValue() == "expanded"
    check panel.headingStartingWith("#9 New").accessibilityValue() == "collapsed"
    check panel.headingStartingWith("#8 ").accessibilityValue() == "collapsed"
    require panel.headingStartingWith("Issues (").accessibilityPerformAction(
      AccessibilityActionCollapse
    )
    require panel.waitForGitHub()
    panel.selectFilter(ghsAll, {ghikIssue, ghikPullRequest})
    require panel.waitForGitHub()
    check panel.headingStartingWith("Issues (").accessibilityValue() == "collapsed"

  test "gh JSON preserves issue bodies and PR metadata":
    let snapshot = sampleSnapshot()
    check snapshot.items.len == 2
    check snapshot.items[0].number == 7
    check snapshot.items[0].labels == @["bug"]
    check snapshot.items[0].author == "alice"
    check "```nim" in snapshot.items[0].body
    check snapshot.items[1].kind == ghikPullRequest
    check snapshot.items[1].draft
    check snapshot.items[1].author == ""
    check snapshot.items[1].headBranch == "feature/viewer"
    check snapshot.items[1].reviewDecision == "REVIEW_REQUIRED"
    require snapshot.items[1].jobs.len == 1
    check snapshot.items[1].jobs[0].state == ghjsRunning
    check snapshot.items[1].jobs[0].workflow == "Build **CI**"

  test "check runs and legacy statuses preserve completed, pending, and unknown states":
    var source = parseJson(prJson)
    source[0]["statusCheckRollup"] = %*[
      {"__typename": "CheckRun", "status": "QUEUED"},
      {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS"},
      {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "TIMED_OUT"},
      {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "CANCELLED"},
      {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SKIPPED"},
      {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "NEUTRAL"},
      {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "FUTURE_STATE"},
      {
        "__typename": "StatusContext",
        "context": "external CI",
        "state": "ERROR",
        "targetUrl": "https://ci.example/job",
      },
      {"__typename": "StatusContext", "context": "deployment", "state": "PENDING"},
      {"__typename": "StatusContext", "context": "lint", "state": "SUCCESS"},
      {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "STALE"},
    ]
    let jobs = parseGitHubItems($source, ghikPullRequest)[0].jobs
    require jobs.len == 11
    for index, state in [
      ghjsPending, ghjsPassed, ghjsFailed, ghjsCancelled, ghjsSkipped, ghjsNeutral,
      ghjsUnknown, ghjsFailed, ghjsPending, ghjsPassed, ghjsStale,
    ]:
      check jobs[index].state == state
    check jobs[7].name == "external CI"
    check jobs[7].url == "https://ci.example/job"
    for invalid in [parseJson("42"), parseJson("[null]")]:
      source[0]["statusCheckRollup"] = invalid
      expect ValueError:
        discard parseGitHubItems($source, ghikPullRequest)
    source[0]["statusCheckRollup"] = newJNull()
    check parseGitHubItems($source, ghikPullRequest)[0].jobs.len == 0

  test "PR job tables show escaped names, workflow, status, and safe details links":
    var snapshot = sampleSnapshot()
    let markdown = snapshot.gitHubMarkdown()
    check "Jobs: **1 running**" in markdown
    check "tests \\| macOS" in markdown
    check "Build \\*\\*CI\\*\\*" in markdown
    check "https://github.com/owner/project/actions/runs/12/job/34" in markdown
    check "| Running |" in markdown
    snapshot.items[1].jobs[0].url = "https://ci.example/job?jobs=build|test"
    check "https://ci.example/job?jobs=build%7Ctest" in snapshot.gitHubMarkdown()
    snapshot.items[1].jobs[0].url = "javascript:alert(1)"
    check "javascript:" notin snapshot.gitHubMarkdown()
    snapshot.items[1].jobs.setLen(0)
    check "Jobs: No checks reported." in snapshot.gitHubMarkdown()

  test "invalid JSON shapes fail as catchable errors":
    for source in ["null", "{}", "[null]", "[{\"number\":0}]", "not JSON"]:
      expect CatchableError:
        discard parseGitHubItems(source, ghikIssue)
    var item = parseJson(issueJson)
    item[0]["title"] = %42
    expect ValueError:
      discard parseGitHubItems($item, ghikIssue)
    item = parseJson(issueJson)
    item[0]["number"] = %"7"
    expect ValueError:
      discard parseGitHubItems($item, ghikIssue)

  test "Markdown quotes descriptions and escapes metadata while preserving links":
    var snapshot = sampleSnapshot()
    snapshot.items[0].body = "```\nunterminated fence"
    let markdown = snapshot.gitHubMarkdown()
    check "Issues (1)" in markdown
    check "Pull Requests (1)" in markdown
    check "Fix \\*\\*wrapping\\*\\* \\[λ\\]" in markdown
    check "> ```\n> unterminated fence\n\n## Pull Requests" in markdown
    check "https://github.com/owner/project/issues/7" in markdown
    check "### \\#7 Fix \\*\\*wrapping\\*\\* \\[λ\\]\n\n[Open issue #7 on GitHub]" in
      markdown
    check "### \\#8 Improve rendering\n\n[Open PR #8 on GitHub]" in markdown
    check "Draft" in markdown
    check "feature/viewer → main" in markdown
    snapshot.items[0].url = "javascript:alert(1)"
    check "javascript:" notin snapshot.gitHubMarkdown()

  test "section identities use kind and number independently of titles and order":
    var snapshot = sampleSnapshot()
    check snapshot.gitHubHeadingIdentifiers() ==
      @[
        "github-project", "github-issues", "github-issues-7", "github-pull-requests",
        "github-pull-requests-8",
      ]
    snapshot.items[1].title = "Renamed pull request"
    snapshot.items[1].body = "# Heading inside a quoted description"
    var another = snapshot.items[1]
    another.number = 7
    snapshot.items.insert(another, 0)
    check snapshot.gitHubHeadingIdentifiers() ==
      @[
        "github-project", "github-issues", "github-issues-7", "github-pull-requests",
        "github-pull-requests-7", "github-pull-requests-8",
      ]
    snapshot.kinds = {ghikPullRequest}
    snapshot.items[0].state = "CLOSED"
    check snapshot.gitHubHeadingIdentifiers() ==
      @["github-project", "github-pull-requests", "github-pull-requests-8"]
    snapshot.state = ghsAll
    check snapshot.gitHubHeadingIdentifiers() ==
      @[
        "github-project", "github-pull-requests", "github-pull-requests-7",
        "github-pull-requests-8",
      ]

  test "empty lists, partial failures, and fetch limits are visible":
    var snapshot = GitHubSnapshot(rootPath: "/projects/project")
    check "No matching issues." in snapshot.gitHubMarkdown()
    snapshot.errors[ghikIssue] = "gh auth login required"
    snapshot.items = parseGitHubItems(prJson, ghikPullRequest)
    snapshot.limitReached = {ghikPullRequest}
    let markdown = snapshot.gitHubMarkdown()
    check "Unable to load issues." in markdown
    check "gh auth login" in markdown
    check "Improve rendering" in markdown
    check "more may be available" in markdown

  test "closed PRs include merged pull requests":
    var snapshot = sampleSnapshot()
    snapshot.state = ghsClosed
    snapshot.items[1].state = "MERGED"
    let markdown = snapshot.gitHubMarkdown()
    check "Pull Requests (1)" in markdown
    check "Improve rendering" in markdown
    check "MERGED" in markdown
    check "Fix" notin markdown

  test "GitHub forwards reading scroll and Markdown section navigation after host shortcuts":
    var snapshot = sampleSnapshot()
    snapshot.items[0].body = "A long issue paragraph.\n\n".repeat(50)
    let
      panel = newKosmoGitHubPanel(snapshot)
      window = newWindow("GitHub keyboard navigation", frame = rect(0, 0, 600, 280))
    defer:
      panel.close()
      window.close()
    window.setContentView(panel)
    require panel.waitForGitHub()
    panel.markdownView.expandMarkdownHeadings()
    panel.layoutSubtreeIfNeeded()
    let scroll = panel.markdownView.scrollView()
    require scroll.maximumContentOffset().y > 64
    panel.keyEquivalentHandler = proc(event: KeyEvent): bool =
      event.key == keyF2
    require window.makeFirstResponder(panel.markdownView.textView())
    panel.markdownView.selectedRange = initTextRange(0, 0)
    require window.dispatchKeyDown(KeyEvent(key: keyArrowDown))
    check window.animationScheduler().tick(140.ms) == 1
    check scroll.contentOffset().y == 64
    require window.dispatchKeyDown(KeyEvent(key: keyArrowUp))
    check window.animationScheduler().tick(140.ms) == 1
    check scroll.contentOffset().y == 0
    require window.dispatchKeyDown(KeyEvent(key: keyF2))
    require window.dispatchKeyDown(KeyEvent(text: "j", key: keyJ))
    let heading = panel.markdownView.textView().selectedText()
    require heading.len > 0
    let expandedLength = panel.markdownView.textStorage().len
    require window.dispatchKeyDown(KeyEvent(key: keyEnter))
    require panel.waitForGitHub()
    check panel.markdownView.textStorage().len < expandedLength
    check panel.markdownView.textView().selectedText() == heading
    require window.dispatchKeyDown(KeyEvent(key: keyEnter))
    require panel.waitForGitHub()
    check panel.markdownView.textStorage().len == expandedLength

  test "offline document supports filters, native find, and tab close":
    let frontend =
      newKosmoApplication(newApplication("GitHub viewer"), monitorsGitStatus = false)
    let panel = newKosmoGitHubPanel(sampleSnapshot())
    defer:
      panel.close()
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 900, 600)
    require frontend.openDocument(
      newKosmoPaneDocument(
        KosmoGitHubTabIdentifier,
        "GitHub",
        panel,
        preferredFirstResponder = panel.markdownView.textView(),
        onClose = proc(document: KosmoPaneDocument): bool =
          panel.close()
          true,
      )
    )
    require panel.waitForGitHub()
    panel.markdownView.expandMarkdownHeadings()
    require panel.waitForGitHub()
    frontend.contentView.layoutSubtreeIfNeeded()
    check panel.refreshButton.enabled == false
    panel.refreshButton.checkVisibleIn(panel)
    panel.kindButton.checkVisibleIn(panel)
    panel.stateButton.checkVisibleIn(panel)
    panel.autoRefreshSwitch.checkVisibleIn(panel)
    check not panel.autoRefreshSwitch.on
    check not panel.autoRefreshSwitch.enabled
    var openedLink: string
    panel.linkHandler = proc(link: string): bool =
      openedLink = link
      true
    let rendered = panel.markdownView.textStorage().stringValue()
    require rendered.find("Fix") >= 0
    let titleIndex = rendered[0 ..< rendered.find("Fix")].runeLen
    check not panel.markdownView.textView().openLinkAtIndex(titleIndex)
    let
      titleRect = panel.markdownView.textView().characterRect(titleIndex)
      titlePoint = initPoint(
        titleRect.origin.x + titleRect.size.width * 0.5'f32,
        titleRect.origin.y + titleRect.size.height * 0.5'f32,
      )
      heading = panel.markdownView.textView().hitTest(titlePoint)
    require not heading.isNil
    check heading.accessibilityRole() == arDisclosureButton
    require panel.markdownView.textView().clickAt(titlePoint)
    require panel.waitForGitHub()
    require panel.markdownView.waitForMarkdownLayout()
    check heading.accessibilityValue() == "collapsed"
    check "A needle" notin panel.markdownView.textStorage().stringValue()
    check openedLink == ""
    let
      collapsedTitleRect = panel.markdownView.textView().characterRect(titleIndex)
      collapsedTitlePoint = initPoint(
        collapsedTitleRect.origin.x + collapsedTitleRect.size.width * 0.5'f32,
        collapsedTitleRect.origin.y + collapsedTitleRect.size.height * 0.5'f32,
      )
    require panel.markdownView.textView().hitTest(collapsedTitlePoint) == heading
    require panel.markdownView.textView().clickAt(collapsedTitlePoint)
    require panel.waitForGitHub()
    require panel.markdownView.waitForMarkdownLayout()
    check heading.accessibilityValue() == "expanded"
    let expanded = panel.markdownView.textStorage().stringValue()
    require expanded.find("Open issue #7 on GitHub") >= 0
    let issueLinkIndex =
      expanded[0 ..< expanded.find("Open issue #7 on GitHub")].runeLen
    require panel.markdownView.textView().openLinkAtIndex(issueLinkIndex)
    check openedLink == "https://github.com/owner/project/issues/7"
    require expanded.find("tests") >= 0
    let jobIndex = expanded[0 ..< expanded.find("tests")].runeLen
    require panel.markdownView.textView().openLinkAtIndex(jobIndex)
    check openedLink == "https://github.com/owner/project/actions/runs/12/job/34"
    require frontend.window.makeFirstResponder(panel.markdownView.textView())
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: shortcutModifiers())
    )
    require frontend.window.dispatchTextInput("needle")
    check panel.searchMatchCount() == 2
    check panel.markdownView.textView().selectedText() == "needle"
    let expression = panel.buttonWithLabel("Use Reni regular expressions")
    require not expression.isNil
    expression.checkVisibleIn(panel)
    require frontend.window.clickAt(expression.pointToWindow(initPoint(14, 14)))
    panel.searchField().selectedRange =
      initTextRange(0, panel.searchField().text().runeLen)
    require frontend.window.dispatchTextInput(r"n(e+)dle")
    check panel.searchMatchCount() == 2
    check panel.markdownView.textView().selectedText() == "needle"
    require panel.kindButton.menu()[2].perform(frontend.window)
    require panel.waitForGitHub()
    check panel.kindButton.title == "Pull Requests"
    check "Fix" notin panel.markdownView.textStorage().stringValue()
    check panel.searchMatchCount() == 1
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    require panel.kindButton.menu()[0].perform(frontend.window)
    require panel.stateButton.menu()[1].perform(frontend.window)
    require panel.waitForGitHub()
    check panel.stateButton.title == "Closed"
    check "Fix" notin panel.markdownView.textStorage().stringValue()
    check "Improve rendering" notin panel.markdownView.textStorage().stringValue()
    require panel.stateButton.menu()[2].perform(frontend.window)
    require panel.waitForGitHub()
    check panel.stateButton.title == "All States"
    check "Fix" in panel.markdownView.textStorage().stringValue()
    check "Improve rendering" in panel.markdownView.textStorage().stringValue()
    require panel.stateButton.menu()[0].perform(frontend.window)
    require panel.kindButton.menu()[1].perform(frontend.window)
    require panel.waitForGitHub()
    check panel.stateButton.title == "Open"
    check panel.kindButton.title == "Issues"
    check "Fix" in panel.markdownView.textStorage().stringValue()
    check "Improve rendering" notin panel.markdownView.textStorage().stringValue()
    let tabIndex =
      frontend.documentTabs.indexOfDocumentTabIdentifier(KosmoGitHubTabIdentifier)
    require frontend.documentTabs.closeDocumentTabAtIndex(tabIndex)
    check panel.closed

  test "GitHub menu action is registered and can be assigned a shortcut":
    let app = newApplication("GitHub action")
    let frontend = newKosmoApplication(app, monitorsGitStatus = false)
    defer:
      frontend.close()
    let item = app.mainMenu().menuItemForAction(KosmoShowGitHubAction)
    require not item.isNil
    check item.title == "Show GitHub Issues and PRs"
    check item.keyEquivalent().key == keyH
    check item.modifierMask() == shortcutModifiers() + {nimkit.kmShift}
    check not item.target.isNil
    var registered = false
    for action in kosmoActions():
      if action.identifier == KosmoShowGitHubAction:
        registered = true
    check registered
