## Git-aware filtering for native workspace notifications, run on a worker.

import std/[os, strutils, tables]
import ../nimkit/foundation/gitprocesses

proc directoryAliases(directories: openArray[string]): seq[string] =
  for directory in directories:
    result.add directory
    try:
      # dmon resolves watch roots (for example /var -> /private/var on macOS),
      # while the workspace retains the path the user opened.
      let resolved = expandFilename(directory)
      if resolved != directory:
        result.add resolved
    except OSError:
      discard

proc hasRelevantRepositoryChanges*(paths, roots, metadata: openArray[string]): bool =
  ## Ignore a batch only when Git confirms every path is ignored and none
  ## contains tracked files. Unknown paths and Git failures invalidate safely.
  let
    rootAliases = directoryAliases(roots)
    metadataAliases = directoryAliases(metadata)
  var grouped: Table[string, seq[string]]
  for path in paths:
    if path.extractFilename() == ".gitignore":
      return true
    for directory in metadataAliases:
      if path == directory or path.isRelativeTo(directory):
        return true
    var root: string
    for candidate in rootAliases:
      if (path == candidate or path.isRelativeTo(candidate)) and candidate.len > root.len:
        root = candidate
    if root.len == 0 or path == root:
      return true
    grouped.mgetOrPut(root, @[]).add path

  for root, changed in grouped:
    var offset: int
    while offset < changed.len:
      let batch = changed[offset ..< min(offset + 128, changed.len)]
      # A removed/renamed ignored directory can still contain tracked files.
      var trackedArgs = @["--literal-pathspecs", "ls-files", "--cached", "-z", "--"]
      trackedArgs.add batch
      let tracked = runGitCommand(root, trackedArgs)
      if tracked.exitCode != 0 or tracked.output.len > 0:
        return true
      var ignoreArgs = @["-c", "core.quotePath=true", "check-ignore", "--"]
      ignoreArgs.add batch
      let ignored = runGitCommand(root, ignoreArgs)
      # Git quotes embedded newlines, so each ignored argument has exactly one
      # output line even for unusual filenames. Unmatched arguments are omitted.
      if ignored.exitCode != 0 or ignored.output.count('\n') != batch.len:
        return true
      offset += batch.len
