type
  BackRefSetCore = object
    slots: seq[ptr BackRefSlot]

  BackRefSet*[T] = object ## Reverse registry owned by a target of type ``T``.
    core: BackRefSetCore

  BackRefSlot = object
    target: pointer
    backRefs: ptr BackRefSetCore

  BackRef*[T] = object
    ## Non-owning reference cleared when its target's ``BackRefSet`` is destroyed.
    slot: BackRefSlot

proc removeSlot(backRefs: ptr BackRefSetCore, slot: ptr BackRefSlot) {.raises: [].} =
  if backRefs.isNil:
    return
  for index in 0 ..< backRefs.slots.len:
    if backRefs.slots[index] == slot:
      backRefs.slots.delete(index)
      return

proc addSlot(backRefs: ptr BackRefSetCore, slot: ptr BackRefSlot) {.raises: [].} =
  if backRefs.isNil:
    return
  for registered in backRefs.slots:
    if registered == slot:
      return
  backRefs.slots.add slot

proc replaceSlot(
    backRefs: ptr BackRefSetCore, oldSlot, newSlot: ptr BackRefSlot
) {.raises: [].} =
  if backRefs.isNil:
    return
  for index in 0 ..< backRefs.slots.len:
    if backRefs.slots[index] == oldSlot:
      backRefs.slots[index] = newSlot
      return
  backRefs.addSlot(newSlot)

proc unregister(slot: var BackRefSlot) {.raises: [].} =
  if not slot.backRefs.isNil:
    slot.backRefs.removeSlot(addr slot)
  slot.target = nil
  slot.backRefs = nil

proc `=destroy`*[T](backRefs: var BackRefSet[T]) {.raises: [].} =
  while backRefs.core.slots.len > 0:
    let slot = backRefs.core.slots.pop()
    slot.target = nil
    slot.backRefs = nil
  `=destroy`(backRefs.core.slots)

proc `=copy`*[T](dest: var BackRefSet[T], src: BackRefSet[T]) {.error.}
proc `=sink`*[T](dest: var BackRefSet[T], src: BackRefSet[T]) {.error.}

proc `=destroy`*[T](backRef: var BackRef[T]) {.raises: [].} =
  backRef.slot.unregister()

proc `=wasMoved`*[T](backRef: var BackRef[T]) {.inline.} =
  backRef.slot = BackRefSlot()

proc `=copy`*[T](dest: var BackRef[T], src: BackRef[T]) {.raises: [].} =
  if cast[pointer](addr dest) == cast[pointer](unsafeAddr src):
    return
  dest.slot.unregister()
  dest.slot = src.slot
  if not dest.slot.backRefs.isNil:
    dest.slot.backRefs.addSlot(addr dest.slot)

proc `=sink`*[T](dest: var BackRef[T], src: BackRef[T]) {.raises: [].} =
  dest.slot.unregister()
  dest.slot = src.slot
  if not dest.slot.backRefs.isNil:
    dest.slot.backRefs.replaceSlot(unsafeAddr src.slot, addr dest.slot)
  cast[ptr BackRef[T]](unsafeAddr src)[].slot = BackRefSlot()

proc clear*[T](backRef: var BackRef[T]) {.inline.} =
  backRef.slot.unregister()

proc set*[T, U](backRef: var BackRef[T], target: T, backRefs: var BackRefSet[U]) =
  if cast[pointer](target) == backRef.slot.target:
    return
  backRef.slot.unregister()
  if target.isNil:
    return
  backRef.slot.target = cast[pointer](target)
  backRef.slot.backRefs = addr backRefs.core
  backRef.slot.backRefs.addSlot(addr backRef.slot)

proc `[]`*[T](backRef: BackRef[T]): T {.inline.} =
  result = cast[T](backRef.slot.target)

proc isNil*[T](backRef: BackRef[T]): bool {.inline.} =
  backRef.slot.target.isNil
