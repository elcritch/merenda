## Require every component test module to appear in its shared runner.
import std/[algorithm, os, sets, strutils]

proc isNameChar(ch: char): bool =
  ch.isAlphaNumeric or ch == '_'

proc withoutComments(source: string): string =
  for line in source.splitLines():
    let comment = line.find('#')
    if comment < 0:
      result.add line
    else:
      result.add line[0 ..< comment]
    result.add '\n'

proc importedModules(source, component: string): HashSet[string] =
  let code = source.withoutComments()
  let prefix = component & "/"
  var position = 0
  while position < code.len:
    let start = code.find("import", position)
    if start < 0:
      break
    position = start + "import".len
    if (start == 0 or not code[start - 1].isNameChar) and position < code.len and
        code[position].isSpaceAscii:
      while position < code.len and code[position].isSpaceAscii:
        inc position
      if code.find(prefix, position) == position:
        position += prefix.len
        if position < code.len and code[position] == '[':
          inc position
          while position < code.len and code[position] != ']':
            if code[position].isNameChar:
              let nameStart = position
              while position < code.len and code[position].isNameChar:
                inc position
              result.incl code[nameStart ..< position]
            else:
              inc position
        else:
          let nameStart = position
          while position < code.len and code[position].isNameChar:
            inc position
          if position > nameStart:
            result.incl code[nameStart ..< position]

proc missingImports(root: string): seq[string] =
  for component in ["nimkit", "kosmo", "tekton", "integrations"]:
    let runner = root / "tests" / ("t" & component & ".nim")
    let imports = importedModules(readFile(runner), component)
    var modules: seq[string]
    for path in listFiles(root / "tests" / component):
      if path.splitFile.ext == ".nim":
        modules.add path
    modules.sort()
    for path in modules:
      if path.splitFile.name notin imports:
        result.add path.relativePath(root) & ": add an import to " &
          runner.relativePath(root)

let missing = missingImports(currentSourcePath().parentDir.parentDir.parentDir)
if missing.len > 0:
  quit "Unreferenced test modules:\n" & missing.join("\n")
echo "All component test modules are referenced by their shared runners."
