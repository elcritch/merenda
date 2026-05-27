import knutella/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow(100, 100, 300, 300, "Nimkit Button Counter")
  root = newView(0, 0, 300, 300)
  button1 = newButton(50, 225, 90, 25, "button1")
  button2 = newButton(50, 125, 200, 75, "button2")
  label1 = newTextField(50, 80, 200, 20, "button1 clicked 0 times")
  label2 = newTextField(50, 50, 200, 20, "button2 clicked 0 times")
  button1Action = actionSelector("button1Clicked")
  button2Action = actionSelector("button2Clicked")

var
  button1Clicked = 0
  button2Clicked = 0

proc onButton1(sender: DynamicAgent) =
  if not sender.isNil:
    inc button1Clicked
    label1.setStringValue("button1 clicked " & $button1Clicked & " times")

proc onButton2(sender: DynamicAgent) =
  if not sender.isNil:
    inc button2Clicked
    label2.setStringValue("button2 clicked " & $button2Clicked & " times")

button1.setTarget(newActionTarget(button1Action, onButton1))
button1.setAction(button1Action)
button2.setTarget(newActionTarget(button2Action, onButton2))
button2.setAction(button2Action)

root.addSubview(button1)
root.addSubview(button2)
root.addSubview(label1)
root.addSubview(label2)
window.setContentView(root)
app.addWindow(window)

discard buildRenders(window)
discard window.clickAt(initPoint(60, 235))
discard window.clickAt(initPoint(60, 135))
discard buildRenders(window)
