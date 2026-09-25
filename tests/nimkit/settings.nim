import std/[importutils, math, os, strutils, tables, unittest]

import merenda/nimkit
import ./fixtures/widgetflows
import merenda/nimkit/app/settings
from figdraw/extras/systemfonttypes import initSystemTypeface

privateAccess(MerendaSettingsWindow)

type
  TestFontPickerController =
    typeof(default(MerendaSettingsWindow).fontPickerController[])
  TestSelectedFont = typeof(default(MerendaSettingsWindow).previewFonts[frUI])

privateAccess(TestFontPickerController)
privateAccess(TestSelectedFont)

type TestSystemTypeface = typeof(default(TestSelectedFont).faces.regular)

suite "nimkit settings":
  test "choosing a visible theme applies it without depending on menu order":
    var
      appliedAppearance: Appearance
      appliedTheme: string
    let settings = newMerendaSettingsWindow(
      appearanceHandler = proc(appearance: Appearance) =
        appliedAppearance = appearance,
      themeHandler = proc(theme: string) =
        appliedTheme = theme,
      initialTheme = "aqua",
    )
    defer:
      settings.window().close()
    settings.window().setContentView(settings.contentView())
    let themeView = settings.contentView().viewWithIdentifier("settings-theme-picker")
    require themeView of ComboBox
    let picker = ComboBox(themeView)
    check picker.stringValue == "Aqua"
    check not appliedAppearance.theme.isInitialized
    require settings.window().chooseItem(picker, "DarkBSD")
    check appliedTheme == "darkbsd"
    check appliedAppearance.theme.isInitialized
    require settings.window().chooseItem(picker, "Aqua")
    check appliedTheme == "aqua"

  test "behavior controls apply toggles and silent updates stay silent":
    var applied: seq[bool]
    let settings = newMerendaSettingsWindow(
      invertScrollingHandler = proc(inverted: bool) =
        applied.add inverted
    )
    defer:
      settings.window().close()
    settings.window().setContentView(settings.contentView())
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require tabsView of TabView
    require settings.window().clickTab(TabView(tabsView), SettingsBehaviorTabIdentifier)
    let invertView =
      settings.contentView().viewWithIdentifier(SettingsInvertScrollingIdentifier)
    require invertView of Button
    let invertButton = Button(invertView)

    require settings.window().clickView(invertButton)
    check settings.invertScrolling
    check applied == @[true]
    require settings.window().clickView(invertButton)
    check not settings.invertScrolling
    check applied == @[true, false]

    settings.invertScrolling = true
    check invertButton.state == bsOn
    check applied == @[true, false]

  test "appearance settings scale the UI in tenths":
    var appliedScale = 0.0'f32
    let settings = newMerendaSettingsWindow(
      initialUiScale = 1.0'f32,
      uiScaleHandler = proc(scale: float32) =
        appliedScale = scale,
    )
    defer:
      settings.window().close()
    settings.window().setContentView(settings.contentView())
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    let tabs = TabView(tabsView)
    require settings.window().clickTab(tabs, "appearance")

    let scaleView = settings.contentView().viewWithIdentifier(SettingsUiScaleIdentifier)
    require not scaleView.isNil
    require scaleView of Stepper
    let scaleStepper = Stepper(scaleView)
    check scaleStepper.value == 1.0'f32
    check scaleStepper.formattedValue() == "1.0x"

    require settings.window().makeFirstResponder(scaleStepper)
    require settings.window().pressKey(keyArrowUp)
    check abs(scaleStepper.value - 1.1'f32) < 0.0001'f32
    check abs(appliedScale - 1.1'f32) < 0.0001'f32
    check settings.uiScale == scaleStepper.value

    require settings.window().pressKey(keyArrowDown)
    check abs(scaleStepper.value - 1.0'f32) < 0.0001'f32
    check abs(appliedScale - 1.0'f32) < 0.0001'f32

  test "settings save committed values and reset to the saved baseline":
    var
      appliedAppearance: Appearance
      appliedInvertScrolling = false
      appliedScale = 1.0'f32
      savedSettings: MerendaSettings
      saveCount = 0
    let settings = newMerendaSettingsWindow(
      appearanceHandler = proc(appearance: Appearance) =
        appliedAppearance = appearance,
      invertScrollingHandler = proc(inverted: bool) =
        appliedInvertScrolling = inverted,
      initialUiScale = 1.0'f32,
      uiScaleHandler = proc(scale: float32) =
        appliedScale = scale,
      initialTheme = "darkbsd",
      saveDefaultsHandler = proc(values: MerendaSettings): bool =
        savedSettings = values
        inc saveCount
        true,
    )
    defer:
      settings.window().close()
    settings.window().setContentView(settings.contentView())

    let
      themeView = settings.contentView().viewWithIdentifier("settings-theme-picker")
      tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require themeView of ComboBox
    require tabsView of TabView
    let tabs = TabView(tabsView)
    require settings.window().clickTab(tabs, "typography")
    let
      fontSizeView =
        settings.contentView().viewWithIdentifier("settings-font-size-stepper")
      applyFontView = settings.contentView().viewWithIdentifier("settings-apply-font")
    require fontSizeView of Stepper
    require applyFontView of Button
    require settings.window().clickTab(tabs, "appearance")
    let scaleView = settings.contentView().viewWithIdentifier(SettingsUiScaleIdentifier)
    require scaleView of Stepper
    require settings.window().clickTab(tabs, SettingsBehaviorTabIdentifier)
    let
      invertView =
        settings.contentView().viewWithIdentifier(SettingsInvertScrollingIdentifier)
      saveView =
        settings.contentView().viewWithIdentifier(SettingsSaveDefaultsIdentifier)
      resetView = settings.contentView().viewWithIdentifier(SettingsResetIdentifier)
      autoSaveView =
        settings.contentView().viewWithIdentifier(SettingsAutoSaveDefaultsIdentifier)
    require invertView of Button
    require saveView of Button
    require resetView of Button
    require autoSaveView of Button
    let
      themePicker = ComboBox(themeView)
      invertButton = Button(invertView)
      scaleStepper = Stepper(scaleView)
      fontSizeStepper = Stepper(fontSizeView)
      applyFontButton = Button(applyFontView)
      saveButton = Button(saveView)
      resetButton = Button(resetView)
      autoSaveButton = Button(autoSaveView)

    let window = settings.window()
    require window.clickTab(tabs, "appearance")
    require window.chooseItem(themePicker, "Aqua")
    require window.makeFirstResponder(scaleStepper)
    require window.pressKey(keyArrowUp)
    let savedScale = scaleStepper.value
    require window.clickTab(tabs, SettingsBehaviorTabIdentifier)
    require window.clickView(invertButton)
    require window.clickView(saveButton)
    check saveCount == 1
    check savedSettings.theme == "aqua"
    check savedSettings.invertScrolling
    check savedSettings.uiScale == savedScale
    check appliedInvertScrolling
    check appliedScale == savedScale

    require window.clickTab(tabs, "typography")
    require window.makeFirstResponder(fontSizeStepper)
    require window.pressKey(keyArrowUp)
    require window.clickView(applyFontButton)
    let savedFontSize = fontSizeStepper.value
    require window.clickTab(tabs, SettingsBehaviorTabIdentifier)
    require window.clickView(saveButton)
    check saveCount == 2

    require window.clickTab(tabs, "typography")
    require window.makeFirstResponder(fontSizeStepper)
    require window.pressKey(keyArrowUp)
    check fontSizeStepper.value > savedFontSize
    require window.clickTab(tabs, "appearance")
    require window.chooseItem(themePicker, "DarkBSD")
    require window.makeFirstResponder(scaleStepper)
    require window.pressKey(keyArrowDown)
    require window.clickTab(tabs, SettingsBehaviorTabIdentifier)
    require window.clickView(invertButton)
    require window.clickView(resetButton)
    check themePicker.stringValue == "Aqua"
    check invertButton.state == bsOn
    check scaleStepper.value == savedScale
    check fontSizeStepper.value == savedFontSize
    check appliedAppearance.resolveLength(
      controlStyle(srTextField), StyleFontSize, 0.0'f32
    ) == savedFontSize
    check appliedInvertScrolling
    check appliedScale == savedScale
    check saveCount == 2

    require window.clickView(autoSaveButton)
    check savedSettings.autoSaveDefaults
    check saveCount == 3
    require window.clickTab(tabs, "appearance")
    require window.makeFirstResponder(scaleStepper)
    require window.pressKey(keyArrowUp)
    check saveCount == 4
    check savedSettings.uiScale == scaleStepper.value
    check savedSettings.uiScale > savedScale

  test "application UI scale reaches existing and new windows":
    let
      app = newApplication("UI Scale Test")
      firstWindow = newWindow("First")
      secondWindow = newWindow("Second")
    app.addWindow(firstWindow)
    app.uiScale = 1.2'f32
    check app.uiScale == 1.2'f32
    check firstWindow.uiScale == 1.2'f32

    app.addWindow(secondWindow)
    check secondWindow.uiScale == 1.2'f32

    app.showMerendaSettings()
    let settingsWindow = app.windows[^1]
    let tabsView = settingsWindow.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    require settingsWindow.clickTab(TabView(tabsView), "appearance")
    let scaleView =
      settingsWindow.contentView().viewWithIdentifier(SettingsUiScaleIdentifier)
    require not scaleView.isNil
    require scaleView of Stepper
    let scaleStepper = Stepper(scaleView)
    check abs(scaleStepper.value - 1.2'f32) < 0.0001'f32
    check scaleStepper.incrementValue()
    check abs(app.uiScale - 1.3'f32) < 0.0001'f32
    check abs(firstWindow.uiScale - 1.3'f32) < 0.0001'f32
    check abs(secondWindow.uiScale - 1.3'f32) < 0.0001'f32

    settingsWindow.close()
    firstWindow.close()
    secondWindow.close()

  test "application scrolling preference reaches existing and new windows":
    let
      app = newApplication("Scrolling Preference Test")
      firstWindow = newWindow("First")
      secondWindow = newWindow("Second")
    app.addWindow(firstWindow)
    check not app.invertScrolling
    check not firstWindow.invertScrolling

    app.invertScrolling = true
    check app.invertScrolling
    check firstWindow.invertScrolling

    app.addWindow(secondWindow)
    check secondWindow.invertScrolling

    app.showMerendaSettings()
    let settingsWindow = app.windows[^1]
    let settingsTabsView =
      settingsWindow.contentView().viewWithIdentifier("settings-tabs")
    require not settingsTabsView.isNil
    require settingsTabsView of TabView
    require settingsWindow.clickTab(
      TabView(settingsTabsView), SettingsBehaviorTabIdentifier
    )
    let invertView =
      settingsWindow.contentView().viewWithIdentifier(SettingsInvertScrollingIdentifier)
    require not invertView.isNil
    require invertView of Button
    let invertButton = Button(invertView)
    check invertButton.state == bsOn
    require settingsWindow.clickView(invertButton)
    check not app.invertScrolling
    check not firstWindow.invertScrolling
    check not secondWindow.invertScrolling

    settingsWindow.close()
    firstWindow.close()
    secondWindow.close()

  test "application settings reset remembers defaults across panel reopenings":
    var savedCount = 0
    let app = newApplication("Settings Default Baseline Test")
    app.merendaSettingsThemeIdentifier = "darkbsd"
    app.merendaSettingsSaveHandler = proc(values: MerendaSettings): bool =
      discard values
      inc savedCount
      true
    app.showMerendaSettings()
    let firstPanel = app.windows[^1]
    let firstThemeView =
      firstPanel.contentView().viewWithIdentifier("settings-theme-picker")
    require firstThemeView of ComboBox
    let firstThemePicker = ComboBox(firstThemeView)
    require firstPanel.chooseItem(firstThemePicker, "Aqua")
    firstPanel.close()

    app.showMerendaSettings()
    let secondPanel = app.windows[^1]
    defer:
      secondPanel.close()
    let
      secondThemeView =
        secondPanel.contentView().viewWithIdentifier("settings-theme-picker")
      secondResetView =
        secondPanel.contentView().viewWithIdentifier(SettingsResetIdentifier)
    require secondThemeView of ComboBox
    require secondResetView of Button
    let
      secondThemePicker = ComboBox(secondThemeView)
      resetButton = Button(secondResetView)
    check secondThemePicker.stringValue == "Aqua"
    require secondPanel.clickView(resetButton)
    check secondThemePicker.stringValue == "DarkBSD"
    check app.merendaSettingsThemeIdentifier == "darkbsd"
    check savedCount == 0

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
      onlyMonospaceFontsView =
        settings.contentView().viewWithIdentifier("settings-only-monospace-fonts")
      onlyDisplayableFontsView =
        settings.contentView().viewWithIdentifier("settings-only-displayable-fonts")

    require not interfaceView.isNil
    require interfaceView of Button
    require not monospaceView.isNil
    require monospaceView of Button
    require not onlyMonospaceFontsView.isNil
    require onlyMonospaceFontsView of Button
    require not onlyDisplayableFontsView.isNil
    require onlyDisplayableFontsView of Button
    let
      interfaceButton = Button(interfaceView)
      monospaceButton = Button(monospaceView)
      onlyMonospaceFonts = Button(onlyMonospaceFontsView)
      onlyDisplayableFonts = Button(onlyDisplayableFontsView)
    check interfaceButton.title == "Default"
    check interfaceButton.state == bsOn
    check monospaceButton.title == "Default"
    check monospaceButton.state == bsOff
    check onlyMonospaceFonts.title == "Show monospace fonts"
    check onlyMonospaceFonts.state == bsOff
    check onlyDisplayableFonts.title == "Only displayable fonts"
    check onlyDisplayableFonts.state == bsOff

    check monospaceButton.sendAction()
    check interfaceButton.state == bsOff
    check monospaceButton.state == bsOn
    check onlyMonospaceFonts.title == "Only monospace fonts"
    check onlyMonospaceFonts.state == bsOn

    check interfaceButton.sendAction()
    check interfaceButton.state == bsOn
    check monospaceButton.state == bsOff
    check onlyMonospaceFonts.title == "Show monospace fonts"
    check onlyMonospaceFonts.state == bsOff

  test "monospace filtering hides and restores an exact proportional face":
    var appliedAppearance: Appearance
    let settings = newMerendaSettingsWindow(
      proc(appearance: Appearance) =
        appliedAppearance = appearance
    )
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    let
      fontPickerView = settings.contentView().viewWithIdentifier("settings-font-picker")
      onlyMonospaceFontsView =
        settings.contentView().viewWithIdentifier("settings-only-monospace-fonts")
      onlyDisplayableFontsView =
        settings.contentView().viewWithIdentifier("settings-only-displayable-fonts")
      applyFontView = settings.contentView().viewWithIdentifier("settings-apply-font")

    require not fontPickerView.isNil
    require fontPickerView of CascadingView
    require not onlyMonospaceFontsView.isNil
    require onlyMonospaceFontsView of Button
    require not onlyDisplayableFontsView.isNil
    require onlyDisplayableFontsView of Button
    require not applyFontView.isNil
    require applyFontView of Button
    settings.window().close()
    let
      fontPicker = CascadingView(fontPickerView)
      onlyMonospaceFonts = Button(onlyMonospaceFontsView)
      onlyDisplayableFonts = Button(onlyDisplayableFontsView)
      applyFont = Button(applyFontView)
      languageIdentifier = "system-font-language:english"
      familyIdentifier = languageIdentifier & ":family:test-font-family"
      proportionalFaceIdentifier = languageIdentifier & ":face:test-proportional"
      proportionalFile = TestSystemTypeface(
        file: typeof(default(TestSystemTypeface).file)(
          path: "/fonts/TestCollection.ttc", faceIndex: 3
        ),
        variations:
          @[
            typeof(default(TestSystemTypeface).variations[0])(
              tag: "wght", value: 650.0'f32
            )
          ],
      )
      proportionalFont = TestSelectedFont(
        name: "Test Proportional", faces: FontFaceSet(regular: proportionalFile)
      )
    var
      proportionalFace = initFontCatalogFace(
        "Regular",
        "English",
        proportionalFile,
        identifier = "test-proportional",
        fontName = proportionalFont.name,
      )
      monospaceFace = initFontCatalogFace(
        "Regular",
        "English",
        "/fonts/TestMono.ttf",
        identifier = "test-monospace",
        fontName = "Test Monospace",
      )
      unavailableFace = initFontCatalogFace(
        "Regular",
        "English",
        "/fonts/TestUnavailable.ttf",
        identifier = "test-unavailable",
        fontName = "Test Unavailable Mono",
      )
    proportionalFace.metadataLoaded = true
    proportionalFace.supportsPreviewText = true
    monospaceFace.metadataLoaded = true
    monospaceFace.supportsPreviewText = true
    unavailableFace.metadataLoaded = true
    settings.fontPickerController.catalogEntries =
      @[
        initFontCatalogEntry(
          "Test Fonts",
          proportionalFile.file.path,
          identifier = "test-font-family",
          faces = [proportionalFace, monospaceFace, unavailableFace],
        )
      ]

    onlyMonospaceFonts.state = bsOn
    check onlyMonospaceFonts.sendAction()
    check settings.fontPickerController.faces.hasKey(
      languageIdentifier & ":face:test-monospace"
    )
    check settings.fontPickerController.faces.hasKey(proportionalFaceIdentifier)
    check settings.fontPickerController.faces.hasKey(
      languageIdentifier & ":face:test-unavailable"
    )
    onlyDisplayableFonts.state = bsOn
    check onlyDisplayableFonts.sendAction()
    check not settings.fontPickerController.faces.hasKey(
      languageIdentifier & ":face:test-unavailable"
    )
    onlyDisplayableFonts.state = bsOff
    check onlyDisplayableFonts.sendAction()
    check settings.fontPickerController.faces.hasKey(
      languageIdentifier & ":face:test-unavailable"
    )
    onlyMonospaceFonts.state = bsOff
    check onlyMonospaceFonts.sendAction()
    check not settings.fontPickerController.faces.hasKey(
      languageIdentifier & ":face:test-monospace"
    )
    check settings.fontPickerController.faces.hasKey(proportionalFaceIdentifier)
    check settings.fontRoleButtons[frMonospace].sendAction()
    onlyMonospaceFonts.state = bsOff
    check onlyMonospaceFonts.sendAction()
    settings.fontPickerController.desiredSelectedFont = proportionalFont
    settings.previewFonts[frMonospace] = proportionalFont
    fontPicker.selectedPath =
      [languageIdentifier, familyIdentifier, proportionalFaceIdentifier]
    check fontPicker.selectedPath[^1] == proportionalFaceIdentifier

    onlyMonospaceFonts.state = bsOn
    check onlyMonospaceFonts.sendAction()
    check fontPicker.selectedPath.len == 0
    check settings.previewFonts[frMonospace].name == proportionalFont.name
    check settings.previewFonts[frMonospace].faces.regular == proportionalFile

    check applyFont.sendAction()
    check appliedAppearance.fontName(frMonospace) == proportionalFont.name
    check appliedAppearance.fontFace(frMonospace) == proportionalFile

    onlyMonospaceFonts.state = bsOff
    check onlyMonospaceFonts.sendAction()
    check fontPicker.selectedPath[^1] == proportionalFaceIdentifier

  test "JetBrains Mono names survive the default font filters":
    let settings = newMerendaSettingsWindow()
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    let
      monospaceFontView =
        settings.contentView().viewWithIdentifier("settings-monospace-font-button")
      onlyMonospaceFontsView =
        settings.contentView().viewWithIdentifier("settings-only-monospace-fonts")
      onlyDisplayableFontsView =
        settings.contentView().viewWithIdentifier("settings-only-displayable-fonts")
    require not monospaceFontView.isNil
    require monospaceFontView of Button
    require not onlyMonospaceFontsView.isNil
    require onlyMonospaceFontsView of Button
    require not onlyDisplayableFontsView.isNil
    require onlyDisplayableFontsView of Button
    settings.window().close()
    let
      monospaceFont = Button(monospaceFontView)
      onlyMonospaceFonts = Button(onlyMonospaceFontsView)
      onlyDisplayableFonts = Button(onlyDisplayableFontsView)
      languageIdentifier = "system-font-language:default"
      faceIdentifier = languageIdentifier & ":face:jetbrains-mono-regular"
    var jetBrainsFace = initFontCatalogFace(
      "Regular",
      DefaultFontLanguage,
      "/fonts/JetBrainsMono-Regular.ttf",
      identifier = "jetbrains-mono-regular",
      fontName = "JetBrainsMono-Regular",
    )
    jetBrainsFace.metadataLoaded = true
    settings.fontPickerController.catalogEntries =
      @[
        initFontCatalogEntry(
          "JetBrains Mono",
          jetBrainsFace.path,
          identifier = "jetbrains-mono",
          faces = [jetBrainsFace],
        )
      ]

    check monospaceFont.sendAction()
    check onlyMonospaceFonts.state == bsOn
    check onlyDisplayableFonts.state == bsOff
    check settings.fontPickerController.faces.hasKey(faceIdentifier)

    onlyDisplayableFonts.state = bsOn
    check onlyDisplayableFonts.sendAction()
    check not settings.fontPickerController.faces.hasKey(faceIdentifier)

  test "background font reloads preserve the browsed family position":
    let settings = newMerendaSettingsWindow()
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    let fontPickerView =
      settings.contentView().viewWithIdentifier("settings-font-picker")
    require not fontPickerView.isNil
    require fontPickerView of CascadingView
    settings.window().close()
    let
      fontPicker = CascadingView(fontPickerView)
      languageIdentifier = DefaultFontLanguage.toLowerAscii()
      firstFamilyIdentifier =
        "system-font-language:" & languageIdentifier & ":family:test-family-00"
    var entries: seq[FontCatalogEntry]
    for index in 0 ..< 24:
      let suffix = align($index, 2, '0')
      entries.add initFontCatalogEntry(
        "Test Family " & suffix,
        "/fonts/TestFamily" & suffix & ".ttf",
        identifier = "test-family-" & suffix,
        faces = [
          initFontCatalogFace(
            "Regular",
            DefaultFontLanguage,
            "/fonts/TestFamily" & suffix & ".ttf",
            identifier = "test-face-" & suffix,
            fontName = "Test Family " & suffix,
          )
        ],
      )
    settings.fontPickerController.catalogEntries = entries
    settings.fontPickerController.rebuildFontPickerItemsForTests()
    fontPicker.frame = rect(0, 0, 360, 120)
    fontPicker.reloadData()
    fontPicker.selectedPath =
      @["system-font-language:" & languageIdentifier, firstFamilyIdentifier]
    discard buildRenders(fontPicker)
    let familyColumn = fontPicker.tableViewForColumn(1)
    familyColumn.scrollRows(10)
    let browsedOffset = familyColumn.scrollView().contentOffset()
    check browsedOffset.y > 0.0'f32

    settings.fontPickerController.needsFontPickerReload = true
    settings.fontPickerController.reloadFontPickerIfVisibleForTests()

    check familyColumn.scrollView().contentOffset() == browsedOffset

  test "font size keyboard edits preview before Apply commits them":
    var
      appliedCount = 0
      appliedAppearance: Appearance
    let settings = newMerendaSettingsWindow(
      proc(appearance: Appearance) =
        inc appliedCount
        appliedAppearance = appearance
    )
    defer:
      settings.window().close()
    let window = settings.window()
    window.setContentView(settings.contentView())
    let initialAppliedCount = appliedCount
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require tabsView of TabView
    require window.clickTab(TabView(tabsView), "typography")
    let
      fontSizeView =
        settings.contentView().viewWithIdentifier("settings-font-size-stepper")
      preview = settings.contentView().viewWithIdentifier("settings-font-preview")
      applyButton = settings.contentView().viewWithIdentifier("settings-apply-font")
    require fontSizeView of Stepper
    require not preview.isNil
    require applyButton of Button
    let
      stepper = Stepper(fontSizeView)
      original = stepper.value
      originalHeight = preview.intrinsicContentSize().height
    require window.makeFirstResponder(stepper)
    require window.pressKey(keyArrowUp)
    check stepper.value > original
    check appliedCount == initialAppliedCount
    let context = controlStyle(
      srTextField, id = "settings-font-preview", classes = @[LabelStyleClass]
    )
    check preview.effectiveAppearance().resolveLength(context, StyleFontSize, 0) ==
      stepper.value
    check preview.intrinsicContentSize().height >= originalHeight
    require window.clickView(applyButton)
    check appliedCount == initialAppliedCount + 1
    check appliedAppearance.resolveLength(controlStyle(srTextField), StyleFontSize, 0) ==
      stepper.value

  test "changing themes preserves editable font preview controls":
    let settings = newMerendaSettingsWindow()
    defer:
      settings.window().close()
    let window = settings.window()
    window.setContentView(settings.contentView())
    let
      themeView = settings.contentView().viewWithIdentifier("settings-theme-picker")
      tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require themeView of ComboBox
    require tabsView of TabView
    let tabs = TabView(tabsView)
    require window.clickTab(tabs, "typography")
    let
      fontSizeView =
        settings.contentView().viewWithIdentifier("settings-font-size-stepper")
      preview = settings.contentView().viewWithIdentifier("settings-font-preview")
    require fontSizeView of Stepper
    require not preview.isNil
    let
      stepper = Stepper(fontSizeView)
      context = controlStyle(
        srTextField, id = "settings-font-preview", classes = @[LabelStyleClass]
      )
    for theme in ["DarkBSD", "macOS", "macOS Dark"]:
      checkpoint("theme: " & theme)
      require window.clickTab(tabs, "appearance")
      require window.chooseItem(ComboBox(themeView), theme)
      require window.clickTab(tabs, "typography")
      let before = stepper.value
      require window.makeFirstResponder(stepper)
      require window.pressKey(keyArrowUp)
      check stepper.value > before
      check preview.effectiveAppearance().resolveLength(context, StyleFontSize, 0) ==
        stepper.value

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

    check fontSizeStepper.value == defaultFontSize()
    check fontPicker.selectedPath.len == 2
    check fontPicker.selectedPath[^1] == DefaultSystemFontIdentifier

  test "bundled exact fonts can be replaced with system defaults":
    let
      interfaceFace = TestSystemTypeface(
        file: typeof(default(TestSystemTypeface).file)(
          path: currentSourcePath().parentDir / "../../data/Ubuntu.ttf"
        )
      )
      monospaceFace = TestSystemTypeface(
        file: typeof(default(TestSystemTypeface).file)(
          path: currentSourcePath().parentDir / "../../data/Ubuntu.ttf"
        )
      )
    var
      initialAppearance = initAppearance()
      builder = initThemeBuilder(initialAppearance.theme)
      appliedAppearance: Appearance
    builder.setFontName(frUI, "Bundled Interface")
    builder.setFontFace(frUI, interfaceFace)
    builder.setFontName(frMonospace, "Bundled Monospace")
    builder.setFontFace(frMonospace, monospaceFace)
    initialAppearance.theme = builder.finish()

    let settings = newMerendaSettingsWindow(
      proc(appearance: Appearance) =
        appliedAppearance = appearance,
      initialAppearance = initialAppearance,
    )
    defer:
      settings.window().close()
    check settings.appliedFonts[frUI].name == "Bundled Interface"
    check settings.appliedFonts[frUI].faces.regular == interfaceFace
    check settings.appliedFonts[frMonospace].name == "Bundled Monospace"
    check settings.appliedFonts[frMonospace].faces.regular == monospaceFace
    check not appliedAppearance.theme.isInitialized

    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require not tabsView.isNil
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    settings.fontPickerController.selectionHandler(TestSelectedFont())
    let applyFontView = settings.contentView().viewWithIdentifier("settings-apply-font")
    require not applyFontView.isNil
    require applyFontView of Button
    check Button(applyFontView).sendAction()
    check appliedAppearance.fontName(frUI) == defaultFontName(frUI)
    check appliedAppearance.fontFace(frUI).file.path.len == 0

  test "applying typography preserves a caller-provided theme":
    let preservedColor = color(0.13, 0.37, 0.71, 1.0)
    var
      themeBuilder = initThemeBuilder(initDarkBSDTheme())
      appliedAppearance: Appearance
    themeBuilder["settings.test.preserved"] = styleColor(preservedColor)
    let initialAppearance = initAppearance(themeBuilder.finish())
    let settings = newMerendaSettingsWindow(
      proc(appearance: Appearance) =
        appliedAppearance = appearance,
      initialAppearance = initialAppearance,
    )
    defer:
      settings.window().close()
    let tabsView = settings.contentView().viewWithIdentifier("settings-tabs")
    require tabsView of TabView
    check TabView(tabsView).selectTabViewItemAtIndex(1)
    let applyFontView = settings.contentView().viewWithIdentifier("settings-apply-font")
    require not applyFontView.isNil
    require applyFontView of Button

    check Button(applyFontView).sendAction()
    check appliedAppearance.colorToken("settings.test.preserved", color(0.0, 0.0, 0.0)) ==
      preservedColor

  test "supplemental families restore exact styled face selections":
    let
      regular = initSystemTypeface("/cache/IBM-Plex-Sans-Regular.ttf")
      italic = initSystemTypeface("/cache/IBM-Plex-Sans-Italic.ttf")
      bold = initSystemTypeface("/cache/IBM-Plex-Sans-Bold.ttf")
      regularFace = initFontCatalogFace(
        "Regular",
        DefaultFontLanguage,
        regular,
        identifier = "bundled-regular",
        fontName = "IBM Plex Sans",
      )
      italicFace = initFontCatalogFace(
        "Italic",
        DefaultFontLanguage,
        italic,
        identifier = "bundled-italic",
        fontName = "IBM Plex Sans",
      )
      boldFace = initFontCatalogFace(
        "Bold",
        DefaultFontLanguage,
        bold,
        identifier = "bundled-bold",
        fontName = "IBM Plex Sans",
      )
      entry = initFontCatalogEntry(
        "IBM Plex Sans",
        regular.file.path,
        identifier = "bundled-ibm-plex-sans",
        faces = [regularFace, italicFace, boldFace],
      )
    var
      initialAppearance = initAppearance()
      builder = initThemeBuilder(initialAppearance.theme)
    builder.setFontName(frUI, "IBM Plex Sans")
    builder.setFontFaces(
      frUI, FontFaceSet(regular: regular, italic: italic, bold: bold)
    )
    initialAppearance.theme = builder.finish()
    let settings = newMerendaSettingsWindow(
      initialAppearance = initialAppearance, supplementalFonts = [entry]
    )
    defer:
      settings.window().close()

    check settings.fontPickerController.desiredSelectedFont.faces.regular == regular
    let familyIdentifier = "system-font-language:default:family:bundled-ibm-plex-sans"
    let regularIdentifier = "system-font-language:default:face:bundled-regular"
    require regularIdentifier in settings.fontPickerController.faces
    settings.fontPickerController.didSelectCascadingItem(
      settings.fontPickerController.fontPicker, 2, 0, regularIdentifier
    )
    check settings.previewFonts[frUI].faces.regular == regular
    check settings.previewFonts[frUI].faces.italic == italic
    check settings.previewFonts[frUI].faces.bold == bold
    check familyIdentifier in settings.fontPickerController.items
