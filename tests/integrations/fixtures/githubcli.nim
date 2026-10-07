## A gh stand-in dispatched before test suites, without shells or GitHub access.
import std/[json, os, strutils]

if paramCount() == 8 and paramStr(1) in ["issue", "pr"] and paramStr(2) == "list" and
    fileExists("github-test-mode"):
  let mode = readFile("github-test-mode").strip()
  let command = paramStr(1)
  var arguments: seq[string]
  for index in 1 .. paramCount():
    arguments.add paramStr(index)
  let countPath = command & "-request-count"
  let count =
    if fileExists(countPath):
      parseInt(readFile(countPath)) + 1
    else:
      1
  writeFile(countPath, $count)
  writeFile(
    command & "-request.json",
    $(
      %*{
        "root": getCurrentDir(),
        "args": arguments,
        "promptDisabled": getEnv("GH_PROMPT_DISABLED"),
        "repoOverride": getEnv("GH_REPO"),
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
  elif mode == "empty":
    stdout.write("[]")
  elif fileExists(command & "-response.json"):
    stdout.write(readFile(command & "-response.json"))
  else:
    let jobState =
      if fileExists("github-job-state"):
        readFile("github-job-state").strip()
      else:
        "IN_PROGRESS"
    let jobStatus = if jobState in ["QUEUED", "IN_PROGRESS"]: jobState else: "COMPLETED"
    stdout.write(
      $(
        %*[
          {
            "number": 9,
            "title": command & " " & paramStr(4),
            "body": "A **rendered** description.",
            "url": "https://github.com/o/r/issues/9",
            "state": paramStr(4).toUpperAscii(),
            "author": {"login": "tester"},
            "labels": [],
            "isDraft": command == "pr",
            "headRefName": "topic",
            "baseRefName": "main",
            "reviewDecision": "APPROVED",
            "statusCheckRollup": [
              {
                "__typename": "CheckRun",
                "name": "tests",
                "workflowName": "CI",
                "status": jobStatus,
                "conclusion": if jobStatus == "COMPLETED": jobState else: "",
                "detailsUrl": "https://github.com/o/r/actions/runs/12/job/34",
              }
            ],
          }
        ]
      )
    )
  quit(0)
