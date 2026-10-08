import std/os
import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("CSS theme and layout preview", frame = rect(120, 120, 820, 540))
  root = newView()
  toolbar = newStackView(laHorizontal)
  sidebar = newStackView(laVertical)
  editor = newStackView(laVertical)
  grid = newGridView()
  title = newTitleLabel("NimKit CSS")
  field = newTextField("Try typing here")
  reload = newButton("Reload CSS")
  status = newStatusLabel("Edit css_theme_demo.css, then click Reload CSS")
  slider = newSlider(value = 0.65)
  base = initThemeByName("macos")
  stylesheet = currentSourcePath().parentDir / "css_theme_demo.css"
  reloadAction = actionSelector("reloadCssTheme")

proc reloadStyles(sender: DynamicAgent) =
  let parsed = loadCssTheme(stylesheet, base)
  root.appearance = initAppearance(parsed.theme)
  root.layoutSubtreeIfNeeded()
  if parsed.diagnostics.len > 0:
    let first = parsed.diagnostics[0]
    status.text = "CSS line " & $first.line & ": " & first.message
  elif root.cssLayoutDiagnostics.len > 0:
    let first = root.cssLayoutDiagnostics[0]
    status.text = "Layout #" & first.viewId & ": " & first.message
  else:
    status.text =
      "CSS controls the panels, spacing and styles. Edit the file and reload."

toolbar.styleId = "toolbar"
sidebar.styleId = "sidebar"
editor.styleId = "editor"
status.styleId = "status"
sidebar.addStyleClass("panel")
editor.addStyleClass("panel")
reload.addStyleClass("primary")
reload.target = newActionTarget(reloadAction, reloadStyles)
reload.action = reloadAction
toolbar.addArrangedSubview(title, reload)
sidebar.addArrangedSubview(
  newHeadingLabel("CONTROL METRICS"),
  newCheckBox("Show guides"),
  newSwitchButton(on = true),
  slider,
  newProgressIndicator(value = 0.65),
)
editor.addArrangedSubview(newTitleLabel("Native constraints, CSS syntax"), field, grid)
grid.addSubview(newLabel("Layout"), row = 0, col = 0)
grid.addSubview(newLabel("Edge pins and sibling anchors"), row = 0, col = 1)
grid.addSubview(newLabel("Sizing"), row = 1, col = 0)
grid.addSubview(newLabel("Percentages with min/max bounds"), row = 1, col = 1)
grid.addSubview(newLabel("Containers"), row = 2, col = 0)
grid.addSubview(newLabel("CSS gaps, insets and alignment"), row = 2, col = 1)
root.addSubview(toolbar)
root.addSubview(sidebar)
root.addSubview(editor)
root.addSubview(status)
window.setContentView(root)
reloadStyles(nil)
app.runWindow(window, root)
