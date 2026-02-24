import std/unittest
import nutella/objc
import nutella/objc/assoc

type
  PersonState = object
    hasName: bool
    name: string
    score: int
    active: bool
    ratio: cfloat
    distance: cdouble

  PersonStateRef = ref PersonState

  ContainerState = object
    person: NSObject

  ContainerStateRef = ref ContainerState

  KVOEvent = object
    keyPath: string
    hasOld: bool
    oldName: string
    hasNew: bool
    newName: string
    prior: bool
    context: pointer

  KVOStateRef = ref object
    events: seq[KVOEvent]

# ---------------------------------------------------------------------------
# NXKVCTestPerson
#   KVC-compatible ObjC methods:
#     name     -> NSObject (NSString)    setName:  -> NSObject (NSString)
#     score    -> NSInteger              setScore: -> NSInteger
#     isActive -> bool (BOOL, enc "B")
#     ratio    -> cfloat (enc "f")       setRatio: -> cfloat
#     distance -> cdouble (enc "d")      setDistance: -> cdouble
# ---------------------------------------------------------------------------

objcImpl:
  type NXKVCTestPerson = object of NSObject

  method init(self: var NXKVCTestPerson): NXKVCTestPerson =
    self = super(NXKVCTestPerson, self, init)
    if self.isNil:
      return
    setAssociatedRef(
      self,
      PersonStateRef(
        hasName: false, name: "", score: 0, active: false, ratio: 0.0'f32, distance: 0.0
      ),
    )
    result = self

  method dealloc(self: NXKVCTestPerson) =
    clearAssociatedRef[PersonStateRef](self)
    superDealloc(self)

  # KVC getter: "name" -> object ID (encoding @)
  method name(self: NXKVCTestPerson): ID =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if state.isNil or not state.hasName:
      return nil
    else:
      var boxed = boxNSObject(state.name)
      result = boxed.value
      boxed.value = nil

  # KVC setter: "setName:" <- NSObject
  method setName(self: NXKVCTestPerson, val: NSObject) =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if state.isNil:
      return
    if val.isNil:
      state.hasName = false
      state.name = ""
      return
    state.hasName = true
    state.name = unboxNSObject[string](val)

  # KVC getter: "score" -> cint (encoded as "i" by objcImpl)
  method score(self: NXKVCTestPerson): cint =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if state.isNil:
      return 0
    state.score.cint

  # KVC setter: "setScore:" <- cint
  method setScore(self: NXKVCTestPerson, val: cint) =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if not state.isNil:
      state.score = val.int

  # KVC getter: "isActive" -> bool (encoded as "B")
  method isActive(self: NXKVCTestPerson): bool =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if state.isNil:
      return false
    state.active

  # KVC setter: "setActive:" <- bool
  method setActive(self: NXKVCTestPerson, val: bool) =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if not state.isNil:
      state.active = val

  # KVC getter: "ratio" -> cfloat (encoded as "f")
  method ratio(self: NXKVCTestPerson): cfloat =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if state.isNil:
      return 0.0'f32
    state.ratio

  # KVC setter: "setRatio:" <- cfloat
  method setRatio(self: NXKVCTestPerson, val: cfloat) =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if not state.isNil:
      state.ratio = val

  # KVC getter: "distance" -> cdouble (encoded as "d")
  method distance(self: NXKVCTestPerson): cdouble =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if state.isNil:
      return 0.0
    state.distance

  # KVC setter: "setDistance:" <- cdouble
  method setDistance(self: NXKVCTestPerson, val: cdouble) =
    let state = getAssociatedRef[PersonStateRef](self, PersonStateRef)
    if not state.isNil:
      state.distance = val

# ---------------------------------------------------------------------------
# NXKVCTestContainer — holds a person for key-path tests
#   KVC-compatible ObjC methods:
#     person     -> NSObject   setPerson: -> NSObject
# ---------------------------------------------------------------------------

objcImpl:
  type NXKVCTestContainer = object of NSObject

  method init(self: var NXKVCTestContainer): NXKVCTestContainer =
    self = super(NXKVCTestContainer, self, init)
    if self.isNil:
      return
    setAssociatedRef(self, ContainerStateRef(person: NSObject(value: nil)))
    result = self

  method dealloc(self: NXKVCTestContainer) =
    clearAssociatedRef[ContainerStateRef](self)
    superDealloc(self)

  method person(self: NXKVCTestContainer): ID =
    let state = getAssociatedRef[ContainerStateRef](self, ContainerStateRef)
    if state.isNil:
      return nil
    elif state.person.isNil:
      return nil
    else:
      return state.person.value

  method setPerson(self: NXKVCTestContainer, val: NSObject) =
    let state = getAssociatedRef[ContainerStateRef](self, ContainerStateRef)
    if not state.isNil:
      state.person = val

# ---------------------------------------------------------------------------
# NXKVCTestTag — read-only property via "tag", no setter
# ---------------------------------------------------------------------------

objcImpl:
  type NXKVCTestTag = object of NSObject

  method init(self: var NXKVCTestTag): NXKVCTestTag =
    self = super(NXKVCTestTag, self, init)
    result = self

  method dealloc(self: NXKVCTestTag) =
    superDealloc(self)

  # Returns object ID — tests the "@"-encoding path
  method tag(self: NXKVCTestTag): ID =
    var boxed = boxNSObject("read-only-tag")
    result = boxed.value
    boxed.value = nil

# ---------------------------------------------------------------------------
# NXKVCTestObserver — receives KVO callbacks
# ---------------------------------------------------------------------------

objcImpl:
  type NXKVCTestObserver = object of NSObject

  method init(self: var NXKVCTestObserver): NXKVCTestObserver =
    self = super(NXKVCTestObserver, self, init)
    if self.isNil:
      return
    setAssociatedRef(self, KVOStateRef(events: @[]))
    result = self

  method dealloc(self: NXKVCTestObserver) =
    clearAssociatedRef[KVOStateRef](self)
    superDealloc(self)

  method observeValueForKeyPath(
      self: NXKVCTestObserver,
      keyPath: NSString,
      ofObject {.kw("ofObject").}: NSObject,
      change {.kw("change").}: NSDictionary[NSString, NSObject],
      context {.kw("context").}: pointer,
  ) =
    let state = getAssociatedRef[KVOStateRef](self, KVOStateRef)
    if state.isNil:
      return

    var evt = KVOEvent(
      keyPath: stringValue(keyPath),
      hasOld: false,
      oldName: "",
      hasNew: false,
      newName: "",
      prior: false,
      context: context,
    )

    if not change.isNil:
      if change.hasKey(nsString("notificationIsPrior")):
        evt.prior = unboxNSObject[bool](change[nsString("notificationIsPrior")])
      if change.hasKey(nsString("old")):
        let oldObj = change[nsString("old")]
        evt.hasOld = not oldObj.isNil
        if not oldObj.isNil:
          evt.oldName = unboxNSObject[string](oldObj)
      if change.hasKey(nsString("new")):
        let newObj = change[nsString("new")]
        evt.hasNew = not newObj.isNil
        if not newObj.isNil:
          evt.newName = unboxNSObject[string](newObj)

    state.events.add(evt)

proc kvoEvents(observer: NXKVCTestObserver): seq[KVOEvent] =
  let state = getAssociatedRef[KVOStateRef](observer, KVOStateRef)
  if state.isNil:
    return @[]
  state.events

proc clearKvoEvents(observer: NXKVCTestObserver) =
  let state = getAssociatedRef[KVOStateRef](observer, KVOStateRef)
  if state.isNil:
    return
  state.events.setLen(0)

# ===========================================================================
# Tests
# ===========================================================================

suite "Key-Value Coding":
  test "valueForKey on NSObject-returning getter (encoding @)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    p.setName(boxNSObject("Alice"))

    let val = valueForKey(p, "name")
    check(not val.isNil)
    check(unboxNSObject[string](val) == "Alice")

  test "setValueForKey on NSObject-accepting setter (encoding @)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)

    let newName = boxNSObject("Bob")
    setValueForKey(p, newName, "name")

    let stored = valueForKey(p, "name")
    check(unboxNSObject[string](stored) == "Bob")

  test "valueForKey on NSInteger-returning getter (encoding i)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    p.setScore(42.cint)

    let val = valueForKey(p, "score")
    check(not val.isNil)
    check(unboxNSObject[NSInteger](val) == 42.NSInteger)

  test "setValueForKey on NSInteger-accepting setter (encoding i)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)

    let scoreBox = boxNSObject(99)
    setValueForKey(p, scoreBox, "score")
    check(p.score() == 99.cint)

  test "valueForKey on bool-returning getter (encoding B) via isKey":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    p.setActive(true)

    # KVC tries "active", then "isActive" — "isActive" exists.
    let val = valueForKey(p, "active")
    check(not val.isNil)
    check(unboxNSObject[NSInteger](val) == 1.NSInteger)

  test "setValueForKey on bool-accepting setter via setActive:":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)

    let trueBox = boxNSObject(1)
    setValueForKey(p, trueBox, "active")
    check(p.isActive() == true)

  test "valueForKey on cfloat-returning getter (encoding f)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    p.setRatio(1.5'f32)

    let val = valueForKey(p, "ratio")
    check(not val.isNil)
    check(abs(unboxNSObject[cfloat](val) - 1.5'f32) < 0.0001'f32)

  test "setValueForKey on cfloat-accepting setter (encoding f)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)

    let ratioBox = boxNSObject(2.25'f32)
    setValueForKey(p, ratioBox, "ratio")
    check(abs(p.ratio() - 2.25'f32) < 0.0001'f32)

  test "valueForKey on cdouble-returning getter (encoding d)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    p.setDistance(123.75)

    let val = valueForKey(p, "distance")
    check(not val.isNil)
    check(abs(unboxNSObject[cdouble](val) - 123.75) < 0.0000001)

  test "setValueForKey on cdouble-accepting setter (encoding d)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)

    let distanceBox = boxNSObject(456.5)
    setValueForKey(p, distanceBox, "distance")
    check(abs(p.distance() - 456.5) < 0.0000001)

  test "valueForKey on read-only NSObject getter":
    var t = NXKVCTestTag.init()
    check(not t.isNil)

    let val = valueForKey(t, "tag")
    check(not val.isNil)
    check(unboxNSObject[string](val) == "read-only-tag")

  test "valueForKey with NSString key":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    p.setName(boxNSObject("NSStringKey"))

    let key = nsString("name")
    let val = valueForKey(p, key)
    check(not val.isNil)
    check(unboxNSObject[string](val) == "NSStringKey")

  test "valueForKey returns nil for unknown key":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    let val = valueForKey(p, "nonexistentKey")
    check(val.isNil)

  test "valueForKey on nil object returns nil":
    let nilObj = NSObject(value: nil)
    check(valueForKey(nilObj, "name").isNil)

  test "setValueForKey on nil object is a no-op":
    let nilObj = NSObject(value: nil)
    setValueForKey(nilObj, boxNSObject("ignored"), "name")

  test "valueForKey with empty key returns nil":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    check(valueForKey(p, "").isNil)

  test "setValueForKey ignores unknown key (no crash)":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    setValueForKey(p, boxNSObject("noop"), "doesNotExist")

  test "valueForKeyPath traverses two levels":
    var person = NXKVCTestPerson.init()
    check(not person.isNil)
    person.setName(boxNSObject("KeyPathValue"))

    var container = NXKVCTestContainer.init()
    check(not container.isNil)
    container.setPerson(person)

    let val = valueForKeyPath(container, "person.name")
    check(not val.isNil)
    check(unboxNSObject[string](val) == "KeyPathValue")

  test "setValueForKeyPath sets leaf at end of two-level path":
    var person = NXKVCTestPerson.init()
    check(not person.isNil)
    person.setName(boxNSObject("OldName"))

    var container = NXKVCTestContainer.init()
    check(not container.isNil)
    container.setPerson(person)

    setValueForKeyPath(container, boxNSObject("NewName"), "person.name")
    check(unboxNSObject[string](valueForKey(person, "name")) == "NewName")

  test "valueForKeyPath returns nil when intermediate is nil":
    var container = NXKVCTestContainer.init()
    check(not container.isNil)
    # person ivar is nil by default
    let val = valueForKeyPath(container, "person.name")
    check(val.isNil)

  test "valueForKeyPath on nil object returns nil":
    let nilObj = NSObject(value: nil)
    check(valueForKeyPath(nilObj, "person.name").isNil)

  test "dictionaryWithValuesForKeys returns correct values":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    p.setName(boxNSObject("DictPerson"))
    p.setScore(55.cint)

    let dict = dictionaryWithValuesForKeys(p, ["name", "score"])
    check(dict.len == 2)
    check(dict.hasKey(nsString("name")))
    check(dict.hasKey(nsString("score")))
    check(unboxNSObject[string](dict[nsString("name")]) == "DictPerson")
    check(unboxNSObject[NSInteger](dict[nsString("score")]) == 55.NSInteger)

  test "dictionaryWithValuesForKeys maps unknown key to nil":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)

    let dict = dictionaryWithValuesForKeys(p, ["name", "missing"])
    check(dict.len == 2)
    check(dict[nsString("missing")].isNil)

  test "setValuesForKeysWithDictionary applies all entries":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)

    var dict = nsDictionary[NSString, NSObject]()
    dict[nsString("name")] = boxNSObject("BulkSet")
    dict[nsString("score")] = boxNSObject(77)
    setValuesForKeysWithDictionary(p, dict)

    check(unboxNSObject[string](valueForKey(p, "name")) == "BulkSet")
    check(p.score() == 77.cint)

  test "KVO notifies old/new values on setValueForKey":
    var p = NXKVCTestPerson.init()
    var obs = NXKVCTestObserver.init()
    check(not p.isNil)
    check(not obs.isNil)

    p.setName(boxNSObject("Alice"))
    addObserver(p, obs, "name", {nsKVOOptionOld, nsKVOOptionNew}, cast[pointer](0x1234))
    clearKvoEvents(obs)

    setValueForKey(p, boxNSObject("Bob"), "name")
    let events = kvoEvents(obs)
    check(events.len == 1)
    check(events[0].keyPath == "name")
    check(events[0].hasOld)
    check(events[0].oldName == "Alice")
    check(events[0].hasNew)
    check(events[0].newName == "Bob")
    check(events[0].context == cast[pointer](0x1234))

  test "KVO initial option sends immediate callback":
    var p = NXKVCTestPerson.init()
    var obs = NXKVCTestObserver.init()
    check(not p.isNil)
    check(not obs.isNil)

    p.setName(boxNSObject("InitialValue"))
    addObserver(p, obs, "name", {nsKVOOptionInitial, nsKVOOptionNew})
    let events = kvoEvents(obs)
    check(events.len == 1)
    check(events[0].keyPath == "name")
    check(events[0].hasNew)
    check(events[0].newName == "InitialValue")

  test "KVO prior option sends prior then final":
    var p = NXKVCTestPerson.init()
    var obs = NXKVCTestObserver.init()
    check(not p.isNil)
    check(not obs.isNil)

    p.setName(boxNSObject("Before"))
    addObserver(p, obs, "name", {nsKVOOptionPrior, nsKVOOptionOld, nsKVOOptionNew})
    clearKvoEvents(obs)

    setValueForKey(p, boxNSObject("After"), "name")
    let events = kvoEvents(obs)
    check(events.len == 2)
    check(events[0].prior == true)
    check(events[0].hasOld)
    check(events[0].oldName == "Before")
    check(events[1].prior == false)
    check(events[1].hasOld)
    check(events[1].oldName == "Before")
    check(events[1].hasNew)
    check(events[1].newName == "After")

  test "KVO removeObserver stops notifications":
    var p = NXKVCTestPerson.init()
    var obs = NXKVCTestObserver.init()
    check(not p.isNil)
    check(not obs.isNil)

    addObserver(p, obs, "name", {nsKVOOptionNew})
    removeObserver(p, obs, "name")
    setValueForKey(p, boxNSObject("NoNotify"), "name")
    check(kvoEvents(obs).len == 0)

  test "ObjC KVO selectors are present on NSObject":
    var p = NXKVCTestPerson.init()
    check(not p.isNil)
    check(p.respondsToSelector("addObserver:forKeyPath:options:context:"))
    check(p.respondsToSelector("removeObserver:forKeyPath:context:"))
    check(p.respondsToSelector("removeObserver:forKeyPath:"))
    check(p.respondsToSelector("willChangeValueForKey:"))
    check(p.respondsToSelector("didChangeValueForKey:"))
