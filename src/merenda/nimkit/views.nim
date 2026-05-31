import ./responders
import ./selectors
import ./theme
import ./types

export responders

type
  LayoutConstraint* = ref object
    xFirstItem: View
    xFirstAttribute: LayoutAttribute
    xRelation: LayoutRelation
    xSecondItem: View
    xSecondAttribute: LayoutAttribute
    xMultiplier: float32
    xConstant: float32
    xPriority: LayoutPriority
    xActive: bool
    xOwningView: View

  View* = ref object of Responder
    xFrame: Rect
    xBounds: Rect
    xHidden: bool
    xNeedsDisplay: bool
    xInvalidRects: seq[Rect]
    xBackgroundColor: Color
    xClipsToBounds: bool
    xAppearance: Appearance
    xHasAppearance: bool
    xInheritedAppearance: Appearance
    xHasInheritedAppearance: bool
    xStyleId: string
    xStyleClasses: seq[string]
    xHovered: bool
    xActive: bool
    xHasFocus: bool
    xFocusVisible: bool
    xNeedsUpdateConstraints: bool
    xNeedsLayout: bool
    xAutoresizingMask: AutoresizingMask
    xTranslatesAutoresizingMaskIntoConstraints: bool
    xAlignmentRectInsets: EdgeInsets
    xBaselineOffsetFromBottom: float32
    xFirstBaselineOffsetFromTop: float32
    xHorizontalContentHuggingPriority: LayoutPriority
    xVerticalContentHuggingPriority: LayoutPriority
    xHorizontalContentCompressionResistancePriority: LayoutPriority
    xVerticalContentCompressionResistancePriority: LayoutPriority
    xConstraints: seq[LayoutConstraint]
    xNextKeyView: View
    xPreviousKeyView: View
    xSuperview: View
    xWindow: Responder
    xSubviews: seq[View]

proc pointFromView*(view: View, point: Point, fromView: View): Point
proc pointToView*(view: View, point: Point, toView: View): Point
proc rectFromView*(view: View, rect: Rect, fromView: View): Rect
proc rectToView*(view: View, rect: Rect, toView: View): Rect
proc pointFromWindow*(view: View, point: Point): Point
proc pointToWindow*(view: View, point: Point): Point
proc rectFromWindow*(view: View, rect: Rect): Rect
proc rectToWindow*(view: View, rect: Rect): Rect
proc notifyWillMoveToSuperview(view, superview: View)
proc notifyDidMoveToSuperview(view: View)
proc notifyWillMoveToWindow(view: View, window: Responder)
proc notifyDidMoveToWindow(view: View)
proc notifyDidAddSubview(view, subview: View)
proc notifyWillRemoveSubview(view, subview: View)
proc setWindowOwner(view: View, window: Responder)
proc markConstraintStorageChanged(view: View)
proc markSubviewAutoresizingConstraintsChanged(view: View)
proc setNeedsUpdateConstraints*(view: View, value: bool)
proc setNeedsLayout*(view: View, value: bool)
proc invalidateLayoutItemGeometry*(view: View)
proc invalidateIntrinsicContentSize*(view: View)
proc setNeedsDisplaySubtree(view: View)
proc viewCanBecomeKeyView*(view: View): bool
proc effectiveAppearance*(view: View): Appearance
proc setInheritedAppearance*(view: View, appearance: Appearance)
proc clearInheritedAppearance*(view: View)

protocol ViewProtocolInternal from View:
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
    if self.xFrame == frame:
      return
    self.xFrame = frame
    self.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
    self.invalidateLayoutItemGeometry()
    self.markSubviewAutoresizingConstraintsChanged()
    self.setNeedsDisplay(true)

  method bounds(self: View): Rect =
    self.xBounds

  method setBounds(self: View, bounds: Rect) =
    if self.xBounds == bounds:
      return
    self.xBounds = initRect(bounds.origin, bounds.size)
    self.markConstraintStorageChanged()
    self.markSubviewAutoresizingConstraintsChanged()
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
    self.xHidden

  method setHidden*(self: View, hidden: bool) =
    if self.xHidden == hidden:
      return
    self.xHidden = hidden
    self.invalidateLayoutItemGeometry()
    self.setNeedsDisplay(true)

  method isHiddenOrHasHiddenAncestor*(self: View): bool =
    var current = self
    while not current.isNil:
      if current.xHidden:
        return true
      current = current.xSuperview
    false

  method visibleRect*(self: View): Rect =
    if self.isHiddenOrHasHiddenAncestor():
      return initRect(0.0, 0.0, 0.0, 0.0)
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
    parent.notifyWillRemoveSubview(self)
    self.notifyWillMoveToSuperview(nil)
    if oldWindow != nil:
      self.notifyWillMoveToWindow(nil)
    let idx = parent.xSubviews.find(self)
    if idx >= 0:
      parent.xSubviews.delete(idx)
      self.invalidateLayoutItemGeometry()
      parent.setNeedsDisplayInRect(self.rectToView(self.bounds, parent))
    self.xSuperview = nil
    self.clearNextResponder()
    self.setNextKeyView(nil)
    self.setPreviousKeyView(nil)
    self.setWindowOwner(nil)
    self.clearInheritedAppearance()
    self.notifyDidMoveToSuperview()
    if oldWindow != nil:
      self.notifyDidMoveToWindow()
    self.markConstraintStorageChanged()

  method addSubview*(self: View, child: View) =
    if child.isNil:
      return
    if not child.xSuperview.isNil:
      child.removeFromSuperview()
    let oldWindow = child.xWindow
    child.notifyWillMoveToSuperview(self)
    if oldWindow != self.xWindow:
      child.notifyWillMoveToWindow(self.xWindow)
    child.xSuperview = self
    self.xSubviews.add child
    child.setNextResponder(self)
    child.setWindowOwner(self.xWindow)
    child.setInheritedAppearance(self.effectiveAppearance())
    self.notifyDidAddSubview(child)
    child.notifyDidMoveToSuperview()
    if oldWindow != self.xWindow:
      child.notifyDidMoveToWindow()
    child.invalidateLayoutItemGeometry()
    self.setNeedsDisplayInRect(child.rectToView(child.bounds, self))

  method pointInside*(self: View, point: Point): bool =
    self.xBounds.contains(point)

  method hitTestLevel*(self: View, point: Point): int =
    DefaultDrawLevel.int

  method hitTest*(self: View, point: Point): View =
    if self.xHidden:
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

protocol ViewLifecycleProtocolInternal:
  method viewWillMoveToSuperview*(superview: View) {.optional.}
  method viewDidMoveToSuperview*() {.optional.}
  method viewWillMoveToWindow*(window: Responder) {.optional.}
  method viewDidMoveToWindow*() {.optional.}
  method didAddSubview*(subview: View) {.optional.}
  method willRemoveSubview*(subview: View) {.optional.}

proc newLayoutConstraint*(
    firstItem: View,
    firstAttribute: LayoutAttribute,
    relation = lrEqual,
    secondItem: View = nil,
    secondAttribute = latNotAnAttribute,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  result = LayoutConstraint(
    xFirstItem: firstItem,
    xFirstAttribute: firstAttribute,
    xRelation: relation,
    xSecondItem: secondItem,
    xSecondAttribute: if secondItem.isNil: latNotAnAttribute else: secondAttribute,
    xMultiplier: multiplier,
    xConstant: constant,
    xPriority: priority,
  )

proc firstItem*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xFirstItem

proc firstAttribute*(constraint: LayoutConstraint): LayoutAttribute =
  if constraint.isNil: latNotAnAttribute else: constraint.xFirstAttribute

proc relation*(constraint: LayoutConstraint): LayoutRelation =
  if constraint.isNil: lrEqual else: constraint.xRelation

proc secondItem*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xSecondItem

proc secondAttribute*(constraint: LayoutConstraint): LayoutAttribute =
  if constraint.isNil: latNotAnAttribute else: constraint.xSecondAttribute

proc multiplier*(constraint: LayoutConstraint): float32 =
  if constraint.isNil: 1.0'f32 else: constraint.xMultiplier

proc constant*(constraint: LayoutConstraint): float32 =
  if constraint.isNil: 0.0'f32 else: constraint.xConstant

proc priority*(constraint: LayoutConstraint): LayoutPriority =
  if constraint.isNil: LayoutPriorityRequired else: constraint.xPriority

proc isActive*(constraint: LayoutConstraint): bool =
  (not constraint.isNil) and constraint.xActive

proc owningView*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xOwningView

proc markConstraintStorageChanged(view: View) =
  if view.isNil:
    return
  view.setNeedsUpdateConstraints(true)
  view.setNeedsLayout(true)

proc markSubviewAutoresizingConstraintsChanged(view: View) =
  if view.isNil:
    return
  for child in view.xSubviews:
    if child.xTranslatesAutoresizingMaskIntoConstraints:
      child.markConstraintStorageChanged()

proc referencesLayoutItem(constraint: LayoutConstraint, view: View): bool =
  (not constraint.isNil) and
    (constraint.xFirstItem == view or constraint.xSecondItem == view)

proc hasConstraintReferencing(view, item: View): bool =
  if view.isNil or item.isNil:
    return false
  for constraint in view.xConstraints:
    if constraint.referencesLayoutItem(item):
      return true

proc invalidateLayoutItemGeometry*(view: View) =
  if view.isNil:
    return
  let parent = view.xSuperview
  var current = view
  while not current.isNil:
    if current == view or current == parent or current.hasConstraintReferencing(view):
      current.markConstraintStorageChanged()
    current = current.xSuperview

proc autoresizingMask*(view: View): AutoresizingMask =
  if view.isNil:
    return {}
  view.xAutoresizingMask

proc setAutoresizingMask*(view: View, mask: AutoresizingMask) =
  if view.isNil or view.xAutoresizingMask == mask:
    return
  view.xAutoresizingMask = mask
  view.invalidateLayoutItemGeometry()

proc translatesAutoresizingMaskIntoConstraints*(view: View): bool =
  (not view.isNil) and view.xTranslatesAutoresizingMaskIntoConstraints

proc setTranslatesAutoresizingMaskIntoConstraints*(view: View, value: bool) =
  if view.isNil or view.xTranslatesAutoresizingMaskIntoConstraints == value:
    return
  view.xTranslatesAutoresizingMaskIntoConstraints = value
  view.invalidateLayoutItemGeometry()

proc alignmentRectInsets*(view: View): EdgeInsets =
  if view.isNil:
    return initEdgeInsets(0.0)
  view.xAlignmentRectInsets

proc setAlignmentRectInsets*(view: View, insets: EdgeInsets) =
  if view.isNil or view.xAlignmentRectInsets == insets:
    return
  view.xAlignmentRectInsets = insets
  view.invalidateLayoutItemGeometry()

proc alignmentRectForFrame*(view: View, frame: Rect): Rect =
  if view.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  frame.inset(view.alignmentRectInsets())

proc frameForAlignmentRect*(view: View, alignmentRect: Rect): Rect =
  if view.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let insets = view.alignmentRectInsets()
  initRect(
    alignmentRect.origin.x - insets.left,
    alignmentRect.origin.y - insets.top,
    alignmentRect.size.width + insets.horizontal,
    alignmentRect.size.height + insets.vertical,
  )

proc alignmentRect*(view: View): Rect =
  if view.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  view.alignmentRectForFrame(view.xFrame)

proc setFrameFromAlignmentRect*(view: View, alignmentRect: Rect) =
  if view.isNil:
    return
  view.setFrame(view.frameForAlignmentRect(alignmentRect))

proc baselineOffsetFromBottom*(view: View): float32 =
  if view.isNil: 0.0'f32 else: view.xBaselineOffsetFromBottom

proc setBaselineOffsetFromBottom*(view: View, offset: float32) =
  let normalized = max(offset, 0.0'f32)
  if view.isNil or view.xBaselineOffsetFromBottom == normalized:
    return
  view.xBaselineOffsetFromBottom = normalized
  view.invalidateLayoutItemGeometry()

proc firstBaselineOffsetFromTop*(view: View): float32 =
  if view.isNil: 0.0'f32 else: view.xFirstBaselineOffsetFromTop

proc setFirstBaselineOffsetFromTop*(view: View, offset: float32) =
  let normalized = max(offset, 0.0'f32)
  if view.isNil or view.xFirstBaselineOffsetFromTop == normalized:
    return
  view.xFirstBaselineOffsetFromTop = normalized
  view.invalidateLayoutItemGeometry()

proc layoutValue*(view: View, attribute: LayoutAttribute): float32 =
  if view.isNil:
    return 0.0'f32
  let rect = view.alignmentRect()
  case attribute
  of latLeft, latLeading:
    rect.minX
  of latRight, latTrailing:
    rect.maxX
  of latTop:
    rect.minY
  of latBottom:
    rect.maxY
  of latWidth:
    rect.size.width
  of latHeight:
    rect.size.height
  of latCenterX:
    rect.minX + rect.size.width / 2.0'f32
  of latCenterY:
    rect.minY + rect.size.height / 2.0'f32
  of latLastBaseline:
    rect.maxY - view.baselineOffsetFromBottom()
  of latFirstBaseline:
    rect.minY + view.firstBaselineOffsetFromTop()
  of latNotAnAttribute:
    0.0'f32

proc invalidateActiveConstraint(constraint: LayoutConstraint) =
  if constraint.isNil or not constraint.xActive:
    return
  constraint.xOwningView.markConstraintStorageChanged()

proc setConstant*(constraint: LayoutConstraint, constant: float32) =
  if constraint.isNil or constraint.xConstant == constant:
    return
  constraint.xConstant = constant
  constraint.invalidateActiveConstraint()

proc setPriority*(constraint: LayoutConstraint, priority: LayoutPriority) =
  if constraint.isNil or constraint.xPriority == priority:
    return
  constraint.xPriority = priority
  constraint.invalidateActiveConstraint()

proc indexOfConstraint(view: View, constraint: LayoutConstraint): int =
  if view.isNil or constraint.isNil:
    return -1
  for index, stored in view.xConstraints:
    if stored == constraint:
      return index
  -1

proc removeStoredConstraint(view: View, constraint: LayoutConstraint) =
  if view.isNil or constraint.isNil:
    return
  let index = view.indexOfConstraint(constraint)
  if index < 0:
    return
  view.xConstraints.delete(index)
  if constraint.xOwningView == view:
    constraint.xOwningView = nil
    constraint.xActive = false
  view.markConstraintStorageChanged()

proc constraints*(view: View): seq[LayoutConstraint] =
  if view.isNil:
    @[]
  else:
    view.xConstraints

proc addConstraint*(view: View, constraint: LayoutConstraint) =
  if view.isNil or constraint.isNil:
    return
  if constraint.xOwningView == view and view.indexOfConstraint(constraint) >= 0:
    if not constraint.xActive:
      constraint.xActive = true
      view.markConstraintStorageChanged()
    return

  let oldOwner = constraint.xOwningView
  if not oldOwner.isNil:
    oldOwner.removeStoredConstraint(constraint)

  view.xConstraints.add constraint
  constraint.xOwningView = view
  constraint.xActive = true
  view.markConstraintStorageChanged()

proc addConstraints*(view: View, constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    view.addConstraint(constraint)

proc removeConstraint*(view: View, constraint: LayoutConstraint) =
  view.removeStoredConstraint(constraint)

proc removeConstraints*(view: View, constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    view.removeConstraint(constraint)

proc nearestCommonSuperview(first, second: View): View =
  var candidate = first
  while not candidate.isNil:
    var other = second
    while not other.isNil:
      if candidate == other:
        return candidate
      other = other.xSuperview
    candidate = candidate.xSuperview

proc activationOwner(constraint: LayoutConstraint): View =
  if constraint.isNil or constraint.xFirstItem.isNil:
    return nil
  if constraint.xSecondItem.isNil:
    return constraint.xFirstItem
  let common = constraint.xFirstItem.nearestCommonSuperview(constraint.xSecondItem)
  if common.isNil: constraint.xFirstItem else: common

proc setActive*(constraint: LayoutConstraint, active: bool) =
  if constraint.isNil or constraint.xActive == active:
    return
  if active:
    let owner = constraint.activationOwner()
    if owner.isNil:
      return
    owner.addConstraint(constraint)
  elif not constraint.xOwningView.isNil:
    constraint.xOwningView.removeConstraint(constraint)
  else:
    constraint.xActive = false

proc activateConstraints*(constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    constraint.setActive(true)

proc deactivateConstraints*(constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    constraint.setActive(false)

proc setNeedsDisplaySubtree(view: View) =
  if view.isNil:
    return
  view.setNeedsDisplay(true)
  for child in view.xSubviews:
    child.setNeedsDisplaySubtree()

proc invalidateIntrinsicContentSizeSubtree(view: View) =
  if view.isNil:
    return
  view.invalidateIntrinsicContentSize()
  for child in view.xSubviews:
    child.invalidateIntrinsicContentSizeSubtree()

proc intrinsicContentSize*(view: View): IntrinsicSize =
  NoIntrinsicContentSize

proc sizeThatFits*(view: View, proposedSize: FittingSize): Size =
  if view.isNil:
    return initSize(0.0, 0.0)
  let
    intrinsicSize = view.intrinsicContentSize()
    fallbackSize = initSize(
      if proposedSize.hasWidth: proposedSize.width else: view.xBounds.size.width,
      if proposedSize.hasHeight: proposedSize.height else: view.xBounds.size.height,
    )
  intrinsicSize.resolveIntrinsicSize(fallbackSize).constrainSize(proposedSize)

proc sizeThatFits*(view: View): Size =
  if view.isNil:
    return initSize(0.0, 0.0)
  view.sizeThatFits(UnconstrainedFittingSize)

proc sizeThatFits*(view: View, proposedSize: Size): Size =
  if view.isNil:
    return initSize(0.0, 0.0)
  view.sizeThatFits(initFittingSize(proposedSize))

proc sizeToFit*(view: View) =
  if view.isNil:
    return
  let frame = view.frame()
  view.setFrame(initRect(frame.origin, view.sizeThatFits(UnconstrainedFittingSize)))

proc invalidateIntrinsicContentSize*(view: View) =
  if view.isNil:
    return
  view.invalidateLayoutItemGeometry()

proc contentHuggingPriority*(view: View, axis: LayoutAxis): LayoutPriority =
  if view.isNil:
    return LayoutPriorityDefaultLow
  case axis
  of laHorizontal: view.xHorizontalContentHuggingPriority
  of laVertical: view.xVerticalContentHuggingPriority

proc setContentHuggingPriority*(
    view: View, priority: LayoutPriority, axis: LayoutAxis
) =
  if view.isNil:
    return
  case axis
  of laHorizontal:
    if view.xHorizontalContentHuggingPriority == priority:
      return
    view.xHorizontalContentHuggingPriority = priority
  of laVertical:
    if view.xVerticalContentHuggingPriority == priority:
      return
    view.xVerticalContentHuggingPriority = priority
  view.invalidateIntrinsicContentSize()

proc contentCompressionResistancePriority*(
    view: View, axis: LayoutAxis
): LayoutPriority =
  if view.isNil:
    return LayoutPriorityDefaultHigh
  case axis
  of laHorizontal: view.xHorizontalContentCompressionResistancePriority
  of laVertical: view.xVerticalContentCompressionResistancePriority

proc setContentCompressionResistancePriority*(
    view: View, priority: LayoutPriority, axis: LayoutAxis
) =
  if view.isNil:
    return
  case axis
  of laHorizontal:
    if view.xHorizontalContentCompressionResistancePriority == priority:
      return
    view.xHorizontalContentCompressionResistancePriority = priority
  of laVertical:
    if view.xVerticalContentCompressionResistancePriority == priority:
      return
    view.xVerticalContentCompressionResistancePriority = priority
  view.invalidateIntrinsicContentSize()

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
  if view.isNil:
    return inherited
  if view.xHasAppearance:
    return view.xAppearance
  if view.xHasInheritedAppearance and view.xSuperview.isNil:
    return view.xInheritedAppearance
  inherited

proc setAppearance*(view: View, appearance: Appearance) =
  if view.isNil:
    return
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
  if view.isNil:
    return
  view.assignInheritedAppearance(appearance)
  view.setNeedsDisplaySubtree()

proc clearInheritedAppearance*(view: View) =
  if view.isNil:
    return
  view.xInheritedAppearance = Appearance()
  view.xHasInheritedAppearance = false
  view.invalidateIntrinsicContentSize()
  for child in view.xSubviews:
    child.clearInheritedAppearance()
  view.setNeedsDisplay(true)

proc styleId*(view: View): string =
  if view.isNil: "" else: view.xStyleId

proc setStyleId*(view: View, id: string) =
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

proc setStyleClasses*(view: View, classes: openArray[string]) =
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

proc setHovered*(view: View, hovered: bool) =
  if view.isNil or view.xHovered == hovered:
    return
  view.xHovered = hovered
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc isActive*(view: View): bool =
  (not view.isNil) and view.xActive

proc setActive*(view: View, active: bool) =
  if view.isNil or view.xActive == active:
    return
  view.xActive = active
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc isFocused*(view: View): bool =
  (not view.isNil) and view.xHasFocus

proc setFocused*(view: View, focused: bool) =
  if view.isNil or view.xHasFocus == focused:
    return
  view.xHasFocus = focused
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc isFocusVisible*(view: View): bool =
  (not view.isNil) and view.xFocusVisible

proc setFocusVisible*(view: View, focusVisible: bool) =
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

proc setNeedsLayout*(view: View, value: bool) =
  if view.isNil:
    return
  view.xNeedsLayout = value

proc setNeedsLayout*(view: View) =
  view.setNeedsLayout(true)

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

proc notifyWillMoveToSuperview(view, superview: View) =
  discard view.sendIfHandled(viewWillMoveToSuperview(), superview)

proc notifyDidMoveToSuperview(view: View) =
  discard view.sendIfHandled(viewDidMoveToSuperview())

proc notifyWillMoveToWindow(view: View, window: Responder) =
  discard view.sendIfHandled(viewWillMoveToWindow(), window)
  for child in view.xSubviews:
    child.notifyWillMoveToWindow(window)

proc notifyDidMoveToWindow(view: View) =
  discard view.sendIfHandled(viewDidMoveToWindow())
  for child in view.xSubviews:
    child.notifyDidMoveToWindow()

proc notifyDidAddSubview(view, subview: View) =
  discard view.sendIfHandled(didAddSubview(), subview)

proc notifyWillRemoveSubview(view, subview: View) =
  discard view.sendIfHandled(willRemoveSubview(), subview)

proc setWindowOwner(view: View, window: Responder) =
  view.xWindow = window
  for child in view.xSubviews:
    child.setWindowOwner(window)

proc moveToWindowOwner*(view: View, window: Responder) =
  if view.isNil or view.xWindow == window:
    return
  view.notifyWillMoveToWindow(window)
  view.setWindowOwner(window)
  view.notifyDidMoveToWindow()

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

proc initViewFields*(view: View, frame: Rect) =
  initResponder(view)
  view.xFrame = frame
  view.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  view.xNeedsDisplay = true
  view.xNeedsLayout = true
  view.xTranslatesAutoresizingMaskIntoConstraints = true
  view.xHorizontalContentHuggingPriority = LayoutPriorityDefaultLow
  view.xVerticalContentHuggingPriority = LayoutPriorityDefaultLow
  view.xHorizontalContentCompressionResistancePriority = LayoutPriorityDefaultHigh
  view.xVerticalContentCompressionResistancePriority = LayoutPriorityDefaultHigh
  view.xBackgroundColor = initColor(0.94, 0.95, 0.97, 1.0)
  discard view.withProto()

proc newView*(frame: Rect): View =
  result = View()
  initViewFields(result, frame)

proc newView*(x, y, width, height: float32): View =
  newView(initRect(x, y, width, height))

proc pointToSuperview(view: View, point: Point): Point =
  let
    frame = view.frame
    bounds = view.bounds
  initPoint(
    frame.origin.x + point.x - bounds.origin.x,
    frame.origin.y + point.y - bounds.origin.y,
  )

proc pointFromSuperview(view: View, point: Point): Point =
  let
    frame = view.frame
    bounds = view.bounds
  initPoint(
    bounds.origin.x + point.x - frame.origin.x,
    bounds.origin.y + point.y - frame.origin.y,
  )

proc pointToWindow*(view: View, point: Point): Point =
  if view.isNil:
    return point
  var resultPoint = point
  var current = view
  while not current.isNil:
    resultPoint = current.pointToSuperview(resultPoint)
    current = current.superview
  resultPoint

proc pointFromWindow*(view: View, point: Point): Point =
  if view.isNil:
    return point
  var chain: seq[View] = @[]
  var current = view
  while not current.isNil:
    chain.add(current)
    current = current.superview
  var resultPoint = point
  for idx in countdown(chain.high, 0):
    resultPoint = chain[idx].pointFromSuperview(resultPoint)
  resultPoint

proc pointToView*(view: View, point: Point, toView: View): Point =
  if view.isNil:
    if toView.isNil:
      return point
    return toView.pointFromWindow(point)
  if view == toView:
    return point
  let windowPoint = view.pointToWindow(point)
  if toView.isNil:
    windowPoint
  else:
    toView.pointFromWindow(windowPoint)

proc pointFromView*(view: View, point: Point, fromView: View): Point =
  if view.isNil:
    if fromView.isNil:
      return point
    return fromView.pointToWindow(point)
  if view == fromView:
    return point
  if fromView.isNil:
    return view.pointFromWindow(point)
  view.pointFromWindow(fromView.pointToWindow(point))

proc rectFromCorners(p0, p1: Point): Rect =
  initRect(min(p0.x, p1.x), min(p0.y, p1.y), abs(p1.x - p0.x), abs(p1.y - p0.y))

proc rectToWindow*(view: View, rect: Rect): Rect =
  let
    p0 = view.pointToWindow(rect.origin)
    p1 = view.pointToWindow(initPoint(rect.maxX, rect.maxY))
  rectFromCorners(p0, p1)

proc rectFromWindow*(view: View, rect: Rect): Rect =
  let
    p0 = view.pointFromWindow(rect.origin)
    p1 = view.pointFromWindow(initPoint(rect.maxX, rect.maxY))
  rectFromCorners(p0, p1)

proc rectToView*(view: View, rect: Rect, toView: View): Rect =
  let
    p0 = view.pointToView(rect.origin, toView)
    p1 = view.pointToView(initPoint(rect.maxX, rect.maxY), toView)
  rectFromCorners(p0, p1)

proc rectFromView*(view: View, rect: Rect, fromView: View): Rect =
  let
    p0 = view.pointFromView(rect.origin, fromView)
    p1 = view.pointFromView(initPoint(rect.maxX, rect.maxY), fromView)
  rectFromCorners(p0, p1)

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

let
  ViewProtocol* = ViewProtocolInternal
  ViewLifecycleProtocol* = ViewLifecycleProtocolInternal
