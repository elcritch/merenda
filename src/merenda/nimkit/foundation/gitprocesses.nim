## Bounded Git commands for background workspace discovery.

import ./backgroundprocesses

type GitCommandResult* = BackgroundCommandResult

proc runGitCommand*(
    root: string,
    args: openArray[string],
    timeoutMilliseconds: Positive = 10_000,
    cancelled: proc(): bool {.closure, gcsafe.} = nil,
    maxOutputBytes: Natural = 128 * 1024 * 1024,
): GitCommandResult =
  ## Disable Git filesystem-monitor hooks; workspace monitoring belongs to us.
  var arguments = @["-C", root, "--no-optional-locks", "-c", "core.fsmonitor=false"]
  arguments.add args
  result = runBackgroundCommand(
    "git",
    arguments,
    timeoutMilliseconds = timeoutMilliseconds,
    cancelled = cancelled,
    maxOutputBytes = maxOutputBytes,
    diagnosticName = "Git workspace command",
  )
  if result.output == "Git workspace command output exceeded the configured limit":
    result.output = "Git output exceeded the configured limit"
