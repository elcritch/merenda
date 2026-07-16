import std/unittest

import merenda/nimkit
import merenda/nimkit/app/settings

suite "nimkit settings":
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
