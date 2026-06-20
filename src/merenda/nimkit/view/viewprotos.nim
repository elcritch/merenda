import std/[algorithm, macros]

import ../foundation/selectors
import ../drawing/theme
import ../foundation/types
import ./viewgeometry
import ./viewbase
import sigils/core

protocol ViewProtocol from View:
  property frame -> Rect
  property bounds -> Rect
  property needsDisplay -> bool
  property backgroundColor -> Color
  property clipsToBounds -> bool
  property nextKeyView -> View
  property previousKeyView -> View

  method frame(self: View): Rect =
    self.xFrame

  method setFrame(self: View, frame: Rect) =
    let nextFrame = self.resolvedFrame(frame)
    if frame.hasAutoMetric:
      self.autoresizingMaskConstraints = false
    if self.xFrame == nextFrame:
      return
    self.xFrame = nextFrame
    self.xBounds = initRect(self.xBounds.origin, nextFrame.size)
    self.invalidateLayoutItemGeometry(lirFrame)
    self.refreshAutoresizingReference()
    emit self.geometryDidChange()
    self.setNeedsDisplay(true)

  method bounds(self: View): Rect =
    self.xBounds

  method setBounds(self: View, bounds: Rect) =
    if self.xBounds == bounds:
      return
    self.xBounds = initRect(bounds.origin, bounds.size)
    emit self.layoutInputChanged(lirBounds)
    emit self.geometryDidChange()
    self.setNeedsDisplay(true)

  method needsDisplay(self: View): bool =
    self.xNeedsDisplay

  method setNeedsDisplay(self: View, value: bool) =
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
      return initRect(0.0, 0.0, 0.0, 0.0)
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

  method setBackgroundColor(self: View, color: Color) =
    if self.xBackgroundColor == color:
      return
    self.xBackgroundColor = color
    self.setNeedsDisplay(true)

  method clipsToBounds(self: View): bool =
    self.xClipsToBounds

  method setClipsToBounds(self: View, clipsToBounds: bool) =
    if self.xClipsToBounds == clipsToBounds:
      return
    self.xClipsToBounds = clipsToBounds
    self.setNeedsDisplaySubtree()

  method nextKeyView(self: View): View =
    self.xNextKeyView

  method setNextKeyView(self: View, next: View) =
    if self.isNil or self.xNextKeyView == next:
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

  method setPreviousKeyView(self: View, previous: View) =
    if self.isNil or self.xPreviousKeyView == previous:
      return
    if previous.isNil:
      let oldPrevious = self.xPreviousKeyView
      if not oldPrevious.isNil and oldPrevious.xNextKeyView == self:
        oldPrevious.xNextKeyView = nil
      self.xPreviousKeyView = nil
      return
    previous.setNextKeyView(self)

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

  method setHidden*(self: View, hidden: bool) =
    if (ssHidden in self.xWidgetStates) == hidden:
      return
    if hidden:
      self.xWidgetStates.incl(ssHidden)
    else:
      self.xWidgetStates.excl(ssHidden)
    self.invalidateLayoutItemGeometry(lirHidden)
    self.setNeedsDisplay(true)

  method isHiddenOrHasHiddenAncestor*(self: View): bool =
    var current = self
    while not current.isNil:
      if ssHidden in current.xWidgetStates:
        return true
      current = current.xSuperview
    false

  method visibleRect*(self: View): Rect =
    if self.isNil or self.isHiddenOrHasHiddenAncestor():
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
    self.setNextKeyView(nil)
    self.setPreviousKeyView(nil)
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

proc `frame=`*(view: View, frame: Rect) =
  view.setFrame(frame)

proc `bounds=`*(view: View, bounds: Rect) =
  view.setBounds(bounds)

proc `needsDisplay=`*(view: View, value: bool) =
  view.setNeedsDisplay(value)

proc background*(view: View): Color =
  view.backgroundColor()

proc `background=`*(view: View, color: Color) =
  view.setBackgroundColor(color)

proc `backgroundColor=`*(view: View, color: Color) =
  view.setBackgroundColor(color)

proc `clipsToBounds=`*(view: View, clipsToBounds: bool) =
  view.setClipsToBounds(clipsToBounds)

proc `nextKeyView=`*(view: View, next: View) =
  view.setNextKeyView(next)

proc `previousKeyView=`*(view: View, previous: View) =
  view.setPreviousKeyView(previous)

proc hidden*(view: View): bool =
  view.isHidden()

proc `hidden=`*(view: View, hidden: bool) =
  view.setHidden(hidden)

proc setNeedsDisplaySubtree*(view: View) =
  view.setNeedsDisplay(true)
  for child in view.xSubviews:
    child.setNeedsDisplaySubtree()

proc viewCanBecomeKeyView*(view: View): bool =
  (not view.isNil) and view.acceptsFirstResponder() and
    not view.isHiddenOrHasHiddenAncestor()

proc hasAppearance*(view: View): bool =
  (not view.isNil) and view.xHasAppearance

proc appearance*(view: View): Appearance =
  if view.isNil or not view.xHasAppearance:
    return initAppearance()
  view.xAppearance

proc effectiveAppearance*(view: View): Appearance =
  if view.isNil:
    return initAppearance()
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
  view.invalidateIntrinsicContentSizeSubtree()
  view.setNeedsDisplaySubtree()

proc clearAppearance*(view: View) =
  if view.isNil or not view.xHasAppearance:
    return
  view.xAppearance = Appearance()
  view.xHasAppearance = false
  view.invalidateIntrinsicContentSizeSubtree()
  view.setNeedsDisplaySubtree()

proc assignInheritedAppearance(view: View, appearance: Appearance) =
  view.xInheritedAppearance = appearance
  view.xHasInheritedAppearance = true
  view.invalidateIntrinsicContentSize()
  for child in view.xSubviews:
    child.assignInheritedAppearance(appearance)

proc setInheritedAppearance*(view: View, appearance: Appearance) =
  view.assignInheritedAppearance(appearance)
  view.setNeedsDisplaySubtree()

proc clearInheritedAppearance*(view: View) =
  view.xInheritedAppearance = Appearance()
  view.xHasInheritedAppearance = false
  view.invalidateIntrinsicContentSize()
  for child in view.xSubviews:
    child.clearInheritedAppearance()
  view.setNeedsDisplay(true)

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
  if view.isNil or compare.isNil:
    return
  view.xSubviews.sort(compare)
  emit view.layoutInputChanged(lirHierarchy)
  view.setNeedsDisplay(true)

proc addSubviewWithDefaultIdentifier(view, child: View, defaultIdentifier: string) =
  if not child.isNil and child.xIdentifier.len == 0 and defaultIdentifier.len > 0:
    child.xIdentifier = defaultIdentifier
  view.addSubview(child)

type NamedSubview* = tuple[view: View, name: string]

func inferredSubviewIdentifier(node: NimNode): string =
  case node.kind
  of nnkIdent:
    $node
  of nnkAccQuoted:
    node.repr
  else:
    ""

macro addSubviews*(view: untyped, rest: varargs[untyped]): untyped =
  ## Adds several subviews and gives simple named arguments a matching identifier
  ## when the child does not already have one.
  let
    parent = genSym(nskLet, "parent")
    addChild = bindSym"addSubviewWithDefaultIdentifier"
  result = newStmtList()
  let body = newStmtList(newLetStmt(parent, view))
  for child in rest:
    body.add newCall(addChild, parent, child, newLit(child.inferredSubviewIdentifier()))
  result.add newBlockStmt(body)

proc addSubviewsWithNames*(view: View, subviews: openArray[NamedSubview]) =
  ## Adds several subviews and assigns the provided identifiers.
  for subview in subviews:
    if not subview.view.isNil:
      subview.view.xIdentifier = subview.name
    view.addSubview(subview.view)

