import std/[math, os, strformat]

import merenda/nimkit
import sigils/selectors

const DefaultSvg =
  """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 240">
  <path d="M160 18 L193 86 L268 97 L214 150 L227 224 L160 188
    L93 224 L106 150 L52 97 L127 86 Z"/>
  <path d="M160 65 C130 65 108 88 108 117 C108 154 143 178 160 192
    C177 178 212 154 212 117 C212 88 190 65 160 65 Z"/>
</svg>
"""

type SvgCanvas = ref object of View
  svg: SvgMtsdfResource
  zoom: float32

proc fittedRect(bounds: Rect, aspect, zoom: float32): Rect =
  let available = bounds.inset(insets(28.0))
  if available.isEmpty or aspect <= 0.0'f32:
    return rect(available.origin, initSize(0.0, 0.0))

  var
    width = available.size.width
    height = width / aspect
  if height > available.size.height:
    height = available.size.height
    width = height * aspect

  width *= zoom
  height *= zoom
  rect(
    available.origin.x + (available.size.width - width) * 0.5'f32,
    available.origin.y + (available.size.height - height) * 0.5'f32,
    width,
    height,
  )

protocol SvgCanvasDrawing of ViewDrawingProtocol:
  method draw(canvas: SvgCanvas, context: DrawContext) =
    if canvas.svg.image.isNil:
      return

    let
      fieldSize = canvas.svg.image.size()
      fieldAspect = fieldSize.width / fieldSize.height
      imageRect = fittedRect(context.bounds, fieldAspect, canvas.zoom)
      shadowRect = rect(
        imageRect.origin.x + 8.0'f32,
        imageRect.origin.y + 10.0'f32,
        imageRect.size.width,
        imageRect.size.height,
      )

    discard
      context.addSvgMtsdf(shadowRect, canvas.svg, fill(color(0.02, 0.03, 0.05, 0.30)))
    discard
      context.addSvgMtsdf(imageRect, canvas.svg, fill(color(0.18, 0.52, 0.94, 1.0)))

proc newSvgCanvas(): SvgCanvas =
  result = SvgCanvas(zoom: 1.0'f32)
  initViewFields(result)
  result.background = color(0.96, 0.97, 0.985, 1.0)
  result.clipsToBounds = true
  result.accessibilityRole = arImage
  result.accessibilityLabel = "MSDF SVG preview"
  discard result.withProtocol(SvgCanvasDrawing)

proc installSvg(
    canvas: SvgCanvas, svg: sink SvgMtsdfResource, displayName: string, status: Label
) =
  canvas.svg = svg
  canvas.accessibilityLabel = displayName
  canvas.setNeedsDisplay(true)
  let size = canvas.svg.image.size()
  status.text =
    fmt"{displayName} — {canvas.svg.elementCount} paths, {size.width.int}×{size.height.int} MTSDF"

let
  app = sharedApplication()
  window = newWindow("NimKit SVG Viewer", frame = rect(120, 100, 920, 700))
  root = newView()
  controls = newStackView(laHorizontal)
  title = newTitleLabel("SVG Viewer")
  status = newStatusLabel("Loading sample SVG…")
  openButton = newButton("Open SVG…")
  zoomLabel = newStatusLabel("Zoom: 100%")
  zoomSlider = newSlider(0.25, 3.0, 1.0)
  canvas = newSvgCanvas()

proc reportError(error: ref CatchableError) =
  status.text = "Unable to load SVG: " & error.msg

proc loadSvgFile(filePath: string) =
  try:
    let svg = newSvgMtsdfResourceFromFile(
      filePath, name = "svg-viewer-field", cachePolicy = icpAlways
    )
    canvas.installSvg(svg, splitFile(filePath).name & ".svg", status)
  except CatchableError as error:
    reportError(error)

proc openSvg(sender: DynamicAgent) =
  discard sender
  let panel = newOpenPanel()
  panel.message = "Choose an SVG file to render as an MTSDF."
  panel.allowedFileTypes = @["svg"]
  if app.runModal(panel) == PanelResponseOk:
    loadSvgFile(panel.selectedUrl().filePathFromUrl())

proc updateZoom(slider: Slider, sender: DynamicAgent) {.slot.} =
  discard sender
  canvas.zoom = slider.value.float32
  zoomLabel.text = "Zoom: " & $int(round(canvas.zoom * 100.0'f32)) & "%"
  canvas.setNeedsDisplay(true)

openButton.target = newActionTarget(actionSelector("openSvg"), openSvg)
openButton.action = actionSelector("openSvg")
zoomSlider.stepValue = 0.05
zoomSlider.connect(actionDidSend, zoomSlider, updateZoom)

controls.spacing = 10.0
controls.alignment = svaCenter
controls.addArrangedSubview(openButton, zoomLabel, zoomSlider)
openButton.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
zoomLabel.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
zoomSlider.setHuggingPriority(LayoutPriorityLow, laHorizontal)

root.addSubviews(autoNames(title, status, controls, canvas))
activateConstraints:
  title[atTop] == root[atTop] + 22.0
  title[atLeft] == root[atLeft] + 24.0
  title[atRight] == root[atRight] - 24.0
  title[atHeight] == 30.0

  status[atTop] == title[atBottom] + 10.0
  status[atLeft] == title[atLeft]
  status[atRight] == title[atRight]
  status[atHeight] == 24.0

  controls[atTop] == status[atBottom] + 16.0
  controls[atLeft] == title[atLeft]
  controls[atRight] == title[atRight]
  controls[atHeight] == 40.0

  canvas[atTop] == controls[atBottom] + 16.0
  canvas[atLeft] == title[atLeft]
  canvas[atRight] == title[atRight]
  canvas[atBottom] == root[atBottom] - 24.0

if paramCount() > 0:
  loadSvgFile(paramStr(1))
else:
  try:
    let svg = newSvgMtsdfResource(
      DefaultSvg, name = "svg-viewer-field", cachePolicy = icpAlways
    )
    canvas.installSvg(svg, "Embedded sample", status)
  except CatchableError as error:
    reportError(error)

app.runWindow(window, root)
