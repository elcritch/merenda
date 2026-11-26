# One upload form, three ways

These Merenda demos build the same upload screen with traditional MVC, reactive
MVC, and DirectView with Sigils. Each version gives you a different way to
follow an edit from the file record back to the screen. You can use these
techniques together in the same NimKit window.

## The upload problem

Imagine preparing a photo and a contract for the same upload. The list shows
which files still need details. The editor shows one file at a time. Erase
the photo's name and its row immediately reads **Untitled file**. Switch to
the contract and back. The photo's name should still be empty, but the error
should stay hidden until you edit the field or try to save.

That interaction separates **file data** from **editing state**. The name,
alt text, category, subcategory, chosen tags, and special flag belong to
the record. Touched fields, visible errors, and the current tag query belong
to a visit to the editor. A reusable list and editor can share a record while
each presents it differently.

Three rules make their coordination interesting.

- Changing category clears the old subcategory. Marking a file **Special**
  clears the flag on every other file.
- Typing `su` requests suggestions. Picking **sunset** stores the tag on the
  file. The editor accepts a worker reply only if it matches the current query.
- **Save** validates the whole batch and opens the first invalid file. The
  shared rules include requiring alt text for images, even after you change
  the display name. [Shared file rules](uploadfiles.nim)

The parent listens for three events. `tagSearchStarted(query)` asks it to
search, `filesChanged(files)` reports additions and removals (including a
clear), and `uploadRequested(files)` delivers the valid batch. The demos start
with five sample paths and simulate the upload so you can try all three
without setting up a backend.

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

### Which version should I read first?

| If your next change is… | Start with | Why |
| --- | --- | --- |
| Change what happens after a failed Save | [Traditional MVC](#traditional-mvc-refreshes-views-from-the-controller) | One handler shows the order in which the form selects a file, reveals its errors, and updates the status. |
| Let a metadata importer update a name while the editor is open | [Reactive MVC](#reactive-mvc-binds-the-same-widgets-to-the-model) | The existing native field and row can both follow the store, regardless of which caller made the edit. |
| Keep individual row widgets alive as files are added and removed | [DirectView](#directview-gives-each-row-and-editor-a-key) | The list declares a key per file. DirectView matches the surviving rows when the list changes. |

## Traditional MVC refreshes views from the controller

In traditional MVC you can step through a user action in one handler. Here
is the decision inside `save` once the controller knows the batch has files.

```nim
for i, file in c.model.files:
  if not file.isValid:
    c.selectFile(i)
    c.submitted = true
    c.showIssues()
    c.ui.status.stringValue = "Fix the highlighted fields before uploading."
    return
emit c.uploadRequested(c.model.files)
```

The order matters. Selecting a different file resets its editor. Setting
`submitted` on the next line reveals the issues on that fresh editor.
`UploadController` owns this interaction and the plain sequence of files.
The parent `UploadPageController` listens for the successful upload and owns
the search worker.

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

The order of operations explains how MVC avoids a feedback loop here. When
opening a file, `addFileEditor` initializes the text fields from the record
before `showEditor` connects their edit handlers. On a keystroke, the text is
already in the active field. The controller writes it once, then refreshes the
row and error labels. There is no step that copies a row title back into the
text field. For a form where typing is the only way to rename, those two
refresh calls may be all the coordination you need. Add a metadata importer
and there are now two ways to rename. The controller must give both paths a
common refresh routine or remember to update the row and editor from each.
That second writer is a concrete reason to consider a binding.

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

The early check for the same index matters. Clicking the selected row again
leaves an in-progress search and the current validation messages alone.
Actually switching files clears the form stack, resets `touched` and
`submitted`, and creates a tag controller initialized with the new file's
chosen tags. The empty query requests suggestions for the fresh picker. A
late reply for `su` is accepted only if it matches the current picker's
normalized query. This works because every file searches the same catalog.

Removing a file also exposes the controller's index bookkeeping. When you
delete a row above the selection, the selected index moves up and the editor
stays with the same file. Delete the selected row and the controller opens
the file that takes its place. If you delete the last row, the selection moves
to the new last file, or clears if the list is empty.

The special-file handler shows the cost of explicit refresh. Either the
selected row or a different row can lose the **Special** label, so the
controller refreshes them all.

```nim
proc specialEdited(c: UploadController, sender: DynamicAgent) {.slot.} =
  if sender == DynamicAgent(c.ui.editor.special):
    c.model.setSpecial(c.selected, c.ui.editor.special.state == bsOn)
    for i in 0 ..< c.ui.rows.len:
      c.showRow(i)
```

A new display of the flag would need a refresh here too.
[Traditional MVC demo](upload_form_mvc_demo.nim)

### See how far one command reaches

Changing a category affects three displays. The radio button's parent stack
tells `choiceEdited` whether the click was a category or a subcategory. For a
category click it remembers the old subcategory, applies the file rule below,
and marks the subcategory touched if that rule cleared a previous answer.

```nim
proc setCategory(file: var UploadFile, category: string) =
  if file.category != category:
    file.category = category
    file.subcategory = ""
```

The handler then calls `showChoices` to rebuild the two option groups,
`showRow` to update the breadcrumb, and `showIssues` to tell the user what
needs attention. Choosing **Photos** again preserves **Portrait**. Changing
to **Documents** removes **Portrait** from both the record and the screen.
The model rule is four lines. Much of the controller's work is deciding
which controls need to present its result.

## Reactive MVC binds the same widgets to the model

A metadata importer can change the name while the native editor is open.
This excerpt adapts the upload test to show what the caller does and what
the two existing widgets display after the UI processes the change.

```nim
let name = TextField(view.viewWithIdentifier("name"))
let row = Button(view.viewWithIdentifier("file-1"))
store.setName(1, "Cover photo")
discard drainMainThreadWork()
check name.stringValue == "Cover photo"
check row.title == "Cover photo"
check controller.page.form.touched{} == {}
```

The importer only needs the store and file ID. The controller can keep
the row and editor constructors from traditional MVC because the bindings
attach to the widgets those constructors return. [Upload form tests](../../tests/nimkit/uploadform.nim)

### Observe the right part of the model

`UploadStore` holds files in a `CollectionSigil` keyed by file ID. Each
subscription follows the state that matters to its target.

- `store.files.order` publishes the ordered IDs. A membership or order change
  calls `showRows` to rebuild the list.
- `store.selected` is a `Sigil[int]` for the selected ID. A selection change
  calls `showEditor` and updates the selection indicators.
- `store.files.item(id)` observes one record. The row and editor can read from
  that record using separate bindings.

In `showRows`, each native row binds its title and detail to its own file.

```nim
let row = list.addFileRow(id)
let item = store.files.item(id)
scope.bindValue("name-" & $id, item, row.select, showName)
scope.bindValue("detail-" & $id, item, row.detail, showDetail)
```

In `showEditor`, a separate scope binds the two editable fields to that same
record. The reader loads the text. The edit callback carries the ID and field
so it can mark a user edit as touched and reject an edit from an old editor.

```nim
let item = store.files.item(id)
for (field, widget) in [(ffName, editor.name), (ffAltText, editor.altText)]:
  let key: FileTextContext = (id, FileTextField(field))
  scope.bindTextField($field, item, form, key, readFileText, widget, editFileText)
```

There are two protections against sending a change round in circles.
`bindTextField` tracks model text and suppresses the edit callback during a
programmatic write to the widget. On the model side, `modifyFile` compares the
edited record with the current value before publishing it. For example, an
import that supplies a new description updates the text on screen without
marking alt text as touched. Typing a description into the same control
marks it touched even if the user later types their way back to the original
value. “Touched” records an interaction during this visit to the file.

### Give subscriptions a lifetime

The controller manages separate scopes for the page, rows, and editor.
Rebuilding the list disposes the row scope. Switching files disposes the old
editor scope before binding the new editor. Disposal releases the subscriptions
and edit callbacks together. The controller also disposes the scopes when it
tears down.

Consider removing the first of three files while editing the third. The
ordered IDs change, so `showRows` clears the list and creates new row widgets
and bindings for the two survivors. Each row button carries its file ID as
the command context. The selected ID still identifies the third file, so
its editor stays mounted. Remove that selected file instead and the store
also publishes a new selection. The selection binding then replaces the
editor, and the form's selection handler resets the editing session.

Bindings can follow derived values too. The category buttons observe
`form.choice`, a computed pair of category and subcategory. Editing the name
leaves that pair unchanged, so the buttons stay in place. Validation labels
observe computed messages that use the file values, touched fields, and whether
the user tried to save. [Reactive MVC demo](upload_form_reactive_mvc_demo.nim) ·
[Shared form state](uploadstate.nim)

### Decide what a model change publishes

A collection item represents a whole `UploadFile`. In the following excerpt,
`{}` reads the current value. Reading `selected{}` and then the corresponding
item inside `computedNow` makes the result depend on both. Switching files
changes which item supplies the category pair.

```nim
result.choice = computedNow[CategoryChoice]:
  let file = files.item(selected{}){}.get(UploadFile())
  (category: file.category, subcategory: file.subcategory)
```

A rename can therefore cause this calculation to run. The resulting pair is
equal to its previous value, so the calculation ends without publishing to
`showChoices`. A change from **Photos › Portrait** to **Documents** produces
a different pair. `setCategory` writes the new category and empty subcategory
into one record before publishing it. The choice controls receive a pair that
already agrees with the file rule. The form separately decides whether the
cleared subcategory warrants a visible issue.

For **Special file**, the store publishes all the changed flags together.
Here is the update inside `setSpecial`, after it checks that the ID exists.

```nim
var next = store.files{}
for file in next.mitems:
  file.special = special and file.id == id
if next != store.files{}:
  store.files <- next
```

The old and new special rows receive the new details through the row bindings
above. File order stays the same, so `showRows` can stay idle.

## DirectView gives each row and editor a key

Delete the photo while editing the contract below it. Both MVC demos rebuild
their lists. DirectView can keep the contract row because the loop in
`drawFileList` identifies it by file ID as it moves up.

```nim
for id in state.ids:
  keyed(id):
    component(fileRow, id, id == state.selected, store)
if state.ids.len == 0:
  Label(stringValue = "No files. Add some to upload.")
```

The same key has a second use in the editor. Selecting a different file
should replace the fields, even when the new file has the same name.

```nim
if id in form.store.files:
  keyed(id):
    component(fileFields, form, id)
else:
  Label(stringValue = "Select or add a file to edit its details.")
```

These two declarations let DirectView keep the surviving rows and retire
the old editor's bindings. The application supplies the identities and
decides which changes should run each builder.

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

Look at how the row uses selection. Its background color is assigned inside
`fileRow` from the `selected` argument. Selecting the contract changes
`listState`, so the list runs its loop again and supplies updated arguments
to the keyed rows. That ordinary property assignment runs again on the
surviving widgets. Each name label has its own `bindValue` on the
record. It can get a new title while the loop is idle. When reading a body,
look at the source passed to each binding to tell which updates can reach
that part of the tree.

### Bind a field inside its editing session

Inside `fileFields`, `this` is the ordinary NimKit text field. DirectView
gives the field a binding scope for the lifetime of its node.

```nim
TextField(identifier = "name"):
  this.bindFileText(form, id, ffName)
```

The helper uses the same reader and edit command as the native MVC binding.

```nim
template bindFileText(field: TextField, form: FileForm, id: int, kind: FileTextField) =
  let key: FileTextContext = (id, kind)
  field.bindTextField(
    $kind, form.store.files.item(id), form, key, readFileText, editFileText
  )
```

Switching IDs mounts a new field that reads the new record. The separate
`FileForm` selection handler clears touched fields, submit errors, and the
query. A rename keeps the same ID and updates the existing field.

### Follow an action out of the tree

The **Special file** checkbox declares both directions together. Its binding
reads the flag for this file, and its action delegates the batch-wide rule
to the same store command reactive MVC uses.

```nim
CheckBox(identifier = "special", title = "Special file (only one per upload)"):
  this.bindValue("special", store.files.item(id)) do(
    box: Button, file: Opt[UploadFile]
  ):
    box.state = if file.isSome and file.get.special: bsOn else: bsOff
  this.onAction(store, id) do(this: Button, receiver: UploadStore, id: int):
    receiver.setSpecial(id, this.state == bsOn)
```

The tag picker shows where a component can keep its existing controller.
`TagPicker(form.tagController, ...)` mounts a native picker. The shared
`FileForm` already connects query edits, selected tags, and returned
suggestions. Changing the selected ID replaces the picker widget along with
the other fields. The form keeps its tag controller, loads the selected file's
tags, and resets the query. Rebuilding the widget alone would leave the old
query in that controller. Resetting the session in the form gives both
reactive versions the same behavior.

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
