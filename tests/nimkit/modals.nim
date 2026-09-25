import std/unittest
import merenda/nimkit
import ./fixtures/widgetflows

suite "NimKit modal lifetimes":
  test "prepared sheet choices reach their callback and editing resumes in the owner":
    let
      app = newApplication("Sheet workflow")
      owner = newWindow("Owner", frame = rect(0, 0, 360, 160))
      unrelated = newWindow("Unrelated", frame = rect(0, 0, 360, 160))
      editor = newTextField("Draft", frame = rect(10, 10, 280, 30))
      root = newView()
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
    var responses: seq[int]
    for choice in [1, 0, 1]:
      let alert = newAlert("Unsaved changes", buttons = ["Discard", "Cancel"])
      alert.prepareForModal(
        proc(response: int) =
          responses.add response
          app.stopModal(response)
      )
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
      check app.modalSession().isNil
      let ownerIsKey = app.keyWindow() == owner
      check ownerIsKey
      let before = editor.text
      require owner.dispatchTextInput(" resumed")
      check editor.text != before
      check TextField(unrelated.contentView()).text == "Unchanged"

  test "closing from an alert response releases the callback and button action":
    let alert = newAlert("Complete", buttons = ["Close"])
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
    check responses == @[alert.buttonResponse(0), 10]
    check alert.window.isClosed()
    check alert.responseHandler.isNil
    check button.target.isNil

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
