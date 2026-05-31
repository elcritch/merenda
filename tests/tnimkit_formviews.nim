import std/unittest

import merenda/nimkit

type FixedIntrinsicView = ref object of View
  naturalSize: Size

protocol FixedIntrinsicLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: FixedIntrinsicView): IntrinsicSize =
    initIntrinsicSize(view.naturalSize)

proc newFixedIntrinsicView(width, height: float32): FixedIntrinsicView =
  result = FixedIntrinsicView()
  initViewFields(result, initRect(0.0, 0.0, width, height))
  result.naturalSize = initSize(width, height)
  result.translatesAutoresizingMaskIntoConstraints = false
  discard result.withProtocol(FixedIntrinsicLayout)

suite "nimkit form views":
  test "intrinsic size uses max label and field columns with spacing and insets":
    let
      form = newFormView(frame = initRect(0, 0, 1, 1))
      shortLabel = newFixedIntrinsicView(40, 12)
      longLabel = newFixedIntrinsicView(60, 14)
      nameField = newFixedIntrinsicView(100, 20)
      roleField = newFixedIntrinsicView(80, 30)

    form.columnSpacing = 8.0
    form.rowSpacing = 5.0
    form.edgeInsets = initEdgeInsets(1.0, 2.0, 3.0, 4.0)
    form.addRow(shortLabel, nameField)
    form.addRow(longLabel, roleField)

    check form.rows.len == 2
    check form.intrinsicContentSize() == initIntrinsicSize(174.0, 59.0)

    form.sizeToFit()
    form.layoutSubtreeIfNeeded()

    check form.frame().size == initSize(174.0, 59.0)
    check shortLabel.frame() == initRect(22.0, 5.0, 40.0, 12.0)
    check nameField.frame() == initRect(70.0, 1.0, 100.0, 20.0)
    check longLabel.frame() == initRect(2.0, 34.0, 60.0, 14.0)
    check roleField.frame() == initRect(70.0, 26.0, 100.0, 30.0)

  test "field column stretches while labels keep natural width":
    let
      form = newFormView(frame = initRect(0, 0, 240, 48))
      label = newFixedIntrinsicView(48, 14)
      field = newFixedIntrinsicView(80, 20)

    form.columnSpacing = 12.0
    form.addRow(label, field)
    form.layoutSubtreeIfNeeded()

    check label.frame() == initRect(0.0, 3.0, 48.0, 14.0)
    check field.frame() == initRect(60.0, 0.0, 180.0, 20.0)

  test "leading labels and fill row alignment are supported":
    let
      form = newFormView(frame = initRect(0, 0, 180, 40))
      label = newFixedIntrinsicView(36, 12)
      field = newFixedIntrinsicView(90, 20)

    form.labelAlignment = flaLeading
    form.rowAlignment = fraFill
    form.columnSpacing = 10.0
    form.addRow(label, field)
    form.layoutSubtreeIfNeeded()

    check label.frame() == initRect(0.0, 0.0, 36.0, 20.0)
    check field.frame() == initRect(46.0, 0.0, 134.0, 20.0)

  test "minimum field width participates in intrinsic and layout sizing":
    let
      form = newFormView(frame = initRect(0, 0, 1, 1))
      label = newFixedIntrinsicView(30, 10)
      field = newFixedIntrinsicView(20, 12)

    form.minFieldWidth = 96.0
    form.addRow(label, field)

    check form.intrinsicContentSize() == initIntrinsicSize(134.0, 12.0)

    form.sizeToFit()
    form.layoutSubtreeIfNeeded()
    check field.frame().size.width == 96.0

  test "hidden rows are omitted from intrinsic size and layout":
    let
      form = newFormView(frame = initRect(0, 0, 1, 1))
      visibleLabel = newFixedIntrinsicView(30, 10)
      visibleField = newFixedIntrinsicView(80, 20)
      hiddenLabel = newFixedIntrinsicView(100, 10)
      hiddenField = newFixedIntrinsicView(120, 20)

    form.addRow(visibleLabel, visibleField)
    form.addRow(hiddenLabel, hiddenField)
    hiddenLabel.hidden = true
    hiddenField.hidden = true

    check form.intrinsicContentSize() == initIntrinsicSize(118.0, 20.0)

    form.sizeToFit()
    form.layoutSubtreeIfNeeded()
    check visibleField.frame().size.width == 80.0
    check hiddenField.frame() == initRect(0.0, 0.0, 120.0, 20.0)

  test "field content changes invalidate form and parent lazily":
    let
      root = newView(frame = initRect(0, 0, 300, 120))
      form = newFormView(frame = initRect(10, 10, 1, 1))
      label = newTextField("Name", frame = initRect(0, 0, 1, 1))
      field = newTextField("Ada", frame = initRect(0, 0, 1, 1))

    label.editable = false
    label.selectable = false
    root.addSubview(form)
    form.addRow(label, field)
    form.sizeToFit()
    root.layoutSubtreeIfNeeded()
    root.setNeedsLayout(false)
    form.setNeedsLayout(false)
    field.setNeedsLayout(false)

    let oldFrame = form.frame()
    field.text = "A much longer field value"

    check form.frame() == oldFrame
    check root.needsLayout
    check form.needsLayout
    check field.needsLayout

    form.sizeToFit()
    root.layoutSubtreeIfNeeded()
    check form.frame().size.width > oldFrame.size.width

  test "form participates in deterministic constraint layout":
    let
      root = newView(frame = initRect(0, 0, 320, 120))
      form = newFormView(frame = initRect(0, 0, 1, 1))
      label = newFixedIntrinsicView(50, 12)
      field = newFixedIntrinsicView(80, 20)
      left = newLayoutConstraint(form, latLeft, lrEqual, root, latLeft, constant = 20)
      right =
        newLayoutConstraint(form, latRight, lrEqual, root, latRight, constant = -30)
      top = newLayoutConstraint(form, latTop, lrEqual, root, latTop, constant = 10)
      height = newLayoutConstraint(form, latHeight, constant = 40)

    form.translatesAutoresizingMaskIntoConstraints = false
    form.columnSpacing = 10.0
    root.addSubview(form)
    form.addRow(label, field)
    activateConstraints([left, right, top, height])
    root.layoutSubtreeIfNeeded()

    check form.frame() == initRect(20.0, 10.0, 270.0, 40.0)
    check label.frame() == initRect(0.0, 4.0, 50.0, 12.0)
    check field.frame() == initRect(60.0, 0.0, 210.0, 20.0)

  test "removing a row subview removes the row":
    let
      form = newFormView(frame = initRect(0, 0, 120, 40))
      label = newFixedIntrinsicView(30, 10)
      field = newFixedIntrinsicView(80, 20)

    form.addRow(label, field)
    check form.rows.len == 1

    label.removeFromSuperview()
    check form.rows.len == 0
