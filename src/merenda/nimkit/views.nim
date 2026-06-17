import sigils/core

import ./responders
import ./selectors
import ./types
import ./viewconstraints
import ./events
import ./theme
import ./viewgeometry
import ./viewprotos
import ./viewbase
import ./accessibilityprotocols

export responders
export viewbase except
  AutoresizingState, LayoutInputKind, LayoutTerm, LayoutEquation, LayoutInput,
  LayoutInputCache
export viewconstraints except generatedLayoutInputs, applyConstraintsForSubtree
export viewgeometry except
  resetAutoresizingState, refreshAutoresizingReference,
  refreshAutoresizingReferenceIfNeeded, applyLayoutFrame, setFrameFromLayout,
  initLayoutSignalBus, markConstraintStorageChanged, observeSuperviewGeometry,
  unobserveSuperviewGeometry, invalidateLayoutItemGeometry, ViewLayoutInputSlots,
  ViewSuperviewGeometrySlots
export viewprotos except ViewSuperviewLifecycleSlots

proc tag*(view: View): int =
  if view.isNil: 0 else: view.xTag

proc `tag=`*(view: View, tag: int) =
  if view.isNil:
    return
  view.xTag = tag

proc identifier*(view: View): string =
  if view.isNil: "" else: view.xIdentifier

proc `identifier=`*(view: View, identifier: string) =
  if view.isNil:
    return
  view.xIdentifier = identifier

proc viewWithTag*(view: View, tag: int): View =
  if view.isNil:
    return nil
  if view.xTag == tag:
    return view
  for child in view.xSubviews:
    let match = child.viewWithTag(tag)
    if not match.isNil:
      return match

proc flipped*(view: View): bool =
  view.isNil or view.xFlipped

proc isFlipped*(view: View): bool =
  view.flipped()

proc `flipped=`*(view: View, flipped: bool) =
  if view.isNil or view.xFlipped == flipped:
    return
  view.xFlipped = flipped
  view.invalidateLayoutItemGeometry(lirBounds)
  view.setNeedsDisplaySubtree()

proc focusRingType*(view: View): FocusRingType =
  if view.isNil: frtDefault else: view.xFocusRingType

proc `focusRingType=`*(view: View, focusRingType: FocusRingType) =
  if view.isNil or view.xFocusRingType == focusRingType:
    return
  view.xFocusRingType = focusRingType
  view.setNeedsDisplay(true)

proc alphaValue*(view: View): float32 =
  if view.isNil: 1.0'f32 else: view.xAlphaValue

proc `alphaValue=`*(view: View, alphaValue: float32) =
  if view.isNil:
    return
  let normalized = min(max(alphaValue, 0.0'f32), 1.0'f32)
  if view.xAlphaValue == normalized:
    return
  view.xAlphaValue = normalized
  view.setNeedsDisplaySubtree()

proc shadow*(view: View): seq[BoxShadow] =
  if view.isNil:
    @[]
  else:
    view.xShadow

proc `shadow=`*(view: View, shadows: openArray[BoxShadow]) =
  if view.isNil:
    return
  let nextShadows = @shadows
  if view.xShadow == nextShadows:
    return
  view.xShadow = nextShadows
  view.setNeedsDisplay(true)

proc toolTip*(view: View): string =
  if view.isNil: "" else: view.xToolTip

proc `toolTip=`*(view: View, toolTip: string) =
  if view.isNil:
    return
  view.xToolTip = toolTip

proc cursorRects*(view: View): seq[ViewCursorRect] =
  if view.isNil:
    @[]
  else:
    view.xCursorRects

proc addCursorRect*(view: View, rect: Rect, cursor: string) =
  if view.isNil:
    return
  view.xCursorRects.add ViewCursorRect(rect: rect, cursor: cursor)

proc discardCursorRects*(view: View) =
  if view.isNil:
    return
  view.xCursorRects.setLen(0)

proc trackingAreas*(view: View): seq[ViewTrackingArea] =
  if view.isNil:
    @[]
  else:
    view.xTrackingAreas

proc addTrackingArea*(view: View, area: ViewTrackingArea) =
  if view.isNil:
    return
  view.xTrackingAreas.add area

proc removeTrackingArea*(view: View, tag: int): bool =
  if view.isNil:
    return
  for idx, area in view.xTrackingAreas:
    if area.tag == tag:
      view.xTrackingAreas.delete(idx)
      return true

proc discardTrackingAreas*(view: View) =
  if view.isNil:
    return
  view.xTrackingAreas.setLen(0)

proc registeredDraggedTypes*(view: View): seq[string] =
  if view.isNil:
    @[]
  else:
    view.xRegisteredDraggedTypes

proc registerForDraggedTypes*(view: View, types: openArray[string]) =
  if view.isNil:
    return
  view.xRegisteredDraggedTypes = @types

proc unregisterDraggedTypes*(view: View) =
  if view.isNil:
    return
  view.xRegisteredDraggedTypes.setLen(0)

proc autoscroll*(view: View, event: MouseEvent): bool =
  discard view
  discard event

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
  let idx = view.xStyleClasses.find(className)
  if idx < 0:
    return
  view.xStyleClasses.delete(idx)
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc widgetStateSet*(view: View): set[WidgetState] =
  view.xWidgetStates

proc setWidgetState*(view: View, state: WidgetState, value: bool) =
  if view.isNil or value == (state in view.xWidgetStates):
    return
  if value:
    view.xWidgetStates.incl state
  else:
    view.xWidgetStates.excl state
  view.setNeedsDisplay(true)

proc isHovered*(view: View): bool =
  ssHovered in view.xWidgetStates

proc hovered*(view: View): bool =
  view.isHovered()

proc `hovered=`*(view: View, hovered: bool) =
  view.setWidgetState(ssHovered, hovered)

proc isActive*(view: View): bool =
  (not view.isNil) and ssActive in view.xWidgetStates

proc active*(view: View): bool =
  view.isActive()

proc `active=`*(view: View, active: bool) =
  view.setWidgetState(ssActive, active)

proc isFocused*(view: View): bool =
  (not view.isNil) and ssFocused in view.xWidgetStates

proc focused*(view: View): bool =
  view.isFocused()

proc `focused=`*(view: View, focused: bool) =
  view.setWidgetState(ssFocused, focused)

proc isFocusVisible*(view: View): bool =
  (not view.isNil) and ssFocusVisible in view.xWidgetStates

proc focusVisible*(view: View): bool =
  view.isFocusVisible()

proc `focusVisible=`*(view: View, focusVisible: bool) =
  view.setWidgetState(ssFocusVisible, focusVisible)

protocol DefaultViewResponder of ResponderProtocol:
  method setFirstResponderFocusState(view: View, focused, focusVisible: bool) =
    if view.isNil:
      return
    var states = view.xWidgetStates
    if focused:
      states.incl ssFocused
    else:
      states.excl ssFocused
    if focusVisible:
      states.incl ssFocusVisible
    else:
      states.excl ssFocusVisible
    if view.xWidgetStates == states:
      return
    view.xWidgetStates = states
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
  view.xNeedsUpdateConstraints = false
  discard view.sendLocalIfHandled(updateConstraints())

proc updateConstraintsForSubtreeIfNeeded*(view: View) =
  for child in view.xSubviews:
    child.updateConstraintsForSubtreeIfNeeded()
  if view.xNeedsUpdateConstraints:
    view.runUpdateConstraints()

proc needsLayout*(view: View): bool =
  (not view.isNil) and view.xNeedsLayout

proc `needsLayout=`*(view: View, value: bool) =
  view.xNeedsLayout = value

proc setNeedsLayout*(view: View) =
  view.needsLayout = true

proc layoutSubtree(view: View) =
  if view.xNeedsLayout:
    view.xNeedsLayout = false
    discard view.sendLocalIfHandled(layoutSubviews())
    discard view.sendLocalIfHandled(layout())
  for child in view.xSubviews:
    child.layoutSubtree()

proc layoutSubtreeIfNeeded*(view: View) =
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

proc needsDisplayUpdateInSubtree*(view: View): bool =
  if view.isNil:
    return false
  if view.xNeedsDisplay or view.xNeedsLayout or view.xNeedsUpdateConstraints:
    return true
  for child in view.xSubviews:
    if child.needsDisplayUpdateInSubtree():
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
  view.xFlipped = true
  view.xAlphaValue = 1.0'f32
  view.xNeedsDisplay = true
  view.xNeedsLayout = true
  view.xAutoresizingMaskConstraints = not frame.hasAutoMetric
  view.xHuggingPriority[laHorizontal] = LayoutPriorityLow
  view.xHuggingPriority[laVertical] = LayoutPriorityLow
  view.xCompressionPriority[laHorizontal] = LayoutPriorityHigh
  view.xCompressionPriority[laVertical] = LayoutPriorityHigh
  view.xBackgroundColor = initColor(0.94, 0.95, 0.97, 1.0)
  discard view.withProto()
  discard view.withProtocol(DefaultViewResponder)
  discard view.withProtocol(DefaultAccessibilityProtocol)
  view.observeProtocol(view, ViewSuperviewLifecycleSlots)

proc newView*(frame: Rect = AutoRect): View =
  result = View()
  initViewFields(result, frame)

proc handleMouse*(view: View, selector: MouseEventSelector, event: MouseEvent): bool =
  ## ``true`` means event handled and should not bubble further.
  ## ``false`` means event should continue up the responder chain.
  var handled = false
  view.performLocal(selector, event, handled) and handled

proc clearNeedsDisplayTree*(view: View) =
  view.finishDisplaySubtree()

proc clickAt*(view: View, point: Point): bool =
  let hit = view.hitTest(point)
  if hit.isNil:
    return false

  let event = MouseEvent(
    location: hit.pointFromView(point, view), button: mbPrimary, clickCount: 1
  )
  discard hit.handleMouse(mouseDown(), event)
  result = hit.handleMouse(mouseUp(), event)
