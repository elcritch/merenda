## Complete file replacement without exposing a partially written destination.

import std/[os, tempfiles]

when defined(posix):
  import std/posix

when defined(windows):
  import std/winlean

  proc setBinaryMode(
    handle, mode: cint
  ): cint {.importc: "_setmode", header: "<io.h>", cdecl.}

  var binaryMode {.importc: "_O_BINARY", header: "<fcntl.h>".}: cint
else:
  proc renameFile(
    source, destination: cstring
  ): cint {.importc: "rename", header: "<stdio.h>", cdecl.}

proc closeFile(file: File): cint {.importc: "fclose", header: "<stdio.h>", cdecl.}

proc saveDestination(path: string): string =
  if path.len == 0 or '\0' in path:
    raise
      newException(ValueError, "save path must be nonempty and contain no NUL bytes")
  result = absolutePath(path)
  var links = 0
  while symlinkExists(result):
    if links == 40:
      raise newException(OSError, "too many symbolic links in save path: " & path)
    result = absolutePath(expandSymlink(result), result.parentDir())
    inc links

proc replaceFile(source, destination: string) =
  # Do not use moveFile: its cross-device fallback can truncate the destination.
  when defined(windows):
    if moveFileExW(
      newWideCString(source), newWideCString(destination), MOVEFILE_REPLACE_EXISTING
    ) == 0:
      raiseOSError(osLastError(), destination)
  else:
    if renameFile(source.cstring, destination.cstring) != 0:
      raiseOSError(osLastError(), destination)

proc checkSaveDestination(destination: string) =
  when defined(posix):
    var info: Stat
    if stat(destination.cstring, info) == 0:
      if S_ISREG(info.st_mode):
        # Renaming only checks directory permissions; retain ordinary file-write
        # permission checks so atomic saves do not silently bypass read-only files.
        if access(destination.cstring, W_OK) != 0:
          raiseOSError(osLastError(), destination)
      elif not S_ISDIR(info.st_mode):
        raise newException(IOError, "cannot replace a special file: " & destination)
    elif errno != ENOENT:
      raiseOSError(osLastError(), destination)

proc atomicWriteFile*(path, contents: string) =
  ## Write to a temporary sibling, then atomically replace `path` after a checked close.
  ## The parent directory must exist. Existing permission bits and symbolic links
  ## are preserved; new files use the temporary file's default permissions.
  ## Raises on write, close, permission, or rename failure, keeping the old contents.
  ## Atomic replacement does not guarantee persistence through a power failure.
  let destination = saveDestination(path)
  checkSaveDestination(destination)
  var output = createTempFile(".merenda-save-", ".tmp", destination.parentDir())
  try:
    when defined(windows):
      if setBinaryMode(output.cfile.getFileHandle().cint, binaryMode) == -1:
        raise newException(IOError, "could not select binary mode for: " & path)
    if contents.len > 0 and
        output.cfile.writeBuffer(unsafeAddr contents[0], contents.len) != contents.len:
      raise newException(IOError, "could not write temporary save file for: " & path)

    # Nim's usual close/flushFile discard buffered write errors. Check fclose
    # before renaming, including failures deferred by a small buffered write.
    let closeResult = closeFile(output.cfile)
    output.cfile = nil
    if closeResult != 0:
      raise newException(IOError, "could not close temporary save file for: " & path)
    if fileExists(destination):
      setFilePermissions(output.path, getFilePermissions(destination))
    replaceFile(output.path, destination)
  finally:
    if not output.cfile.isNil:
      discard closeFile(output.cfile)
    discard tryRemoveFile(output.path)
