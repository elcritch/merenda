import std/[algorithm, macros]

import ../app/animations
import ../foundation/selectors
import ../themes
import ../drawing/drawing
import ../foundation/types
import ./viewgeometry
import ./viewbase
import sigils/core

protocol ViewProtocol {.setterStyle: nim.} from View:
  property tag -> int
  property identifier -> string
  property frame -> Rect
  property bounds -> Rect
  property needsDisplay -> bool
  property backgroundColor -> Color
  property hidden -> bool
  property flipped -> bool
  property focusRingType -> FocusRingType
  property alphaValue -> float32
  property shadow -> seq[BoxShadow]
  property toolTip -> string
  property styleId -> string
  property styleClasses -> seq[string]
  property usesThemedRootBackground -> bool
  property clipsToBounds -> bool
  property nextKeyView -> View
  property previousKeyView -> View

  method tag(self: View): int =
    self.xTag

  method `tag=`(self: View, tag: int) =
    self.xTag = tag

  method identifier(self: View): string =
    self.xIdentifier

  method `identifier=`(self: View, identifier: string) =
    self.xIdentifier = identifier

  method frame(self: View): Rect =
    self.xFrame

  method `frame=`(self: View, frame: Rect) =
    let nextFrame = self.resolvedFrame(frame)
    if frame.hasAutoMetric:
      self.autoresizingMaskConstraints = false
    if self.xFrame == nextFrame:
      return
    discard
      recordPropertyAnimation(DynamicAgent(self), `frame=`(), self.xFrame, nextFrame)
    self.xFrame = nextFrame
    self.xBounds = rect(self.xBounds.origin, nextFrame.size)
    self.invalidateLayoutItemGeometry(lirFrame)
    self.refreshAutoresizingReference()
    emit self.geometryDidChange()
    self.needsDisplay = true

  method bounds(self: View): Rect =
    self.xBounds

  method `bounds=`(self: View, bounds: Rect) =
    if self.xBounds == bounds:
      return
    discard
      recordPropertyAnimation(DynamicAgent(self), `bounds=`(), self.xBounds, bounds)
    self.xBounds = rect(bounds.origin, bounds.size)
    emit self.layoutInputChanged(lirBounds)
    emit self.geometryDidChange()
    self.needsDisplay = true

  method needsDisplay(self: View): bool =
    self.xNeedsDisplay

  method `needsDisplay=`(self: View, value: bool) =
    if not value:
      self.xNeedsDisplay = false
      self.xInvalidRects.setLen(0)
      return

    self.xNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    let parent = self.xSuperview
    if not parent.isNil:
      parent.setNeedsDisplayInRect(self.rectToView(self.bounds, parent))

  method setNeedsDisplayInRect*(self: View, rect: Rect) =
    let clipped = rect.intersection(self.visibleRect())
    if clipped.isEmpty:
      return

    if not self.xNeedsDisplay:
      self.xNeedsDisplay = true
      self.xInvalidRects = @[clipped]
    elif self.xInvalidRects.len > 0:
      self.xInvalidRects[0] = self.xInvalidRects[0].union(clipped)
      self.xInvalidRects.setLen(1)

    let parent = self.xSuperview
    if not parent.isNil:
      parent.setNeedsDisplayInRect(self.rectToView(clipped, parent))

  method invalidRect*(self: View): Rect =
    if not self.xNeedsDisplay:
      return rect(0.0, 0.0, 0.0, 0.0)
    if self.xInvalidRects.len == 0:
      return self.visibleRect()
    result = self.xInvalidRects[0]
    for idx in 1 ..< self.xInvalidRects.len:
      result = result.union(self.xInvalidRects[idx])

  method invalidRects*(self: View): seq[Rect] =
    if not self.xNeedsDisplay:
      return @[]
    if self.xInvalidRects.len == 0:
      return @[self.visibleRect()]
    self.xInvalidRects

  method backgroundColor(self: View): Color =
    self.xBackgroundColor

  method `backgroundColor=`(self: View, color: Color) =
    if self.xBackgroundColor == color:
      return
    self.xBackgroundColor = color
    self.needsDisplay = true

  method hidden(self: View): bool =
    self.isHidden()

  method flipped(self: View): bool =
    self.xFlipped

  method `flipped=`(self: View, flipped: bool) =
    if self.xFlipped == flipped:
      return
    self.xFlipped = flipped
    self.invalidateLayoutItemGeometry(lirBounds)
    self.setNeedsDisplaySubtree()

  method focusRingType(self: View): FocusRingType =
    self.xFocusRingType

  method `focusRingType=`(self: View, focusRingType: FocusRingType) =
    if self.xFocusRingType == focusRingType:
      return
    self.xFocusRingType = focusRingType
    self.needsDisplay = true

  method alphaValue(self: View): float32 =
    self.xAlphaValue

  method `alphaValue=`(self: View, alphaValue: float32) =
    let normalized = min(max(alphaValue, 0.0'f32), 1.0'f32)
    if self.xAlphaValue == normalized:
      return
    discard recordPropertyAnimation(
      DynamicAgent(self), `alphaValue=`(), self.xAlphaValue, normalized
    )
    self.xAlphaValue = normalized
    self.setNeedsDisplaySubtree()

  method shadow(self: View): seq[BoxShadow] =
    self.xShadow

  method `shadow=`(self: View, shadows: seq[BoxShadow]) =
    if self.xShadow == shadows:
      return
    self.xShadow = shadows
    self.needsDisplay = true

  method toolTip(self: View): string =
    self.xToolTip

  method `toolTip=`(self: View, toolTip: string) =
    self.xToolTip = toolTip

  method styleId(self: View): string =
    self.xStyleId

  method `styleId=`(self: View, id: string) =
    if self.xStyleId == id:
      return
    self.xStyleId = id
    self.invalidateIntrinsicContentSize()
    self.needsDisplay = true

  method styleClasses(self: View): seq[string] =
    self.xStyleClasses

  method `styleClasses=`(self: View, classes: seq[string]) =
    if self.xStyleClasses == classes:
      return
    self.xStyleClasses = classes
    self.invalidateIntrinsicContentSize()
    self.needsDisplay = true

  method usesThemedRootBackground(self: View): bool =
    self.xUsesThemedRootBackground

  method `usesThemedRootBackground=`(self: View, enabled: bool) =
    if self.xUsesThemedRootBackground == enabled:
      return
    self.xUsesThemedRootBackground = enabled
    self.needsDisplay = true

  method clipsToBounds(self: View): bool =
    self.xClipsToBounds

  method `clipsToBounds=`(self: View, clipsToBounds: bool) =
    if self.xClipsToBounds == clipsToBounds:
      return
    self.xClipsToBounds = clipsToBounds
    self.setNeedsDisplaySubtree()

  method nextKeyView(self: View): View =
    self.xNextKeyView

  method `nextKeyView=`(self: View, next: View) =
    if self.xNextKeyView == next:
      return

    let oldNext = self.xNextKeyView
    if not oldNext.isNil and oldNext.xPreviousKeyView == self:
      oldNext.xPreviousKeyView = nil

    self.xNextKeyView = next
    if not next.isNil:
      let oldPrevious = next.xPreviousKeyView
      if not oldPrevious.isNil and oldPrevious != self and
          oldPrevious.xNextKeyView == next:
        oldPrevious.xNextKeyView = nil
      next.xPreviousKeyView = self

  method previousKeyView(self: View): View =
    self.xPreviousKeyView

  method `previousKeyView=`(self: View, previous: View) =
    if self.xPreviousKeyView == previous:
      return
    if previous.isNil:
      let oldPrevious = self.xPreviousKeyView
      if not oldPrevious.isNil and oldPrevious.xNextKeyView == self:
        oldPrevious.xNextKeyView = nil
      self.xPreviousKeyView = nil
      return
    previous.nextKeyView = self

  method canBecomeKeyView*(self: View): bool =
    self.viewCanBecomeKeyView()

  method nextValidKeyView*(self: View): View =
    var candidate = self.nextKeyView()
    var hopCount = 0
    while not candidate.isNil and hopCount < 4096:
      if candidate == self:
        if candidate.canBecomeKeyView():
          return candidate
        return nil
      if candidate.canBecomeKeyView():
        return candidate
      candidate = candidate.nextKeyView()
      inc hopCount

  method previousValidKeyView*(self: View): View =
    var candidate = self.previousKeyView()
    var hopCount = 0
    while not candidate.isNil and hopCount < 4096:
      if candidate == self:
        if candidate.canBecomeKeyView():
          return candidate
        return nil
      if candidate.canBecomeKeyView():
        return candidate
      candidate = candidate.previousKeyView()
      inc hopCount

  method isHidden*(self: View): bool =
    ssHidden in self.xWidgetStates

  method `hidden=`*(self: View, hidden: bool) =
    if (ssHidden in self.xWidgetStates) == hidden:
      return
    if hidden:
      self.xWidgetStates.incl(ssHidden)
    else:
      self.xWidgetStates.excl(ssHidden)
    self.invalidateLayoutItemGeometry(lirHidden)
    self.needsDisplay = true

  method isHiddenOrHasHiddenAncestor*(self: View): bool =
    var current = self
    while not current.isNil:
      if ssHidden in current.xWidgetStates:
        return true
      current = current.xSuperview
    false

  method visibleRect*(self: View): Rect =
    if self.isHiddenOrHasHiddenAncestor():
      return
    result = self.xBounds
    var ancestor = self.xSuperview
    while not ancestor.isNil:
      if ancestor.xClipsToBounds:
        result = result.intersection(self.rectFromView(ancestor.xBounds, ancestor))
        if result.isEmpty:
          return
      ancestor = ancestor.xSuperview

  method superview*(self: View): View =
    self.xSuperview

  method window*(self: View): Responder =
    self.xWindow

  method subviews*(self: View): seq[View] =
    self.xSubviews

  method removeFromSuperview*(self: View) =
    let parent = self.xSuperview
    if parent.isNil:
      return
    let oldWindow = self.xWindow
    emit parent.willRemoveSubview(self)
    emit self.viewWillMoveToSuperview(nil)
    if oldWindow != nil:
      self.propagateWillMoveToWindow(nil)
    let idx = parent.xSubviews.find(self)
    if idx >= 0:
      parent.xSubviews.delete(idx)
      emit self.layoutInputChanged(lirSuperview)
      emit parent.layoutInputChanged(lirHierarchy)
      parent.setNeedsDisplayInRect(self.rectToView(self.bounds, parent))
    self.xSuperview = nil
    self.resetAutoresizingState()
    self.clearNextResponder()
    self.nextKeyView = nil
    self.previousKeyView = nil
    self.setWindowOwner(nil)
    self.clearInheritedAppearance()
    emit self.viewDidMoveToSuperview()
    if oldWindow != nil:
      self.propagateDidMoveToWindow()
    emit self.layoutInputChanged(lirSuperview)

  method addSubview*(self: View, child: View) =
    if child.isNil:
      return
    if not child.xSuperview.isNil:
      child.removeFromSuperview()
    let oldWindow = child.xWindow
    emit child.viewWillMoveToSuperview(self)
    if oldWindow != self.xWindow:
      child.propagateWillMoveToWindow(self.xWindow)
    child.xSuperview = self
    child.refreshAutoresizingReference()
    self.xSubviews.add child
    child.setNextResponder(self)
    child.setWindowOwner(self.xWindow)
    child.setInheritedAppearance(self.effectiveAppearance())
    emit self.didAddSubview(child)
    emit child.viewDidMoveToSuperview()
    if oldWindow != self.xWindow:
      child.propagateDidMoveToWindow()
    emit child.layoutInputChanged(lirSuperview)
    emit self.layoutInputChanged(lirHierarchy)
    self.setNeedsDisplayInRect(child.rectToView(child.bounds, self))

  method pointInside*(self: View, point: Point): bool =
    self.xBounds.contains(point)

  method hitTestLevel*(self: View, point: Point): int =
    DefaultDrawLevel.int

  method hitTest*(self: View, point: Point): View =
    if self.isHidden():
      return nil

    let inside = self.pointInside(point)
    if inside or not self.xClipsToBounds:
      var
        bestHit: View
        bestLevel = low(int)
      for idx in countdown(self.xSubviews.high, 0):
        let child = self.xSubviews[idx]
        let local = child.pointFromView(point, self)
        let hit = child.hitTest(local)
        if not hit.isNil:
          let
            hitLocal = hit.pointFromView(point, self)
            level = max(child.hitTestLevel(local), hit.hitTestLevel(hitLocal))
          if bestHit.isNil or level > bestLevel:
            bestHit = hit
            bestLevel = level
      if not bestHit.isNil:
        return bestHit

    if inside: self else: nil

protocol ViewLifecycleProtocol:
  proc viewWillMoveToSuperview*(view: View, superview: View) {.signal.}
  proc viewDidMoveToSuperview*(view: View) {.signal.}
  proc viewWillMoveToWindow*(view: View, window: Responder) {.signal.}
  proc viewDidMoveToWindow*(view: View) {.signal.}
  proc didAddSubview*(view: View, subview: View) {.signal.}
  proc willRemoveSubview*(view: View, subview: View) {.signal.}

protocol ViewSuperviewLifecycleSlots of ViewLifecycleProtocol:
  proc unbindSuperviewGeometry(
      view: View, superview: View
  ) {.slotFor: viewWillMoveToSuperview.} =
    view.unobserveSuperviewGeometry()

  proc bindSuperviewGeometry(view: View) {.slotFor: viewDidMoveToSuperview.} =
    view.observeSuperviewGeometry()

proc background*(view: View): Color =
  view.backgroundColor()

proc `background=`*(view: View, color: Color) =
  view.backgroundColor = color

proc setNeedsDisplaySubtree*(view: View) =
  view.needsDisplay = true
  for child in view.xSubviews:
    child.setNeedsDisplaySubtree()

proc viewCanBecomeKeyView*(view: View): bool =
  view.acceptsFirstResponder() and not view.isHiddenOrHasHiddenAncestor()

proc hasAppearance*(view: View): bool =
  view.xHasAppearance

proc appearance*(view: View): Appearance =
  if not view.xHasAppearance:
    return initAppearance()
  view.xAppearance

proc effectiveAppearance*(view: View): Appearance =
  if view.xHasAppearance:
    return view.xAppearance
  if not view.xSuperview.isNil:
    return view.xSuperview.effectiveAppearance()
  if view.xHasInheritedAppearance:
    return view.xInheritedAppearance
  initAppearance()

proc resolvedAppearance*(view: View, inherited: Appearance): Appearance =
  if view.xHasAppearance:
    return view.xAppearance
  if view.xHasInheritedAppearance and view.xSuperview.isNil:
    return view.xInheritedAppearance
  inherited

proc `appearance=`*(view: View, appearance: Appearance) =
  view.xAppearance = appearance
  view.xHasAppearance = true
  view.invalidateIntrinsicContentSizeSubtree(lirAppearanceMetrics)
  view.setNeedsDisplaySubtree()

proc clearAppearance*(view: View) =
  if not view.xHasAppearance:
    return
  view.xAppearance = Appearance()
  view.xHasAppearance = false
  view.invalidateIntrinsicContentSizeSubtree(lirAppearanceMetrics)
  view.setNeedsDisplaySubtree()

proc assignInheritedAppearance(view: View, appearance: Appearance) =
  view.xInheritedAppearance = appearance
  view.xHasInheritedAppearance = true
  for child in view.xSubviews:
    child.assignInheritedAppearance(appearance)

proc setInheritedAppearance*(view: View, appearance: Appearance) =
  view.assignInheritedAppearance(appearance)
  view.invalidateIntrinsicContentSizeSubtree(lirAppearanceMetrics)
  view.setNeedsDisplaySubtree()

proc clearInheritedAppearanceFields(view: View) =
  view.xInheritedAppearance = Appearance()
  view.xHasInheritedAppearance = false
  for child in view.xSubviews:
    child.clearInheritedAppearanceFields()

proc clearInheritedAppearance*(view: View) =
  view.clearInheritedAppearanceFields()
  view.invalidateIntrinsicContentSizeSubtree(lirAppearanceMetrics)
  view.setNeedsDisplaySubtree()

proc propagateWillMoveToWindow*(view: View, window: Responder) =
  emit view.viewWillMoveToWindow(window)
  for child in view.xSubviews:
    child.propagateWillMoveToWindow(window)

proc propagateDidMoveToWindow*(view: View) =
  emit view.viewDidMoveToWindow()
  for child in view.xSubviews:
    child.propagateDidMoveToWindow()

proc setWindowOwner*(view: View, window: Responder) =
  view.xWindow = window
  for child in view.xSubviews:
    child.setWindowOwner(window)

proc attachSubviewAt(view, child: View, index: Natural) =
  if child.isNil:
    return
  if not child.xSuperview.isNil:
    child.removeFromSuperview()
  let oldWindow = child.xWindow
  emit child.viewWillMoveToSuperview(view)
  if oldWindow != view.xWindow:
    child.propagateWillMoveToWindow(view.xWindow)
  child.xSuperview = view
  child.refreshAutoresizingReference()
  view.xSubviews.insert(child, min(index, view.xSubviews.len))
  child.setNextResponder(view)
  child.setWindowOwner(view.xWindow)
  child.setInheritedAppearance(view.effectiveAppearance())
  emit view.didAddSubview(child)
  emit child.viewDidMoveToSuperview()
  if oldWindow != view.xWindow:
    child.propagateDidMoveToWindow()
  emit child.layoutInputChanged(lirSuperview)
  emit view.layoutInputChanged(lirHierarchy)
  view.setNeedsDisplayInRect(child.rectToView(child.bounds, view))

proc insertSubview*(view, child: View, index: Natural) =
  if view.isNil:
    return
  view.attachSubviewAt(child, index)

proc addSubview*(
    view, child: View, positioned: SubviewPosition, relativeTo: View = nil
) =
  if view.isNil:
    return
  var index = if positioned == svpBelow: 0 else: view.xSubviews.len
  if not relativeTo.isNil:
    let relativeIndex = view.xSubviews.find(relativeTo)
    if relativeIndex >= 0:
      index =
        if positioned == svpBelow:
          relativeIndex
        else:
          relativeIndex + 1
  view.attachSubviewAt(child, index)

proc replaceSubview*(view, oldChild, newChild: View): bool =
  if view.isNil or oldChild.isNil or oldChild.xSuperview != view:
    return
  let index = view.xSubviews.find(oldChild)
  if index < 0:
    return
  oldChild.removeFromSuperview()
  if not newChild.isNil:
    view.attachSubviewAt(newChild, index)
  true

proc sortSubviews*(view: View, compare: proc(a, b: View): int) =
  if compare.isNil:
    return
  view.xSubviews.sort(compare)
  emit view.layoutInputChanged(lirHierarchy)
  view.needsDisplay = true

type NamedSubview* = tuple[view: View, name: string]

func inferredSubviewIdentifier(node: NimNode): string =
  case node.kind
  of nnkIdent:
    $node
  of nnkAccQuoted:
    node.repr
  else:
    ""

macro autoNames*(rest: varargs[untyped]): untyped =
  ## Builds named subview tuples using each simple argument's variable name.
  let viewType = bindSym"View"
  result = newTree(nnkBracket)
  for child in rest:
    result.add newTree(
      nnkTupleConstr,
      newColonExpr(ident"view", newCall(viewType, child)),
      newColonExpr(ident"name", newLit(child.inferredSubviewIdentifier())),
    )

proc addSubviews*(view: View, subviews: openArray[NamedSubview], override = false) =
  ## Adds several subviews and assigns provided names as identifiers.
  ## Existing identifiers are preserved unless ``override`` is true.
  for subview in subviews:
    if not subview.view.isNil and (override or subview.view.xIdentifier.len == 0):
      subview.view.xIdentifier = subview.name
    view.addSubview(subview.view)
