import std/[json, monotimes, options, os, strutils, tempfiles, times, unittest]
when defined(posix):
  import std/posix

import merenda/kosmo/kosmo

proc hookConfiguration(directory, label: string, waits = false): string =
  result = directory / (label & ".toml")
  let childCommand =
    quoteShell(getAppFilename()) & " --moe-hook-fixture " & quoteShell(label) & " " &
    quoteShell(directory / (label & ".ready")) & (if waits: " wait" else: "")
  writeFile(
    result,
    "[[Hook.entries]]\nevent = 'BufWritePost'\ncommand = " & $(%childCommand) &
      "\nshowOutput = true\ntimeout = 10\n",
  )

proc waitForHookOutput(editor: KosmoEditor, label: string): bool =
  let deadline = getMonoTime() + initDuration(seconds = 20)
  while getMonoTime() < deadline:
    discard editor.pollFrontendWork()
    var request = editor.takeHostCommandRequest()
    while request.isSome:
      if request.get.kind == KosmoHostCommandKind.Output and label in request.get.text:
        return true
      request = editor.takeHostCommandRequest()
    sleep(5)

suite "Kosmo Moe asynchronous work":
  test "write hooks advance without terminal runtime and route output to their editor":
    let directory = createTempDir("kosmo moe hooks ", "")
    defer:
      removeDir(directory)
    let first = newKosmoEditor()
    let second = newKosmoEditor()
    defer:
      first.close()
      second.close()
    for item in [(first, "first"), (second, "second")]:
      let path = directory / (item[1] & ".txt")
      writeFile(path, "original")
      let loaded = item[0].loadHooks(directory.hookConfiguration(item[1]))
      checkpoint loaded.message
      require loaded.loaded
      require item[0].openFile(path).loaded
      require item[0].handleTextInput("A edited")
      require item[0].handleKey("Esc")
      require item[0].save().saved
    check first.waitForHookOutput("first")
    check second.waitForHookOutput("second")
    check first.tabs().len == 1
    check second.tabs().len == 1

  when defined(posix):
    test "closing an editor terminates and reaps an active hook process":
      let directory = createTempDir("kosmo-hook-close-", "")
      defer:
        removeDir(directory)
      let editor = newKosmoEditor()
      defer:
        editor.close()
      let path = directory / "sample.txt"
      writeFile(path, "original")
      require editor.loadHooks(directory.hookConfiguration("slow", waits = true)).loaded
      require editor.openFile(path).loaded
      require editor.handleTextInput("A edited")
      require editor.handleKey("Esc")
      require editor.save().saved
      let ready = directory / "slow.ready"
      let deadline = getMonoTime() + initDuration(seconds = 20)
      while not fileExists(ready) and getMonoTime() < deadline:
        discard editor.pollFrontendWork()
        sleep(5)
      require fileExists(ready)
      let childPid = Pid(parseInt(readFile(ready)))
      require posix.kill(childPid, 0) == 0
      editor.close()
      # close advances cancellation callbacks and ChildProcess reaps the child.
      check posix.kill(childPid, 0) == -1
      check osLastError() == OSErrorCode(ESRCH)
