import std/tables

import ../responder/responders
import ../themes
import ../foundation/backrefs
import ../foundation/types
import ../drawing/renderresources

when not defined(useNativeDynlib):
  import ../drawing/renderscenes

when defined(useNativeDynlib):
  from figdraw/dynlib import Renders
else:
  import figdraw

export responders

type
  LayoutInvalidationReason* = enum
    lirFrame
    lirBounds
    lirSuperview
    lirSuperviewGeometry
    lirSubviews
    lirHierarchy
    lirDescendantGeometry
    lirDescendantIntrinsic
    lirHidden
    lirAutoresizingMask
    lirConstraints
    lirIntrinsic
    lirAppearanceMetrics
    lirContainerMetrics
    lirExplicit

  LayoutTransactionPhase* = enum
    ltpIdle
    ltpUpdatingConstraints
    ltpSolvingConstraints
    ltpLayingOut

  LayoutInputSource* = enum
    lisUser
    lisAutoresizingMask
    lisIntrinsic
    lisContainer

  LayoutInputSources* = set[LayoutInputSource]

  LayoutInputKind* = enum
    likConstraint
    likEquation

  LayoutFrameOrigin* = enum
    lfoAuthored
    lfoContainer
    lfoSolver

  FocusRingType* = enum
    frtDefault
    frtNone
    frtExterior

  SubviewPosition* = enum
    svpAbove
    svpBelow

  ViewTrackingOption* = enum
    vtoMouseEnteredAndExited
    vtoMouseMoved
    vtoCursorUpdate
    vtoActiveAlways
    vtoInVisibleRect

  ViewTrackingOptions* = set[ViewTrackingOption]

  ViewCursorRect* = object
    rect*: Rect
    cursor*: string

  ViewTrackingArea* = object
    rect*: Rect
    options*: ViewTrackingOptions
    tag*: int
    owner*: Responder

  AutoresizingState* = object
    referenceRect*: Rect
    referenceSuperviewRect*: Rect
    hasReference*: bool
    referenceDirty*: bool
    inputsDirty*: bool

  LayoutConstraint* = ref object
    xFirstItem*: View
    xFirstAttribute*: LayoutAttribute
    xRelation*: LayoutRelation
    xSecondItem*: View
    xSecondAttribute*: LayoutAttribute
    xMultiplier*: float32
    xConstant*: float32
    xPriority*: LayoutPriority
    xActive*: bool
    xOwningView*: View

  LayoutTerm* = object
    item*: View
    attribute*: LayoutAttribute
    multiplier*: float32

  LayoutEquation* = object
    terms*: seq[LayoutTerm]
    relation*: LayoutRelation
    constant*: float32
    priority*: LayoutPriority
    source*: LayoutInputSource

  LayoutInput* = object
    case kind*: LayoutInputKind
    of likConstraint:
      constraint*: LayoutConstraint
    of likEquation:
      equation*: LayoutEquation

  LayoutInputCache* = object
    generated*: array[LayoutInputSource, seq[LayoutInput]]
    dirtySources*: LayoutInputSources
    aggregateDirtySources*: LayoutInputSources
    structureDirty*: bool
    aggregateStructureDirty*: bool
    sourceGenerations*: array[LayoutInputSource, Natural]
    generation*: Natural

  LayoutInputSummary* = object
    source*: LayoutInputSource
    constraints*: Natural
    equations*: Natural
    terms*: Natural

  LayoutInvalidationDiagnostic* = object
    generation*: Natural
    invalidatingView*: string
    targetView*: string
    phase*: LayoutTransactionPhase
    reason*: LayoutInvalidationReason

  LayoutTransactionState* = object
    root*: View
    currentView*: View
    generation*: Natural
    phase*: LayoutTransactionPhase
    followUpRequested*: bool
    lastInvalidation*: LayoutInvalidationDiagnostic

  View* = ref object of Responder
    xTag*: int
    xIdentifier*: string
    xFrame*: Rect
    xBounds*: Rect
    xFlipped*: bool
    xNeedsDisplay*: bool
    xNeedsLocalDisplay*: bool
    xDisplayRevision*: uint64
    xRenderSlotRevisions*: Table[RenderSlotId, uint64]
    xInvalidRects*: seq[Rect]
    xBackgroundColor*: Color
    xUsesThemedRootBackground*: bool
    xClipsToBounds*: bool
    xFocusRingType*: FocusRingType
    xAlphaValue*: float32
    xShadow*: seq[BoxShadow]
    xAppearance*: Appearance
    xHasAppearance*: bool
    xInheritedAppearance*: Appearance
    xHasInheritedAppearance*: bool
    xStyleId*: string
    xStyleClasses*: seq[string]
    xWidgetStates*: set[WidgetState]
    xHasAccessibilityRole*: bool
    xAccessibilityRole*: AccessibilityRole
    xAccessibilityElement*: bool
    xAccessibilityIgnored*: bool
    xAccessibilityLabel*: string
    xAccessibilityValue*: string
    xAccessibilityHelp*: string
    xAccessibilityIdentifier*: string
    xAccessibilityTraits*: AccessibilityTraits
    xValidationMessage*: string
    xNeedsUpdateConstraints*: bool
    xNeedsLayout*: bool
    xLayoutSubtreeInProgress*: bool
    xLayoutGeneration*: Natural
    xConstraintVisitGeneration*: Natural
    xLayoutVisitGeneration*: Natural
    xLayoutPhase*: LayoutTransactionPhase
    xLayoutFeedbackCycles*: Natural
    xLastLayoutInvalidation*: LayoutInvalidationDiagnostic
    xAutoresizingMask*: AutoresizingMask
    xAutoresizingMaskConstraints*: bool
    xAutoresizingState*: AutoresizingState
    xAlignmentInsets*: EdgeInsets
    xLastBaselineOffset*: float32
    xFirstBaselineOffset*: float32
    xHuggingPriority*: array[LayoutAxis, LayoutPriority]
    xCompressionPriority*: array[LayoutAxis, LayoutPriority]
    xConstraints*: seq[LayoutConstraint]
    xLayoutInputCache*: LayoutInputCache
    xNextKeyView*: View
    xPreviousKeyView*: View
    xSuperview*: BackRef[View]
    xWindow*: BackRef[Responder]
    xSubviews*: seq[View]
    xToolTip*: string
    xCursorRects*: seq[ViewCursorRect]
    xTrackingAreas*: seq[ViewTrackingArea]
    xRegisteredDraggedTypes*: seq[string]
    xContextMenu*: Responder
    xContextMenuHandlerInstalled*: bool
    when not defined(useNativeDynlib):
      xRenderViewId*: RenderViewId
      xCachedRenderScene*: RenderScene
    xCachedRenders*: Renders
    xCachedRenderResources*: RenderResourceManifest
    xCachedAppearanceGeneration*: ThemeGeneration
    xHasCachedRenders*: bool

proc superviewBacklink*(view: View): View {.inline.} =
  if not view.isNil and not view.xSuperview.isNil:
    result = view.xSuperview[]

proc windowBacklink*(view: View): Responder {.inline.} =
  if not view.isNil and not view.xWindow.isNil:
    result = view.xWindow[]

var activeLayoutTransaction* {.threadvar.}: ptr LayoutTransactionState
var layoutGenerationCounter {.threadvar.}: Natural

proc advanceRevision(value: var uint64) =
  inc value
  if value == 0:
    value = 1

proc renderSlotRevision*(view: View, slot: RenderSlotId): uint64 =
  ## Returns a view-local revision, creating the slot on first use.
  if view.isNil:
    return
  if slot notin view.xRenderSlotRevisions:
    view.xRenderSlotRevisions[slot] = 1
  view.xRenderSlotRevisions[slot]

proc markLocalNeedsDisplay*(view: View, wholeView = true, propagateAncestors = false) =
  if view.isNil:
    return
  view.xDisplayRevision.advanceRevision()
  for revision in view.xRenderSlotRevisions.mvalues:
    revision.advanceRevision()
  view.xNeedsDisplay = true
  view.xNeedsLocalDisplay = true
  if wholeView:
    view.xInvalidRects.setLen(0)
  if propagateAncestors:
    var ancestor = view.superviewBacklink()
    while not ancestor.isNil:
      ancestor.xNeedsDisplay = true
      ancestor = ancestor.superviewBacklink()

proc markRenderSlotNeedsDisplay*(
    view: View, slot: RenderSlotId, propagateAncestors = false
) =
  ## Invalidates one registered drawing slot while retaining the other slots.
  if view.isNil:
    return
  view.xDisplayRevision.advanceRevision()
  discard view.renderSlotRevision(slot)
  view.xRenderSlotRevisions[slot].advanceRevision()
  view.xNeedsDisplay = true
  view.xNeedsLocalDisplay = true
  view.xInvalidRects.setLen(0)
  if propagateAncestors:
    var ancestor = view.superviewBacklink()
    while not ancestor.isNil:
      ancestor.xNeedsDisplay = true
      ancestor = ancestor.superviewBacklink()

proc markRenderStructureChanged*(view: View) =
  ## Schedules retained-transform reconciliation without dirtying view drawing.
  if view.isNil:
    return
  when defined(useNativeDynlib):
    view.markLocalNeedsDisplay(propagateAncestors = true)
  else:
    view.xNeedsDisplay = true
    var ancestor = view.superviewBacklink()
    while not ancestor.isNil:
      ancestor.xNeedsDisplay = true
      ancestor = ancestor.superviewBacklink()

proc nextLayoutGeneration*(): Natural =
  inc layoutGenerationCounter
  if layoutGenerationCounter == 0:
    inc layoutGenerationCounter
  layoutGenerationCounter

proc layoutDiagnosticName(view: View): string =
  if view.isNil:
    return "<none>"
  if view.xIdentifier.len > 0:
    return view.xIdentifier
  "<unnamed frame=" & $view.xFrame & ">"

proc belongsToLayoutTransaction(
    view: View, transaction: ptr LayoutTransactionState
): bool =
  var current = view
  while not current.isNil:
    if current == transaction.root:
      return true
    current = current.superviewBacklink()

proc noteLayoutInvalidation*(
    target: View, reason: LayoutInvalidationReason, affectsConstraints: bool
) =
  let transaction = activeLayoutTransaction
  if transaction.isNil or target.isNil or
      not target.belongsToLayoutTransaction(transaction):
    return

  let requiresFollowUp =
    case transaction.phase
    of ltpIdle:
      false
    of ltpUpdatingConstraints:
      affectsConstraints and target.xConstraintVisitGeneration == transaction.generation
    of ltpSolvingConstraints:
      affectsConstraints
    of ltpLayingOut:
      affectsConstraints or target.xLayoutVisitGeneration == transaction.generation
  if not requiresFollowUp:
    return

  let invalidatingView =
    if transaction.currentView.isNil: target else: transaction.currentView
  transaction.followUpRequested = true
  transaction.lastInvalidation = LayoutInvalidationDiagnostic(
    generation: transaction.generation,
    invalidatingView: invalidatingView.layoutDiagnosticName(),
    targetView: target.layoutDiagnosticName(),
    phase: transaction.phase,
    reason: reason,
  )
