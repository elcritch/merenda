import std/unittest
import nutella/objc
import nutella/objc/assoc

type
  PersonState = object
    hasName: bool
    name: string
    score: int
    active: bool

  PersonStateRef = ref PersonState

  ContainerState = object
    person: NSObject

  ContainerStateRef = ref ContainerState

# ---------------------------------------------------------------------------
# NXKVCTestPerson
#   KVC-compatible ObjC methods:
#     name     -> NSObject (NSString)    setName:  -> NSObject (NSString)
#     score    -> NSInteger              setScore: -> NSInteger
#     isActive -> bool (BOOL, enc "B")
# ---------------------------------------------------------------------------

objcImpl:
  type NXKVCTestPerson = object of NSObject

  method init(self: var NXKVCTestPerson): NXKVCTestPerson =
    self = super(NXKVCTestPerson, self, init)
    if self.isNil:
      return
    setAssociatedRef(
      self, PersonStateRef(hasName: false, name: "", score: 0, active: false)
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
