import std/unittest

import sigils/core

import merenda/nimkit
import merenda/nimkit/responders as nimkitResponders
import merenda/nimkit/viewgeometry

type
  MouseSpyView = ref object of View

  LifecycleSpyView = ref object of View
    events: seq[string]
    superviews: seq[View]
    windows: seq[Responder]
    addedSubviews: seq[View]
    removedSubviews: seq[View]

  LayoutSpyView = ref object of View
    events: seq[string]

  ConstraintSpyView = ref object of View
    name: string

var
  spyMouseDownPoint: Point
  spyMouseUpPoint: Point
  spyMouseDownCount: int
  spyMouseUpCount: int
  constraintEvents: seq[string]

protocol MouseSpyEvents of ResponderEventProtocol:
  method mouseDown(spy: MouseSpyView, event: MouseEvent): bool =
    spyMouseDownPoint = event.location
    inc spyMouseDownCount
    true

  method mouseUp(spy: MouseSpyView, event: MouseEvent): bool =
    spyMouseUpPoint = event.location
    inc spyMouseUpCount
    true

protocol LifecycleSpyViewEvents of ViewLifecycleProtocol:
  proc rememberViewWillMoveToSuperview(
      spy: LifecycleSpyView, superview: View
  ) {.slotFor: viewWillMoveToSuperview.} =
    spy.events.add "willSuperview"
    spy.superviews.add superview

  proc rememberViewDidMoveToSuperview(
      spy: LifecycleSpyView
  ) {.slotFor: viewDidMoveToSuperview.} =
    spy.events.add "didSuperview"

  proc rememberViewWillMoveToWindow(
      spy: LifecycleSpyView, window: Responder
  ) {.slotFor: viewWillMoveToWindow.} =
    spy.events.add "willWindow"
    spy.windows.add window

  proc rememberViewDidMoveToWindow(
      spy: LifecycleSpyView
  ) {.slotFor: viewDidMoveToWindow.} =
    spy.events.add "didWindow"

  proc rememberDidAddSubview(
      spy: LifecycleSpyView, subview: View
  ) {.slotFor: didAddSubview.} =
    spy.events.add "didAddSubview"
    spy.addedSubviews.add subview

  proc rememberWillRemoveSubview(
      spy: LifecycleSpyView, subview: View
  ) {.slotFor: willRemoveSubview.} =
    spy.events.add "willRemoveSubview"
    spy.removedSubviews.add subview

protocol LayoutSpyHooks of ViewLayoutProtocol:
  method layoutSubviews(spy: LayoutSpyView) =
    spy.events.add "layoutSubviews"

  method layout(spy: LayoutSpyView) =
    spy.events.add "layout"

protocol ConstraintSpyHooks of ViewLayoutProtocol:
  method updateConstraints(spy: ConstraintSpyView) =
    constraintEvents.add spy.name & ".updateConstraints"

  method layoutSubviews(spy: ConstraintSpyView) =
    constraintEvents.add spy.name & ".layoutSubviews"

  method layout(spy: ConstraintSpyView) =
    constraintEvents.add spy.name & ".layout"

proc newMouseSpyView(frame: Rect): MouseSpyView =
  result = MouseSpyView()
  initViewFields(result, frame)
  discard result.withProtocol(MouseSpyEvents)

proc newLifecycleSpyView(frame: Rect): LifecycleSpyView =
  result = LifecycleSpyView()
  initViewFields(result, frame)
  result = result.withProto()
  discard result.withProtocol(LifecycleSpyViewEvents)
  result.observeProtocol(result, LifecycleSpyViewEvents)

proc newLayoutSpyView(frame: Rect): LayoutSpyView =
  result = LayoutSpyView()
  initViewFields(result, frame)
  discard result.withProtocol(LayoutSpyHooks)

proc newConstraintSpyView(name: string, frame: Rect): ConstraintSpyView =
  result = ConstraintSpyView(name: name)
  initViewFields(result, frame)
  discard result.withProtocol(ConstraintSpyHooks)

suite "nimkit views":
  test "frame changes preserve bounds origin":
    let view = newView(frame = initRect(0, 0, 100, 80))

    view.bounds = initRect(20, 30, 100, 80)
    view.frame = initRect(10, 15, 120, 90)
    check view.bounds == initRect(20, 30, 120, 90)

    view.applyLayoutFrame(initRect(12, 18, 130, 95))
    check view.bounds == initRect(20, 30, 130, 95)

  test "subviews participate in hit testing from front to back":
    let root = newView(frame = initRect(0, 0, 200, 160))
    let back = newView(frame = initRect(20, 20, 80, 50))
    let front = newView(frame = initRect(30, 25, 80, 50))
    root.addSubview(back, front)

    check root.hitTest(initPoint(35, 30)) == front
    check root.hitTest(initPoint(22, 22)) == back
    check root.hitTest(initPoint(199, 159)) == root
    check root.hitTest(initPoint(220, 159)).isNil

  test "hidden views do not hit test":
    let root = newView(frame = initRect(0, 0, 200, 160))
    let child = newView(frame = initRect(20, 20, 80, 50))
    root.addSubview(child)
    child.hidden = true

    check root.hitTest(initPoint(25, 25)) == root

  test "unclipped subviews can hit test outside parent bounds":
    let
      root = newView(frame = initRect(0, 0, 200, 160))
      parent = newView(frame = initRect(20, 20, 40, 40))
      child = newView(frame = initRect(50, 0, 40, 40))

    root.addSubview(parent)
    parent.addSubview(child)

    check root.hitTest(initPoint(85, 30)) == child

    parent.clipsToBounds = true
    check root.hitTest(initPoint(85, 30)) == root

  test "child invalidation propagates to parent":
    let root = newView(frame = initRect(0, 0, 200, 160))
    let child = newView(frame = initRect(20, 20, 80, 50))
    root.addSubview(child)
    root.needsDisplay = false
    child.needsDisplay = false

    child.background = initColor(1, 0, 0)

    check child.needsDisplay
    check root.needsDisplay

  test "appearance inherits from application window and view":
    let
      app = newApplication()
      window = newWindow("Appearance", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      child = newView(frame = initRect(10, 10, 80, 40))

    root.addSubview(child)
    window.setContentView(root)
    app.addWindow(window)

    var appAppearance = initAppearance()
    let appFill = initColor(0.1, 0.2, 0.3, 1.0)
    appAppearance[srButton, StyleFill] = appFill
    app.setAppearance(appAppearance)

    let appStyle =
      child.effectiveAppearance().resolveButtonStyle(initControlStyleContext(srButton))
    check appStyle.box.fill == appFill

    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)

    var windowAppearance = initAppearance()
    let windowFill = initColor(0.4, 0.5, 0.6, 1.0)
    windowAppearance[srButton, StyleFill] = windowFill
    window.setAppearance(windowAppearance)

    let inheritedStyle =
      child.effectiveAppearance().resolveButtonStyle(initControlStyleContext(srButton))
    check inheritedStyle.box.fill == windowFill
    check root.needsDisplay
    check child.needsDisplay

    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)

    var rootAppearance = initAppearance()
    let rootFill = initColor(0.7, 0.2, 0.1, 1.0)
    rootAppearance[srButton, StyleFill] = rootFill
    root.appearance = rootAppearance

    let rootStyle =
      child.effectiveAppearance().resolveButtonStyle(initControlStyleContext(srButton))
    check rootStyle.box.fill == rootFill
    check root.needsDisplay
    check child.needsDisplay

    root.clearAppearance()
    let clearedStyle =
      child.effectiveAppearance().resolveButtonStyle(initControlStyleContext(srButton))
    check clearedStyle.box.fill == windowFill

  test "style identity is stored on views and invalidates display":
    let view = newView(frame = initRect(0, 0, 100, 80))
    view.needsDisplay = false

    view.styleId = "primary"
    check view.styleId == "primary"
    check view.needsDisplay

    view.needsDisplay = false
    view.styleClasses = ["toolbar", "primary"]
    check view.styleClasses == @["toolbar", "primary"]
    check view.hasStyleClass("toolbar")
    check view.needsDisplay

    view.setNeedsDisplay(false)
    view.addStyleClass("danger")
    check view.styleClasses == @["toolbar", "primary", "danger"]
    check view.needsDisplay

    view.setNeedsDisplay(false)
    view.removeStyleClass("primary")
    check view.styleClasses == @["toolbar", "danger"]
    check not view.hasStyleClass("primary")
    check view.needsDisplay

  test "clipsToBounds defaults off and invalidates display":
    let view = newView(frame = initRect(0, 0, 100, 80))

    check not view.clipsToBounds

    view.needsDisplay = false
    view.clipsToBounds = true
    check view.clipsToBounds
    check view.needsDisplay

    view.needsDisplay = false
    view.clipsToBounds = false
    check not view.clipsToBounds
    check view.needsDisplay

  test "layout lifecycle runs selector hooks before display cleanup":
    let
      root = newLayoutSpyView(initRect(0, 0, 200, 160))
      child = newLayoutSpyView(initRect(20, 30, 80, 40))

    root.addSubview(child)
    root.events.setLen(0)
    child.events.setLen(0)

    check root.needsLayout
    check child.needsLayout

    check root.prepareDisplaySubtree()
    check root.events == @["layoutSubviews", "layout"]
    check child.events == @["layoutSubviews", "layout"]
    check not root.needsLayout
    check not child.needsLayout

    root.frame = initRect(0, 0, 220, 180)
    check root.needsLayout
    root.finishDisplaySubtree()
    check not root.needsDisplay

  test "display update predicate includes display layout and constraints":
    let
      root = newView(frame = initRect(0, 0, 200, 160))
      child = newView(frame = initRect(20, 20, 80, 40))

    root.addSubview(child)
    discard root.prepareDisplaySubtree()
    root.finishDisplaySubtree()
    check not root.needsDisplayUpdateInSubtree()

    child.setNeedsDisplay(true)
    check root.needsDisplayUpdateInSubtree()
    root.finishDisplaySubtree()
    check not root.needsDisplayUpdateInSubtree()

    child.setNeedsLayout()
    check root.needsDisplayUpdateInSubtree()
    child.layoutSubtreeIfNeeded()
    check not root.needsDisplayUpdateInSubtree()

    child.setNeedsUpdateConstraints()
    check root.needsDisplayUpdateInSubtree()
    child.updateConstraintsForSubtreeIfNeeded()
    check not root.needsDisplayUpdateInSubtree()

  test "constraint update lifecycle runs before layout":
    let
      root = newConstraintSpyView("root", initRect(0, 0, 200, 160))
      child = newConstraintSpyView("child", initRect(20, 30, 80, 40))

    root.addSubview(child)
    root.needsLayout = false
    child.needsLayout = false
    constraintEvents.setLen(0)

    root.setNeedsUpdateConstraints()
    child.setNeedsUpdateConstraints()
    check root.needsUpdateConstraints
    check child.needsUpdateConstraints

    root.updateConstraintsForSubtreeIfNeeded()

    check constraintEvents == @["child.updateConstraints", "root.updateConstraints"]
    check not root.needsUpdateConstraints
    check not child.needsUpdateConstraints
    check not root.needsLayout
    check not child.needsLayout

    constraintEvents.setLen(0)
    root.needsLayout = true
    child.needsLayout = true
    root.setNeedsUpdateConstraints()
    child.setNeedsUpdateConstraints()

    root.layoutSubtreeIfNeeded()

    check constraintEvents ==
      @[
        "child.updateConstraints", "root.updateConstraints", "root.layoutSubviews",
        "root.layout", "child.layoutSubviews", "child.layout",
      ]
    check not root.needsUpdateConstraints
    check not child.needsUpdateConstraints
    check not root.needsLayout
    check not child.needsLayout

  test "setNeedsUpdateConstraints ignores false like AppKit":
    let view = newView(frame = initRect(0, 0, 100, 80))

    check not view.needsUpdateConstraints
    view.setNeedsUpdateConstraints(false)
    check not view.needsUpdateConstraints
    view.setNeedsUpdateConstraints()
    view.setNeedsUpdateConstraints(false)
    check view.needsUpdateConstraints

  test "setNeedsDisplayInRect clips and unions dirty rects":
    let view = newView(frame = initRect(0, 0, 100, 80))
    view.setNeedsDisplay(false)

    view.setNeedsDisplayInRect(initRect(10, 10, 20, 20))
    check view.needsDisplay
    check view.invalidRects == @[initRect(10, 10, 20, 20)]
    check view.invalidRect == initRect(10, 10, 20, 20)

    view.setNeedsDisplayInRect(initRect(25, 25, 50, 30))
    check view.invalidRects == @[initRect(10, 10, 65, 45)]
    check view.invalidRect == initRect(10, 10, 65, 45)

    view.setNeedsDisplayInRect(initRect(-10, -10, 20, 20))
    check view.invalidRects == @[initRect(0, 0, 75, 55)]

  test "visibleRect only clips through clipping ancestors":
    let
      root = newView(frame = initRect(0, 0, 100, 80))
      child = newView(frame = initRect(80, 60, 50, 40))
      grandchild = newView(frame = initRect(10, 10, 30, 30))

    root.addSubview(child)
    child.addSubview(grandchild)

    check root.visibleRect == initRect(0, 0, 100, 80)
    check child.visibleRect == initRect(0, 0, 50, 40)
    check grandchild.visibleRect == initRect(0, 0, 30, 30)

    root.clipsToBounds = true
    check child.visibleRect == initRect(0, 0, 20, 20)
    check grandchild.visibleRect == initRect(0, 0, 10, 10)

    root.hidden = true
    check root.visibleRect.isEmpty
    check child.visibleRect.isEmpty
    check grandchild.visibleRect.isEmpty

  test "setNeedsDisplayInRect clips to effective visibleRect":
    let
      root = newView(frame = initRect(0, 0, 100, 80))
      child = newView(frame = initRect(80, 60, 50, 40))

    root.addSubview(child)
    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)

    child.setNeedsDisplayInRect(initRect(0, 0, 50, 40))

    check child.invalidRects == @[initRect(0, 0, 50, 40)]
    check root.invalidRects == @[initRect(80, 60, 20, 20)]

    root.clipsToBounds = true
    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)

    child.setNeedsDisplayInRect(initRect(0, 0, 50, 40))

    check child.invalidRects == @[initRect(0, 0, 20, 20)]
    check root.invalidRects == @[initRect(80, 60, 20, 20)]

  test "child invalid rect propagates to parent coordinates":
    let
      root = newView(frame = initRect(0, 0, 200, 160))
      child = newView(frame = initRect(20, 30, 80, 50))

    root.addSubview(child)
    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)

    child.setNeedsDisplayInRect(initRect(5, 6, 10, 11))

    check child.invalidRects == @[initRect(5, 6, 10, 11)]
    check root.invalidRects == @[initRect(25, 36, 10, 11)]

  test "whole-view invalidation propagates as child frame":
    let
      root = newView(frame = initRect(0, 0, 200, 160))
      child = newView(frame = initRect(20, 30, 80, 50))

    root.addSubview(child)
    root.setNeedsDisplay(false)
    child.setNeedsDisplay(false)

    child.setNeedsDisplay(true)

    check child.invalidRects == @[initRect(0, 0, 80, 50)]
    check root.invalidRects == @[initRect(20, 30, 80, 50)]

  test "coordinate conversion covers hierarchy, siblings, and rectangles":
    let
      root = newView(frame = initRect(0, 0, 300, 240))
      child = newView(frame = initRect(20, 30, 100, 80))
      sibling = newView(frame = initRect(150, 40, 70, 60))
      grandchild = newView(frame = initRect(5, 7, 30, 20))

    root.addSubview(child)
    root.addSubview(sibling)
    child.addSubview(grandchild)

    check root.pointFromView(initPoint(3, 4), child) == initPoint(23, 34)
    check child.pointToView(initPoint(3, 4), root) == initPoint(23, 34)
    check child.pointFromView(initPoint(23, 34), root) == initPoint(3, 4)
    check sibling.pointFromView(initPoint(3, 4), child) == initPoint(-127, -6)
    check grandchild.pointToView(initPoint(1, 2), root) == initPoint(26, 39)

    check root.rectFromView(initRect(1, 2, 10, 11), child) == initRect(21, 32, 10, 11)
    check child.rectFromView(initRect(21, 32, 10, 11), root) == initRect(1, 2, 10, 11)

  test "coordinate conversion honors non-zero bounds origins":
    let
      root = newView(frame = initRect(0, 0, 300, 240))
      child = newView(frame = initRect(30, 40, 100, 80))

    root.setBounds(initRect(10, 20, 300, 240))
    child.setBounds(initRect(5, 6, 100, 80))
    root.addSubview(child)

    check child.pointFromView(initPoint(30, 40), root) == initPoint(5, 6)
    check root.pointFromView(initPoint(5, 6), child) == initPoint(30, 40)
    check child.pointToWindow(initPoint(5, 6)) == initPoint(20, 20)
    check child.pointFromWindow(initPoint(20, 20)) == initPoint(5, 6)

  test "coordinate conversion updates after reparenting":
    let
      firstRoot = newView(frame = initRect(0, 0, 200, 160))
      secondRoot = newView(frame = initRect(10, 15, 200, 160))
      child = newView(frame = initRect(20, 30, 80, 40))

    firstRoot.addSubview(child)
    check child.pointToWindow(initPoint(0, 0)) == initPoint(20, 30)

    secondRoot.addSubview(child)
    check child.superview == secondRoot
    check child.pointToWindow(initPoint(0, 0)) == initPoint(30, 45)

  test "add and remove subview route selector-backed lifecycle hooks":
    let
      parent = newLifecycleSpyView(initRect(0, 0, 200, 160))
      child = newLifecycleSpyView(initRect(20, 30, 80, 40))

    parent.addSubview(child)

    check child.superview == parent
    check nimkitResponders.nextResponder(Responder(child)) == Responder(parent)
    check parent.addedSubviews == @[View(child)]
    check child.superviews == @[View(parent)]
    check child.events == @["willSuperview", "didSuperview"]
    check parent.events == @["didAddSubview"]

    child.removeFromSuperview()

    check child.superview.isNil
    check nimkitResponders.nextResponder(Responder(child)).isNil
    check parent.removedSubviews == @[View(child)]
    check child.superviews.len == 2
    check child.superviews[1].isNil
    check child.events ==
      @["willSuperview", "didSuperview", "willSuperview", "didSuperview"]
    check parent.events == @["didAddSubview", "willRemoveSubview"]

  test "content view changes route window lifecycle through descendants":
    let
      window = newWindow("Lifecycle", frame = initRect(0, 0, 240, 160))
      root = newLifecycleSpyView(initRect(0, 0, 240, 160))
      child = newLifecycleSpyView(initRect(20, 30, 80, 40))
      replacement = newLifecycleSpyView(initRect(0, 0, 240, 160))

    root.addSubview(child)
    root.events.setLen(0)
    child.events.setLen(0)

    window.setContentView(root)

    check window.contentView == root
    check root.window == Responder(window)
    check child.window == Responder(window)
    check nimkitResponders.nextResponder(Responder(root)) == Responder(window)
    check nimkitResponders.nextResponder(Responder(child)) == Responder(root)
    check root.windows == @[Responder(window)]
    check child.windows == @[Responder(window)]
    check root.events == @["willWindow", "didWindow"]
    check child.events == @["willWindow", "didWindow"]

    window.setContentView(replacement)

    check window.contentView == replacement
    check root.window.isNil
    check child.window.isNil
    check nimkitResponders.nextResponder(Responder(root)).isNil
    check root.windows.len == 2
    check root.windows[1].isNil
    check child.windows.len == 2
    check child.windows[1].isNil
    check replacement.window == Responder(window)
    check nimkitResponders.nextResponder(Responder(replacement)) == Responder(window)

  test "content view replacement clears first responder from removed subtree":
    let
      window = newWindow("First responder cleanup", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      button = newButton("Action", frame = initRect(20, 30, 80, 30))

    root.addSubview(button)
    window.setContentView(root)

    check window.makeFirstResponder(button)
    check window.firstResponder == button

    window.setContentView(newView(frame = initRect(0, 0, 240, 160)))

    check window.firstResponder.isNil

  test "window coordinate helpers convert through content view frames and bounds":
    let content = newView(frame = initRect(10, 15, 240, 180))
    content.setBounds(initRect(5, 7, 240, 180))

    check content.pointToWindow(initPoint(5, 7)) == initPoint(10, 15)
    check content.pointFromWindow(initPoint(10, 15)) == initPoint(5, 7)
    check content.rectToWindow(initRect(5, 7, 20, 30)) == initRect(10, 15, 20, 30)
    check content.rectFromWindow(initRect(10, 15, 20, 30)) == initRect(5, 7, 20, 30)

  test "hit testing and mouse dispatch use conversion helpers":
    let
      root = newView(frame = initRect(0, 0, 200, 160))
      child = newMouseSpyView(initRect(30, 40, 80, 50))

    root.setBounds(initRect(10, 20, 200, 160))
    child.setBounds(initRect(5, 6, 80, 50))
    root.addSubview(child)

    spyMouseDownPoint = initPoint(0, 0)
    spyMouseUpPoint = initPoint(0, 0)
    spyMouseDownCount = 0
    spyMouseUpCount = 0

    check root.hitTest(initPoint(30, 40)) == child
    check root.clickAt(initPoint(30, 40))
    check spyMouseDownPoint == initPoint(5, 6)
    check spyMouseUpPoint == initPoint(5, 6)
    check spyMouseDownCount == 1
    check spyMouseUpCount == 1
