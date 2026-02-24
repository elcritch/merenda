import ./runtime
import ../objc/assoc

var controllerMarkersReady {.threadvar.}: bool
var NSNoSelectionMarker* {.threadvar.}: ID
var NSMultipleValuesMarker* {.threadvar.}: ID
var NSNotApplicableMarker* {.threadvar.}: ID

proc ensureControllerMarkers() =
  if controllerMarkersReady:
    return
  NSNoSelectionMarker = retainId(ns("NSNoSelectionMarker").value)
  NSMultipleValuesMarker = retainId(ns("NSMultipleValuesMarker").value)
  NSNotApplicableMarker = retainId(ns("NSNotApplicableMarker").value)
  controllerMarkersReady = true

proc NSIsControllerMarker*(obj: ID): bool =
  ensureControllerMarkers()
  obj == NSNoSelectionMarker or obj == NSMultipleValuesMarker or
    obj == NSNotApplicableMarker

type NSControllerStorage = ref object
  editors: seq[ID]

proc editorStorage(self: NSObject): NSControllerStorage =
  if self.isNil:
    return nil
  result = getAssociatedRef(self, NSControllerStorage)
  if result.isNil:
    new(result)
    result.editors = @[]
    setAssociatedRef(self, result)

objcImpl:
  type NSController* = object of NSObject

  method init*(self: var NSController): NSController =
    result =
      asType[NSController](callSuperIdFrom(NSController, self, @selector("init")))
    if result.isNil:
      return
    ensureControllerMarkers()
    discard editorStorage(result)

  method dealloc(self: NSController) {.used.} =
    let store = getAssociatedRef(self, NSControllerStorage)
    if not store.isNil:
      clearOwnedIds(store.editors)
    clearAssociatedRef[NSControllerStorage](self)
    clearIvarRefs(self)
    discard callSuperIdFrom(NSController, self, getSelector("dealloc"))

  method initWithCoder*(self: var NSController, coder: ID): NSController =
    discard coder
    result = self.init()

  method encodeWithCoder*(self: NSController, coder: ID) =
    discard self
    discard coder

  method commitEditing*(self: NSController): bool =
    if self.isNil:
      return true
    let store = editorStorage(self)
    if store.isNil or store.editors.len == 0:
      return true
    let commitSel = getSelector("commitEditing")
    for editor in store.editors:
      let committed = cast[proc(obj: ID, op: SEL): bool {.cdecl, varargs.}](objc_msgSend)(
        editor, commitSel
      )
      if not committed:
        return false
    true

  method discardEditing*(self: NSController) =
    if self.isNil:
      return
    let store = editorStorage(self)
    if store.isNil:
      return
    let discardSel = getSelector("discardEditing")
    for editor in store.editors:
      cast[proc(obj: ID, op: SEL): void {.cdecl, varargs.}](objc_msgSend)(
        editor, discardSel
      )

  method isEditing*(self: NSController): bool =
    if self.isNil:
      return false
    let store = editorStorage(self)
    if store.isNil:
      return false
    store.editors.len > 0

  method objectDidBeginEditing*(self: NSController, editor: ID) =
    if self.isNil or editor.isNil:
      return
    let store = editorStorage(self)
    if store.isNil:
      return
    store.editors.add(retainId(editor))

  method objectDidEndEditing*(self: NSController, editor: ID) =
    if self.isNil or editor.isNil:
      return
    let store = editorStorage(self)
    if store.isNil:
      return
    var idx = 0
    while idx < store.editors.len:
      if store.editors[idx] == editor:
        removeOwnedIdAt(store.editors, idx)
      else:
        inc idx

proc new*(t: typedesc[NSController]): NSController =
  var allocated = NSController.alloc()
  result = initOwned(move(allocated))

ensureControllerMarkers()
