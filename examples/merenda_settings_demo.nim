import merenda/nimkit

import std/[options, os]
import sigils/selectors

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
  fontPickerSource = newSystemFontCatalogDataSource()
  themePicker = newComboBox(
    [
      dtDefault.title(),
      dtMacOS.title(),
      dtNebula.title(),
      dtPeachy.title(),
      dtSynthwave83.title(),
    ]
  )
  fontPicker = newComboBox()
  fontSizePicker = newComboBox(
    [dfs12.title(), dfs14.title(), dfs16.title(), dfs18.title(), dfs20.title()]
  )
  preview = newLabel("The quick brown fox jumps over the lazy dog.")
  applyFontButton = newButton("Apply font")
  themeChanged = actionSelector("themeChanged")
  fontChanged = actionSelector("fontChanged")
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

proc fontDidChange(sender: DynamicAgent) =
  if sender of ComboBox:
    let
      comboBox = ComboBox(sender)
      index = comboBox.selectedIndex()
    if index >= 0:
      let fontPath = comboBox.itemObjectValueAtIndex(index).getString()
      if fontPath.isSome:
        previewFontPath = fontPath.get()
        updatePreview()

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
fontPicker.sizingMode = cbsmPreferredWidth
fontPicker.preferredContentWidth = DefaultFontPickerContentWidth
fontPicker.dataSource = fontPickerSource
fontPicker.selectedIndex = 0
fontPicker.target = newActionTarget(fontChanged, fontDidChange)
fontPicker.action = fontChanged
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
  newLabel("Preview a system font, then apply it to the application."),
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
app.runWindow(panel, root, themePicker)
