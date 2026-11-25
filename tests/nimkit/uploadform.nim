import std/[monotimes, os, times, unittest]
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/foundation/mainthreadwork
import ../../examples/upload_form_demo

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
    page.store.addTag(1, "night")
    page.form.tagQuery <- "N"
    check recorder.queries == @["n"]
    waitUntil(page.form.suggestions{}.len > 0)
    check page.form.suggestions{} == @["nature", "nim"]

    page.form.tagQuery <- "su"
    check page.form.suggestions{}.len == 0
    page.form.showSuggestions("n", @["nature"])
    check page.form.suggestions{}.len == 0
    waitUntil(page.form.suggestions{} == @["summer", "sunset"])

    page.form.addTag("sunset")
    check page.store.files[1].tags == @["night", "sunset"]
    check page.form.tagQuery{} == ""
    check page.form.suggestions{}.len == 0

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
