## Frontend-owned clipboard, background work, output, and recovery lifecycles.
## Included by the Moe facade to keep its engine and callbacks private.

var kosmoMoeHosts {.threadvar.}: Table[pointer, WeakRef[KosmoEditor]]

let terminalHookOutputPresenter = moeHooks.hookOutputPresenter
moeHooks.hookOutputPresenter = proc(engine: Editor, output: seq[string]) =
  let key = cast[pointer](engine)
  if kosmoMoeHosts.hasKey(key):
    let host = kosmoMoeHosts[key]
    if not host.isNil:
      host[].hostCommands.add KosmoHostCommand(
        kind: KosmoHostCommandKind.Output, text: output.join("\n"), keepFocus: true
      )
  elif not terminalHookOutputPresenter.isNil:
    terminalHookOutputPresenter(engine, output)

proc installFrontendHooks(editor: KosmoEditor) =
  kosmoMoeHosts[cast[pointer](editor.editor)] = editor.unsafeWeakRef()

proc clearFrontendHooks(editor: KosmoEditor) =
  kosmoMoeHosts.del(cast[pointer](editor.editor))
  editor.clipboardRead = nil
  editor.clipboardWrite = nil
  if editor.editor.recovery.isSome:
    for session in editor.recoverySessions:
      discard editor.editor.recovery.get.store.discardSession(session)
  editor.hostCommands.setLen(0)

proc configureClipboard*(
    editor: KosmoEditor, read: KosmoClipboardReader, write: KosmoClipboardWriter
) =
  ## Supply synchronous host clipboard access. Callbacks belong to this editor.
  if editor.isNil or editor.editor.isNil:
    return
  editor.clipboardRead = read
  editor.clipboardWrite = write
  editor.clipboardValues = default(array[KosmoClipboardSelection, Option[string]])

proc clipboardRegister(selection: KosmoClipboardSelection): char =
  if selection == KosmoClipboardSelection.Primary: '*' else: '+'

proc readHostClipboard(editor: KosmoEditor) =
  if editor.clipboardRead.isNil:
    return
  let registers = editor.editor.state.registers
  for selection in KosmoClipboardSelection:
    try:
      let text = editor.clipboardRead(selection)
      # Preserve linewise metadata when reading back our own write. An empty
      # external clipboard must clear the cached register as well.
      if some(text) != editor.clipboardValues[selection]:
        registers.setClipboardRegister(
          selection.clipboardRegister, text, text.endsWith("\n")
        )
      editor.clipboardValues[selection] = some(text)
    except CatchableError as error:
      editor.editor.state.statusMessage = "Clipboard read failed: " & error.msg

proc writeHostClipboard(editor: KosmoEditor) =
  if editor.clipboardWrite.isNil:
    return
  let registers = editor.editor.state.registers
  for selection in KosmoClipboardSelection:
    let value =
      if selection == KosmoClipboardSelection.Primary:
        registers.primarySelection
      else:
        registers.clipboardSelection
    let text = value.getContent()
    if some(text) != editor.clipboardValues[selection]:
      try:
        if editor.clipboardWrite(selection, text):
          editor.clipboardValues[selection] = some(text)
        else:
          editor.editor.state.statusMessage = "Clipboard write failed"
      except CatchableError as error:
        editor.editor.state.statusMessage = "Clipboard write failed: " & error.msg

proc loadHooks*(editor: KosmoEditor, path: string): FileOpenResult =
  ## Load Moe's [Hook] settings without replacing Kosmo's frontend configuration.
  if editor.isNil or editor.editor.isNil:
    return FileOpenResult(message: "The editor is closed.")
  if not fileExists(path):
    return FileOpenResult(message: "Hook configuration does not exist: " & path)
  let loaded = loadConfigFromToml(path)
  if loaded.isErr:
    return FileOpenResult(message: loaded.error)
  let (configuration, validation) = loaded.get
  for issue in validation.errors:
    if issue.name.startsWith("Hook"):
      return FileOpenResult(message: issue.toMessage())
  editor.editor.config.hooks = configuration.hooks
  FileOpenResult(loaded: true)

proc saveBuffer*(
    editor: KosmoEditor, id: KosmoBufferId, filename = none(string), force = false
): KosmoSaveResult =
  ## Save the requested buffer using Moe's complete write and hook bookkeeping.
  if editor.isNil or editor.editor.isNil:
    return KosmoSaveResult(message: "The editor is closed.")
  let buffer = editor.editor.bufferById(id.toMoeBufferId)
  if buffer.isNone:
    return KosmoSaveResult(message: "Buffer no longer available")
  let outcome = editor.inWorkingDirectory:
    editor.editor.saveFile(buffer.get, filename, force)
  if outcome.isErr:
    editor.editor.state.statusMessage = outcome.error
    return KosmoSaveResult(message: outcome.error)
  editor.forgetTemporaryBuffer(id.toMoeBufferId)
  KosmoSaveResult(saved: true)

proc frontendRevision*(editor: KosmoEditor): uint64 =
  ## Changes when the idle pump observes text, status, diagnostics, or popup changes.
  if not editor.isNil:
    result = editor.xFrontendRevision

proc jobsText*(editor: KosmoEditor, stop = false): string =
  ## List or stop external work using Moe's shared cancellation and job lanes.
  if editor.isNil or editor.editor.isNil:
    return "The editor is closed."
  if stop:
    let count = editor.editor.stopRunningCommands()
    return "Stopped " & $count & " external commands"
  let commands = editor.editor.runningCommands()
  if commands.len == 0:
    "No external commands are running"
  else:
    commands.join("\n")

proc visibleFrontendFingerprint(editor: KosmoEditor): Hash =
  let engine = editor.editor
  result = hash($engine.frontendStatus())
  result = result !& hash(engine.frontendGitStatusRevision())
  result = result !& hash(engine.state.ui.lspProgressText)
  result = result !& hash($editor.popupMenu())
  result = result !& hash($engine.state.notificationPopup.queue)
  result = result !& hash(engine.state.lspCache.hoverPopup.state)
  result = result !& hash(engine.state.lspCache.hoverPopup.display.lines)
  let signature = engine.handlerManager.insertHandler.signatureHelpManager
  result = result !& hash(signature.state) !& hash($signature.display)
  result = result !& hash($engine.state.lspCache.codeLensPicker)
  result = result !& hash($engine.state.lspCache.codeLensCache)
  result = result !& hash($engine.state.lspCache.inlayHintCache)
  result = result !& hash($engine.state.lspCache.documentHighlightCache)
  for buffer in engine.buffers:
    result = result !& hash(int(buffer.id))
    result = result !& hash(buffer.contentVersion)
    result = result !& hash(buffer.isModified)
    result = result !& hash($buffer.diagnostics)
    result = result !& hash(buffer.highlight.semanticContentVersion)
    result = result !& hash(buffer.highlightNeedsUpdate)
  result = !$result

proc takeEngineOutput(editor: KosmoEditor) =
  let engine = editor.editor
  let output = engine.bufferById(engine.state.commandOutputBufferId)
  if output.isNone:
    return
  let buffer = output.get
  var keepFocus = true
  let previousWindow = engine.activeWindow
  for index in countdown(engine.windowManager.windows.high, 0):
    let window = engine.windowManager.windows[index]
    if window.tabBufferId == buffer.id:
      keepFocus = keepFocus and window != previousWindow
      engine.windowManager.activateWindow(index)
      discard engine.windowManager.closeWindow(engine.showStatusLine)
  let previousIndex = engine.windowManager.windows.find(previousWindow)
  if previousIndex >= 0:
    engine.windowManager.activateWindow(previousIndex)
  engine.syncActiveWindow()
  engine.enforceModePolicy()
  editor.hostCommands.add KosmoHostCommand(
    kind: KosmoHostCommandKind.Output,
    text: buffer.getTextString(),
    keepFocus: keepFocus,
  )
  let index = engine.bufferIndexById(buffer.id)
  if index >= 0:
    discard engine.removeBufferAt(index)
  engine.state.commandOutputBufferId = BufferId(0)

proc configureRecovery*(editor: KosmoEditor, directory: string) =
  ## Use a host-owned store; this does not install terminal signal handlers.
  if editor.isNil or editor.editor.isNil:
    return
  if editor.recoverySessions.len > 0:
    raise
      newException(ValueError, "Cannot change a recovery store with live checkpoints")
  editor.recoveryDirectory = normalizedPath(absolutePath(directory))
  editor.editor.recovery = some(moeRecovery.newRecoveryIndex(editor.recoveryDirectory))

proc recoveryEntries*(editor: KosmoEditor): seq[KosmoRecoveryEntry] =
  ## List preserved work, excluding this running editor's own checkpoints.
  if editor.isNil or editor.editor.isNil or editor.editor.recovery.isNone:
    return
  let index = editor.editor.recovery.get
  index.refresh()
  let state =
    moeRecoveryManager.initRecoveryManagerState(index, "", editor.editor.buffers)
  for entry in state.items:
    if entry.sessionDir notin editor.recoverySessions:
      result.add KosmoRecoveryEntry(
        copyPath: entry.copyPath,
        originalPath: entry.originalPath,
        savedAt: moeRecoveryManager.formatTimestamp(entry.savedAt),
        note: moeRecoveryManager.noteFor(entry),
        reviewed: entry.reviewed,
        restored: entry.restored,
        changedSince: entry.changedSince,
      )

proc preserveModifiedBuffers*(editor: KosmoEditor): seq[string] =
  ## Explicitly preserve unsaved work. Returned copy paths remain after clean close.
  if editor.isNil or editor.editor.isNil or editor.editor.recovery.isNone:
    return
  result = moeEmergency.emergencySaveBuffers(
    editor.editor,
    moeRecovery.ckUnknown,
    "Kosmo preserved work",
    baseDir = editor.recoveryDirectory,
  )
  editor.editor.recovery.get.refresh()

proc restoreRecoveryCopy*(editor: KosmoEditor, copyPath: string): FileOpenResult =
  ## Restore into the original buffer as an undoable edit; never write its file.
  if editor.isNil or editor.editor.isNil or editor.editor.recovery.isNone:
    return FileOpenResult(message: "Recovery is not configured.")
  let index = editor.editor.recovery.get
  index.refresh()
  let state =
    moeRecoveryManager.initRecoveryManagerState(index, "", editor.editor.buffers)
  for entryIndex, entry in state.items:
    if entry.copyPath != copyPath:
      continue
    let engine = editor.editor
    discard editor.focusTextWindow()
    engine.finalizeInsertSessionForBufferSwitch(engine.activeBuffer)
    # Reuse Moe's restore transaction, rollback, encoding, and settled-copy
    # bookkeeping. The temporary listing covers this window without a split
    # or a registered buffer and never reaches the native renderer.
    let entered = engine.enterViewerMode(
      EditorMode.RecoveryManager,
      moeTypes.ModeState(
        kind: moeTypes.ModeStateKind.mskRecoveryManager, recoveryManager: state
      ),
      state.createRecoveryManagerTextBuffer(),
      moeTypes.ViewerPlacement.vpInPlace,
    )
    if entered.isErr:
      return FileOpenResult(message: entered.error)
    defer:
      engine.leaveViewerMode(EditorMode.RecoveryManager)
      engine.enforceModePolicy()
    discard engine.processRecoveryResult(
      moeHandlerResult.HandlerResult(
        kind: moeHandlerResult.hrRecoveryManagerRestore,
        restoreRecoveryIndex: entryIndex,
      )
    )
    if engine.activeWindow.modeState.kind == moeTypes.ModeStateKind.mskRecoveryManager:
      return FileOpenResult(message: engine.state.statusMessage)
    return FileOpenResult(loaded: true)
  FileOpenResult(message: "Preserved copy no longer available")

proc discardRecoveryCopy*(editor: KosmoEditor, copyPath: string): FileOpenResult =
  ## Discard a copy that belongs to the configured store.
  if editor.isNil or editor.editor.isNil or editor.editor.recovery.isNone:
    return FileOpenResult(message: "Recovery is not configured.")
  let index = editor.editor.recovery.get
  index.refresh()
  for session in index.sessions:
    for file in session.files:
      if file.path == copyPath:
        var reason: string
        if not index.store.discardCopy(copyPath, session.dir, reason):
          return FileOpenResult(message: reason)
        index.refresh()
        return FileOpenResult(loaded: true)
  FileOpenResult(message: "Preserved copy no longer available")

proc checkpointRecovery(editor: KosmoEditor) =
  if editor.editor.recovery.isNone:
    return
  var fingerprint: Hash
  var modified = 0
  for buffer in editor.editor.buffers:
    if buffer.isModified:
      inc modified
      fingerprint = fingerprint !& hash(int(buffer.id)) !& hash(buffer.contentVersion)
  if fingerprint != editor.recoveryFingerprint:
    editor.recoveryFingerprint = fingerprint
    if editor.recoveryCheckpoint.isNone:
      editor.recoveryCheckpoint = some(getMonoTime() + initDuration(seconds = 5))
  if modified == 0:
    for session in editor.recoverySessions:
      discard editor.editor.recovery.get.store.discardSession(session)
    editor.recoverySessions.setLen(0)
    editor.recoveryCheckpoint = none(MonoTime)
    return
  if editor.recoveryCheckpoint.isNone or getMonoTime() < editor.recoveryCheckpoint.get:
    return
  editor.recoveryCheckpoint = none(MonoTime)
  let copies = editor.preserveModifiedBuffers()
  if copies.len > 0:
    let session = copies[0].parentDir().parentDir()
    if copies.len == modified:
      for old in editor.recoverySessions:
        discard editor.editor.recovery.get.store.discardSession(old)
      editor.recoverySessions.setLen(0)
    editor.recoverySessions.add session

proc nonblockingAsyncStep() =
  # A due timer forces Chronos' OS poll timeout to zero, even with no ready I/O.
  let timer = moeAsync.setTimer(
    moeAsync.Moment.now(),
    proc(data: pointer) {.gcsafe, raises: [].} =
      discard,
  )
  try:
    moeAsync.poll()
  finally:
    moeAsync.clearTimer(timer)

proc stopFrontendWork(editor: KosmoEditor) =
  let engine = editor.editor
  discard engine.stopRunningCommands()
  engine.releaseExternalResources()
  # The last native window may own the only Chronos pump. Drain cancellation
  # and reaping callbacks before dropping it, with a bounded monotonic wait.
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while true:
    nonblockingAsyncStep()
    if engine.runningCommands().len == 0 or getMonoTime() >= deadline:
      break
    sleep(1)

proc pollFrontendWork*(editor: KosmoEditor): bool =
  ## Advance Moe and Chronos without blocking; report all visible state changes.
  if editor.isNil or editor.editor.isNil or editor.pollingWork:
    return
  editor.pollingWork = true
  defer:
    editor.pollingWork = false
  result = editor.pollKeyMappingTimeout()
  editor.inWorkingDirectory:
    # Terminal-only operations never enter the TUI's blocking suspend path.
    var pending: seq[moeTypes.PendingAsyncOp]
    for operation in editor.editor.state.pending:
      case operation.kind
      of moeTypes.paoQuickRun, moeTypes.paoFilter:
        pending.add operation
      of moeTypes.paoTerminalCommand, moeTypes.paoShellCommand:
        editor.hostCommands.add KosmoHostCommand(
          kind: KosmoHostCommandKind.Terminal, filename: some(operation.command)
        )
      of moeTypes.paoManPage:
        editor.hostCommands.add KosmoHostCommand(
          kind: KosmoHostCommandKind.Terminal,
          filename: some("man " & quoteShell(operation.command)),
        )
      of moeTypes.paoBackground:
        editor.editor.state.statusMessage =
          "Use Kosmo's native terminal for this command"
    editor.editor.state.pending = move(pending)
    moeAsync.asyncSpawn editor.editor.handlePendingAsyncOperations(FrontendHooks())
    nonblockingAsyncStep()
    editor.editor.tick()
  editor.takeEngineOutput()
  editor.checkpointRecovery()
  let fingerprint = editor.visibleFrontendFingerprint()
  result =
    result or fingerprint != editor.frontendFingerprint or editor.hostCommands.len > 0
  if result:
    inc editor.xFrontendRevision
  editor.frontendFingerprint = fingerprint
