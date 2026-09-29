import std/[os, sequtils, tempfiles, unittest]

import merenda/kosmo/config
import merenda/nimkit/app/documents
import merenda/nimkit/foundation/atomicfiles
import merenda/nimkit/resources/resrccore
import merenda/tekton/editor

when defined(posix):
  import std/[monotimes, osproc, posix, streams, times]
  import ./fixtures/atomicsavefailure

  proc runSaveFailureProbe(kind, path: string) =
    let process = startProcess(
      getAppFilename(),
      args = @[AtomicSaveFailureProbe, kind, path],
      options = {poStdErrToStdOut},
    )
    try:
      let deadline = getMonoTime() + initDuration(seconds = 60)
      var exitCode = process.peekExitCode()
      while exitCode == -1 and getMonoTime() < deadline:
        sleep(5)
        exitCode = process.peekExitCode()
      doAssert exitCode != -1, "atomic save failure probe timed out"
      let output = process.outputStream().readAll()
      doAssert exitCode == 0, output
    finally:
      if process.peekExitCode() == -1:
        process.kill()
      discard process.waitForExit()
      process.close()

suite "Atomic file saves":
  test "replaces and creates files with exact binary contents and no temporary siblings":
    let root = createTempDir("merenda-atomic-save-", "")
    defer:
      removeDir(root)
    let path = root / "contents.cbor"
    atomicWriteFile(path, "old contents")
    let contents = "binary\0data\r\nwith\nnewlines\xFF"
    atomicWriteFile(path, contents)
    check readFile(path) == contents
    check toSeq(walkDir(root)) == @[(pcFile, path)]
    atomicWriteFile(path, "")
    check readFile(path) == ""

  test "failed replacement preserves the target and removes its temporary sibling":
    let root = createTempDir("merenda-atomic-rename-", "")
    defer:
      removeDir(root)
    let path = root / "occupied"
    createDir(path)
    writeFile(path / "original", "keep this")
    expect OSError:
      atomicWriteFile(path, "replacement")
    check readFile(path / "original") == "keep this"
    check toSeq(walkDir(root)) == @[(pcDir, path)]

  test "Kosmo creates parent directories and replaces valid configuration":
    let root = createTempDir("merenda-atomic-config-", "")
    defer:
      removeDir(root)
    let path = root / "nested" / "config.json"
    require KosmoConfig(merendaFont: "original").saveKosmoConfig(path)
    let replacement = KosmoConfig(merendaFont: "replacement", merendaFontSize: 18.0)
    check replacement.saveKosmoConfig(path)
    check loadKosmoConfig(path) == replacement
    check toSeq(walkDir(path.parentDir())) == @[(pcFile, path)]

  test "Tekton preserves dirty state and diagnostics when replacement fails":
    let root = createTempDir("merenda-atomic-document-", "")
    defer:
      removeDir(root)
    let
      path = root / "occupied.cbor"
      originalUrl = root / "original.cbor"
      document = newResourceEditorDocument("atomic-save", fileUrl = originalUrl)
    createDir(path)
    writeFile(path / "original", "keep this")
    document.documentEdited = true
    check not document.saveAs(path)
    check document.isDocumentEdited()
    check document.fileUrl() == originalUrl
    check document.ioDiagnostics().hasErrors()
    check readFile(path / "original") == "keep this"
    check toSeq(walkDir(root)) == @[(pcDir, path)]

  when defined(posix):
    test "replacement preserves existing permission bits":
      let root = createTempDir("merenda-atomic-permissions-", "")
      defer:
        removeDir(root)
      let path = root / "config.json"
      writeFile(path, "original")
      let permissions = {fpUserRead, fpUserWrite, fpGroupRead}
      setFilePermissions(path, permissions)
      atomicWriteFile(path, "replacement")
      check readFile(path) == "replacement"
      check getFilePermissions(path) == permissions

    test "read-only files keep their contents and permissions":
      if geteuid() != 0:
        let root = createTempDir("merenda-atomic-read-only-", "")
        defer:
          removeDir(root)
        let path = root / "config.json"
        writeFile(path, "original")
        setFilePermissions(path, {fpUserRead})
        expect OSError:
          atomicWriteFile(path, "replacement")
        check readFile(path) == "original"
        check getFilePermissions(path) == {fpUserRead}
        check toSeq(walkDir(root)) == @[(pcFile, path)]

    test "special files cannot be replaced by regular files":
      let root = createTempDir("merenda-atomic-special-", "")
      defer:
        removeDir(root)
      let path = root / "pipe"
      require mkfifo(path.cstring, Mode(S_IRUSR or S_IWUSR)) == 0
      expect IOError:
        atomicWriteFile(path, "replacement")
      check getFileInfo(path).isSpecial
      check toSeq(walkDir(root)).len == 1

    test "saves through relative symbolic links without replacing the links":
      let root = createTempDir("merenda-atomic-symlink-", "")
      defer:
        removeDir(root)
      let
        target = root / "target.json"
        link = root / "config.json"
      writeFile(target, "original")
      createSymlink("target.json", link)
      atomicWriteFile(link, "replacement")
      check symlinkExists(link)
      check expandSymlink(link) == "target.json"
      check readFile(target) == "replacement"
      check toSeq(walkDir(root)).len == 2
      removeFile(target)
      atomicWriteFile(link, "created through link")
      check symlinkExists(link)
      check readFile(target) == "created through link"

    test "buffered close failures preserve existing contents and remove temporary files":
      let root = createTempDir("merenda-atomic-close-failure-", "")
      defer:
        removeDir(root)
      let path = root / "original"
      writeFile(path, "original contents")
      runSaveFailureProbe("buffered", path)
      check readFile(path) == "original contents"
      check toSeq(walkDir(root)) == @[(pcFile, path)]

    test "partial writes preserve existing contents and remove temporary files":
      let root = createTempDir("merenda-atomic-write-failure-", "")
      defer:
        removeDir(root)
      let path = root / "original"
      writeFile(path, "original contents")
      runSaveFailureProbe("large", path)
      check readFile(path) == "original contents"
      check toSeq(walkDir(root)) == @[(pcFile, path)]

    test "a failed first save leaves no destination or temporary files":
      let root = createTempDir("merenda-atomic-new-failure-", "")
      defer:
        removeDir(root)
      let path = root / "new"
      runSaveFailureProbe("buffered", path)
      check not fileExists(path)
      check toSeq(walkDir(root)).len == 0

    test "Kosmo preserves saved JSON when a buffered write fails":
      let root = createTempDir("merenda-atomic-config-failure-", "")
      defer:
        removeDir(root)
      let path = root / "config.json"
      let config = KosmoConfig(merendaFont: "original")
      require config.saveKosmoConfig(path)
      let contents = readFile(path)
      runSaveFailureProbe("config", path)
      check readFile(path) == contents
      check loadKosmoConfig(path) == config
      check toSeq(walkDir(root)) == @[(pcFile, path)]

    test "Tekton preserves saved CBOR and document state when a partial write fails":
      let root = createTempDir("merenda-atomic-document-failure-", "")
      defer:
        removeDir(root)
      let path = root / "document.cbor"
      let document = newResourceEditorDocument("original", fileUrl = path)
      require document.save()
      let contents = readFile(path)
      runSaveFailureProbe("tekton", path)
      check readFile(path) == contents
      check toSeq(walkDir(root)) == @[(pcFile, path)]
