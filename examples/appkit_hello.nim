import std/[os, strutils]

import nutella/appkit
import nutella/objc

proc maxFramesFromEnv(defaultValue = -1): int =
  let raw = getEnv("NUTELLA_EXAMPLE_FRAMES").strip()
  if raw.len == 0:
    return defaultValue
  try:
    parseInt(raw)
  except ValueError:
    defaultValue

proc debugRenderDumpEnabled(): bool =
  getEnv("NUTELLA_APPKIT_DEBUG_RENDER").strip().toLowerAscii() in
    ["1", "true", "yes", "on"]

const
  titleTag = 1001
  badgeTag = 1002
  statusTag = 1003
  searchTag = 1004
  secureTag = 1005
  clipTag = 1006
  collectionTag = 1007
  modernStatusTag = 1008
  leftInset = 28.0'f32
  titleTop = 28.0'f32
  titleHeight = 48.0'f32
  rowGap = 10.0'f32

proc stateName(state: int): string =
  case state
  of NSOnState: "On"
  of NSMixedState: "Mixed"
  else: "Off"

when isMainModule:
  var app = NSApp()
  var window = newWindow(120, 120, 720, 560, "Nutella AppKit Hello")
  var panel = NSPanel.new()
  window.setFrameOrigin(nsPoint(120, 120))
  window.setContentSize(nsSize(720, 560))
  panel.setTitle(@ns"Inspector Panel")
  panel.setFrameOrigin(860.cfloat, 170.cfloat)
  panel.setContentSize(nsSize(280, 180))
  panel.setFloatingPanel(true)
  panel.setWorksWhenModal(true)

  var root = newView(0, 0, 720, 560)
  root.setTag(1)
  root.setBackgroundColor(0.95, 0.96, 0.98, 1.0)

  var title =
    newTextField(leftInset, titleTop, 520, titleHeight, "Hello from Nutella/AppKit")
  title.setTag(titleTag)
  title.setAlignment(NSCenterTextAlignment)
  title.setTextColor(nsColor(0.13, 0.20, 0.34, 1.0))
  title.setDrawsBackground(false)
  root.addSubview(title)

  let subtitleTop = titleTop + titleHeight + rowGap
  var subtitle = newTextField(
    leftInset, subtitleTop, 620, 36,
    "Ported APIs: NSClipView/NSCollectionView/NSButtonCell/NSAlert plus state/contentSize",
  )
  subtitle.setAlignment(NSLeftTextAlignment)
  subtitle.setTextColor(nsColor(0.20, 0.24, 0.31, 1.0))
  subtitle.setBackgroundColor(nsColor(0.98, 0.98, 0.99, 1.0))
  subtitle.setDrawsBackground(true)
  root.addSubview(subtitle)

  var badge = newTextField(560, titleTop + 2, 132, 28, "Temporary Tag")
  badge.setTag(badgeTag)
  badge.setAlignment(NSCenterTextAlignment)
  badge.setBackgroundColor(nsColor(0.91, 0.95, 1.0, 1.0))
  root.addSubview(badge)

  var taggedBadge = root.viewWithTag(badgeTag)
  if not taggedBadge.isNil:
    taggedBadge.removeFromSuperview()
  taggedBadge.value = nil
  badge.value = nil

  let statusTop = subtitleTop + 36 + rowGap
  var status = newTextField(
    leftInset, statusTop, 420, 30, "Button state cycle: Off -> On -> Mixed"
  )
  status.setTag(statusTag)
  status.setDrawsBackground(false)
  status.setTextColor(nsColor(0.12, 0.28, 0.20, 1.0))
  root.addSubview(status)

  var button = newButton(leftInset, statusTop + 40, 220, 44, "Cycle State")
  button.setAllowsMixedState(true)
  button.setState(NSOffState.cint)
  button.setAlignment(NSCenterTextAlignment)
  echo "initial button state: ", button.state()
  let initialStateLabel = stateName(button.state())
  status.setStringValue("Button state: " & initialStateLabel & " (click to cycle)")
  button.setTitle("Cycle State (" & initialStateLabel & ")")
  button.setOnClick(
    proc(sender: NSButton) =
      let label = stateName(sender.state())
      status.setStringValue("Button state: " & label & " (click to cycle)")
      sender.setTitle("Cycle State (" & label & ")")
      echo "button clicked, state=", label
  )
  root.addSubview(button)

  let boxTop = statusTop + 100
  var authBox = NSBox.new()
  authBox.setFrame(leftInset.cfloat, boxTop.cfloat, 660.cfloat, 132.cfloat)
  authBox.setTitle(@ns"Search + Secure Input (newly ported)")
  authBox.setTransparent(false)
  authBox.setContentViewMargins(nsSize(10, 10))
  root.addSubview(authBox)

  var searchField = NSSearchField.new()
  searchField.setTag(searchTag)
  searchField.setFrame(12.cfloat, 14.cfloat, 390.cfloat, 32.cfloat)
  searchField.setStringValue(@ns"ravynos AppKit")
  searchField.setRecentsAutosaveName(@ns"nutella-example-search")
  searchField.setRecentSearches(
    nsArray[NSString]([@ns"ravynos", @ns"Nutella", @ns"AppKit"])
  )
  authBox.contentView().addSubview(searchField)

  var secureField = NSSecureTextField.new()
  secureField.setTag(secureTag)
  secureField.setFrame(420.cfloat, 14.cfloat, 220.cfloat, 32.cfloat)
  secureField.setStringValue(@ns"supersafe")
  secureField.setEchosBullets(true)
  authBox.contentView().addSubview(secureField)

  let loadedSearches = searchField.recentSearches()
  echo "search recents count: ", loadedSearches.len
  echo "secure field echosBullets: ", secureField.echosBullets()

  let modernTop = boxTop + 132 + rowGap
  var modernBox = NSBox.new()
  modernBox.setFrame(leftInset.cfloat, modernTop.cfloat, 660.cfloat, 152.cfloat)
  modernBox.setTitle(
    @ns"Latest classes: NSClipView, NSCollectionView, NSActionCell, NSButtonCell, NSAlert"
  )
  modernBox.setTransparent(false)
  modernBox.setContentViewMargins(nsSize(10, 10))
  root.addSubview(modernBox)

  var clipView = NSClipView.new()
  clipView.setTag(clipTag)
  clipView.setFrame(12.cfloat, 12.cfloat, 310.cfloat, 94.cfloat)
  clipView.setDrawsBackground(true)
  clipView.setBackgroundColor(nsColor(0.95, 0.97, 1.0, 1.0))

  var clipDoc = newView(0, 0, 520, 220)
  clipDoc.setBackgroundColor(0.88, 0.92, 0.99, 1.0)
  var clipDocLabel = newTextField(
    10, 10, 470, 24, "Clip doc view is larger than the clip (scroll origin is clamped)"
  )
  clipDocLabel.setDrawsBackground(false)
  clipDocLabel.setTextColor(nsColor(0.16, 0.22, 0.34, 1.0))
  clipDoc.addSubview(clipDocLabel)
  clipView.setDocumentView(clipDoc)
  clipView.scrollToPoint(nsPoint(130, 90))
  modernBox.contentView().addSubview(clipView)

  var collectionView = NSCollectionView.new()
  collectionView.setTag(collectionTag)
  collectionView.setFrame(332.cfloat, 12.cfloat, 316.cfloat, 94.cfloat)
  collectionView.setBackgroundColor(0.93, 0.96, 0.93, 1.0)
  collectionView.setSelectable(false)
  collectionView.setMinItemSize(nsSize(72, 40))
  collectionView.setMaxItemSize(nsSize(160, 80))
  collectionView.setMaxNumberOfRows(2)
  collectionView.setMaxNumberOfColumns(3)
  modernBox.contentView().addSubview(collectionView)

  var modernStatus = newTextField(12, 112, 636, 24, "")
  modernStatus.setTag(modernStatusTag)
  modernStatus.setDrawsBackground(false)
  modernStatus.setTextColor(nsColor(0.18, 0.22, 0.28, 1.0))
  modernBox.contentView().addSubview(modernStatus)

  var actionCell = NSActionCell.new()
  actionCell.setTag(17)
  actionCell.setControlView(clipView)

  var buttonCell = NSButtonCell.new()
  buttonCell.setTitle(@ns"Cell Toggle")
  buttonCell.setAllowsMixedState(true)
  buttonCell.setState(NSOffState)
  var cellSender = NSObject.new()
  buttonCell.performClick(cellSender)
  cellSender.value = nil

  var alert = NSAlert.new()
  alert.setAlertStyle(NSInformationalAlertStyle)
  alert.setMessageText(@ns"Latest UI classes wired in appkit_hello")
  alert.setInformativeText(
    @ns"NSAlert runModal is stubbed but API is ready for call-sites."
  )
  discard alert.addButtonWithTitle(@ns"OK")
  discard alert.addButtonWithTitle(@ns"Cancel")
  let alertResult = alert.runModal()

  let visibleRect = clipView.documentVisibleRect()
  modernStatus.setStringValue(
    "clip=(" & $visibleRect.origin.x.int & "," & $visibleRect.origin.y.int &
      "), collection=" & $collectionView.maxNumberOfRows() & "x" &
      $collectionView.maxNumberOfColumns() & ", buttonCell=" &
      stateName(buttonCell.state()) & ", alertResult=" & $alertResult
  )
  echo "action cell tag: ", actionCell.tag()
  echo "clip visible rect: ", visibleRect
  echo "alert buttons: ", alert.buttons().len, ", runModal result: ", alertResult

  var lookedUpTitle = root.viewWithTag(titleTag)
  if not lookedUpTitle.isNil:
    echo "title tag lookup: ", lookedUpTitle.tag()
  lookedUpTitle.value = nil

  var lookedUpClip = root.viewWithTag(clipTag)
  if not lookedUpClip.isNil:
    echo "clip tag lookup: ", lookedUpClip.tag()
  lookedUpClip.value = nil

  var parent = button.superview()
  if not parent.isNil:
    echo "button superview tag: ", parent.tag()
  parent.value = nil

  window.setContentView(root)
  app.addWindow(window)
  app.addWindow(panel)
  window.makeKeyAndOrderFront(app)
  panel.makeKeyAndOrderFront(app)
  echo "window title: ", window.title(), ", tracked windows: ", app.windows().len
  if debugRenderDumpEnabled():
    debugDumpWindowRenderTree(window)

  try:
    let maxFrames = maxFramesFromEnv()
    if maxFrames < 0:
      app.run()
    else:
      discard app.runForFrames(maxFrames)
  except Exception as exc:
    echo "Unable to run AppKit example: ", exc.msg
  finally:
    alert.value = nil
    buttonCell.value = nil
    actionCell.value = nil
    modernStatus.value = nil
    collectionView.value = nil
    clipDocLabel.value = nil
    clipDoc.value = nil
    clipView.value = nil
    modernBox.value = nil
    secureField.value = nil
    searchField.value = nil
    authBox.value = nil
    status.value = nil
    button.value = nil
    subtitle.value = nil
    title.value = nil
    root.value = nil
    panel.value = nil
    window.value = nil
    app.value = nil
