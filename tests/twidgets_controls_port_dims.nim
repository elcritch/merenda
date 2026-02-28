import std/[os, osproc, strscans, strutils, tables, unittest]

type RectSample = object
  x: float
  y: float
  w: float
  h: float

type LayoutDump = object
  hasWindowFrame: bool
  hasContentRect: bool
  windowFrame: RectSample
  contentRect: RectSample
  frames: Table[string, RectSample]

proc rectNear(a, b: RectSample, tolerance: float): bool =
  abs(a.x - b.x) <= tolerance and abs(a.y - b.y) <= tolerance and
    abs(a.w - b.w) <= tolerance and abs(a.h - b.h) <= tolerance

proc extractRectToken(line: string, key: string): string =
  let keyPos = line.find(key)
  if keyPos < 0:
    return ""
  let openPos = line.find('(', keyPos)
  if openPos < 0:
    return ""
  let closePos = line.find(')', openPos + 1)
  if closePos < 0:
    return ""
  line[openPos .. closePos]

proc parseRectToken(token: string, outRect: var RectSample): bool =
  scanf(token, "($f,$f $fx$f)", outRect.x, outRect.y, outRect.w, outRect.h)

proc parseLayoutDump(output: string): LayoutDump =
  result.frames = initTable[string, RectSample]()
  for rawLine in output.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or not line.contains("frame=("):
      continue
    let frameMarkerPos = line.find("] frame=(")
    if frameMarkerPos < 0:
      continue
    if frameMarkerPos == 0:
      continue
    let linePrefix = line[0 ..< frameMarkerPos]
    let bracketOpen = linePrefix.rfind('[')
    if bracketOpen < 0:
      continue
    let bracketClose = line.find(']', bracketOpen + 1)
    if bracketClose < 0:
      continue
    let name = line[(bracketOpen + 1) ..< bracketClose]
    if name == "Window init":
      var frameRect, contentRect: RectSample
      let frameTok = extractRectToken(line, "frame=")
      let contentTok = extractRectToken(line, "contentRect=")
      if parseRectToken(frameTok, frameRect):
        result.hasWindowFrame = true
        result.windowFrame = frameRect
      if parseRectToken(contentTok, contentRect):
        result.hasContentRect = true
        result.contentRect = contentRect
      continue
    var frameRect: RectSample
    let frameTok = extractRectToken(line, "frame=")
    if parseRectToken(frameTok, frameRect):
      result.frames[name] = frameRect

proc runCommandOrFail(cmd: string) =
  let run = execCmdEx(cmd, options = {poUsePath, poEvalCommand, poStdErrToStdOut})
  doAssert(
    run.exitCode == 0,
    "Command failed: " & cmd & "\nExit: " & $run.exitCode & "\n" & run.output,
  )

proc runAndReadOutput(cmd: string, outputPath: string): string =
  let run = execCmdEx(
    cmd & " > " & outputPath.quoteShell & " 2>&1", options = {poUsePath, poEvalCommand}
  )
  if run.exitCode != 0:
    let output =
      if fileExists(outputPath):
        readFile(outputPath)
      else:
        run.output
    doAssert(
      false, "Command failed: " & cmd & "\nExit: " & $run.exitCode & "\n" & output
    )
  if fileExists(outputPath):
    return readFile(outputPath)
  ""

proc compareGeometry(objcDump, nimDump: LayoutDump, frameNames: openArray[string]) =
  const tolerance = 1.0
  doAssert(objcDump.hasWindowFrame, "Missing ObjC window frame dump")
  doAssert(objcDump.hasContentRect, "Missing ObjC contentRect dump")
  doAssert(nimDump.hasWindowFrame, "Missing Nim window frame dump")
  doAssert(nimDump.hasContentRect, "Missing Nim contentRect dump")
  doAssert(
    rectNear(nimDump.windowFrame, objcDump.windowFrame, tolerance),
    "Window frame mismatch: objc=" & $objcDump.windowFrame & " nim=" &
      $nimDump.windowFrame,
  )
  doAssert(
    rectNear(nimDump.contentRect, objcDump.contentRect, tolerance),
    "Content rect mismatch: objc=" & $objcDump.contentRect & " nim=" &
      $nimDump.contentRect,
  )

  for name in frameNames:
    doAssert(name in objcDump.frames, "Missing ObjC frame for " & name)
    doAssert(name in nimDump.frames, "Missing Nim frame for " & name)
    doAssert(
      rectNear(nimDump.frames[name], objcDump.frames[name], tolerance),
      "Frame mismatch for " & name & ": objc=" & $objcDump.frames[name] & " nim=" &
        $nimDump.frames[name],
    )

when defined(macosx):
  suite "widgets controls geometry parity":
    test "checkbox example roughly matches Cocoa dimensions":
      runCommandOrFail(
        "clang -framework Cocoa tests/widgets/controls/CheckBox.m -o /tmp/nutella_checkbox_objc"
      )
      runCommandOrFail(
        "nim c --nimcache:/tmp/nimcache_test_checkbox tests/widgets/controls/checkbox.nim"
      )
      let objcOutput = runAndReadOutput(
        "CHECKBOX_DUMP_LAYOUT_ONCE=1 /tmp/nutella_checkbox_objc",
        "/tmp/nutella_checkbox_objc_dims.out",
      )
      let nimOutput = runAndReadOutput(
        "NUTELLA_EXAMPLE_FRAMES=1 ./tests/widgets/controls/checkbox",
        "/tmp/nutella_checkbox_nim_dims.out",
      )
      let objcDump = parseLayoutDump(objcOutput)
      let nimDump = parseLayoutDump(nimOutput)
      compareGeometry(
        objcDump,
        nimDump,
        ["contentView", "checkBox1", "checkBox2", "checkBox3", "checkBox4", "checkBox5"],
      )

    test "label example roughly matches Cocoa dimensions":
      runCommandOrFail(
        "clang -framework Cocoa tests/widgets/controls/Label.m -o /tmp/nutella_label_objc"
      )
      runCommandOrFail(
        "nim c --nimcache:/tmp/nimcache_test_label tests/widgets/controls/label.nim"
      )
      let objcOutput = runAndReadOutput(
        "LABEL_DUMP_LAYOUT_ONCE=1 /tmp/nutella_label_objc",
        "/tmp/nutella_label_objc_dims.out",
      )
      let nimOutput = runAndReadOutput(
        "NUTELLA_EXAMPLE_FRAMES=1 ./tests/widgets/controls/label",
        "/tmp/nutella_label_nim_dims.out",
      )
      let objcDump = parseLayoutDump(objcOutput)
      let nimDump = parseLayoutDump(nimOutput)
      compareGeometry(objcDump, nimDump, ["contentView", "label1"])

    test "textbox example roughly matches Cocoa dimensions":
      runCommandOrFail(
        "clang -framework Cocoa tests/widgets/controls/TextBox.m -o /tmp/nutella_textbox_objc"
      )
      runCommandOrFail(
        "nim c --nimcache:/tmp/nimcache_test_textbox tests/widgets/controls/textbox.nim"
      )
      let objcOutput = runAndReadOutput(
        "TEXTBOX_DUMP_LAYOUT_ONCE=1 /tmp/nutella_textbox_objc",
        "/tmp/nutella_textbox_objc_dims.out",
      )
      let nimOutput = runAndReadOutput(
        "NUTELLA_EXAMPLE_FRAMES=1 ./tests/widgets/controls/textbox",
        "/tmp/nutella_textbox_nim_dims.out",
      )
      let objcDump = parseLayoutDump(objcOutput)
      let nimDump = parseLayoutDump(nimOutput)
      compareGeometry(objcDump, nimDump, ["contentView", "textBox1", "textBox2"])
else:
  suite "widgets controls geometry parity":
    test "skipped off macOS":
      check(true)
