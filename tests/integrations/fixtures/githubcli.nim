## A gh stand-in dispatched before test suites, without shells or GitHub access.
import std/[json, os, strutils]

proc fieldOrNull(node: JsonNode, key: string): JsonNode =
  result = node.getOrDefault(key)
  if result.isNil:
    result = newJNull()

if paramCount() == 2 and paramStr(1) == "api" and fileExists("github-test-mode"):
  let
    mode = readFile("github-test-mode").strip()
    endpoint = paramStr(2)
    isChecks = "/check-runs?" in endpoint
    isStatus = "/status?" in endpoint
    isReviews = "/reviews?" in endpoint
    isRun = "/actions/runs/" in endpoint
    command = if "/issues?" in endpoint: "issue" else: "pr"
    state =
      if "state=closed" in endpoint:
        "closed"
      elif "state=all" in endpoint:
        "all"
      else:
        "open"
    countPath =
      (
        if isChecks or isStatus: "checks"
        elif isReviews: "reviews"
        elif isRun: "runs"
        else: command
      ) & "-request-count"
    count =
      if fileExists(countPath):
        parseInt(readFile(countPath)) + 1
      else:
        1
  writeFile(countPath, $count)
  if not (isChecks or isStatus or isReviews or isRun):
    writeFile(
      command & "-request.json",
      $(
        %*{
          "root": getCurrentDir(),
          "args": @[paramStr(1), endpoint],
          "promptDisabled": getEnv("GH_PROMPT_DISABLED"),
          "repoOverride": getEnv("GH_REPO"),
          "pager": getEnv("GH_PAGER"),
        }
      ),
    )
  if mode == "block":
    writeFile("github-started", $getCurrentProcessId())
    discard stdin.readLine()
  elif mode == "invalid":
    stdout.write("not JSON")
  elif mode == "large":
    stdout.write("x".repeat(100_000))
  elif mode == "partial" and command == "issue":
    stderr.write("Issues are disabled for this repository")
    quit(1)
  elif mode == "auth":
    stderr.write("Run gh auth login to authenticate")
    quit(4)
  elif mode == "checks-error" and isChecks:
    stderr.write("Checks permission denied")
    quit(1)
  elif mode == "checks-error" and isStatus:
    stdout.write("{\"statuses\":[{\"context\":\"external\",\"state\":\"success\"}]}")
  elif mode == "pages" and command == "issue":
    var items = newJArray()
    if "&page=1" in endpoint:
      for number in 1 .. 100:
        items.add %*{
          "number": number,
          "pull_request": {},
          "title": "PR",
          "html_url": "https://github.com/o/r/pull/" & $number,
          "state": "open",
        }
    elif "&page=2" in endpoint:
      items.add %*{
        "number": 101,
        "title": "Real issue",
        "html_url": "https://github.com/o/r/issues/101",
        "state": "open",
      }
    stdout.write($items)
  elif mode == "pages" and isChecks:
    var checks = newJArray()
    let count = if "&page=1" in endpoint: 100 else: 1
    for index in 1 .. count:
      checks.add %*{
        "name": "test " & $index, "status": "completed", "conclusion": "success"
      }
    stdout.write($(%*{"check_runs": checks}))
  elif isReviews:
    stdout.write("[{\"user\":{\"login\":\"alice\"},\"state\":\"APPROVED\"}]")
  elif isRun:
    stdout.write("{\"name\":\"CI\"}")
  elif isStatus:
    stdout.write("{\"statuses\":[]}")
  elif isChecks:
    let jobState =
      if fileExists("github-job-state"):
        readFile("github-job-state").strip()
      else:
        "IN_PROGRESS"
    let jobStatus = if jobState in ["QUEUED", "IN_PROGRESS"]: jobState else: "COMPLETED"
    stdout.write(
      $(
        %*{
          "check_runs": [
            {
              "name": "tests",
              "status": jobStatus,
              "conclusion": if jobStatus == "COMPLETED": jobState else: "",
              "html_url": "https://github.com/o/r/actions/runs/12/job/34",
            }
          ]
        }
      )
    )
  elif mode == "empty":
    stdout.write("[]")
  else:
    let input =
      if fileExists(command & "-response.json"):
        parseJson(readFile(command & "-response.json"))
      else:
        %*[
          {
            "number": 9,
            "title": command & " " & state,
            "body": "A **rendered** description.",
            "url": "https://github.com/o/r/issues/9",
            "state": state.toUpperAscii(),
            "author": {"login": "tester"},
            "labels": [],
            "isDraft": command == "pr",
            "headRefName": "topic",
            "baseRefName": "main",
          }
        ]
    var output = newJArray()
    for item in input:
      var converted = %*{
        "number": item["number"],
        "title": item["title"],
        "body": item.fieldOrNull("body"),
        "html_url": item["url"],
        "state": item["state"],
        "user": item.fieldOrNull("author"),
        "labels": item.fieldOrNull("labels"),
        "updated_at": item.fieldOrNull("updatedAt"),
      }
      if command == "pr":
        converted["draft"] = item.fieldOrNull("isDraft")
        converted["head"] = %*{
          "ref": item.fieldOrNull("headRefName"),
          "sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }
        converted["base"] = %*{"ref": item.fieldOrNull("baseRefName")}
      output.add converted
    stdout.write($output)
  quit(0)
