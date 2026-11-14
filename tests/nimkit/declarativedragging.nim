import std/[math, options, unittest]
import figdraw
import ./fixtures/rendergeometry
import merenda/nimkit/interaction/dragcontrollers
import merenda/nimkit/app/windows
import merenda/nimkit/foundation/[events, selectors, types, undomanagers]
import merenda/nimkit/drawing/[drawing, rendering]
import merenda/nimkit/view/views
import merenda/nimkit/themes

proc buildList(model: seq[string], env: DragEnvironment): View =
  result = newView(rect(0, 0, env.bounds.size.width, env.bounds.size.height))
  let nested = newView(rect(13, 11, 180, 200))
  nested.bounds = rect(3, 5, 180, 200)
  result.addSubview(nested)
  var y = 0.0'f32
  for id in model:
    let height = if id == "B": 50.0'f32 else: 30.0'f32
    let row = newView(rect(0, y, 160, height))
    row.dragId = id
    row.backgroundColor = color(0.2, 0.5, 0.8, 1)
    nested.addSubview(row)
    y += height + 10

proc successors(model: seq[string], id: string): seq[seq[string]] =
  var rest = model
  rest.delete(rest.find(id))
  for index in 0 .. rest.len:
    var next = rest
    next.insert(id, index)
    result.add next

suite "NimKit declarative dragging":
  test "closest preserves ties and stickiness and rejects invalid targets":
    let targets = @[
      DragTarget(position: initPoint(0, 0), eligible: true),
      DragTarget(position: initPoint(10, 0), eligible: true),
    ]
    check closest(targets, initPoint(5, 0)).index == 0
    check closest(targets, initPoint(5, 0), previous = 1).index == 0
    check closest(targets, initPoint(4, 0), previous = 1, stickiness = 3).index == 1
    check closest(targets, initPoint(30, 0), snapRadius = 5).index == -1
    check closest([], initPoint(0, 0)).index == -1
    check closest(
      [DragTarget(position: initPoint(NaN, 0), eligible: true)], initPoint(0, 0)
    ).index == -1
    check closest([DragTarget()], initPoint(0, 0)).index == -1

  test "detached layouts use semantic IDs and nested bounds coordinates":
    let env =
      DragEnvironment(bounds: rect(0, 0, 240, 250), appearance: initAppearance())
    let root = buildList(@["A", "B", "C"], env)
    let preview = captureDragPreview(root, env)
    check preview.elements[preview.find("B")].frame == rect(10, 46, 160, 50)
    check root.window.isNil
    check root.subviews[0].subviews.len == 3
    check root.subviews[0].subviews[1].frame == rect(0, 40, 160, 50)
    root.subviews[0].subviews[1].dragId = "A"
    expect ValueError:
      discard captureDragPreview(root, env)

  test "drag IDs are independent of ordinary view identifiers":
    let env =
      DragEnvironment(bounds: rect(0, 0, 240, 250), appearance: initAppearance())
    let root = buildList(@["A", "B"], env)
    let container = root.subviews[0]
    let row = container.subviews[0]
    root.identifier = "board"
    container.identifier = "list"
    for child in container.subviews:
      child.identifier = "row"
    let label = newView(rect(0, 0, 100, 20))
    label.identifier = "title"
    row.addSubview(label)

    let preview = captureDragPreview(root, env)
    check preview.elements.len == 2
    check preview.find("A") >= 0
    check preview.find("B") >= 0
    check preview.find("row") == -1
    check root.viewWithIdentifier("title") == label

    row.dragId = ""
    let unmarked = captureDragPreview(root, env)
    check unmarked.elements.len == 1
    check unmarked.find("A") == -1
    check unmarked.find("B") >= 0

  test "ordinary identifiers alone do not arm a drag":
    proc identifiedList(model: seq[string], env: DragEnvironment): View =
      result = buildList(model, env)
      for row in result.subviews[0].subviews:
        row.identifier = row.dragId
        row.dragId = ""

    let host = newDeclarativeDragView(
      @["A", "B"], identifiedList, successors, frame = rect(0, 0, 240, 250)
    )
    check not host.beginDrag(initPoint(17, 15))
    check not host.beginDrag(initPoint(17, 55))
    check host.dragState == ddsIdle
    check host.model == @["A", "B"]

  test "root and nested drag IDs are rejected":
    let env =
      DragEnvironment(bounds: rect(0, 0, 240, 250), appearance: initAppearance())
    let root = buildList(@["A", "B"], env)
    root.dragId = "board"
    expect ValueError:
      discard captureDragPreview(root, env)
    root.dragId = ""
    root.subviews[0].dragId = "list"
    expect ValueError:
      discard captureDragPreview(root, env)

  test "noncentral grab selects a future layout and commits once through window input":
    var commits = 0
    let host = newDeclarativeDragView(
      @["A", "B", "C"],
      buildList,
      successors,
      commit = proc(previous, next: seq[string]): bool =
        inc commits
        true,
      frame = rect(20, 20, 240, 250),
    )
    let window = newWindow("D2 test", frame = rect(0, 0, 400, 400))
    let root = newView(rect(0, 0, 400, 400))
    root.addSubview(host)
    window.setContentView(root)
    defer:
      window.close()
    # B's grabbed point is (7, 9) within its frame, not its center.
    check window.mouseDownAt(initPoint(37, 75))
    check host.dragState == ddsArmed
    check window.mouseDraggedAt(initPoint(37, 115))
    check host.dragState == ddsDragging
    check host.model == @["A", "B", "C"]
    check commits == 0
    check window.mouseUpAt(initPoint(37, 115))
    check host.model == @["A", "C", "B"]
    check commits == 1
    discard host.endDrag(initPoint(17, 95))
    check commits == 1

  test "click, escape, outside release and external edits never commit":
    var clicks, commits: int
    let host = newDeclarativeDragView(
      @["A", "B", "C"],
      buildList,
      successors,
      commit = proc(previous, next: seq[string]): bool =
        inc commits
        true,
      frame = rect(0, 0, 240, 250),
      clicked = proc(id: string) =
        inc clicks
      ,
    )
    check host.beginDrag(initPoint(17, 55))
    check host.endDrag(initPoint(18, 56))
    check clicks == 1
    check host.beginDrag(initPoint(17, 55))
    check host.updateDrag(initPoint(17, 95))
    check host.trySendLocal(keyDown(), KeyEvent(key: keyEscape)).get(false)
    check host.model == @["A", "B", "C"]
    check host.beginDrag(initPoint(17, 55))
    check host.endDrag(initPoint(17, 350))
    check host.beginDrag(initPoint(17, 55))
    check host.updateDrag(initPoint(17, 95))
    host.model = @["C", "B", "A"]
    check not host.endDrag(initPoint(17, 95))
    check host.model == @["C", "B", "A"]
    check commits == 0

  test "no-change, missing dragged IDs and rejected commits are harmless":
    let host = newDeclarativeDragView(
      @["A", "B", "C"],
      buildList,
      successors,
      commit = proc(previous, next: seq[string]): bool =
        false,
      frame = rect(0, 0, 240, 250),
    )
    check host.beginDrag(initPoint(17, 55))
    check host.endDrag(initPoint(17, 95))
    check host.model == @["A", "B", "C"]
    let empty = newDeclarativeDragView(
      @["A"],
      buildList,
      proc(model: seq[string], id: string): seq[seq[string]] =
        @[@["Z"]],
      frame = rect(0, 0, 240, 250),
    )
    check empty.beginDrag(initPoint(17, 15))
    check empty.endDrag(initPoint(17, 85))
    check empty.model == @["A"]

  test "closing a window and removing the host cancel captured drags":
    let host = newDeclarativeDragView(
      @["A", "B", "C"], buildList, successors, frame = rect(0, 0, 240, 250)
    )
    let root = newView(rect(0, 0, 300, 300))
    root.addSubview(host)
    let window = newWindow("D2 lifecycle", frame = root.frame)
    window.setContentView(root)
    check window.mouseDownAt(initPoint(17, 55))
    check host.updateDrag(initPoint(17, 95))
    host.removeFromSuperview()
    check host.dragState == ddsIdle
    root.addSubview(host)
    check window.mouseDownAt(initPoint(17, 55))
    check host.updateDrag(initPoint(17, 95))
    window.close()
    check host.dragState == ddsIdle
    check host.model == @["A", "B", "C"]

  test "a completed drag registers one reversible model change":
    let manager = newUndoManager()
    var host: DeclarativeDragView[seq[string]]
    proc applyModel(value: seq[string]) =
      manager.registerValueChange(applyModel, host.model, "Reorder")
      host.model = value

    host = newDeclarativeDragView(
      @["A", "B", "C"],
      buildList,
      successors,
      commit = proc(previous, next: seq[string]): bool =
        manager.registerValueChange(applyModel, previous, "Reorder")
        true,
      frame = rect(0, 0, 240, 250),
    )
    check host.beginDrag(initPoint(17, 55))
    check host.endDrag(initPoint(17, 95))
    check manager.undoCount == 1
    check host.model == @["A", "C", "B"]
    check manager.performUndo()
    check host.model == @["A", "B", "C"]
    check manager.performRedo()
    check host.model == @["A", "C", "B"]
    manager.clearAll()

  test "reentrant model replacement invalidates the proposal":
    var host: DeclarativeDragView[seq[string]]
    host = newDeclarativeDragView(
      @["A", "B", "C"],
      buildList,
      successors,
      commit = proc(previous, next: seq[string]): bool =
        host.model = @["newer"]
        true,
      frame = rect(0, 0, 240, 250),
    )
    check host.beginDrag(initPoint(17, 55))
    check host.endDrag(initPoint(17, 95))
    check host.model == @["newer"]

  test "candidate exceptions discard the session without touching the model":
    let host = newDeclarativeDragView(
      @["A"],
      buildList,
      proc(model: seq[string], id: string): seq[seq[string]] =
        @[@["X", "X"]],
      frame = rect(0, 0, 240, 250),
    )
    check host.beginDrag(initPoint(17, 15))
    expect ValueError:
      discard host.updateDrag(initPoint(17, 95))
    check host.dragState == ddsIdle
    check host.model == @["A"]

  test "floating paints each card once and settles at committed geometry":
    let host = newDeclarativeDragView(
      @["A", "B", "C"], buildList, successors, frame = rect(0, 0, 240, 250)
    )
    proc cardRects(): seq[Rect] =
      for node in buildRenders(host)[DefaultDrawLevel].resolvedNodes():
        if node.kind == nkRectangle and node.fill.kind == flColor and
            node.fill.color == color(0.2, 0.5, 0.8, 1).rgba:
          result.add rect(
            node.screenBox.x, node.screenBox.y, node.screenBox.w, node.screenBox.h
          )

    check cardRects().len == 3
    check host.beginDrag(initPoint(17, 55))
    check host.updateDrag(initPoint(47, 95))
    let floating = cardRects()
    require floating.len == 3
    check floating[^1] == rect(40, 86, 160, 50)
    check host.endDrag(initPoint(47, 95))
    let resting = cardRects()
    require resting.len == 3
    check resting[^1] == rect(10, 86, 160, 50)

  test "clipped portions of elements cannot be grabbed":
    proc clippedList(model: seq[string], env: DragEnvironment): View =
      result = buildList(model, env)
      result.subviews[0].clipsToBounds = true
      result.subviews[0].frame = rect(13, 11, 180, 40)

    let host = newDeclarativeDragView(
      @["A", "B", "C"], clippedList, successors, frame = rect(0, 0, 240, 250)
    )
    check not host.beginDrag(initPoint(17, 75))
    check host.beginDrag(initPoint(17, 15))
    host.cancelDrag(animated = false)
