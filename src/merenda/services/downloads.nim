## Bounded HTTP downloads through the system curl client.

import ./backgroundprocesses

proc downloadUrl*(
    url, userAgent: string,
    timeoutSeconds: Positive = 10,
    maxOutputBytes: Natural = 1024 * 1024,
    cancelled: proc(): bool {.closure, gcsafe.} = nil,
): BackgroundCommandResult =
  runBackgroundCommand(
    "curl",
    ["-fsSL", "--max-time", $timeoutSeconds, "--user-agent", userAgent, "--", url],
    timeoutMilliseconds = (timeoutSeconds + 2) * 1000,
    cancelled = cancelled,
    maxOutputBytes = maxOutputBytes,
    diagnosticName = "HTTP download",
  )
