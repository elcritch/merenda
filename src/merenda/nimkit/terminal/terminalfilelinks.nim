## Local source locations printed by terminal programs.

import std/[nativesockets, options, os, strutils]

import ../foundation/urls

type TerminalFileLocation* = object
  ## A local file and an optional one-based source position.
  ## A zero line or column means that component was not specified.
  path*: string
  line*, column*: int

proc localTerminalPath(text, basePath: string): string =
  if text.startsWith("file:"):
    let url = text.initUrl()
    if url.host().len > 0 and
        url.host().toLowerAscii() notin ["localhost", getHostname().toLowerAscii()]:
      return
    return url.localFilePath(basePath)
  if "://" notin text:
    let path = text.expandTilde()
    if path.isAbsolute():
      return path
    if basePath.len > 0:
      return basePath / path

proc sourcePosition(text: string): Option[int] =
  let digits = text.strip()
  if digits.len == 0 or not digits.allCharsInSet({'0' .. '9'}):
    return none(int)
  try:
    let position = digits.parseInt()
    if position > 0:
      return some(position)
  except ValueError:
    discard

proc resolveTerminalFileLocation*(
    text, workingDirectory: string, allowMissing = false
): Option[TerminalFileLocation] =
  ## Resolve a path, `path:line[:column]`, or Nim's `path(line[, column])`.
  ## The working directory can be an OSC 7 file URL. Remote file URLs, missing
  ## files, and invalid or overflowing source positions produce `none`.
  ## Set `allowMissing` for CLI paths that can create a new file.
  let basePath = localTerminalPath(workingDirectory, "")
  var
    location: TerminalFileLocation
    pathText = text
  location.path = localTerminalPath(pathText, basePath)
  if location.path.len > 0 and fileExists(location.path):
    location.path = normalizedPath(absolutePath(location.path))
    return some(location)

  let paren = pathText.rfind('(')
  if pathText.endsWith(')') and paren >= 0 and paren + 1 < pathText.high and
      pathText[paren + 1] in {'0' .. '9', '-', '+'}:
    let parts = pathText[paren + 1 ..< pathText.high].split(',')
    if parts.len notin 1 .. 2:
      return none(TerminalFileLocation)
    let line = sourcePosition(parts[0])
    if line.isNone:
      return none(TerminalFileLocation)
    location.line = line.get()
    if parts.len == 2:
      let column = sourcePosition(parts[1])
      if column.isNone:
        return none(TerminalFileLocation)
      location.column = column.get()
    pathText.setLen(paren)
  else:
    var positions: seq[int]
    for _ in 0 ..< 2:
      let colon = pathText.rfind(':')
      if colon < 0 or colon == pathText.high:
        break
      let suffix = pathText[colon + 1 .. ^1]
      if not suffix.allCharsInSet({'0' .. '9'}):
        break
      let position = sourcePosition(suffix)
      if position.isNone:
        return none(TerminalFileLocation)
      positions.add position.get()
      pathText.setLen(colon)
    if positions.len > 0:
      location.line = positions[^1]
      if positions.len == 2:
        location.column = positions[0]
  location.path = localTerminalPath(pathText, basePath)
  if location.path.len > 0 and not dirExists(location.path) and
      (allowMissing or fileExists(location.path)):
    location.path = normalizedPath(absolutePath(location.path))
    return some(location)
