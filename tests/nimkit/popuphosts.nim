import std/unittest

import figdraw

import merenda/nimkit
import sigils/selectors

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
    anchor.focusable = true
    content.focusable = true
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

  test "an inline popup follows its anchor when layout moves it":
    let
      window = newWindow("Popup follows anchor", frame = rect(0, 0, 240, 220))
      stack = newStackView(laVertical, frame = rect(0, 0, 240, 220))
      anchor = newTextField("anchor")
      content = newView(frame = rect(0, 0, 120, 50))
    defer:
      window.close()
    stack.alignment = svaFill
    stack.addArrangedSubview(anchor)
    window.setContentView(stack)
    stack.layoutSubtreeIfNeeded()
    let host =
      newPopupHost(window, anchor, content, initSize(120, 50), presentation = ppInline)
    check host.presentPopup()
    check content.frame.minY == anchor.frame.maxY

    stack.insertArrangedSubview(newTextField("above"), 0)
    stack.layoutSubtreeIfNeeded()
    check anchor.frame.minY > 0
    check content.frame.minY == anchor.frame.maxY
    check stack.layoutFeedbackCycles() == 0
    check not stack.needsLayout

    check host.dismissPopup()
    stack.insertArrangedSubview(newTextField("first"), 0)
    stack.layoutSubtreeIfNeeded()
    check content.superview().isNil

  test "an inline popup follows an ancestor moved by constraints":
    let
      window = newWindow("Popup follows constraints", frame = rect(0, 0, 400, 220))
      root = newView(frame = rect(0, 0, 400, 220))
      parent = newView(frame = rect(10, 10, 220, 130))
      anchor = newView(frame = rect(10, 10, 70, 20))
      content = newView(frame = rect(0, 0, 110, 30))
      left = parent[atLeft].equalTo(root[atLeft] + 10)
      host = newPopupHost(
        window, anchor, content, initSize(110, 30), presentation = ppInline
      )
    defer:
      window.close()
    anchor.autoresizingMaskConstraints = false
    parent.addSubview(anchor)
    root.addSubview(parent)
    window.setContentView(root)
    left.activate()
    root.layoutSubtreeIfNeeded()
    require host.presentPopup()
    check content.frame.minX == 20

    left.constant = 110
    root.layoutSubtreeIfNeeded()
    check parent.frame.minX == 110
    check anchor.frame.minX == 10
    check content.frame.minX == 120
    check root.layoutFeedbackCycles() == 0

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

  test "popup replacement respects a dismissal veto":
    let
      window = newWindow("Popup replacement veto", frame = rect(0, 0, 240, 140))
      root = newView(frame = rect(0, 0, 240, 140))
      anchor = newView(frame = rect(8, 8, 120, 24))
      firstContent = newView(frame = rect(0, 0, 120, 50))
      secondContent = newView(frame = rect(0, 0, 120, 50))
    defer:
      window.close()
    root.addSubview(anchor)
    window.setContentView(root)
    let
      first = newPopupHost(
        window, anchor, firstContent, initSize(120, 50), presentation = ppInline
      )
      second = newPopupHost(
        window, anchor, secondContent, initSize(120, 50), presentation = ppInline
      )
    var allowDismiss = false
    discard window.addMethod(
      shouldDismiss(),
      proc(_: Window, reason: DismissReason): bool =
        discard reason
        allowDismiss,
    )

    check first.presentPopup()
    check not second.presentPopup()
    check first.popupOpen
    check not second.popupOpen
    check firstContent.superview() == root
    check secondContent.superview().isNil
    check window.transientOwner() == Responder(firstContent)

    allowDismiss = true
    check second.presentPopup()
    check not first.popupOpen
    check firstContent.superview().isNil
    check secondContent.superview() == root
    check window.transientOwner() == Responder(secondContent)
