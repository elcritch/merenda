## Native listing and actions for work preserved by the editor engine.

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./moe

type
  KosmoRecoveryList = ref object of nimkit.OutlineView
    entries: seq[KosmoRecoveryEntry]

  KosmoRecoveryView* = ref object of nimkit.View
    editor: KosmoEditor
    list: KosmoRecoveryList
    restoreButton, discardButton, refreshButton: nimkit.Button
    statusLabel: nimkit.Label
    armedDiscard: string
    onRestore*: proc(copyPath: string): FileOpenResult {.closure.}

protocol KosmoRecoveryDataSource of nimkit.OutlineViewDataSource:
  method numberOfChildren(
      list: KosmoRecoveryList, outline: nimkit.OutlineView, parentIdentifier: string
  ): int =
    if parentIdentifier.len == 0:
      result = list.entries.len

  method childIdentifier(
      list: KosmoRecoveryList,
      outline: nimkit.OutlineView,
      parentIdentifier: string,
      index: int,
  ): string =
    if parentIdentifier.len == 0 and index in 0 ..< list.entries.len:
      result = list.entries[index].copyPath

  method outlineItem(
      list: KosmoRecoveryList, outline: nimkit.OutlineView, identifier: string
  ): nimkit.OutlineItem =
    for entry in list.entries:
      if entry.copyPath == identifier:
        let title = if entry.originalPath.len > 0: entry.originalPath else: "Untitled"
        return nimkit.initOutlineItem(
          identifier,
          title & "  —  " & entry.savedAt & "  " & entry.note,
          leaf = true,
          tooltip = title,
        )

proc refresh*(view: KosmoRecoveryView) =
  let selected = view.list.selectedItemIdentifier()
  view.list.entries = view.editor.recoveryEntries()
  view.list.reloadOutlineData()
  view.list.selectedItemIdentifier = selected
  if view.list.selectedItemIdentifier().len == 0 and view.list.entries.len > 0:
    view.list.selectedItemIdentifier = view.list.entries[0].copyPath
  view.armedDiscard = ""
  view.discardButton.title = "Discard"
  view.statusLabel.text =
    if view.list.entries.len == 0:
      "No preserved work"
    else:
      "Restore brings the selected copy into an unsaved editor tab."

proc restoreSelected*(view: KosmoRecoveryView): bool {.discardable.} =
  ## Restore the selected copy using the host's buffer-activation callback.
  let selected = view.list.selectedItemIdentifier()
  if selected.len == 0:
    return
  let outcome =
    if view.onRestore.isNil:
      view.editor.restoreRecoveryCopy(selected)
    else:
      view.onRestore(selected)
  view.refresh()
  if not outcome.loaded:
    view.statusLabel.text = outcome.message
  outcome.loaded

proc discardSelected(view: KosmoRecoveryView) =
  let selected = view.list.selectedItemIdentifier()
  if selected.len == 0:
    return
  if view.armedDiscard != selected:
    view.armedDiscard = selected
    view.discardButton.title = "Confirm Discard"
    view.statusLabel.text = "Click Confirm Discard to remove this preserved copy."
    return
  let outcome = view.editor.discardRecoveryCopy(selected)
  view.refresh()
  if not outcome.loaded:
    view.statusLabel.text = outcome.message

proc preferredResponder*(view: KosmoRecoveryView): nimkit.View =
  ## The list accepts keyboard navigation and activation inside a native tab.
  view.list

proc recoveryRowWasActivated(
    view: KosmoRecoveryView, sender: nimkit.DynamicAgent
) {.slot.} =
  discard view.restoreSelected()

protocol KosmoRecoveryLayout of nimkit.ViewLayoutProtocol:
  method layout(view: KosmoRecoveryView) =
    let bounds = view.bounds()
    view.list.setFrameFromLayout(
      nimkit.rect(0, 0, bounds.size.width, max(bounds.size.height - 72, 0))
    )
    let y = max(bounds.size.height - 64, 0)
    view.restoreButton.setFrameFromLayout(nimkit.rect(8, y, 90, 28))
    view.discardButton.setFrameFromLayout(nimkit.rect(106, y, 132, 28))
    view.refreshButton.setFrameFromLayout(nimkit.rect(246, y, 90, 28))
    view.statusLabel.setFrameFromLayout(
      nimkit.rect(8, y + 34, max(bounds.size.width - 16, 0), 22)
    )

proc newKosmoRecoveryView*(editor: KosmoEditor): KosmoRecoveryView =
  result = KosmoRecoveryView(editor: editor)
  result.initViewFields()
  discard result.withProtocol(KosmoRecoveryLayout)
  result.list = KosmoRecoveryList()
  result.list.initOutlineViewFields()
  discard result.list.withProtocol(KosmoRecoveryDataSource)
  result.list.outlineDataSource = result.list
  result.list.outlineColumn().title = "Preserved work"
  result.list.outlineColumn().width = 640
  result.list.selectionMode = nimkit.tsmSingle
  result.list.connect(nimkit.rowWasActivated, result, recoveryRowWasActivated)
  result.restoreButton = nimkit.newButton("Restore")
  result.discardButton = nimkit.newButton("Discard")
  result.refreshButton = nimkit.newButton("Refresh")
  result.statusLabel = nimkit.newLabel("")
  for child in [
    nimkit.View(result.list), result.restoreButton, result.discardButton,
    result.refreshButton, result.statusLabel,
  ]:
    result.addSubview(child)
  let view = result.unsafeWeakRef()
  result.restoreButton.action = nimkit.actionSelector("kosmo.restoreRecovery")
  result.restoreButton.target = nimkit.newActionTarget(result.restoreButton.action) do(
    sender: nimkit.DynamicAgent
  ):
    if not view.isNil:
      discard view[].restoreSelected()
  result.discardButton.action = nimkit.actionSelector("kosmo.discardRecovery")
  result.discardButton.target = nimkit.newActionTarget(result.discardButton.action) do(
    sender: nimkit.DynamicAgent
  ):
    if not view.isNil:
      view[].discardSelected()
  result.refreshButton.action = nimkit.actionSelector("kosmo.refreshRecovery")
  result.refreshButton.target = nimkit.newActionTarget(result.refreshButton.action) do(
    sender: nimkit.DynamicAgent
  ):
    if not view.isNil:
      view[].refresh()
  result.refresh()
