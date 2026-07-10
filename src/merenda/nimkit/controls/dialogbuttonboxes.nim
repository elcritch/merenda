import std/algorithm

import ./buttons
import ../containers/stackviews
import ../foundation/types
import ../view/views

export buttons, stackviews

type
  DialogButtonRole* = enum
    dbrHelp
    dbrReset
    dbrApply
    dbrAlternate
    dbrDestructive
    dbrReject
    dbrAccept

  DialogButtonAlignment* = enum
    dbaLeading
    dbaCenter
    dbaTrailing

  DialogButtonSpec* = object
    role*: DialogButtonRole
    button*: Button

  DialogButtonBox* = ref object of StackView
    xButtonSpecs: seq[DialogButtonSpec]
    xButtonAlignment: DialogButtonAlignment
    xLeadingSpacer: View
    xTrailingSpacer: View

  OrderedDialogButton = object
    index: int
    spec: DialogButtonSpec

const DefaultDialogButtonSpacing = 10.0'f32

func standardTitle*(role: DialogButtonRole): string =
  case role
  of dbrHelp: "Help"
  of dbrReset: "Reset"
  of dbrApply: "Apply"
  of dbrAlternate: "Alternate"
  of dbrDestructive: "Delete"
  of dbrReject: "Cancel"
  of dbrAccept: "OK"

func dialogButtonRank(role: DialogButtonRole): int =
  when defined(macosx) or defined(macos):
    case role
    of dbrHelp: 10
    of dbrReset: 20
    of dbrApply: 30
    of dbrAlternate: 40
    of dbrDestructive: 50
    of dbrReject: 80
    of dbrAccept: 90
  else:
    case role
    of dbrHelp: 10
    of dbrReset: 20
    of dbrApply: 30
    of dbrAlternate: 40
    of dbrDestructive: 50
    of dbrAccept: 80
    of dbrReject: 90

func compareDialogButtons(a, b: OrderedDialogButton): int =
  result = cmp(a.spec.role.dialogButtonRank(), b.spec.role.dialogButtonRank())
  if result == 0:
    result = cmp(a.index, b.index)

proc orderedSpecs(buttonBox: DialogButtonBox): seq[DialogButtonSpec] =
  var ordered: seq[OrderedDialogButton]
  for index, spec in buttonBox.xButtonSpecs:
    if not spec.button.isNil:
      ordered.add OrderedDialogButton(index: index, spec: spec)
  ordered.sort(compareDialogButtons)
  for item in ordered:
    result.add item.spec

proc clearArrangedContent(buttonBox: DialogButtonBox) =
  for child in buttonBox.arrangedSubviews():
    child.removeFromSuperview()
  buttonBox.xLeadingSpacer = nil
  buttonBox.xTrailingSpacer = nil

proc addSpacer(buttonBox: DialogButtonBox, target: var View) =
  target = buttonBox.addFlexibleSpacer()

proc rebuildButtons(buttonBox: DialogButtonBox) =
  buttonBox.clearArrangedContent()
  if buttonBox.orientation == laHorizontal and
      buttonBox.xButtonAlignment in {dbaCenter, dbaTrailing}:
    buttonBox.addSpacer(buttonBox.xLeadingSpacer)

  for spec in buttonBox.orderedSpecs():
    buttonBox.addArrangedSubview(spec.button)

  if buttonBox.orientation == laHorizontal and
      buttonBox.xButtonAlignment in {dbaLeading, dbaCenter}:
    buttonBox.addSpacer(buttonBox.xTrailingSpacer)

proc initDialogButtonSpec*(button: Button, role: DialogButtonRole): DialogButtonSpec =
  DialogButtonSpec(role: role, button: button)

proc initDialogButtonSpec*(role: DialogButtonRole): DialogButtonSpec =
  initDialogButtonSpec(newButton(role.standardTitle()), role)

proc initDialogButtonSpec*(title: string, role: DialogButtonRole): DialogButtonSpec =
  initDialogButtonSpec(newButton(title), role)

proc buttonAlignment*(buttonBox: DialogButtonBox): DialogButtonAlignment =
  buttonBox.xButtonAlignment

proc `buttonAlignment=`*(buttonBox: DialogButtonBox, alignment: DialogButtonAlignment) =
  if buttonBox.xButtonAlignment == alignment:
    return
  buttonBox.xButtonAlignment = alignment
  buttonBox.rebuildButtons()

proc dialogButtons*(buttonBox: DialogButtonBox): seq[DialogButtonSpec] =
  buttonBox.xButtonSpecs

proc buttonForRole*(buttonBox: DialogButtonBox, role: DialogButtonRole): Button =
  for spec in buttonBox.xButtonSpecs:
    if spec.role == role:
      return spec.button

proc addButton*(
    buttonBox: DialogButtonBox, button: Button, role: DialogButtonRole
): Button {.discardable.} =
  if button.isNil:
    return nil
  result = button
  buttonBox.xButtonSpecs.add initDialogButtonSpec(button, role)
  buttonBox.rebuildButtons()

proc addButton*(
    buttonBox: DialogButtonBox, title: string, role: DialogButtonRole
): Button {.discardable.} =
  buttonBox.addButton(newButton(title), role)

proc addButton*(
    buttonBox: DialogButtonBox, role: DialogButtonRole
): Button {.discardable.} =
  buttonBox.addButton(role.standardTitle(), role)

proc initDialogButtonBoxFields*(
    buttonBox: DialogButtonBox,
    buttons: openArray[DialogButtonSpec] = [],
    orientation = laHorizontal,
    frame: Rect = AutoRect,
) =
  initStackViewFields(buttonBox, orientation, frame)
  buttonBox.spacing = DefaultDialogButtonSpacing
  buttonBox.alignment = svaCenter
  buttonBox.distribution = svdNatural
  buttonBox.xButtonAlignment = dbaTrailing
  buttonBox.xButtonSpecs = @buttons
  buttonBox.rebuildButtons()

proc newDialogButtonBox*(
    buttons: openArray[DialogButtonSpec] = [],
    orientation = laHorizontal,
    frame: Rect = AutoRect,
): DialogButtonBox =
  result = DialogButtonBox()
  initDialogButtonBoxFields(result, buttons, orientation, frame)
