## ARC back-reference behavior shared by the NimKit test runner.
import std/unittest

import merenda/nimkit
import merenda/nimkit/responder/responders as nimkitResponders
import merenda/nimkit/view/[viewbase, viewconstraints]

static:
  doAssert compileOption("mm", "arc") or compileOption("mm", "orc") or
    compileOption("mm", "atomicArc")

type
  IntrinsicLifetimeView = ref object of View
  RegistryOwner = ref object
    first, second: BackRefSet[RegistryOwner]

  ActionReceiver = ref object of Responder
    calls: int

static:
  doAssert not compiles(
    block:
      proc withCapture(receiver: Responder) =
        var calls = 0
        let handler = proc(receiver: Responder, sender: DynamicAgent) {.closure.} =
          inc calls
        discard newActionTarget(actionSelector("test.rejectCapture"), receiver, handler)

      withCapture(newResponder())
  )

protocol IntrinsicLifetimeLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: IntrinsicLifetimeView): IntrinsicSize =
    initIntrinsicSize(120, 30)

proc newIntrinsicLifetimeView(): IntrinsicLifetimeView =
  result = IntrinsicLifetimeView()
  initViewFields(result, rect(0, 0, 120, 30))
  result.autoresizingMaskConstraints = false
  discard result.withProtocol(IntrinsicLifetimeLayout)

proc observe(view: View): BackRef[View] =
  result.target = view

suite "NimKit ARC back references":
  test "action adapters copy explicit context and release their receiver":
    let button = newButton("Run")
    let action = actionSelector("test.contextReceiver")
    var observed: BackRef[ActionReceiver]
    block:
      let receiver = ActionReceiver()
      initResponder(receiver)
      observed.target = receiver
      var amount = 3
      button.target = newActionTarget(action, receiver, amount) do(
        receiver: ActionReceiver, context: int, sender: DynamicAgent
      ):
        check sender of Button
        receiver.calls += context
      amount = 8
      button.action = action
      check button.sendAction()
      check receiver.calls == 3
    check observed.isNil
    check button.sendAction()

  test "non-capturing action adapters do not retain their receiver":
    let button = newButton("Run")
    var observed: BackRef[ActionReceiver]
    block:
      let receiver = ActionReceiver()
      initResponder(receiver)
      observed{} = receiver
      let action = actionSelector("test.explicitReceiver")
      button.target = newActionTarget(action, receiver) do(
        receiver: ActionReceiver, sender: DynamicAgent
      ):
        check sender of Button
        inc receiver.calls
      button.action = action
      check button.sendAction()
      check receiver.calls == 1
    check observed.isNil
    check button.target() of ActionAdapter
    check not (button.target() of ClosureTarget)
    check button.sendAction()
    button.target = nil
    check button.target().isNil

  test "action target copies retain callbacks and switch ownership independently":
    var storage, copied: ActionTarget
    var observed: BackRef[Responder]
    block:
      let callback = newActionTarget(actionSelector("test.sharedStorage")) do(
        sender: DynamicAgent
      ):
        discard sender
      observed{} = Responder(callback)
      storage{} = callback
      copied = storage
    check not observed.isNil
    expect ValueError:
      storage{} = DynamicAgent()
    check storage{} == observed{}
    storage{} = Responder(nil)
    check storage{}.isNil
    check copied{} == observed{}
    copied{} = nil
    check observed.isNil

  test "dereferencing returns the target or nil after it is released":
    var reference: BackRef[View]
    var retained: View
    check reference{}.isNil
    block:
      let view = newView()
      reference{} = view
      check reference{} == view
      retained = reference{}
      check retained == view
    check reference{} == retained
    retained = nil
    check reference{}.isNil
    reference.clear()
    check reference{}.isNil

  test "empty action targets and typed nil assignments are safe":
    let
      button = newButton("Empty")
      cell = newActionCell()
      item = newMenuItem("Empty")
    var
      menuModel: MenuItemModel
      matrixModel: MatrixItemModel
      emptyResponder: Responder
      emptyClosure: ClosureTarget
      emptyAdapter: ActionAdapter
    check button.target().isNil
    check cell.target().isNil
    check item.target().isNil
    check menuModel.target().isNil
    check matrixModel.target().isNil
    button.target = emptyResponder
    item.target = emptyResponder
    button.target = emptyClosure
    item.target = emptyClosure
    cell.setTarget(emptyClosure)
    button.target = emptyAdapter
    item.target = emptyAdapter
    cell.setTarget(emptyAdapter)
    menuModel.target = emptyAdapter
    matrixModel.target = emptyAdapter
    menuModel.target = emptyClosure
    matrixModel.target = emptyClosure
    check button.target().isNil
    check cell.target().isNil
    check item.target().isNil
    check menuModel.target().isNil
    check matrixModel.target().isNil

  test "nil responder assignment clears a window owner safely":
    let view = newView()
    block:
      let window = newWindow("Back-reference nil owner")
      view.setWindowOwner(window)
      check view.windowBacklink() == Responder(window)
      var empty: Responder
      view.setWindowOwner(empty)
      check view.windowBacklink().isNil
      window.close()

  test "base and derived references share the responder registry":
    var base: BackRef[Responder]
    var derived: BackRef[View]
    block:
      let view = newView()
      base.target = Responder(view)
      derived.target = view
      check base{} == Responder(view)
      check derived{} == view
    check base.isNil
    check derived.isNil

  test "a registry stays bound to its first target after its last link is cleared":
    let
      first = RegistryOwner()
      other = RegistryOwner()
    var reference: BackRef[RegistryOwner]
    reference.set(first, first.first)
    reference.clear()
    expect AssertionDefect:
      reference.set(other, first.first)
    check reference.isNil
    reference.set(first, first.first)
    check reference{} == first
    expect AssertionDefect:
      reference.set(other, first.first)
    check reference{} == first

  test "a reference can switch registries for the same target":
    var reference, copy: BackRef[RegistryOwner]
    block:
      let target = RegistryOwner()
      reference.set(target, target.first)
      copy = reference
      reference.set(target, target.second)
      check reference{} == target
      check copy{} == target
      reference.clear()
      check copy{} == target
    check copy.isNil

  test "returned copied and moved back references clear independently":
    var original, copied, moved: BackRef[View]

    block:
      let target = newView()
      original = observe(target)
      copied = original
      moved = move(original)

      check original.isNil
      check copied{} == target
      check moved{} == target

      original = copied
      original = original
      copied.clear()
      check copied.isNil
      check original{} == target
      check moved{} == target

    check original.isNil
    check copied.isNil
    check moved.isNil

  test "copied back references can be rebound independently":
    var original, copied: BackRef[View]

    block:
      let firstTarget = newView()
      original = observe(firstTarget)
      copied = original

      block:
        let secondTarget = newView()
        original.target = secondTarget
        check original{} == secondTarget
        check copied{} == firstTarget

      check original.isNil
      check original{}.isNil
      check copied{} == firstTarget

      original.target = firstTarget
      copied.target = nil
      check copied.isNil
      check copied{}.isNil
      check original{} == firstTarget

    check original.isNil
    check copied.isNil

  test "dropping the last copied handle unregisters its shared link":
    let target = newView()
    var survivor: BackRef[View]
    block:
      var original = observe(target)
      var copied = original
      survivor = observe(target)
      original.clear()
      check copied{} == target
      copied.clear()
    # Removing the earlier link must update the moved link's registry index.
    survivor.clear()
    check survivor.isNil

  test "back references remain registered through sequence growth and deletion":
    var references, copied: seq[BackRef[View]]

    block:
      let target = newView()
      for index in 0 ..< 257:
        references.add observe(target)
      copied = references
      references.delete(13)
      references[17].clear()
      references[17].target = target

      check references.len == 256
      check copied.len == 257
      for reference in references:
        check reference{} == target
      for reference in copied:
        check reference{} == target

    for reference in references:
      check reference.isNil
    for reference in copied:
      check reference.isNil

  test "view back links do not retain a destroyed superview":
    let child = newView(frame = rect(20, 30, 80, 40))

    block:
      let parent = newView(frame = rect(0, 0, 200, 160))
      parent.addSubview(child)

      check child.superview == parent
      check nimkitResponders.nextResponder(Responder(child)) == Responder(parent)

    check child.superview.isNil
    check nimkitResponders.nextResponder(Responder(child)).isNil

  test "view back links do not retain a destroyed window":
    let content = newView(frame = rect(0, 0, 240, 160))

    block:
      let window = newWindow("Back link", frame = rect(0, 0, 240, 160))
      window.setAutorecalculatesKeyViewLoop(false)
      window.setContentView(content)

      check content.window == Responder(window)
      check nimkitResponders.nextResponder(Responder(content)) == Responder(window)

    check content.window.isNil
    check nimkitResponders.nextResponder(Responder(content)).isNil

  test "laid out standalone trees release their cached views":
    var rootRef, branchRef, leafRef: BackRef[View]

    block:
      let
        root = newView(frame = rect(0, 0, 240, 160))
        branch = newView(frame = rect(10, 10, 120, 80))
        leaf = newView(frame = rect(5, 5, 40, 20))
      rootRef.target = root
      branchRef.target = branch
      leafRef.target = leaf
      branch.addSubview(leaf)
      root.addSubview(branch)
      root.layoutSubtreeIfNeeded()

      check root.layoutInputGeneration() > 0
      check root.generatedLayoutInputs().len > 0
      check leaf.frame == rect(5, 5, 40, 20)

    check rootRef.isNil
    check branchRef.isNil
    check leafRef.isNil

  test "laid out children do not retain a destroyed parent":
    let child = newView(frame = rect(20, 30, 80, 40))
    var parentRef: BackRef[View]

    block:
      let parent = newView(frame = rect(0, 0, 200, 160))
      parentRef.target = parent
      parent.addSubview(child)
      parent.layoutSubtreeIfNeeded()

      check parent.generatedLayoutInputs().len > 0
      check child.superview == parent

    check parentRef.isNil
    check child.superview.isNil
    check nimkitResponders.nextResponder(Responder(child)).isNil

  test "intrinsic layout snapshots do not retain their standalone root":
    var
      rootRef: BackRef[View]
      snapshot: seq[LayoutInput]

    block:
      # Keep lifetime coverage independent of system fonts and their startup cost.
      let root = newIntrinsicLifetimeView()
      rootRef.target = View(root)
      root.layoutSubtreeIfNeeded()
      snapshot = root.generatedLayoutInputs()

      check not root.xLastLayoutSolveDiagnostic.failed
      check snapshot.len == 4
      for input in snapshot:
        check input.kind == likEquation
        check input.source == lisIntrinsic
        for term in input.equation.terms:
          check term.item == View(root)

    check rootRef.isNil
    for input in snapshot:
      for term in input.equation.terms:
        check term.item.isNil

  test "detached trees release before the old root rebuilds its cache":
    let root = newView(frame = rect(0, 0, 240, 160))
    var
      branchRef, leafRef: BackRef[View]
      snapshot: seq[LayoutInput]

    block:
      let
        branch = newView(frame = rect(10, 10, 120, 80))
        leaf = newView(frame = rect(5, 5, 40, 20))
      branchRef.target = branch
      leafRef.target = leaf
      branch.addSubview(leaf)
      root.addSubview(branch)
      root.layoutSubtreeIfNeeded()
      snapshot = root.generatedLayoutInputs()
      check snapshot.len > 0

      branch.removeFromSuperview()
      branch.layoutSubtreeIfNeeded()
      check branch.generatedLayoutInputs().len > 0

    check branchRef.isNil
    check leafRef.isNil
    check root.subviews.len == 0
    for input in snapshot:
      for term in input.equation.terms:
        check term.item.isNil or term.item == root

    root.layoutSubtreeIfNeeded()
    check root.generatedLayoutInputs().len == 0

  test "reparented trees release old caches and reuse current layout inputs":
    var newRootRef, branchRef, leafRef: BackRef[View]

    block:
      let
        newRoot = newView(frame = rect(0, 0, 300, 160))
        branch = newView(frame = rect(10, 10, 120, 80))
        leaf = newView(frame = rect(5, 5, 40, 20))
      newRootRef.target = newRoot
      branchRef.target = branch
      leafRef.target = leaf
      branch.autoresizingMask = {cxWidthSizable}
      branch.addSubview(leaf)
      var oldRootRef: BackRef[View]

      block:
        let oldRoot = newView(frame = rect(0, 0, 240, 160))
        oldRootRef.target = oldRoot
        oldRoot.addSubview(branch)
        oldRoot.layoutSubtreeIfNeeded()
        check oldRoot.generatedLayoutInputs().len > 0

        newRoot.addSubview(branch)
        newRoot.layoutSubtreeIfNeeded()
        check branch.superview == newRoot
        check branch.frame == rect(10, 10, 120, 80)

      check oldRootRef.isNil
      let generation = newRoot.layoutInputGeneration()
      newRoot.layoutSubtreeIfNeeded()
      check newRoot.layoutInputGeneration() == generation

      newRoot.frame = rect(0, 0, 360, 160)
      newRoot.layoutSubtreeIfNeeded()
      check branch.frame == rect(10, 10, 180, 80)
      check leaf.frame == rect(5, 5, 40, 20)

    check newRootRef.isNil
    check branchRef.isNil
    check leafRef.isNil
