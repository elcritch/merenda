import std/[os, unittest]

import pkg/pixie

import figdraw/commons
import figdraw/figrender as glrenderer
import figdraw/fignodes
import figdraw/windowing/siwinshim

import merenda/nimkit
import merenda/nimkit/app/windows as nimkit_windows

when UseVulkanBackend:
  import pkg/vulkan/wrapper

when not UseMetalBackend and not UseVulkanBackend:
  import pkg/opengl

proc ensureTestOutputDir(subdir = "output"): string =
  result = getCurrentDir() / "tests" / subdir
  createDir(result)

type InkBounds = object
  found: bool
  x0: int
  y0: int
  x1: int
  y1: int

proc isDarkInk(px: ColorRGBX): bool =
  px.a >= 20'u8 and px.r.int + px.g.int + px.b.int <= 540

proc maxChannelDelta(px: ColorRGBX, r, g, b: uint8): int =
  max(abs(px.r.int - r.int), max(abs(px.g.int - g.int), abs(px.b.int - b.int)))

proc colorNear(img: Image, x, y: int, r, g, b: uint8, tol = 18): bool =
  maxChannelDelta(img[x, y], r, g, b) <= tol

proc findDarkInkBounds(img: Image, x0, y0, w, h: int): InkBounds =
  let
    minX = max(0, x0)
    minY = max(0, y0)
    maxX = min(img.width - 1, x0 + w - 1)
    maxY = min(img.height - 1, y0 + h - 1)
  if maxX < minX or maxY < minY:
    return InkBounds(found: false)

  result = InkBounds(found: false, x0: maxX, y0: maxY, x1: minX, y1: minY)
  for y in minY .. maxY:
    for x in minX .. maxX:
      if isDarkInk(img[x, y]):
        if not result.found:
          result = InkBounds(found: true, x0: x, y0: y, x1: x, y1: y)
        else:
          result.x0 = min(result.x0, x)
          result.y0 = min(result.y0, y)
          result.x1 = max(result.x1, x)
          result.y1 = max(result.y1, y)

proc inkWidth(bounds: InkBounds): int =
  if bounds.found:
    bounds.x1 - bounds.x0 + 1
  else:
    0

proc maxInkColumnGap(img: Image, x0, y0, w, h: int): int =
  let bounds = findDarkInkBounds(img, x0, y0, w, h)
  if not bounds.found:
    return high(int)

  var currentGap = 0
  for x in bounds.x0 .. bounds.x1:
    var hasInk = false
    for y in max(0, y0) .. min(img.height - 1, y0 + h - 1):
      if isDarkInk(img[x, y]):
        hasInk = true
        break
    if hasInk:
      result = max(result, currentGap)
      currentGap = 0
    else:
      inc currentGap
  max(result, currentGap)

proc assertCompleteHelloScreenshot(img: Image) =
  check img.width > 0
  check img.height > 0

  check colorNear(img, 40, 32, 236, 247, 254)
  check colorNear(img, 680, 32, 236, 247, 254)
  check colorNear(img, 40, 55, 158, 179, 214)
  check colorNear(img, 680, 55, 158, 179, 214)
  check colorNear(img, 40, 102, 235, 250, 238)
  check colorNear(img, 680, 102, 235, 250, 238)
  check colorNear(img, 40, 150, 220, 220, 218, 24)
  check colorNear(img, 680, 150, 220, 220, 218, 24)

  let
    titleInk = findDarkInkBounds(img, 220, 24, 280, 36)
    subtitleInk = findDarkInkBounds(img, 24, 64, 440, 28)
    statusInk = findDarkInkBounds(img, 34, 94, 300, 36)
    buttonInk = findDarkInkBounds(img, 260, 128, 200, 44)
  check titleInk.found
  check subtitleInk.found
  check statusInk.found
  check buttonInk.found
  check titleInk.inkWidth > 120
  check subtitleInk.inkWidth > 250
  check statusInk.inkWidth > 150
  check buttonInk.inkWidth > 80
  check maxInkColumnGap(img, 220, 24, 280, 36) < 36
  check maxInkColumnGap(img, 24, 64, 440, 28) < 36
  check maxInkColumnGap(img, 34, 94, 300, 36) < 36
  check maxInkColumnGap(img, 260, 128, 200, 44) < 36

proc renderAndScreenshotOnce(
    makeRenders: proc(w, h: float32): Renders {.closure.},
    outputPath: string,
    windowW = 360,
    windowH = 220,
    atlasSize = 2048,
    title = "merenda nimkit screenshot",
): Image =
  when UseMetalBackend:
    try:
      let renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)
      var renders = makeRenders(windowW.float32, windowH.float32)
      renderer.renderFrame(renders, vec2(windowW.float32, windowH.float32))
      result = glrenderer.takeScreenshot(renderer)
      result.writeFile(outputPath)
    except ValueError:
      raise newException(ValueError, "Metal device not available")
  elif UseVulkanBackend:
    let renderer = glrenderer.newFigRenderer(
      atlasSize = atlasSize, backendState = SiwinRenderBackend()
    )
    let window = newSiwinWindow(
      renderer,
      size = ivec2(windowW.int32, windowH.int32),
      fullscreen = false,
      title = title,
    )
    try:
      renderer.setupBackend(window)
      window.firstStep()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      renderer.beginFrame()
      renderer.renderFrame(renders, sz)
      if renderer.backendKind() == rbOpenGL:
        result = glrenderer.takeOneFrameScreenshot(renderer)
        renderer.endFrame()
      else:
        renderer.endFrame()
        result = glrenderer.takeOneFrameScreenshot(renderer)
      if result.isNil or result.width <= 0 or result.height <= 0 or result.data.len == 0:
        raise newException(ValueError, "screenshot unavailable")
      result.writeFile(outputPath)
    except VulkanError as exc:
      raise newException(ValueError, "Vulkan device not available: " & exc.msg)
    except ValueError:
      raise newException(ValueError, "Vulkan device not available")
    finally:
      when not defined(emscripten):
        window.close()
  else:
    let window = newSiwinWindow(
      size = ivec2(windowW.int32, windowH.int32), fullscreen = false, title = title
    )
    try:
      window.firstStep()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      let renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)
      renderer.renderFrame(renders, sz)
      glFinish()
      result = glrenderer.takeOneFrameScreenshot(renderer)
      presentNow(window)
      result.writeFile(outputPath)
    finally:
      when not defined(emscripten):
        window.close()

proc renderAndScreenshotSequence(
    makeInitialRenders: proc(w, h: float32): Renders {.closure.},
    makeUpdatedRenders: proc(w, h: float32): Renders {.closure.},
    initialPath: string,
    updatedPath: string,
    windowW = 720,
    windowH = 360,
    atlasSize = 1024,
    title = "merenda nimkit screenshot sequence",
): tuple[initial, updated: Image] =
  when UseVulkanBackend:
    let renderer = glrenderer.newFigRenderer(
      atlasSize = atlasSize, backendState = SiwinRenderBackend()
    )
    let window = newSiwinWindow(
      renderer,
      size = ivec2(windowW.int32, windowH.int32),
      fullscreen = false,
      title = title,
    )

    proc capture(
        makeRenders: proc(w, h: float32): Renders {.closure.}, outputPath: string
    ): Image =
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      renderer.beginFrame()
      renderer.renderFrame(renders, sz)
      if renderer.backendKind() == rbOpenGL:
        result = glrenderer.takeOneFrameScreenshot(renderer)
        renderer.endFrame()
      else:
        renderer.endFrame()
        result = glrenderer.takeOneFrameScreenshot(renderer)
      if result.isNil or result.width <= 0 or result.height <= 0 or result.data.len == 0:
        raise newException(ValueError, "screenshot unavailable")
      result.writeFile(outputPath)

    try:
      renderer.setupBackend(window)
      window.firstStep()
      result.initial = capture(makeInitialRenders, initialPath)
      result.updated = capture(makeUpdatedRenders, updatedPath)
    except VulkanError as exc:
      raise newException(ValueError, "Vulkan device not available: " & exc.msg)
    except ValueError:
      raise newException(ValueError, "Vulkan device not available")
    finally:
      when not defined(emscripten):
        window.close()
  else:
    raise newException(ValueError, "Vulkan backend not enabled")

proc captureNativeWindowScreenshot(
    window: nimkit_windows.Window, outputPath: string
): Image =
  let renderer = window.rendererOrNil()
  if renderer.isNil:
    raise newException(ValueError, "native renderer unavailable")
  result = glrenderer.takeOneFrameScreenshot(renderer)
  if result.isNil or result.width <= 0 or result.height <= 0 or result.data.len == 0:
    raise newException(ValueError, "screenshot unavailable")
  result.writeFile(outputPath)

suite "nimkit screenshot":
  test "captures hello labels with complete text ink":
    let
      window = newWindow("KNutella Nimkit Hello", frame = initRect(0, 0, 720, 220))
      root = newView()
      layout = newStackView(laVertical)
      title = newTitleLabel("Hello from KNutella/nimkit")
      subtitle = newLabel("Pure Nim responder/action dispatch with plain widget state")
      status = newStatusLabel("Button state: Off (click to cycle)")
      button = newButton("Cycle State (Off)")

    button.buttonType = btToggle
    button.allowsMixedState = true
    layout.spacing = 12.0
    layout.alignment = svaFill
    layout.addArrangedSubview(title, subtitle, status, button)
    root.addSubview(layout)
    layout.pinEdges(
      toGuide = root.contentLayoutGuide(initEdgeInsets(28.0, 28.0, 0.0, 28.0)),
      edges = {leLeft, leTop, leRight},
    )
    window.setContentView(root)
    discard window.selectNextKeyView()

    let outDir = ensureTestOutputDir()
    let outPath = outDir / "nimkit_hello_text.png"
    let tallOutPath = outDir / "nimkit_hello_text_tall.png"
    if fileExists(outPath):
      removeFile(outPath)
    if fileExists(tallOutPath):
      removeFile(tallOutPath)

    block capture:
      try:
        let img = renderAndScreenshotOnce(
          proc(w, h: float32): Renders =
            window.frame = initRect(0.0, 0.0, w, h)
            window.buildRenders(),
          outputPath = outPath,
          windowW = 720,
          windowH = 220,
          atlasSize = 1024,
          title = "merenda nimkit hello screenshot",
        )
        check fileExists(outPath)
        check getFileSize(outPath) > 0
        assertCompleteHelloScreenshot(img)

        let tallImg = renderAndScreenshotOnce(
          proc(w, h: float32): Renders =
            window.frame = initRect(0.0, 0.0, w, h)
            window.buildRenders(),
          outputPath = tallOutPath,
          windowW = 720,
          windowH = 360,
          atlasSize = 1024,
          title = "merenda nimkit hello tall screenshot",
        )
        check fileExists(tallOutPath)
        check getFileSize(tallOutPath) > 0
        assertCompleteHelloScreenshot(tallImg)
      except ValueError:
        skip()
        break capture

  test "captures hello text after state update on one Vulkan renderer":
    when UseVulkanBackend:
      let
        window = newWindow("KNutella Nimkit Hello", frame = initRect(0, 0, 720, 360))
        root = newView()
        layout = newStackView(laVertical)
        title = newTitleLabel("Hello from KNutella/nimkit")
        subtitle =
          newLabel("Pure Nim responder/action dispatch with plain widget state")
        status = newStatusLabel("Button state: Off (click to cycle)")
        button = newButton("Cycle State (Off)")

      button.buttonType = btToggle
      button.allowsMixedState = true
      layout.spacing = 12.0
      layout.alignment = svaFill
      layout.addArrangedSubview(title, subtitle, status, button)
      root.addSubview(layout)
      layout.pinEdges(
        toGuide = root.contentLayoutGuide(initEdgeInsets(28.0, 28.0, 0.0, 28.0)),
        edges = {leLeft, leTop, leRight},
      )
      window.setContentView(root)
      discard window.selectNextKeyView()

      let outDir = ensureTestOutputDir()
      let initialPath = outDir / "nimkit_hello_sequence_initial.png"
      let updatedPath = outDir / "nimkit_hello_sequence_updated.png"
      if fileExists(initialPath):
        removeFile(initialPath)
      if fileExists(updatedPath):
        removeFile(updatedPath)

      block capture:
        try:
          let images = renderAndScreenshotSequence(
            proc(w, h: float32): Renders =
              window.frame = initRect(0.0, 0.0, w, h)
              window.buildRenders(),
            proc(w, h: float32): Renders =
              window.frame = initRect(0.0, 0.0, w, h)
              status.text = "Button state: Mixed (click to cycle)"
              button.title = "Cycle State (Mixed)"
              window.buildRenders(),
            initialPath = initialPath,
            updatedPath = updatedPath,
            windowW = 720,
            windowH = 360,
            atlasSize = 1024,
            title = "merenda nimkit hello sequence screenshot",
          )
          check fileExists(initialPath)
          check getFileSize(initialPath) > 0
          assertCompleteHelloScreenshot(images.initial)
          check fileExists(updatedPath)
          check getFileSize(updatedPath) > 0
          assertCompleteHelloScreenshot(images.updated)
        except ValueError:
          skip()
          break capture
    else:
      skip()

  test "captures hello text after native Vulkan state update":
    let
      app = newApplication()
      window = newWindow("KNutella Nimkit Hello", frame = initRect(80, 80, 720, 360))
      root = newView()
      layout = newStackView(laVertical)
      title = newTitleLabel("Hello from KNutella/nimkit")
      subtitle = newLabel("Pure Nim responder/action dispatch with plain widget state")
      status = newStatusLabel("Button state: Off (click to cycle)")
      button = newButton("Cycle State (Off)")
      action = actionSelector("cycleState")

    proc updateStatus() =
      let label =
        case button.state
        of bsOn: "On"
        of bsMixed: "Mixed"
        of bsOff: "Off"
      status.text = "Button state: " & label & " (click to cycle)"
      button.title = "Cycle State (" & label & ")"

    proc onCycle(sender: DynamicAgent) =
      if not sender.isNil:
        updateStatus()

    button.buttonType = btToggle
    button.allowsMixedState = true
    button.target = newActionTarget(action, onCycle)
    button.action = action

    layout.spacing = 12.0
    layout.alignment = svaFill
    layout.addArrangedSubview(title, subtitle, status, button)
    root.addSubview(layout)
    layout.pinEdges(
      toGuide = root.contentLayoutGuide(initEdgeInsets(28.0, 28.0, 0.0, 28.0)),
      edges = {leLeft, leTop, leRight},
    )
    window.setContentView(root)
    discard window.selectNextKeyView()
    app.addWindow(window)
    window.makeKeyAndOrderFront()

    let outDir = ensureTestOutputDir()
    let initialPath = outDir / "nimkit_hello_native_initial.png"
    let updatedPath = outDir / "nimkit_hello_native_updated.png"
    if fileExists(initialPath):
      removeFile(initialPath)
    if fileExists(updatedPath):
      removeFile(updatedPath)

    block capture:
      try:
        check app.runForFrames(2) == 2
        check window.nativeReady
        let initial = captureNativeWindowScreenshot(window, initialPath)
        check fileExists(initialPath)
        check getFileSize(initialPath) > 0
        assertCompleteHelloScreenshot(initial)

        discard button.send(performClick(), ActionArgs(sender: button))
        discard button.send(performClick(), ActionArgs(sender: button))
        check button.state == bsMixed
        check app.runForFrames(3) == 3
        let updated = captureNativeWindowScreenshot(window, updatedPath)
        check fileExists(updatedPath)
        check getFileSize(updatedPath) > 0
        assertCompleteHelloScreenshot(updated)
      except ValueError:
        skip()
        break capture
      finally:
        window.close()

  test "captures button demo before and after click":
    let
      root = newView(frame = initRect(0, 0, 360, 220))
      label = newTextField("Ready", frame = initRect(24, 24, 220, 32))
      button = newButton("Click", frame = initRect(24, 72, 140, 40))
      action = actionSelector("buttonClicked")

    proc onClicked(sender: DynamicAgent) =
      if not sender.isNil:
        label.setStringValue("Clicked")

    let target = newActionTarget(action, onClicked)
    button.target = target
    button.action = action
    root.addSubview(label)
    root.addSubview(button)

    let outDir = ensureTestOutputDir()
    let initialPath = outDir / "nimkit_button_initial.png"
    let clickedPath = outDir / "nimkit_button_clicked.png"
    if fileExists(initialPath):
      removeFile(initialPath)
    if fileExists(clickedPath):
      removeFile(clickedPath)

    block capture:
      try:
        let initial = renderAndScreenshotOnce(
          proc(w, h: float32): Renders =
            root.setFrame(initRect(0, 0, w, h))
            buildRenders(root),
          outputPath = initialPath,
          title = "merenda nimkit screenshot initial",
        )
        check initial.width > 0
        check initial.height > 0
        check fileExists(initialPath)
        check getFileSize(initialPath) > 0

        check root.clickAt(initPoint(32, 84))
        check label.stringValue == "Clicked"

        let clicked = renderAndScreenshotOnce(
          proc(w, h: float32): Renders =
            root.setFrame(initRect(0, 0, w, h))
            buildRenders(root),
          outputPath = clickedPath,
          title = "merenda nimkit screenshot clicked",
        )
        check clicked.width > 0
        check clicked.height > 0
        check fileExists(clickedPath)
        check getFileSize(clickedPath) > 0
      except ValueError:
        skip()
        break capture
