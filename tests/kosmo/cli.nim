## Kosmo standalone command-line handling shared by the Kosmo test runner.
import std/[os, tempfiles, times, unittest]

import merenda/kosmo/cli

suite "Kosmo command line":
  test "background launch removes every background flag and keeps other arguments":
    let commandLine = parseKosmoCommandLine(
      @["--bg", "notes.md", "--literal", "--bg", "with spaces.md"]
    )
    check commandLine.background
    check not commandLine.help
    check commandLine.arguments == @["notes.md", "--literal", "with spaces.md"]
    check commandLine.filePath == "notes.md"

  test "background child arguments cannot request another background launch":
    let parent = parseKosmoCommandLine(@["project", "--bg", "README.md"])
    let child = parseKosmoCommandLine(parent.arguments)
    check parent.background
    check not child.background
    check child.arguments == @["project", "README.md"]
    check child.filePath == "project"

  test "double dash preserves a dash-prefixed path without restarting in background":
    let parent = parseKosmoCommandLine(@["--bg", "--", "--bg"])
    let child = parseKosmoCommandLine(parent.arguments)
    check parent.background
    check parent.arguments == @["--", "--bg"]
    check parent.filePath == "--bg"
    check not child.background
    check child.arguments == @["--", "--bg"]
    check child.filePath == "--bg"

  test "the first non-option remains the target path":
    let commandLine = parseKosmoCommandLine(@["", "later", "--bg"])
    check commandLine.background
    check commandLine.arguments == @["", "later"]
    check commandLine.filePath == ""

  test "help does not become an editor path":
    let commandLine = parseKosmoCommandLine(@["--bg", "--help"])
    check commandLine.background
    check commandLine.help
    check commandLine.arguments.len == 0
    check commandLine.filePath.len == 0

  when not defined(windows):
    test "detached launcher preserves the requested directory and arguments":
      let root = createTempDir("merenda-kosmo-bg-", "")
      defer:
        removeDir(root)
      let
        helperPath = root / "record.sh"
        outputPath = root / "output.txt"
        commandLine = parseKosmoCommandLine(
          @[helperPath, outputPath, "argument with spaces", "--bg"]
        )
      writeFile(
        helperPath,
        """#!/bin/sh
printf '%s\n' "$PWD" > "$1"
printf '%s\n' "$2" >> "$1"
""",
      )
      launchKosmoInBackground("/bin/sh", commandLine.arguments, root)

      let deadline = epochTime() + 2.0
      while not fileExists(outputPath) and epochTime() < deadline:
        sleep(10)
      require fileExists(outputPath)
      check readFile(outputPath) == expandFilename(root) & "\nargument with spaces\n"
