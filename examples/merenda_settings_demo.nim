import merenda/nimkit

import sigils/selectors

type DemoTheme = enum
  dtDefault
  dtMacOS
  dtNebula
  dtPeachy
  dtSynthwave83

func title(theme: DemoTheme): string =
  case theme
  of dtDefault: "Default"
  of dtMacOS: "macOS"
  of dtNebula: "Nebula"
  of dtPeachy: "Peachy"
  of dtSynthwave83: "Synthwave '83"

proc appearanceFor(theme: DemoTheme): Appearance =
  case theme
  of dtDefault:
    initAppearance(initTheme())
  of dtMacOS:
    initAppearance(initMacOSTheme())
  of dtNebula:
    initAppearance(initNebulaTheme())
  of dtPeachy:
    initAppearance(initPeachyTheme())
  of dtSynthwave83:
    initAppearance(initSynthwave83Theme())

let
  app = sharedApplication()
  panel = newPanel("Merenda Settings", frame = rect(180, 160, 420, 220))
  root = newView()
  layout = newStackView(laVertical)
  form = newFormView()
  titleLabel = newTitleLabel("Merenda Settings")
  description =
    newLabel("Choose one of Merenda's built-in themes for this application.")
  themeLabel = newFormLabel("Theme")
  themePicker = newComboBox(
    [
      dtDefault.title(),
      dtMacOS.title(),
      dtNebula.title(),
      dtPeachy.title(),
      dtSynthwave83.title(),
    ]
  )
  status = newStatusLabel()
  themeChanged = actionSelector("themeChanged")

proc applyTheme(theme: DemoTheme) =
  app.setAppearance(theme.appearanceFor())
  status.text = "Using the " & theme.title() & " theme"

proc themeDidChange(sender: DynamicAgent) =
  if sender of ComboBox:
    let index = ComboBox(sender).selectedIndex()
    if index >= ord(low(DemoTheme)) and index <= ord(high(DemoTheme)):
      applyTheme(DemoTheme(index))

themePicker.selectedIndex = dtDefault.ord
themePicker.target = newActionTarget(themeChanged, themeDidChange)
themePicker.action = themeChanged
applyTheme(dtDefault)

layout.spacing = 12.0
layout.alignment = svaFill
form.edgeInsets = insets(0.0)
form.spacing[dcol] = 12.0
form.spacing[drow] = 10.0
form.minFieldWidth = 220.0
form.addRow(themeLabel, themePicker)
layout.addArrangedSubview(titleLabel, description, form, status)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(26.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

app.runWindow(panel, root, themePicker)
