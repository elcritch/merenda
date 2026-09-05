import std/[os, osproc, strutils, tempfiles, unittest]

import regex
import sigils/core

import merenda/nimkit/foundation/filesearch

type FileSearchSpy = ref object of Agent
  finishedIdentifiers: seq[uint64]
  batchIdentifiers: seq[uint64]
  batchMatches: seq[seq[FileSearchMatch]]
  batchWasFinished: seq[bool]

type LateFileSearchSpy = ref object of Agent
  path: string
  createdFile: bool
  batchWasFinished: bool

proc rememberFinishedSearch(spy: FileSearchSpy, handle: FileSearchHandle) {.slot.} =
  spy.finishedIdentifiers.add handle.identifier()

proc rememberSearchMatches(
    spy: FileSearchSpy, handle: FileSearchHandle, matches: seq[FileSearchMatch]
) {.slot.} =
  spy.batchIdentifiers.add handle.identifier()
  spy.batchMatches.add matches
  spy.batchWasFinished.add handle.isFinished()

proc createMatchAfterFirstBatch(
    spy: LateFileSearchSpy, handle: FileSearchHandle, matches: seq[FileSearchMatch]
) {.slot.} =
  discard matches
  if not spy.createdFile:
    spy.batchWasFinished = handle.isFinished()
    writeFile(spy.path, "late needle\n")
    spy.createdFile = true

proc runSearch(
    service: FileSearchService, root, pattern: string, options = initFileSearchOptions()
): FileSearchHandle =
  result = service.search(initFileSearchQuery(root, pattern, options))
  check service.waitFor(result, timeoutMilliseconds = 10_000)

suite "nimkit memory-mapped file search":
  test "multiple overlapping roots share result and file limits":
    let
      workspace = createTempDir("merenda-search-roots-", "")
      first = workspace / "first"
      second = workspace / "second"
      service = newFileSearchService()
    createDir(first / "nested")
    createDir(second)
    writeFile(first / "nested" / "a.txt", "needle")
    writeFile(second / "b.txt", "needle")
    defer:
      service.close()
      removeDir(workspace)
    let roots = @[first, first / "nested", second, second / "."]
    let all = service.search(initFileSearchQuery(roots, "needle"))
    require service.waitFor(all)
    check all.result().matches.len == 2
    check all.result().stats.discoveredFileCount == 2
    let limited = service.search(
      initFileSearchQuery(roots, "needle", initFileSearchOptions(maxResults = 1))
    )
    require service.waitFor(limited)
    check limited.result().matches.len == 1
    check limited.result().reason == fsfrResultLimitReached
    let fileLimited = service.search(
      initFileSearchQuery(roots, "needle", initFileSearchOptions(maxFiles = 1))
    )
    require service.waitFor(fileLimited)
    check fileLimited.result().stats.discoveredFileCount == 1
    check fileLimited.result().reason == fsfrFileLimitReached

  test "searches nested files on a Sigils worker and reports mmap usage":
    let
      root = createTempDir("merenda-file-search-", "")
      nested = root / "nested"
      service = newFileSearchService(workers = 2)
      spy = FileSearchSpy()
    createDir(nested)
    writeFile(root / "alpha.txt", "Alpha needle\nsecond NEEDLE\nneedle twice needle\n")
    writeFile(nested / "beta.nim", "let needleValue = 1\n")
    writeFile(root / ".hidden.txt", "needle\n")
    service.connect(fileSearchDidFinish, spy, rememberFinishedSearch)

    try:
      let
        options = initFileSearchOptions(caseSensitive = false)
        handle = service.runSearch(root, "needle", options)
        searchResult = handle.result()

      check searchResult.reason == fsfrCompleted
      check searchResult.matches.len == 5
      check searchResult.matches[0].path == root / "alpha.txt"
      check searchResult.matches[0].line == 1
      check searchResult.matches[0].column == 7
      check searchResult.matches[0].byteOffset == 6
      check searchResult.matches[0].matchLength == 6
      check searchResult.matches[0].lineText == "Alpha needle"
      check searchResult.matches[^1].path == nested / "beta.nim"
      check searchResult.stats.workerThreadId != getThreadId()
      check searchResult.stats.discoveredFileCount == 2
      check searchResult.stats.searchedFileCount == 2
      check searchResult.stats.mappedFileCount == 2
      check searchResult.stats.bytesSearched > 0
      check spy.finishedIdentifiers == @[handle.identifier()]
    finally:
      service.close()
      removeDir(root)

  test "uses Git tracked and untracked non-ignored files by default":
    let
      root = createTempDir("merenda-file-search-git-ignore-", "")
      ignoredDirectory = root / "build"
      service = newFileSearchService(workers = 1)
    createDir(ignoredDirectory)
    writeFile(root / ".gitignore", "build/\n")
    writeFile(root / "tracked.nim", "tracked needle\n")
    writeFile(root / "untracked.nim", "untracked needle\n")
    writeFile(ignoredDirectory / "generated.nim", "ignored needle\n")
    discard execProcess(
      "git",
      workingDir = root,
      args = ["init", "-q"],
      options = {poUsePath, poStdErrToStdOut},
    )
    discard execProcess(
      "git",
      workingDir = root,
      args = ["add", "tracked.nim"],
      options = {poUsePath, poStdErrToStdOut},
    )
    require dirExists(root / ".git")

    try:
      block defaultOptions:
        let searchResult = service.runSearch(root, "needle").result()
        check searchResult.reason == fsfrCompleted
        check searchResult.matches.len == 2
        check searchResult.matches[0].path == root / "tracked.nim"
        check searchResult.matches[1].path == root / "untracked.nim"

      block includeIgnored:
        let
          options = initFileSearchOptions(respectGitIgnore = false)
          searchResult = service.runSearch(root, "needle", options).result()
        check searchResult.reason == fsfrCompleted
        check searchResult.matches.len == 3
        check searchResult.matches[^1].path == ignoredDirectory / "generated.nim"
    finally:
      service.close()
      removeDir(root)

  test "skips non-text MIME types and unsupported encodings by default":
    let
      root = createTempDir("merenda-file-search-content-type-", "")
      service = newFileSearchService(workers = 1)
    writeFile(root / "plain.txt", "plain needle\n")
    writeFile(root / "source.dart", "source needle\n")
    writeFile(root / "misleading.png", "image needle\n")
    writeFile(root / "binary.dat", "blob\0needle\n")
    writeFile(root / "invalid.txt", "\xffneedle\n")

    try:
      block defaultOptions:
        let searchResult = service.runSearch(root, "needle").result()
        check searchResult.reason == fsfrCompleted
        check searchResult.matches.len == 2
        check searchResult.matches[0].path == root / "plain.txt"
        check searchResult.matches[1].path == root / "source.dart"
        check searchResult.stats.discoveredFileCount == 5
        check searchResult.stats.searchedFileCount == 2
        check searchResult.stats.skippedNonTextFileCount == 3

      block includeBinaryFiles:
        let
          options = initFileSearchOptions(includeBinaryFiles = true)
          searchResult = service.runSearch(root, "needle", options).result()
        check searchResult.reason == fsfrCompleted
        check searchResult.matches.len == 5
        check searchResult.stats.searchedFileCount == 5
        check searchResult.stats.skippedNonTextFileCount == 0
    finally:
      service.close()
      removeDir(root)

  test "skips oversized files before opening a memory map":
    let
      root = createTempDir("merenda-file-search-large-", "")
      service = newFileSearchService(workers = 1)
    writeFile(root / "small.txt", "find me\n")
    writeFile(root / "large.txt", repeat('x', 1_024) & "find me\n")

    try:
      let
        options = initFileSearchOptions(maxFileSizeBytes = 64)
        searchResult = service.runSearch(root, "find me", options).result()

      check searchResult.reason == fsfrCompleted
      check searchResult.matches.len == 1
      check searchResult.matches[0].path == root / "small.txt"
      check searchResult.stats.discoveredFileCount == 2
      check searchResult.stats.skippedLargeFileCount == 1
      check searchResult.stats.searchedFileCount == 1
      check searchResult.stats.mappedFileCount == 1
    finally:
      service.close()
      removeDir(root)

  test "streams bounded match batches before search completion":
    let
      root = createTempDir("merenda-file-search-stream-", "")
      service = newFileSearchService(workers = 1)
      spy = FileSearchSpy()
      contents = repeat("needle\n", 130)
    writeFile(root / "matches.txt", contents)
    service.connect(fileSearchDidFindMatches, spy, rememberSearchMatches)
    service.connect(fileSearchDidFinish, spy, rememberFinishedSearch)

    try:
      let
        handle = service.runSearch(root, "needle")
        searchResult = handle.result()
      var streamedMatches: seq[FileSearchMatch]
      for batch in spy.batchMatches:
        streamedMatches.add batch

      check spy.batchMatches.len > 1
      for batch in spy.batchMatches:
        check batch.len in 1 .. 64
      for identifier in spy.batchIdentifiers:
        check identifier == handle.identifier()
      for wasFinished in spy.batchWasFinished:
        check not wasFinished
      check streamedMatches == searchResult.matches
      check spy.finishedIdentifiers == @[handle.identifier()]
    finally:
      service.close()
      removeDir(root)

  test "starts scanning before recursive file discovery finishes":
    let
      root = createTempDir("merenda-file-search-discovery-stream-", "")
      nested = root / "nested"
      latePath = nested / "late.txt"
      service = newFileSearchService(workers = 1)
      spy = LateFileSearchSpy(path: latePath)
    createDir(nested)
    writeFile(root / "first.txt", "needle\n" & repeat('x', 2 * 1024 * 1024))
    service.connect(fileSearchDidFindMatches, spy, createMatchAfterFirstBatch)

    try:
      let searchResult = service.runSearch(root, "needle").result()

      check spy.createdFile
      check not spy.batchWasFinished
      check searchResult.matches.len == 2
      check searchResult.matches[0].path == root / "first.txt"
      if searchResult.matches.len == 2:
        check searchResult.matches[1].path == latePath
    finally:
      service.close()
      removeDir(root)

  test "enforces global and per-file result limits":
    let
      root = createTempDir("merenda-file-search-limits-", "")
      service = newFileSearchService(workers = 1)
    writeFile(root / "first.txt", "hit hit hit hit hit\n")
    writeFile(root / "second.txt", "hit\n")

    try:
      block globalLimit:
        let
          options = initFileSearchOptions(maxResults = 3)
          searchResult = service.runSearch(root, "hit", options).result()
        check searchResult.reason == fsfrResultLimitReached
        check searchResult.matches.len == 3

      block perFileLimit:
        let
          options = initFileSearchOptions(maxResults = 10, maxMatchesPerFile = 2)
          searchResult = service.runSearch(root, "hit", options).result()
        check searchResult.reason == fsfrCompleted
        check searchResult.matches.len == 3
        check searchResult.stats.limitedFileCount == 1
        check searchResult.matches[^1].path == root / "second.txt"
    finally:
      service.close()
      removeDir(root)

  test "honors traversal options and searches up to the file-count limit":
    let
      root = createTempDir("merenda-file-search-traversal-", "")
      nested = root / "nested"
      service = newFileSearchService(workers = 1)
    createDir(nested)
    writeFile(root / ".hidden.txt", "found\n")
    writeFile(root / "first.txt", "found\n")
    writeFile(root / "second.txt", "found\n")
    writeFile(nested / "third.txt", "found\n")

    try:
      block traversalOptions:
        let
          options = initFileSearchOptions(recursive = false, includeHidden = true)
          searchResult = service.runSearch(root, "found", options).result()
        check searchResult.reason == fsfrCompleted
        check searchResult.matches.len == 3
        check searchResult.stats.discoveredFileCount == 3

      block fileLimit:
        let
          options =
            initFileSearchOptions(includeHidden = true, maxFiles = 2, maxResults = 10)
          searchResult = service.runSearch(root, "found", options).result()
        check searchResult.reason == fsfrFileLimitReached
        check searchResult.matches.len == 2
        check searchResult.stats.discoveredFileCount == 2
        check searchResult.stats.mappedFileCount == 2
    finally:
      service.close()
      removeDir(root)

  test "cancellation stops queued or active mmap searches":
    let
      root = createTempDir("merenda-file-search-cancel-", "")
      service = newFileSearchService(workers = 1)
      contents = repeat("searchable source text without the requested token\n", 2_048)
    for index in 0 ..< 64:
      writeFile(root / ("source-" & $index & ".txt"), contents)

    try:
      let handle = service.search(initFileSearchQuery(root, "missing-pattern"))
      handle.cancel()

      check handle.cancelRequested()
      check service.waitFor(handle, timeoutMilliseconds = 10_000)
      check handle.result().reason == fsfrCancelled
      check handle.result().matches.len == 0
    finally:
      service.close()
      removeDir(root)

  test "validates roots patterns and configured limits before queuing work":
    let
      root = createTempDir("merenda-file-search-validation-", "")
      service = newFileSearchService(workers = 1)
    try:
      expect IOError:
        discard service.search(initFileSearchQuery(root / "missing", "value"))
      expect ValueError:
        discard service.search(initFileSearchQuery(root, ""))
      expect RegexError:
        discard service.search(initFileSearchQuery(root, "("))
      expect ValueError:
        var options = initFileSearchOptions()
        options.maxResults = 0
        discard service.search(initFileSearchQuery(root, "value", options))
    finally:
      service.close()
      removeDir(root)

  test "closing the service cancels outstanding handles":
    let
      root = createTempDir("merenda-file-search-close-", "")
      service = newFileSearchService(workers = 1)
      contents = repeat("one more searchable line\n", 4_096)
    for index in 0 ..< 32:
      writeFile(root / ("source-" & $index & ".txt"), contents)

    let handle = service.search(initFileSearchQuery(root, "not-present"))
    service.close()
    try:
      check handle.isFinished()
      check handle.result().reason == fsfrCancelled
      expect FileSearchClosedError:
        discard service.search(initFileSearchQuery(root, "value"))
    finally:
      removeDir(root)
