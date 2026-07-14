import merenda/nimkit

import std/[options, os, strutils, tables]
import sigils/selectors

when defined(settingsDemoBenchmark):
  import std/[monotimes, times]

  let settingsDemoStartedAt = getMonoTime()

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw

type
  DemoTheme = enum
    dtDefault
    dtMacOS
    dtNebula
    dtPeachy
    dtSynthwave83

  DemoFontSize = enum
    dfs12
    dfs14
    dfs16
    dfs18
    dfs20

  FontSelectionProc = proc(path: string) {.closure.}

  FontPickerController = ref object of Responder
    items: Table[string, CascadingItem]
    childIdentifiers: Table[string, seq[string]]
    childIndexes: Table[string, Table[string, int]]
    selectionHandler: FontSelectionProc

proc addFontPickerItem(controller: FontPickerController, item: CascadingItem) =
  controller.items[item.identifier] = item
  controller.childIdentifiers.mgetOrPut(item.parentIdentifier, @[]).add item.identifier

func fontPickerLanguageIdentifier(language: string): string =
  "system-font-language:" & language.toLowerAscii()

func fontPickerFamilyIdentifier(languageIdentifier, familyIdentifier: string): string =
  languageIdentifier & ":family:" & familyIdentifier

func fontPickerFaceTitle(style: string): string =
  if style.toLowerAscii() == "regular": "Normal" else: style

proc addFontPickerLanguage(controller: FontPickerController, language: string): string =
  result = language.fontPickerLanguageIdentifier()
  if result notin controller.items:
    controller.addFontPickerItem(cascadeItem(result, language))

protocol FontPickerDataSource of CascadingDataSource:
  method cascadingNumberOfChildren(
      controller: FontPickerController, view: CascadingView, parentIdentifier: string
  ): int =
    discard view
    controller.childIdentifiers.getOrDefault(parentIdentifier).len

  method cascadingChildIdentifier(
      controller: FontPickerController,
      view: CascadingView,
      parentIdentifier: string,
      index: int,
  ): string =
    discard view
    let children = controller.childIdentifiers.getOrDefault(parentIdentifier)
    if index in 0 ..< children.len:
      children[index]
    else:
      ""

  method cascadingItem(
      controller: FontPickerController, view: CascadingView, identifier: string
  ): CascadingItem =
    discard view
    controller.items.getOrDefault(identifier)

  method indexOfCascadingChildIdentifier(
      controller: FontPickerController,
      view: CascadingView,
      parentIdentifier: string,
      identifier: string,
  ): int =
    discard view
    if parentIdentifier in controller.childIndexes:
      controller.childIndexes[parentIdentifier].getOrDefault(identifier, -1)
    else:
      -1

protocol FontPickerDelegate of CascadingDelegate:
  method didSelectCascadingItem(
      controller: FontPickerController,
      view: CascadingView,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard column
    discard row
    let item = view.cascadingItemWithIdentifier(identifier)
    if not item.leaf or controller.selectionHandler.isNil:
      return
    let path = item.objectValue.getString()
    if path.isSome:
      controller.selectionHandler(path.get())

proc newFontPickerController(): FontPickerController =
  result = FontPickerController(
    items: initTable[string, CascadingItem](),
    childIdentifiers: initTable[string, seq[string]](),
    childIndexes: initTable[string, Table[string, int]](),
  )
  let defaultLanguageIdentifier = result.addFontPickerLanguage(DefaultFontLanguage)
  result.addFontPickerItem(
    cascadeItem(
      DefaultSystemFontIdentifier,
      "System Default",
      parentIdentifier = defaultLanguageIdentifier,
      leaf = true,
      objectValue = toObj(""),
    )
  )
  for entry in systemFontCatalog():
    for face in entry.faces:
      let
        languageIdentifier = result.addFontPickerLanguage(face.language)
        familyIdentifier =
          languageIdentifier.fontPickerFamilyIdentifier(entry.identifier)
      if familyIdentifier notin result.items:
        result.addFontPickerItem(
          cascadeItem(
            familyIdentifier, entry.family, parentIdentifier = languageIdentifier
          )
        )
      result.addFontPickerItem(
        cascadeItem(
          face.identifier,
          face.style.fontPickerFaceTitle(),
          parentIdentifier = familyIdentifier,
          leaf = true,
          objectValue = toObj(face.path),
        )
      )
  for parentIdentifier, identifiers in result.childIdentifiers:
    var indexes = initTable[string, int]()
    for index, identifier in identifiers:
      indexes[identifier] = index
    result.childIndexes[parentIdentifier] = indexes
  initResponder(result)
  discard result.withProtocol(FontPickerDataSource)
  discard result.withProtocol(FontPickerDelegate)

const TextStyleRoles = [
  srBox, srButton, srCheckBox, srRadioButton, srTextField, srTextView, srMonoTextView,
  srComboBox, srComboBoxItem, srTab, srTableHeaderCell, srRowItem, srCascadingRowItem,
]

func title(theme: DemoTheme): string =
  case theme
  of dtDefault: "Default"
  of dtMacOS: "macOS"
  of dtNebula: "Nebula"
  of dtPeachy: "Peachy"
  of dtSynthwave83: "Synthwave '83"

func title(size: DemoFontSize): string =
  case size
  of dfs12: "12 pt"
  of dfs14: "14 pt"
  of dfs16: "16 pt"
  of dfs18: "18 pt"
  of dfs20: "20 pt"

proc fontTitle(path: string): string =
  if path.len == 0:
    "Default"
  else:
    path.extractFilename()

func pointSize(size: DemoFontSize): float32 =
  case size
  of dfs12: 12.0'f32
  of dfs14: 14.0'f32
  of dfs16: 16.0'f32
  of dfs18: 18.0'f32
  of dfs20: 20.0'f32

proc appearanceFor(
    theme: DemoTheme, fontPath: string, fontSize: DemoFontSize
): Appearance =
  case theme
  of dtDefault:
    result = initAppearance(initTheme())
  of dtMacOS:
    result = initAppearance(initMacOSTheme())
  of dtNebula:
    result = initAppearance(initNebulaTheme())
  of dtPeachy:
    result = initAppearance(initPeachyTheme())
  of dtSynthwave83:
    result = initAppearance(initSynthwave83Theme())

  for role in TextStyleRoles:
    result.theme[role, StyleFontName] = styleKeyword(
      if fontPath.len > 0:
        fontPath
      else:
        defaultFontName()
    )
    result.theme[role, StyleFontSize] = fontSize.pointSize()

proc newSettingsPage(): tuple[view: View, stack: StackView] =
  result.view = newView()
  result.stack = newStackView(laVertical)
  result.stack.spacing = 12.0
  result.stack.alignment = svaFill
  result.view.addSubview(result.stack)
  discard result.stack.pinEdges(
    toGuide = result.view.contentLayoutGuide(insets(18.0, 20.0)),
    edges = {leLeft, leTop, leRight, leBottom},
  )

let
  app = sharedApplication()
  panel = newPanel("Merenda Settings", frame = rect(180, 160, 520, 350))
  root = newView()
  layout = newStackView(laVertical)
  tabs = newTabView()
  appearancePage = newSettingsPage()
  typographyPage = newSettingsPage()
  appearanceForm = newFormView()
  typographyForm = newFormView()
  titleLabel = newTitleLabel("Merenda Settings")
  status = newStatusLabel()
  themeLabel = newFormLabel("Theme")
  fontLabel = newFormLabel("Font")
  fontSizeLabel = newFormLabel("Size")
  fontPickerController =
    when defined(settingsDemoBenchmark):
      block:
        let startedAt = getMonoTime()
        let controller = newFontPickerController()
        echo "font picker model: ", (getMonoTime() - startedAt).inMilliseconds, " ms"
        controller
    else:
      newFontPickerController()
  themePicker = newComboBox(
    [
      dtDefault.title(),
      dtMacOS.title(),
      dtNebula.title(),
      dtPeachy.title(),
      dtSynthwave83.title(),
    ]
  )
  fontPicker = newCascadingView()
  fontSizePicker = newComboBox(
    [dfs12.title(), dfs14.title(), dfs16.title(), dfs18.title(), dfs20.title()]
  )
  preview = newLabel("The quick brown fox jumps over the lazy dog.")
  applyFontButton = newButton("Apply font")
  themeChanged = actionSelector("themeChanged")
  fontSizeChanged = actionSelector("fontSizeChanged")
  applyFont = actionSelector("applyFont")

var
  activeTheme = dtDefault
  previewFontPath = ""
  previewFontSize = dfs14
  appliedFontPath = ""
  appliedFontSize = dfs14

proc updatePreview() =
  preview.appearance = activeTheme.appearanceFor(previewFontPath, previewFontSize)
  status.text =
    "Previewing " & previewFontPath.fontTitle() & " · " & previewFontSize.title() &
    " — application: " & appliedFontPath.fontTitle() & " · " & appliedFontSize.title()

proc applyAppearance() =
  app.setAppearance(activeTheme.appearanceFor(appliedFontPath, appliedFontSize))
  updatePreview()

proc themeDidChange(sender: DynamicAgent) =
  if sender of ComboBox:
    let index = ComboBox(sender).selectedIndex()
    if index >= ord(low(DemoTheme)) and index <= ord(high(DemoTheme)):
      activeTheme = DemoTheme(index)
      applyAppearance()

proc fontSizeDidChange(sender: DynamicAgent) =
  if sender of ComboBox:
    let index = ComboBox(sender).selectedIndex()
    if index >= ord(low(DemoFontSize)) and index <= ord(high(DemoFontSize)):
      previewFontSize = DemoFontSize(index)
      updatePreview()

proc applyFontDidClick(sender: DynamicAgent) =
  if sender of Button:
    appliedFontPath = previewFontPath
    appliedFontSize = previewFontSize
    applyAppearance()

for form in [appearanceForm, typographyForm]:
  form.edgeInsets = insets(0.0)
  form.spacing[dcol] = 12.0
  form.spacing[drow] = 10.0
  form.minFieldWidth = 260.0

themePicker.selectedIndex = activeTheme.ord
themePicker.target = newActionTarget(themeChanged, themeDidChange)
themePicker.action = themeChanged
fontPicker.columnWidth = 180.0
fontPicker.minColumnWidth = 140.0
fontPicker.accessibilityLabel = "Font"
fontPickerController.selectionHandler = proc(path: string) =
  previewFontPath = path
  updatePreview()
when defined(settingsDemoBenchmark):
  let cascadingSetupStartedAt = getMonoTime()
fontPicker.dataSource = fontPickerController
fontPicker.delegate = fontPickerController
fontPicker.selectedPath =
  @[DefaultFontLanguage.fontPickerLanguageIdentifier(), DefaultSystemFontIdentifier]
when defined(settingsDemoBenchmark):
  echo "cascading source setup: ",
    (getMonoTime() - cascadingSetupStartedAt).inMilliseconds, " ms"
fontSizePicker.selectedIndex = previewFontSize.ord
fontSizePicker.target = newActionTarget(fontSizeChanged, fontSizeDidChange)
fontSizePicker.action = fontSizeChanged
applyFontButton.target = newActionTarget(applyFont, applyFontDidClick)
applyFontButton.action = applyFont

appearanceForm.addRow(themeLabel, themePicker)
appearancePage.stack.addArrangedSubview(
  newHeadingLabel("Appearance"),
  newLabel("Choose one of Merenda's built-in themes for this application."),
  appearanceForm,
)
appearancePage.stack.addFlexibleSpacer()

typographyForm.addRow(fontLabel, fontPicker)
typographyForm.addRow(fontSizeLabel, fontSizePicker)
typographyPage.stack.addArrangedSubview(
  newHeadingLabel("Typography"),
  newLabel("Choose a font family, language, and face, then preview and apply it."),
  typographyForm,
  newHeadingLabel("Preview"),
  preview,
  applyFontButton,
)
typographyPage.stack.addFlexibleSpacer()

discard
  tabs.addTabViewItem(newTabViewItem("Appearance", appearancePage.view, "appearance"))
discard
  tabs.addTabViewItem(newTabViewItem("Typography", typographyPage.view, "typography"))
tabs.setHuggingPriority(LayoutPriorityLow, laVertical)
tabs.setCompressionPriority(LayoutPriorityRequired, laVertical)

layout.spacing = 12.0
layout.alignment = svaFill
layout.addArrangedSubview(titleLabel, tabs, status)
root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(22.0, 24.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)
panel.styleMask = panel.styleMask + {wsmResizable}
panel.automaticallyAdjustsContentMinSize = true

applyAppearance()
when defined(settingsDemoBenchmark):
  echo "settings demo setup: ",
    (getMonoTime() - settingsDemoStartedAt).inMilliseconds, " ms"
else:
  app.runWindow(panel, root, themePicker)
