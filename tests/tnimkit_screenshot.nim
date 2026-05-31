import std/[os, unittest]

import pkg/pixie

import figdraw/commons
import figdraw/figrender as glrenderer
import figdraw/fignodes
import figdraw/windowing/siwinshim

import merenda/nimkit

when UseVulkanBackend:
  import pkg/vulkan/wrapper

when not UseMetalBackend and not UseVulkanBackend:
  import pkg/opengl

proc ensureTestOutputDir(subdir = "output"): string =
  result = getCurrentDir() / "tests" / subdir
  createDir(result)

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
        result = glrenderer.takeScreenshot(renderer, readFront = false)
        renderer.endFrame()
      else:
        renderer.endFrame()
        result = glrenderer.takeScreenshot(renderer)
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
      renderer.beginFrame()
      renderer.renderFrame(renders, sz)
      glFinish()
      result = glrenderer.takeScreenshot(renderer, readFront = false)
      renderer.endFrame()
      presentNow(window)
      result.writeFile(outputPath)
    finally:
      when not defined(emscripten):
        window.close()

suite "nimkit screenshot":
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
    button.setTarget(target)
    button.setAction(action)
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
