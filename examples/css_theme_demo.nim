import std/os
import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("CSS theme preview", frame = rect(120, 120, 600, 340))
  root = newView()
  form = newStackView(laVertical)
  title = newTitleLabel("Style your NimKit app with CSS")
  field = newTextField("Try typing here")
  reload = newButton("Reload CSS")
  status = newStatusLabel("Edit css_theme_demo.css, then click Reload CSS")
  base = initThemeByName("macos")
  stylesheet = currentSourcePath().parentDir / "css_theme_demo.css"
  reloadAction = actionSelector("reloadCssTheme")

proc reloadStyles(sender: DynamicAgent) =
  discard sender
  let parsed = loadCssTheme(stylesheet, base)
  window.setAppearance(initAppearance(parsed.theme))
  if parsed.diagnostics.len > 0:
    let first = parsed.diagnostics[0]
    status.text = "CSS line " & $first.line & ": " & first.message
  else:
    status.text = "Edit css_theme_demo.css, then click Reload CSS"

reload.addStyleClass("primary")
reload.target = newActionTarget(reloadAction, reloadStyles)
reload.action = reloadAction
form.spacing = 14
form.addArrangedSubview(title, field, reload, status)
root.addSubview(form)
form.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24)), edges = {leLeft, leTop, leRight}
)
reloadStyles(nil)
app.runWindow(window, root)
