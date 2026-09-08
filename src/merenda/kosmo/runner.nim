## Standalone Kosmo process startup and command-line dispatch.

import std/[options, os]

import ./[application, cli, cliopen]

proc runKosmo*(paths: openArray[string]) =
  ## Run Kosmo as a standalone NimKit text-editor application.
  if paths.len == 0:
    runKosmoRequest(none(KosmoCliOpenRequest))
  else:
    runKosmoRequest(
      some(
        KosmoCliOpenRequest(
          requestId: randomIdentifier(), kind: kcrOpenPaths, paths: @paths
        )
      )
    )

proc runKosmoDiff*(content: string, workingDirectory = getCurrentDir()) =
  ## Run Kosmo with a static Git Diff view populated from standard input.
  runKosmoRequest(
    some(
      KosmoCliOpenRequest(
        requestId: randomIdentifier(),
        kind: kcrShowDiff,
        workingDirectory: workingDirectory,
        diffText: content,
      )
    )
  )

proc runKosmo*(filePath = "") =
  ## Compatibility overload for callers opening one initial path.
  if filePath.len > 0:
    runKosmo([filePath])
  else:
    runKosmo(newSeq[string]())

proc reportCliErrors(errors: openArray[string]) =
  for message in errors:
    stderr.writeLine(message)

proc runKosmoMain*() =
  ## Dispatch Kosmo's standalone command line.
  let commandLine = parseKosmoCommandLine(commandLineParams())
  if commandLine.help:
    echo KosmoUsage
  elif commandLine.version:
    echo KosmoVersion
  elif commandLine.errors.len > 0:
    reportCliErrors(commandLine.errors)
    quit(1)
  elif commandLine.stdinName.len > 0:
    if kosmoCliInputIsTerminal():
      stderr.writeLine("Kosmo --file reads text from standard input")
      quit(1)
    var content: string
    try:
      content = stdin.readKosmoCliText()
    except CatchableError as error:
      stderr.writeLine(error.msg)
      quit(1)
    let directory = getCurrentDir()
    let response = openStdinInRunningKosmo(commandLine.stdinName, content, directory)
    if response.delivered:
      reportCliErrors(response.errors)
      quit(if response.errors.len == 0: 0 else: 1)
    if commandLine.background:
      stderr.writeLine("Kosmo --bg --file requires a running Kosmo instance")
      quit(1)
    runKosmoRequest(
      some(
        KosmoCliOpenRequest(
          requestId: randomIdentifier(),
          kind: kcrOpenStdin,
          stdinName: commandLine.stdinName,
          stdinText: content,
          workingDirectory: directory,
        )
      )
    )
  elif commandLine.diff:
    if commandLine.paths.len > 0:
      stderr.writeLine("Kosmo --diff does not accept file or folder arguments")
      quit(1)
    if kosmoCliInputIsTerminal():
      stderr.writeLine("Kosmo --diff reads a unified Git diff from standard input")
      quit(1)
    var content: string
    try:
      content = stdin.readKosmoCliDiff()
    except CatchableError as error:
      stderr.writeLine(error.msg)
      quit(1)
    let workingDirectory = getCurrentDir()
    let response = showDiffInRunningKosmo(content, workingDirectory)
    if response.delivered:
      reportCliErrors(response.errors)
      quit(if response.errors.len == 0: 0 else: 1)
    if commandLine.background:
      stderr.writeLine(
        "Kosmo --bg --diff requires a running Kosmo instance to receive the pipe"
      )
      quit(1)
    runKosmoDiff(content, workingDirectory)
  else:
    let paths = resolveKosmoCliPaths(commandLine.paths)
    if paths.errors.len > 0:
      reportCliErrors(paths.errors)
      quit(1)
    if paths.paths.len > 0:
      let response = openInRunningKosmo(paths.paths)
      if response.delivered:
        reportCliErrors(response.errors)
        quit(if response.errors.len == 0: 0 else: 1)
    if commandLine.background:
      var arguments: seq[string]
      if paths.paths.len > 0:
        arguments.add "--"
        arguments.add paths.paths
      launchKosmoInBackground(arguments)
    else:
      runKosmo(paths.paths)
