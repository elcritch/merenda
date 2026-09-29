type
  BackRefSetCore = object
    slots: seq[ptr BackRefSlot]

  BackRefSet*[T] = object ## Reverse registry owned by a target of type ``T``.
    core: BackRefSetCore

  BackRefSlot = object
    target: pointer
    backRefs: ptr BackRefSetCore
    index: int

  BackRef*[T] = object
    ## Non-owning reference cleared when its target's ``BackRefSet`` is destroyed.
    ## Its registration stays at a stable address when this value is returned,
    ## moved, or stored in a growing sequence. Access stays on the target's thread.
    slot: ptr BackRefSlot

proc removeSlot(backRefs: ptr BackRefSetCore, slot: ptr BackRefSlot) {.raises: [].} =
  if backRefs.isNil:
    return
  let last = backRefs.slots.pop()
  if last != slot:
    backRefs.slots[slot.index] = last
    last.index = slot.index

proc addSlot(backRefs: ptr BackRefSetCore, slot: ptr BackRefSlot) {.raises: [].} =
  if backRefs.isNil:
    return
  slot.index = backRefs.slots.len
  backRefs.slots.add slot

proc unregister(slot: var BackRefSlot) {.raises: [].} =
  if not slot.backRefs.isNil:
    slot.backRefs.removeSlot(addr slot)
  slot.target = nil
  slot.backRefs = nil

proc newSlot(): ptr BackRefSlot =
  when compileOption("threads"):
    result = createShared(BackRefSlot)
  else:
    result = create(BackRefSlot)

proc `=destroy`*[T](backRefs: var BackRefSet[T]) {.raises: [].} =
  while backRefs.core.slots.len > 0:
    let slot = backRefs.core.slots.pop()
    slot.target = nil
    slot.backRefs = nil
  `=destroy`(backRefs.core.slots)

proc `=copy`*[T](dest: var BackRefSet[T], src: BackRefSet[T]) {.error.}
proc `=sink`*[T](dest: var BackRefSet[T], src: BackRefSet[T]) {.error.}

proc `=destroy`*[T](backRef: BackRef[T]) {.raises: [].} =
  if not backRef.slot.isNil:
    backRef.slot[].unregister()
    when compileOption("threads"):
      deallocShared(backRef.slot)
    else:
      dealloc(backRef.slot)

proc `=wasMoved`*[T](backRef: var BackRef[T]) {.inline.} =
  backRef.slot = nil

proc `=copy`*[T](dest: var BackRef[T], src: BackRef[T]) {.raises: [].} =
  if dest.slot == src.slot:
    return
  `=destroy`(dest)
  `=wasMoved`(dest)
  if not src.slot.isNil and not src.slot.target.isNil:
    dest.slot = newSlot()
    dest.slot[] = src.slot[]
    dest.slot.backRefs.addSlot(dest.slot)

proc clear*[T](backRef: var BackRef[T]) {.inline.} =
  `=destroy`(backRef)
  `=wasMoved`(backRef)

proc set*[T, U](backRef: var BackRef[T], target: T, backRefs: var BackRefSet[U]) =
  if target.isNil:
    backRef.clear()
    return
  if backRef.slot.isNil:
    backRef.slot = newSlot()
  elif cast[pointer](target) == backRef.slot.target:
    return
  else:
    backRef.slot[].unregister()
  backRef.slot.target = cast[pointer](target)
  backRef.slot.backRefs = addr backRefs.core
  backRef.slot.backRefs.addSlot(backRef.slot)

proc `[]`*[T](backRef: BackRef[T]): T {.inline.} =
  if not backRef.slot.isNil:
    result = cast[T](backRef.slot.target)

proc isNil*[T](backRef: BackRef[T]): bool {.inline.} =
  backRef.slot.isNil or backRef.slot.target.isNil
