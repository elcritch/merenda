## Model-driven dragging for a single NimKit view and mouse pointer.
import std/[math, times]
import sigils/[core, selectors]
import ../app/[animations, windows]
import ../drawing/drawing
import ../foundation/[events, selectors, types]
import ../responder/responders
import ../view/views
import ./[dragbehaviors, dragpreviews]
export dragbehaviors, dragpreviews

type
  DeclarativeDragState* = enum
    ddsIdle
    ddsArmed
    ddsDragging
    ddsSettling

  DragPlacement = object
    id: string
    origin, start, destination: Point

  DragHost* = ref object of View
    xState: DeclarativeDragState
    xOptions: DragOptions
    xEnvironment: DragEnvironment
    xRest, xPresented: DragPreview
    xCandidates: seq[DragPreview]
    xTargets: seq[DragTarget]
    xPlacements: seq[DragPlacement]
    xDraggedId: string
    xDown, xPointer, xAnchor: Point
    xRevision: uint64
    xChoice: int
    xAnimation: Animation
    build: proc(host: DragHost, env: DragEnvironment): DragPreview {.closure.}
    describe: proc(host: DragHost, id: string, env: DragEnvironment): seq[DragPreview] {.
      closure
    .}
    commit: proc(host: DragHost, index: int): bool {.closure.}
    clearCandidates: proc(host: DragHost) {.closure.}
    clicked: proc(id: string) {.closure.}

  DeclarativeDragView*[T] = ref object of DragHost
    xModel: T
    xModels: seq[T]

  DragViewBuilder*[T] = proc(model: T, environment: DragEnvironment): View {.closure.}
  DragSuccessors*[T] = proc(model: T, elementId: string): seq[T] {.closure.}
  DragCommit*[T] = proc(previous, next: T): bool {.closure.}

proc dragState*(host: DragHost): DeclarativeDragState =
  host.xState

proc selectedCandidate*(host: DragHost): int =
  host.xChoice

proc model*[T](host: DeclarativeDragView[T]): T =
  host.xModel

proc stopTransition(host: DragHost) =
  if not host.xAnimation.isNil:
    let owner = host.window()
    if owner of Window:
      discard Window(owner).stopAnimation(host.xAnimation)
    else:
      host.xAnimation.stop()
    host.xAnimation = nil

proc clearSession(host: DragHost) =
  host.xCandidates.setLen(0)
  host.xTargets.setLen(0)
  host.clearCandidates(host)
  host.xChoice = -1
  host.xDraggedId = ""

proc cancelDrag*(host: DragHost, animated = true)
proc refreshDragView*(host: DragHost)

protocol DragPresentationProtocol:
  method dragProgress*(value: float32)

protocol DragPresentation of DragPresentationProtocol:
  method dragProgress(host: DragHost, value: float32) =
    for placement in host.xPlacements.mitems:
      placement.origin = initPoint(
        placement.start.x + (placement.destination.x - placement.start.x) * value,
        placement.start.y + (placement.destination.y - placement.start.y) * value,
      )
    if value >= 1:
      host.xAnimation = nil
      if host.xState == ddsSettling:
        host.xState = ddsIdle
    host.needsDisplay = true

proc transition(host: DragHost, preview: DragPreview, animated = true) =
  host.stopTransition()
  var placements: seq[DragPlacement]
  for element in preview.elements:
    var origin = element.frame.origin
    for old in host.xPlacements:
      if old.id == element.id:
        origin = old.origin
    if host.xState == ddsSettling and element.id == host.xDraggedId and
        host.xOptions.floating:
      origin =
        initPoint(host.xPointer.x - host.xAnchor.x, host.xPointer.y - host.xAnchor.y)
    placements.add DragPlacement(
      id: element.id, origin: origin, start: origin, destination: element.frame.origin
    )
  host.xPlacements = placements
  host.xPresented = preview
  let owner = host.window()
  if animated and host.xOptions.transitionSeconds > 0 and owner of Window:
    let animation = newPropertyAnimation[float32](
      host,
      dragProgress(),
      0,
      1,
      initDuration(milliseconds = int64(host.xOptions.transitionSeconds * 1000)),
    )
    host.xAnimation = animation
    discard Window(owner).startAnimation(animation)
  else:
    discard host.send(dragProgress(), 1.0'f32)
  host.needsDisplay = true

proc refreshDragView*(host: DragHost) =
  ## Call after an external style/layout input changes. Replaces all snapshots.
  host.cancelDrag(animated = false)
  host.xEnvironment =
    DragEnvironment(bounds: host.bounds, appearance: host.effectiveAppearance())
  host.xRest = host.build(host, host.xEnvironment)
  host.transition(host.xRest, animated = false)

proc `model=`*[T](host: DeclarativeDragView[T], model: T) =
  ## External edits invalidate any armed or active drag before replacing state.
  host.cancelDrag(animated = false)
  inc host.xRevision
  host.xModel = model
  host.refreshDragView()

proc cancelDrag*(host: DragHost, animated = true) =
  if host.xState == ddsIdle:
    return
  host.xState = ddsSettling
  let owner = host.window()
  if owner of Window:
    Window(owner).releaseMouseCapture(host)
  host.transition(host.xRest, animated)
  host.clearSession()

proc beginDrag*(host: DragHost, point: Point): bool =
  ## Arms a drag in host coordinates. Candidate construction waits for threshold.
  if not point.finite:
    return
  host.cancelDrag(animated = false)
  # Refresh on every press so changes to appearance and builder inputs are seen.
  host.refreshDragView()
  for i in countdown(host.xRest.elements.high, 0):
    let element = host.xRest.elements[i]
    if element.frame.contains(point) and element.clip.contains(point):
      host.xDraggedId = element.id
      host.xDown = point
      host.xPointer = point
      host.xAnchor =
        initPoint(point.x - element.frame.origin.x, point.y - element.frame.origin.y)
      host.xState = ddsArmed
      return true

proc updateDrag*(host: DragHost, point: Point): bool =
  if host.xState notin {ddsArmed, ddsDragging}:
    return
  if not point.finite:
    host.cancelDrag(animated = false)
    return true
  host.xPointer = point
  if host.xState == ddsArmed:
    if distance(point, host.xDown) < host.xOptions.threshold:
      return true
    try:
      host.xCandidates = @[host.xRest]
      host.xCandidates.add host.describe(host, host.xDraggedId, host.xEnvironment)
      for candidate in host.xCandidates:
        let index = candidate.find(host.xDraggedId)
        var target: DragTarget
        if index >= 0:
          let frame = candidate.elements[index].frame
          target = DragTarget(
            eligible: true,
            position: initPoint(
              frame.origin.x + host.xAnchor.x, frame.origin.y + host.xAnchor.y
            ),
          )
        host.xTargets.add target
      host.xState = ddsDragging
      host.xChoice = 0
    except CatchableError:
      host.cancelDrag(animated = false)
      raise
  let choice = closest(
    host.xTargets, point, host.xChoice, host.xOptions.stickiness,
    host.xOptions.snapRadius,
  )
  if choice.index != host.xChoice:
    host.xChoice = choice.index
    host.transition(
      if choice.index < 0:
        host.xRest
      else:
        host.xCandidates[choice.index]
    )
  host.needsDisplay = true
  true

proc endDrag*(host: DragHost, point: Point): bool =
  if host.xState notin {ddsArmed, ddsDragging}:
    return
  if host.xState == ddsArmed and distance(point, host.xDown) < host.xOptions.threshold:
    let id = host.xDraggedId
    host.cancelDrag(animated = false)
    if host.bounds.contains(point) and not host.clicked.isNil:
      host.clicked(id)
    return true
  discard host.updateDrag(point)
  if host.xState != ddsDragging:
    return true
  # Releasing outside the host cancels, even if an unlimited-radius target is near.
  let choice = host.xChoice
  try:
    if choice > 0 and host.bounds.contains(point) and host.commit(host, choice - 1):
      host.xRest = host.build(host, host.xEnvironment)
    host.xState = ddsSettling
    host.transition(host.xRest)
  finally:
    host.clearSession()
    if host.xState == ddsDragging:
      host.cancelDrag(animated = false)
  true

protocol DragHostEvents of ResponderEventProtocol:
  method mouseDown(host: DragHost, event: MouseEvent): bool =
    event.button == mbPrimary and host.beginDrag(event.location)

  method mouseDragged(host: DragHost, event: MouseEvent): bool =
    event.button == mbPrimary and host.updateDrag(event.location)

  method mouseUp(host: DragHost, event: MouseEvent): bool =
    event.button == mbPrimary and host.endDrag(event.location)

  method mouseCancelled(host: DragHost) =
    host.cancelDrag(animated = false)

  method keyDown(host: DragHost, event: KeyEvent): bool =
    if event.key == keyEscape and host.xState != ddsIdle:
      host.cancelDrag()
      return true

protocol DragHostCommands of MenuCommandProtocol:
  method cancelOperation(host: DragHost, args: ActionArgs) =
    host.cancelDrag()

protocol DragHostDrawing of ViewDrawingProtocol:
  method draw(host: DragHost, context: DrawContext) =
    host.xPresented.drawBackdrop(context)
    for i, element in host.xPresented.elements:
      if host.xState != ddsDragging or not host.xOptions.floating or
          element.id != host.xDraggedId:
        element.drawElement(context, host.xPlacements[i].origin)
    if host.xState == ddsDragging and host.xOptions.floating:
      let index = host.xRest.find(host.xDraggedId)
      if index >= 0:
        host.xRest.elements[index].drawElement(
          context,
          initPoint(host.xPointer.x - host.xAnchor.x, host.xPointer.y - host.xAnchor.y),
          clipped = false,
        )

protocol DragHostLayout of ViewLayoutProtocol:
  method layoutSubviews(host: DragHost) =
    if host.bounds != host.xEnvironment.bounds or
        host.effectiveAppearance().theme.generation() !=
        host.xEnvironment.appearance.theme.generation():
      host.refreshDragView()

protocol DragHostWindowLifecycle of WindowLifecycleEvents:
  proc closing(host: DragHost) {.slotFor: willClose.} =
    host.cancelDrag(animated = false)

protocol DragHostLifecycle of ViewLifecycleProtocol:
  proc departing(host: DragHost, parent: View) {.slotFor: viewWillMoveToSuperview.} =
    host.cancelDrag(animated = false)

  proc changingWindow(
      host: DragHost, owner: Responder
  ) {.slotFor: viewWillMoveToWindow.} =
    host.cancelDrag(animated = false)
    let previous = host.window()
    if previous of Window:
      host.unobserveProtocol(Window(previous), DragHostWindowLifecycle)
    if owner of Window:
      host.observeProtocol(Window(owner), DragHostWindowLifecycle)

proc newDeclarativeDragView*[T](
    model: T,
    build: DragViewBuilder[T],
    successors: DragSuccessors[T],
    commit: DragCommit[T] = nil,
    frame = AutoRect,
    options = initDragOptions(),
    clicked: proc(id: string) {.closure.} = nil,
): DeclarativeDragView[T] =
  ## Models must have value semantics (or immutable referenced data). `build`
  ## returns fresh, effect-free trees. `successors` enumerates local outcomes;
  ## the unchanged outcome is automatically included. `commit` can reject a
  ## stale proposal and owns undo registration; it is called once per change.
  if build.isNil or successors.isNil:
    raise
      newException(ValueError, "declarative dragging needs a builder and successors")
  if not initPoint(options.threshold, options.stickiness).finite or
      not initPoint(options.transitionSeconds, 0).finite or options.threshold < 0 or
      options.stickiness < 0 or options.transitionSeconds < 0 or options.snapRadius < 0 or
      classify(options.snapRadius) == fcNan:
    raise newException(
      ValueError, "drag options require nonnegative distances and durations"
    )
  result = DeclarativeDragView[T](
    xModel: model, xOptions: options, xChoice: -1, clicked: clicked
  )
  initViewFields(result, frame)
  result.acceptsFirstResponder = true
  result.clipsToBounds = true
  result.build = proc(host: DragHost, env: DragEnvironment): DragPreview =
    captureDragPreview(build(DeclarativeDragView[T](host).xModel, env), env)
  result.describe = proc(
      host: DragHost, id: string, env: DragEnvironment
  ): seq[DragPreview] =
    let view = DeclarativeDragView[T](host)
    view.xModels = successors(view.xModel, id)
    for model in view.xModels:
      result.add captureDragPreview(build(model, env), env)
  result.commit = proc(host: DragHost, index: int): bool =
    let view = DeclarativeDragView[T](host)
    let next = view.xModels[index]
    if next == view.xModel:
      return false
    let revision = view.xRevision
    if not commit.isNil and not commit(view.xModel, next):
      return false
    if revision != view.xRevision:
      return false
    inc view.xRevision
    view.xModel = next
    true
  result.clearCandidates = proc(host: DragHost) =
    DeclarativeDragView[T](host).xModels.setLen(0)
  discard result.withProtocol(DragPresentation)
  discard result.withProtocol(DragHostEvents)
  discard result.withProtocol(DragHostCommands)
  discard result.withProtocol(DragHostDrawing)
  discard result.withProtocol(DragHostLayout)
  result.observeProtocol(result, DragHostLifecycle)
  result.refreshDragView()
