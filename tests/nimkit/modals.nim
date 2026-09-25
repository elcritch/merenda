import std/unittest
import merenda/nimkit

suite "NimKit modal lifetimes":
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
