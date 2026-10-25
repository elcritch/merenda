## Local source locations printed by terminal programs.

import std/[nativesockets, options, os, strutils]

import ../foundation/urls

type TerminalFileLocation* = object
  ## An existing local file and an optional one-based source position.
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

proc resolveTerminalFileLocation*(
    text, workingDirectory: string
): Option[TerminalFileLocation] =
  ## Resolve a path, `path:line`, or `path:line:column` to an existing local file.
  ## The working directory can be an OSC 7 file URL. Remote file URLs, missing
  ## files, and invalid or overflowing source positions produce `none`.
  let basePath = localTerminalPath(workingDirectory, "")
  var
    location: TerminalFileLocation
    pathText = text
  location.path = localTerminalPath(pathText, basePath)
  if location.path.len > 0 and fileExists(location.path):
    location.path = normalizedPath(absolutePath(location.path))
    return some(location)

  var positions: seq[int]
  for _ in 0 ..< 2:
    let colon = pathText.rfind(':')
    if colon < 0 or colon == pathText.high:
      break
    let suffix = pathText[colon + 1 .. ^1]
    if not suffix.allCharsInSet({'0' .. '9'}):
      break
    var position: int
    try:
      position = suffix.parseInt()
    except ValueError:
      return none(TerminalFileLocation)
    if position <= 0:
      return none(TerminalFileLocation)
    positions.add position
    pathText.setLen(colon)
  if positions.len == 0:
    return none(TerminalFileLocation)
  location.path = localTerminalPath(pathText, basePath)
  if location.path.len > 0 and fileExists(location.path):
    location.path = normalizedPath(absolutePath(location.path))
    location.line = positions[^1]
    if positions.len == 2:
      location.column = positions[0]
    return some(location)
