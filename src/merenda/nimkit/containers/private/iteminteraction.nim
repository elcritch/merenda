## Item pointer tracking and drag transitions. Callbacks execute synchronously.

import ../../app/dragging
import ../../app/windows
import ../../controls/controls
import ../../foundation/events
import ../../foundation/types
import ../../responder/responders
import sigils/core
import sigils/selectors

type ItemInteractionState*[K] = object
  tracking*: bool
  pressed*: K
  dragSession*: DraggingSession
  dropTarget*: DraggingDropTarget

proc activeSession*[K](state: ItemInteractionState[K]): bool =
  not state.dragSession.isNil and state.dragSession.state() == dssActive

proc updateItemDrag*(
    session: DraggingSession,
    owner: DynamicAgent,
    location: Point,
    target: DraggingDropTarget,
    finish = false,
): bool =
  if session.isNil or session.state() != dssActive:
    return
  discard updateDraggingSession(session, location, owner, target)
  if finish:
    if performDraggingOperation(session, owner, location, target):
      session.endDraggingSession(session.selectedOperations())
    else:
      session.cancelDraggingSession()
  else:
    discard autoscrollDraggingSession(session, location, owner, target)
  true

proc beginItemTracking*[K](
    view: Control, state: var ItemInteractionState[K], event: MouseEvent
): bool =
  if not view.isEnabled() or event.button != mbPrimary:
    return false
  let owner = view.window()
  if owner of Window:
    discard Window(owner).makeFirstResponder(view)
  state.tracking = true
  true

proc endItemTracking*[K](state: var ItemInteractionState[K], empty: K) =
  state.tracking = false
  state.pressed = empty

template defineItemDraggingProtocols*(
    Source, Destination, Widget, Update, Validate, Accept, Autoscroll: untyped
) =
  protocol Source of DraggingSourceProtocol:
    method draggingSourceOperationMask(
        widget: Widget, info: DraggingInfo
    ): DragOperations =
      info.allowedOperations

    method draggingSessionEnded(widget: Widget, info: DraggingInfo) =
      if widget.xInteraction.dragSession == info.session:
        widget.xInteraction.dragSession = nil
        Update(widget, initDraggingDropTarget())

  protocol Destination of DraggingDestinationProtocol:
    method draggingEntered(widget: Widget, info: DraggingInfo): DragOperations =
      Update(widget, info.dropTarget)
      Validate(widget, info)

    method draggingUpdated(widget: Widget, info: DraggingInfo): DragOperations =
      Update(widget, info.dropTarget)
      Validate(widget, info)

    method draggingExited(widget: Widget, info: DraggingInfo) =
      Update(widget, initDraggingDropTarget())

    method prepareForDragOperation(widget: Widget, info: DraggingInfo): bool =
      Validate(widget, info) != NoDragOperations

    method performDragOperation(widget: Widget, info: DraggingInfo): bool =
      Accept(widget, info)

    method concludeDragOperation(widget: Widget, info: DraggingInfo) =
      Update(widget, initDraggingDropTarget())

    method autoscrollDraggingSession(widget: Widget, info: DraggingInfo): bool =
      Autoscroll(widget, info)

template defineItemActiveDragHandlers*(
    Update, Perform, Widget, Target, SetTarget, EndTracking: untyped
) =
  proc Update(widget: Widget, event: MouseEvent): bool =
    if widget.xInteraction.activeSession():
      let target = Target(widget, event.location)
      SetTarget(widget, target)
      return updateItemDrag(
        widget.xInteraction.dragSession, DynamicAgent(widget), event.location, target
      )

  proc Perform(widget: Widget, event: MouseEvent): bool =
    if widget.xInteraction.activeSession():
      let target = Target(widget, event.location)
      SetTarget(widget, target)
      discard updateItemDrag(
        widget.xInteraction.dragSession,
        DynamicAgent(widget),
        event.location,
        target,
        finish = true,
      )
      EndTracking(widget)
      return true
