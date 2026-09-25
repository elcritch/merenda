import std/[strutils, unittest]

import figdraw
import ./fixtures/rendergeometry
import ./fixtures/widgetflows

import merenda/nimkit

import ../../examples/window_effects_demo

suite "NimKit window effects demo":
  test "translucent root does not resolve to the opaque themed background":
    let demo = newWindowEffectsDemo()
    defer:
      demo.window.close()

    check demo.root.backgroundColor.a > 0.0'f32
    check demo.root.backgroundColor.a < 1.0'f32

    let
      list = buildRenders(demo.root)[DefaultDrawLevel]
      rootNode = list.nodes[list.firstRectangle().int]
    check rootNode.kind == nkRectangle
    check rootNode.fill == fill(demo.root.backgroundColor)

  test "controls update and clear the staged backdrop request":
    let demo = newWindowEffectsDemo()
    defer:
      demo.window.close()

    check demo.window.backdrop.kind == wbekBlur
    check demo.window.backdrop.regions.len == 0

    require demo.window.chooseItem(demo.effectPicker, "Material: Sidebar")
    check demo.window.backdrop.kind == wbekMaterial
    check demo.window.backdrop.material == bmSidebar
    check demo.status.text.contains("Material: Sidebar")

    require demo.window.clickView(demo.regionToggle)
    require demo.window.backdrop.regions.len > 0
    for region in demo.window.backdrop.regions:
      check region.size.width > 0
      check region.size.height > 0
      check region.minX >= demo.root.bounds().minX
      check region.minY >= demo.root.bounds().minY
      check region.maxX <= demo.root.bounds().maxX
      check region.maxY <= demo.root.bounds().maxY

    require demo.window.clickView(demo.applyButton)
    check demo.window.backdrop.kind == wbekMaterial

    require demo.window.clickView(demo.clearButton)
    check demo.window.backdrop.kind == wbekNone

    require demo.window.clickView(demo.applyButton)
    check demo.window.backdrop.kind == wbekMaterial
    require demo.window.clickView(demo.regionToggle)
    check demo.window.backdrop.regions.len == 0
