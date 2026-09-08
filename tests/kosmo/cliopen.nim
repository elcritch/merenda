## Kosmo window-routing behavior for command-line open requests.

import std/[options, os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc hasOpenPath(frontend: KosmoApplication, path: string): bool =
  for tab in frontend.editorView.editor.tabs():
    if tab.filePath == some(path):
      return true

suite "Kosmo CLI window routing":
  test "stdin creates separate modified buffers without changing existing files":
    let root = createTempDir("kosmo-stdin-", "")
    let manager = newKosmoWindowManager(newApplication("Stdin files"))
    let frontend = newKosmoApplication(manager, root, monitorsGitStatus = false)
    defer:
      manager.close()
      removeDir(root)
    writeFile(root / "output.py", "original\n")
    require frontend.openPath(root / "output.py")
    let originalCount = frontend.editorView.editor.tabs().len
    for content in ["def answer():\n  return 42\n", ""]:
      let response = manager.openCliRequestForTesting(
        KosmoCliOpenRequest(
          requestId: "stdin",
          kind: kcrOpenStdin,
          stdinName: "output.py",
          stdinText: content,
          workingDirectory: root,
          originWindow: frontend.cliWindowId(),
        )
      )
      check response.delivered
      check response.errors.len == 0
      let tabs = frontend.editorView.editor.tabs()
      for tab in tabs:
        if tab.active:
          check tab.modified
          check tab.filePath == some(root / "output.py")
          # Moe stores the final newline in its endOfLine flag, outside the lines.
          var lines = content
          lines.removeSuffix("\n")
          check frontend.editorView.editor.bufferText(tab.id) == some(lines)
      check readFile(root / "output.py") == "original\n"
    check frontend.editorView.editor.tabs().len == originalCount + 2
    let editor = frontend.editorView.editor
    for content in ["hello\n", "hello", ""]:
      require editor.newStdinBuffer("saved.txt", content, root).isSome
      discard editor.save()
      require fileExists(root / "saved.txt")
      check readFile(root / "saved.txt") == content

  test "an embedded terminal targets its owning project window":
    let
      firstRoot = createTempDir("merenda-kosmo-cli-first-", "")
      secondRoot = createTempDir("merenda-kosmo-cli-second-", "")
      firstFile = firstRoot / "first.nim"
      secondFile = secondRoot / "second.nim"
      app = newApplication("Kosmo CLI origin")
      manager = newKosmoWindowManager(app)
      first = newKosmoApplication(manager, firstRoot, monitorsGitStatus = false)
      second = newKosmoApplication(manager, secondRoot, monitorsGitStatus = false)
    defer:
      manager.close()
      removeDir(firstRoot)
      removeDir(secondRoot)
    writeFile(firstFile, "discard")
    writeFile(secondFile, "discard")
    second.show()

    let response = manager.openCliRequestForTesting(
      KosmoCliOpenRequest(
        requestId: "origin", paths: @[firstFile], originWindow: first.cliWindowId()
      )
    )
    check response.delivered
    check response.errors.len == 0
    check first.hasOpenPath(firstFile)
    check not second.hasOpenPath(firstFile)

  test "folders create one new multi-root project window for the request":
    let
      firstRoot = createTempDir("merenda-kosmo-cli-project-a-", "")
      secondRoot = createTempDir("merenda-kosmo-cli-project-b-", "")
      filePath = secondRoot / "opened.nim"
      app = newApplication("Kosmo CLI projects")
      manager = newKosmoWindowManager(app)
      existing = newKosmoApplication(manager, monitorsGitStatus = false)
    defer:
      manager.close()
      removeDir(firstRoot)
      removeDir(secondRoot)
    writeFile(filePath, "discard")
    existing.show()

    let response = manager.openCliRequestForTesting(
      KosmoCliOpenRequest(
        requestId: "folders", paths: @[firstRoot, filePath, secondRoot]
      )
    )
    check response.delivered
    check response.errors.len == 0
    let windows = manager.managedWindows()
    require windows.len == 2
    let project = windows[^1]
    check project.fileTree.rootPaths == @[firstRoot, secondRoot]
    check project.hasOpenPath(filePath)
    check not existing.hasOpenPath(filePath)

  test "a file request without a window creates an editor-only destination":
    let
      root = createTempDir("merenda-kosmo-cli-file-window-", "")
      filePath = root / "new-file.nim"
      manager = newKosmoWindowManager(newApplication("Kosmo CLI file"))
    defer:
      manager.close()
      removeDir(root)

    let response = manager.openCliRequestForTesting(
      KosmoCliOpenRequest(requestId: "file", paths: @[filePath])
    )
    check response.delivered
    check response.errors.len == 0
    let windows = manager.managedWindows()
    require windows.len == 1
    check not windows[0].hasFileBrowser()
    check windows[0].hasOpenPath(filePath)

  test "a piped diff targets its originating window and opens the Git Diff tab":
    let
      root = createTempDir("merenda-kosmo-cli-piped-diff-", "")
      app = newApplication("Kosmo CLI piped diff")
      manager = newKosmoWindowManager(app)
      origin = newKosmoApplication(manager, root, monitorsGitStatus = false)
      active = newKosmoApplication(manager, monitorsGitStatus = false)
      diffText =
        "diff --git a/source.nim b/source.nim\n" & "--- a/source.nim\n+++ b/source.nim\n" &
        "@@ -1 +1 @@\n-let value = 1\n+let value = 2\n"
    defer:
      manager.close()
      removeDir(root)
    origin.show()
    active.show()

    let response = manager.openCliRequestForTesting(
      KosmoCliOpenRequest(
        requestId: "piped-diff",
        kind: kcrShowDiff,
        originWindow: origin.cliWindowId(),
        workingDirectory: root,
        diffText: diffText,
      )
    )
    check response.delivered
    check response.errors.len == 0
    require not origin.gitDiffPanel.isNil
    require origin.gitDiffPanel.waitForDiff()
    check active.gitDiffPanel.isNil
    check origin.gitDiffPanel.snapshot.source == gdsStandardInput
    check origin.gitDiffPanel.snapshot.rootPath == root
    require origin.gitDiffPanel.snapshot.files.len == 1
    check origin.gitDiffPanel.snapshot.files[0].path == "source.nim"
    check origin.gitDiffPanel.snapshot.files[0].additions == 1
    check origin.gitDiffPanel.snapshot.files[0].deletions == 1
    check not origin.gitDiffPanel.refreshButton.enabled
    check origin.documentTabs.selectedDocumentTabIdentifier == KosmoGitDiffTabIdentifier
