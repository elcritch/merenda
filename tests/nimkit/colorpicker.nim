import std/unittest

import figdraw

import merenda/nimkit

suite "NimKit color picker":
  test "color wells expose a drawn color value and popup accessibility":
    let
      selected = color(0.20, 0.48, 0.92, 1.0)
      well = newColorWell(selected, frame = rect(0, 0, 72, 30))
      root = newView(frame = rect(0, 0, 100, 50))
    root.addSubview(well)

    check well.color() == selected
    check well.selectedTitle() == "Blue"
    check well.colorDescription() == "#337AEAFF"
    check well.intrinsicContentSize() == initIntrinsicSize(72, 30)
    check well.accessibilityRole() == arPopupButton
    check well.accessibilityValue() == "Blue"
    check AccessibilityActionShowMenu in well.accessibilityActionNames()

    var
      rectangleCount = 0
      hasRoundedTransparencyMask = false
    for node in buildRenders(root)[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle:
        inc rectangleCount
        if NfClipContent in node.flags and node.corners[dcTopLeft] > 0'u16:
          hasRoundedTransparencyMask = true
    check rectangleCount >= 4
    check hasRoundedTransparencyMask

  test "tabbed picker sends palette wheel and CSS colors back to its source well":
    let
      choices =
        @[
          initColorWellChoice("Coral", color(0.92, 0.34, 0.28, 1.0)),
          initColorWellChoice("Ocean", color(0.12, 0.48, 0.78, 1.0)),
        ]
      well = newColorWell(choices, choices[0].color, rect(10, 10, 72, 30))
      root = newView(frame = rect(0, 0, 180, 100))
      window = newWindow("Color Well", frame = rect(0, 0, 180, 100))
      action = actionSelector("testColorPickerAction")
    var actionCount = 0
    well.target = newActionTarget(
      action,
      proc(sender: DynamicAgent) =
        check sender == DynamicAgent(well)
        inc actionCount
      ,
    )
    well.action = action
    root.addSubview(well)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseUpAt(initPoint(20, 20))
    check well.popupOpen()
    let
      popupWindow = well.popupWindow()
      picker = well.picker()
    check not popupWindow.isNil
    check not picker.isNil
    check popupWindow.contentView() == View(picker)
    check picker.len == 3
    check picker[0].label() == "Palette"
    check picker[1].label() == "Wheel"
    check picker[2].label() == "Values"
    check picker.okayButton().title() == "OK"
    check window.hasActiveTransientSession()
    check window.transientWindow() == popupWindow

    check well.activateColorAtIndex(1)
    check well.color() == choices[1].color
    check well.selectedTitle() == "Ocean"
    check actionCount == 1
    check well.popupOpen()

    check picker.selectTabViewItemAtIndex(1)
    picker.layoutSubtreeIfNeeded()
    let
      wheelView = picker[1].view()
      wheelPoint = wheelView.pointToWindow(
        initPoint(
          wheelView.bounds().size.width * 0.5'f32,
          wheelView.bounds().size.height * 0.5'f32,
        )
      )
      paletteColor = well.color()
    check popupWindow.mouseDownAt(wheelPoint)
    check popupWindow.mouseUpAt(wheelPoint)
    check well.color() != paletteColor
    check actionCount == 2
    check well.popupOpen()

    check picker.selectTabViewItemAtIndex(2)
    let cssField = picker.cssColorField()
    cssField.stringValue = "tomato"
    check cssField.sendAction()
    check well.color() == parseHtmlColor("tomato")
    check actionCount == 3

    let cssColor = well.color()
    cssField.stringValue = "definitely-not-a-color"
    check cssField.sendAction()
    check well.color() == cssColor
    check cssField.stringValue() == "definitely-not-a-color"
    check actionCount == 3

    cssField.stringValue = "rgba(25, 50, 75, 0.5)"
    check cssField.sendAction()
    check well.color() == parseHtmlColor("rgba(25, 50, 75, 0.5)")
    check actionCount == 4

    let redSlider = picker.rgbaSlider(0)
    redSlider.value = 0.75'f32
    check redSlider.sendAction()
    check well.color().r == 0.75'f32
    check actionCount == 5

    check picker.okayButton().sendAction()
    check not well.popupOpen()
    check well.popupWindow().isNil
    check popupWindow.isClosed()
    check not window.hasActiveTransientSession()

  test "popup color choices update selection state and send actions":
    let
      choices =
        @[
          initPopupColorChoice("Red", color(0.9, 0.2, 0.2, 1.0)),
          initPopupColorChoice("Blue", color(0.2, 0.4, 0.9, 1.0)),
        ]
      well = newPopupColorWell(choices, choices[0].color)
      action = actionSelector("testColorWellAction")
    var actionCount = 0
    well.target = newActionTarget(
      action,
      proc(sender: DynamicAgent) =
        check sender == DynamicAgent(well)
        inc actionCount
      ,
    )
    well.action = action

    check well.selectedIndex() == 0
    check well.menu().items()[0].state() == bsOn
    check well.menu().items()[1].state() == bsOff
    check well.activateColorAtIndex(1)
    check well.color() == choices[1].color
    check well.selectedIndex() == 1
    check well.menu().items()[0].state() == bsOff
    check well.menu().items()[1].state() == bsOn
    check actionCount == 1
    check well.menu().items()[0].perform(Responder(well))
    check well.color() == choices[0].color
    check actionCount == 2

  test "default palette retains custom colors":
    let
      custom = color(0.13, 0.27, 0.41, 0.73)
      well = newPopupColorWell(custom)
    check well.color() == custom
    check well.selectedIndex() == -1
    check well.choices().len == 20
