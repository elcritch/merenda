## Native context menus must preserve the stacking order of document windows.
when defined(macosx):
  import std/[monotimes, os, tempfiles, times, unittest]

  import darwin/app_kit/[nsapplication, nswindow]
  import darwin/foundation/nsarray
  import darwin/objc/runtime
  from figdraw/windowing/siwinshim import WindowCocoa, nativeWindowHandle

  import merenda/nimkit
  import merenda/nimkit/app/windows as nimkitWindows
  import merenda/kosmo/[filetree, workspacefiles]

  proc orderedWindows(app: NSApplication): NSArray[NSWindow] {.objc: "orderedWindows".}
  proc isVisible(window: NSWindow): BOOL {.objc: "isVisible".}

  proc cocoaWindow(window: nimkitWindows.Window): NSWindow =
    cast[NSWindow](WindowCocoa(window.nativeWindowOrNil()).nativeWindowHandle())

  proc nativeDocumentOrder(windows: openArray[nimkitWindows.Window]): seq[int] =
    for native in NSApplication.sharedApplication().orderedWindows():
      for index, window in windows:
        if native == window.cocoaWindow():
          result.add index

  proc waitForNativeFront(
      app: Application, windows: openArray[nimkitWindows.Window], frontIndex: int
  ): bool =
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while getMonoTime() < deadline:
      discard app.runForFrames(1)
      let order = nativeDocumentOrder(windows)
      if order.len == windows.len and order[0] == frontIndex:
        return true
      sleep(1)

  suite "NimKit native window activation":
    test "file tree context menus preserve document window stacking order":
      let
        root = createTempDir("kosmo-native-context-", "")
        path = root / "item.txt"
        app = newApplication("Native Context Menu Activation Test")
      var
        windows: seq[nimkitWindows.Window]
        trees: seq[KosmoFileTree]
      defer:
        for window in windows:
          window.close()
        removeDir(root)
      writeFile(path, "context menu target")

      for index in 0 ..< 3:
        let
          window = newWindow(
            "Context Menu " & $index,
            frame = rect((80 + index * 40).float32, 80, 360, 240),
          )
          tree = newKosmoFileTree(root, frame = rect(0, 0, 360, 240))
        windows.add window
        trees.add tree
        window.setContentView(tree)
        app.addWindow(window)
        window.makeKeyAndOrderFront()
        window.ensureNativeWindow()
        require window.nativeReady
        require tree.workspaceFiles.waitForFiles()

      # Exercise both older and newer owners, including reopening a menu.
      # The native order, rather than Application.orderedWindows, catches
      # backends that restack unrelated windows while realizing a popup.
      for ownerIndex in [0, 2, 1, 0]:
        let
          owner = windows[ownerIndex]
          tree = trees[ownerIndex]
        owner.makeKeyAndOrderFront()
        # Establish the owner's native order even when another test process
        # has desktop keyboard focus. This test measures application window
        # stacking, which does not require exclusive desktop focus.
        owner.cocoaWindow().makeKeyAndOrderFront(cast[ID](nil))
        require app.waitForNativeFront(windows, ownerIndex)
        let before = nativeDocumentOrder(windows)
        require before.len == windows.len
        require before[0] == ownerIndex

        let row = tree.rowForItem(path)
        require row >= 0
        let bounds = tree.rowItemRect(row)
        require owner.rightMouseDownAt(
          tree.pointToWindow(initPoint(bounds.minX + 120, bounds.minY + 12))
        )
        let popup = owner.transientWindow()
        require not popup.isNil
        require popup.nativeReady
        check popup.cocoaWindow().isVisible()
        check nativeDocumentOrder(windows) == before
        check app.keyWindow() == owner
        check tree.menu().isOpen()

        require owner.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
        check not owner.hasActiveTransientSession()
        check app.keyWindow() == owner
        check nativeDocumentOrder(windows) == before
