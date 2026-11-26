# One upload form, three ways

These Merenda demos build the same upload screen with traditional MVC, reactive
MVC, and DirectView with Sigils. Each version gives you a different way to
follow an edit from the file record back to the screen. You can use these
techniques together in the same NimKit window.

## The upload problem

You have a batch of files to upload. A list on the left lets you select, add,
and remove files. The editor on the right shows the selected file's name, alt
text, category, subcategory, tags, and **Special file** flag. When you select
another file, the editor loads that file's values and starts a fresh editing
session.

Several rules make this a useful example.

- **File values and editing state have different lifetimes.** Your edits stay
  with each file. Touched fields and visible errors reset when you select
  another file.
- **Some rules span fields or files.** Changing category clears the subcategory.
  Marking one file as special clears the flag on the others.
- **Tag search runs asynchronously.** The parent sends each query to a simulated
  worker. The form checks the query again when results arrive and applies
  suggestions for the current query.
- **Save checks the whole batch.** It selects the first invalid file and shows
  its errors. When all files are valid, the demo displays a simulated upload
  summary.

This gives you three kinds of updates to compare. Editing a name changes the
text already on screen. Selecting another file replaces the editor. Adding or
removing a file changes the list's structure. A design needs to account for all
three while keeping one authoritative set of file records.

## Run the demos

Install dependencies and run a demo from the repository root. Check the
platform requirements before building. [Merenda setup guide](../../README.md#try-merenda)

```sh
atlas install -tuk
nim c -r examples/uploads/upload_form_mvc_demo.nim
nim c -r examples/uploads/upload_form_reactive_mvc_demo.nim
nim c -r examples/uploads/upload_form_direct_demo.nim
```

Start with the same edit in each version.

1. Erase the first file's name. The row becomes **Untitled file**, and the
   editor shows **A file name is required.**
2. Select another file, then return to the first. Its name is still empty. The
   message is hidden until you edit the name or try to save.
3. Mark two different files as special in succession. The **Special** label
   moves from the first row to the second.

Next, choose **Photos** and **Portrait**, then change the category to
**Documents**. The subcategory options change to **Invoice**, **Contract**, and
**Report**. The editor also prompts you to choose a subcategory because the
category change cleared your earlier choice.

Type `su` in the tag field and pick **sunset** from the results. Switch files
and return. The tag stays with the file, and the search field starts empty.
These interactions work with the sample records that are loaded at startup.

## Traditional MVC refreshes views from the controller

Build the widget tree with ordinary NimKit constructors. A plain `UploadModel`
holds the file records in a sequence. The controller keeps the selected index
and the set of fields touched in the current editor. It uses that index to find
both the record to edit and the row to refresh.

### Follow a text edit

The controller connects both text fields to `textEdited` when it creates the
editor. The handler recognizes the sender, writes the text to the corresponding
file field, and marks that field as touched. The last two calls tell you
exactly which parts of the screen update.

```nim
proc textEdited(c: UploadController, sender: DynamicAgent) {.slot.} =
  let editor = c.ui.editor
  if sender == DynamicAgent(editor.name):
    c.model.files[c.selected].name = editor.name.stringValue
    c.touched.incl ffName
  elif sender == DynamicAgent(editor.altText):
    c.model.files[c.selected].altText = editor.altText.stringValue
    c.touched.incl ffAltText
  else:
    return
  c.showRow(c.selected)
  c.showIssues()
```

`showRow` reads the record and sets the row's title, selection state, and
detail text. `showIssues` displays validation messages for touched fields,
or for every field after a failed save attempt. The text field stays in place
with the text the user typed.

### Handle selection and changes across files

Selection takes a different path. The controller sets the index and calls
`showEditor`, which resets the touched fields and constructs the editor from
the newly selected record. Refreshing the previous and current rows moves the
selection highlight.

```nim
proc selectFile(c: UploadController, index: int) =
  let previous = c.selected
  if previous != index:
    c.selected = index
    c.showEditor()
    if previous >= 0:
      c.showRow(previous)
  c.showRow(index)
```

Removing a file also exposes the controller's index bookkeeping. When you
delete a row above the selection, the selected index moves up and the editor
stays with the same file. Delete the selected row and the controller opens
the file that takes its place. If you delete the last row, the selection moves
to the new last file, or clears if the list is empty.

For **Special file**, the handler calls `c.model.setSpecial` to update the flags,
then refreshes every row. That covers the previously marked file as well as the
selected one. The handler makes the full update easy to trace, and each new
display of that flag needs a refresh call from the relevant edit paths.
[Traditional MVC demo](upload_form_mvc_demo.nim)

## Reactive MVC binds the same widgets to the model

Keep the native row and editor constructors and connect their widgets to the
model with a `BindingScope`. Button actions and text edits call commands.
Changes from those commands and changes from elsewhere in the application
follow the same path from the model back to the widgets.

### Observe the right part of the model

`UploadStore` holds files in a `CollectionSigil` keyed by file ID. Each
subscription follows the state that matters to its target.

- `store.files.order` publishes the ordered IDs. A membership or order change
  calls `showRows` to rebuild the list.
- `store.selected` is a `Sigil[int]` for the selected ID. A selection change
  calls `showEditor` and updates the selection indicators.
- `store.files.item(id)` observes one record. The row and editor can read from
  that record using separate bindings.

The row's `bindValue` calls `showName` when the record changes. The editor's
`bindTextField` has both a reader and an edit callback. The reader supplies the
model text to the widget, and `editFileText` marks the field as touched and
calls the store command when the user types.

```nim
# When binding a row in the list.
let item = store.files.item(id)
scope.bindValue("name-" & $id, item, row.select, showName)

# In the selected file's editor scope.
let key: FileTextContext = (id, ffName)
scope.bindTextField("name", item, form, key, readFileText, editor.name, editFileText)
```

Calling `store.setName(id, "Cover photo")` for the selected file updates the
row title and the mounted text field in place. That model-driven update uses
the field setter and leaves the touched flags as they were. User edits take
the callback path. The callback checks the selected ID before writing so an
edit from an old editor leaves the new selection alone.

### Give subscriptions a lifetime

The controller manages separate scopes for the page, rows, and editor.
Rebuilding the list disposes the row scope. Switching files disposes the old
editor scope before binding the new editor. Disposal releases the subscriptions
and edit callbacks together. The controller also disposes the scopes when it
tears down.

Bindings can follow derived values too. The category buttons observe
`form.choice`, a computed pair of category and subcategory. Editing the name
leaves that pair unchanged, so the buttons stay in place. Validation labels
observe computed messages that use the file values, touched fields, and whether
the user tried to save. [Reactive MVC demo](upload_form_reactive_mvc_demo.nim) ·
[Shared form state](uploadstate.nim)

## DirectView gives each row and editor a key

Describe the tree with `viewBody`. Inside a control's body, `this` is the
ordinary NimKit widget. The demo's `bindFileText` helper connects the name
field to the same file and edit command as reactive MVC. DirectView ties the
binding's lifetime to the node that declares it.

```nim
TextField(identifier = "name"):
  this.bindFileText(form, id, ffName)
```

### Separate value updates from changes to the tree

A field binding updates a property on an existing widget. A body binding runs
its builder when its observed input changes. The list observes a pair of
ordered file IDs and the selected ID. The editor's body observes selection
directly.

```nim
# In the left column's body.
component(bindBody, page.store.listState, page.store, drawFileList)

# In the right column's body.
component(bindBody, page.form.store.selected, page.form, drawForm)
```

Changing a name leaves the ordered IDs and selection intact. The row label and
field update through their own bindings. Removing a file changes the list
input, and `drawFileList` runs again with the current IDs.

The category controls have their own body binding within the editor.

```nim
component(bindBody, form.choice, form, drawChoices)
```

Changing category updates that group of controls and keeps the text fields
in place. The subcategory keys include both the category and option name, so
options belong to the category that generated them.

### Match identity to the editing session

The list gives each row the file's ID as a key. When you remove the first row,
the rows below keep their widgets as they move up. The key follows the file as
its position changes.

```nim
for id in state.ids:
  keyed(id):
    component(fileRow, id, id == state.selected, store)
```

The editor also uses the file ID as its key. A different selection gives it a
new key, so DirectView mounts fresh fields and retires the old bindings.
`FileForm` resets validation and tag search state on selection. The view
lifecycle and the session reset follow the same selected ID. The new fields
read the values already in the store.

[DirectView demo](upload_form_direct_demo.nim) ·
[DirectView guide](../../docs/declarative-direct-views.md)

## Combine them in Merenda

The techniques solve different parts of the screen. MVC gives the model,
controller, and view clear responsibilities. Sigils propagate state changes.
DirectView describes and updates the widget tree. The examples share code along
those boundaries.

| Shared code | What it owns | Used by |
| --- | --- | --- |
| [File rules](uploadfiles.nim) | File type, validation, and the simulated tag search | All three demos |
| [Native widget builders](uploadviews.nim) | Construction of the list rows and editor widgets | Traditional and reactive MVC |
| [Observable state](uploadstate.nim) | Store commands, file observations, and form-session state | Reactive MVC and DirectView |

You can combine the same pieces when building your own screen.

1. **Put shared rules in the model.** Have each action call the same command
   for a given operation. In the reactive demos, `setCategory` changes the
   category and clears the subcategory in one publication. Views can consume
   the resulting record as a unit.
2. **Bind the values that multiple widgets share.** A native row and a
   DirectView editor can both observe `files.item(id)`. Use the selected ID for
   editor lifetime and file order for list membership so each update reaches
   the part of the screen that needs it.
3. **Choose how to build each part of the tree.** Keep ordinary NimKit
   constructors where explicit widget setup reads clearly. Use a DirectView
   body for a region with repeated or conditional children. A
   `ViewController` can own a `StackView` that contains both.

### Put a native command beside the DirectView editor

Save this example as `examples/uploads/mixed_upload.nim` and run
`nim c -r examples/uploads/mixed_upload.nim`. The window controller hosts a
regular stack with a native button and the DirectView upload screen. The button
calls the store's `clearFiles` command, and its own binding observes file order.

Click **Clear files**. The DirectView list and editor show their empty states,
and the change in file order disables the native button. Adding files through
the upload screen enables it again.

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
