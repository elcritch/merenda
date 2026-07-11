import sigils/core

import ../accessibility/accessibility
import ../drawing
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/views

export views

type IconLabel* = ref object of View
  xIcon: string
  xTitle: string
  xIconColor: Color

proc icon*(label: IconLabel): string =
  label.xIcon

proc `icon=`*(label: IconLabel, value: string) =
  if label.xIcon == value:
    return
  label.xIcon = value
  label.invalidateIntrinsicContentSize()
  label.setNeedsDisplay(true)

proc title*(label: IconLabel): string =
  label.xTitle

proc `title=`*(label: IconLabel, value: string) =
  if label.xTitle == value:
    return
  label.xTitle = value
  label.invalidateIntrinsicContentSize()
  label.setNeedsDisplay(true)

proc iconColor*(label: IconLabel): Color =
  label.xIconColor

proc `iconColor=`*(label: IconLabel, value: Color) =
  if label.xIconColor == value:
    return
  label.xIconColor = value
  label.setNeedsDisplay(true)

proc iconLabelStyleContext(label: IconLabel): StyleContext =
  controlStyle(
    srTextField,
    label.widgetStateSet(),
    id = label.styleId,
    classes = label.styleClasses,
  )

proc resolvedIconColor(
    label: IconLabel, appearance: Appearance, context: StyleContext, fallback: Color
): Color =
  if label.xIconColor.a > 0.0'f32:
    label.xIconColor
  else:
    appearance.resolveColor(context, StyleMarkColor, fallback)

proc iconLabelMetrics(
    label: IconLabel, appearance: Appearance
): tuple[textStyle, iconStyle: TextStyle, iconWidth, spacing: float32] =
  let
    context = label.iconLabelStyleContext()
    textStyle =
      appearance.resolveTextStyle(context, color(0.12, 0.12, 0.13, 1.0), insets(0.0))
    iconSize = appearance.resolveLength(
      context, StyleIndicatorSize, textStyle.fontSize + 4.0'f32
    )
    spacing = appearance.resolveLength(context, StyleIndicatorSpacing, 8.0'f32)
    iconStyle = TextStyle(
      color: label.resolvedIconColor(appearance, context, textStyle.color),
      insets: insets(0.0),
      fontName: textStyle.fontName,
      fontSize: iconSize,
    )
    iconNaturalSize = label.xIcon.textNaturalSize(iconStyle)
    iconWidth =
      if label.xIcon.len > 0:
        max(iconNaturalSize.width, iconSize)
      else:
        0.0'f32
  (
    textStyle,
    iconStyle,
    iconWidth,
    if label.xIcon.len > 0 and label.xTitle.len > 0: spacing else: 0.0'f32,
  )

proc iconLabelNaturalSize(label: IconLabel, appearance: Appearance): Size =
  let metrics = label.iconLabelMetrics(appearance)
  let
    iconSize = label.xIcon.textNaturalSize(metrics.iconStyle)
    textSize = label.xTitle.textNaturalSize(metrics.textStyle)
  initSize(
    metrics.iconWidth + metrics.spacing + textSize.width,
    max(iconSize.height, textSize.height),
  )

protocol IconLabelDrawing of ViewDrawingProtocol:
  method draw(label: IconLabel, context: DrawContext) =
    let
      metrics = label.iconLabelMetrics(context.appearance)
      contentRect = context.bounds.inset(metrics.textStyle.insets)
      iconRect = rect(
        contentRect.origin.x,
        contentRect.origin.y,
        min(metrics.iconWidth, contentRect.size.width),
        contentRect.size.height,
      )
      textX = iconRect.maxX + metrics.spacing
      textRect = rect(
        textX,
        contentRect.origin.y,
        max(contentRect.maxX - textX, 0.0'f32),
        contentRect.size.height,
      )
    if label.xIcon.len > 0:
      context.addText(iconRect, label.xIcon, metrics.iconStyle, alignment = taCenter)
    if label.xTitle.len > 0:
      context.addText(textRect, label.xTitle, metrics.textStyle)

  method layoutIntrinsicContentSize(label: IconLabel): IntrinsicSize =
    initIntrinsicSize(label.iconLabelNaturalSize(label.effectiveAppearance()))

protocol IconLabelAccessibility of AccessibilityProtocol:
  method accessibilityRole(label: IconLabel): AccessibilityRole =
    arStaticText

  method accessibilityLabel(label: IconLabel): string =
    if label.xAccessibilityLabel.len > 0: label.xAccessibilityLabel else: label.xTitle

  method accessibilityValue(label: IconLabel): string =
    ""

  method isAccessibilityElement(label: IconLabel): bool =
    true

proc intrinsicContentSize*(label: IconLabel): IntrinsicSize =
  initIntrinsicSize(label.iconLabelNaturalSize(label.effectiveAppearance()))

proc initIconLabelFields*(
    label: IconLabel,
    icon: string,
    title: string,
    iconColor = color(0.0, 0.0, 0.0, 0.0),
    frame: Rect = AutoRect,
) =
  initViewFields(label, frame)
  label.xIcon = icon
  label.xTitle = title
  label.xIconColor = iconColor
  label.styleClasses = [LabelStyleClass, IconLabelStyleClass]
  label.accessibilityElement = true
  discard label.withProtocol(IconLabelDrawing)
  discard label.withProtocol(IconLabelAccessibility)
  label.applyInitialFrame(frame)

proc newIconLabel*(
    icon: string,
    title: string,
    iconColor = color(0.0, 0.0, 0.0, 0.0),
    frame: Rect = AutoRect,
): IconLabel =
  result = IconLabel()
  result.initIconLabelFields(icon, title, iconColor, frame)
