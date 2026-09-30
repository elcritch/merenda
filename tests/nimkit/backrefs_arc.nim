## ARC back-reference behavior shared by the NimKit test runner.
import std/unittest

import merenda/nimkit
import merenda/nimkit/responder/responders as nimkitResponders
import merenda/nimkit/view/[viewbase, viewconstraints]

static:
  doAssert compileOption("mm", "arc") or compileOption("mm", "orc") or
    compileOption("mm", "atomicArc")

type IntrinsicLifetimeView = ref object of View

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
  test "returned copied and moved back references clear independently":
    var original, copied, moved: BackRef[View]

    block:
      let target = newView()
      original = observe(target)
      copied = original
      moved = move(original)

      check original.isNil
      check copied.target == target
      check moved.target == target

      original = copied
      original = original
      copied.clear()
      check copied.isNil
      check original.target == target
      check moved.target == target

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
        check original.target == secondTarget
        check copied.target == firstTarget

      check original.isNil
      check original.target.isNil
      check copied.target == firstTarget

      original.target = firstTarget
      copied.target = nil
      check copied.isNil
      check copied.target.isNil
      check original.target == firstTarget

    check original.isNil
    check copied.isNil

  test "dropping the last copied handle unregisters its shared slot":
    let target = newView()
    var survivor: BackRef[View]
    block:
      var original = observe(target)
      var copied = original
      survivor = observe(target)
      original.clear()
      check copied.target == target
      copied.clear()
    # Removing the earlier slot must update the moved slot's registry index.
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
        check reference.target == target
      for reference in copied:
        check reference.target == target

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
