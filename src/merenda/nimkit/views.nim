import ./responders
import ./selectors
import ./types
import ./viewconstraints
import ./viewgeometry
import ./viewprotos
import ./viewbase

export responders
export viewbase except
  AutoresizingState, LayoutInputKind, LayoutTerm, LayoutEquation, LayoutInput,
  LayoutInputCache
export viewconstraints except generatedLayoutInputs, applyConstraintsForSubtree
export viewgeometry except
  resetAutoresizingState, refreshAutoresizingReference,
  refreshAutoresizingReferenceIfNeeded, applyLayoutFrame, setFrameFromLayout,
  initLayoutSignalBus, markConstraintStorageChanged,
  propagateAutoresizingDependentsChanged, invalidateLayoutItemGeometry,
  onLayoutInputChanged
export viewprotos

proc styleId*(view: View): string =
  if view.isNil: "" else: view.xStyleId

proc `styleId=`*(view: View, id: string) =
  if view.isNil or view.xStyleId == id:
    return
  view.xStyleId = id
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc styleClasses*(view: View): seq[string] =
  if view.isNil:
    @[]
  else:
    view.xStyleClasses

proc `styleClasses=`*(view: View, classes: openArray[string]) =
  if view.isNil:
    return
  let nextClasses = @classes
  if view.xStyleClasses == nextClasses:
    return
  view.xStyleClasses = nextClasses
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc hasStyleClass*(view: View, className: string): bool =
  (not view.isNil) and view.xStyleClasses.find(className) >= 0

proc addStyleClass*(view: View, className: string) =
  if view.isNil or view.hasStyleClass(className):
    return
  view.xStyleClasses.add className
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc removeStyleClass*(view: View, className: string) =
  if view.isNil:
    return
  let idx = view.xStyleClasses.find(className)
  if idx < 0:
    return
  view.xStyleClasses.delete(idx)
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc isHovered*(view: View): bool =
  (not view.isNil) and view.xHovered

proc hovered*(view: View): bool =
  view.isHovered()

proc `hovered=`*(view: View, hovered: bool) =
  if view.isNil or view.xHovered == hovered:
    return
  view.xHovered = hovered
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc isActive*(view: View): bool =
  (not view.isNil) and view.xActive

proc active*(view: View): bool =
  view.isActive()

proc `active=`*(view: View, active: bool) =
  if view.isNil or view.xActive == active:
    return
  view.xActive = active
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc isFocused*(view: View): bool =
  (not view.isNil) and view.xHasFocus

proc focused*(view: View): bool =
  view.isFocused()

proc `focused=`*(view: View, focused: bool) =
  if view.isNil or view.xHasFocus == focused:
    return
  view.xHasFocus = focused
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc isFocusVisible*(view: View): bool =
  (not view.isNil) and view.xFocusVisible

proc focusVisible*(view: View): bool =
  view.isFocusVisible()

proc `focusVisible=`*(view: View, focusVisible: bool) =
  if view.isNil or view.xFocusVisible == focusVisible:
    return
  view.xFocusVisible = focusVisible
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc needsUpdateConstraints*(view: View): bool =
  (not view.isNil) and view.xNeedsUpdateConstraints

proc setNeedsUpdateConstraints*(view: View, value: bool) =
  if view.isNil or not value:
    return
  view.xNeedsUpdateConstraints = true

proc setNeedsUpdateConstraints*(view: View) =
  view.setNeedsUpdateConstraints(true)

proc runUpdateConstraints(view: View) =
  if view.isNil:
    return
  view.xNeedsUpdateConstraints = false
  discard view.sendIfHandled(updateConstraints())

proc updateConstraintsForSubtreeIfNeeded*(view: View) =
  if view.isNil:
    return
  for child in view.xSubviews:
    child.updateConstraintsForSubtreeIfNeeded()
  if view.xNeedsUpdateConstraints:
    view.runUpdateConstraints()

proc needsLayout*(view: View): bool =
  (not view.isNil) and view.xNeedsLayout

proc `needsLayout=`*(view: View, value: bool) =
  if view.isNil:
    return
  view.xNeedsLayout = value

proc setNeedsLayout*(view: View) =
  view.needsLayout = true

proc layoutSubtree(view: View) =
  if view.isNil:
    return
  if view.xNeedsLayout:
    view.xNeedsLayout = false
    discard view.sendIfHandled(layoutSubviews())
    discard view.sendIfHandled(layout())
  for child in view.xSubviews:
    child.layoutSubtree()

proc layoutSubtreeIfNeeded*(view: View) =
  if view.isNil:
    return
  view.updateConstraintsForSubtreeIfNeeded()
  view.applyConstraintsForSubtree()
  view.layoutSubtree()

proc dirtyRects*(view: View): seq[Rect] =
  if view.isNil:
    @[]
  else:
    view.invalidRects()

proc needsDisplayInSubtree*(view: View): bool =
  if view.isNil:
    return false
  if view.needsDisplay:
    return true
  for child in view.xSubviews:
    if child.needsDisplayInSubtree():
      return true
  false

proc prepareDisplaySubtree*(view: View): bool =
  if view.isNil:
    return false
  view.layoutSubtreeIfNeeded()
  view.needsDisplayInSubtree()

proc finishDisplaySubtree*(view: View) =
  if view.isNil:
    return
  view.setNeedsDisplay(false)
  for child in view.xSubviews:
    child.finishDisplaySubtree()

proc moveToWindowOwner*(view: View, window: Responder) =
  if view.isNil or view.xWindow == window:
    return
  view.propagateWillMoveToWindow(window)
  view.setWindowOwner(window)
  view.propagateDidMoveToWindow()

proc clearSuperviewForWindowOwner*(view: View) =
  if view.isNil:
    return
  view.xSuperview = nil
  view.clearNextResponder()

proc containsView*(view, candidate: View): bool =
  if view.isNil or candidate.isNil:
    return false
  if view == candidate:
    return true
  for child in view.xSubviews:
    if child.containsView(candidate):
      return true
  false

proc initViewFields*(view: View, frame: Rect = AutoRect) =
  initResponder(view)
  view.initLayoutSignalBus()
  view.xFrame = frame.resolveAutoRect(initRect(0.0, 0.0, 0.0, 0.0))
  view.xBounds = initRect(0.0, 0.0, view.xFrame.size.width, view.xFrame.size.height)
  view.xNeedsDisplay = true
  view.xNeedsLayout = true
  view.xAutoresizingMaskConstraints = not frame.hasAutoMetric
  view.xHuggingPriority[laHorizontal] = LayoutPriorityLow
  view.xHuggingPriority[laVertical] = LayoutPriorityLow
  view.xCompressionPriority[laHorizontal] = LayoutPriorityHigh
  view.xCompressionPriority[laVertical] = LayoutPriorityHigh
  view.xBackgroundColor = initColor(0.94, 0.95, 0.97, 1.0)
  discard view.withProto()

proc newView*(frame: Rect = AutoRect): View =
  result = View()
  initViewFields(result, frame)

proc handleMouseDown*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseDown(), event)

proc handleMouseUp*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseUp(), event)

proc handleMouseEntered*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseEntered(), event)

proc handleMouseExited*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseExited(), event)

proc handleMouseMoved*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseMoved(), event)

proc handleMouseDragged*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseDragged(), event)

proc handleScrollWheel*(view: View, event: ScrollEvent): bool =
  view.sendLocalIfHandled(scrollWheel(), event)

proc handleKeyDown*(view: View, event: KeyEvent): bool =
  view.sendLocalIfHandled(keyDown(), event)

proc clearNeedsDisplayTree*(view: View) =
  view.finishDisplaySubtree()

proc clickAt*(view: View, point: Point): bool =
  let hit = view.hitTest(point)
  if hit.isNil:
    return false

  let event = MouseEvent(
    location: hit.pointFromView(point, view), button: mbPrimary, clickCount: 1
  )
  discard hit.handleMouseDown(event)
  result = hit.handleMouseUp(event)
