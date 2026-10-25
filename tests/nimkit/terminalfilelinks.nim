import std/[options, os, strutils, tempfiles, unittest, uri]

import merenda/nimkit/terminal/terminalfilelinks

proc fileUrl(path: string, host = "localhost"): string =
  var uriPath = path.replace('\\', '/')
  if not uriPath.startsWith('/'):
    uriPath = "/" & uriPath
  "file://" & host & uriPath.encodeUrl(usePlus = false).replace("%2F", "/")

suite "terminal file locations":
  test "existing absolute and relative files resolve with source positions":
    let root = createTempDir("merenda-terminal-links-", "")
    defer:
      removeDir(root)
    createDir(root / "src")
    let path = root / "src" / "hello.nim"
    writeFile(path, "first\nsecond\n")
    for text in [path, "src/hello.nim", "./src/hello.nim"]:
      for suffix in ["", ":2", ":2:4", "(2)", "(2,4)", "(2, 4)"]:
        let location = resolveTerminalFileLocation(text & suffix, root)
        require location.isSome
        check location.get().path == normalizedPath(path)
        check location.get().line == (if suffix.len > 0: 2 else: 0)
        check location.get().column ==
          (if suffix in [":2:4", "(2,4)", "(2, 4)"]: 4 else: 0)

  test "CLI resolution can retain source positions when creating a missing file":
    let root = createTempDir("merenda-terminal-new-file-", "")
    defer:
      removeDir(root)
    for suffix in ["", ":2", ":2:4", "(2)", "(2, 4)"]:
      let text = "new.nim" & suffix
      check resolveTerminalFileLocation(text, root).isNone
      let location = resolveTerminalFileLocation(text, root, allowMissing = true)
      require location.isSome
      check location.get().path == root / "new.nim"
      check location.get().line == (if suffix.len > 0: 2 else: 0)
    require resolveTerminalFileLocation("new (copy)", root, allowMissing = true).isSome

  test "OSC file links and current directories decode spaces and Unicode":
    let root = createTempDir("merenda-terminal-links-", "")
    defer:
      removeDir(root)
    let path = root / "hello λ %.nim"
    writeFile(path, "source")
    for text in [path, path.extractFilename(), fileUrl(path)]:
      let location = resolveTerminalFileLocation(text & ":2:4", fileUrl(root))
      require location.isSome
      check location.get().path == normalizedPath(path)
      check location.get().line == 2
      check location.get().column == 4

  test "missing files remote URLs directories and invalid positions are ignored":
    let root = createTempDir("merenda-terminal-links-", "")
    defer:
      removeDir(root)
    let path = root / "source.nim"
    writeFile(path, "source")
    for text in [
      root,
      "missing.nim",
      "source.nim:0",
      "source.nim:2:0",
      "source.nim:-1",
      "source.nim:2:no",
      "source.nim:999999999999999999999999",
      "source.nim(0)",
      "source.nim(2, 0)",
      "source.nim(-1, 2)",
      "source.nim(2, 3, 4)",
      "source.nim(999999999999999999999999)",
      fileUrl(path, "remote.invalid"),
      "https://example.com/source.nim:2:4",
    ]:
      check resolveTerminalFileLocation(text, root).isNone
    check resolveTerminalFileLocation("source.nim", fileUrl(root, "remote.invalid")).isNone

  when not defined(windows):
    test "literal colons in existing file names take precedence over positions":
      let root = createTempDir("merenda-terminal-links-", "")
      defer:
        removeDir(root)
      let path = root / "source.nim:2:4"
      writeFile(path, "source")
      let location = resolveTerminalFileLocation("source.nim:2:4", root)
      require location.isSome
      check location.get().path == path
      check location.get().line == 0

  test "literal parenthesized file names take precedence over positions":
    let root = createTempDir("merenda-terminal-parenthesized-", "")
    defer:
      removeDir(root)
    let path = root / "source.nim(2, 4)"
    writeFile(path, "source")
    let location = resolveTerminalFileLocation("source.nim(2, 4)", root)
    require location.isSome
    check location.get().path == path
    check location.get().line == 0
