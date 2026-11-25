import std/[monotimes, os, times, unittest]
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/directviews/dsl
import merenda/nimkit/foundation/mainthreadwork

type LifetimeOwner = ref object of Responder
  calls, draws: int
  nested: Sigil[int]
  host: DirectView
  root: BackRef[DirectNode]
  rootAliveAfterClear: bool

proc lifetimeBody(context: DirectNode, owner: LifetimeOwner, value: int) =
  inc owner.draws
  context.viewBody:
    Button($value):
      this.onAction(owner, value) do(this: Button, receiver: LifetimeOwner, amount: int):
        receiver.calls += amount

proc observedLifetime(context: DirectNode, owner: LifetimeOwner, input: Sigil[int]) =
  context.bindBody(input, owner, lifetimeBody)

proc conditionalBody(context: DirectNode, owner: LifetimeOwner, visible: bool) =
  context.viewBody:
    if visible:
      component(observedLifetime, owner, owner.nested)
    else:
      Button("gone")

proc conditionalLifetime(
    context: DirectNode, owner: LifetimeOwner, input: Sigil[bool]
) =
  context.bindBody(input, owner, conditionalBody)

proc clearOnChange(context: DirectNode, owner: LifetimeOwner, shouldClear: bool) =
  if shouldClear:
    owner.host.clear()
    owner.rootAliveAfterClear = not owner.root.isNil
  else:
    context.viewBody:
      Button("first")

proc clearingComponent(context: DirectNode, owner: LifetimeOwner, input: Sigil[bool]) =
  context.bindBody(input, owner, clearOnChange)

proc `checkedSpacing=`(stack: StackView, value: int) =
  if value < 0:
    raise newException(ValueError, "negative spacing")
  stack.spacing = value.float32

proc configuredBody(context: DirectNode, owner: LifetimeOwner, spacing: int) =
  context.viewBody:
    owner.host.checkedSpacing = spacing
    component(observedLifetime, owner, owner.nested)

proc settleTitle(button: Button, expected: string) =
  let deadline = getMonoTime() + initDuration(seconds = 60)
  while button.title != expected and getMonoTime() < deadline:
    discard drainMainThreadWork()
    if button.title != expected:
      sleep(1)
  check button.title == expected

suite "direct view activation and lifetime":
  test "a nested setter failure preserves its error and permits clear and rebuild":
    let host = newDirectView()
    let owner = LifetimeOwner(host: host, nested: newSigil(1))
    proc render(spacing: int) =
      host.viewBody:
        component(configuredBody, owner, spacing)

    render(4)
    let old = Button(host.arrangedSubviews[0])
    owner.nested <- 2
    var message = ""
    try:
      render(-1)
    except ValueError as error:
      message = error.msg
    check message == "negative spacing"
    host.clear()
    check host.arrangedSubviews.len == 0
    check owner.nested.subcriptions.len == 0
    render(6)
    discard drainMainThreadWork()
    check old.title == "1"
    discard old.send(performClick(), ActionArgs(sender: old))
    check owner.calls == 0
    require host.arrangedSubviews.len == 1
    let current = Button(host.arrangedSubviews[0])
    check current != old
    check current.title == "2"
    discard current.send(performClick(), ActionArgs(sender: current))
    check owner.calls == 2

  test "a late duplicate key permits clearing visited and unvisited mounts":
    let host = newDirectView()
    let owner = LifetimeOwner(nested: newSigil(1))
    proc render(keys: seq[string]) =
      host.viewBody:
        VStack:
          for key in keys:
            keyed(key):
              component(observedLifetime, owner, owner.nested)

    render(@["a", "b"])
    let oldStack = StackView(host.arrangedSubviews[0])
    let removed = Button(oldStack.arrangedSubviews[1])
    owner.nested <- 3
    expect ValueError:
      render(@["a", "c", "a"])
    host.clear()
    check oldStack.arrangedSubviews.len == 0
    check owner.nested.subcriptions.len == 0
    render(@["b"])
    discard drainMainThreadWork()
    discard removed.send(performClick(), ActionArgs(sender: removed))
    check removed.title == "1"
    check owner.calls == 0
    require host.arrangedSubviews.len == 1
    let stack = StackView(host.arrangedSubviews[0])
    require stack.arrangedSubviews.len == 1
    check Button(stack.arrangedSubviews[0]).title == "3"

  test "hiding retained content keeps observation while clear retires queued work":
    let owner = LifetimeOwner()
    let input = newSigil(1)
    let host = newDirectView()
    host.viewBody:
      component(observedLifetime, owner, input)
    let oldButton = Button(host.arrangedSubviews[0])
    check input.subcriptions.len == 1

    host.hidden = true
    input <- 2
    oldButton.settleTitle("2")
    check input.subcriptions.len == 1

    input <- 3
    host.clear()
    check input.subcriptions.len == 0
    check host.arrangedSubviews.len == 0
    discard drainMainThreadWork()
    check oldButton.title == "2"
    discard oldButton.send(performClick(), ActionArgs(sender: oldButton))
    check owner.calls == 0

    host.hidden = false
    host.viewBody:
      component(observedLifetime, owner, input)
    let newButton = Button(host.arrangedSubviews[0])
    check newButton != oldButton
    check newButton.title == "3"
    check input.subcriptions.len == 1
    discard newButton.send(performClick(), ActionArgs(sender: newButton))
    check owner.calls == 3
    host.clear()
    check input.subcriptions.len == 0

  test "explicit suspension retains content and coalesces current state":
    let
      owner = LifetimeOwner()
      input = newSigil(1)
      host = newDirectView()
    host.viewBody:
      component(observedLifetime, owner, input)
    let button = Button(host.arrangedSubviews[0])
    check owner.draws == 1
    input <- 2
    host.suspendUpdates()
    host.suspendUpdates()
    input <- 3
    input <- 4
    discard drainMainThreadWork()
    host.flushBindings()
    check button.title == "1"
    check owner.draws == 1
    check input.subcriptions.len == 1
    expect ValueError:
      host.viewBody:
        Button("should not be mounted")
    host.resumeUpdates()
    check host.arrangedSubviews[0] == button
    check button.title == "4"
    check owner.draws == 2
    host.resumeUpdates()
    discard drainMainThreadWork()
    check owner.draws == 2
    host.clear()
    check input.subcriptions.len == 0

  test "clear while suspended cancels updates and remains suspended":
    let
      owner = LifetimeOwner()
      input = newSigil(1)
      host = newDirectView()
    host.viewBody:
      component(observedLifetime, owner, input)
    let button = Button(host.arrangedSubviews[0])
    host.suspendUpdates()
    input <- 2
    host.clear()
    check input.subcriptions.len == 0
    discard drainMainThreadWork()
    check button.title == "1"
    expect ValueError:
      host.viewBody:
        component(observedLifetime, owner, input)
    host.resumeUpdates()
    host.viewBody:
      component(observedLifetime, owner, input)
    check Button(host.arrangedSubviews[0]).title == "2"
    host.clear()

  test "resume retires stale descendants before their pending updates":
    let
      owner = LifetimeOwner(nested: newSigil(1))
      show = newSigil(true)
      host = newDirectView()
    host.viewBody:
      component(conditionalLifetime, owner, show)
    let oldButton = Button(host.arrangedSubviews[0])
    check owner.draws == 1
    host.suspendUpdates()
    owner.nested <- 2
    show <- false
    host.resumeUpdates()
    check Button(host.arrangedSubviews[0]).title == "gone"
    check oldButton.title == "1"
    check owner.draws == 1
    check owner.nested.subcriptions.len == 0
    discard drainMainThreadWork()
    check oldButton.title == "1"
    host.clear()
    check show.subcriptions.len == 0

  test "suspension during composition fails without changing the scope":
    let
      owner = LifetimeOwner()
      input = newSigil(1)
      host = newDirectView()
    discard host.beginUpdate()
    expect ValueError:
      host.suspendUpdates()
    host.endUpdate()
    host.viewBody:
      component(observedLifetime, owner, input)
    input <- 2
    Button(host.arrangedSubviews[0]).settleTitle("2")
    host.clear()

  test "resume tolerates a pending child clearing its siblings":
    let
      host = newDirectView()
      owner = LifetimeOwner(host: host, nested: newSigil(1))
      clearSignal = newSigil(false)
    block:
      let root = host.beginUpdate()
      owner.root.target = root
      host.endUpdate()
    host.viewBody:
      component(clearingComponent, owner, clearSignal)
      component(observedLifetime, owner, owner.nested)
    let second = Button(host.arrangedSubviews[1])
    host.suspendUpdates()
    clearSignal <- true
    owner.nested <- 2
    host.resumeUpdates()
    check owner.rootAliveAfterClear
    check owner.root.isNil
    check host.arrangedSubviews.len == 0
    check second.title == "1"
    check owner.nested.subcriptions.len == 0
    check clearSignal.subcriptions.len == 0
    discard drainMainThreadWork()
    check second.title == "1"
