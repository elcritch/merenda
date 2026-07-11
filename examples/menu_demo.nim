import std/os

import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Menu Demo", frame = rect(120, 120, 520, 300))
  content = newStackView(laVertical)
  title = newTitleLabel("Menu Demo")
  status = newStatusLabel("Menu action count: 0")
  button = newButton("Run Menu Action")
  runAction = actionSelector("runMenuDemoAction")
  resetAction = actionSelector("resetMenuDemoAction")
  mainMenu = newMenu("Main")
  actionsMenu = newMenu("Actions")
  actionsItem = newMenuItem("Actions")
  runItem = newMenuItem("Run Menu Action", runAction, "r", {kmCommand})
  resetItem = newMenuItem("Reset Count", resetAction, "0", {kmCommand})
  contextMenu = newMenu("Menu Demo Context")
  contextRunItem = newMenuItem("Run Menu Action", runAction)
  contextResetItem = newMenuItem("Reset Count", resetAction)

if "--in-window-menu" in commandLineParams():
  app.mainMenuPresentation = mmpInWindow

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
contextRunItem.target = runTarget
contextResetItem.target = resetTarget
actionsItem.submenu = actionsMenu
discard actionsMenu.addItem(runItem)
discard actionsMenu.addSeparator()
discard actionsMenu.addItem(resetItem)
discard mainMenu.addItem(actionsItem)
discard contextMenu.addItem(contextRunItem)
discard contextMenu.addSeparator()
discard contextMenu.addItem(contextResetItem)
app.mainMenu = mainMenu

button.target = runTarget
button.action = runAction

content.spacing = 12.0
content.alignment = svaFill
content.edgeInsets = insets(28.0, 28.0, 0.0, 28.0)
content.addArrangedSubview(title, status, button)
content.menu = contextMenu

let root = newMenuRootView(mainMenu, content, rect(0, 0, 520, 300))

app.runWindow(window, root)
