import std/unittest

import knutella/appkit
import knutella/objc

var commitCallCount = 0
var discardCallCount = 0

objcImpl:
  type CommitPassEditor = object of NSObject

  method commitEditing*(self: CommitPassEditor): bool =
    inc commitCallCount
    true

  method discardEditing*(self: CommitPassEditor) =
    inc discardCallCount

suite "appkit nscontroller":
  test "controller markers are initialized and recognized by identity":
    let noSelection = NSNoSelectionMarker
    let multipleValues = NSMultipleValuesMarker
    let notApplicable = NSNotApplicableMarker

    check(not noSelection.isNil)
    check(not multipleValues.isNil)
    check(not notApplicable.isNil)
    check(noSelection != multipleValues)
    check(noSelection != notApplicable)
    check(multipleValues != notApplicable)
    check(NSIsControllerMarker(noSelection))
    check(NSIsControllerMarker(multipleValues))
    check(NSIsControllerMarker(notApplicable))
    check(not NSIsControllerMarker(ns("NSNoSelectionMarker").value))
    check(not NSIsControllerMarker(nil))

  test "editing lifecycle tracks one editor and dispatches commit/discard":
    commitCallCount = 0
    discardCallCount = 0

    var controller = NSController.new()
    var editor = CommitPassEditor.new()

    check(not controller.isEditing())
    controller.objectDidBeginEditing(editor.value)
    check(controller.isEditing())

    check(controller.commitEditing())
    check(commitCallCount == 1)

    controller.discardEditing()
    check(discardCallCount == 1)

    controller.objectDidEndEditing(editor.value)
    check(not controller.isEditing())

    editor.value = nil
    controller.value = nil
