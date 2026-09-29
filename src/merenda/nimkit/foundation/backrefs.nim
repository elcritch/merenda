type
  BackRefSetCore = object
    slots: seq[ptr BackRefSlot]

  BackRefSet*[T] = object ## Reverse registry owned by a target of type ``T``.
    core: BackRefSetCore

  BackRefSlot = object
    target: pointer
    backRefs: ptr BackRefSetCore
    index: int

  BackRef*[T] = ref object
    ## Non-owning reference cleared when its target's ``BackRefSet`` is destroyed.
    ## Copies share a stable registration. Setting or clearing a handle replaces
    ## that handle without changing its copies. Access stays on the target's thread.
    slot: BackRefSlot

proc `=destroy`(slot: BackRefSlot) {.raises: [].} =
  if not slot.backRefs.isNil:
    let last = slot.backRefs.slots.pop()
    if slot.index < slot.backRefs.slots.len:
      slot.backRefs.slots[slot.index] = last
      last.index = slot.index

# The registration must stay inside its original heap object.
proc `=copy`(dest: var BackRefSlot, src: BackRefSlot) {.error.}
proc `=dup`(src: BackRefSlot): BackRefSlot {.error.}
proc `=sink`(dest: var BackRefSlot, src: BackRefSlot) {.error.}

proc `=destroy`*[T](backRefs: var BackRefSet[T]) {.raises: [].} =
  while backRefs.core.slots.len > 0:
    let slot = backRefs.core.slots.pop()
    slot.target = nil
    slot.backRefs = nil
  `=destroy`(backRefs.core.slots)

proc `=copy`*[T](dest: var BackRefSet[T], src: BackRefSet[T]) {.error.}
proc `=sink`*[T](dest: var BackRefSet[T], src: BackRefSet[T]) {.error.}

proc clear*[T](backRef: var BackRef[T]) {.inline.} =
  backRef = nil

proc set*[T, U](backRef: var BackRef[T], target: T, backRefs: var BackRefSet[U]) =
  if target.isNil:
    backRef.clear()
    return
  if backRef != nil and cast[pointer](target) == backRef.slot.target:
    return
  let replacement = BackRef[T]()
  replacement.slot.target = cast[pointer](target)
  replacement.slot.backRefs = addr backRefs.core
  replacement.slot.index = backRefs.core.slots.len
  backRefs.core.slots.add addr replacement.slot
  backRef = replacement

proc target*[T](backRef: BackRef[T]): T {.inline.} =
  ## Returns the target, or nil if the handle is empty or the target has died.
  if backRef != nil:
    result = cast[T](backRef.slot.target)

proc isNil*[T](backRef: BackRef[T]): bool {.inline.} =
  ## Tests the target's lifetime, including handles whose registration survives it.
  backRef == nil or backRef.slot.target.isNil
