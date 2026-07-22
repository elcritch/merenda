import std/strutils

import merenda/nimkit

import sigils/selectors

const EffectNames = [
  "Blur", "Material: Default", "Material: Light", "Material: Dark",
  "Material: Titlebar", "Material: Sidebar", "Material: HUD", "Material: Popover",
]

type BackdropCanvas = ref object of View

func backdropRegions(size: Size): seq[Rect] =
  let
    margin = 24.0'f32
    gap = 18.0'f32
    sidebarWidth = min(218.0'f32, max(170.0'f32, size.width * 0.32'f32))
    contentX = margin + sidebarWidth + gap
    contentWidth = max(size.width - contentX - margin, 1.0'f32)
    headerHeight = 112.0'f32
    bodyY = margin + headerHeight + gap
  @[
    rect(margin, margin, sidebarWidth, max(size.height - margin * 2.0'f32, 1.0'f32)),
    rect(contentX, margin, contentWidth, headerHeight),
    rect(contentX, bodyY, contentWidth, max(size.height - bodyY - margin, 1.0'f32)),
  ]

protocol BackdropCanvasDrawing of ViewDrawingProtocol:
  method draw(canvas: BackdropCanvas, context: DrawContext) =
    discard context.addRenderRectangle(
      context.renderRectFor(canvas.bounds), fill(color(0.05, 0.07, 0.11, 0.24))
    )
    for index, region in canvas.bounds.size.backdropRegions():
      let tint =
        if index == 0:
          color(0.13, 0.16, 0.23, 0.62)
        elif index == 1:
          color(0.19, 0.13, 0.23, 0.52)
        else:
          color(0.10, 0.14, 0.20, 0.52)
      discard context.addRenderRectangle(
        context.renderRectFor(region), fill(tint), color(1.0, 1.0, 1.0, 0.16), 1.0, 14.0
      )

proc newBackdropCanvas(): BackdropCanvas =
  result = BackdropCanvas()
  initViewFields(result)
  result.background = color(0.0, 0.0, 0.0, 0.0)
  discard result.withProtocol(BackdropCanvasDrawing)

let
  app = sharedApplication()
  window = newWindow(
    "NimKit Window Effects", frame = rect(140, 120, 720, 480), transparent = true
  )
  root = newBackdropCanvas()
  effectTitle = newHeadingLabel("Backdrop effect")
  effectPicker = newComboBox(EffectNames)
  regionToggle = newCheckBox("Limit blur to panels")
  applyButton = newButton("Apply")
  clearButton = newButton("Clear")
  title = newTitleLabel("Native window effects")
  subtitle = newStatusLabel(
    "A transparent NimKit window backed by Siwin blur and material effects."
  )
  statusTitle = newHeadingLabel("Backend status")
  status = newStatusLabel("Preparing the native window…")
  hint = newStatusLabel(
    "Move this window over photos, text, or another app to make the effect obvious."
  )
  applyAction = actionSelector("applyWindowBackdrop")
  clearAction = actionSelector("clearWindowBackdrop")

func chosenEffect(index: int, regions: openArray[Rect]): WindowBackdropEffect =
  case index
  of 0:
    initWindowBackdropEffect(regions)
  of 1:
    initWindowBackdropEffect(bmDefault, regions)
  of 2:
    initWindowBackdropEffect(bmLight, regions)
  of 3:
    initWindowBackdropEffect(bmDark, regions)
  of 4:
    initWindowBackdropEffect(bmTitlebar, regions)
  of 5:
    initWindowBackdropEffect(bmSidebar, regions)
  of 6:
    initWindowBackdropEffect(bmHud, regions)
  else:
    initWindowBackdropEffect(bmPopover, regions)

func capabilityName(capability: WindowEffectCapability): string =
  case capability
  of wecBackdropBlur: "blur"
  of wecBackdropBlurRegions: "regions"
  of wecBackdropMaterial: "materials"

proc capabilitySummary(window: Window): string =
  var names: seq[string]
  for capability in WindowEffectCapability:
    if window.supports(capability):
      names.add capability.capabilityName()
  if names.len == 0:
    return "none"
  names.join(", ")

proc applyEffect(sender: DynamicAgent) =
  discard sender
  let
    selectedIndex = min(max(effectPicker.selectedIndex, 0), EffectNames.high)
    regions =
      if regionToggle.state == bsOn:
        root.bounds.size.backdropRegions()
      else:
        @[]
    effect = chosenEffect(selectedIndex, regions)
  if window.trySetBackdrop(effect):
    let scope = if regions.len == 0: "whole window" else: "three panel regions"
    status.text =
      EffectNames[selectedIndex] & " active · " & scope & " · capabilities: " &
      window.capabilitySummary()
  else:
    status.text =
      "Unavailable on this backend · capabilities: " & window.capabilitySummary()

proc clearEffect(sender: DynamicAgent) =
  discard sender
  window.clearBackdrop()
  status.text = "Backdrop cleared · capabilities: " & window.capabilitySummary()

effectPicker.selectedIndex = 0
regionToggle.state = bsOn
let applyTarget = newActionTarget(applyAction, applyEffect)
effectPicker.target = applyTarget
effectPicker.action = applyAction
regionToggle.target = applyTarget
regionToggle.action = applyAction
applyButton.target = applyTarget
applyButton.action = applyAction
clearButton.target = newActionTarget(clearAction, clearEffect)
clearButton.action = clearAction

root.addSubviews(
  autoNames(
    effectTitle, effectPicker, regionToggle, applyButton, clearButton, title, subtitle,
    statusTitle, status, hint,
  )
)

activateConstraints:
  effectTitle[atTop] == root[atTop] + 48.0
  effectTitle[atLeft] == root[atLeft] + 42.0
  effectTitle[atWidth] == 180.0
  effectPicker[atTop] == effectTitle[atBottom] + 12.0
  effectPicker[atLeft] == effectTitle[atLeft]
  effectPicker[atWidth] == 176.0
  regionToggle[atTop] == effectPicker[atBottom] + 14.0
  regionToggle[atLeft] == effectTitle[atLeft]
  regionToggle[atWidth] == 176.0
  applyButton[atTop] == regionToggle[atBottom] + 18.0
  applyButton[atLeft] == effectTitle[atLeft]
  applyButton[atWidth] == 82.0
  clearButton[atTop] == applyButton[atTop]
  clearButton[atLeft] == applyButton[atRight] + 10.0
  clearButton[atWidth] == 82.0
  title[atTop] == root[atTop] + 48.0
  title[atLeft] == root[atLeft] + 284.0
  title[atRight] == root[atRight] - 42.0
  subtitle[atTop] == title[atBottom] + 8.0
  subtitle[atLeft] == title[atLeft]
  subtitle[atRight] == title[atRight]
  statusTitle[atTop] == root[atTop] + 184.0
  statusTitle[atLeft] == title[atLeft]
  statusTitle[atRight] == title[atRight]
  status[atTop] == statusTitle[atBottom] + 12.0
  status[atLeft] == statusTitle[atLeft]
  status[atRight] == statusTitle[atRight]
  hint[atTop] == status[atBottom] + 24.0
  hint[atLeft] == statusTitle[atLeft]
  hint[atRight] == statusTitle[atRight]

discard app.showWindow(window, root, effectPicker)
window.ensureNativeWindow()
applyEffect(nil)
app.run()
