import std/[os, strformat, strutils]

type SymbolDef = object
  kind: string
  name: string
  line: int

func isIdentChar(c: char): bool =
  c.isAlphaNumeric or c == '_'

func parseSymbol(line: string): tuple[kind, name: string] =
  let text = line.strip(leading = true, trailing = false)
  let kind =
    if text.startsWith("proc "):
      "proc"
    elif text.startsWith("func "):
      "func"
    else:
      ""
  if kind.len == 0:
    return ("", "")

  var pos = kind.len
  while pos < text.len and text[pos].isSpaceAscii:
    inc pos
  if pos >= text.len:
    return ("", "")

  let start = pos
  if text[pos] == '`':
    inc pos
    while pos < text.len and text[pos] != '`':
      inc pos
    if pos < text.len:
      inc pos
  else:
    while pos < text.len and text[pos] notin {'*', '(', '[', ' ', '\t'}:
      inc pos

  let name = text[start ..< pos]
  if name.len == 0:
    ("", "")
  else:
    (kind, name)

func countCalls(line, name: string): int =
  if name.len == 0 or name[0] == '`':
    return 0

  var pos = 0
  while true:
    let found = line.find(name, pos)
    if found < 0:
      break

    let
      beforeOk = found == 0 or not line[found - 1].isIdentChar
      afterName = found + name.len
    if beforeOk:
      var next = afterName
      while next < line.len and line[next].isSpaceAscii:
        inc next
      if next < line.len and line[next] == '(':
        inc result

    pos = found + name.len

proc countCallsInModule(path, name: string): int =
  let source = readFile(path)
  for line in source.splitLines():
    result += countCalls(line, name)

proc countCallsInOtherModules(rootDir, targetPath, name: string): int =
  let target = targetPath.normalizedPath()
  for path in walkFiles(rootDir / "*.nim"):
    if path.normalizedPath() != target:
      result += countCallsInModule(path, name)

proc main() =
  if paramCount() != 1:
    quit &"usage: {getAppFilename().extractFilename()} module.nim", 1

  let path = paramStr(1)
  let rootDir = path.parentDir()
  let source = readFile(path)
  let lines = source.splitLines()
  var
    defs: seq[SymbolDef]
    declarationLines: seq[bool]

  declarationLines.setLen(lines.len)
  for lineNumber, line in pairs(lines):
    let (kind, name) = parseSymbol(line)
    if kind.len > 0:
      defs.add SymbolDef(kind: kind, name: name, line: lineNumber + 1)
      declarationLines[lineNumber] = true

  echo "line\tkind\tname\tcalls\totherModules"
  for def in defs:
    var calls = 0
    for lineNumber, line in pairs(lines):
      if not declarationLines[lineNumber]:
        calls += countCalls(line, def.name)
    let otherCalls = countCallsInOtherModules(rootDir, path, def.name)
    echo &"{def.line}\t{def.kind}\t{def.name}\t{calls}\t{otherCalls}"

when isMainModule:
  main()
