import ./responders
import ./theme
import ./types

export responders

type
  AutoresizingState* = object
    referenceRect*: Rect
    referenceSuperviewRect*: Rect
    hasReference*: bool

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

  View* = ref object of Responder
    xFrame*: Rect
    xBounds*: Rect
    xHidden*: bool
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
    xHovered*: bool
    xActive*: bool
    xHasFocus*: bool
    xFocusVisible*: bool
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
    xNextKeyView*: View
    xPreviousKeyView*: View
    xSuperview*: View
    xWindow*: Responder
    xSubviews*: seq[View]
