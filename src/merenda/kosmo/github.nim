## GitHub CLI snapshots and Markdown presentation for a local project repository.

import std/[json, os, strtabs, strutils, uri]
import ../nimkit/foundation/backgroundprocesses

const GitHubDefaultItemLimit* = 100

type
  GitHubItemKind* = enum
    ghikIssue
    ghikPullRequest

  GitHubState* = enum
    ghsOpen
    ghsClosed
    ghsAll

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
    headBranch*, baseBranch*, reviewDecision*: string
    jobs*: seq[GitHubJob]

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

proc readGitHubSnapshot*(
    rootPath: string,
    state = ghsOpen,
    kinds: set[GitHubItemKind] = {ghikIssue, ghikPullRequest},
    itemLimit: Positive = GitHubDefaultItemLimit,
    executable = "gh",
    cancelled: proc(): bool {.closure, gcsafe.} = nil,
    timeoutMilliseconds: Positive = 30_000,
    maxOutputBytes: Natural = 8 * 1024 * 1024,
): GitHubSnapshot =
  ## Read bounded lists using the project's remotes and the user's existing gh login.
  ## Each list may fail independently; successful results remain available.
  result =
    GitHubSnapshot(rootPath: rootPath, state: state, kinds: kinds, itemLimit: itemLimit)
  let environment = newStringTable(modeCaseSensitive)
  for key, value in envPairs():
    environment[key] = value
  environment.del("GH_REPO")
  environment["GH_PROMPT_DISABLED"] = "1"
  environment["GH_PAGER"] = "cat"
  for kind in kinds:
    if not cancelled.isNil and cancelled():
      return
    let command = if kind == ghikIssue: "issue" else: "pr"
    var fields = "number,title,body,url,state,author,labels,updatedAt"
    if kind == ghikPullRequest:
      fields.add ",isDraft,headRefName,baseRefName,reviewDecision,statusCheckRollup"
    let response = runBackgroundCommand(
      executable,
      [
        command,
        "list",
        "--state",
        state.cliState(),
        "--limit",
        $itemLimit,
        "--json",
        fields,
      ],
      workingDirectory = rootPath,
      timeoutMilliseconds = timeoutMilliseconds,
      cancelled = cancelled,
      maxOutputBytes = maxOutputBytes,
      environment = environment,
      diagnosticName = "GitHub CLI",
    )
    if response.exitCode != 0:
      result.errors[kind] = response.output.strip()
      if result.errors[kind].len == 0:
        result.errors[kind] = "gh exited with code " & $response.exitCode
    else:
      try:
        let items = parseGitHubItems(response.output, kind)
        if items.len >= itemLimit:
          result.limitReached.incl kind
        result.items.add items
      except CatchableError:
        result.errors[kind] = "Invalid gh JSON: " & getCurrentExceptionMsg()

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

proc gitHubMarkdown*(snapshot: GitHubSnapshot): string =
  ## Render metadata as text and each item's body as an isolated Markdown quote.
  result = "# GitHub · " & snapshot.rootPath.lastPathPart().markdownText() & "\n\n"
  result.add "Project: " & snapshot.rootPath.markdownText() & "\n\n"
  result.add "State: " & snapshot.state.cliState().capitalizeAscii() & "\n\n"
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
        result.add "### " &
          (if url.len > 0: "[" & label & "](<" & url & ">)" else: label)
        result.add "\n\n" & item.state.markdownText()
        if item.draft:
          result.add " · Draft"
        if item.author.len > 0:
          result.add " · @" & item.author.markdownText()
        if item.updatedAt.len > 0:
          result.add " · Updated " & item.updatedAt.markdownText()
        result.add "\n\n"
        if item.labels.len > 0:
          result.add "Labels: " & item.labels.join(", ").markdownText() & "\n\n"
        if item.headBranch.len > 0:
          result.add item.headBranch.markdownText() & " → " &
            item.baseBranch.markdownText() & "\n\n"
        if item.reviewDecision.len > 0:
          result.add "Review: " & item.reviewDecision.markdownText() & "\n\n"
        if item.kind == ghikPullRequest:
          result.add item.jobs.jobsMarkdown()
        if item.body.strip().len > 0:
          for line in item.body.splitLines():
            result.add "> " & line & "\n"
          result.add "\n"
        else:
          result.add "No description.\n\n"
