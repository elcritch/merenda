## Run `nim ic -r examples/direct_text_binding_demo.nim` and edit the text
## in the window. Each edit updates the same Sigil the field reads from.
import sigils/reactive
import merenda/nimkit
import merenda/nimkit/directviews

proc runDirectTextBindingDemo() =
  # The Sigil holds the string and tells the field when it changes.
  let text = newSigil("Edit this text")

  let root = newDirectView()
  root.edgeInsets = insets(16)
  root.viewBody:
    TextField:
      # The TextField block supplies the field and its binding scope.
      # "text" names the binding, and source is the Sigil it watches.
      # The binding reads with text{} and publishes edits with text <- value.
      bindTextField(id = "text", source = text)

  let window = newWindow("DirectView text binding", frame = rect(100, 100, 400, 120))
  sharedApplication().runWindow(window, root)

when isMainModule and not defined(merendaTests):
  runDirectTextBindingDemo()
