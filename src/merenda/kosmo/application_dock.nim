# Kosmo dock groups, pane commands, and terminal documents.

proc groupForTabs(
    controller: KosmoDockController, tabs: nimkit.DocumentTabs
): KosmoEditorGroup =
  for group in controller.groups:
    if group.editorView.documentTabs == tabs:
      return group

proc groupForPanel(
    controller: KosmoDockController, panel: nimkit.DockPanel
): KosmoEditorGroup =
  for group in controller.groups:
    if group.panel == panel:
      return group

proc appendGroupsInPanelOrder(
    controller: KosmoDockController,
    view: nimkit.View,
    groups: var seq[KosmoEditorGroup],
) =
  if view of nimkit.DockPanel:
    let group = controller.groupForPanel(nimkit.DockPanel(view))
    if not group.isNil:
      groups.add group
  elif view of nimkit.SplitView:
    for pane in nimkit.SplitView(view).panes():
      controller.appendGroupsInPanelOrder(pane, groups)

proc groupsInPanelOrder(controller: KosmoDockController): seq[KosmoEditorGroup] =
  for host in controller.hosts:
    if not host.window.isNil and not host.window.isClosed():
      controller.appendGroupsInPanelOrder(host.workspace.rootView(), result)

proc hostForWorkspace(
    controller: KosmoDockController, workspace: nimkit.DockView
): KosmoDockHost =
  for host in controller.hosts:
    if host.workspace == workspace:
      return host

proc focusedEditorGroup(controller: KosmoDockController): KosmoEditorGroup =
  if controller.isNil or controller.frontend.isNil:
    return
  let window = controller.frontend[].application.keyWindow()
  if window.isNil or window.isClosed():
    return
  var responder = window.firstResponder()
  while not responder.isNil:
    for group in controller.groups:
      if responder == nimkit.Responder(group.pane):
        return group
    responder = responder.nextResponder()

proc activePaneGroup(controller: KosmoDockController): KosmoEditorGroup =
  if controller.isNil or controller.frontend.isNil or controller.frontend[].xClosed:
    return
  result = controller.focusedEditorGroup()
  if not result.isNil:
    return
  let window =
    if controller.frontend.isNil:
      nil
    else:
      controller.frontend[].application.keyWindow()
  for host in controller.hosts:
    if host.window == window and not window.isNil and not window.isClosed():
      if host.activeGroup in controller.groups:
        return host.activeGroup
      for group in controller.groups:
        if group.window == window:
          return group
  let active = controller.activeGroup
  if not active.isNil and active in controller.groups and not active.window.isNil and
      not active.window.isClosed():
    return active
  for group in controller.groups:
    if not group.window.isNil and not group.window.isClosed():
      return group

proc activeEditorView(controller: KosmoDockController): KosmoEditorView =
  let group = controller.activePaneGroup()
  if not group.isNil:
    result = group.editorView

proc installShortcutBindings(controller: KosmoDockController, window: nimkit.Window) =
  var bindings = window.keyBindings()
  for command in kosmoShortcutCommands():
    discard bindings.remove(nimkit.actionSelector(command))
  for binding in controller.shortcutBindings.bindings:
    bindings.add(binding.sequence, binding.selector)
  window.setKeyBindings(bindings)

proc activateGroup(controller: KosmoDockController, view: KosmoEditorView) =
  if controller.isNil or view.isNil:
    return
  let group = controller.groupForView(view)
  if not group.isNil:
    if controller.activeGroup != group:
      let previous = controller.activeGroup
      controller.editor.dismissCompletionPopup()
      controller.editor.dismissCommandLine()
      if not previous.isNil:
        previous.editorView.refresh()
    controller.activeGroup = group
    let tabs = view.visibleTabs(view.editor.tabs())
    view.selectVisibleBuffer(tabs)
    discard view.syncSelectedEditorContent(tabs)
    view.syncChrome()

proc activatePaneTab(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    identifier: string,
    focus = true,
) =
  if controller.isNil or group.isNil:
    return
  group.selectedTabIdentifier = identifier
  controller.activateGroup(group.editorView)
  var id: KosmoBufferId
  if identifier.parseTabIdentifier(id):
    group.editorView.saveViewState()
    group.editorView.editor.dismissCompletionPopup()
    group.editorView.editor.dismissCommandLine()
    group.editorView.selectedBufferId = some(id)
    group.editorView.selectVisibleBuffer(
      group.editorView.visibleTabs(group.editorView.editor.tabs())
    )
    group.editorView.refresh()
    if focus:
      discard group.window.makeFirstResponder(nimkit.Responder(group.pane.contentView))
    return

  let document = group.documentForIdentifier(identifier)
  if document.isNil:
    return
  group.editorView.editor.dismissCompletionPopup()
  group.editorView.editor.dismissCommandLine()
  group.pane.setContentView(document.contentView)
  group.editorView.syncTabs(group.editorView.editor.tabs())
  if not group.editorView.statusLabel.isNil:
    group.editorView.statusLabel.text = document.title
  group.pane.layoutSubtreeIfNeeded()
  if focus and not document.preferredFirstResponder.isNil:
    discard group.window.makeFirstResponder(document.preferredFirstResponder)

proc activatePanelWindow(controller: KosmoDockController, window: nimkit.Window) =
  if controller.frontend.isNil or window.isNil:
    return
  let app = controller.frontend[].application
  let keyWindow = app.keyWindow()
  if not keyWindow.isNil and keyWindow != window:
    app.activateWindow(window)

proc focusPanel(controller: KosmoDockController, panelNumber: int): bool =
  if controller.isNil or panelNumber < 1:
    return
  if panelNumber == 1:
    if controller.frontend.isNil:
      return
    let frontend = controller.frontend[]
    return frontend.showFileExplorer()

  let
    groupIndex = panelNumber - 2
    groups = controller.groupsInPanelOrder()
  if groupIndex notin 0 ..< groups.len:
    return
  controller.focusGroup(groups[groupIndex])

proc initialBufferIds(editor: KosmoEditor): seq[KosmoBufferId] =
  for tab in editor.tabs():
    result.add tab.id

proc configureGroupView(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    bufferIds: openArray[KosmoBufferId],
) =
  let view = group.editorView
  view.usesBufferSubset = true
  view.bufferIds = @bufferIds
  view.selectedBufferId =
    if bufferIds.len > 0:
      some(bufferIds[^1])
    else:
      none(KosmoBufferId)
  view.lastTabs.setLen(0)
  view.dockGroup = group.unsafeWeakRef()
  group.pane.dockGroup = group.unsafeWeakRef()
  group.tabOrder.setLen(0)
  for id in bufferIds:
    group.tabOrder.add id.tabIdentifier
  group.selectedTabIdentifier =
    if bufferIds.len > 0:
      bufferIds[^1].tabIdentifier
    else:
      ""
  view.tabsDelegate.dockController = controller.unsafeWeakRef()
  let host = controller.hostForWorkspace(group.workspace)
  if not host.isNil:
    view.statusLabel = host.statusLabel
  if not controller.frontend.isNil:
    view.applyKosmoEditorStyle(controller.frontend[].application.effectiveAppearance())
  view.tabsDelegate.observeAppearance(group.window)
  view.refresh()

proc newEditorGroup(
    controller: KosmoDockController,
    workspace: nimkit.DockView,
    window: nimkit.Window,
    bufferIds: openArray[KosmoBufferId],
    editorView: KosmoEditorView = nil,
    editorPane: KosmoEditorPane = nil,
    addToWorkspace = false,
): KosmoEditorGroup =
  let
    view =
      if editorView.isNil:
        newKosmoEditorView(controller.editor)
      else:
        editorView
    pane =
      if editorPane.isNil:
        newKosmoEditorPane(view)
      else:
        editorPane
    panel = nimkit.newDockPanel(pane)
  inc controller.nextGroupIdentifier
  result = KosmoEditorGroup(
    identifier: "kosmo.group." & $controller.nextGroupIdentifier,
    panel: panel,
    pane: pane,
    editorView: view,
    workspace: workspace,
    window: window,
  )
  controller.groups.add result
  controller.configureGroupView(result, bufferIds)
  if addToWorkspace:
    discard workspace.addPanel(panel)
  if controller.activeGroup.isNil:
    controller.activeGroup = result
  else:
    result.updateActivePaneIndicator(false)

proc removeBuffer(group: KosmoEditorGroup, id: KosmoBufferId) =
  let index = group.editorView.bufferIds.find(id)
  if index < 0:
    return
  group.editorView.bufferIds.delete(index)
  group.editorView.removeViewState(id)
  group.editorView.forgetMarkdownMode(id)
  group.editorView.selectedBufferId = none(KosmoBufferId)
  group.editorView.lastTabs.setLen(0)
  group.pane.removeMarkdownPreview(id)
  let orderIndex = group.tabOrder.find(id.tabIdentifier)
  if orderIndex >= 0:
    group.tabOrder.delete(orderIndex)

proc addBuffer(group: KosmoEditorGroup, id: KosmoBufferId) =
  if id notin group.editorView.bufferIds:
    group.editorView.bufferIds.add id
  group.editorView.selectedBufferId = some(id)
  group.editorView.lastTabs.setLen(0)
  if id.tabIdentifier notin group.tabOrder:
    group.tabOrder.add id.tabIdentifier

proc removeGroup(controller: KosmoDockController, group: KosmoEditorGroup) =
  if group.isNil:
    return
  group.editorView.stopMatterHighlightRefresh()
  group.editorView.tabsDelegate.stopObservingWindow()
  group.editorView.tabsDelegate.dockController = default(WeakRef[KosmoDockController])
  group.editorView.dockGroup = default(WeakRef[KosmoEditorGroup])
  group.pane.dockGroup = default(WeakRef[KosmoEditorGroup])
  group.pane.clearMarkdownPreviews()
  let wasActive = controller.activeGroup == group
  discard group.workspace.removePanel(group.panel)
  let index = controller.groups.find(group)
  if index >= 0:
    controller.groups.delete(index)
  let host = controller.hostForWorkspace(group.workspace)
  if not host.isNil and group.workspace.len == 0 and not host.primary and
      not host.window.isClosed():
    host.window.close()
  if wasActive:
    controller.activeGroup = nil
    for candidate in controller.groups:
      if controller.activeGroup.isNil and candidate.workspace == group.workspace:
        controller.activeGroup = candidate
    if controller.activeGroup.isNil and controller.groups.len > 0:
      controller.activeGroup = controller.groups[0]

proc finishTabClose(controller: KosmoDockController, view: KosmoEditorView) =
  let group = controller.groupForView(view)
  if group.isNil:
    view.refresh()
    return
  if view.bufferIds.len == 0 and group.documents.len == 0 and group.workspace.len > 1:
    let wasActive = controller.activeGroup == group
    controller.removeGroup(group)
    if wasActive and not controller.activeGroup.isNil:
      let replacement = controller.activeGroup
      controller.activateGroup(replacement.editorView)
      discard replacement.window.makeFirstResponder(replacement.editorView)
      replacement.editorView.refresh()
    return
  let selectedItem = view.documentTabs.selectedDocumentTabItem()
  if not selectedItem.isNil:
    controller.activatePaneTab(group, selectedItem.identifier())
    return
  if view.bufferIds.len == 0 and group.documents.len == 0:
    view.adoptActiveBuffer()
  view.lastTabs.setLen(0)
  view.refresh()

proc closeCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup) =
  if controller.isNil or group.isNil:
    return
  controller.activeGroup = group
  group.editorView.editor.dismissCommandLine()
  let index =
    group.pane.documentTabs.indexOfDocumentTabIdentifier(group.selectedTabIdentifier)
  if index >= 0:
    discard group.pane.documentTabs.closeDocumentTabAtIndex(index)
  else:
    group.editorView.refresh()

proc closeCurrentTab(controller: KosmoDockController, view: KosmoEditorView) =
  let group = controller.groupForView(view)
  if not group.isNil:
    controller.closeCurrentPaneTab(group)
    return
  view.editor.dismissCommandLine()
  view.refresh()

proc saveDirectory(frontend: KosmoApplication, view: KosmoEditorView): string =
  let workingDirectory = view.editor.workingDirectory()
  if workingDirectory.len > 0 and dirExists(workingDirectory):
    return workingDirectory
  if not frontend.isNil and not frontend.fileTree.isNil:
    let rootPath = frontend.fileTree.rootPath
    if rootPath.len > 0 and dirExists(rootPath):
      return rootPath
  getCurrentDir()

proc saveUntitledTab(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    view: KosmoEditorView,
    savePanel: nimkit.SavePanel = nil,
): KosmoSaveResult =
  if controller.isNil or view.isNil or controller.frontend.isNil:
    return KosmoSaveResult(message: "Kosmo has no active editor window.")
  let frontend = controller.frontend[]
  if frontend.isNil or frontend.application.isNil:
    return KosmoSaveResult(message: "Kosmo has no active application.")

  let ownsPanel = savePanel.isNil
  let panel =
    if ownsPanel:
      nimkit.newSavePanel()
    else:
      savePanel
  if ownsPanel:
    defer:
      panel.window.close()
  panel.window.title = "Save As"
  panel.prompt = "Save"
  panel.message = "Save the untitled editor as a file."
  panel.directoryUrl = frontend.saveDirectory(view)
  if panel.nameFieldStringValue.len == 0:
    panel.nameFieldStringValue = "No Name"
  if not group.isNil and not group.window.isNil:
    panel.window.setInheritedAppearance(group.window.effectiveAppearance())
  discard panel.rebuildSavePanelView()

  if ownsPanel:
    discard panel.window.makeFirstResponder(panel.nameField)
    if frontend.application.runModal(panel) != nimkit.PanelResponseOk:
      return
  elif not panel.validateSelection():
    return

  let path = nimkit.filePathFromUrl(panel.selectedUrl())
  if path.len == 0:
    return KosmoSaveResult(message: "No save path specified.")
  view.editor.saveAs(path)

proc saveCurrentPaneTab(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    savePanel: nimkit.SavePanel,
): bool {.discardable.} =
  if controller.isNil or group.isNil:
    return
  let document = group.documentForIdentifier(group.selectedTabIdentifier)
  if not document.isNil:
    controller.activeGroup = group
    result = document.save()
    return
  result = controller.saveCurrentTab(group.editorView, savePanel)

proc saveCurrentTab(
    controller: KosmoDockController, view: KosmoEditorView, savePanel: nimkit.SavePanel
): bool {.discardable.} =
  controller.activateGroup(view)
  view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
  let tabs = view.editor.tabs()
  var activeTab: KosmoTab
  var hasActiveTab = false
  for tab in tabs:
    if tab.active:
      activeTab = tab
      hasActiveTab = true
      break
  if hasActiveTab and activeTab.filePath.isNone:
    let outcome =
      controller.saveUntitledTab(controller.groupForView(view), view, savePanel)
    view.lastTabs.setLen(0)
    view.refresh()
    if not outcome.saved and outcome.message.len > 0 and not view.statusLabel.isNil:
      view.statusLabel.text = outcome.message
    return outcome.saved

  let outcome = view.editor.save()
  view.lastTabs.setLen(0)
  view.refresh()
  if not outcome.saved and not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message
  outcome.saved

proc selectRelativeTab(
    controller: KosmoDockController, view: KosmoEditorView, offset: int
) =
  let group = controller.groupForView(view)
  if not group.isNil:
    controller.selectRelativePaneTab(group, offset)
    return
  controller.activateGroup(view)
  let tabs = view.visibleTabs(view.editor.tabs())
  if tabs.len == 0:
    return
  var selectedIndex = 0
  if view.selectedBufferId.isSome:
    for index, tab in tabs:
      if tab.id == view.selectedBufferId.get:
        selectedIndex = index
        break
  let targetIndex = (selectedIndex + offset + tabs.len) mod tabs.len
  discard view.documentTabs.selectDocumentTabWithIdentifier(
    tabs[targetIndex].id.tabIdentifier
  )

proc selectRelativePaneTab(
    controller: KosmoDockController, group: KosmoEditorGroup, offset: int
) =
  if controller.isNil or group.isNil or group.pane.documentTabs.len == 0:
    return
  controller.activeGroup = group
  var selectedIndex =
    group.pane.documentTabs.indexOfDocumentTabIdentifier(group.selectedTabIdentifier)
  if selectedIndex < 0:
    selectedIndex = 0
  let targetIndex =
    (selectedIndex + offset + group.pane.documentTabs.len) mod
    group.pane.documentTabs.len
  discard group.pane.documentTabs.selectDocumentTabAtIndex(targetIndex)

proc finishPaneTabMove(
    controller: KosmoDockController,
    source, target: KosmoEditorGroup,
    identifier: string,
) =
  if source != target:
    var id: KosmoBufferId
    if identifier.parseTabIdentifier(id):
      target.addBuffer(id)
      source.removeBuffer(id)
    else:
      let documentIndex = source.documentIndex(identifier)
      if documentIndex < 0:
        return
      let document = source.documents[documentIndex]
      source.documents.delete(documentIndex)
      let orderIndex = source.tabOrder.find(identifier)
      if orderIndex >= 0:
        source.tabOrder.delete(orderIndex)
      target.documents.add document
      if identifier notin target.tabOrder:
        target.tabOrder.add identifier
    if source.editorView.bufferIds.len == 0 and source.documents.len == 0:
      controller.removeGroup(source)
    else:
      source.editorView.lastTabs.setLen(0)
      source.editorView.refresh()
      let fallback = source.pane.documentTabs.selectedDocumentTabItem()
      if not fallback.isNil:
        controller.activatePaneTab(source, fallback.identifier(), focus = false)
  controller.activeGroup = target
  target.selectedTabIdentifier = identifier
  target.editorView.lastTabs.setLen(0)
  target.editorView.refresh()
  controller.activatePaneTab(target, identifier)

proc splitCurrentPaneTab(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    position: nimkit.DockPosition,
): bool =
  if controller.isNil or source.isNil or position == nimkit.dpCenter:
    return false
  let selectedItem = source.pane.documentTabs.selectedDocumentTabItem()
  if selectedItem.isNil:
    return false
  let
    identifier = selectedItem.identifier()
    duplicatesCurrentTab = source.pane.documentTabs.len == 1
  var
    id: KosmoBufferId
    bufferIds: seq[KosmoBufferId]
    duplicateDocument: KosmoPaneDocument
  if identifier.parseTabIdentifier(id):
    bufferIds.add id
  else:
    let document = source.documentForIdentifier(identifier)
    if document.isNil:
      return false
    if duplicatesCurrentTab:
      try:
        duplicateDocument = document.duplicate()
      except nimkit.TerminexSessionError as error:
        if not source.editorView.statusLabel.isNil:
          source.editorView.statusLabel.text = error.msg
        return false
      if duplicateDocument.isNil:
        if not source.editorView.statusLabel.isNil:
          source.editorView.statusLabel.text = "This tab cannot be duplicated"
        return false

  let target = controller.newEditorGroup(source.workspace, source.window, bufferIds)
  if not source.workspace.splitPanel(source.panel, target.panel, position):
    if not duplicateDocument.isNil:
      discard duplicateDocument.close()
    controller.removeGroup(target)
    return false
  if duplicatesCurrentTab:
    if duplicateDocument.isNil:
      controller.activatePaneTab(target, identifier)
      return true
    let opened = controller.openPaneDocument(target, duplicateDocument)
    if opened and
        target.documentForIdentifier(duplicateDocument.identifier) == duplicateDocument:
      return true
    discard duplicateDocument.close()
    controller.removeGroup(target)
    return false
  controller.finishPaneTabMove(source, target, identifier)
  true

proc splitCurrentBuffer(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    position: nimkit.DockPosition,
): bool =
  let selectedItem = source.pane.documentTabs.selectedDocumentTabItem()
  if selectedItem.isNil:
    return
  var id: KosmoBufferId
  if not selectedItem.identifier().parseTabIdentifier(id):
    return controller.splitCurrentPaneTab(source, position)
  let target = controller.newEditorGroup(source.workspace, source.window, [id])
  if not source.workspace.splitPanel(source.panel, target.panel, position):
    controller.removeGroup(target)
    return
  controller.activatePaneTab(target, id.tabIdentifier)
  true

proc splitNewBufferBelow(
    controller: KosmoDockController, source: KosmoEditorGroup
): bool =
  let bufferId = controller.editor.newEmptyBuffer()
  if bufferId.isNone:
    return
  let target =
    controller.newEditorGroup(source.workspace, source.window, [bufferId.get])
  if not source.workspace.splitPanel(source.panel, target.panel, nimkit.dpBottom):
    controller.removeGroup(target)
    return
  controller.activatePaneTab(target, bufferId.get.tabIdentifier)
  true

proc preferredPaneResponder(group: KosmoEditorGroup): nimkit.Responder =
  let document = group.documentForIdentifier(group.selectedTabIdentifier)
  if not document.isNil and not document.preferredFirstResponder.isNil:
    nimkit.Responder(document.preferredFirstResponder)
  elif group.pane.contentView == nimkit.View(group.pane.markdownView):
    nimkit.Responder(group.pane.markdownView)
  else:
    nimkit.Responder(group.editorView)

proc focusGroup(controller: KosmoDockController, group: KosmoEditorGroup): bool =
  if controller.isNil or group.isNil or group.window.isNil or group.window.isClosed():
    return
  controller.activatePanelWindow(group.window)
  controller.activateGroup(group.editorView)
  result = group.window.makeFirstResponder(group.preferredPaneResponder())
  group.editorView.refresh()

proc focusNextGroup(controller: KosmoDockController, source: KosmoEditorGroup): bool =
  var candidates: seq[KosmoEditorGroup]
  for group in controller.groups:
    if group.workspace == source.workspace:
      candidates.add group
  let index = candidates.find(source)
  if candidates.len < 2 or index < 0:
    return
  controller.focusGroup(candidates[(index + 1) mod candidates.len])

proc focusSpatialGroup(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    direction: KosmoPaneCommand,
): bool =
  let sourceRect = source.panel.rectToView(source.panel.bounds(), source.workspace)
  let
    sourceX = sourceRect.origin.x + sourceRect.size.width * 0.5'f32
    sourceY = sourceRect.origin.y + sourceRect.size.height * 0.5'f32
  var
    target: KosmoEditorGroup
    bestScore = float32.high
  for candidate in controller.groups:
    if candidate == source or candidate.workspace != source.workspace:
      continue
    let candidateRect =
      candidate.panel.rectToView(candidate.panel.bounds(), candidate.workspace)
    let
      dx = candidateRect.origin.x + candidateRect.size.width * 0.5'f32 - sourceX
      dy = candidateRect.origin.y + candidateRect.size.height * 0.5'f32 - sourceY
      eligible =
        case direction
        of kpcFocusLeft:
          dx < 0.0'f32
        of kpcFocusRight:
          dx > 0.0'f32
        of kpcFocusAbove:
          dy < 0.0'f32
        of kpcFocusBelow:
          dy > 0.0'f32
        else:
          false
    if not eligible:
      continue
    let score =
      case direction
      of kpcFocusLeft, kpcFocusRight:
        abs(dx) + abs(dy) * 0.35'f32
      of kpcFocusAbove, kpcFocusBelow:
        abs(dy) + abs(dx) * 0.35'f32
      else:
        float32.high
    if score < bestScore:
      bestScore = score
      target = candidate
  controller.focusGroup(target)

proc closePane(controller: KosmoDockController, source: KosmoEditorGroup): bool =
  if source.workspace.len <= 1:
    return
  for document in source.documents:
    if not document.closeable or not document.close():
      return
  var replacement: KosmoEditorGroup
  for candidate in controller.groups:
    if candidate != source and candidate.workspace == source.workspace:
      replacement = candidate
      break
  controller.removeGroup(source)
  controller.focusGroup(replacement)

proc containingSplit(
    source: KosmoEditorGroup, axis: nimkit.LayoutAxis
): tuple[splitView: nimkit.SplitView, paneIndex: int] =
  var child = nimkit.View(source.panel)
  while not child.isNil:
    let parent = child.superview()
    if parent of nimkit.SplitView and nimkit.SplitView(parent).splitAxis == axis:
      return (
        splitView: nimkit.SplitView(parent),
        paneIndex: nimkit.SplitView(parent).paneIndex(child),
      )
    child = parent
  (splitView: nil, paneIndex: -1)

proc resizePane(source: KosmoEditorGroup, axis: nimkit.LayoutAxis, grow: bool): bool =
  const ResizeStep = 32.0'f32
  let context = source.containingSplit(axis)
  if context.splitView.isNil or context.splitView.paneCount() < 2 or
      context.paneIndex < 0:
    return
  let
    hasFollowing = context.paneIndex < context.splitView.paneCount() - 1
    dividerIndex =
      if hasFollowing:
        context.paneIndex
      else:
        context.paneIndex - 1
    direction =
      if hasFollowing:
        (if grow: 1.0'f32 else: -1.0'f32)
      else:
        (if grow: -1.0'f32 else: 1.0'f32)
    position = context.splitView.positionOfDivider(dividerIndex)
  context.splitView.setPositionOfDivider(
    dividerIndex, position + direction * ResizeStep
  )
  true

proc equalizeSplits(view: nimkit.View) =
  if view of nimkit.SplitView:
    let splitView = nimkit.SplitView(view)
    var state = splitView.captureState()
    for index in 0 ..< state.fractions.len:
      state.fractions[index] = 1.0'f32
    splitView.restoreState(state)
  for child in view.xSubviews:
    child.equalizeSplits()

proc performPaneCommand(
    controller: KosmoDockController, source: KosmoEditorGroup, command: KosmoPaneCommand
): bool =
  if controller.isNil or source.isNil:
    return
  case command
  of kpcSplitBelow:
    controller.splitCurrentBuffer(source, nimkit.dpBottom)
  of kpcSplitRight:
    controller.splitCurrentBuffer(source, nimkit.dpRight)
  of kpcNewBelow:
    controller.splitNewBufferBelow(source)
  of kpcFocusNext:
    controller.focusNextGroup(source)
  of kpcFocusLeft, kpcFocusBelow, kpcFocusAbove, kpcFocusRight:
    controller.focusSpatialGroup(source, command)
  of kpcClose:
    controller.closePane(source)
  of kpcGrowHeight:
    source.resizePane(nimkit.laVertical, true)
  of kpcShrinkHeight:
    source.resizePane(nimkit.laVertical, false)
  of kpcShrinkWidth:
    source.resizePane(nimkit.laHorizontal, false)
  of kpcGrowWidth:
    source.resizePane(nimkit.laHorizontal, true)
  of kpcEqualize:
    source.workspace.rootView().equalizeSplits()
    true
  of kpcNone:
    false

proc screenPoint(tabs: nimkit.DocumentTabs, location: nimkit.Point): nimkit.Point =
  let owner = tabs.window()
  if owner of nimkit.Window:
    return nimkit.Window(owner).convertPointToScreen(tabs.pointToWindow(location))
  tabs.pointToWindow(location)

proc targetAtScreenPoint(
    controller: KosmoDockController, point: nimkit.Point
): tuple[workspace: nimkit.DockView, target: nimkit.DockDropTarget] =
  for host in controller.hosts:
    if not host.window.isNil and not host.window.isClosed():
      let
        windowPoint = host.window.convertPointFromScreen(point)
        workspacePoint = host.workspace.pointFromWindow(windowPoint)
      if host.workspace.bounds().contains(workspacePoint):
        var target = host.workspace.dropTargetAtPoint(workspacePoint)
        if target.valid():
          let group = controller.groupForPanel(target.panel)
          if not group.isNil:
            let tabPoint = group.editorView.documentTabs.pointFromView(
              workspacePoint, host.workspace
            )
            if group.editorView.documentTabs.bounds().contains(tabPoint):
              let panelRect =
                target.panel.rectToView(target.panel.bounds(), host.workspace)
              target = nimkit.DockDropTarget(
                panel: target.panel, position: nimkit.dpCenter, rect: panelRect
              )
          return (host.workspace, target)

proc clearDockTargets(controller: KosmoDockController) =
  for host in controller.hosts:
    host.workspace.clearDropTarget()

proc updateDockTarget(
    controller: KosmoDockController, tabs: nimkit.DocumentTabs, location: nimkit.Point
) =
  if controller.isNil:
    return
  controller.clearDockTargets()
  let resolved = controller.targetAtScreenPoint(tabs.screenPoint(location))
  if not resolved.workspace.isNil and resolved.target.valid():
    resolved.workspace.dropTarget = resolved.target

protocol KosmoDetachedContentLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(content: KosmoDetachedContentView) =
    let bounds = content.bounds()
    content.statusLabel.setFrameFromLayout(
      nimkit.rect(
        0,
        max(bounds.size.height - KosmoStatusBarHeight, 0.0'f32),
        bounds.size.width,
        KosmoStatusBarHeight,
      )
    )
    content.workspace.setFrameFromLayout(
      nimkit.rect(
        0, 0, bounds.size.width, max(bounds.size.height - KosmoStatusBarHeight, 1.0'f32)
      )
    )

proc newKosmoDetachedContentView(
    workspace: nimkit.DockView, statusLabel: nimkit.Label
): KosmoDetachedContentView =
  result = KosmoDetachedContentView(workspace: workspace, statusLabel: statusLabel)
  result.initViewFields()
  result.addSubview(workspace)
  result.addSubview(statusLabel)
  discard result.withProtocol(KosmoDetachedContentLayout)

protocol KosmoDetachedWindowLifecycleDelegate of nimkit.WindowDelegateProtocol:
  method windowDidClose(
      lifecycle: KosmoDetachedWindowLifecycle, window: nimkit.Window
  ) =
    if lifecycle.controller.isNil:
      return
    let controller = lifecycle.controller[]
    var hostedGroups: seq[KosmoEditorGroup]
    for group in controller.groups:
      if group.window == window:
        hostedGroups.add group
    let closeDocuments = controller.frontend.isNil or not controller.frontend[].xClosed
    for group in hostedGroups:
      if closeDocuments:
        for document in group.documents:
          discard document.close()
      controller.removeGroup(group)
    for index in countdown(controller.hosts.high, 0):
      if controller.hosts[index].window == window:
        controller.hosts.delete(index)

proc detachPaneTab(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    identifier: string,
    screenLocation: nimkit.Point,
) =
  if controller.frontend.isNil:
    return
  let
    frontend = controller.frontend[]
    workspace = nimkit.newDockView()
    statusLabel = nimkit.newStatusLabel("Ready")
    contentView = newKosmoDetachedContentView(workspace, statusLabel)
    window = nimkit.newWindow(
      "Kosmo",
      nimkit.rect(screenLocation.x - 360.0'f32, screenLocation.y - 24.0'f32, 720, 520),
    )
    host = KosmoDockHost(
      workspace: workspace,
      window: window,
      contentView: contentView,
      statusLabel: statusLabel,
    )
    lifecycle = KosmoDetachedWindowLifecycle(controller: controller.unsafeWeakRef())
  lifecycle.initResponder()
  discard lifecycle.withProtocol(KosmoDetachedWindowLifecycleDelegate)
  window.delegate = lifecycle
  controller.hosts.add host
  controller.installShortcutBindings(window)
  var
    id: KosmoBufferId
    bufferIds: seq[KosmoBufferId]
  if identifier.parseTabIdentifier(id):
    bufferIds.add id
  let group =
    controller.newEditorGroup(workspace, window, bufferIds, addToWorkspace = true)
  controller.finishPaneTabMove(source, group, identifier)
  window.setContentView(contentView)
  frontend.application.addWindow(window)
  if frontend.application.isRunning():
    frontend.application.activateWindow(window)

proc finishDockDrag(
    controller: KosmoDockController,
    tabs: nimkit.DocumentTabs,
    item: nimkit.DocumentTabItem,
    location: nimkit.Point,
) =
  if controller.isNil or item.isNil:
    return
  let
    point = tabs.screenPoint(location)
    resolved = controller.targetAtScreenPoint(point)
    source = controller.groupForTabs(tabs)
  controller.clearDockTargets()
  if source.isNil:
    return
  let identifier = item.identifier()
  var id: KosmoBufferId
  if not identifier.parseTabIdentifier(id) and
      source.documentForIdentifier(identifier).isNil:
    return

  if resolved.target.valid():
    let target = controller.groupForPanel(resolved.target.panel)
    if target.isNil:
      return
    if resolved.target.position == nimkit.dpCenter:
      if target != source:
        controller.finishPaneTabMove(source, target, identifier)
    else:
      let bufferIds =
        if identifier.parseTabIdentifier(id):
          @[id]
        else:
          @[]
      let next = controller.newEditorGroup(resolved.workspace, target.window, bufferIds)
      if resolved.workspace.splitPanel(
        target.panel, next.panel, resolved.target.position
      ):
        controller.finishPaneTabMove(source, next, identifier)
      else:
        controller.removeGroup(next)
  else:
    controller.detachPaneTab(source, identifier, point)

proc openPaneDocument(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    document: KosmoPaneDocument,
    insertAfterSelected = false,
): bool =
  if controller.isNil or group.isNil or document.isNil or document.identifier.len == 0 or
      document.contentView.isNil:
    return
  var bufferId: KosmoBufferId
  if document.identifier.parseTabIdentifier(bufferId):
    return
  for candidate in controller.groups:
    if not candidate.documentForIdentifier(document.identifier).isNil:
      controller.activatePaneTab(candidate, document.identifier)
      return true
  if document.preferredFirstResponder.isNil:
    document.preferredFirstResponder = document.contentView
  group.documents.add document
  let selectedIndex =
    if insertAfterSelected:
      group.tabOrder.find(group.selectedTabIdentifier)
    else:
      -1
  group.tabOrder.insert(
    document.identifier,
    if selectedIndex >= 0:
      selectedIndex + 1
    else:
      group.tabOrder.len,
  )
  group.selectedTabIdentifier = document.identifier
  group.editorView.lastTabs.setLen(0)
  group.editorView.refresh()
  controller.activatePaneTab(group, document.identifier)
  true

proc openTerminalLink(lifecycle: KosmoWindowLifecycle, link: string) {.slot.} =
  if lifecycle.isNil or lifecycle.frontend.isNil:
    return
  let frontend = lifecycle.frontend[]
  if not frontend.isNil and not frontend.application.isNil:
    discard frontend.application.workspace().openUrl(link)

proc workspaceGitChanged(lifecycle: KosmoWindowLifecycle) {.slot.} =
  if not lifecycle.frontend.isNil and not lifecycle.frontend[].xClosed:
    # All panes share one Moe engine. Invalidate once, not once per pane.
    let frontend = lifecycle.frontend[]
    frontend.dockController.editor.notifyGitRepositoryChanged()

proc pollWorkspaceGit(lifecycle: KosmoWindowLifecycle) {.slot.} =
  if not lifecycle.frontend.isNil and not lifecycle.frontend[].xClosed:
    let frontend = lifecycle.frontend[]
    let controller = frontend.dockController
    frontend.fileTree.workspaceFiles.setGitRoots(controller.editor.gitWatchRoots())
    if controller.editor.pollGitStatus():
      for group in controller.groups:
        group.editorView.refresh()

proc setTerminalEnvironment(
    options: var nimkit.TerminexSpawnOptions, name, value: string
) =
  for variable in options.environment.mitems:
    if variable.name == name:
      variable.value = value
      return
  options.environment.add nimkit.initTerminalEnvironmentVariable(name, value)

proc prepareInteractiveTerminal(options: var nimkit.TerminexSpawnOptions) =
  when defined(macosx):
    if options.command.len == 0:
      var shell = options.shell
      if shell.len == 0:
        shell = getEnv("SHELL")
      if shell.len == 0:
        shell = "/bin/sh"
      # Apps opened by Launch Services inherit a minimal environment. Let the
      # login shell rebuild it, then replace that shell with the interactive one.
      options.command = "exec " & quoteShell(shell)

proc newTerminalDocument(
    controller: KosmoDockController, options: nimkit.TerminexSpawnOptions
): KosmoPaneDocument =
  let terminalView = newKosmoTerminalView()
  var resolvedOptions = options
  resolvedOptions.prepareInteractiveTerminal()
  if not controller.frontend.isNil:
    let frontend = controller.frontend[]
    terminalView.optionAsMeta = frontend.xTerminalOptionAsMeta
    terminalView.allowsLinkActivation = frontend.xTerminalLinksEnabled
    terminalView.connect(
      nimkit.terminalHyperlinkWasActivated, frontend.xWindowLifecycle, openTerminalLink
    )
    if not frontend.xWindowManager.isNil:
      let manager = frontend.xWindowManager[]
      if not manager.cliServer.isNil:
        resolvedOptions.setTerminalEnvironment(
          KosmoCliEndpointEnvironment, manager.cliServer.endpointPath()
        )
        resolvedOptions.setTerminalEnvironment(
          KosmoCliWindowEnvironment, frontend.xCliWindowId
        )
  try:
    terminalView.start(resolvedOptions)
  except nimkit.TerminexSessionError:
    terminalView.close()
    raise

  inc controller.nextDocumentIdentifier
  let weakController = controller.unsafeWeakRef()
  result = newKosmoPaneDocument(
    identifier = KosmoTerminalIdentifierPrefix & $controller.nextDocumentIdentifier,
    title = "Terminal " & $controller.nextDocumentIdentifier,
    contentView = terminalView,
    tooltip = "Terminal",
    onClose = proc(document: KosmoPaneDocument): bool =
      discard document
      terminalView.close()
      true,
    onDuplicate = proc(document: KosmoPaneDocument): KosmoPaneDocument =
      discard document
      if not weakController.isNil:
        result = weakController[].newTerminalDocument(resolvedOptions)
    ,
  )

proc terminalWorkingDirectory(group: KosmoEditorGroup): string =
  if group.isNil:
    return
  let document = group.documentForIdentifier(group.selectedTabIdentifier)
  if document.isNil or document.contentView.isNil or
      not (document.contentView of nimkit.TerminalView):
    return
  let currentDirectory =
    nimkit.TerminalView(document.contentView).session().screenInfo().currentDirectory
  let url = nimkit.initUrl(currentDirectory)
  var path = url.localFilePath()
  when defined(posix):
    # Local shells may include the machine name in OSC 7 file URLs. Treat
    # that host as metadata rather than a UNC path on POSIX.
    if url.isFileUrl() and url.host().len > 0:
      path = url.decodedPath()
  if path.len > 0 and dirExists(path):
    return absolutePath(path)

proc defaultTerminalWorkingDirectory(
    frontend: KosmoApplication, group: KosmoEditorGroup
): string =
  result = group.terminalWorkingDirectory()
  if result.len == 0 and not frontend.isNil and not frontend.fileTree.isNil:
    result = frontend.fileTree.rootPath
  if result.len == 0:
    result = getCurrentDir()

proc openTerminal(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    options: nimkit.TerminexSpawnOptions = nimkit.initTerminalSpawnOptions(),
    insertAfterSelected = true,
): bool =
  if controller.isNil or group.isNil:
    return
  var resolvedOptions = options
  if resolvedOptions.workingDirectory.len == 0 and not controller.frontend.isNil:
    resolvedOptions.workingDirectory =
      controller.frontend[].defaultTerminalWorkingDirectory(group)
  var document: KosmoPaneDocument
  try:
    document = controller.newTerminalDocument(resolvedOptions)
  except nimkit.TerminexSessionError as error:
    if not group.editorView.statusLabel.isNil:
      group.editorView.statusLabel.text = error.msg
    return
  if controller.openPaneDocument(group, document, insertAfterSelected):
    return true
  discard document.close()

proc newEditorTab*(frontend: KosmoApplication): bool {.discardable.} =
  ## Create and select an unnamed buffer in the active editor pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  let
    controller = frontend.dockController
    group = controller.activePaneGroup()
  if group.isNil:
    return
  let bufferId = controller.editor.newEmptyBuffer()
  if bufferId.isNone:
    return
  group.addBuffer(bufferId.get)
  controller.activatePaneTab(group, bufferId.get.tabIdentifier)
  result = true

proc newTerminal*(frontend: KosmoApplication): bool {.discardable.} =
  ## Open a terminal in the active editor pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  let
    controller = frontend.dockController
    group = controller.activePaneGroup()
  result = controller.openTerminal(group)

protocol KosmoContentLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(content: KosmoContentView) =
    let
      bounds = content.bounds()
      splitWidthChanged =
        content.setInitialDivider and
        abs(bounds.size.width - content.lastSplitWidth) > 0.001'f32
    content.statusLabel.setFrameFromLayout(
      nimkit.rect(
        0,
        max(bounds.size.height - KosmoStatusBarHeight, 0.0'f32),
        bounds.size.width,
        KosmoStatusBarHeight,
      )
    )
    content.splitView.setFrameFromLayout(
      nimkit.rect(
        0, 0, bounds.size.width, max(bounds.size.height - KosmoStatusBarHeight, 1.0'f32)
      )
    )
    if not content.quickOpenPanel.isNil:
      let
        availableWidth = max(bounds.size.width - 48.0'f32, 1.0'f32)
        availableHeight = max(
          bounds.size.height - KosmoStatusBarHeight - KosmoQuickOpenTopInset -
            KosmoQuickOpenBottomInset,
          1.0'f32,
        )
        popupWidth = min(availableWidth, 640.0'f32)
        popupHeight = min(availableHeight, 360.0'f32)
      content.quickOpenPanel.setFrameFromLayout(
        nimkit.rect(
          max((bounds.size.width - popupWidth) * 0.5'f32, 0.0'f32),
          KosmoQuickOpenTopInset + content.quickOpenPanel.presentationOffset(),
          popupWidth,
          popupHeight,
        )
      )
    if not content.setInitialDivider and bounds.size.width > 0.0'f32:
      content.splitView.setPositionOfDivider(0, min(bounds.size.width * 0.25, 260.0))
      content.setInitialDivider = true
    elif splitWidthChanged:
      content.splitView.setPositionOfDivider(0, content.fileTreeWidth)
    content.lastSplitWidth = bounds.size.width
    if content.splitView.paneCount() > 1 and not splitWidthChanged:
      content.fileTreeWidth = content.splitView.positionOfDivider(0)
