# One upload form, three ways

Open any demo and erase the first file's name. Its row becomes “Untitled file”
and the editor shows “A file name is required.” Select another file and come
back. The name is still empty, and the error stays hidden until you edit the
name or try to save.

The three demos give that interaction the same behavior. Traditional MVC puts
the update sequence in the controller. Reactive MVC binds ordinary NimKit
widgets to the model. DirectView uses the same bindings and takes care of
matching widgets as the tree changes.

## Run the demos

Install dependencies and run a demo from the repository root. Check the
platform requirements before building. [Merenda setup guide](../../README.md#try-merenda)

```sh
atlas install -tuk
nim c -r examples/uploads/upload_form_mvc_demo.nim
nim c -r examples/uploads/upload_form_reactive_mvc_demo.nim
nim c -r examples/uploads/upload_form_direct_demo.nim
```

Changing category clears the subcategory, and only one file can be marked
special. Tag suggestions come from a simulated search worker. Save selects the
first invalid file so you can fix it. Once every file is valid, Save shows a
simulated upload summary.

## Traditional MVC refreshes views from the controller

Build the widget tree with ordinary NimKit constructors. A plain `UploadModel`
holds the file records. The controller handles widget actions, changes the model,
and explicitly refreshes the affected views. For a screen with a few edit paths,
you can trace an interaction from input to display in one handler.

The name branch of `textEdited` stores the new value, marks the field as touched,
and refreshes the existing row and validation labels.

```nim
if sender == DynamicAgent(editor.name):
  c.model.files[c.selected].name = editor.name.stringValue
  c.touched.incl ffName
# The handler also accepts edits from the alt-text field.
c.showRow(c.selected)
c.showIssues()
```

[Traditional MVC demo](upload_form_mvc_demo.nim)

## Reactive MVC binds the same widgets to a file

Build the same native widgets and use a `BindingScope` to subscribe them to the
model. A change from a form edit or another part of the application follows the
same path back to the widgets.

`UploadStore` exposes files as a keyed `CollectionSigil` and the selected file
ID as a `Sigil[int]`. The list rebuilds its rows when file order changes, and each
row observes its own file. The editor gets a fresh scope when selection changes.
Its text binding reads that file and passes edits to `editFileText`, which
marks the field touched and calls the store command.

```nim
# When binding a row in the list.
let item = store.files.item(id)
scope.bindValue("name-" & $id, item, row.select, showName)

# In the selected file's editor scope.
let key: FileTextContext = (id, ffName)
scope.bindTextField("name", item, form, key, readFileText, editor.name, editFileText)
```

Calling `store.setName(id, "Cover photo")` updates the row title and the mounted
text field through the bindings. Both widgets stay in place. The edit callback
marks the field touched when the user types.

[Reactive MVC demo](upload_form_reactive_mvc_demo.nim)

## DirectView gives each row and editor a key

Describe the widget tree in a `viewBody`. The name field uses the same
per-file observation and edit command as reactive MVC. The DirectView node
owns the binding's lifetime.

```nim
TextField(identifier = "name"):
  this.bindFileText(form, id, ffName)
```

Keys matter when the structure changes. The list's body identifies rows by file
ID, so DirectView can keep surviving rows when you add or remove a file.

```nim
for id in state.ids:
  keyed(id):
    component(fileRow, id, id == state.selected, store)
```

The editor also uses the file ID as its key. Selecting another file mounts a
fresh editor and retires the previous editor's bindings. `FileForm` resets the
validation and tag search state on selection.

[DirectView demo](upload_form_direct_demo.nim) ·
[DirectView guide](../../docs/declarative-direct-views.md)

## Combine them in Merenda

Use MVC to decide who owns file data and handles commands. Add Sigil bindings
where multiple widgets need to follow the same state. Use DirectView for the
parts of the widget tree you want to express declaratively. All three use NimKit
widgets, so a native controller can host a DirectView subtree in a regular
`StackView`.

Traditional and reactive MVC use the same row and editor builders. Reactive
MVC and DirectView share `UploadStore` and `FileForm`. The store enforces file rules
such as clearing the subcategory in the same update that changes the category.
The form keeps session state such as touched fields and tag queries. All three
share the file type, validation rules, and search worker.

[Shared reactive model and form state](uploadstate.nim) ·
[Shared native widget construction](uploadviews.nim) · [File rules](uploadfiles.nim)

Save this example as `examples/uploads/mixed_upload.nim` and run
`nim c -r examples/uploads/mixed_upload.nim`. Click **Clear files**. The native
button sends a store command, the DirectView list and editor show their empty
states, and the same change in file order disables the button.

```nim
import merenda/nimkit
import ./upload_form_direct_demo

let page = newUploadPage()
let root = newStackView(laVertical)
let clearButton = newButton("Clear files")
clearButton.action = actionSelector("clearFiles")
clearButton.target = newActionTarget(clearButton.action, page.store) do(
  store: UploadStore, sender: DynamicAgent
):
  store.clearFiles()

let bindings = newBindingScope()
bindings.bindValue("can-clear", page.store.files.order, clearButton) do(
  button: Button, ids: seq[int]
):
  button.enabled = ids.len > 0

root.addArrangedSubview(clearButton, (page.newUploadView(), svspFillAvailableSpace))
let app = sharedApplication()
let window = newWindowController(
  newWindow("Mixed upload form", frame = rect(80, 80, 980, 680))
)
window.viewController = newViewController(root)
window.showWindow(app)
app.run()
bindings.dispose()
```
