import std/unittest

import figdraw

import merenda/nimkit

suite "NimKit popup hosts":
  test "inline popup host owns placement focus and dismissal":
    let
      window = newWindow("Popup host", frame = rect(0, 0, 240, 140))
      root = newView(frame = rect(0, 0, 240, 140))
      anchor = newView(frame = rect(8, 108, 120, 24))
      content = newView(frame = rect(0, 0, 120, 50))

    var
      dismissCount = 0
      dismissReason = tdrProgrammatic
    root.addSubview(anchor)
    window.setContentView(root)
    anchor.acceptsFirstResponder = true
    content.acceptsFirstResponder = true
    let host = newPopupHost(
      window,
      anchor,
      content,
      initSize(120, 50),
      presentation = ppInline,
      restoreResponder = Responder(anchor),
      onDismiss = proc(_: PopupHost, reason: DismissReason) =
        inc dismissCount
        dismissReason = reason,
    )

    check host.presentPopup()
    check host.popupOpen
    check host.popupWindow().isNil
    check content.superview() == root
    check content.frame.maxY <= anchor.frame.minY
    check content.frame.minY >= root.bounds().minY
    check window.hasActiveTransientSession()
    check window.transientOwner() == Responder(content)
    check window.firstResponder == Responder(content)

    anchor.frame = rect(8, 8, 120, 24)
    host.repositionPopup()
    check content.frame.minY >= anchor.frame.maxY

    check host.dismissPopup(tdrEscape)
    check not host.popupOpen
    check content.superview().isNil
    check not window.hasActiveTransientSession()
    check window.firstResponder == Responder(anchor)
    check dismissCount == 1
    check dismissReason == tdrEscape

  test "popup host can force above placement and use a custom inline parent":
    let
      window = newWindow("Popup host parent", frame = rect(0, 0, 320, 220))
      root = newView(frame = rect(0, 0, 320, 220))
      container = newView(frame = rect(40, 40, 240, 140))
      anchor = newView(frame = rect(10, 100, 100, 20))
      content = newView(frame = rect(0, 0, 100, 40))

    container.addSubview(anchor)
    root.addSubview(container)
    window.setContentView(root)
    let host = newPopupHost(
      window,
      anchor,
      content,
      initSize(100, 40),
      presentation = ppInline,
      inlineParent = container,
      placeAbove = true,
    )

    host.popupOpen = true
    check content.superview() == container
    check content.frame.maxY <= anchor.frame.minY
    host.popupOpen = false
    check content.superview().isNil
