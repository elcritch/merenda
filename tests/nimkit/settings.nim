import std/unittest

import merenda/nimkit
import merenda/nimkit/app/settings

suite "nimkit settings":
  test "typography settings expose independent interface and monospace fonts":
    let settings = newMerendaSettingsWindow()
    defer:
      settings.window().close()
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    let
      interfaceView =
        settings.contentView().viewWithIdentifier("settings-ui-font-button")
      monospaceView =
        settings.contentView().viewWithIdentifier("settings-monospace-font-button")

    require not interfaceView.isNil
    require interfaceView of Button
    require not monospaceView.isNil
    require monospaceView of Button
    let
      interfaceButton = Button(interfaceView)
      monospaceButton = Button(monospaceView)
    check interfaceButton.title == "Default"
    check interfaceButton.state == bsOn
    check monospaceButton.title == "Default"
    check monospaceButton.state == bsOff

    check monospaceButton.sendAction()
    check interfaceButton.state == bsOff
    check monospaceButton.state == bsOn

    check interfaceButton.sendAction()
    check interfaceButton.state == bsOn
    check monospaceButton.state == bsOff

  test "font size stepper previews within bounds and applies on request":
    var appliedCount = 0
    var appliedAppearance: Appearance
    let settings = newMerendaSettingsWindow(
      proc(appearance: Appearance) =
        inc appliedCount
        appliedAppearance = appearance
    )
    defer:
      settings.window().close()
    let initialAppliedCount = appliedCount
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    let fontSizeView =
      settings.contentView().viewWithIdentifier("settings-font-size-stepper")

    require not fontSizeView.isNil
    require fontSizeView of Stepper
    let fontSizeStepper = Stepper(fontSizeView)
    check fontSizeStepper.minValue == 6.0'f32
    check fontSizeStepper.maxValue == 120.0'f32
    check fontSizeStepper.value == 14.0'f32
    check fontSizeStepper.increment == 1.0'f32

    check fontSizeStepper.incrementValue()
    check fontSizeStepper.value == 15.0'f32
    check appliedCount == initialAppliedCount

    let previewView = settings.contentView().viewWithIdentifier("settings-font-preview")
    require not previewView.isNil
    check previewView.appearance.resolveLength(
      controlStyle(srTextField), StyleFontSize, 0.0'f32
    ) == 15.0'f32

    let applyFontView = settings.contentView().viewWithIdentifier("settings-apply-font")
    require not applyFontView.isNil
    require applyFontView of Button
    check Button(applyFontView).sendAction()
    check appliedCount == initialAppliedCount + 1
    check appliedAppearance.resolveLength(
      controlStyle(srTextField), StyleFontSize, 0.0'f32
    ) == 15.0'f32

  test "macOS themes apply font size to the preview label":
    let settings = newMerendaSettingsWindow()
    defer:
      settings.window().close()
    let
      themeView = settings.contentView().viewWithIdentifier("settings-theme-picker")
      tabsView = settings.contentView().viewWithIdentifier("settings-tabs")

    require not themeView.isNil
    require themeView of ComboBox
    require not tabsView.isNil
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    let
      fontSizeView =
        settings.contentView().viewWithIdentifier("settings-font-size-stepper")
      previewView = settings.contentView().viewWithIdentifier("settings-font-preview")
    require not fontSizeView.isNil
    require fontSizeView of Stepper
    require not previewView.isNil
    let
      themePicker = ComboBox(themeView)
      fontSizeStepper = Stepper(fontSizeView)
      previewContext = controlStyle(
        srTextField, id = "settings-font-preview", classes = @[LabelStyleClass]
      )

    for themeIndex in [1, 2]:
      themePicker.selectedIndex = themeIndex
      check themePicker.sendAction()
      fontSizeStepper.value = 14.0'f32
      check fontSizeStepper.incrementValue()
      check previewView.appearance.resolveLength(previewContext, StyleFontSize, 0.0'f32) ==
        15.0'f32

  test "opening settings restores applied font controls":
    let app = newApplication("Settings Reset Test")
    app.showMerendaSettings()
    let settingsPanel = app.windows[0]
    defer:
      settingsPanel.close()
    let tabsView = settingsPanel.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    let
      fontPickerView =
        settingsPanel.contentView().viewWithIdentifier("settings-font-picker")
      fontSizeView =
        settingsPanel.contentView().viewWithIdentifier("settings-font-size-stepper")

    require not fontPickerView.isNil
    require fontPickerView of CascadingView
    require not fontSizeView.isNil
    require fontSizeView of Stepper
    let
      fontPicker = CascadingView(fontPickerView)
      fontSizeStepper = Stepper(fontSizeView)
    check fontSizeStepper.incrementValue()
    fontPicker.selectedPath = []
    check fontPicker.selectedPath.len == 0

    app.showMerendaSettings()

    check fontSizeStepper.value == 14.0'f32
    check fontPicker.selectedPath.len == 2
    check fontPicker.selectedPath[^1] == DefaultSystemFontIdentifier
