import sigils/core
import sigils/selectors

import ../accessibility/accessibility
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types

import ./buttons

export buttons

type
  Chip* = ref object of Button
    xLabel: string
    xRemovable: bool
    xOnRemove: ChipRemoveHandler

  ChipRemoveHandler* = proc(chip: Chip) {.closure.}

const ChipRemoveWidth = 24.0'f32

func chipTitle(label: string, removable: bool): string =
  if not removable:
    return label
  if label.len == 0:
    "×"
  else:
    label & "  ×"

proc label*(chip: Chip): string =
  chip.xLabel

proc `label=`*(chip: Chip, value: string) =
  if chip.xLabel == value:
    return
  chip.xLabel = value
  chip.title = chipTitle(value, chip.xRemovable)

proc text*(chip: Chip): string =
  chip.label()

proc `text=`*(chip: Chip, value: string) =
  chip.label = value

proc removable*(chip: Chip): bool =
  chip.xRemovable

proc `removable=`*(chip: Chip, value: bool) =
  if chip.xRemovable == value:
    return
  chip.xRemovable = value
  chip.title = chipTitle(chip.xLabel, value)

proc onRemove*(chip: Chip): ChipRemoveHandler =
  chip.xOnRemove

proc `onRemove=`*(chip: Chip, handler: ChipRemoveHandler) =
  chip.xOnRemove = handler

proc selected*(chip: Chip): bool =
  chip.state in {bsOn, bsMixed}

proc `selected=`*(chip: Chip, value: bool) =
  chip.state = if value: bsOn else: bsOff

proc removeButtonRect*(chip: Chip): Rect =
  if not chip.xRemovable:
    return rect(0.0, 0.0, 0.0, 0.0)
  let bounds = chip.bounds()
  rect(
    max(bounds.maxX - ChipRemoveWidth, bounds.origin.x),
    bounds.origin.y,
    min(ChipRemoveWidth, bounds.size.width),
    bounds.size.height,
  )

proc remove*(chip: Chip): bool {.discardable.} =
  if not chip.isEnabled() or not chip.xRemovable or chip.xOnRemove.isNil:
    return false
  chip.xOnRemove(chip)
  true

protocol DefaultChipEvents of ResponderEventProtocol:
  method mouseEntered(chip: Chip, event: MouseEvent): bool =
    discard event
    if chip.isEnabled():
      chip.hovered = true
      return true

  method mouseExited(chip: Chip, event: MouseEvent): bool =
    discard event
    if chip.isEnabled():
      chip.hovered = false
      return true

  method mouseDown(chip: Chip, event: MouseEvent): bool =
    if chip.isEnabled() and event.button == mbPrimary:
      chip.cancelActivationFeedback()
      chip.setHighlighted(true)
      return true

  method mouseDragged(chip: Chip, event: MouseEvent): bool =
    if chip.isEnabled() and event.button == mbPrimary:
      chip.setHighlighted(chip.pointInside(event.location))
      return true

  method mouseUp(chip: Chip, event: MouseEvent): bool =
    if chip.isEnabled() and event.button == mbPrimary:
      let clicked = chip.pointInside(event.location)
      let removeClicked = clicked and chip.removeButtonRect().contains(event.location)
      chip.setHighlighted(false)
      if clicked:
        if removeClicked:
          discard chip.remove()
        else:
          discard chip.sendAction()
      return true

  method keyDown(chip: Chip, event: KeyEvent): bool =
    if not chip.isEnabled():
      return false
    case event.key
    of keyEnter, keySpace:
      discard chip.sendAction()
      true
    of keyBackspace, keyDelete:
      chip.remove()
    else:
      false

protocol DefaultChipAccessibility of AccessibilityProtocol:
  method accessibilityRole(chip: Chip): AccessibilityRole =
    arButton

  method accessibilityLabel(chip: Chip): string =
    if chip.xAccessibilityLabel.len > 0: chip.xAccessibilityLabel else: chip.xLabel

  method accessibilityValue(chip: Chip): string =
    if chip.selected: "selected" else: ""

  method accessibilityTraits(chip: Chip): AccessibilityTraits =
    result = chip.xAccessibilityTraits + {atButton}
    if not chip.isEnabled():
      result.incl atDisabled
    if chip.focused():
      result.incl atFocused
    if chip.selected:
      result.incl atSelected

  method isAccessibilityElement(chip: Chip): bool =
    true

  method accessibilityActionNames(chip: Chip): seq[string] =
    result = @[AccessibilityActionPress]
    if chip.removable:
      result.add AccessibilityActionDelete

  method accessibilityPerformAction(chip: Chip, action: string): bool =
    if not chip.isEnabled():
      return false
    case action
    of AccessibilityActionPress:
      discard chip.sendAction()
      true
    of AccessibilityActionDelete:
      chip.remove()
    else:
      false

proc initChipFields*(chip: Chip, label = "", removable = true, frame: Rect = AutoRect) =
  initButtonFields(chip, chipTitle(label, removable), frame)
  chip.xLabel = label
  chip.xRemovable = removable
  chip.buttonType = btMomentary
  discard chip.withProtocol(DefaultChipEvents)
  discard chip.withProtocol(DefaultChipAccessibility)
  chip.applyInitialFrame(frame)

proc newChip*(label = "", removable = true, frame: Rect = AutoRect): Chip =
  result = Chip()
  result.initChipFields(label, removable, frame)
