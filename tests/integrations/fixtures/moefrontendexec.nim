## Small child executable used by the Moe hook lifecycle integration tests.
import std/[monotimes, os, times]

if paramCount() >= 3 and paramStr(1) == "--moe-hook-fixture":
  writeFile(paramStr(3), $getCurrentProcessId())
  echo "hook output: " & paramStr(2)
  if paramCount() == 4 and paramStr(4) == "wait":
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while not fileExists(paramStr(3) & ".finish") and getMonoTime() < deadline:
      sleep(5)
  quit(0)
