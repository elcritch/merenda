import std/[os, strutils]

import sigils/core

import ../containers/stackviews
import ../controls/buttons
import ../foundation/selectors
import ../foundation/types
import ../text/textfields
import ../themes
import ../view/views
import ./windows

export windows

const
  PanelResponseCancel* = 0
  PanelResponseOk* = 1

const
  PanelContentInsets = insets(22.0'f32, 24.0'f32, 22.0'f32, 24.0'f32)
  PanelButtonSpacing = 8.0'f32

proc rebuildAlertView*(alert: Alert): View
proc rebuildOpenPanelView*(panel: OpenPanel): View
proc rebuildSavePanelView*(panel: SavePanel): View
proc updatePrimaryButton(buttons: seq[View], enabled: bool)
proc validateSelection*(panel: OpenPanel): bool
proc validateSelection*(panel: SavePanel): bool

proc refreshOpenPanelValidation(panel: OpenPanel, sender: DynamicAgent) {.slot.} =
  discard sender
  discard panel.validateSelection()

proc refreshSavePanelValidation(panel: SavePanel, sender: DynamicAgent) {.slot.} =
  discard sender
  discard panel.validateSelection()

func normalizedFileType*(fileType: string): string =
  result = fileType.strip().toLowerAscii()
  while result.len > 0 and result[0] == '.':
    result = result[1 .. ^1]

proc filePathFromUrl*(fileUrl: string): string =
  result = fileUrl
  let queryStart = result.find('?')
  if queryStart >= 0:
    result.setLen(queryStart)
  let fragmentStart = result.find('#')
  if fragmentStart >= 0:
    result.setLen(fragmentStart)
  if result.startsWith("file://"):
    result = result[7 .. ^1]

proc fileTypeForUrl*(fileUrl: string): string =
  let ext = splitFile(filePathFromUrl(fileUrl)).ext
  if ext.len > 0 and ext[0] == '.':
    ext[1 .. ^1].normalizedFileType()
  else:
    ext.normalizedFileType()

proc selectedFileType*(panel: SavePanel): string

proc acceptsFileType*(allowedFileTypes: openArray[string], fileType: string): bool =
  if allowedFileTypes.len == 0:
    return true
  let normalized = fileType.normalizedFileType()
  for allowed in allowedFileTypes:
    if allowed.normalizedFileType() == normalized:
      return true

proc acceptsFileUrl*(panel: OpenPanel, fileUrl: string): bool =
  if panel.isNil or fileUrl.len == 0:
    return false
  let looksLikeDirectory = fileUrl.endsWith("/")
  if looksLikeDirectory:
    return panel.canChooseDirectories
  panel.canChooseFiles and
    panel.allowedFileTypes.acceptsFileType(fileUrl.fileTypeForUrl())

proc acceptsFileUrl*(panel: SavePanel, fileUrl: string): bool =
  if panel.isNil or fileUrl.len == 0:
    return false
  panel.allowedFileTypes.acceptsFileType(fileUrl.fileTypeForUrl())

proc modalResponse*(alert: Alert): int =
  if alert.isNil: PanelResponseCancel else: alert.response

proc modalResponse*(panel: OpenPanel): int =
  if panel.isNil: PanelResponseCancel else: panel.response

proc modalResponse*(panel: SavePanel): int =
  if panel.isNil: PanelResponseCancel else: panel.response

proc setAccessoryView*(alert: Alert, view: View) =
  if alert.isNil or alert.accessoryView == view:
    return
  alert.accessoryView = view
  discard alert.rebuildAlertView()

proc setAccessoryView*(panel: OpenPanel, view: View) =
  if panel.isNil or panel.accessoryView == view:
    return
  panel.accessoryView = view
  discard panel.rebuildOpenPanelView()

proc setAccessoryView*(panel: SavePanel, view: View) =
  if panel.isNil or panel.accessoryView == view:
    return
  panel.accessoryView = view
  discard panel.rebuildSavePanelView()

proc addButton*(alert: Alert, title: string, response: int): int {.discardable.} =
  if alert.isNil:
    return -1
  alert.buttons.add title
  alert.buttonResponses.add response
  discard alert.rebuildAlertView()
  alert.buttons.high

proc setButtonResponse*(alert: Alert, index, response: int): bool {.discardable.} =
  if alert.isNil or index < 0 or index >= alert.buttonResponses.len:
    return false
  alert.buttonResponses[index] = response
  discard alert.rebuildAlertView()
  true

proc buttonResponse*(alert: Alert, index: int): int =
  if alert.isNil or index < 0 or index >= alert.buttonResponses.len:
    PanelResponseCancel
  else:
    alert.buttonResponses[index]

proc dismiss*(alert: Alert, response: int) =
  if alert.isNil:
    return
  alert.response = response
  if not alert.responseHandler.isNil:
    alert.responseHandler(response)

proc dismiss*(panel: OpenPanel, response: int) =
  if panel.isNil:
    return
  panel.response = response
  if not panel.responseHandler.isNil:
    panel.responseHandler(response)

proc dismiss*(panel: SavePanel, response: int) =
  if panel.isNil:
    return
  panel.response = response
  if not panel.responseHandler.isNil:
    panel.responseHandler(response)

proc syncOpenPanelFromField(panel: OpenPanel) =
  if panel.isNil or panel.urlField.isNil or not (panel.urlField of TextField):
    return
  panel.selectedUrls.setLen(0)
  for line in TextField(panel.urlField).text.splitLines():
    let value = line.strip()
    if value.len > 0:
      panel.selectedUrls.add value

proc syncSavePanelFromField(panel: SavePanel) =
  if panel.isNil or panel.nameField.isNil or not (panel.nameField of TextField):
    return
  panel.nameFieldStringValue = TextField(panel.nameField).text.strip()

proc selectedUrl*(panel: OpenPanel): string =
  if panel.isNil or panel.selectedUrls.len == 0:
    ""
  else:
    panel.selectedUrls[0]

proc selectedUrls*(panel: OpenPanel): seq[string] =
  if panel.isNil:
    @[]
  else:
    panel.selectedUrls

proc setSelectedUrls*(panel: OpenPanel, urls: openArray[string]) =
  if panel.isNil:
    return
  panel.selectedUrls = @urls
  if not panel.urlField.isNil and panel.urlField of TextField:
    TextField(panel.urlField).text = panel.selectedUrls.join("\n")

proc selectUrls*(panel: OpenPanel, urls: openArray[string]) =
  panel.setSelectedUrls(urls)

proc `selectedUrls=`*(panel: OpenPanel, urls: openArray[string]) =
  panel.setSelectedUrls(urls)

proc selectUrl*(panel: OpenPanel, url: string) =
  if panel.isNil:
    return
  if url.len == 0:
    panel.setSelectedUrls([])
  else:
    panel.setSelectedUrls([url])

proc validateSelection*(panel: OpenPanel): bool =
  if panel.isNil:
    return false
  panel.syncOpenPanelFromField()
  result =
    panel.selectedUrls.len > 0 and
    (panel.allowsMultipleSelection or panel.selectedUrls.len == 1)
  if result:
    for url in panel.selectedUrls:
      if not panel.acceptsFileUrl(url):
        result = false
        break
  panel.buttonViews.updatePrimaryButton(result)

proc urlFromDirectory(directoryUrl, name: string): string =
  if name.len == 0:
    return ""
  if name.contains("://") or name.startsWith("/") or directoryUrl.len == 0:
    return name
  if directoryUrl.endsWith("/") or directoryUrl.endsWith("\\"):
    directoryUrl & name
  else:
    directoryUrl & "/" & name

proc selectedFileType*(panel: SavePanel): string =
  if panel.isNil:
    return ""
  let explicitType = panel.nameFieldStringValue.fileTypeForUrl()
  if explicitType.len > 0:
    return explicitType
  if panel.allowedFileTypes.len > 0:
    return panel.allowedFileTypes[0].normalizedFileType()
  ""

proc selectedUrl*(panel: SavePanel): string =
  if panel.isNil:
    return ""
  panel.syncSavePanelFromField()
  var name = panel.nameFieldStringValue
  if name.len == 0:
    return ""
  let fileType = panel.selectedFileType()
  if fileType.len > 0 and name.fileTypeForUrl().len == 0:
    name.add "." & fileType
  panel.directoryUrl.urlFromDirectory(name)

proc validateSelection*(panel: SavePanel): bool =
  if panel.isNil:
    return false
  let url = panel.selectedUrl()
  result = url.len > 0 and panel.acceptsFileUrl(url)
  panel.buttonViews.updatePrimaryButton(result)

proc updatePrimaryButton(buttons: seq[View], enabled: bool) =
  if buttons.len > 0 and buttons[0] of Button:
    Button(buttons[0]).enabled = enabled

proc newResponseButton(
    title: string, response: int, callback: proc(response: int) {.closure.}
): Button =
  result = newButton(title)
  let action = actionSelector("panelResponse")
  result.action = action
  result.target = newActionTarget(action) do(sender: DynamicAgent):
    discard sender
    callback(response)

proc attachButtonRow(
    layout: StackView,
    titles: openArray[string],
    responses: openArray[int],
    callback: proc(response: int) {.closure.},
): seq[View] =
  let row = newStackView(laHorizontal)
  row.spacing = PanelButtonSpacing
  row.alignment = svaFill
  row.distribution = svdFillEqually
  for index, title in titles:
    let response =
      if index < responses.len:
        responses[index]
      else:
        index + 1
    let button = newResponseButton(title, response, callback)
    row.addArrangedSubview(View(button))
    result.add View(button)
  layout.addArrangedSubview(View(row))

proc prepareRoot(window: Window): tuple[root: View, layout: StackView] =
  let frame =
    if window.isNil:
      initRect(0.0, 0.0, 360.0, 180.0)
    else:
      initRect(0.0, 0.0, window.frame().size.width, window.frame().size.height)
  result.root = newView(frame = frame)
  result.layout = newStackView(laVertical)
  result.layout.spacing = 12.0
  result.layout.alignment = svaFill
  result.root.addSubview(result.layout)
  discard
    result.layout.pinEdges(toGuide = result.root.contentLayoutGuide(PanelContentInsets))

proc setPanelContent(window: Window, content: View) =
  if not window.isNil:
    window.setContentView(content)

proc rebuildAlertView*(alert: Alert): View =
  if alert.isNil:
    return nil
  let prepared = prepareRoot(alert.window)
  let layout = prepared.layout
  layout.addArrangedSubview(View(newTitleLabel(alert.messageText)))
  if alert.informativeText.len > 0:
    layout.addArrangedSubview(View(newStatusLabel(alert.informativeText)))
  if not alert.accessoryView.isNil:
    layout.addArrangedSubview(alert.accessoryView)
  alert.buttonViews = layout.attachButtonRow(alert.buttons, alert.buttonResponses) do(
    response: int
  ):
    alert.dismiss(response)
  alert.contentView = prepared.root
  alert.window.setPanelContent(alert.contentView)
  result = alert.contentView

proc rebuildOpenPanelView*(panel: OpenPanel): View =
  if panel.isNil:
    return nil
  let prepared = prepareRoot(panel.window)
  let layout = prepared.layout
  layout.addArrangedSubview(View(newTitleLabel(panel.window.title())))
  if panel.message.len > 0:
    layout.addArrangedSubview(View(newStatusLabel(panel.message)))
  panel.urlField = View(newTextField(panel.selectedUrls.join("\n")))
  TextField(panel.urlField).connect(textDidChange, panel, refreshOpenPanelValidation)
  layout.addArrangedSubview(panel.urlField)
  if panel.allowedFileTypes.len > 0:
    layout.addArrangedSubview(
      View(newStatusLabel("Allowed types: " & panel.allowedFileTypes.join(", ")))
    )
  if not panel.accessoryView.isNil:
    layout.addArrangedSubview(panel.accessoryView)
  panel.buttonViews = layout.attachButtonRow(
    [panel.prompt, "Cancel"], [PanelResponseOk, PanelResponseCancel]
  ) do(response: int):
    if response == PanelResponseOk and not panel.validateSelection():
      panel.buttonViews.updatePrimaryButton(false)
      return
    panel.dismiss(response)
  panel.buttonViews.updatePrimaryButton(panel.validateSelection())
  panel.contentView = prepared.root
  panel.window.setPanelContent(panel.contentView)
  result = panel.contentView

proc rebuildSavePanelView*(panel: SavePanel): View =
  if panel.isNil:
    return nil
  let prepared = prepareRoot(panel.window)
  let layout = prepared.layout
  layout.addArrangedSubview(View(newTitleLabel(panel.window.title())))
  if panel.message.len > 0:
    layout.addArrangedSubview(View(newStatusLabel(panel.message)))
  panel.nameField = View(newTextField(panel.nameFieldStringValue))
  TextField(panel.nameField).connect(textDidChange, panel, refreshSavePanelValidation)
  layout.addArrangedSubview(panel.nameField)
  if panel.allowedFileTypes.len > 0:
    layout.addArrangedSubview(
      View(newStatusLabel("Allowed types: " & panel.allowedFileTypes.join(", ")))
    )
  if not panel.accessoryView.isNil:
    layout.addArrangedSubview(panel.accessoryView)
  panel.buttonViews = layout.attachButtonRow(
    [panel.prompt, "Cancel"], [PanelResponseOk, PanelResponseCancel]
  ) do(response: int):
    if response == PanelResponseOk and not panel.validateSelection():
      panel.buttonViews.updatePrimaryButton(false)
      return
    panel.dismiss(response)
  panel.buttonViews.updatePrimaryButton(panel.validateSelection())
  panel.contentView = prepared.root
  panel.window.setPanelContent(panel.contentView)
  result = panel.contentView

proc contentView*(alert: Alert): View =
  if alert.isNil:
    nil
  elif alert.contentView.isNil:
    alert.rebuildAlertView()
  else:
    alert.contentView

proc contentView*(panel: OpenPanel): View =
  if panel.isNil:
    nil
  elif panel.contentView.isNil:
    panel.rebuildOpenPanelView()
  else:
    panel.contentView

proc contentView*(panel: SavePanel): View =
  if panel.isNil:
    nil
  elif panel.contentView.isNil:
    panel.rebuildSavePanelView()
  else:
    panel.contentView

proc prepareForModal*(alert: Alert, responseHandler: proc(response: int) {.closure.}) =
  if alert.isNil:
    return
  alert.responseHandler = responseHandler
  discard alert.contentView()

proc prepareForModal*(
    panel: OpenPanel, responseHandler: proc(response: int) {.closure.}
) =
  if panel.isNil:
    return
  panel.responseHandler = responseHandler
  discard panel.contentView()
  discard panel.validateSelection()

proc prepareForModal*(
    panel: SavePanel, responseHandler: proc(response: int) {.closure.}
) =
  if panel.isNil:
    return
  panel.responseHandler = responseHandler
  discard panel.contentView()
  discard panel.validateSelection()
