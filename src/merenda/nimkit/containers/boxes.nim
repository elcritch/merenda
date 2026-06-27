import std/options

import sigils/core

import ../accessibility/accessibility
import ../drawing
import ../foundation/selectors
import ../themes
import ../foundation/types
import ../view/viewgeometry
import ../view/views

export views

type
  BoxKind* = enum
    bkGroup
    bkSeparator

  Box* = ref object of View
    xTitle: string
    xKind: BoxKind
    xSeparatorAxis: LayoutAxis
    xContentView: View

proc invalidateBoxMetrics(box: Box) =
  if box.isNil:
    return
  box.invalidateContainerMetrics()
  box.setNeedsLayout()
  box.setNeedsDisplay(true)

proc boxStyleContext(box: Box): StyleContext =
  if box.isNil:
    controlStyle(srBox)
  else:
    controlStyle(
      srBox, box.widgetStateSet(), id = box.styleId, classes = box.styleClasses
    )

proc resolvedBoxStyle(box: Box): BoxStyle =
  let appearance =
    if box.isNil:
      initAppearance()
    else:
      box.effectiveAppearance()
  appearance.resolveBoxStyle(box.boxStyleContext())

proc boxTitleSize(box: Box): Size =
  if box.isNil or box.xKind == bkSeparator or box.xTitle.len == 0:
    initSize(0.0, 0.0)
  else:
    let style = box.resolvedBoxStyle()
    textNaturalSize(box.xTitle, style.text)

proc boxHasTitle(box: Box): bool =
  not box.isNil and box.xKind == bkGroup and box.xTitle.len > 0

proc boundedRect(rect: Rect): Rect =
  initRect(
    rect.origin.x,
    rect.origin.y,
    max(rect.size.width, 0.0'f32),
    max(rect.size.height, 0.0'f32),
  )

proc contentRect*(box: Box): Rect =
  if box.isNil or box.xKind == bkSeparator:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let
    style = box.resolvedBoxStyle()
    titleSize = box.boxTitleSize()
  style.boxContentRect(box.bounds(), box.boxHasTitle(), titleSize.height).boundedRect()

proc separatorRect(box: Box, style: BoxStyle): Rect =
  let
    bounds = box.bounds()
    thickness = min(
      max(style.separatorThickness, 1.0'f32), max(bounds.size.width, bounds.size.height)
    )
  case box.xSeparatorAxis
  of laHorizontal:
    initRect(
      bounds.origin.x,
      bounds.origin.y + max((bounds.size.height - thickness) / 2.0'f32, 0.0'f32),
      bounds.size.width,
      thickness,
    )
  of laVertical:
    initRect(
      bounds.origin.x + max((bounds.size.width - thickness) / 2.0'f32, 0.0'f32),
      bounds.origin.y,
      thickness,
      bounds.size.height,
    )

proc contentFittingSize(box: Box): Size =
  if box.isNil or box.xKind == bkSeparator or box.xContentView.isNil:
    initSize(0.0, 0.0)
  else:
    let
      content = box.xContentView
      intrinsic = content.trySendLocal(layoutIntrinsicContentSize(), ()).get(
          content.intrinsicContentSize()
        )
    intrinsic.resolveIntrinsicSize(content.bounds().size)

proc naturalGroupSize(box: Box): Size =
  let
    style = box.resolvedBoxStyle()
    titleSize = box.boxTitleSize()
  style.boxControlSize(box.contentFittingSize(), titleSize, box.boxHasTitle())

proc naturalSeparatorSize(box: Box): IntrinsicSize =
  let
    style = box.resolvedBoxStyle()
    thickness = max(style.separatorThickness, 1.0'f32)
  case box.xSeparatorAxis
  of laHorizontal:
    initIntrinsicSize(NoIntrinsicMetric, thickness)
  of laVertical:
    initIntrinsicSize(thickness, NoIntrinsicMetric)

protocol BoxProtocol {.selectorScope: protocol.} from Box:
  property boxTitle -> string
  property boxKind -> BoxKind
  property separatorAxis -> LayoutAxis
  property contentView -> View

  method boxTitle(box: Box): string =
    if box.isNil: "" else: box.xTitle

  method setBoxTitle(box: Box, title: string) =
    if box.isNil or box.xTitle == title:
      return
    box.xTitle = title
    box.invalidateBoxMetrics()

  method boxKind(box: Box): BoxKind =
    if box.isNil: bkGroup else: box.xKind

  method setBoxKind(box: Box, kind: BoxKind) =
    if box.isNil or box.xKind == kind:
      return
    box.xKind = kind
    box.invalidateBoxMetrics()

  method separatorAxis(box: Box): LayoutAxis =
    if box.isNil: laHorizontal else: box.xSeparatorAxis

  method setSeparatorAxis(box: Box, axis: LayoutAxis) =
    if box.isNil or box.xSeparatorAxis == axis:
      return
    box.xSeparatorAxis = axis
    box.invalidateBoxMetrics()

  method contentView(box: Box): View =
    if box.isNil: nil else: box.xContentView

  method setContentView(box: Box, contentView: View) =
    if box.isNil:
      return
    if not contentView.isNil and box.xContentView == contentView:
      return

    let oldContent = box.xContentView
    if not oldContent.isNil and oldContent.superview == box:
      oldContent.removeFromSuperview()

    box.xContentView =
      if contentView.isNil:
        newView(frame = initRect(0.0, 0.0, 0.0, 0.0))
      else:
        contentView
    box.xContentView.background = initColor(0.0, 0.0, 0.0, 0.0)
    box.xContentView.autoresizingMaskConstraints = false
    if box.xContentView.superview != box:
      box.addSubview(box.xContentView)
    box.invalidateBoxMetrics()

  method addContentSubview*(box: Box, child: View) =
    if box.isNil or child.isNil:
      return
    if box.xContentView.isNil:
      box.setContentView(nil)
    box.xContentView.addSubview(child)
    box.invalidateBoxMetrics()

proc title*(box: Box): string =
  if box.isNil:
    ""
  else:
    box.boxTitle()

proc `title=`*(box: Box, title: string) =
  box.setBoxTitle(title)

proc `boxKind=`*(box: Box, kind: BoxKind) =
  box.setBoxKind(kind)

proc `separatorAxis=`*(box: Box, axis: LayoutAxis) =
  box.setSeparatorAxis(axis)

proc `contentView=`*(box: Box, contentView: View) =
  box.setContentView(contentView)

proc intrinsicContentSize*(box: Box): IntrinsicSize =
  if box.isNil:
    NoIntrinsicContentSize
  elif box.xKind == bkSeparator:
    box.naturalSeparatorSize()
  else:
    initIntrinsicSize(box.naturalGroupSize())

proc layoutBoxContent(box: Box) =
  if box.isNil or box.xContentView.isNil:
    return
  let frame =
    if box.xKind == bkSeparator:
      initRect(0.0, 0.0, 0.0, 0.0)
    else:
      box.contentRect()
  box.xContentView.applyLayoutFrame(frame, lfoContainer)

proc drawSeparator(box: Box, context: DrawContext, style: BoxStyle) =
  let rect = box.separatorRect(style)
  if rect.isEmpty:
    return
  discard context.addRenderRectangle(
    context.renderRectFor(rect), style.box.borderColor, style.box.borderColor, 0.0'f32
  )

proc drawGroupBox(box: Box, context: DrawContext, style: BoxStyle) =
  let
    bounds = box.bounds()
    titleSize = box.boxTitleSize()
    hasTitle = box.boxHasTitle()
    titleBand = style.boxTitleBandHeight(hasTitle, titleSize.height)
    borderRect =
      if hasTitle:
        initRect(
          bounds.origin.x,
          bounds.origin.y + titleBand,
          bounds.size.width,
          max(bounds.size.height - titleBand, 0.0'f32),
        )
      else:
        bounds

  if not borderRect.isEmpty:
    discard context.addRenderRectangle(
      context.renderRectFor(borderRect),
      style.box.fill,
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      cornerRadii = style.box.cornerRadii,
    )

  if hasTitle:
    let
      textHeight = max(style.titleHeight, titleSize.height)
      textRect = initRect(
        bounds.origin.x + style.contentInsets.left + style.text.insets.left,
        bounds.origin.y,
        max(
          bounds.size.width - style.contentInsets.horizontal -
            style.text.insets.horizontal,
          0.0'f32,
        ),
        textHeight,
      )
      titleText = clippedText(box.xTitle, textRect.size.width, style.text)
    if titleText.len > 0 and not textRect.isEmpty:
      context.addText(textRect, titleText, style.text)

protocol DefaultBoxLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(box: Box): IntrinsicSize =
    box.intrinsicContentSize()

  method layoutSubviews(box: Box) =
    box.layoutBoxContent()

protocol DefaultBoxDrawing of ViewDrawingProtocol:
  method draw(box: Box, context: DrawContext) =
    if box.isNil or context.isNil or box.bounds().isEmpty:
      return
    let style = context.appearance.resolveBoxStyle(box.boxStyleContext())
    case box.xKind
    of bkGroup:
      box.drawGroupBox(context, style)
    of bkSeparator:
      box.drawSeparator(context, style)

protocol DefaultBoxAccessibility of AccessibilityProtocol:
  method accessibilityRole(box: Box): AccessibilityRole =
    if box.xHasAccessibilityRole:
      box.xAccessibilityRole
    elif box.xKind == bkSeparator:
      arSeparator
    else:
      arGroup

  method accessibilityLabel(box: Box): string =
    if box.xAccessibilityLabel.len > 0:
      box.xAccessibilityLabel
    elif box.xKind == bkGroup:
      box.xTitle
    else:
      box.xIdentifier

  method isAccessibilityElement(box: Box): bool =
    true

  method accessibilityChildren(box: Box): seq[View] =
    if box.xKind == bkSeparator:
      return @[]
    else:
      for child in box.subviews():
        if child.isAccessibilityIgnored():
          continue
        if child.isAccessibilityElement():
          result.add child
        else:
          result.add child.accessibilityChildren()

protocol BoxLifecycleSlots of ViewLifecycleProtocol:
  proc willRemoveSubview(box: Box, child: View) {.slot.} =
    if child == box.xContentView:
      box.xContentView = nil
      box.invalidateBoxMetrics()

proc initBoxFields*(
    box: Box,
    title = "",
    frame: Rect = AutoRect,
    kind = bkGroup,
    separatorAxis = laHorizontal,
) =
  initViewFields(box, frame)
  box.background = initColor(0.0, 0.0, 0.0, 0.0)
  box.xTitle = title
  box.xKind = kind
  box.xSeparatorAxis = separatorAxis
  discard box.withProto()
  discard box.withProtocol(DefaultBoxLayout)
  discard box.withProtocol(DefaultBoxDrawing)
  discard box.withProtocol(DefaultBoxAccessibility)
  discard box.withProtocol(BoxLifecycleSlots)
  box.observeProtocol(box, BoxLifecycleSlots)
  box.setContentView(nil)
  box.applyInitialFrame(frame)

proc newBox*(title = "", frame: Rect = AutoRect): Box =
  result = Box()
  initBoxFields(result, title, frame, bkGroup)

proc newGroupBox*(title = "", frame: Rect = AutoRect): Box =
  newBox(title, frame)

proc newSeparatorBox*(axis = laHorizontal, frame: Rect = AutoRect): Box =
  result = Box()
  initBoxFields(result, frame = frame, kind = bkSeparator, separatorAxis = axis)

proc newHorizontalSeparator*(frame: Rect = AutoRect): Box =
  newSeparatorBox(laHorizontal, frame)

proc newVerticalSeparator*(frame: Rect = AutoRect): Box =
  newSeparatorBox(laVertical, frame)
