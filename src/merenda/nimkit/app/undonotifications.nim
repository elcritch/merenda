## Publish undo history changes through NimKit's notification center.

import sigils/[core, selectors]

import ../../foundation/undomanagers
import ./notifications

export undomanagers except newUndoManager

proc postUndoStateChanged(manager: UndoManager) =
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkUndoStateDidChange,
      sender = DynamicAgent(manager),
      payload = initUndoNotificationPayload(
        undoCount = manager.undoCount(),
        redoCount = manager.redoCount(),
        groupingDepth = manager.groupingDepth(),
        disabledDepth = manager.undoRegistrationDisableDepth(),
        undoing = manager.isUndoing(),
        redoing = manager.isRedoing(),
        clean = manager.isAtCleanState(),
        nextUndoActionName = manager.undoActionName(),
        nextRedoActionName = manager.redoActionName(),
      ),
    )
  )

proc newUndoManager*(): UndoManager =
  ## Create history that posts NimKit undo notifications.
  undomanagers.newUndoManager(postUndoStateChanged)
