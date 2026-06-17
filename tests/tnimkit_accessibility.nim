import std/unittest

import sigils/core

import merenda/nimkit

type AccessibilitySpy = ref object of Agent
  notifications: seq[AccessibilityNotification]

proc rememberAccessibilityNotification(
    spy: AccessibilitySpy, notification: AccessibilityNotification
) {.slot.} =
  spy.notifications.add notification

suite "nimkit accessibility":
  test "views expose explicit accessibility metadata and attributes":
    let view = newView(frame = initRect(10, 20, 80, 24))

    check not view.isAccessibilityElement()

    view.accessibilityRole = arGroup
    view.accessibilityLabel = "Container"
    view.accessibilityHelp = "Contains controls"
    view.accessibilityIdentifier = "main.container"

    check view.isAccessibilityElement()
    check view.accessibilityRole() == arGroup
    check view.accessibilityLabel() == "Container"
    check view.accessibilityHelp() == "Contains controls"
    check view.accessibilityIdentifier() == "main.container"

    let labelValue = view.accessibilityAttributeValue(AccessibilityAttributeLabel)
    check labelValue.kind == avString
    check labelValue.stringValue == "Container"

    let frameValue = view.accessibilityAttributeValue(AccessibilityAttributeFrame)
    check frameValue.kind == avRect
    check frameValue.rectValue == initRect(10, 20, 80, 24)

  test "accessibility children flatten non-element containers":
    let
      root = newView(frame = initRect(0, 0, 200, 120))
      group = newView(frame = initRect(10, 10, 180, 80))
      button = newButton("Apply", frame = initRect(4, 4, 80, 28))

    group.addSubview(button)
    root.addSubview(group)

    check root.accessibilityChildren() == @[View(button)]

    group.accessibilityLabel = "Group"
    check root.accessibilityChildren() == @[group]
    check group.accessibilityChildren() == @[View(button)]

  test "buttons provide role label value traits and press action":
    var actionCount = 0
    let
      button = newCheckBox("Enabled", frame = initRect(0, 0, 120, 24))
      action = actionSelector("accessibilityPress")

    proc onPress(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    button.target = newActionTarget(action, onPress)
    button.action = action

    check button.isAccessibilityElement()
    check button.accessibilityRole() == arCheckBox
    check button.accessibilityLabel() == "Enabled"
    check button.accessibilityValue() == "off"
    check button.accessibilityActionNames() == @[AccessibilityActionPress]

    check button.accessibilityPerformAction(AccessibilityActionPress)
    check button.accessibilityValue() == "on"
    check atSelected in button.accessibilityTraits()
    check actionCount == 1

  test "text fields and labels expose text semantics":
    let
      field = newTextField("abc", frame = initRect(0, 0, 120, 24))
      label = newHeadingLabel("Title")

    field.identifier = "name"

    check field.accessibilityRole() == arTextField
    check field.accessibilityLabel() == "name"
    check field.accessibilityValue() == "abc"
    check atEditable in field.accessibilityTraits()
    check atSelectable in field.accessibilityTraits()

    check label.accessibilityRole() == arStaticText
    check label.accessibilityLabel() == "Title"
    check label.accessibilityValue() == ""
    check atHeader in label.accessibilityTraits()

  test "accessibility value changes emit notifications":
    let
      view = newView()
      spy = AccessibilitySpy()

    view.connect(
      accessibilityNotificationPosted, spy, rememberAccessibilityNotification
    )

    view.accessibilityValue = "ready"
    check spy.notifications == @[anValueChanged]
