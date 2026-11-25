## Run `nim ic -r examples/direct_text_binding_demo.nim` and edit the text
## in the window. Each edit changes the string in the controller.
import sigils/reactive
import merenda/nimkit
import merenda/nimkit/directviews

# The controller holds a Sigil[string] so the field can follow changes
# to the text even when they come from somewhere else in the app.
type TextController = ref object of Responder
  text: Sigil[string]

# To fill the field, the binding calls readText. The {} reads the
# current string from the Sigil.
proc readText(controller: TextController, _: tuple[]): string =
  controller.text{}

# When you type, the binding calls editText with the field's new text.
# The <- writes the string and notifies listeners if the value changed.
proc editText(controller: TextController, _: tuple[], text: string) =
  controller.text <- text

proc runDirectTextBindingDemo() =
  let controller = TextController(text: newSigil("Edit this text"))
  initResponder(controller)

  let root = newDirectView()
  root.edgeInsets = insets(16)
  root.viewBody:
    TextField:
      # The TextField block supplies the field and its binding scope.
      # "text" names the binding, and controller.text is the Sigil it watches.
      # Both callbacks receive controller. The empty tuple () means
      # they need no extra context.
      # readText fills the field. editText takes edits back to the controller.
      bindTextField("text", controller.text, controller, (), readText, editText)

  let window = newWindow("DirectView text binding", frame = rect(100, 100, 400, 120))
  sharedApplication().runWindow(window, root)

when isMainModule and not defined(merendaTests):
  runDirectTextBindingDemo()
