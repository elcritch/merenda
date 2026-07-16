## Built-in Merenda settings panel.

import std/[algorithm, options, os, strutils, tables]

import sigils

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw

import ../accessibility/accessibility
import ../containers/cascadingviews
import ../containers/formviews
import ../containers/stackviews
import ../containers/tabviews
import ../controls/buttons
import ../controls/comboboxes
import ../controls/fontpickers
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/types
import ../responder/responders
import ../text/textfields
import ../themes
import ../view/views
import ./windows

type
  SettingsTheme = enum
    stDefault
    stMacOS
    stMacOSDark
    stNebula
    stPeachy
    stSynthwave83

  SettingsFontSize = enum
    sfs12
    sfs14
    sfs16
    sfs18
    sfs20

  AppearanceHandler* = proc(appearance: Appearance) {.closure.}
  FontSelectionProc = proc(path: string) {.closure.}
  FontLoadingProgressProc = proc(message: string) {.closure.}

  FontCatalogLoader = ref object of AgentActor
    entries: seq[FontCatalogEntry]
    nextEntryIndex: int
    loadedEntryCount: int
    loadedFaceCount: int
    started: bool
    finished: bool

  FontPickerController = ref object of Responder
    items: Table[string, CascadingItem]
    faces: Table[string, FontCatalogFace]
    childIdentifiers: Table[string, seq[string]]
    childIndexes: Table[string, Table[string, int]]
    fontPicker: CascadingView
    needsFontPickerReload: bool
    pendingFontPickerBatchCount: int
    selectionHandler: FontSelectionProc
    progressHandler: FontLoadingProgressProc

  MerendaSettingsWindow* = ref object of Responder
    xWindow: Panel
    xContentView: View
    xFirstResponder: Responder
    fontPickerController: FontPickerController
    fontCatalogLoader: AgentProxy[FontCatalogLoader]
    fontLoadingPool: SigilThreadPoolPtr
    fontLoadingStopped: bool
    applyAppearanceHandler: AppearanceHandler
    activeTheme: SettingsTheme
    previewFontPath: string
    previewFontSize: SettingsFontSize
    appliedFontPath: string
    appliedFontSize: SettingsFontSize
    fontLoadingStatus: string
    preview: Label
    status: Label

const
  FontCatalogBatchSize = 8
  FontCatalogBatchesPerReload = 10

proc fontCatalogLoadRequested(controller: FontPickerController) {.signal.}
proc fontCatalogBatchLoaded(
  loader: FontCatalogLoader,
  entries: seq[FontCatalogEntry],
  loadedEntryCount: int,
  loadedFaceCount: int,
) {.signal.}

proc fontCatalogLoadingFinished(
  loader: FontCatalogLoader, loadedEntryCount: int, loadedFaceCount: int
) {.signal.}

proc fontCatalogLoadingFailed(loader: FontCatalogLoader, message: string) {.signal.}

proc addFontPickerItem(controller: FontPickerController, item: CascadingItem) =
  if item.identifier in controller.items:
    controller.items[item.identifier] = item
    return
  controller.items[item.identifier] = item
  let
    parentIdentifier = item.parentIdentifier
    childIndex = controller.childIdentifiers.getOrDefault(parentIdentifier).len

  controller.childIndexes.mgetOrPut(parentIdentifier, initTable[string, int]())[
    item.identifier
  ] = childIndex
  controller.childIdentifiers.mgetOrPut(parentIdentifier, @[]).add item.identifier

proc reindexFontPickerChildren(
    controller: FontPickerController, parentIdentifier: string
) =
  var indexes = initTable[string, int]()
  for index, identifier in controller.childIdentifiers.getOrDefault(parentIdentifier):
    indexes[identifier] = index
  controller.childIndexes[parentIdentifier] = move indexes

proc sortFontPickerLanguages(controller: FontPickerController) =
  var identifiers = controller.childIdentifiers.getOrDefault("")
  identifiers.sort(
    proc(left, right: string): int =
      let
        leftTitle = controller.items.getOrDefault(left).title
        rightTitle = controller.items.getOrDefault(right).title
        leftIsDefault = leftTitle == DefaultFontLanguage
        rightIsDefault = rightTitle == DefaultFontLanguage
      if leftIsDefault != rightIsDefault:
        return if leftIsDefault: -1 else: 1
      result = cmp(leftTitle.toLowerAscii(), rightTitle.toLowerAscii())
      if result == 0:
        result = cmp(leftTitle, rightTitle)
  )
  controller.childIdentifiers[""] = move identifiers
  controller.reindexFontPickerChildren("")

func fontPickerLanguageIdentifier(language: string): string =
  "system-font-language:" & language.toLowerAscii()

func fontPickerFamilyIdentifier(languageIdentifier, familyIdentifier: string): string =
  languageIdentifier & ":family:" & familyIdentifier

func fontPickerFaceIdentifier(languageIdentifier, faceIdentifier: string): string =
  languageIdentifier & ":face:" & faceIdentifier

func fontPickerFaceTitle(face: FontCatalogFace): string =
  result = if face.style.toLowerAscii() == "regular": "Normal" else: face.style
  if face.variable:
    result.add " (Variable)"

proc addFontPickerLanguage(controller: FontPickerController, language: string): string =
  result = language.fontPickerLanguageIdentifier()
  if result notin controller.items:
    controller.addFontPickerItem(cascadeItem(result, language))
    controller.sortFontPickerLanguages()

proc addFontCatalogEntry(controller: FontPickerController, entry: FontCatalogEntry) =
  for face in entry.faces:
    let languages =
      if face.languages.len > 0:
        face.languages
      else:
        @[face.language]
    for language in languages:
      let
        languageIdentifier = controller.addFontPickerLanguage(language)
        familyIdentifier =
          languageIdentifier.fontPickerFamilyIdentifier(entry.identifier)
        faceIdentifier = languageIdentifier.fontPickerFaceIdentifier(face.identifier)
      if familyIdentifier notin controller.items:
        controller.addFontPickerItem(
          cascadeItem(
            familyIdentifier, entry.family, parentIdentifier = languageIdentifier
          )
        )
      controller.addFontPickerItem(
        cascadeItem(
          faceIdentifier,
          face.fontPickerFaceTitle(),
          parentIdentifier = familyIdentifier,
          leaf = true,
          objectValue = toObj(face.path),
        )
      )
      controller.faces[faceIdentifier] = face

proc reportFontLoadingProgress(
    controller: FontPickerController,
    loadedEntryCount, loadedFaceCount: int,
    finished = false,
) =
  if controller.progressHandler.isNil:
    return
  let prefix = if finished: "Loaded" else: "Loading fonts:"
  controller.progressHandler(
    prefix & " " & $loadedEntryCount & " families, " & $loadedFaceCount & " faces"
  )

proc reloadFontPickerIfVisible(controller: FontPickerController) =
  if controller.fontPicker.isNil or controller.fontPicker.isHiddenOrHasHiddenAncestor():
    return
  controller.fontPicker.reloadData()
  controller.needsFontPickerReload = false
  controller.pendingFontPickerBatchCount = 0

proc loadFontCatalog(loader: FontCatalogLoader) {.slot.} =
  if loader.finished:
    return
  try:
    if not loader.started:
      loader.entries = systemFontCatalog()
      loader.started = true

    var batch = newSeqOfCap[FontCatalogEntry](FontCatalogBatchSize)
    while loader.nextEntryIndex < loader.entries.len and batch.len < FontCatalogBatchSize:
      var loadedEntry = move loader.entries[loader.nextEntryIndex]
      inc loader.nextEntryIndex
      if loadedEntry.family == "Last Resort":
        continue
      for face in loadedEntry.faces.mitems:
        face.loadFontCatalogFaceMetadata()
        inc loader.loadedFaceCount
      batch.add move loadedEntry
      inc loader.loadedEntryCount

    if batch.len > 0:
      emit loader.fontCatalogBatchLoaded(
        move batch, loader.loadedEntryCount, loader.loadedFaceCount
      )
    else:
      loader.finished = true
      loader.entries.setLen(0)
      emit loader.fontCatalogLoadingFinished(
        loader.loadedEntryCount, loader.loadedFaceCount
      )
  except CatchableError as error:
    loader.finished = true
    emit loader.fontCatalogLoadingFailed(error.msg)

proc didLoadFontCatalogBatch(
    controller: FontPickerController,
    entries: seq[FontCatalogEntry],
    loadedEntryCount: int,
    loadedFaceCount: int,
) {.slot.} =
  for entry in entries:
    controller.addFontCatalogEntry(entry)
  controller.needsFontPickerReload = true
  inc controller.pendingFontPickerBatchCount
  if controller.pendingFontPickerBatchCount >= FontCatalogBatchesPerReload:
    controller.reloadFontPickerIfVisible()
  controller.reportFontLoadingProgress(loadedEntryCount, loadedFaceCount)
  emit controller.fontCatalogLoadRequested()

proc didFinishLoadingFontCatalog(
    controller: FontPickerController, loadedEntryCount: int, loadedFaceCount: int
) {.slot.} =
  if controller.needsFontPickerReload:
    controller.reloadFontPickerIfVisible()
  controller.reportFontLoadingProgress(
    loadedEntryCount, loadedFaceCount, finished = true
  )

proc didFailLoadingFontCatalog(
    controller: FontPickerController, message: string
) {.slot.} =
  if not controller.progressHandler.isNil:
    controller.progressHandler("Font loading failed: " & message)

protocol FontPickerTabDelegate of TabViewDelegate:
  method didSelectTabViewItem(
      controller: FontPickerController, tabView: TabView, item: TabViewItem
  ) =
    discard tabView
    if not item.isNil and item.identifier() == "typography" and
        controller.needsFontPickerReload:
      controller.reloadFontPickerIfVisible()

protocol FontPickerDataSource of CascadingDataSource:
  method cascadingNumberOfChildren(
      controller: FontPickerController, view: CascadingView, parentIdentifier: string
  ): int =
    discard view
    controller.childIdentifiers.getOrDefault(parentIdentifier).len

  method cascadingChildIdentifier(
      controller: FontPickerController,
      view: CascadingView,
      parentIdentifier: string,
      index: int,
  ): string =
    discard view
    let children = controller.childIdentifiers.getOrDefault(parentIdentifier)
    if index in 0 ..< children.len:
      children[index]
    else:
      ""

  method cascadingItem(
      controller: FontPickerController, view: CascadingView, identifier: string
  ): CascadingItem =
    discard view
    if identifier in controller.faces and not controller.faces[identifier].metadataLoaded:
      var face = controller.faces[identifier]
      let groupedLanguage = face.language
      face.loadFontCatalogFaceMetadata()
      face.language = groupedLanguage
      controller.faces[identifier] = face
      controller.items[identifier].title = face.fontPickerFaceTitle()
    controller.items.getOrDefault(identifier)

  method indexOfCascadingChildIdentifier(
      controller: FontPickerController,
      view: CascadingView,
      parentIdentifier: string,
      identifier: string,
  ): int =
    discard view
    if parentIdentifier in controller.childIndexes:
      controller.childIndexes[parentIdentifier].getOrDefault(identifier, -1)
    else:
      -1

protocol FontPickerDelegate of CascadingDelegate:
  method didSelectCascadingItem(
      controller: FontPickerController,
      view: CascadingView,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard column
    discard row
    let item = view.cascadingItemWithIdentifier(identifier)
    if not item.leaf or controller.selectionHandler.isNil:
      return
    let path = item.objectValue.getString()
    if path.isSome:
      controller.selectionHandler(path.get())

proc newFontPickerController(): FontPickerController =
  result = FontPickerController(
    items: initTable[string, CascadingItem](),
    faces: initTable[string, FontCatalogFace](),
    childIdentifiers: initTable[string, seq[string]](),
    childIndexes: initTable[string, Table[string, int]](),
  )
  let defaultLanguageIdentifier = result.addFontPickerLanguage(DefaultFontLanguage)
  result.addFontPickerItem(
    cascadeItem(
      DefaultSystemFontIdentifier,
      "System Default",
      parentIdentifier = defaultLanguageIdentifier,
      leaf = true,
      objectValue = toObj(""),
    )
  )
  initResponder(result)
  discard result.withProtocol(FontPickerDataSource)
  discard result.withProtocol(FontPickerDelegate)
  discard result.withProtocol(FontPickerTabDelegate)

const TextStyleRoles = [
  srBox, srButton, srCheckBox, srRadioButton, srTextField, srTextView, srMonoTextView,
  srComboBox, srComboBoxItem, srTab, srTableHeaderCell, srRowItem, srCascadingRowItem,
]

func title(theme: SettingsTheme): string =
  case theme
  of stDefault: "Default"
  of stMacOS: "macOS"
  of stMacOSDark: "macOS Dark"
  of stNebula: "Nebula"
  of stPeachy: "Peachy"
  of stSynthwave83: "Synthwave '83"

func title(size: SettingsFontSize): string =
  case size
  of sfs12: "12 pt"
  of sfs14: "14 pt"
  of sfs16: "16 pt"
  of sfs18: "18 pt"
  of sfs20: "20 pt"

proc fontTitle(path: string): string =
  if path.len == 0:
    "Default"
  else:
    path.extractFilename()

func pointSize(size: SettingsFontSize): float32 =
  case size
  of sfs12: 12.0'f32
  of sfs14: 14.0'f32
  of sfs16: 16.0'f32
  of sfs18: 18.0'f32
  of sfs20: 20.0'f32

proc appearanceFor(
    theme: SettingsTheme, fontPath: string, fontSize: SettingsFontSize
): Appearance =
  case theme
  of stDefault:
    result = initAppearance(initTheme())
  of stMacOS:
    result = initAppearance(initMacOSTheme())
  of stMacOSDark:
    result = initAppearance(initMacOSDarkTheme())
  of stNebula:
    result = initAppearance(initNebulaTheme())
  of stPeachy:
    result = initAppearance(initPeachyTheme())
  of stSynthwave83:
    result = initAppearance(initSynthwave83Theme())

  for role in TextStyleRoles:
    result.theme[role, StyleFontName] = styleKeyword(
      if fontPath.len > 0:
        fontPath
      else:
        defaultFontName()
    )
    result.theme[role, StyleFontSize] = fontSize.pointSize()

proc newSettingsPage(): tuple[view: View, stack: StackView] =
  result.view = newView()
  result.stack = newStackView(laVertical)
  result.stack.spacing = 12.0
  result.stack.alignment = svaFill
  result.view.addSubview(result.stack)
  discard result.stack.pinEdges(
    toGuide = result.view.contentLayoutGuide(insets(18.0, 20.0)),
    edges = {leLeft, leTop, leRight, leBottom},
  )

proc updatePreview(settings: MerendaSettingsWindow) =
  settings.preview.appearance = settings.activeTheme.appearanceFor(
    settings.previewFontPath, settings.previewFontSize
  )
  settings.status.text =
    "Previewing " & settings.previewFontPath.fontTitle() & " · " &
    settings.previewFontSize.title() & " — application: " &
    settings.appliedFontPath.fontTitle() & " · " & settings.appliedFontSize.title() &
    " · " & settings.fontLoadingStatus

proc applyAppearance(settings: MerendaSettingsWindow) =
  if not settings.applyAppearanceHandler.isNil:
    settings.applyAppearanceHandler(
      settings.activeTheme.appearanceFor(
        settings.appliedFontPath, settings.appliedFontSize
      )
    )
  settings.updatePreview()

proc themeDidChange(settings: MerendaSettingsWindow, sender: DynamicAgent) =
  if sender of ComboBox:
    let index = ComboBox(sender).selectedIndex()
    if index >= ord(low(SettingsTheme)) and index <= ord(high(SettingsTheme)):
      settings.activeTheme = SettingsTheme(index)
      settings.applyAppearance()

proc fontSizeDidChange(settings: MerendaSettingsWindow, sender: DynamicAgent) =
  if sender of ComboBox:
    let index = ComboBox(sender).selectedIndex()
    if index >= ord(low(SettingsFontSize)) and index <= ord(high(SettingsFontSize)):
      settings.previewFontSize = SettingsFontSize(index)
      settings.updatePreview()

proc applyFontDidClick(settings: MerendaSettingsWindow, sender: DynamicAgent) =
  if sender of Button:
    settings.appliedFontPath = settings.previewFontPath
    settings.appliedFontSize = settings.previewFontSize
    settings.applyAppearance()

proc stopFontLoading(settings: MerendaSettingsWindow) =
  if settings.fontLoadingStopped or settings.fontLoadingPool.isNil:
    return
  settings.fontLoadingStopped = true
  settings.fontLoadingPool.stop()
  settings.fontLoadingPool.join()

protocol MerendaSettingsWindowDelegate of WindowDelegateProtocol:
  method windowDidClose(settings: MerendaSettingsWindow, window: Window) =
    discard window
    settings.stopFontLoading()

proc newMerendaSettingsWindow*(
    appearanceHandler: AppearanceHandler = nil
): MerendaSettingsWindow =
  result = MerendaSettingsWindow(
    xWindow: newPanel("Merenda Settings", frame = rect(180, 160, 520, 350)),
    xContentView: newView(),
    fontPickerController: newFontPickerController(),
    applyAppearanceHandler: appearanceHandler,
    activeTheme: stDefault,
    previewFontSize: sfs14,
    appliedFontSize: sfs14,
    fontLoadingStatus: "Loading system fonts…",
  )
  initResponder(result)
  discard result.withProtocol(MerendaSettingsWindowDelegate)
  let settings = result

  let
    layout = newStackView(laVertical)
    tabs = newTabView()
    appearancePage = newSettingsPage()
    typographyPage = newSettingsPage()
    appearanceForm = newFormView()
    typographyForm = newFormView()
    titleLabel = newTitleLabel("Merenda Settings")
    themeLabel = newFormLabel("Theme")
    fontLabel = newFormLabel("Font")
    fontSizeLabel = newFormLabel("Size")
    themePicker = newComboBox(
      [
        stDefault.title(),
        stMacOS.title(),
        stMacOSDark.title(),
        stNebula.title(),
        stPeachy.title(),
        stSynthwave83.title(),
      ]
    )
    fontPicker = newCascadingView()
    fontSizePicker = newComboBox(
      [sfs12.title(), sfs14.title(), sfs16.title(), sfs18.title(), sfs20.title()]
    )
    applyFontButton = newButton("Apply font")
    themeChanged = actionSelector("themeChanged")
    fontSizeChanged = actionSelector("fontSizeChanged")
    applyFont = actionSelector("applyFont")

  result.preview = newLabel("The quick brown fox jumps over the lazy dog.")
  result.status = newStatusLabel()
  result.xFirstResponder = themePicker

  for form in [appearanceForm, typographyForm]:
    form.edgeInsets = insets(0.0)
    form.spacing[dcol] = 12.0
    form.spacing[drow] = 10.0
    form.minFieldWidth = 260.0

  themePicker.selectedIndex = result.activeTheme.ord
  themePicker.target = newActionTarget(
    themeChanged,
    proc(sender: DynamicAgent) =
      settings.themeDidChange(sender),
  )
  themePicker.action = themeChanged
  fontPicker.columnWidth = 180.0
  fontPicker.minColumnWidth = 140.0
  fontPicker.accessibilityLabel = "Font"
  result.fontPickerController.fontPicker = fontPicker
  result.fontPickerController.selectionHandler = proc(path: string) =
    settings.previewFontPath = path
    settings.updatePreview()
  result.fontPickerController.progressHandler = proc(message: string) =
    settings.fontLoadingStatus = message
    settings.updatePreview()
  fontPicker.dataSource = result.fontPickerController
  fontPicker.delegate = result.fontPickerController
  fontPicker.selectedPath =
    @[DefaultFontLanguage.fontPickerLanguageIdentifier(), DefaultSystemFontIdentifier]
  fontSizePicker.selectedIndex = result.previewFontSize.ord
  fontSizePicker.target = newActionTarget(
    fontSizeChanged,
    proc(sender: DynamicAgent) =
      settings.fontSizeDidChange(sender),
  )
  fontSizePicker.action = fontSizeChanged
  applyFontButton.target = newActionTarget(
    applyFont,
    proc(sender: DynamicAgent) =
      settings.applyFontDidClick(sender),
  )
  applyFontButton.action = applyFont

  appearanceForm.addRow(themeLabel, themePicker)
  appearancePage.stack.addArrangedSubview(
    newHeadingLabel("Appearance"),
    newLabel("Choose one of Merenda's built-in themes for this application."),
    appearanceForm,
  )
  appearancePage.stack.addFlexibleSpacer()

  typographyForm.addRow(fontLabel, fontPicker)
  typographyForm.addRow(fontSizeLabel, fontSizePicker)
  typographyPage.stack.addArrangedSubview(
    newHeadingLabel("Typography"),
    newLabel("Choose a font family, language, and face, then preview and apply it."),
    typographyForm,
    newHeadingLabel("Preview"),
    result.preview,
    applyFontButton,
  )
  typographyPage.stack.addFlexibleSpacer()

  discard
    tabs.addTabViewItem(newTabViewItem("Appearance", appearancePage.view, "appearance"))
  discard
    tabs.addTabViewItem(newTabViewItem("Typography", typographyPage.view, "typography"))
  tabs.delegate = result.fontPickerController
  tabs.setHuggingPriority(LayoutPriorityLow, laVertical)
  tabs.setCompressionPriority(LayoutPriorityRequired, laVertical)

  layout.spacing = 12.0
  layout.alignment = svaFill
  layout.addArrangedSubview(titleLabel, tabs, result.status)
  result.xContentView.addSubview(layout)
  discard layout.pinEdges(
    toGuide = result.xContentView.contentLayoutGuide(insets(22.0, 24.0)),
    edges = {leLeft, leTop, leRight, leBottom},
  )
  result.xWindow.styleMask = result.xWindow.styleMask + {wsmResizable}
  result.xWindow.automaticallyAdjustsContentMinSize = true
  result.xWindow.delegate = result

  result.applyAppearance()
  result.fontLoadingPool = newSigilThreadPool(workers = 2)
  result.fontLoadingPool.start()
  var fontCatalogLoader = FontCatalogLoader()
  result.fontCatalogLoader = fontCatalogLoader.moveToThread(result.fontLoadingPool)
  connectThreaded(
    result.fontPickerController, fontCatalogLoadRequested, result.fontCatalogLoader,
    loadFontCatalog,
  )
  connectThreaded(
    result.fontCatalogLoader,
    fontCatalogBatchLoaded,
    result.fontPickerController,
    FontPickerController.didLoadFontCatalogBatch(),
  )
  connectThreaded(
    result.fontCatalogLoader,
    fontCatalogLoadingFinished,
    result.fontPickerController,
    FontPickerController.didFinishLoadingFontCatalog(),
  )
  connectThreaded(
    result.fontCatalogLoader,
    fontCatalogLoadingFailed,
    result.fontPickerController,
    FontPickerController.didFailLoadingFontCatalog(),
  )
  emit result.fontPickerController.fontCatalogLoadRequested()

proc window*(settings: MerendaSettingsWindow): Panel =
  ## The panel that presents the settings interface.
  settings.xWindow

proc contentView*(settings: MerendaSettingsWindow): View =
  ## The settings panel's root view.
  settings.xContentView

proc firstResponder*(settings: MerendaSettingsWindow): Responder =
  ## The control that should receive initial keyboard focus.
  settings.xFirstResponder
