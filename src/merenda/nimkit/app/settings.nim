## Built-in Merenda settings panel.

import std/[algorithm, os, strutils, tables]

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
import ../controls/steppers
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
    stDarkBSD
    stAqua
    stMacOS
    stMacOSDark
    stNebula
    stPeachy
    stSynthwave83

  AppearanceHandler* = proc(appearance: Appearance) {.closure.}

  SelectedFont = object
    name: string
    face: SystemTypeface

  FontSelectionProc = proc(font: SelectedFont) {.closure.}
  FontLoadingProgressProc = proc(message: string) {.closure.}

  FontPickerFilter = enum
    fpfProportional
    fpfAll
    fpfMonospace

  FontCatalogLoader = ref object of AgentActor
    entries: seq[FontCatalogEntry]
    nextEntryIndex: int
    loadedEntryCount: int
    loadedFaceCount: int
    started: bool
    finished: bool

  FontPickerController = ref object of Responder
    catalogEntries: seq[FontCatalogEntry]
    items: Table[string, CascadingItem]
    faces: Table[string, FontCatalogFace]
    childIdentifiers: Table[string, seq[string]]
    childIndexes: Table[string, Table[string, int]]
    fontPicker: CascadingView
    needsFontPickerReload: bool
    pendingFontPickerBatchCount: int
    desiredSelectedFont: SelectedFont
    fontFilter: FontPickerFilter
    onlyDisplayableFonts: bool
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
    activeFontRole: FontRole
    previewFonts: array[FontRole, SelectedFont]
    previewFontSize: float32
    appliedFonts: array[FontRole, SelectedFont]
    appliedFontSize: float32
    fontLoadingStatus: string
    preview: Label
    status: Label
    fontSizeValue: Label
    fontSizeStepper: Stepper
    fontRoleButtons: array[FontRole, Button]
    onlyMonospaceFontsCheckbox: Button
    onlyDisplayableFontsCheckbox: Button

const
  FontCatalogBatchSize = 1
  FontCatalogBatchesPerReload = 1
  SettingsMinimumFontSize = 6.0'f32
  SettingsMaximumFontSize = 120.0'f32
  SettingsDefaultFontSize = 14.0'f32
  SettingsThemePickerIdentifier = "settings-theme-picker"
  SettingsUIFontButtonIdentifier = "settings-ui-font-button"
  SettingsMonospaceFontButtonIdentifier = "settings-monospace-font-button"
  SettingsFontPickerIdentifier = "settings-font-picker"
  SettingsFontPreviewIdentifier = "settings-font-preview"
  SettingsOnlyMonospaceFontsIdentifier = "settings-only-monospace-fonts"
  SettingsOnlyDisplayableFontsIdentifier = "settings-only-displayable-fonts"

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

func defaultFontPickerPath(): seq[string] =
  @[DefaultFontLanguage.fontPickerLanguageIdentifier(), DefaultSystemFontIdentifier]

proc selectionPathForFont(
    controller: FontPickerController, selectedFont: SelectedFont
): seq[string] =
  if selectedFont.name.len == 0:
    return defaultFontPickerPath()
  for identifier, face in controller.faces:
    let matches =
      if selectedFont.face.file.path.len > 0:
        face.typeface == selectedFont.face
      else:
        face.fontName == selectedFont.name
    if not matches:
      continue
    let
      faceItem = controller.items.getOrDefault(identifier)
      familyIdentifier = faceItem.parentIdentifier
      familyItem = controller.items.getOrDefault(familyIdentifier)
      languageIdentifier = familyItem.parentIdentifier
    if familyIdentifier.len > 0 and languageIdentifier.len > 0:
      return @[languageIdentifier, familyIdentifier, identifier]

proc restoreFontPickerSelection(controller: FontPickerController) =
  if controller.fontPicker.isNil:
    return
  let path = controller.selectionPathForFont(controller.desiredSelectedFont)
  if path.len > 0:
    if controller.fontPicker.selectedPath != path:
      controller.fontPicker.selectedPath = path
  elif controller.desiredSelectedFont.name.len > 0 and
      controller.fontPicker.selectedPath.len > 0:
    controller.fontPicker.selectedPath = @[]

proc selectFont(controller: FontPickerController, font: SelectedFont) =
  controller.desiredSelectedFont = font
  controller.restoreFontPickerSelection()

proc addFontPickerLanguage(controller: FontPickerController, language: string): string =
  result = language.fontPickerLanguageIdentifier()
  if result notin controller.items:
    controller.addFontPickerItem(cascadeItem(result, language))
    controller.sortFontPickerLanguages()

proc addDefaultFontPickerItem(controller: FontPickerController) =
  let defaultLanguageIdentifier = controller.addFontPickerLanguage(DefaultFontLanguage)
  controller.addFontPickerItem(
    cascadeItem(
      DefaultSystemFontIdentifier,
      "System Default",
      parentIdentifier = defaultLanguageIdentifier,
      leaf = true,
      objectValue = toObj(""),
    )
  )

func isMonospaceCandidate(entry: FontCatalogEntry, face: FontCatalogFace): bool =
  face.monospace or entry.family.toLowerAscii().contains("mono") or
    face.fontName.toLowerAscii().contains("mono")

proc addFontCatalogEntry(controller: FontPickerController, entry: FontCatalogEntry) =
  for face in entry.faces:
    let isMonospace = entry.isMonospaceCandidate(face)
    let matchesFontKind =
      controller.fontFilter == fpfAll or
      isMonospace == (controller.fontFilter == fpfMonospace)
    if matchesFontKind and
        (not controller.onlyDisplayableFonts or face.supportsPreviewText):
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
            objectValue = toObj(face.fontName),
          )
        )
        controller.faces[faceIdentifier] = face

proc checkFontCatalogEntryDisplayability(entry: var FontCatalogEntry) =
  for face in entry.faces.mitems:
    face.checkFontCatalogFaceDisplayability()

proc rebuildFontPickerItems(controller: FontPickerController) =
  controller.items.clear()
  controller.faces.clear()
  controller.childIdentifiers.clear()
  controller.childIndexes.clear()
  controller.addDefaultFontPickerItem()
  for entry in controller.catalogEntries.mitems:
    if controller.onlyDisplayableFonts:
      entry.checkFontCatalogEntryDisplayability()
    controller.addFontCatalogEntry(entry)

proc setFontFilter(controller: FontPickerController, value: FontPickerFilter) =
  if controller.fontFilter == value:
    return
  controller.fontFilter = value
  controller.rebuildFontPickerItems()
  if not controller.fontPicker.isNil:
    controller.fontPicker.reloadData()
    controller.restoreFontPickerSelection()
  controller.needsFontPickerReload = false
  controller.pendingFontPickerBatchCount = 0

proc setOnlyDisplayableFonts(controller: FontPickerController, value: bool) =
  if controller.onlyDisplayableFonts == value:
    return
  controller.onlyDisplayableFonts = value
  controller.rebuildFontPickerItems()
  if not controller.fontPicker.isNil:
    controller.fontPicker.reloadData()
    controller.restoreFontPickerSelection()
  controller.needsFontPickerReload = false
  controller.pendingFontPickerBatchCount = 0

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
  let horizontalOffset = controller.fontPicker.scrollView().contentOffset()
  var columnOffsets = newSeqOfCap[Point](controller.fontPicker.columnCount())
  for column in 0 ..< controller.fontPicker.columnCount():
    columnOffsets.add(
      controller.fontPicker.tableViewForColumn(column).scrollView().contentOffset()
    )
  controller.fontPicker.reloadData()
  controller.fontPicker.scrollView().contentOffset = horizontalOffset
  for column, offset in columnOffsets:
    let tableView = controller.fontPicker.tableViewForColumn(column)
    if not tableView.isNil:
      tableView.scrollView().contentOffset = offset
  controller.needsFontPickerReload = false
  controller.pendingFontPickerBatchCount = 0

when defined(merendaTests):
  proc rebuildFontPickerItemsForTests*(controller: FontPickerController) =
    controller.rebuildFontPickerItems()

  proc reloadFontPickerIfVisibleForTests*(controller: FontPickerController) =
    controller.reloadFontPickerIfVisible()

proc loadFontCatalog(loader: FontCatalogLoader) {.slot.} =
  if loader.finished:
    return
  try:
    if not loader.started:
      loader.entries = systemFontCatalog()
      loader.started = true

    var batch = newSeqOfCap[FontCatalogEntry](FontCatalogBatchSize)
    let batchEnd = min(loader.nextEntryIndex + FontCatalogBatchSize, loader.entries.len)
    while loader.nextEntryIndex < batchEnd:
      var loadedEntry = move loader.entries[loader.nextEntryIndex]
      inc loader.nextEntryIndex
      if loadedEntry.family == "Last Resort":
        continue
      for face in loadedEntry.faces.mitems:
        face.loadFontCatalogFaceMetadata()
        inc loader.loadedFaceCount
      if loadedEntry.faces.len > 0:
        batch.add move loadedEntry
        inc loader.loadedEntryCount

    if batch.len > 0 or loader.nextEntryIndex < loader.entries.len:
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
    controller.catalogEntries.add entry
    if controller.onlyDisplayableFonts:
      controller.catalogEntries[^1].checkFontCatalogEntryDisplayability()
    controller.addFontCatalogEntry(controller.catalogEntries[^1])
  if entries.len > 0:
    controller.restoreFontPickerSelection()
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
    var selectedFont: SelectedFont
    if identifier in controller.faces:
      let face = controller.faces[identifier]
      selectedFont = SelectedFont(name: face.fontName, face: face.typeface)
    controller.desiredSelectedFont = selectedFont
    controller.selectionHandler(selectedFont)

proc newFontPickerController(): FontPickerController =
  result = FontPickerController(
    items: initTable[string, CascadingItem](),
    faces: initTable[string, FontCatalogFace](),
    childIdentifiers: initTable[string, seq[string]](),
    childIndexes: initTable[string, Table[string, int]](),
  )
  result.addDefaultFontPickerItem()
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
  of stDarkBSD: "DarkBSD"
  of stAqua: "Aqua"
  of stMacOS: "macOS"
  of stMacOSDark: "macOS Dark"
  of stNebula: "Nebula"
  of stPeachy: "Peachy"
  of stSynthwave83: "Synthwave '83"

proc fontTitle(name: string): string =
  if name.len == 0:
    "Default"
  else:
    name.extractFilename()

func fontSizeTitle(size: float32): string =
  $size.int & " pt"

func title(role: FontRole): string =
  case role
  of frUI: "Interface"
  of frMonospace: "Monospace"

proc appearanceFor(
    theme: SettingsTheme,
    fonts: array[FontRole, SelectedFont],
    fontSize: float32,
    previewRole = frUI,
): Appearance =
  case theme
  of stDarkBSD:
    result = initAppearance(initDarkBSDTheme())
  of stAqua:
    result = initAppearance(initAquaTheme())
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

  var
    builder = initThemeBuilder(result.theme)
    selectedFonts: array[FontRole, SelectedFont]
  for role in FontRole:
    var selectedFont = fonts[role]
    if selectedFont.name.len == 0:
      selectedFont.name = defaultFontName(role)
    selectedFonts[role] = selectedFont
    builder.setFontName(role, selectedFont.name)
    builder.setFontFace(role, selectedFont.face)
  for role in TextStyleRoles:
    builder[role, StyleFontSize] = fontSize
  let preview = initStyleSelector(srTextField, id = SettingsFontPreviewIdentifier)
  builder[preview, StyleFontName] = styleKeyword(selectedFonts[previewRole].name)
  builder[preview, StyleFontFace] = styleFontFace(selectedFonts[previewRole].face)
  builder[preview, StyleFontSize] = fontSize
  result.theme = builder.finish()

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

proc updateStatus(settings: MerendaSettingsWindow) =
  settings.status.text =
    "Previewing " & settings.activeFontRole.title() & ": " &
    settings.previewFonts[settings.activeFontRole].name.fontTitle() & " · " &
    settings.previewFontSize.fontSizeTitle() & " — UI: " &
    settings.appliedFonts[frUI].name.fontTitle() & " · mono: " &
    settings.appliedFonts[frMonospace].name.fontTitle() & " · " &
    settings.fontLoadingStatus

proc updateFontRoleButtons(settings: MerendaSettingsWindow) =
  for role in FontRole:
    let button = settings.fontRoleButtons[role]
    if button.isNil:
      continue
    button.title = settings.previewFonts[role].name.fontTitle()
    button.state = if role == settings.activeFontRole: bsOn else: bsOff

proc updatePreview(settings: MerendaSettingsWindow) =
  if not settings.fontSizeValue.isNil:
    settings.fontSizeValue.text = settings.previewFontSize.fontSizeTitle()
  settings.updateFontRoleButtons()
  settings.preview.appearance = settings.activeTheme.appearanceFor(
    settings.previewFonts, settings.previewFontSize, settings.activeFontRole
  )
  settings.updateStatus()

proc applyAppearance(settings: MerendaSettingsWindow) =
  if not settings.applyAppearanceHandler.isNil:
    settings.applyAppearanceHandler(
      settings.activeTheme.appearanceFor(
        settings.appliedFonts, settings.appliedFontSize
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
  if sender of Stepper:
    settings.previewFontSize = Stepper(sender).value
    settings.updatePreview()

proc selectFontRole(settings: MerendaSettingsWindow, role: FontRole) =
  settings.activeFontRole = role
  let onlyMonospaceFonts = role == frMonospace
  if not settings.onlyMonospaceFontsCheckbox.isNil:
    let title =
      if onlyMonospaceFonts: "Only monospace fonts" else: "Show monospace fonts"
    settings.onlyMonospaceFontsCheckbox.title = title
    settings.onlyMonospaceFontsCheckbox.accessibilityLabel = title
    settings.onlyMonospaceFontsCheckbox.state = if onlyMonospaceFonts: bsOn else: bsOff
  settings.fontPickerController.setFontFilter(
    if onlyMonospaceFonts: fpfMonospace else: fpfProportional
  )
  settings.fontPickerController.selectFont(settings.previewFonts[role])
  settings.updatePreview()

proc fontRoleDidClick(
    settings: MerendaSettingsWindow, role: FontRole, sender: DynamicAgent
) =
  if sender of Button:
    settings.selectFontRole(role)

proc onlyMonospaceFontsDidChange(
    settings: MerendaSettingsWindow, sender: DynamicAgent
) =
  if sender of Button:
    let enabled = Button(sender).state == bsOn
    settings.fontPickerController.setFontFilter(
      if settings.activeFontRole == frMonospace:
        (if enabled: fpfMonospace else: fpfAll)
      else:
        (if enabled: fpfAll else: fpfProportional)
    )

proc onlyDisplayableFontsDidChange(
    settings: MerendaSettingsWindow, sender: DynamicAgent
) =
  if sender of Button:
    settings.fontPickerController.setOnlyDisplayableFonts(Button(sender).state == bsOn)

proc applyFontDidClick(settings: MerendaSettingsWindow, sender: DynamicAgent) =
  if sender of Button:
    settings.appliedFonts = settings.previewFonts
    settings.appliedFontSize = settings.previewFontSize
    settings.applyAppearance()

proc resetSelections*(settings: MerendaSettingsWindow) =
  ## Restores the controls to the currently applied appearance when the panel opens.
  settings.previewFonts = settings.appliedFonts
  settings.previewFontSize = settings.appliedFontSize
  if not settings.fontSizeStepper.isNil:
    settings.fontSizeStepper.value = settings.previewFontSize
  settings.fontPickerController.selectFont(
    settings.previewFonts[settings.activeFontRole]
  )
  settings.updatePreview()

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
    xWindow: newPanel("Merenda Settings", frame = rect(180, 160, 520, 390)),
    xContentView: newView(),
    fontPickerController: newFontPickerController(),
    applyAppearanceHandler: appearanceHandler,
    activeTheme: stDarkBSD,
    activeFontRole: frUI,
    previewFontSize: SettingsDefaultFontSize,
    appliedFontSize: SettingsDefaultFontSize,
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
    interfaceFontLabel = newFormLabel("Interface Font")
    monospaceFontLabel = newFormLabel("Monospace Font")
    fontLabel = newFormLabel("Browse Fonts")
    fontFilterLabel = newFormLabel("Filter")
    fontSizeLabel = newFormLabel("Size")
    themePicker = newComboBox(
      [
        stDarkBSD.title(),
        stAqua.title(),
        stMacOS.title(),
        stMacOSDark.title(),
        stNebula.title(),
        stPeachy.title(),
        stSynthwave83.title(),
      ]
    )
    interfaceFontButton = newRadioButton("Default")
    monospaceFontButton = newRadioButton("Default")
    fontPicker = newCascadingView()
    onlyMonospaceFontsCheckbox = newCheckBox("Show monospace fonts")
    onlyDisplayableFontsCheckbox = newCheckBox("Only displayable fonts")
    fontFilterControl = newStackView(laVertical)
    fontSizeControl = newStackView(laHorizontal)
    fontSizeValue = newLabel(SettingsDefaultFontSize.fontSizeTitle())
    fontSizeStepper = newStepper(
      SettingsMinimumFontSize,
      SettingsMaximumFontSize,
      result.previewFontSize,
      increment = 1.0,
    )
    applyFontButton = newButton("Apply font")
    themeChanged = actionSelector("themeChanged")
    interfaceFontSelected = actionSelector("interfaceFontSelected")
    monospaceFontSelected = actionSelector("monospaceFontSelected")
    onlyMonospaceFontsChanged = actionSelector("onlyMonospaceFontsChanged")
    onlyDisplayableFontsChanged = actionSelector("onlyDisplayableFontsChanged")
    fontSizeChanged = actionSelector("fontSizeChanged")
    applyFont = actionSelector("applyFont")

  result.preview = newLabel(FontCatalogPreviewText)
  result.status = newStatusLabel()
  result.fontSizeValue = fontSizeValue
  result.fontSizeStepper = fontSizeStepper
  result.fontRoleButtons[frUI] = interfaceFontButton
  result.fontRoleButtons[frMonospace] = monospaceFontButton
  result.onlyMonospaceFontsCheckbox = onlyMonospaceFontsCheckbox
  result.onlyDisplayableFontsCheckbox = onlyDisplayableFontsCheckbox
  result.xFirstResponder = themePicker
  tabs.identifier = "settings-tabs"

  for form in [appearanceForm, typographyForm]:
    form.edgeInsets = insets(0.0)
    form.spacing[dcol] = 12.0
    form.spacing[drow] = 10.0
    form.minFieldWidth = 260.0

  themePicker.selectedIndex = result.activeTheme.ord
  themePicker.identifier = SettingsThemePickerIdentifier
  themePicker.target = newActionTarget(
    themeChanged,
    proc(sender: DynamicAgent) =
      settings.themeDidChange(sender),
  )
  themePicker.action = themeChanged
  interfaceFontButton.identifier = SettingsUIFontButtonIdentifier
  interfaceFontButton.accessibilityLabel = "Interface font"
  interfaceFontButton.target = newActionTarget(
    interfaceFontSelected,
    proc(sender: DynamicAgent) =
      settings.fontRoleDidClick(frUI, sender),
  )
  interfaceFontButton.action = interfaceFontSelected
  monospaceFontButton.identifier = SettingsMonospaceFontButtonIdentifier
  monospaceFontButton.accessibilityLabel = "Monospace font"
  monospaceFontButton.target = newActionTarget(
    monospaceFontSelected,
    proc(sender: DynamicAgent) =
      settings.fontRoleDidClick(frMonospace, sender),
  )
  monospaceFontButton.action = monospaceFontSelected
  fontPicker.columnWidth = 180.0
  fontPicker.minColumnWidth = 140.0
  fontPicker.fitsColumnsToWidth = true
  fontPicker.accessibilityLabel = "Font"
  fontPicker.identifier = SettingsFontPickerIdentifier
  result.fontPickerController.fontPicker = fontPicker
  result.fontPickerController.selectionHandler = proc(font: SelectedFont) =
    settings.previewFonts[settings.activeFontRole] = font
    settings.updatePreview()
  result.fontPickerController.progressHandler = proc(message: string) =
    settings.fontLoadingStatus = message
    settings.updateStatus()
  fontPicker.dataSource = result.fontPickerController
  fontPicker.delegate = result.fontPickerController
  fontPicker.selectedPath = defaultFontPickerPath()
  onlyMonospaceFontsCheckbox.identifier = SettingsOnlyMonospaceFontsIdentifier
  onlyMonospaceFontsCheckbox.accessibilityLabel = "Show monospace fonts"
  onlyMonospaceFontsCheckbox.target = newActionTarget(
    onlyMonospaceFontsChanged,
    proc(sender: DynamicAgent) =
      settings.onlyMonospaceFontsDidChange(sender),
  )
  onlyMonospaceFontsCheckbox.action = onlyMonospaceFontsChanged
  onlyDisplayableFontsCheckbox.identifier = SettingsOnlyDisplayableFontsIdentifier
  onlyDisplayableFontsCheckbox.accessibilityLabel = "Only displayable fonts"
  onlyDisplayableFontsCheckbox.target = newActionTarget(
    onlyDisplayableFontsChanged,
    proc(sender: DynamicAgent) =
      settings.onlyDisplayableFontsDidChange(sender),
  )
  onlyDisplayableFontsCheckbox.action = onlyDisplayableFontsChanged
  fontFilterControl.spacing = 6.0
  fontFilterControl.addArrangedSubview(
    onlyMonospaceFontsCheckbox, onlyDisplayableFontsCheckbox
  )
  fontSizeControl.spacing = 8.0
  fontSizeControl.alignment = svaCenter
  fontSizeValue.setHuggingPriority(LayoutPriorityHigh, laHorizontal)
  fontSizeStepper.accessibilityLabel = "Font size"
  fontSizeStepper.valueFormatter = proc(value: float32): string =
    value.fontSizeTitle()
  fontSizeStepper.target = newActionTarget(
    fontSizeChanged,
    proc(sender: DynamicAgent) =
      settings.fontSizeDidChange(sender),
  )
  fontSizeStepper.action = fontSizeChanged
  fontSizeControl.addArrangedSubview(fontSizeValue, fontSizeStepper)
  fontSizeStepper.identifier = "settings-font-size-stepper"
  fontSizeControl.addFlexibleSpacer()
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

  typographyForm.addRow(interfaceFontLabel, interfaceFontButton)
  typographyForm.addRow(monospaceFontLabel, monospaceFontButton)
  typographyForm.addRow(fontLabel, fontPicker)
  typographyForm.addRow(fontFilterLabel, fontFilterControl)
  typographyForm.addRow(fontSizeLabel, fontSizeControl)
  typographyPage.stack.addArrangedSubview(
    newHeadingLabel("Typography"),
    newLabel("Choose which font to edit, select a face from Browse Fonts, then apply."),
    typographyForm,
    newHeadingLabel("Preview"),
    result.preview,
    applyFontButton,
  )
  result.preview.identifier = SettingsFontPreviewIdentifier
  result.preview.styleId = SettingsFontPreviewIdentifier
  applyFontButton.identifier = "settings-apply-font"
  typographyPage.stack.addFlexibleSpacer()

  discard
    tabs.addTabViewItem(newTabViewItem("Appearance", appearancePage.view, "appearance"))
  discard
    tabs.addTabViewItem(newTabViewItem("Typography", typographyPage.view, "typography"))
  tabs.delegate = result.fontPickerController

  layout.spacing = 12.0
  layout.alignment = svaFill
  layout.addArrangedSubview(titleLabel)
  layout.fillAvailableSpace(tabs)
  layout.addArrangedSubview(result.status)
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
