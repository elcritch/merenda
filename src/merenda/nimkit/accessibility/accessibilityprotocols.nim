import sigils/core
import sigils/selectors

import ../foundation/types
import ../view/viewbase
import ../view/viewgeometry

export types
export viewbase

const
  AccessibilityAttributeRole* = "role"
  AccessibilityAttributeSubrole* = "subrole"
  AccessibilityAttributeLabel* = "label"
  AccessibilityAttributeValue* = "value"
  AccessibilityAttributeHelp* = "help"
  AccessibilityAttributeIdentifier* = "identifier"
  AccessibilityAttributeEnabled* = "enabled"
  AccessibilityAttributeFocused* = "focused"
  AccessibilityAttributeSelected* = "selected"
  AccessibilityAttributeFrame* = "frame"
  AccessibilityAttributeParent* = "parent"
  AccessibilityAttributeChildren* = "children"
  AccessibilityAttributeWindow* = "window"

  AccessibilityActionPress* = "press"
  AccessibilityActionIncrement* = "increment"
  AccessibilityActionDecrement* = "decrement"
  AccessibilityActionShowMenu* = "showMenu"
  AccessibilityActionExpand* = "expand"
  AccessibilityActionCollapse* = "collapse"
  AccessibilityActionDelete* = "delete"

type
  AccessibilityValueKind* = enum
    avNone
    avString
    avBool
    avInt
    avFloat
    avRect
    avView
    avViews

  AccessibilityValue* = object
    case kind*: AccessibilityValueKind
    of avNone:
      discard
    of avString:
      stringValue*: string
    of avBool:
      boolValue*: bool
    of avInt:
      intValue*: int
    of avFloat:
      floatValue*: float32
    of avRect:
      rectValue*: Rect
    of avView:
      viewValue*: View
    of avViews:
      viewValues*: seq[View]

func initAccessibilityValue*(): AccessibilityValue =
  AccessibilityValue(kind: avNone)

func initAccessibilityValue*(value: string): AccessibilityValue =
  AccessibilityValue(kind: avString, stringValue: value)

func initAccessibilityValue*(value: bool): AccessibilityValue =
  AccessibilityValue(kind: avBool, boolValue: value)

func initAccessibilityValue*(value: int): AccessibilityValue =
  AccessibilityValue(kind: avInt, intValue: value)

func initAccessibilityValue*(value: float32): AccessibilityValue =
  AccessibilityValue(kind: avFloat, floatValue: value)

func initAccessibilityValue*(value: Rect): AccessibilityValue =
  AccessibilityValue(kind: avRect, rectValue: value)

func initAccessibilityValue*(value: View): AccessibilityValue =
  AccessibilityValue(kind: avView, viewValue: value)

func initAccessibilityValue*(value: openArray[View]): AccessibilityValue =
  AccessibilityValue(kind: avViews, viewValues: @value)

func accessibilityRoleName*(role: AccessibilityRole): string =
  case role
  of arUnknown: "unknown"
  of arApplication: "application"
  of arWindow: "window"
  of arGroup: "group"
  of arStaticText: "staticText"
  of arButton: "button"
  of arCheckBox: "checkBox"
  of arRadioButton: "radioButton"
  of arTextField: "textField"
  of arList: "list"
  of arListItem: "listItem"
  of arTable: "table"
  of arCell: "cell"
  of arImage: "image"
  of arLink: "link"
  of arMenu: "menu"
  of arMenuItem: "menuItem"
  of arPopupButton: "popupButton"
  of arComboBox: "comboBox"
  of arScrollArea: "scrollArea"
  of arSlider: "slider"
  of arTabGroup: "tabGroup"
  of arTab: "tab"

proc hasHiddenAncestor(view: View): bool =
  var current = view
  while not current.isNil:
    if ssHidden in current.xWidgetStates:
      return true
    current = current.xSuperview

proc accessibilityChildrenForView(view: View): seq[View]

protocol AccessibilityEvents:
  proc accessibilityNotificationPosted*(
    view: View, notification: AccessibilityNotification
  ) {.signal.}

protocol AccessibilityProtocol:
  method accessibilityElement*(): bool {.optional.}
  method setAccessibilityElement*(value: bool) {.optional.}
  method accessibilityIgnored*(): bool {.optional.}
  method setAccessibilityIgnored*(value: bool) {.optional.}
  method accessibilityRole*(): AccessibilityRole {.optional.}
  method setAccessibilityRole*(role: AccessibilityRole) {.optional.}
  method accessibilityLabel*(): string {.optional.}
  method setAccessibilityLabel*(label: string) {.optional.}
  method accessibilityValue*(): string {.optional.}
  method setAccessibilityValue*(value: string) {.optional.}
  method accessibilityHelp*(): string {.optional.}
  method setAccessibilityHelp*(value: string) {.optional.}
  method accessibilityIdentifier*(): string {.optional.}
  method setAccessibilityIdentifier*(value: string) {.optional.}
  method accessibilityTraits*(): AccessibilityTraits {.optional.}
  method setAccessibilityTraits*(traits: AccessibilityTraits) {.optional.}
  method isAccessibilityElement*(): bool {.optional.}
  method isAccessibilityIgnored*(): bool {.optional.}
  method accessibilityFrame*(): Rect {.optional.}
  method accessibilityParent*(): View {.optional.}
  method accessibilityChildren*(): seq[View] {.optional.}
  method accessibilityAttributeNames*(): seq[string] {.optional.}
  method accessibilityAttributeValue*(attribute: string): AccessibilityValue {.optional.}
  method accessibilityIsAttributeSettable*(attribute: string): bool {.optional.}
  method accessibilitySetAttributeValue*(
    attribute: string, value: AccessibilityValue
  ): bool {.optional.}
  method accessibilityActionNames*(): seq[string] {.optional.}
  method accessibilityActionDescription*(action: string): string {.optional.}
  method accessibilityPerformAction*(action: string): bool {.optional.}

protocol DefaultAccessibilityProtocol of AccessibilityProtocol:
  method accessibilityElement(view: View): bool =
    view.xAccessibilityElement or view.xHasAccessibilityRole or
      view.xAccessibilityLabel.len > 0 or view.xAccessibilityValue.len > 0

  method setAccessibilityElement(view: View, value: bool) =
    if not view.isNil:
      view.xAccessibilityElement = value

  method accessibilityIgnored(view: View): bool =
    view.isNil or view.xAccessibilityIgnored or view.hasHiddenAncestor()

  method setAccessibilityIgnored(view: View, value: bool) =
    if not view.isNil:
      view.xAccessibilityIgnored = value

  method accessibilityRole(view: View): AccessibilityRole =
    if view.xHasAccessibilityRole: view.xAccessibilityRole else: arGroup

  method setAccessibilityRole(view: View, role: AccessibilityRole) =
    if view.isNil:
      return
    view.xAccessibilityRole = role
    view.xHasAccessibilityRole = true
    view.xAccessibilityElement = role != arGroup

  method accessibilityLabel(view: View): string =
    if view.xAccessibilityLabel.len > 0:
      view.xAccessibilityLabel
    else:
      view.xIdentifier

  method setAccessibilityLabel(view: View, label: string) =
    if not view.isNil:
      view.xAccessibilityLabel = label
      view.xAccessibilityElement = true

  method accessibilityValue(view: View): string =
    view.xAccessibilityValue

  method setAccessibilityValue(view: View, value: string) =
    if view.isNil or view.xAccessibilityValue == value:
      return
    view.xAccessibilityValue = value
    view.xAccessibilityElement = true
    emit view.accessibilityNotificationPosted(anValueChanged)

  method accessibilityHelp(view: View): string =
    if view.xAccessibilityHelp.len > 0:
      view.xAccessibilityHelp
    else:
      view.xToolTip

  method setAccessibilityHelp(view: View, value: string) =
    if not view.isNil:
      view.xAccessibilityHelp = value

  method accessibilityIdentifier(view: View): string =
    if view.xAccessibilityIdentifier.len > 0:
      view.xAccessibilityIdentifier
    else:
      view.xIdentifier

  method setAccessibilityIdentifier(view: View, value: string) =
    if not view.isNil:
      view.xAccessibilityIdentifier = value

  method accessibilityTraits(view: View): AccessibilityTraits =
    result = view.xAccessibilityTraits
    if ssDisabled in view.xWidgetStates:
      result.incl atDisabled
    if ssFocused in view.xWidgetStates:
      result.incl atFocused
    if ssSelected in view.xWidgetStates:
      result.incl atSelected

  method setAccessibilityTraits(view: View, traits: AccessibilityTraits) =
    if not view.isNil:
      view.xAccessibilityTraits = traits

  method isAccessibilityElement*(view: View): bool =
    view.accessibilityElement()

  method isAccessibilityIgnored*(view: View): bool =
    view.accessibilityIgnored()

  method accessibilityFrame*(view: View): Rect =
    if view.isNil: initRect(0, 0, 0, 0) else: view.rectToWindow(view.xBounds)

  method accessibilityParent*(view: View): View =
    if view.isNil: nil else: view.xSuperview

  method accessibilityChildren*(view: View): seq[View] =
    view.accessibilityChildrenForView()

  method accessibilityAttributeNames*(view: View): seq[string] =
    result = @[
      AccessibilityAttributeRole,
      AccessibilityAttributeLabel,
      AccessibilityAttributeValue,
      AccessibilityAttributeHelp,
      AccessibilityAttributeIdentifier,
      AccessibilityAttributeEnabled,
      AccessibilityAttributeFocused,
      AccessibilityAttributeSelected,
      AccessibilityAttributeFrame,
      AccessibilityAttributeParent,
      AccessibilityAttributeChildren,
      AccessibilityAttributeWindow,
    ]

  method accessibilityAttributeValue*(
      view: View, attribute: string
  ): AccessibilityValue =
    case attribute
    of AccessibilityAttributeRole:
      initAccessibilityValue(view.accessibilityRole().accessibilityRoleName())
    of AccessibilityAttributeLabel:
      initAccessibilityValue(view.accessibilityLabel())
    of AccessibilityAttributeValue:
      initAccessibilityValue(view.accessibilityValue())
    of AccessibilityAttributeHelp:
      initAccessibilityValue(view.accessibilityHelp())
    of AccessibilityAttributeIdentifier:
      initAccessibilityValue(view.accessibilityIdentifier())
    of AccessibilityAttributeEnabled:
      initAccessibilityValue(ssDisabled notin view.xWidgetStates)
    of AccessibilityAttributeFocused:
      initAccessibilityValue(ssFocused in view.xWidgetStates)
    of AccessibilityAttributeSelected:
      initAccessibilityValue(ssSelected in view.xWidgetStates)
    of AccessibilityAttributeFrame:
      initAccessibilityValue(view.accessibilityFrame())
    of AccessibilityAttributeParent:
      initAccessibilityValue(view.accessibilityParent())
    of AccessibilityAttributeChildren:
      initAccessibilityValue(view.accessibilityChildren())
    else:
      initAccessibilityValue()

  method accessibilityIsAttributeSettable*(view: View, attribute: string): bool =
    attribute == AccessibilityAttributeLabel or
      attribute == AccessibilityAttributeValue or
      attribute == AccessibilityAttributeHelp or
      attribute == AccessibilityAttributeIdentifier

  method accessibilitySetAttributeValue*(
      view: View, attribute: string, value: AccessibilityValue
  ): bool =
    if value.kind != avString:
      return false
    case attribute
    of AccessibilityAttributeLabel:
      view.accessibilityLabel = value.stringValue
      true
    of AccessibilityAttributeValue:
      view.accessibilityValue = value.stringValue
      true
    of AccessibilityAttributeHelp:
      view.accessibilityHelp = value.stringValue
      true
    of AccessibilityAttributeIdentifier:
      view.accessibilityIdentifier = value.stringValue
      true
    else:
      false

  method accessibilityActionNames*(view: View): seq[string] =
    @[]

  method accessibilityActionDescription*(view: View, action: string): string =
    case action
    of AccessibilityActionPress: "press"
    of AccessibilityActionIncrement: "increment"
    of AccessibilityActionDecrement: "decrement"
    of AccessibilityActionShowMenu: "show menu"
    of AccessibilityActionExpand: "expand"
    of AccessibilityActionCollapse: "collapse"
    of AccessibilityActionDelete: "delete"
    else: action

  method accessibilityPerformAction*(view: View, action: string): bool =
    false

proc accessibilityChildrenForView(view: View): seq[View] =
  if view.isNil:
    return
  for child in view.xSubviews:
    if child.isAccessibilityIgnored():
      continue
    if child.isAccessibilityElement():
      result.add child
    else:
      result.add child.accessibilityChildren()

proc postAccessibilityNotification*(
    view: View, notification: AccessibilityNotification
) =
  if not view.isNil:
    emit view.accessibilityNotificationPosted(notification)

proc `accessibilityElement=`*(view: View, value: bool) =
  view.setAccessibilityElement(value)

proc `accessibilityIgnored=`*(view: View, value: bool) =
  view.setAccessibilityIgnored(value)

proc `accessibilityRole=`*(view: View, role: AccessibilityRole) =
  view.setAccessibilityRole(role)

proc `accessibilityLabel=`*(view: View, label: string) =
  view.setAccessibilityLabel(label)

proc `accessibilityValue=`*(view: View, value: string) =
  view.setAccessibilityValue(value)

proc `accessibilityHelp=`*(view: View, value: string) =
  view.setAccessibilityHelp(value)

proc `accessibilityIdentifier=`*(view: View, value: string) =
  view.setAccessibilityIdentifier(value)

proc `accessibilityTraits=`*(view: View, traits: AccessibilityTraits) =
  view.setAccessibilityTraits(traits)

export DefaultAccessibilityProtocol
