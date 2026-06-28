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
  AccessibilityAttributeNumberOfCharacters* = "numberOfCharacters"
  AccessibilityAttributeSelectedTextRange* = "selectedTextRange"
  AccessibilityAttributeInsertionPoint* = "insertionPoint"

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
    avTextRange

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
    of avTextRange:
      textRangeValue*: AccessibilityTextRange

  AccessibilityValidationResult* = object
    errors*: seq[string]

  AccessibilityTextRange* = object
    location*: Natural
    length*: Natural

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

func initAccessibilityTextRange*(location, length: int): AccessibilityTextRange =
  AccessibilityTextRange(
    location: max(location, 0).Natural, length: max(length, 0).Natural
  )

func maxIndex*(range: AccessibilityTextRange): int =
  int(range.location) + int(range.length)

func isEmpty*(range: AccessibilityTextRange): bool =
  range.length == 0

func initAccessibilityValue*(value: AccessibilityTextRange): AccessibilityValue =
  AccessibilityValue(kind: avTextRange, textRangeValue: value)

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
  method accessibilityAttributeValue*(
    attribute: string
  ): AccessibilityValue {.optional.}

  method accessibilityIsAttributeSettable*(attribute: string): bool {.optional.}
  method accessibilitySetAttributeValue*(
    attribute: string, value: AccessibilityValue
  ): bool {.optional.}

  method accessibilityTextLength*(): int {.optional.}
  method accessibilitySelectedTextRange*(): AccessibilityTextRange {.optional.}
  method setAccessibilitySelectedTextRange*(
    range: AccessibilityTextRange
  ): bool {.optional.}

  method accessibilityInsertionPoint*(): int {.optional.}
  method setAccessibilityInsertionPoint*(index: int): bool {.optional.}
  method accessibilityBoundsForTextRange*(
    range: AccessibilityTextRange
  ): seq[Rect] {.optional.}

  method accessibilityBoundsForCharacter*(index: int): Rect {.optional.}
  method accessibilityCharacterIndexAtPoint*(point: Point): int {.optional.}
  method accessibilityLineRange*(line: int): AccessibilityTextRange {.optional.}
  method accessibilityLineForCharacter*(index: int): int {.optional.}
  method accessibilityBoundsForLine*(line: int): Rect {.optional.}

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
    if view.xAccessibilityLabel.len > 0: view.xAccessibilityLabel else: view.xIdentifier

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
    if view.xAccessibilityHelp.len > 0: view.xAccessibilityHelp else: view.xToolTip

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
    if view.isNil:
      initRect(0, 0, 0, 0)
    else:
      view.rectToWindow(view.xBounds)

  method accessibilityParent*(view: View): View =
    if view.isNil: nil else: view.xSuperview

  method accessibilityChildren*(view: View): seq[View] =
    view.accessibilityChildrenForView()

  method accessibilityAttributeNames*(view: View): seq[string] =
    result =
      @[
        AccessibilityAttributeRole, AccessibilityAttributeLabel,
        AccessibilityAttributeValue, AccessibilityAttributeHelp,
        AccessibilityAttributeIdentifier, AccessibilityAttributeEnabled,
        AccessibilityAttributeFocused, AccessibilityAttributeSelected,
        AccessibilityAttributeFrame, AccessibilityAttributeParent,
        AccessibilityAttributeChildren, AccessibilityAttributeWindow,
      ]
    if view.accessibilityRole() in {arTextField, arTextArea, arStaticText}:
      result.add AccessibilityAttributeNumberOfCharacters
      result.add AccessibilityAttributeSelectedTextRange
      result.add AccessibilityAttributeInsertionPoint

  method accessibilityAttributeValue*(
      view: View, attribute: string
  ): AccessibilityValue =
    case attribute
    of AccessibilityAttributeRole:
      initAccessibilityValue($view.accessibilityRole())
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
    of AccessibilityAttributeNumberOfCharacters:
      initAccessibilityValue(view.accessibilityTextLength())
    of AccessibilityAttributeSelectedTextRange:
      initAccessibilityValue(view.accessibilitySelectedTextRange())
    of AccessibilityAttributeInsertionPoint:
      initAccessibilityValue(view.accessibilityInsertionPoint())
    else:
      initAccessibilityValue()

  method accessibilityIsAttributeSettable*(view: View, attribute: string): bool =
    if attribute == AccessibilityAttributeLabel or
        attribute == AccessibilityAttributeValue or
        attribute == AccessibilityAttributeHelp or
        attribute == AccessibilityAttributeIdentifier:
      return true
    if attribute == AccessibilityAttributeSelectedTextRange or
        attribute == AccessibilityAttributeInsertionPoint:
      let traits = view.accessibilityTraits()
      return atEditable in traits or atSelectable in traits
    false

  method accessibilitySetAttributeValue*(
      view: View, attribute: string, value: AccessibilityValue
  ): bool =
    case attribute
    of AccessibilityAttributeLabel:
      if value.kind != avString:
        return false
      view.accessibilityLabel = value.stringValue
      true
    of AccessibilityAttributeValue:
      if value.kind != avString:
        return false
      view.accessibilityValue = value.stringValue
      true
    of AccessibilityAttributeHelp:
      if value.kind != avString:
        return false
      view.accessibilityHelp = value.stringValue
      true
    of AccessibilityAttributeIdentifier:
      if value.kind != avString:
        return false
      view.accessibilityIdentifier = value.stringValue
      true
    of AccessibilityAttributeSelectedTextRange:
      if value.kind != avTextRange:
        return false
      view.setAccessibilitySelectedTextRange(value.textRangeValue)
    of AccessibilityAttributeInsertionPoint:
      if value.kind != avInt:
        return false
      view.setAccessibilityInsertionPoint(value.intValue)
    else:
      false

  method accessibilityTextLength*(view: View): int =
    0

  method accessibilitySelectedTextRange*(view: View): AccessibilityTextRange =
    initAccessibilityTextRange(0, 0)

  method setAccessibilitySelectedTextRange*(
      view: View, range: AccessibilityTextRange
  ): bool =
    false

  method accessibilityInsertionPoint*(view: View): int =
    0

  method setAccessibilityInsertionPoint*(view: View, index: int): bool =
    false

  method accessibilityBoundsForTextRange*(
      view: View, range: AccessibilityTextRange
  ): seq[Rect] =
    @[]

  method accessibilityBoundsForCharacter*(view: View, index: int): Rect =
    initRect(0, 0, 0, 0)

  method accessibilityCharacterIndexAtPoint*(view: View, point: Point): int =
    -1

  method accessibilityLineRange*(view: View, line: int): AccessibilityTextRange =
    initAccessibilityTextRange(0, 0)

  method accessibilityLineForCharacter*(view: View, index: int): int =
    -1

  method accessibilityBoundsForLine*(view: View, line: int): Rect =
    initRect(0, 0, 0, 0)

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

proc addValidationError(
    validation: var AccessibilityValidationResult, view: View, message: string
) =
  if view.isNil:
    validation.errors.add "<nil>: " & message
    return
  let identifier = view.accessibilityIdentifier()
  if identifier.len > 0:
    validation.errors.add identifier & ": " & message
  else:
    validation.errors.add $view.accessibilityRole() & ": " & message

func passed*(validation: AccessibilityValidationResult): bool =
  validation.errors.len == 0

proc accessibilityHasRole*(view: View, role: AccessibilityRole): bool =
  not view.isNil and view.accessibilityRole() == role

proc accessibilityHasRole*(view: View, roles: openArray[AccessibilityRole]): bool =
  if view.isNil:
    return false
  let role = view.accessibilityRole()
  for expected in roles:
    if role == expected:
      return true

proc accessibilitySupportsAction*(view: View, action: string): bool =
  if view.isNil or action.len == 0:
    return false
  for available in view.accessibilityActionNames():
    if available == action:
      return true

proc validateAccessibilityElement*(view: View): AccessibilityValidationResult =
  if view.isNil:
    result.addValidationError(view, "missing accessibility element")
    return
  if view.isAccessibilityIgnored():
    result.addValidationError(view, "accessibility element is ignored")
    return
  if not view.isAccessibilityElement():
    result.addValidationError(view, "view is not an accessibility element")
  if view.accessibilityRole() == arUnknown:
    result.addValidationError(view, "accessibility role is unknown")
  var seenActions: seq[string]
  for action in view.accessibilityActionNames():
    if action.len == 0:
      result.addValidationError(view, "accessibility action is empty")
      continue
    for seen in seenActions:
      if seen == action:
        result.addValidationError(view, "duplicate accessibility action: " & action)
    seenActions.add action

proc validateAccessibilityRole*(
    view: View, expected: AccessibilityRole
): AccessibilityValidationResult =
  if view.isNil:
    result.addValidationError(view, "missing accessibility element")
    return
  result = view.validateAccessibilityElement()
  if view.accessibilityRole() != expected:
    result.addValidationError(
      view,
      "expected accessibility role " & $expected & ", got " & $view.accessibilityRole(),
    )

proc validateAccessibilityRole*(
    view: View, expected: openArray[AccessibilityRole]
): AccessibilityValidationResult =
  if view.isNil:
    result.addValidationError(view, "missing accessibility element")
    return
  result = view.validateAccessibilityElement()
  if not view.accessibilityHasRole(expected):
    var message = "expected one of accessibility roles"
    for role in expected:
      message.add " " & $role
    message.add ", got " & $view.accessibilityRole()
    result.addValidationError(view, message)

proc validateAccessibilityActions*(
    view: View, requiredActions: openArray[string]
): AccessibilityValidationResult =
  if view.isNil:
    result.addValidationError(view, "missing accessibility element")
    return
  result = view.validateAccessibilityElement()
  for action in requiredActions:
    if not view.accessibilitySupportsAction(action):
      result.addValidationError(view, "missing accessibility action: " & action)

proc addOrderedAccessibilityElements(
    result: var seq[View], view: View, includeSelf: bool
) =
  if view.isNil or view.isAccessibilityIgnored():
    return
  if includeSelf and view.isAccessibilityElement():
    result.add view
  for child in view.accessibilityChildren():
    result.addOrderedAccessibilityElements(child, includeSelf = true)

proc orderedAccessibilityElements*(view: View, includeRoot = false): seq[View] =
  result.addOrderedAccessibilityElements(view, includeRoot)

proc orderedAccessibilityDescendants*(view: View): seq[View] =
  view.orderedAccessibilityElements(includeRoot = false)

iterator accessibilityDescendants*(view: View): View =
  for element in view.orderedAccessibilityDescendants():
    yield element

proc validateAccessibilityTree*(view: View): AccessibilityValidationResult =
  for element in view.orderedAccessibilityElements(includeRoot = true):
    let validation = element.validateAccessibilityElement()
    result.errors.add validation.errors

proc accessibilityElementAtPoint*(view: View, point: Point): View =
  if view.isNil or view.isAccessibilityIgnored():
    return nil
  let children = view.accessibilityChildren()
  for index in countdown(children.high, 0):
    let hit = children[index].accessibilityElementAtPoint(point)
    if not hit.isNil:
      return hit
  if view.isAccessibilityElement() and view.accessibilityFrame().contains(point):
    return view

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
