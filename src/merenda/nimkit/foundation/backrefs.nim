type
  BackRefSetCore = object
    target: pointer
    links: seq[ptr BackRefLink]

  BackRefSet*[T] = object
    ## Reverse registry owned by a target of type ``T``. The first non-nil
    ## registration binds it to that target for the registry's lifetime.
    core: BackRefSetCore

  BackRefLink = object
    backRefs: ptr BackRefSetCore
    index: int

  BackRef*[T] = ref object
    ## Non-owning reference cleared when its target's ``BackRefSet`` is destroyed.
    ## Copies share a stable registration. Setting or clearing a handle replaces
    ## that handle without changing its copies. Access stays on the target's thread.
    link: BackRefLink

proc `=destroy`(link: BackRefLink) {.raises: [].} =
  if not link.backRefs.isNil:
    let last = link.backRefs.links.pop()
    if link.index < link.backRefs.links.len:
      link.backRefs.links[link.index] = last
      last.index = link.index

# The registration must stay inside its original heap object.
proc `=copy`(dest: var BackRefLink, src: BackRefLink) {.error.}
proc `=dup`(src: BackRefLink): BackRefLink {.error.}
proc `=sink`(dest: var BackRefLink, src: BackRefLink) {.error.}

proc `=destroy`*[T](backRefs: var BackRefSet[T]) {.raises: [].} =
  while backRefs.core.links.len > 0:
    let link = backRefs.core.links.pop()
    link.backRefs = nil
  `=destroy`(backRefs.core.links)

proc `=copy`*[T](dest: var BackRefSet[T], src: BackRefSet[T]) {.error.}
proc `=sink`*[T](dest: var BackRefSet[T], src: BackRefSet[T]) {.error.}

proc clear*[T](backRef: var BackRef[T]) {.inline.} =
  backRef = nil

proc set*[T, U](backRef: var BackRef[T], target: T, backRefs: var BackRefSet[U]) =
  ## Bind a reference to a target. The registry must be owned by the target and
  ## remains bound to it for its lifetime, even after its last reference clears.
  ## Raises AssertionDefect if the registry is already bound to a different target.
  if target.isNil:
    backRef.clear()
    return
  let targetAddress = cast[pointer](target)
  doAssert backRefs.core.target.isNil or backRefs.core.target == targetAddress,
    "BackRefSet is already bound to another target"
  if backRef != nil and backRef.link.backRefs == addr backRefs.core:
    return
  let replacement = BackRef[T]()
  replacement.link.backRefs = addr backRefs.core
  replacement.link.index = backRefs.core.links.len
  backRefs.core.links.add addr replacement.link
  backRefs.core.target = targetAddress
  backRef = replacement

proc target*[T](backRef: BackRef[T]): T {.inline.} =
  ## Returns the target, or nil if the handle is empty or the target has died.
  if backRef != nil and not backRef.link.backRefs.isNil:
    result = cast[T](backRef.link.backRefs.target)

proc isNil*[T](backRef: BackRef[T]): bool {.inline.} =
  ## Tests the target's lifetime, including handles whose registration survives it.
  backRef == nil or backRef.link.backRefs.isNil
