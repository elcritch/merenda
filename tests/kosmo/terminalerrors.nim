import std/[os, tempfiles, unittest]
import merenda/nimkit
import merenda/kosmo/kosmo

proc findButton(view: View): Button =
  if view of Button:
    return Button(view)
  for child in view.subviews:
    result = findButton(child)
    if not result.isNil:
      return

suite "Kosmo terminal errors":
  test "invalid working directories present a dismissible error without adding a tab":
    let root = createTempDir("merenda-terminal-errors-", "")
    defer:
      removeDir(root)
    let app = newApplication("Terminal error test")
    let frontend = newKosmoApplication(app, monitorsGitStatus = false)
    defer:
      frontend.close()
    let originalContent = frontend.editorPane.contentView
    check not frontend.openTerminal(
      initTerminalSpawnOptions(workingDirectory = root / "missing")
    )
    check frontend.editorPane.contentView == originalContent
    var session = app.modalSession()
    require not session.isNil
    check session.window.title == "Could not start terminal"
    let button = findButton(session.window.contentView())
    require not button.isNil
    check button.title == "OK"
    let dialogWindow = session.window
    session = nil
    discard button.send(performClick(), ActionArgs(sender: button))
    check app.modalSession().isNil
    check dialogWindow.isClosed

    # Closing through window chrome must also end the modal session.
    check not frontend.openTerminal(
      initTerminalSpawnOptions(workingDirectory = root / "missing")
    )
    let secondSession = app.modalSession()
    require not secondSession.isNil
    secondSession.window.close()
    check app.modalSession().isNil
