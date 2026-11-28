import std/[monotimes, os, sequtils, strutils, times, unittest]
import sigils/[core, reactive, threads]
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/foundation/mainthreadwork
import
  ../../examples/uploads/
    [upload_form_direct_demo, upload_form_mvc_demo, upload_form_reactive_mvc_demo]

type EventRecorder = ref object of Agent
  publications: int
  fileCounts: seq[int]
  queries: seq[string]
  uploads: seq[seq[UploadFile]]

proc published(recorder: EventRecorder, attrs: set[SigilAttributes]) {.slot.} =
  inc recorder.publications

proc filesChanged(recorder: EventRecorder, files: seq[UploadFile]) {.slot.} =
  recorder.fileCounts.add files.len

proc tagSearchStarted(recorder: EventRecorder, query: string) {.slot.} =
  recorder.queries.add query

proc uploadRequested(recorder: EventRecorder, files: seq[UploadFile]) {.slot.} =
  recorder.uploads.add files

template waitUntil(condition: untyped) =
  block:
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while not (condition) and getMonoTime() < deadline:
      # Worker results arrive through the Sigils thread queue.
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard drainMainThreadWork()
      sleep(1)
    check condition

proc newRecorder(page: UploadPage): EventRecorder =
  result = EventRecorder()
  connect(page.store.files, change, result, published)
  connect(page.store, filesChanged, result, filesChanged)
  connect(page.store, uploadRequested, result, uploadRequested)
  connect(page.form, tagSearchStarted, result, tagSearchStarted)

proc completeFile(store: UploadStore, id: int, category, subcategory: string) =
  store.setAltText(id, "Alt text for " & $id)
  store.setCategory(id, category)
  store.setSubcategory(id, subcategory)

suite "upload form demo":
  test "a typed edit updates only the selected file and publishes once":
    let page = newUploadPage(["one.png", "two.pdf"])
    let recorder = page.newRecorder()
    let view = page.newUploadView()
    defer:
      view.clear()
    discard drainMainThreadWork()
    let field = TextField(view.viewWithIdentifier("name"))
    require not field.isNil
    check field.stringValue == "one.png"

    field.stringValue = "renamed.png"
    emit field.textDidChange(field)
    discard drainMainThreadWork()
    check page.store.files[1].name == "renamed.png"
    check page.store.files[2].name == "two.pdf"
    check recorder.publications == 1
    check field.stringValue == "renamed.png"
    check ffName in page.form.touched{}

    let altText = TextField(view.viewWithIdentifier("alt-text"))
    require not altText.isNil
    page.store.setAltText(1, "Imported description")
    discard drainMainThreadWork()
    check altText.stringValue == "Imported description"
    check page.form.touched{} == {ffName}
    check recorder.publications == 2

    altText.stringValue = "Edited description"
    emit altText.textDidChange(altText)
    discard drainMainThreadWork()
    check page.store.files[1].altText == "Edited description"
    check page.store.files[2].altText == ""
    check page.form.touched{} == {ffName, ffAltText}
    check recorder.publications == 3

  test "selecting another file rebuilds its fields and resets form state":
    let page = newUploadPage(["one.png", "two.pdf"])
    let view = page.newUploadView()
    defer:
      view.clear()
    discard drainMainThreadWork()
    let first = TextField(view.viewWithIdentifier("name"))
    page.store.setName(1, "")
    page.form.touch(ffName)
    page.form.tagQuery <- "zz"
    page.form.submitted <- true
    check page.form.issues[ffName]{} == "A file name is required."

    page.store.selectFile(2)
    discard drainMainThreadWork()
    let second = TextField(view.viewWithIdentifier("name"))
    check second != first
    check second.stringValue == "two.pdf"
    check page.form.touched{} == {}
    check not page.form.submitted{}
    check page.form.tagQuery{} == ""
    for field in FileField:
      check page.form.issues[field]{} == ""

  test "a new category clears the dependent subcategory":
    let page = newUploadPage(["one.png"])
    page.form.chooseCategory("Photos")
    page.form.chooseSubcategory("Portrait")
    check page.store.files[1].subcategory == "Portrait"
    page.form.chooseSubcategory("Invoice")
    check page.store.files[1].subcategory == "Portrait"

    page.form.chooseCategory("Documents")
    check page.store.files[1].category == "Documents"
    check page.store.files[1].subcategory == ""
    check page.form.issues[ffSubcategory]{} == "Choose a subcategory."

  test "only one file can be special":
    let page = newUploadPage(["one.png", "two.pdf", "three.mp3"])
    let recorder = page.newRecorder()
    page.store.setSpecial(1, true)
    page.store.setSpecial(3, true)
    check not page.store.files[1].special
    check page.store.files[3].special
    check recorder.publications == 2
    page.store.setSpecial(3, false)
    for file in page.store.files{}:
      check not file.special

  test "tag queries reach the parent and only current results are shown":
    let page = newUploadPage(["one.png"])
    let recorder = page.newRecorder()
    let tags = page.form.tagController
    page.store.addTag(1, "night")
    check tags.selectedIdentifiers == @["night"]
    page.form.tagQuery <- "N"
    check recorder.queries == @["n"]
    waitUntil(page.form.suggestions{} == @["nature", "night", "nim"])
    var matches: seq[string]
    for item in tags.matches:
      matches.add item.identifier
    check matches == @["nature", "nim"]

    tags.query = "su"
    check page.form.tagQuery{} == "su"
    page.form.showSuggestions("n", @["nature"])
    check page.form.suggestions{} == @["nature", "night", "nim"]
    waitUntil(page.form.suggestions{} == @["summer", "sunset"])

    check tags.addTag(tagItem("sunset"))
    check page.store.files[1].tags == @["night", "sunset"]
    check tags.removeTag("night")
    check page.store.files[1].tags == @["sunset"]

  test "adding and removing files notifies the parent":
    let page = newUploadPage(["one.png", "two.pdf", "three.mp3"])
    let recorder = page.newRecorder()
    page.store.selectFile(2)
    page.store.removeFile(2)
    check page.store.selected{} == 3
    page.store.addPaths(["four.txt"])
    page.store.removeFile(99)
    check recorder.fileCounts == @[2, 3]

  test "save selects the first invalid file, then uploads every file":
    let page = newUploadPage(["one.png", "two.pdf"])
    let recorder = page.newRecorder()
    page.store.completeFile(1, "Photos", "Landscape")
    page.store.selectFile(1)
    page.save()
    check page.store.selected{} == 2
    check page.form.submitted{}
    check page.form.issues[ffCategory]{} == "Choose a category."
    check recorder.uploads.len == 0

    page.store.completeFile(2, "Documents", "Contract")
    page.store.addTag(2, "legal")
    page.save()
    require recorder.uploads.len == 1
    check recorder.uploads[0] == page.store.files{}
    check recorder.uploads[0][1].tags == @["legal"]

proc click(view: View, id: string) =
  let button = Button(view.viewWithIdentifier(id))
  require not button.isNil
  discard button.send(performClick(), ActionArgs(sender: button))

suite "reactive MVC upload form":
  test "the native list and editor follow model changes while keeping their widget identity":
    let controller = newReactiveUploadController(["one.png", "two.pdf"])
    defer:
      controller.teardown()
    let store = controller.page.store
    let view = controller.view
    let recorder = controller.page.newRecorder()
    let name = TextField(view.viewWithIdentifier("name"))
    let row = Button(view.viewWithIdentifier("file-1"))
    require not name.isNil and not row.isNil

    store.setName(1, "From the model")
    store.setCategory(1, "Photos")
    store.setSpecial(1, true)
    discard drainMainThreadWork()
    check name.stringValue == "From the model"
    check row.title == "From the model"
    check view.viewWithIdentifier("name") == name
    check view.viewWithIdentifier("file-1") == row
    check not view.viewWithIdentifier("subcategory-Portrait").isNil
    check Button(view.viewWithIdentifier("special")).state == bsOn
    check controller.page.form.touched{} == {}
    check recorder.publications == 3

    name.stringValue = ""
    emit name.textDidChange(name)
    discard drainMainThreadWork()
    check row.title == "Untitled file"
    check Label(view.viewWithIdentifier("issue-ffName")).stringValue.len > 0
    check recorder.publications == 4

    view.click("file-2")
    name.stringValue = "Stale edit"
    emit name.textDidChange(name)
    discard drainMainThreadWork()
    check store.files[1].name == ""
    check store.files[2].name == "two.pdf"
    check TextField(view.viewWithIdentifier("name")).stringValue == "two.pdf"
    check view.viewWithIdentifier("file-1") == row
    check row.state == bsOff
    check Label(view.viewWithIdentifier("issue-ffName")).stringValue == ""

    view.click("remove-2")
    discard drainMainThreadWork()
    check view.viewWithIdentifier("file-2").isNil
    check store.selected{} == 1
    check recorder.fileCounts == @[1]

suite "MVC upload form":
  test "edits stay with their file and a selection change resets validation":
    let page = newUploadPageController(["one.png", "two.pdf"])
    let view = page.view
    let recorder = EventRecorder()
    connect(page.form, uploadRequested, recorder, uploadRequested)
    connect(page.form, filesChanged, recorder, filesChanged)

    let first = TextField(view.viewWithIdentifier("name"))
    first.stringValue = ""
    emit first.textDidChange(first)
    check view.viewWithIdentifier("name") == first
    check Button(view.viewWithIdentifier("file-1")).title == "Untitled file"
    check Label(view.viewWithIdentifier("issue-ffName")).stringValue.len > 0
    view.click("save")
    check Label(view.viewWithIdentifier("issue-ffAltText")).stringValue.len > 0

    view.click("file-2")
    check TextField(view.viewWithIdentifier("name")).stringValue == "two.pdf"
    view.click("file-1")
    check TextField(view.viewWithIdentifier("name")).stringValue == ""
    check Label(view.viewWithIdentifier("issue-ffName")).stringValue == ""
    check Label(view.viewWithIdentifier("issue-ffAltText")).stringValue == ""

    for id in ["name", "alt-text"]:
      let field = TextField(view.viewWithIdentifier(id))
      field.stringValue = "sunset"
      emit field.textDidChange(field)
    view.click("category-Photos")
    view.click("subcategory-Portrait")
    view.click("category-Documents")
    check view.viewWithIdentifier("subcategory-Portrait").isNil
    check Label(view.viewWithIdentifier("issue-ffSubcategory")).stringValue.len > 0
    view.click("subcategory-Report")
    view.click("special")
    view.click("save")
    check recorder.uploads.len == 0
    check TextField(view.viewWithIdentifier("name")).stringValue == "two.pdf"
    check Label(view.viewWithIdentifier("issue-ffCategory")).stringValue.len > 0
    view.click("category-Media")
    view.click("subcategory-Audio")
    view.click("special")
    view.click("file-1")
    check Button(view.viewWithIdentifier("special")).state == bsOff
    view.click("save")
    require recorder.uploads.len == 1
    let files = recorder.uploads[0]
    require files.len == 2
    check files[0].name == "sunset" and files[0].altText == "sunset"
    check files[0].subcategory == "Report" and not files[0].special
    check files[1].subcategory == "Audio" and files[1].special
    check recorder.fileCounts.len == 0

  test "the parent handles membership and asynchronous tag search events":
    let page = newUploadPageController([])
    let view = page.view
    let recorder = EventRecorder()
    connect(page.form, filesChanged, recorder, filesChanged)
    connect(page.form, tagSearchStarted, recorder, tagSearchStarted)
    page.form.addPaths(["one.png", "two.pdf"])
    let tags = TagPicker(view.viewWithIdentifier("tags")).controller
    tags.query = " SU "
    check recorder.queries == @["", "su"]
    page.form.showSuggestions("old", @["surprise"])
    check not tags.matches.anyIt(it.identifier == "surprise")
    waitUntil(tags.matches.mapIt(it.identifier) == @["summer", "sunset"])
    check tags.addTag(tagItem("sunset"))
    view.click("file-2")
    let other = TagPicker(view.viewWithIdentifier("tags")).controller
    check other.query == "" and other.selectedIdentifiers.len == 0
    page.form.showSuggestions("su", @["surprise"])
    check not other.matches.anyIt(it.identifier == "surprise")
    view.click("file-1")
    check TagPicker(view.viewWithIdentifier("tags")).controller.selectedIdentifiers ==
      @["sunset"]
    view.click("remove-1")
    check TextField(view.viewWithIdentifier("name")).stringValue == "two.pdf"
    check Label(view.viewWithIdentifier("events")).stringValue.contains(
      "filesChanged: 1 file(s)"
    )
    view.click("cancel")
    check view.viewWithIdentifier("name").isNil
    page.form.addPaths(["three.txt"])
    check TextField(view.viewWithIdentifier("name")).stringValue == "three.txt"
    check recorder.fileCounts == @[2, 1, 0, 1]
