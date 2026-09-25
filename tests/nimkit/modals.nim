import std/unittest
import merenda/nimkit
import ./fixtures/widgetflows

suite "NimKit modal lifetimes":
  test "closing a window releases its active field editor":
    var weakWindow, weakField, weakEditor: BackRef[Responder]
    block:
      let
        app = newApplication("Editing lifetime")
        window = newWindow("Editor")
        field = newTextField("Draft")
      window.setContentView(field)
      app.addWindow(window)
      window.makeKeyAndOrderFront()
      require window.clickView(field)
      weakWindow[] = Responder(window)
      weakField[] = Responder(field)
      weakEditor[] = Responder(window.fieldEditor())
      window.close()
      discard app.runForFrames(1)
    check weakWindow.isNil
    check weakField.isNil
    check weakEditor.isNil

  test "prepared sheet choices reach their callback and editing resumes in the owner":
    var weakOwner, weakUnrelated, weakEditor: BackRef[Responder]
    var weakAlerts, weakAlertWindows, weakAlertContents: array[3, BackRef[Responder]]
    block:
      let
        app = newApplication("Sheet workflow")
        owner = newWindow("Owner", frame = rect(0, 0, 360, 160))
        unrelated = newWindow("Unrelated", frame = rect(0, 0, 360, 160))
        editor = newTextField("Draft", frame = rect(10, 10, 280, 30))
        root = newView()
      weakOwner[] = Responder(owner)
      weakUnrelated[] = Responder(unrelated)
      weakEditor[] = Responder(editor)
      root.addSubview(editor)
      owner.setContentView(root)
      unrelated.setContentView(newTextField("Unchanged"))
      app.addWindow(owner)
      app.addWindow(unrelated)
      owner.makeKeyAndOrderFront()
      require owner.clickView(editor)
      defer:
        owner.close()
        unrelated.close()
        discard app.runForFrames(1)
      var responses: seq[int]
      for index, choice in [1, 0, 1]:
        let alert = newAlert("Unsaved changes", buttons = ["Discard", "Cancel"])
        weakAlerts[index][] = Responder(alert)
        weakAlertWindows[index][] = Responder(alert.window)
        alert.prepareForModal(
          proc(response: int) =
            responses.add response
            app.stopModal(response)
        )
        weakAlertContents[index][] = Responder(alert.contentView)
        # Use the prepared window overload: installing another default handler
        # would drop the caller's completion callback.
        let session = app.beginModalSheet(owner, alert.window)
        require not session.isNil
        let belongsToOwner = session.parentWindow == owner
        check belongsToOwner
        let previousResponses = responses.len
        require alert.window.clickView(alert.buttonViews[choice])
        require responses.len == previousResponses + 1
        check responses[^1] == alert.buttonResponse(choice)
        check session.state == mssStopped
        check session.response == responses[^1]
        app.endModalSession(session)
        alert.window.close()
        check alert.window.isClosed()
        check alert.responseHandler.isNil
        for button in alert.buttonViews:
          check Button(button).target.isNil
        check app.modalSession().isNil
        let ownerIsKey = app.keyWindow() == owner
        check ownerIsKey
        let before = editor.text
        require owner.dispatchTextInput(" resumed")
        check editor.text != before
        check TextField(unrelated.contentView()).text == "Unchanged"
    check weakOwner.isNil
    check weakUnrelated.isNil
    check weakEditor.isNil
    for index in 0 ..< weakAlerts.len:
      check weakAlerts[index].isNil
      check weakAlertWindows[index].isNil
      check weakAlertContents[index].isNil

  test "closing from an alert response releases the callback and button action":
    var weakAlert: BackRef[Responder]
    var weakWindow: BackRef[Responder]
    var weakEditor: BackRef[Responder]
    block:
      let alert = newAlert("Complete", buttons = ["Close"])
      weakAlert[] = Responder(alert)
      weakWindow[] = Responder(alert.window)
      var responses: seq[int]
      let afterClose = proc() =
        responses.add 10
      alert.prepareForModal(
        proc(response: int) =
          responses.add response
          alert.window.close()
          afterClose()
      )

      let button = Button(alert.buttonViews[0])
      require alert.window.clickView(button)
      weakEditor[] = Responder(alert.window.fieldEditor())
      check responses == @[alert.buttonResponse(0), 10]
      check alert.window.isClosed()
      check alert.responseHandler.isNil
      check button.target.isNil
    check weakAlert.isNil
    check weakWindow.isNil
    check weakEditor.isNil

  test "closing a modal aborts its running session and repeated ending is harmless":
    let
      app = newApplication("Modal lifetime test")
      parent = newWindow("Parent")
      dialog = newWindow("Dialog")
    app.addWindow(parent)
    parent.makeKeyAndOrderFront()
    defer:
      parent.close()
      dialog.close()
      discard app.runForFrames(1)
    let session = app.beginModalSession(dialog)
    dialog.close()
    check session.state == mssAborted
    check app.modalSession().isNil
    check app.keyWindow() == parent
    # An aborted session returns without entering the native event loop.
    check app.runModalSession(session) == 0
    let another = newWindow("Another dialog")
    defer:
      another.close()
    let active = app.beginModalSession(another)
    app.endModalSession(session)
    check app.modalSession() == active
    check app.keyWindow() == another

  test "closing a lower modal preserves the active dialog and stopped responses":
    let
      app = newApplication("Nested modal test")
      parent = newWindow("Parent")
      first = newWindow("First")
      second = newWindow("Second")
    app.addWindow(parent)
    parent.makeKeyAndOrderFront()
    defer:
      second.close()
      first.close()
      parent.close()
      discard app.runForFrames(1)
    let lower = app.beginModalSession(first)
    let active = app.beginModalSession(second)
    first.close()
    check lower.state == mssAborted
    check app.modalSession() == active
    check app.keyWindow() == second
    check app.mainWindow() == second
    app.stopModal(42)
    second.close()
    check active.state == mssStopped
    check active.response == 42
    check app.modalSession().isNil
