## Run `nim ic -r examples/direct_text_binding_signal_demo.nim` and edit
## the text in the window. Each edit updates a plain string.
import sigils/core
import merenda/nimkit
import merenda/nimkit/directviews

# The controller stores the text and tells listeners when it changes.
type TextController = ref object of Responder
  text: string

# textChanged carries no value. It tells the binding to read the text again.
proc textChanged(controller: TextController) {.signal.}

# The binding calls readText to fill the field when it first appears
# and to refresh it after the controller signals a change.
proc readText(controller: TextController, _: tuple[]): string =
  controller.text

# When you type, the field sends its text to editText. The check keeps
# repeated values from triggering another write and notification.
proc editText(controller: TextController, _: tuple[], text: string) =
  if controller.text != text:
    controller.text = text
    emit controller.textChanged()

proc runDirectTextBindingSignalDemo() =
  let controller = TextController(text: "Edit this text")
  initResponder(controller)

  let root = newDirectView()
  root.edgeInsets = insets(16)
  root.viewBody:
    TextField:
      # The view's bindingScope owns the connection named "text".
      # Here controller both sends textChanged and receives edits.
      # The callbacks need no extra context, so we pass ().
      # readText supplies the value for this, the field we're building.
      # editText handles edits from that field.
      bindingScope.bindTextField(
        "text", controller, textChanged, (), readText, this, editText
      )

  let window =
    newWindow("DirectView text binding with a signal", frame = rect(100, 100, 400, 120))
  sharedApplication().runWindow(window, root)

when isMainModule and not defined(merendaTests):
  runDirectTextBindingSignalDemo()
