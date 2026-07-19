import sigils/core

import ../accessibility/accessibility
import ../drawing
import ../drawing/images
import ../foundation/selectors
import ../foundation/types
import ./views

export images
export views

type
  ImageScaling* = enum
    isScaleNone
    isScaleAxesIndependently
    isScaleProportionallyUpOrDown
    isScaleProportionallyDown

  ImageAlignment* = enum
    iaCenter
    iaTop
    iaTopLeft
    iaTopRight
    iaLeft
    iaRight
    iaBottom
    iaBottomLeft
    iaBottomRight

  ImageView* = ref object of View
    xImage: ImageResource
    xScaling: ImageScaling
    xAlignment: ImageAlignment
    xTint: Color

proc imageRectForBounds(
    bounds: Rect, imageSize: Size, scaling: ImageScaling, alignment: ImageAlignment
): Rect =
  if imageSize.width <= 0.0'f32 or imageSize.height <= 0.0'f32 or bounds.isEmpty:
    return rect(bounds.origin, initSize(0.0, 0.0))

  var drawSize = imageSize
  case scaling
  of isScaleNone:
    discard
  of isScaleAxesIndependently:
    drawSize = bounds.size
  of isScaleProportionallyUpOrDown, isScaleProportionallyDown:
    let factor =
      min(bounds.size.width / imageSize.width, bounds.size.height / imageSize.height)
    let scale =
      if scaling == isScaleProportionallyDown:
        min(factor, 1.0'f32)
      else:
        factor
    drawSize = initSize(imageSize.width * scale, imageSize.height * scale)

  let x =
    case alignment
    of iaTopLeft, iaLeft, iaBottomLeft:
      bounds.origin.x
    of iaTopRight, iaRight, iaBottomRight:
      bounds.maxX - drawSize.width
    else:
      bounds.origin.x + (bounds.size.width - drawSize.width) / 2.0'f32
  let y =
    case alignment
    of iaTop, iaTopLeft, iaTopRight:
      bounds.origin.y
    of iaBottom, iaBottomLeft, iaBottomRight:
      bounds.maxY - drawSize.height
    else:
      bounds.origin.y + (bounds.size.height - drawSize.height) / 2.0'f32

  rect(x, y, drawSize.width, drawSize.height)

protocol ImageViewProtocol {.setterStyle: nim.} from ImageView:
  property image -> ImageResource
  property imageScaling -> ImageScaling
  property imageAlignment -> ImageAlignment
  property imageTint -> Color

  method image(imageView: ImageView): ImageResource =
    imageView.xImage

  method `image=`(imageView: ImageView, image: ImageResource) =
    if imageView.xImage == image:
      return
    imageView.xImage = image
    imageView.invalidateIntrinsicContentSize()
    imageView.needsDisplay = true

  method imageScaling(imageView: ImageView): ImageScaling =
    imageView.xScaling

  method `imageScaling=`(imageView: ImageView, scaling: ImageScaling) =
    if imageView.xScaling == scaling:
      return
    imageView.xScaling = scaling
    imageView.needsDisplay = true

  method imageAlignment(imageView: ImageView): ImageAlignment =
    imageView.xAlignment

  method `imageAlignment=`(imageView: ImageView, alignment: ImageAlignment) =
    if imageView.xAlignment == alignment:
      return
    imageView.xAlignment = alignment
    imageView.needsDisplay = true

  method imageTint(imageView: ImageView): Color =
    imageView.xTint

  method `imageTint=`(imageView: ImageView, tint: Color) =
    if imageView.xTint == tint:
      return
    imageView.xTint = tint
    imageView.needsDisplay = true

protocol ImageViewDrawing of ViewDrawingProtocol:
  method draw(imageView: ImageView, context: DrawContext) =
    let image = imageView.image()
    if image.isNil:
      return
    let rect = context.bounds.imageRectForBounds(
      image.size(), imageView.imageScaling(), imageView.imageAlignment()
    )
    discard context.addImage(rect, image, imageView.imageTint())

  method layoutIntrinsicContentSize(imageView: ImageView): IntrinsicSize =
    let image = imageView.image()
    if image.isNil:
      return NoIntrinsicContentSize
    initIntrinsicSize(image.size())

protocol ImageViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(imageView: ImageView): AccessibilityRole =
    arImage

  method accessibilityTraits(imageView: ImageView): AccessibilityTraits =
    result = imageView.xAccessibilityTraits
    if ssDisabled in imageView.xWidgetStates:
      result.incl atDisabled
    if ssFocused in imageView.xWidgetStates:
      result.incl atFocused
    if ssSelected in imageView.xWidgetStates:
      result.incl atSelected
    result.incl atImage

  method accessibilityLabel(imageView: ImageView): string =
    if imageView.xAccessibilityLabel.len > 0:
      return imageView.xAccessibilityLabel
    if imageView.xIdentifier.len > 0:
      return imageView.xIdentifier
    let image = imageView.image()
    if image.isNil:
      ""
    else:
      image.name()

proc intrinsicContentSize*(imageView: ImageView): IntrinsicSize =
  let image = imageView.image()
  if image.isNil:
    return NoIntrinsicContentSize
  initIntrinsicSize(image.size())

proc initImageViewFields*(
    imageView: ImageView, image: ImageResource = nil, frame: Rect = AutoRect
) =
  initViewFields(imageView, frame)
  imageView.xImage = image
  imageView.xScaling = isScaleProportionallyDown
  imageView.xAlignment = iaCenter
  imageView.xTint = color(1.0, 1.0, 1.0, 1.0)
  imageView.backgroundColor = color(0.0, 0.0, 0.0, 0.0)
  imageView.accessibilityElement = true
  discard imageView.withProto()
  discard imageView.withProtocol(ImageViewDrawing)
  discard imageView.withProtocol(ImageViewAccessibility)
  imageView.applyInitialFrame(frame)

proc newImageView*(image: ImageResource = nil, frame: Rect = AutoRect): ImageView =
  result = ImageView()
  initImageViewFields(result, image, frame)
