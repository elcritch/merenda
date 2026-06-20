import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Menu Demo", frame = initRect(120, 120, 520, 300))
  root = newView(frame = initRect(0, 0, 520, 300))
  content = newStackView(laVertical)
  title = newTitleLabel("Menu Demo")
  status = newStatusLabel("Menu action count: 0")
  button = newButton("Run Menu Action")
  runAction = actionSelector("runMenuDemoAction")
  resetAction = actionSelector("resetMenuDemoAction")
  mainMenu = newMenu("Main")
  menuBar = newMenuBar(mainMenu, initRect(0, 0, 520, 28))
  actionsMenu = newMenu("Actions")
  actionsItem = newMenuItem("Actions")
  runItem = newMenuItem("Run Menu Action", runAction, "r", {kmCommand})
  resetItem = newMenuItem("Reset Count", resetAction, "0", {kmCommand})

var actionCount = 0

proc updateStatus() =
  status.text = "Menu action count: " & $actionCount

proc onRun(sender: DynamicAgent) =
  inc actionCount
  updateStatus()

proc onReset(sender: DynamicAgent) =
  actionCount = 0
  updateStatus()

let
  runTarget = newActionTarget(runAction, onRun)
  resetTarget = newActionTarget(resetAction, onReset)

runItem.target = runTarget
resetItem.target = resetTarget
actionsItem.submenu = actionsMenu
discard actionsMenu.addItem(runItem)
discard actionsMenu.addSeparator()
discard actionsMenu.addItem(resetItem)
discard mainMenu.addItem(actionsItem)
app.mainMenu = mainMenu
menuBar.reload()

root.background = initColor(0.95, 0.96, 0.98)

button.target = runTarget
button.action = runAction

content.spacing = 12.0
content.alignment = svaFill
content.addArrangedSubview(title, status, button)
root.addSubview(menuBar, content)

menuBar.pinEdges(toGuide = root.contentLayoutGuide(), edges = {leLeft, leTop, leRight})
menuBar[atHeight].equalTo(28).active = true
content.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(72.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
