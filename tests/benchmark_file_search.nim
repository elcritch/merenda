## Measures mmap-backed regular-expression search throughput.
##
## Run with:
##   nim r -d:release tests/benchmark_file_search.nim
##
## This diagnostic benchmark has no timing threshold because filesystem caches,
## storage, and CI hardware vary substantially.

import std/[monotimes, os, strformat, strutils, tempfiles, times]

import merenda/nimkit/foundation/filesearch

const
  FileCount = 128
  LinesPerFile = 2_048

proc benchmarkContents(fileIndex: int): string =
  result = newStringOfCap(LinesPerFile * 80)
  for line in 0 ..< LinesPerFile:
    if line mod 64 == 0:
      result.add &"source {fileIndex:03} line {line:04} TODO(search-target)"
    else:
      result.add &"source {fileIndex:03} line {line:04} ordinary searchable source text"
    result.add '\n'

let
  root = createTempDir("merenda-file-search-benchmark-", "")
  service = newFileSearchService(workers = 4)
try:
  for fileIndex in 0 ..< FileCount:
    writeFile(root / &"source-{fileIndex:03}.nim", benchmarkContents(fileIndex))

  let
    startedAt = getMonoTime()
    handle = service.search(initFileSearchQuery(root, r"TODO\([^)]*\)"))
  doAssert service.waitFor(handle, timeoutMilliseconds = 60_000)
  let
    elapsed = getMonoTime() - startedAt
    searchResult = handle.result()
    seconds = max(elapsed.inNanoseconds.float / 1_000_000_000.0, 0.000_001)
    mibibytes = searchResult.stats.bytesSearched.float / (1024.0 * 1024.0)

  doAssert searchResult.reason == fsfrCompleted
  doAssert searchResult.stats.mappedFileCount == FileCount
  echo "Memory-mapped file search"
  echo &"files             {searchResult.stats.searchedFileCount:>9}"
  echo &"matches           {searchResult.matches.len:>9}"
  echo &"searched           {mibibytes:>8.2f} MiB"
  echo &"elapsed            {seconds * 1_000.0:>8.2f} ms"
  echo &"throughput         {mibibytes / seconds:>8.2f} MiB/s"
finally:
  service.close()
  removeDir(root)
