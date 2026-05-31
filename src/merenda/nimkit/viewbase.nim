import ./responders
import ./theme
import ./types

export responders

type
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
    xAlignmentInsets*: EdgeInsets
    xLastBaselineOffset*: float32
    xFirstBaselineOffset*: float32
    xHorizHuggingPriority*: LayoutPriority
    xVertHuggingPriority*: LayoutPriority
    xHorizCompressionPriority*: LayoutPriority
    xVertCompressionPriority*: LayoutPriority
    xConstraints*: seq[LayoutConstraint]
    xNextKeyView*: View
    xPreviousKeyView*: View
    xSuperview*: View
    xWindow*: Responder
    xSubviews*: seq[View]
