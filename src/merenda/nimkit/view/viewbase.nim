import ../responder/responders
import ../themes
import ../foundation/types

from figdraw/fignodes import Renders

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

  View* = ref object of Responder
    xTag*: int
    xIdentifier*: string
    xFrame*: Rect
    xBounds*: Rect
    xFlipped*: bool
    xNeedsDisplay*: bool
    xInvalidRects*: seq[Rect]
    xBackgroundColor*: Color
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
    xSuperview*: View
    xWindow*: Responder
    xSubviews*: seq[View]
    xToolTip*: string
    xCursorRects*: seq[ViewCursorRect]
    xTrackingAreas*: seq[ViewTrackingArea]
    xRegisteredDraggedTypes*: seq[string]
    xContextMenu*: Responder
    xContextMenuHandlerInstalled*: bool
    xCachedRenders*: Renders
    xCachedAppearance*: Appearance
    xHasCachedRenders*: bool
