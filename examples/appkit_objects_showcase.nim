import std/[os, strutils]

import knutella/appkit
import knutella/objc

proc maxFramesFromEnv(defaultValue = -1): int =
  let raw = getEnv("KNUTELLA_EXAMPLE_FRAMES").strip()
  if raw.len == 0:
    return defaultValue
  try:
    parseInt(raw)
  except ValueError:
    defaultValue

var commitEditingCalls = 0
var discardEditingCalls = 0

objcImpl:
  type ShowcaseFormatter = object of NSFormatter

  method stringForObjectValue*(
      self: ShowcaseFormatter, objectValue: NSObject
  ): NSString =
    if objectValue.isNil:
      return @ns"formatted:nil"
    @ns("formatted:" & $unboxNSObject[int](objectValue))

  type ShowcaseEditor = object of NSObject

  method commitEditing*(self: ShowcaseEditor): bool =
    inc commitEditingCalls
    true

  method discardEditing*(self: ShowcaseEditor) =
    inc discardEditingCalls

when isMainModule:
  let contentSize = nsSize(640.0, 360.0)
  let frameSize =
    NSScrollView.frameSizeForContentSize(contentSize, true, true, NSLineBorder)

  var app = NSApp()
  var window = newWindow(120, 100, 900, 620, "KNutella AppKit Object Showcase")
  var panel = NSPanel.new()
  panel.setTitle(@ns"Showcase Panel")
  panel.setFrameOrigin(1040.cfloat, 130.cfloat)
  panel.setContentSize(nsSize(260.0, 120.0))
  panel.setFloatingPanel(true)

  var root = newView(0, 0, 900, 620)
  root.setBackgroundColor(nsColor(0.95, 0.96, 0.98, 1.0))

  var header = newTextField(24, 20, 840, 32, "Implemented NS* objects showcase")
  header.setDrawsBackground(false)
  header.setTextColor(nsColor(0.12, 0.16, 0.26, 1.0))
  let titleDescriptor = NSFontDescriptor.fontDescriptorWithName(@ns"Ubuntu", 20.0)
  let titleFont = NSFont.fontWithDescriptor(titleDescriptor, 0.0)
  header.cell().setFont(titleFont)
  root.addSubview(header)

  var intro = newTextField(24, 58, 840, 24, "")
  intro.setDrawsBackground(false)
  intro.setTextColor(nsColor(0.20, 0.22, 0.30, 1.0))
  intro.setStringValue(
    @ns(
      "Using NSApplication, NSWindow, NSPanel, NSScrollView, NSScroller, NSCell, NSFormatter, NSAttributedString."
    )
  )
  root.addSubview(intro)

  var query = NSSearchField.new()
  query.setFrame(nsRect(24.cfloat, 96.cfloat, 330.cfloat, 30.cfloat))
  query.setStringValue(@ns"appkit showcase")
  query.setRecentsAutosaveName(@ns"knutella-showcase-recent-search")
  query.setRecentSearches(
    nsArray[NSString]([@ns"scroll view", @ns"cells", @ns"events"])
  )
  root.addSubview(query)

  var password = NSSecureTextField.new()
  password.setFrame(nsRect(364.cfloat, 96.cfloat, 220.cfloat, 30.cfloat))
  password.setStringValue(@ns"secret")
  password.setEchosBullets(true)
  root.addSubview(password)

  var status = newTextField(
    24, 132, 840, 28, "Click the button to cycle NSButton + NSButtonCell state."
  )
  status.setDrawsBackground(false)
  status.setTextColor(nsColor(0.10, 0.30, 0.22, 1.0))
  root.addSubview(status)

  var button = newButton(24, 166, 300, 38, "Cycle ButtonCell State")
  button.setAllowsMixedState(true)
  button.setState(NSOffState.cint)
  button.setOnClick(
    proc(sender: NSButton) =
      let stateText =
        case sender.state()
        of NSOnState: "On"
        of NSMixedState: "Mixed"
        else: "Off"
      status.setStringValue("Button state is now " & stateText)
  )
  root.addSubview(button)

  var alertButton = newButton(336, 166, 180, 38, "Show Alert")
  alertButton.setOnClick(
    proc(sender: NSButton) =
      var clickAlert = NSAlert.new()
      clickAlert.setAlertStyle(NSInformationalAlertStyle)
      clickAlert.setMessageText(@ns"Showcase Ready")
      clickAlert.setInformativeText(
        @ns(
          "NSScroller width=" & $NSScroller.scrollerWidth() & ", clickState=" &
            $button.state()
        )
      )
      discard clickAlert.addButtonWithTitle(@ns"OK")
      let clickResult = clickAlert.runModal()
      status.setStringValue("Alert result: " & $clickResult)
      clickAlert.value = nil
  )
  root.addSubview(alertButton)

  var scroll = NSScrollView.new()
  scroll.setFrame(
    nsRect(24.cfloat, 220.cfloat, frameSize.width.cfloat, frameSize.height.cfloat)
  )
  scroll.setBorderType(NSLineBorder)
  scroll.setDrawsBackground(true)
  scroll.setBackgroundColor(nsColor(1.0, 1.0, 1.0, 1.0))
  scroll.setHasVerticalScroller(true)
  scroll.setHasHorizontalScroller(true)
  scroll.setAutohidesScrollers(false)

  var doc = newView(0, 0, 860, 520)
  doc.setBackgroundColor(nsColor(0.89, 0.93, 0.99, 1.0))

  let image = NSImage.imageNamed(@ns"arrow.png")
  var imageView = NSImageView.new()
  imageView.setFrame(nsRect(40.cfloat, 40.cfloat, 120.cfloat, 90.cfloat))
  imageView.setImage(image)
  imageView.setImageScaling(NSImageScaleAxesIndependently)
  imageView.setImageAlignment(NSImageAlignCenter)
  doc.addSubview(imageView)

  var collection = NSCollectionView.new()
  collection.setFrame(nsRect(200.cfloat, 34.cfloat, 260.cfloat, 130.cfloat))
  collection.setSelectable(false)
  collection.setMaxNumberOfRows(2)
  collection.setMaxNumberOfColumns(3)
  collection.setMinItemSize(nsSize(64, 36))
  collection.setMaxItemSize(nsSize(140, 72))
  doc.addSubview(collection)

  var cellFormatter = ShowcaseFormatter.new()
  var rawCell = NSCell.new()
  rawCell.setFormatter(cellFormatter)
  rawCell.setObjectValue(boxNSObject(27))
  let formattedPreview = cellFormatter.stringForObjectValue(boxNSObject(27))

  var actionCell = NSActionCell.new()
  actionCell.setTag(77)
  actionCell.setControlView(scroll.contentView())

  var buttonCell = NSButtonCell.new()
  buttonCell.setAllowsMixedState(true)
  buttonCell.setState(NSOffState)
  buttonCell.performClick(NSObject.new())

  var imageCell = NSImageCell.new()
  imageCell.setImage(image)
  let imageCellRect = imageCell.imageRectForBounds(nsRect(0.0, 0.0, 220.0, 140.0))

  var attrs = nsDictionary[NSObject, NSObject]()
  let fgKey = ownFromId[NSObject](NSForegroundColorAttributeName.value)
  attrs[fgKey] = boxNSObject(42)
  var attributedAlloc = NSAttributedString.alloc()
  var attributed = attributedAlloc.initWithString(@ns"alpha beta gamma", attrs)
  attributedAlloc.value = nil

  var docInfo = newTextField(24, 190, 700, 24, "")
  docInfo.setDrawsBackground(false)
  docInfo.setTextColor(nsColor(0.17, 0.23, 0.35, 1.0))
  docInfo.setStringValue(
    @ns(
      "NSFormatter output=" & $formattedPreview & ", NSAttributedString length=" &
        $attributed.length()
    )
  )
  doc.addSubview(docInfo)

  scroll.setDocumentView(doc)
  scroll.contentView().scrollToPoint(nsPoint(120.0, 80.0))
  scroll.reflectScrolledClipView(scroll.contentView())
  root.addSubview(scroll)

  var controller = NSController.new()
  var editor = ShowcaseEditor.new()
  controller.objectDidBeginEditing(editor.value)
  discard controller.commitEditing()
  controller.discardEditing()
  controller.objectDidEndEditing(editor.value)

  let event =
    newMouseEvent(NSLeftMouseDown, nsPoint(20.0, 30.0), {NSShiftKeyMask}, 0.25, 1, 1)

  window.setContentView(root)
  app.addWindow(window)
  app.addWindow(panel)
  window.makeKeyAndOrderFront(app)
  panel.makeKeyAndOrderFront(app)

  echo "search recents: ", query.recentSearches().len
  echo "secure echosBullets: ", password.echosBullets()
  echo "formatted cell value: ", formattedPreview
  echo "buttonCell state after performClick: ", buttonCell.state()
  echo "imageCell rect: ", imageCellRect
  echo "attributed substring(6,4): ",
    attributed
    .attributedSubstringFromRange(NSMakeRange(6.NSUInteger, 4.NSUInteger))
    .string()
  echo "controller commit/discard calls: ", commitEditingCalls, "/", discardEditingCalls
  echo "vertical scroller enabled: ", scroll.verticalScroller().isEnabled()
  echo "event type example: ", event.`type`()
  echo "click 'Show Alert' to open dialog"

  let frames = maxFramesFromEnv()
  try:
    if frames < 0:
      app.run()
    else:
      discard app.runForFrames(frames)
  except CatchableError as exc:
    echo "Unable to run showcase window backend: ", exc.msg

  attributed.value = nil
  imageCell.value = nil
  buttonCell.value = nil
  actionCell.value = nil
  rawCell.value = nil
  cellFormatter.value = nil
  collection.value = nil
  imageView.value = nil
  docInfo.value = nil
  doc.value = nil
  scroll.value = nil
  alertButton.value = nil
  button.value = nil
  status.value = nil
  password.value = nil
  query.value = nil
  intro.value = nil
  header.value = nil
  root.value = nil
  editor.value = nil
  controller.value = nil
  panel.value = nil
  window.value = nil
  app.value = nil
