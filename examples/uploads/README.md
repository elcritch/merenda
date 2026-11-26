# One upload form, three ways

These Merenda demos build the same upload screen with traditional MVC, reactive
MVC, and DirectView with Sigils. Each version gives you a different way to
follow an edit from the file record back to the screen. You can use these
techniques together in the same NimKit window.

## The upload problem

Imagine preparing a photo, a contract, and a podcast for the same upload.
You give the photo a readable name and describe it for someone who can't see
it. You file the contract under **Documents › Contract** and add a **legal**
tag. You can move between files in any order, remove one, or add more before
saving. **Save** submits the metadata for the whole batch. The demos start
with five sample paths and simulate the upload, so you can try the entire
interaction without supplying files or running a server.

The list on the left shows the whole batch at a glance. Each row has a display name,
file type, category if chosen, and whether the file still needs details. The
editor on the right gives you the full record for one file. Erase the photo's
name and its row immediately reads **Untitled file**. Switch to the contract
and back, and the photo's name field should still be empty. “Untitled file”
is a presentation choice for the list. Saving that string into the record
would accidentally satisfy the required-name check.

This is a common integration problem when a screen combines a reusable list
with a reusable editor. A list can report which row was clicked without
knowing what makes an image valid. A tag picker can report a query without
knowing where the catalog lives. Someone still has to decide which record an
edit belongs to, how long an error should stay visible, and what a parent
receives when the user clicks Save. The examples use concrete upload widgets
so you can follow those decisions in ordinary Nim code.

Several rules make this a useful example.

- **File values and editing state have different lifetimes.** Your edits stay
  with each file. Touched fields and visible errors reset when you select
  another file.
- **Some rules span fields or files.** Changing category clears the subcategory.
  Marking one file as special clears the flag on the others.
- **Tag search runs asynchronously.** The parent sends each query to a worker
  that simulates a backend. The form checks the query when results arrive and applies
  suggestions for the current query.
- **Save checks the whole batch.** It selects the first invalid file and shows
  its errors. When all files are valid, the demo displays a simulated upload
  summary.

This gives you three kinds of updates to compare. Editing a name changes the
text already on screen. Selecting another file replaces the editor. Adding or
removing a file changes the list's structure. A design needs to account for all
three while keeping one authoritative set of file records.

### What belongs to a file?

The shared `UploadFile` type has an ID, an original path, and editable
metadata. The path supplies the initial name and determines whether alt text
is required. Renaming a JPEG to “Cover photo” leaves that requirement intact.
Both the row summary and the Save action use `issueFor` through `isValid`, so
they agree about which records are ready. The editor asks a second question
before showing an issue. Has the user touched this field or tried to submit
this file? A row can truthfully say **Needs details** while the newly opened
editor shows no errors. [Shared file rules](uploadfiles.nim)

The tag field makes the distinction especially visible. A chosen tag such as
**sunset** belongs in the upload. The characters `su` belong to the current
search. The suggestions **summer** and **sunset** are an answer from the
catalog. Returning to the file restores its chosen tags and starts with an
empty query. The parent sees three events with different meanings.

| Event | When the parent receives it | What the demo parent does |
| --- | --- | --- |
| `tagSearchStarted(query)` | The picker browses the catalog or asks for a prefix | Sends the normalized query to a worker and returns the matching tags to the editor |
| `filesChanged(files)` | An add, removal, or clear changes batch membership | Logs the new count from the resulting file sequence |
| `uploadRequested(files)` | Save finds every file valid | Records the submitted batch and displays a summary |

For example, renaming the photo changes its row on every keystroke. The
parent receives the edited name with the eventual upload. A parent that only
cares how many files are queued can listen to `filesChanged` without handling
every keystroke. Try renaming a file and then removing it. The row title
reflects the edit, and the **Events** line reports the removal.

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

To follow the code, start with the operation you care about. For a rename,
look for the point where an editor hands text to the model. For selection,
look for who owns the old editor and its connections. For a change made
outside the editor, such as a parent updating a name, look for how the row
learns about it. Those questions expose the architectural differences even
when the three windows look much the same.

## Traditional MVC refreshes views from the controller

Build the widget tree with ordinary NimKit constructors. A plain `UploadModel`
holds the file records in a sequence. The controller keeps the selected index
and the set of fields touched in the current editor. It uses that index to find
both the record to edit and the row to refresh.

There are two controllers here. `UploadController` owns the editable batch
and the controls that operate on it. `UploadPageController` embeds that form,
listens for its events, and owns the search worker and submitted batches.
Inside the form, `UploadView` keeps handles to the controls, including a
`FileEditor` with the text fields and issue labels. The widget builder can
therefore concentrate on layout. The controller can update the label for
`ffName` directly without searching the view tree for “the name error”.

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
text field. If another command later changes a name programmatically, its
author must also arrange the appropriate widget updates. An assignment to
the plain model has no subscribers.

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

For **Special file**, the handler calls `c.model.setSpecial` to update the flags,
then refreshes every row. That covers the previously marked file as well as the
selected one. The handler makes the full update easy to trace, and each new
display of that flag needs a refresh call from the relevant edit paths.
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

Save uses the same selection path as a row click. It walks the files in list
order, selects the first invalid one, *then* sets `submitted` and refreshes
its issues. Setting that flag before switching would let the fresh editor
clear it. Once the batch passes, the controller emits `uploadRequested` and
the page handles the result. This division lets the page change what happens
after submission without changing how the editor validates an image.

## Reactive MVC binds the same widgets to the model

Keep the native row and editor constructors and connect their widgets to the
model with a `BindingScope`. Button actions and text edits call commands.
Changes from those commands and changes from elsewhere in the application
follow the same path from the model back to the widgets.

There are still ordinary constructors, a `ViewController`, and named commands.
What changes is the return trip after the command runs. In traditional MVC
the person writing the rename handler has to know about the sidebar. Here
the person building the sidebar declares what its title reads. You can add a
second display of the selected name by binding it to the same file. The code
that accepts a rename can stay as it is.

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

The **Special file** command widens the same idea to the whole collection.
It takes the current sequence, sets each flag from the requested ID and
checkbox state, then publishes the finished sequence if it changed. Both
affected rows can read the new flags without observing a moment when two
files are special. Their IDs are still in the same order, so the list builder
has no work to do. The parent receives a membership event when a file is
removed, but moving the special flag only updates observers of file data.

## DirectView gives each row and editor a key

Describe the tree with `viewBody`. Inside a control's body, `this` is the
ordinary NimKit widget. The demo's `bindFileText` helper connects the name
field to the same file and edit command as reactive MVC. DirectView ties the
binding's lifetime to the node that declares it.

```nim
TextField(identifier = "name"):
  this.bindFileText(form, id, ffName)
```

The model side of this line is exactly the one used by reactive MVC.
`bindFileText` supplies the file's item, the pair of file ID and field, and
the `readFileText` and `editFileText` callbacks. What changes is who owns the
widget side. In reactive MVC, `showEditor` makes a scope and registers the
widgets it just constructed. Here the field declaration gives DirectView
enough information to create or reuse the text field and own its binding.
The body describes ordinary NimKit controls, so a custom control can still
handle native input or call an existing controller.

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

The row and the editor both have identifiers you can use to find widgets.
Their keys serve a different purpose. Imagine deleting the photo at the top
of the list. The contract moves into the photo's old position. Matching on
file ID lets the contract row keep its own identity, including the remove
action that targets the contract. On the right, replacing the editor is
deliberate. Even if two files have identical names, moving from one ID to
the other starts a new editing session.

### Follow an action out of the tree

Here is the checkbox's action from `fileFields`. The widget supplies the new
checkbox state, and the action carries the ID from this editor.

```nim
this.onAction(store, id) do(this: Button, receiver: UploadStore, id: int):
  receiver.setSpecial(id, this.state == bsOn)
```

Reading the declaration alongside its `bindValue` shows both directions.
The action asks the store to make the change. The binding presents the flag
that the store accepted. The checkbox knows nothing about how many rows are
visible or which one used to be special. Those rows have their own bindings
to the affected records. Save works the same way at page level. Its button
calls `page.save()`, and a label bound to `page.status` displays the result.

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
