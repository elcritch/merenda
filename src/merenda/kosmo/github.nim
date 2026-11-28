## GitHub CLI snapshots and Markdown presentation for a local project repository.

import std/[json, os, strtabs, strutils, tables, uri]
import ../nimkit/foundation/backgroundprocesses

const GitHubDefaultItemLimit* = 100

const GitHubDiffLinkPrefix* = "kosmo-pr-diff:"
const GitHubMergeAnchorPrefix* = "kosmo-pr-merge:"

type
  GitHubItemKind* = enum
    ghikIssue
    ghikPullRequest

  GitHubState* = enum
    ghsOpen
    ghsClosed
    ghsAll

  GitHubMergeMethod* {.pure.} = enum
    Merge = "merge"
    Squash = "squash"
    Rebase = "rebase"

  GitHubJobState* = enum
    ghjsUnknown
    ghjsPending
    ghjsRunning
    ghjsPassed
    ghjsFailed
    ghjsCancelled
    ghjsSkipped
    ghjsNeutral
    ghjsStale

  GitHubJob* = object
    name*, workflow*, url*: string
    state*: GitHubJobState

  GitHubItem* = object
    kind*: GitHubItemKind
    number*: int
    title*, body*, url*, state*, author*, updatedAt*: string
    labels*: seq[string]
    draft*: bool
    headBranch*, baseBranch*, reviewDecision*, reviewActivity*, headSha*: string
    jobs*: seq[GitHubJob]
    jobsPending*: bool
    jobsTruncated*: bool
    jobsError*: string

  GitHubSnapshot* = object
    rootPath*: string
    state*: GitHubState
    kinds*: set[GitHubItemKind] = {ghikIssue, ghikPullRequest}
    items*: seq[GitHubItem]
    errors*: array[GitHubItemKind, string]
    limitReached*: set[GitHubItemKind]
    itemLimit*: int = GitHubDefaultItemLimit

func cliState(state: GitHubState): string =
  case state
  of ghsOpen: "open"
  of ghsClosed: "closed"
  of ghsAll: "all"

func title*(kind: GitHubItemKind): string =
  case kind
  of ghikIssue: "Issues"
  of ghikPullRequest: "Pull Requests"

proc pullRequestRepository*(item: GitHubItem): string =
  ## Repository URL hosting the PR, including fork PR refs exposed by GitHub.
  if item.kind != ghikPullRequest or item.number <= 0:
    return
  let url = parseUri(item.url)
  let suffix = "/pull/" & $item.number
  if url.scheme in ["http", "https"] and url.hostname.len > 0 and
      url.path.endsWith(suffix):
    var repository = url
    repository.path = url.path[0 ..< url.path.len - suffix.len] & ".git"
    repository.query = ""
    repository.anchor = ""
    result = $repository

func title*(state: GitHubJobState): string =
  case state
  of ghjsUnknown: "Unknown"
  of ghjsPending: "Pending"
  of ghjsRunning: "Running"
  of ghjsPassed: "Passed"
  of ghjsFailed: "Failed"
  of ghjsCancelled: "Cancelled"
  of ghjsSkipped: "Skipped"
  of ghjsNeutral: "Neutral"
  of ghjsStale: "Stale"

proc stringField(node: JsonNode, key: string): string =
  let value = node.getOrDefault(key)
  if not value.isNil and value.kind != JNull:
    if value.kind != JString:
      raise newException(ValueError, "Invalid GitHub field: " & key)
    result = value.getStr()

func completedJobState(conclusion: string): GitHubJobState =
  case conclusion
  of "SUCCESS":
    ghjsPassed
  of "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE":
    ghjsFailed
  of "CANCELLED":
    ghjsCancelled
  of "SKIPPED":
    ghjsSkipped
  of "NEUTRAL":
    ghjsNeutral
  of "STALE":
    ghjsStale
  else:
    ghjsUnknown

proc parseGitHubJob(node: JsonNode): GitHubJob =
  if node.kind != JObject:
    raise newException(ValueError, "Invalid GitHub job")
  if node.stringField("__typename") == "StatusContext":
    result.name = node.stringField("context")
    result.url = node.stringField("targetUrl")
    let state = node.stringField("state")
    result.state =
      if state in ["PENDING", "EXPECTED"]:
        ghjsPending
      else:
        completedJobState(state)
  else:
    result.name = node.stringField("name")
    result.workflow = node.stringField("workflowName")
    result.url = node.stringField("detailsUrl")
    result.state =
      case node.stringField("status")
      of "IN_PROGRESS":
        ghjsRunning
      of "QUEUED", "PENDING", "WAITING", "REQUESTED":
        ghjsPending
      of "COMPLETED":
        completedJobState(node.stringField("conclusion"))
      else:
        ghjsUnknown
  if result.name.len == 0:
    result.name = "Unnamed check"

proc parseGitHubItems*(source: string, kind: GitHubItemKind): seq[GitHubItem] =
  ## Parse `gh issue list --json` or `gh pr list --json`; reject malformed records.
  let records = parseJson(source)
  if records.kind != JArray:
    raise newException(ValueError, "Expected a GitHub JSON array")
  for record in records:
    if record.kind != JObject:
      raise newException(ValueError, "Expected a GitHub item object")
    let number = record.getOrDefault("number")
    if number.isNil or number.kind != JInt or number.getBiggestInt() <= 0 or
        number.getBiggestInt() > int.high:
      raise newException(ValueError, "Invalid GitHub item number")
    var item = GitHubItem(
      kind: kind,
      number: number.getInt(),
      title: record.stringField("title"),
      body: record.stringField("body"),
      url: record.stringField("url"),
      state: record.stringField("state"),
      updatedAt: record.stringField("updatedAt"),
    )
    if item.title.len == 0 or item.url.len == 0 or item.state.len == 0:
      raise newException(ValueError, "Missing GitHub item title, URL, or state")
    let author = record.getOrDefault("author")
    if not author.isNil and author.kind == JObject:
      item.author = author.stringField("login")
    let labels = record.getOrDefault("labels")
    if not labels.isNil and labels.kind == JArray:
      for label in labels:
        if label.kind != JObject:
          raise newException(ValueError, "Invalid GitHub label")
        item.labels.add label.stringField("name")
    if kind == ghikPullRequest:
      let draft = record.getOrDefault("isDraft")
      if not draft.isNil and draft.kind == JBool:
        item.draft = draft.getBool()
      item.headBranch = record.stringField("headRefName")
      item.baseBranch = record.stringField("baseRefName")
      item.reviewDecision = record.stringField("reviewDecision")
      let jobs = record.getOrDefault("statusCheckRollup")
      if not jobs.isNil and jobs.kind != JNull:
        if jobs.kind != JArray:
          raise newException(ValueError, "Invalid GitHub job list")
        for job in jobs:
          item.jobs.add parseGitHubJob(job)
    result.add item

proc parseGitHubRestRecords(records: JsonNode, kind: GitHubItemKind): seq[GitHubItem] =
  if records.kind != JArray:
    raise newException(ValueError, "Expected a GitHub JSON array")
  for record in records:
    if record.kind != JObject:
      raise newException(ValueError, "Expected a GitHub item object")
    if kind == ghikIssue and record.hasKey("pull_request"):
      continue
    let number = record.getOrDefault("number")
    if number.isNil or number.kind != JInt or number.getBiggestInt() <= 0 or
        number.getBiggestInt() > int.high:
      raise newException(ValueError, "Invalid GitHub item number")
    var item = GitHubItem(
      kind: kind,
      number: number.getInt(),
      title: record.stringField("title"),
      body: record.stringField("body"),
      url: record.stringField("html_url"),
      state: record.stringField("state").toUpperAscii(),
      updatedAt: record.stringField("updated_at"),
    )
    if item.title.len == 0 or item.url.len == 0 or item.state.len == 0:
      raise newException(ValueError, "Missing GitHub item title, URL, or state")
    let author = record.getOrDefault("user")
    if not author.isNil and author.kind == JObject:
      item.author = author.stringField("login")
    let labels = record.getOrDefault("labels")
    if not labels.isNil and labels.kind == JArray:
      for label in labels:
        if label.kind != JObject:
          raise newException(ValueError, "Invalid GitHub label")
        item.labels.add label.stringField("name")
    if kind == ghikPullRequest:
      let draft = record.getOrDefault("draft")
      if not draft.isNil and draft.kind == JBool:
        item.draft = draft.getBool()
      let head = record.getOrDefault("head")
      if not head.isNil and head.kind == JObject:
        item.headBranch = head.stringField("ref")
        item.headSha = head.stringField("sha")
      let base = record.getOrDefault("base")
      if not base.isNil and base.kind == JObject:
        item.baseBranch = base.stringField("ref")
      let merged = record.getOrDefault("merged_at")
      if not merged.isNil and merged.kind != JNull:
        item.state = "MERGED"
      item.jobsPending = true
    result.add item

proc parseGitHubRestItems*(source: string, kind: GitHubItemKind): seq[GitHubItem] =
  ## Parse REST issue or pull request records; issue endpoints also return PRs.
  parseGitHubRestRecords(parseJson(source), kind)

proc parseRestChecks(source: string): seq[GitHubJob] =
  let response = parseJson(source)
  if response.kind != JObject or not response.hasKey("check_runs") or
      response["check_runs"].kind != JArray:
    raise newException(ValueError, "Invalid GitHub check runs")
  for node in response["check_runs"]:
    if node.kind != JObject:
      raise newException(ValueError, "Invalid GitHub check run")
    let detailsUrl = node.stringField("details_url")
    let normalized = %*{
      "name": node.stringField("name"),
      "status": node.stringField("status").toUpperAscii(),
      "conclusion": node.stringField("conclusion").toUpperAscii(),
      "detailsUrl":
        if detailsUrl.len > 0:
          detailsUrl
        else:
          node.stringField("html_url"),
    }
    result.add parseGitHubJob(normalized)

proc parseRestStatuses(source: string): seq[GitHubJob] =
  let response = parseJson(source)
  if response.kind != JObject or not response.hasKey("statuses") or
      response["statuses"].kind != JArray:
    raise newException(ValueError, "Invalid GitHub commit statuses")
  for node in response["statuses"]:
    if node.kind != JObject:
      raise newException(ValueError, "Invalid GitHub commit status")
    let normalized = %*{
      "__typename": "StatusContext",
      "context": node.stringField("context"),
      "state": node.stringField("state").toUpperAscii(),
      "targetUrl": node.stringField("target_url"),
    }
    result.add parseGitHubJob(normalized)

proc parseRestReviewActivity(response: JsonNode): string =
  if response.kind != JArray:
    raise newException(ValueError, "Invalid GitHub reviews")
  var latest = initTable[string, string]()
  for review in response:
    if review.kind != JObject:
      raise newException(ValueError, "Invalid GitHub review")
    let user = review.getOrDefault("user")
    if user.isNil or user.kind != JObject:
      continue
    let
      name = user.stringField("login")
      state = review.stringField("state").toUpperAscii()
    if name.len > 0 and state in ["APPROVED", "CHANGES_REQUESTED", "DISMISSED"]:
      latest[name] = state
  var approvals, changes: int
  for state in latest.values:
    if state == "APPROVED":
      inc approvals
    elif state == "CHANGES_REQUESTED":
      inc changes
  if approvals > 0:
    result.add $approvals & " approved"
  if changes > 0:
    if result.len > 0:
      result.add " · "
    result.add $changes & " requested changes"

func workflowRunId(url: string): string =
  let path = url.split('/')
  for index in 0 ..< max(path.len - 2, 0):
    if path[index] == "actions" and path[index + 1] == "runs":
      let identifier = path[index + 2]
      if identifier.len > 0 and identifier.len <= 20 and identifier.allCharsInSet(
        Digits
      ):
        return identifier

proc runGitHubCli(
    rootPath, executable: string,
    arguments: seq[string],
    cancelled: proc(): bool {.closure, gcsafe.},
    timeoutMilliseconds: Positive,
    maxOutputBytes: Natural,
): BackgroundCommandResult =
  let environment = newStringTable(modeCaseSensitive)
  for key, value in envPairs():
    environment[key] = value
  environment.del("GH_REPO")
  environment["GH_PROMPT_DISABLED"] = "1"
  environment["GH_PAGER"] = "cat"
  var
    commandExecutable = executable
    commandArguments = arguments
  when defined(posix):
    if executable == "gh":
      commandExecutable = getEnv("SHELL")
      if commandExecutable.len == 0:
        commandExecutable = "/bin/sh"
      # Reapply repository settings after the login profile and exec for cancellation.
      let commandParts =
        @[
          "/usr/bin/env",
          "-C",
          absolutePath(rootPath),
          "-u",
          "GH_REPO",
          "--",
          "GH_PROMPT_DISABLED=1",
          "GH_PAGER=cat",
          executable,
        ] & arguments
      commandArguments = @["-l", "-c", "exec " & quoteShellCommand(commandParts)]
  runBackgroundCommand(
    commandExecutable,
    commandArguments,
    workingDirectory = rootPath,
    timeoutMilliseconds = timeoutMilliseconds,
    cancelled = cancelled,
    maxOutputBytes = maxOutputBytes,
    environment = environment,
    diagnosticName = "GitHub CLI",
  )

func validHeadSha(sha: string): bool =
  sha.len in [40, 64] and sha.allCharsInSet(HexDigits)

proc pullRequestMergeTarget(item: GitHubItem): tuple[host, endpoint: string] =
  if item.kind != ghikPullRequest or item.number <= 0 or item.draft or
      item.state.toUpperAscii() != "OPEN" or not item.headSha.validHeadSha():
    return
  let
    url = parseUri(item.url)
    path = url.path.split('/')
  if url.scheme notin ["http", "https"] or url.hostname.len == 0 or path.len != 5 or
      path[0].len != 0 or path[3] != "pull" or path[4] != $item.number:
    return
  for part in [path[1], path[2]]:
    if part.len == 0 or part in [".", ".."] or
        not part.allCharsInSet(Letters + Digits + {'-', '_', '.'}):
      return
  result =
    (url.hostname, "repos/" & path[1] & "/" & path[2] & "/pulls/" & path[4] & "/merge")

proc canMergePullRequest*(item: GitHubItem): bool =
  ## Whether the snapshot supplies a target and head for a direct merge request.
  item.pullRequestMergeTarget().endpoint.len > 0

proc mergeGitHubPullRequest*(
    rootPath: string,
    item: GitHubItem,
    mergeMethod: GitHubMergeMethod,
    executable = "gh",
    cancelled: proc(): bool {.closure, gcsafe.} = nil,
): string =
  ## Request a direct merge for this PR and head commit. Return GitHub's error on failure.
  let (host, endpoint) = item.pullRequestMergeTarget()
  if endpoint.len == 0:
    return "The pull request is unavailable for merging."
  let response = runGitHubCli(
    rootPath,
    executable,
    @[
      "api",
      endpoint,
      "--hostname",
      host,
      "--method",
      "PUT",
      "--raw-field",
      "merge_method=" & $mergeMethod,
      "--raw-field",
      "sha=" & item.headSha,
    ],
    cancelled,
    30_000,
    64 * 1024,
  )
  if response.exitCode != 0:
    let output = response.output.strip()
    for line in output.splitLines():
      if line.startsWith("gh: "):
        return line[4 .. ^1]
    return
      if output.len > 0:
        output
      else:
        "gh exited with code " & $response.exitCode
  try:
    let body = parseJson(response.output)
    if body.kind == JObject:
      if body.getOrDefault("merged").getBool():
        return
      let message = body.stringField("message")
      if message.len > 0:
        return message
  except CatchableError:
    discard
  result = "GitHub did not confirm the merge."

proc readGitHubSnapshot*(
    rootPath: string,
    state = ghsOpen,
    kinds: set[GitHubItemKind] = {ghikIssue, ghikPullRequest},
    itemLimit: Positive = GitHubDefaultItemLimit,
    executable = "gh",
    cancelled: proc(): bool {.closure, gcsafe.} = nil,
    timeoutMilliseconds: Positive = 30_000,
    maxOutputBytes: Natural = 8 * 1024 * 1024,
    openPullRequests: seq[int] = @[],
    previousSnapshot: GitHubSnapshot = GitHubSnapshot(),
    detailsOnly = false,
): GitHubSnapshot =
  ## Read bounded lists using the project's remotes and the user's existing gh login.
  ## Each list may fail independently; successful results remain available.
  ## On POSIX, the default `gh` command runs through the user's login shell so
  ## desktop-launched apps can find commands installed by their shell profile.
  ## Explicit executable paths run directly.
  result =
    GitHubSnapshot(rootPath: rootPath, state: state, kinds: kinds, itemLimit: itemLimit)
  if detailsOnly:
    result = previousSnapshot
  var rateLimitResponse: BackgroundCommandResult
  proc request(endpoint: string): BackgroundCommandResult =
    if rateLimitResponse.exitCode != 0:
      return rateLimitResponse
    result = runGitHubCli(
      rootPath,
      executable,
      @["api", endpoint],
      cancelled,
      timeoutMilliseconds,
      maxOutputBytes,
    )
    if result.exitCode != 0 and "rate limit" in result.output.toLowerAscii():
      rateLimitResponse = result

  for kind in (if detailsOnly: {} else: kinds):
    if not cancelled.isNil and cancelled():
      return
    let path = if kind == ghikIssue: "issues" else: "pulls"
    const pageSize = 100
    var page = 1
    var count = 0
    while count < itemLimit:
      if not cancelled.isNil and cancelled():
        return
      let endpoint =
        "repos/{owner}/{repo}/" & path & "?state=" & state.cliState() & "&per_page=" &
        $pageSize & "&page=" & $page & "&sort=updated&direction=desc"
      let response = request(endpoint)
      if response.exitCode != 0:
        result.errors[kind] = response.output.strip()
        if result.errors[kind].len == 0:
          result.errors[kind] = "gh exited with code " & $response.exitCode
        break
      try:
        let raw = parseJson(response.output)
        if raw.kind != JArray:
          raise newException(ValueError, "Expected a GitHub JSON array")
        let items = parseGitHubRestRecords(raw, kind)
        for item in items:
          if count >= itemLimit:
            break
          result.items.add item
          inc count
        if count >= itemLimit:
          result.limitReached.incl kind
          break
        if raw.len < pageSize:
          break
        inc page
      except CatchableError:
        result.errors[kind] = "Invalid gh JSON: " & getCurrentExceptionMsg()
        break
  for item in result.items.mitems:
    if item.kind != ghikPullRequest or item.number notin openPullRequests:
      continue
    if not cancelled.isNil and cancelled():
      return
    item.jobsPending = false
    item.jobs.setLen(0)
    item.jobsError = ""
    item.jobsTruncated = false
    item.reviewActivity = ""
    if not item.headSha.validHeadSha():
      item.jobsError = "The pull request head commit is unavailable."
      continue
    for endpoint in ["check-runs", "status"]:
      for page in 1 .. 10:
        if not cancelled.isNil and cancelled():
          return
        let response = request(
          "repos/{owner}/{repo}/commits/" & item.headSha & "/" & endpoint &
            "?per_page=100&page=" & $page
        )
        if response.exitCode != 0:
          item.jobsError = response.output.strip()
          if item.jobsError.len == 0:
            item.jobsError = "gh exited with code " & $response.exitCode
          break
        try:
          let jobs =
            if endpoint == "check-runs":
              parseRestChecks(response.output)
            else:
              parseRestStatuses(response.output)
          item.jobs.add jobs
          if jobs.len < 100:
            break
          if page == 10:
            item.jobsTruncated = true
        except CatchableError:
          item.jobsError = "Invalid gh JSON: " & getCurrentExceptionMsg()
          break
    var workflowNames = initTable[string, string]()
    for job in item.jobs.mitems:
      let runId = workflowRunId(job.url)
      if runId.len == 0:
        continue
      if runId notin workflowNames:
        if not cancelled.isNil and cancelled():
          return
        let workflow = request("repos/{owner}/{repo}/actions/runs/" & runId)
        var name = ""
        if workflow.exitCode == 0:
          try:
            let record = parseJson(workflow.output)
            if record.kind == JObject:
              name = record.stringField("name")
          except CatchableError:
            discard
        workflowNames[runId] = name
      job.workflow = workflowNames[runId]
    if not cancelled.isNil and cancelled():
      return
    var reviews = newJArray()
    for page in 1 .. 10:
      if not cancelled.isNil and cancelled():
        return
      let response = request(
        "repos/{owner}/{repo}/pulls/" & $item.number & "/reviews?per_page=100&page=" &
          $page
      )
      if response.exitCode != 0:
        break
      try:
        let records = parseJson(response.output)
        if records.kind != JArray:
          break
        for record in records:
          reviews.add record
        if records.len < 100:
          item.reviewActivity = parseRestReviewActivity(reviews)
          break
        if page == 10:
          item.reviewActivity = "More reviews are available on GitHub"
      except CatchableError:
        break

proc markdownText(value: string): string =
  for ch in value:
    case ch
    of '\r', '\n', '\t':
      result.add ' '
    of '\\', '`', '*', '_', '{', '}', '[', ']', '(', ')', '#', '+', '-', '.', '!', '>',
        '<', '|', '~':
      result.add '\\'
      result.add ch
    else:
      result.add ch

proc markdownUrl(value: string): string =
  let url = parseUri(value)
  if url.scheme in ["https", "http"] and url.hostname.len > 0:
    result = value
      .replace("\r", "%0D")
      .replace("\n", "%0A")
      .replace("<", "%3C")
      .replace(">", "%3E")
      .replace(" ", "%20")
      .replace("|", "%7C")
      .replace("\\", "%5C")

proc markdownCode(value: string): string =
  ## A code span whose fence is longer than any backtick run in `value`.
  var longest, run: int
  for ch in value:
    if ch == '`':
      inc run
      longest = max(longest, run)
    else:
      run = 0
  let
    fence = "`".repeat(longest + 1)
    text = value.multiReplace(("\r", " "), ("\n", " "))
    padding = if text.startsWith('`') or text.endsWith('`'): " " else: ""
  fence & padding & text & padding & fence

func displayState(state: string): string =
  state.toLowerAscii().capitalizeAscii()

func displayDate(timestamp: string): string =
  ## ISO 8601 timestamps show their calendar date; other values are unchanged.
  if timestamp.len >= 10 and timestamp[4] == '-' and timestamp[7] == '-' and
      timestamp[0 .. 3].allCharsInSet(Digits):
    timestamp[0 .. 9]
  else:
    timestamp

const GitHubBodyHeadingOffset = 3 ## Description headings follow the item title, an H3.

proc demotedHeadings(body: string): string =
  ## Shift ATX headings below the item title, leaving fenced code unchanged.
  var fence = ""
  var first = true
  for line in body.splitLines():
    if not first:
      result.add '\n'
    first = false
    let
      indent = line.len - line.strip(trailing = false).len
      content = line.strip(trailing = false)
    if indent <= 3 and (content.startsWith("```") or content.startsWith("~~~")):
      var marker = 0
      while marker < content.len and content[marker] == content[0]:
        inc marker
      if fence.len == 0:
        fence = content[0 ..< marker]
      elif content[0] == fence[0] and marker >= fence.len and
          content[marker .. ^1].strip().len == 0:
        fence = ""
    elif fence.len == 0 and indent <= 3 and content.startsWith('#'):
      var level = 0
      while level < content.len and content[level] == '#':
        inc level
      if level <= 6 and (level == content.len or content[level] in {' ', '\t'}):
        result.add line[0 ..< indent]
        result.add '#'.repeat(min(level + GitHubBodyHeadingOffset, 6))
        result.add content[level .. ^1]
        continue
    result.add line

func matchesState(item: GitHubItem, state: GitHubState): bool =
  case state
  of ghsOpen:
    item.state == "OPEN"
  of ghsClosed:
    item.state == "CLOSED" or (item.kind == ghikPullRequest and item.state == "MERGED")
  of ghsAll:
    true

proc jobsMarkdown(jobs: seq[GitHubJob]): string =
  if jobs.len == 0:
    return "Jobs: No checks reported.\n\n"
  var counts: array[GitHubJobState, int]
  for job in jobs:
    inc counts[job.state]
  var summary: seq[string]
  for state in [
    ghjsFailed, ghjsRunning, ghjsPending, ghjsPassed, ghjsCancelled, ghjsSkipped,
    ghjsNeutral, ghjsStale, ghjsUnknown,
  ]:
    if counts[state] > 0:
      summary.add $counts[state] & " " & state.title().toLowerAscii()
  result = "Jobs: **" & summary.join(" · ") & "**\n\n"
  result.add "| Job | Workflow | Status |\n| --- | --- | --- |\n"
  for job in jobs:
    let name = job.name.markdownText()
    let url = job.url.markdownUrl()
    let label =
      if url.len > 0:
        "[" & name & "](<" & url & ">)"
      else:
        name
    result.add "| " & label & " | " & job.workflow.markdownText() & " | " &
      job.state.title() & " |\n"
  result.add "\n"

proc gitHubHeadingIdentifiers*(snapshot: GitHubSnapshot): seq[string] =
  ## Stable section identities in the heading order produced by `gitHubMarkdown`.
  result.add "github-project"
  for kind in snapshot.kinds:
    let prefix = if kind == ghikIssue: "github-issues" else: "github-pull-requests"
    result.add prefix
    for item in snapshot.items:
      if item.kind == kind and item.matchesState(snapshot.state):
        result.add prefix & "-" & $item.number

proc gitHubMarkdown*(snapshot: GitHubSnapshot, mergeActions = false): string =
  ## Render metadata as text and each item's body as an isolated Markdown quote.
  result = "# GitHub · " & snapshot.rootPath.lastPathPart().markdownText() & "\n\n"
  result.add snapshot.rootPath.markdownText() & "\n\n"
  for kind in snapshot.kinds:
    var count = 0
    for item in snapshot.items:
      if item.kind == kind and item.matchesState(snapshot.state):
        inc count
    result.add "## " & kind.title() & " (" & $count & ")\n\n"
    if snapshot.errors[kind].len > 0:
      result.add "Unable to load " & kind.title().toLowerAscii() & ".\n\n"
      result.add snapshot.errors[kind].markdownText() & "\n\n"
      result.add "Check that `gh` is installed, run `gh auth login`, and verify " &
        "this project's GitHub remote. Then choose Refresh.\n\n"
    elif count == 0:
      result.add "No matching " & kind.title().toLowerAscii() & ".\n\n"
    if kind in snapshot.limitReached:
      result.add "Showing up to " & $snapshot.itemLimit &
        " items; more may be available on GitHub.\n\n"
    for item in snapshot.items:
      if item.kind == kind and item.matchesState(snapshot.state):
        let label = ("#" & $item.number & " " & item.title).markdownText()
        let url = item.url.markdownUrl()
        result.add "### " & label & "\n\n"
        var details = @["**" & item.state.displayState().markdownText() & "**"]
        if item.draft:
          details.add "Draft"
        if item.author.len > 0:
          details.add "@" & item.author.markdownText()
        if item.updatedAt.len > 0:
          details.add "updated " & item.updatedAt.displayDate().markdownText()
        if url.len > 0:
          let linkLabel =
            (if kind == ghikIssue: "Open issue #" else: "Open PR #") & $item.number &
            " on GitHub"
          details.add "[" & linkLabel & "](<" & url & ">)"
        result.add details.join(" · ") & "\n\n"
        if item.labels.len > 0:
          var labels: seq[string]
          for name in item.labels:
            labels.add name.markdownCode()
          result.add "Labels: " & labels.join(" ") & "\n\n"
        if item.headBranch.len > 0:
          result.add item.headBranch.markdownCode() & " → " &
            item.baseBranch.markdownCode()
          if item.kind == ghikPullRequest and item.number > 0 and item.baseBranch.len > 0:
            result.add " · [Open diff in Kosmo](" & GitHubDiffLinkPrefix & $item.number &
              ")"
          result.add "\n\n"
        if item.reviewDecision.len > 0:
          result.add "Review: " & item.reviewDecision.markdownText() & "\n\n"
        elif item.reviewActivity.len > 0:
          result.add "Review activity: " & item.reviewActivity.markdownText() & "\n\n"
        if item.kind == ghikPullRequest:
          if mergeActions and item.canMergePullRequest():
            # Reserve two text lines for the native buttons in the repository view.
            result.add "[&#160;](" & GitHubMergeAnchorPrefix & $item.number &
              ")  \n&#160;\n\n"
          if item.jobsPending:
            result.add "Jobs: Open this pull request to load checks.\n\n"
          elif item.jobsError.len > 0:
            if item.jobs.len > 0:
              result.add item.jobs.jobsMarkdown()
              result.add "Some checks could not be loaded: " &
                item.jobsError.markdownText() & "\n\n"
            else:
              result.add "Jobs: Unable to load checks: " & item.jobsError.markdownText() &
                "\n\n"
          else:
            result.add item.jobs.jobsMarkdown()
            if item.jobsTruncated:
              result.add "Additional checks may be available on GitHub.\n\n"
        if item.body.strip().len > 0:
          for line in item.body.demotedHeadings().splitLines():
            result.add "> " & line & "\n"
          result.add "\n"
        else:
          result.add "No description.\n\n"
