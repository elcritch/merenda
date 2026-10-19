## Small child executable used by the Moe hook lifecycle integration tests.
import std/[monotimes, os, times]

if paramCount() >= 3 and paramStr(1) == "--moe-hook-fixture":
  let ready = paramStr(3)
  # File existence must mean the parent can read a complete PID.
  writeFile(ready & ".tmp", $getCurrentProcessId())
  moveFile(ready & ".tmp", ready)
  echo "hook output: " & paramStr(2)
  if paramCount() == 4 and paramStr(4) == "wait":
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while not fileExists(paramStr(3) & ".finish") and getMonoTime() < deadline:
      sleep(5)
  quit(0)
