import std/[math, os, strformat]

import merenda/nimkit
import sigils/selectors

const DefaultSvg =
  """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 460 240">
  <path d="M120 18 L153 86 L228 97 L174 150 L187 224 L120 188
    L53 224 L66 150 L12 97 L87 86 Z"/>
  <path d="M345 218 C330 202 250 153 250 96 C250 62 276 40 307 40
    C325 40 339 49 345 62 C351 49 365 40 383 40 C414 40 440 62 440 96
    C440 153 360 202 345 218 Z"/>
  <path d="M28 30 C72 2 166 2 212 30" fill="none" stroke="black"
    stroke-width="4" stroke-linecap="round"/>
  <ellipse cx="345" cy="132" rx="72" ry="82" fill="none" stroke="black"
    stroke-width="3"/>
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
    if canvas.svg.layers.len == 0:
      return

    let
      imageAspect = canvas.svg.size.width / canvas.svg.size.height
      imageRect = fittedRect(context.bounds, imageAspect, canvas.zoom)
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
  var mtsdfCount = 0
  for layer in canvas.svg.layers:
    if layer.kind == slkMtsdfFill:
      inc mtsdfCount
  status.text =
    fmt"{displayName} — {canvas.svg.elementCount} elements, {mtsdfCount} MTSDFs, {canvas.svg.layers.len} layers"

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
