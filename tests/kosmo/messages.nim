import std/[strutils, unittest]

import merenda/kosmo/moe

suite "Kosmo editor messages":
  test "shows Moe messages in host status rather than the editor grid":
    let editor = newKosmoEditor("alpha")
    defer:
      editor.close()
    check not editor.searchFrom("missing", KosmoBufferCursor(line: 0, column: 0))
    var buffer = newRenderBuffer(60, 12)
    editor.render(buffer)
    check editor.status().message == "Pattern not found: missing"
    var rendered = ""
    for row in 0 ..< buffer.height:
      for column in 0 ..< buffer.width:
        rendered.add(buffer.cell(column, row).symbol)
      rendered.add('\n')
    check "Pattern not found: missing" notin rendered
    check editor.handleKey("/")
    check editor.commandLine().visible
