## Exercise native Cocoa key delivery through Siwin into Kosmo panes.
when defined(macosx):
  import std/[monotimes, os, strutils, tempfiles, times, unittest]

  import darwin/app_kit/[nsapplication, nsevent, nswindow]
  import darwin/foundation/[nsgeometry, nsstring]
  import darwin/objc/runtime
  from figdraw/windowing/siwinshim import WindowCocoa, nativeWindowHandle
  import siwin/platforms/cocoa/modifierstate
  import siwin/window as siwinwindow
  import sigils/threads

  import merenda/kosmo/kosmo
  import merenda/nimkit
  import ../support/terminalhelpers

  proc nativeWindowNumber(window: NSWindow): NSInteger {.objc: "windowNumber".}
  proc makeNativeKeyEvent(
    eventClass: typedesc[NSEvent],
    kind: NSInteger,
    point: NSPoint,
    modifiers: NSUInteger,
    timestamp: float64,
    windowNumber: NSInteger,
    context: ID,
    characters, ignoringModifiers: NSString,
    repeated: BOOL,
    keyCode: uint16,
  ): NSEvent {.
    objc:
      "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"
  .}

  proc sendNativeKey(window: nimkit.Window, characters: string, code: uint16): bool =
    # Siwin reads current global modifiers on Cocoa, including for synthetic events.
    let deadline = getMonoTime() + initDuration(seconds = 10)
    var modifiers: set[siwinwindow.ModifierKey]
    var ready = false
    while getMonoTime() < deadline:
      if tryCurrentModifierState(modifiers) and modifiers == {}:
        ready = true
        break
      discard getCurrentSigilThread().pollAll(NonBlocking)
      sleep(1)
    if not ready:
      return
    let native =
      cast[NSWindow](WindowCocoa(window.nativeWindowOrNil()).nativeWindowHandle())
    for kind in [10, 11]: # NSEventTypeKeyDown and NSEventTypeKeyUp
      let event = NSEvent.makeNativeKeyEvent(
        kind,
        NSMakePoint(0, 0),
        0,
        0,
        native.nativeWindowNumber(),
        nil,
        characters.toNSString,
        characters.toNSString,
        false,
        code,
      )
      if event == nil:
        return
      NSApp.sendEvent(event)
    true

  proc waitForTerminalText(terminal: TerminalView, expected: string): bool =
    let deadline = getMonoTime() + initDuration(seconds = 10)
    while getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard terminal.poll()
      if expected in terminal.session().screen().plainText().splitWhitespace().join(""):
        return true
      sleep(1)

  suite "native Cocoa keys in Kosmo panes":
    test "editor receives arrows, enter, and backspace":
      let root = createTempDir("kosmo-native-editor-keys-", "")
      let path = root / "test.txt"
      writeFile(path, "abc\ndef\n")
      let frontend = newKosmoApplication(
        newApplication("Native editor keys"),
        root,
        monitorsGitStatus = false,
        configPath = root / "config.json",
      )
      let window = frontend.window
      defer:
        frontend.close()
        removeFile(path)
        removeDir(root)
      frontend.show()
      window.ensureNativeWindow()
      require window.nativeReady
      require frontend.openPath(path)
      require window.makeFirstResponder(frontend.editorView)
      require window.sendNativeKey("\uf703", 0x7c) # Right
      require window.sendNativeKey("\uf701", 0x7d) # Down
      check frontend.editorView.editor.bufferCursor().line == 1
      check frontend.editorView.editor.bufferCursor().column == 1
      require frontend.editorView.editor.handleKey("i")
      require window.sendNativeKey("\r", 0x24)
      check frontend.editorView.editor.bufferCursor().line == 2
      check frontend.editorView.editor.bufferCursor().column == 0
      require window.sendNativeKey("\x7f", 0x33)
      check frontend.editorView.editor.bufferCursor().line == 1
      check frontend.editorView.editor.bufferCursor().column == 1

    test "terminal receives arrows, enter, and backspace":
      let root = createTempDir("kosmo-native-terminal-keys-", "")
      let session = spawnTerminalViewSession(
        initTerminalSpawnOptions(
          command =
            "stty raw -echo; printf READY; dd bs=1 count=8 2>/dev/null | od -An -tx1; " &
            "stty sane; IFS= read -r hold"
        ),
        columns = 80,
        rows = 4,
      )
      let terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 200))
      let frontend = newKosmoApplication(
        newApplication("Native terminal keys"),
        root,
        monitorsGitStatus = false,
        configPath = root / "config.json",
      )
      let window = frontend.window
      defer:
        frontend.close()
        terminal.close()
        session.waitForCommands()
        removeDir(root)
      frontend.show()
      window.ensureNativeWindow()
      require window.nativeReady
      require terminal.waitForTerminalText("READY")
      require frontend.openDocument(
        newKosmoPaneDocument("native-keys", "Terminal", terminal)
      )
      require window.makeFirstResponder(terminal)
      require window.sendNativeKey("\uf702", 0x7b) # Left
      require window.sendNativeKey("\x7f", 0x33) # Backspace
      require window.sendNativeKey("\r", 0x24) # Enter
      require window.sendNativeKey("\uf700", 0x7e) # Up
      check terminal.waitForTerminalText("1b5b447f0d1b5b41")
