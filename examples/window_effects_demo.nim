import std/strutils

import merenda/nimkit

import sigils/selectors

const EffectNames = [
  "Blur", "Material: Default", "Material: Light", "Material: Dark",
  "Material: Titlebar", "Material: Sidebar", "Material: HUD", "Material: Popover",
]

type
  BackdropCanvas* = ref object of View

  WindowEffectsDemo* = ref object
    app*: Application
    window*: Window
    root*: BackdropCanvas
    effectPicker*: ComboBox
    regionToggle*: Button
    applyButton*: Button
    clearButton*: Button
    status*: Label

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
    for index, region in canvas.bounds.size.backdropRegions():
      let tint =
        if index == 0:
          color(0.13, 0.16, 0.23, 0.34)
        elif index == 1:
          color(0.19, 0.13, 0.23, 0.27)
        else:
          color(0.10, 0.14, 0.20, 0.27)
      discard context.addRenderRectangle(
        context.renderRectFor(region), fill(tint), color(1.0, 1.0, 1.0, 0.24), 1.0, 14.0
      )

proc newBackdropCanvas(): BackdropCanvas =
  result = BackdropCanvas()
  initViewFields(result)
  result.background = color(0.03, 0.04, 0.07, 0.08)
  discard result.withProtocol(BackdropCanvasDrawing)

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

proc applyEffect*(demo: WindowEffectsDemo): bool {.discardable.} =
  if demo.isNil:
    return
  let
    selectedIndex = min(max(demo.effectPicker.selectedIndex, 0), EffectNames.high)
    regions =
      if demo.regionToggle.state == bsOn:
        demo.root.bounds.size.backdropRegions()
      else:
        @[]
    effect = chosenEffect(selectedIndex, regions)
  result = demo.window.trySetBackdrop(effect)
  if result:
    let scope = if regions.len == 0: "whole window" else: "three panel regions"
    let state = if demo.window.backdropActive: "active" else: "staged"
    demo.status.text =
      EffectNames[selectedIndex] & " " & state & " · " & scope & " · capabilities: " &
      demo.window.capabilitySummary()
  else:
    demo.status.text =
      "Unavailable on this backend · capabilities: " & demo.window.capabilitySummary()

proc clearEffect*(demo: WindowEffectsDemo) =
  if demo.isNil:
    return
  demo.window.clearBackdrop()
  demo.status.text =
    "Backdrop cleared · capabilities: " & demo.window.capabilitySummary()

proc newWindowEffectsDemo*(app = newApplication()): WindowEffectsDemo =
  result = WindowEffectsDemo(
    app: app,
    window: newWindow(
      "NimKit Window Effects", frame = rect(140, 120, 720, 480), transparent = true
    ),
    root: newBackdropCanvas(),
    effectPicker: newComboBox(EffectNames),
    regionToggle: newCheckBox("Limit blur to panels"),
    applyButton: newButton("Apply"),
    clearButton: newButton("Clear"),
    status: newStatusLabel("Preparing the native window…"),
  )
  let
    effectTitle = newHeadingLabel("Backdrop effect")
    title = newTitleLabel("Native window effects")
    subtitle = newStatusLabel(
      "A transparent NimKit window backed by Siwin blur and material effects."
    )
    statusTitle = newHeadingLabel("Backend status")
    hint = newStatusLabel(
      "Move this window over photos, text, or another app to make the effect obvious."
    )
    applyAction = actionSelector("applyWindowBackdrop")
    clearAction = actionSelector("clearWindowBackdrop")
    demo = result

  result.effectPicker.selectedIndex = 0
  result.regionToggle.state = bsOff
  let applyTarget = newActionTarget(
    applyAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.applyEffect(),
  )
  result.effectPicker.target = applyTarget
  result.effectPicker.action = applyAction
  result.regionToggle.target = applyTarget
  result.regionToggle.action = applyAction
  result.applyButton.target = applyTarget
  result.applyButton.action = applyAction
  result.clearButton.target = newActionTarget(
    clearAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.clearEffect(),
  )
  result.clearButton.action = clearAction

  result.root.addSubviews(
    autoNames(
      effectTitle, result.effectPicker, result.regionToggle, result.applyButton,
      result.clearButton, title, subtitle, statusTitle, result.status, hint,
    )
  )

  activateConstraints:
    effectTitle[atTop] == result.root[atTop] + 48.0
    effectTitle[atLeft] == result.root[atLeft] + 42.0
    effectTitle[atWidth] == 180.0
    result.effectPicker[atTop] == effectTitle[atBottom] + 12.0
    result.effectPicker[atLeft] == effectTitle[atLeft]
    result.effectPicker[atWidth] == 176.0
    result.regionToggle[atTop] == result.effectPicker[atBottom] + 14.0
    result.regionToggle[atLeft] == effectTitle[atLeft]
    result.regionToggle[atWidth] == 176.0
    result.applyButton[atTop] == result.regionToggle[atBottom] + 18.0
    result.applyButton[atLeft] == effectTitle[atLeft]
    result.applyButton[atWidth] == 82.0
    result.clearButton[atTop] == result.applyButton[atTop]
    result.clearButton[atLeft] == result.applyButton[atRight] + 10.0
    result.clearButton[atWidth] == 82.0
    title[atTop] == result.root[atTop] + 48.0
    title[atLeft] == result.root[atLeft] + 284.0
    title[atRight] == result.root[atRight] - 42.0
    subtitle[atTop] == title[atBottom] + 8.0
    subtitle[atLeft] == title[atLeft]
    subtitle[atRight] == title[atRight]
    statusTitle[atTop] == result.root[atTop] + 184.0
    statusTitle[atLeft] == title[atLeft]
    statusTitle[atRight] == title[atRight]
    result.status[atTop] == statusTitle[atBottom] + 12.0
    result.status[atLeft] == statusTitle[atLeft]
    result.status[atRight] == statusTitle[atRight]
    hint[atTop] == result.status[atBottom] + 24.0
    hint[atLeft] == statusTitle[atLeft]
    hint[atRight] == statusTitle[atRight]

  result.window.setContentView(result.root)
  result.applyEffect()

proc showWindowEffectsDemo*(demo: WindowEffectsDemo) =
  if demo.isNil:
    return
  discard demo.app.showWindow(demo.window, demo.root, demo.effectPicker)
  demo.window.ensureNativeWindow()
  demo.applyEffect()

when isMainModule:
  let demo = newWindowEffectsDemo(sharedApplication())
  demo.showWindowEffectsDemo()
  demo.app.run()
