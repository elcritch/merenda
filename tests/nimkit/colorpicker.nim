import std/[strutils, unittest]

import figdraw

import merenda/nimkit
import ./fixtures/[rendergeometry, widgetflows]

suite "NimKit color picker":
  test "picker descendants stay above the popup panel":
    let
      well = newColorWell(color(0.20, 0.48, 0.92, 1.0))
      picker = newColorPicker(well, rect(0, 0, 300, 340))
      renders = buildRenders(picker)

    require PopupDrawLevel in renders.layers
    for item in picker.items():
      check item.label in renders[PopupDrawLevel].renderedText()
      check item.label notin renders[DefaultDrawLevel].renderedText()
    check picker.okayButton().title in renders[PopupDrawLevel].renderedText()

  test "color wells expose a drawn color value and popup accessibility":
    let
      selected = color(0.20, 0.48, 0.92, 1.0)
      well = newColorWell(selected, frame = rect(0, 0, 72, 30))
      root = newView(frame = rect(0, 0, 100, 50))
    root.addSubview(well)

    check well.color() == selected
    check well.colorDescription() == "#337AEAFF"
    check well.intrinsicContentSize().width > 0
    check well.intrinsicContentSize().height > 0
    check well.accessibilityRole() == arPopupButton
    check well.accessibilityValue() == well.selectedTitle()
    check AccessibilityActionShowMenu in well.accessibilityActionNames()

    var
      hasSelectedColor = false
      hasRoundedTransparencyMask = false
    for node in buildRenders(root)[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle:
        if node.fill == fill(selected):
          hasSelectedColor = true
        if NfClipContent in node.flags and node.corners[dcTopLeft] > 0'u16:
          hasRoundedTransparencyMask = true
    check hasSelectedColor
    check hasRoundedTransparencyMask

  test "tabbed picker sends palette wheel and CSS colors back to its source well":
    let
      choices =
        @[
          initColorWellChoice("Coral", color(0.92, 0.34, 0.28, 1.0)),
          initColorWellChoice("Ocean", color(0.12, 0.48, 0.78, 1.0)),
        ]
      well = newColorWell(choices, choices[0].color, rect(10, 10, 72, 30))
      root = newView(frame = rect(0, 0, 480, 440))
      window = newWindow("Color Well", frame = rect(0, 0, 480, 440))
      action = actionSelector("testColorPickerAction")
    defer:
      window.close()
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
    well.popupPresentation = ppWindow

    check well.popupPresentation == ppWindow
    check well.effectivePopupPresentation == ppInline

    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseUpAt(initPoint(20, 20))
    check well.popupOpen()
    let
      popupWindow = well.popupWindow()
      picker = well.picker()
    check popupWindow.isNil
    check not picker.isNil
    check picker.superview() == root
    check PopupDrawLevel in window.buildRenders().layers
    check window.hasActiveTransientSession()
    check window.transientWindow().isNil

    check well.activateColorAtIndex(1)
    check well.color() == choices[1].color
    check well.selectedTitle() == "Ocean"
    check actionCount == 1
    check well.popupOpen()

    require window.clickTab(picker, "wheel")
    picker.layoutSubtreeIfNeeded()
    let
      wheelView = picker.selectedTabViewItem().view()
      wheelPoint = wheelView.pointToWindow(
        initPoint(
          wheelView.bounds().size.width * 0.5'f32,
          wheelView.bounds().size.height * 0.5'f32,
        )
      )
      paletteColor = well.color()
    check window.mouseDownAt(wheelPoint)
    check window.mouseUpAt(wheelPoint)
    check well.color() != paletteColor
    check actionCount == 2
    check well.popupOpen()

    require window.clickTab(picker, "values")
    let cssField = picker.cssColorField()
    require window.replaceText(cssField, "tomato")
    require window.pressKey(keyEnter)
    check well.color() == parseHtmlColor("tomato")
    check actionCount == 3

    let cssColor = well.color()
    require window.replaceText(cssField, "definitely-not-a-color")
    require window.pressKey(keyEnter)
    check well.color() == cssColor
    check cssField.stringValue() == "definitely-not-a-color"
    check actionCount == 3

    require window.replaceText(cssField, "rgba(25, 50, 75, 0.5)")
    require window.pressKey(keyEnter)
    check well.color() == parseHtmlColor("rgba(25, 50, 75, 0.5)")
    check actionCount == 4

    let redSlider = picker.rgbaSlider(0)
    redSlider.value = 0.75'f32
    check redSlider.sendAction()
    check well.color().r == 0.75'f32
    check actionCount == 5

    require window.clickView(picker.okayButton())
    check not well.popupOpen()
    check well.popupWindow().isNil
    check picker.superview().isNil
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
      customDescription = well.accessibilityValue()
    check well.color() == custom
    check well.selectedIndex() == -1
    require well.choices().len > 0
    let choice = well.choices()[0]
    require well.activateColorAtIndex(0)
    check well.color() == choice.color
    check well.accessibilityValue() == choice.title
    well.color = custom
    check well.selectedIndex() == -1
    check well.color() == custom
    check well.accessibilityValue() == customDescription
