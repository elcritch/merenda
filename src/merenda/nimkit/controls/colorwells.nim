## Popup color selection controls.

import sigils/core

import ../accessibility/accessibility
import ../drawing
import ../foundation/[selectors, types]
import ../themes
import ../view/views
import ./[controls, menus]

export menus

type
  PopupColorChoice* = object
    title*: string
    color*: Color

  PopupColorWell* = ref object of PopupMenuButton
    xColor: Color
    xChoices: seq[PopupColorChoice]

protocol PopupColorWellEvents:
  proc colorDidChange*(well: PopupColorWell, sender: DynamicAgent) {.signal.}

func initPopupColorChoice*(title: string, color: Color): PopupColorChoice =
  PopupColorChoice(title: title, color: color)

func defaultPopupColorChoices*(): seq[PopupColorChoice] =
  @[
    initPopupColorChoice("Clear", color(0.0, 0.0, 0.0, 0.0)),
    initPopupColorChoice("Black", color(0.08, 0.09, 0.11, 1.0)),
    initPopupColorChoice("White", color(1.0, 1.0, 1.0, 1.0)),
    initPopupColorChoice("Gray", color(0.52, 0.54, 0.58, 1.0)),
    initPopupColorChoice("Red", color(0.88, 0.24, 0.26, 1.0)),
    initPopupColorChoice("Orange", color(0.96, 0.52, 0.16, 1.0)),
    initPopupColorChoice("Yellow", color(0.96, 0.82, 0.20, 1.0)),
    initPopupColorChoice("Green", color(0.22, 0.70, 0.38, 1.0)),
    initPopupColorChoice("Blue", color(0.20, 0.48, 0.92, 1.0)),
    initPopupColorChoice("Purple", color(0.58, 0.34, 0.86, 1.0)),
  ]

proc color*(well: PopupColorWell): Color =
  well.xColor

proc choices*(well: PopupColorWell): lent seq[PopupColorChoice] =
  well.xChoices

proc selectedIndex*(well: PopupColorWell): int =
  for index, choice in well.xChoices:
    if choice.color == well.xColor:
      return index
  -1

proc choiceTitle(well: PopupColorWell): string =
  let index = well.selectedIndex()
  if index >= 0:
    well.xChoices[index].title
  else:
    "Custom"

proc synchronizeChoiceState(well: PopupColorWell) =
  let selected = well.selectedIndex()
  if not well.menu().isNil:
    for index, item in well.menu().items():
      item.state = if index == selected: bsOn else: bsOff
  PopupMenuButton(well).title = "      " & well.choiceTitle()
  well.accessibilityValue = well.choiceTitle()

proc `color=`*(well: PopupColorWell, value: Color) =
  if well.xColor == value:
    well.synchronizeChoiceState()
    return
  well.xColor = value
  well.synchronizeChoiceState()
  well.needsDisplay = true

proc activateColorAtIndex*(well: PopupColorWell, index: int): bool {.discardable.} =
  if index notin 0 ..< well.xChoices.len:
    return
  well.color = well.xChoices[index].color
  emit well.colorDidChange(DynamicAgent(well))
  discard well.sendAction()
  true

protocol PopupColorWellDrawing of ViewDrawingProtocol:
  method draw(well: PopupColorWell, context: DrawContext) =
    discard well.performNext(draw, context)
    let
      bounds = well.bounds()
      swatchSize = max(min(bounds.size.height - 10.0'f32, 18.0'f32), 0.0'f32)
      swatch = rect(
        bounds.origin.x + 7.0'f32,
        bounds.origin.y + (bounds.size.height - swatchSize) * 0.5'f32,
        swatchSize,
        swatchSize,
      )
    discard context.addRenderRectangle(
      context.renderRectFor(swatch),
      fill(well.xColor),
      color(0.28, 0.30, 0.34, 0.85),
      1.0'f32,
      3.0'f32,
    )

proc newColorChoiceMenuItem(well: PopupColorWell, index: int): MenuItem =
  let action = actionSelector("popupColorWellChoose" & $index)
  result = newMenuItem(well.xChoices[index].title, action)
  result.identifier = "color." & $index
  result.validates = false
  result.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      discard well.activateColorAtIndex(index),
  )

proc rebuildMenu(well: PopupColorWell) =
  let menu = newMenu("Colors")
  for index in 0 ..< well.xChoices.len:
    discard menu.addItem(well.newColorChoiceMenuItem(index))
  well.menu = menu
  well.synchronizeChoiceState()

proc initPopupColorWellFields*(
    well: PopupColorWell,
    choices: openArray[PopupColorChoice],
    selectedColor: Color,
    frame = AutoRect,
) =
  initPopupMenuButtonFields(well, frame = frame)
  well.xChoices = @choices
  well.xColor = selectedColor
  well.rebuildMenu()
  well.accessibilityLabel = "Color"
  discard well.withProtocol(PopupColorWellDrawing)

proc newPopupColorWell*(
    choices: openArray[PopupColorChoice],
    selectedColor = color(0.08, 0.09, 0.11, 1.0),
    frame = AutoRect,
): PopupColorWell =
  result = PopupColorWell()
  result.initPopupColorWellFields(choices, selectedColor, frame)

proc newPopupColorWell*(
    selectedColor = color(0.08, 0.09, 0.11, 1.0), frame = AutoRect
): PopupColorWell =
  newPopupColorWell(defaultPopupColorChoices(), selectedColor, frame)
