import ./responders
import ./theme
import ./types

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
    xFrame*: Rect
    xBounds*: Rect
    xNeedsDisplay*: bool
    xInvalidRects*: seq[Rect]
    xBackgroundColor*: Color
    xClipsToBounds*: bool
    xAppearance*: Appearance
    xHasAppearance*: bool
    xInheritedAppearance*: Appearance
    xHasInheritedAppearance*: bool
    xStyleId*: string
    xStyleClasses*: seq[string]
    xWidgetStates*: set[WidgetState]
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
