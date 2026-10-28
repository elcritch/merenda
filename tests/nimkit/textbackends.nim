## Exercise Merenda font setup with optional native text libraries.
import std/[strutils, unittest]

import figdraw
import pkg/bumpy
import pkg/pixie

import merenda/nimkit/drawing
import merenda/nimkit/foundation/types
import merenda/nimkit/themes
import merenda/nimkit/text/texttypes
import merenda/kosmo/textbackendlogging

when defined(figdrawTestMissingVulkan):
  import figdraw/vulkan/vulkan_dispatch

const merendaTestTextBackend {.strdefine.} = ""
const merendaTestTextDiagnostic {.strdefine.} = ""

proc layoutSample(): GlyphArrangement =
  let font = TextStyle(fontSize: 16, language: initLanguageTag("en-US")).textFont()
  check font.font.fallbackTypefaceIds.len == 0
  when runtimeTextBackends:
    # Retain shaping metadata even if libraries are loaded after font creation.
    check font.font.language == "en-US"
    check fontFallbackResolver() != nil
  typeset(
    bumpy.rect(0, 0, 240, 40), font.font, "Kosmo", minContent = false, wrap = false
  )

proc checkRasterization(layout: GlyphArrangement, backend: GlyphRasterBackend) =
  require layout.arrangedGlyphs.len == 5
  for glyph in layout.arrangedGlyphs:
    check glyph.rasterBackend == backend
  for glyph in layout.glyphs():
    let image = glyph.generateGlyph(force = true, upload = false)
    require not image.isNil
    check image.opaqueBounds().w > 0
    check image.opaqueBounds().h > 0

suite "nimkit optional text backends":
  when defined(figdrawTestMissingVulkan):
    test "an unavailable Vulkan loader raises a catchable error":
      expect LibraryError:
        discard newVulkanDispatch()

  test "backend diagnostics explain library availability":
    let diagnostic = textBackendDiagnostic()
    logTextBackend()
    check diagnostic.backend == textBackend()
    when runtimeTextBackends:
      if diagnostic.backend == "harfbuzzy":
        check diagnostic.detail == "HarfBuzz and FriBidi loaded successfully"
    when merendaTestTextDiagnostic != "":
      check merendaTestTextDiagnostic in diagnostic.detail

  test "default fonts lay out and rasterize with the discovered backend":
    when merendaTestTextBackend != "":
      check textBackend() == merendaTestTextBackend
    let raster =
      if selectedTextBackend() == TextBackendKind.Harfbuzzy:
        GlyphRasterBackend.Harfbuzz
      else:
        GlyphRasterBackend.Pixie
    checkRasterization(layoutSample(), raster)

  when runtimeTextBackends:
    test "Pixie fonts remain usable after retrying native library discovery":
      let previous = selectedTextBackend()
      defer:
        setTextBackend(previous)
      setTextBackend(TextBackendKind.Pixie)
      let pixieLayout = layoutSample()
      checkRasterization(pixieLayout, GlyphRasterBackend.Pixie)
      let loaded = trySetTextBackend(TextBackendKind.Harfbuzzy)
      when merendaTestTextBackend == "pixie":
        check not loaded
      if loaded:
        check selectedTextBackend() == TextBackendKind.Harfbuzzy
        let shapedLayout = layoutSample()
        checkRasterization(shapedLayout, GlyphRasterBackend.Harfbuzz)
        setTextBackend(TextBackendKind.Pixie)
        checkRasterization(shapedLayout, GlyphRasterBackend.Harfbuzz)
      else:
        check selectedTextBackend() == TextBackendKind.Pixie
        checkRasterization(layoutSample(), GlyphRasterBackend.Pixie)
      checkRasterization(pixieLayout, GlyphRasterBackend.Pixie)
