## Persistent solver experiments are opt-in; the default build keeps fresh solves.
when defined(merendaPersistentLayout) and defined(merendaProfile):
  import std/[strutils, unittest]
  import merenda/foundation/backrefs
  import merenda/nimkit
  import merenda/nimkit/view/viewbase
  from pkg/kiwiberry import sameVariable
  import merenda/nimkit/debug/viewprofiling
  from merenda/nimkit/view/viewconstraints import solveBlocked

  type PersistentFixture = object
    root, child, peer: View

  proc fixture(): PersistentFixture =
    result.root = newView(frame = rect(0, 0, 200, 100))
    result.root{vpPersistentLayout} = true
    result.child = newView(frame = rect(10, 5, 40, 20))
    result.peer = newView(frame = rect(60, 10, 30, 20))
    result.child.autoresizingMask = {cxWidthSizable}
    result.root.addSubview(result.child)
    result.root.addSubview(result.peer)

  proc layout(root: View): ViewProfile =
    resetViewProfile()
    root.layoutSubtreeIfNeeded()
    currentViewProfile()

  proc sameFrames(a, b: PersistentFixture): bool =
    a.root.frame == b.root.frame and a.child.frame == b.child.frame and
      a.peer.frame == b.peer.frame

  suite "experimental persistent layout":
    test "only opted-in roots retain solvers and disabling releases the cache":
      let item = fixture()
      item.root{vpPersistentLayout} = false
      check item.root.layout().persistentBuilds == 0
      check not item.root.xPersistentLayout.valid
      item.root{vpPersistentLayout} = true
      check item.root.layout().persistentBuilds == 1
      require item.root.xPersistentLayout.valid
      item.root{vpPersistentLayout} = false
      check not item.root.xPersistentLayout.valid
      item.root.frame = rect(0, 0, 230, 100)
      let profile = item.root.layout()
      check profile.persistentReuses == 0
      check profile.persistentBuilds == 0

    test "stable resize reuses variables and agrees with a fresh solve":
      let fresh = fixture()
      let cached = fixture()
      discard fresh.root.layout()
      let first = cached.root.layout()
      check first.persistentBuilds == 1
      require cached.root.xPersistentLayout.valid
      for width in [240.0'f32, 180.0'f32, 300.0'f32, 200.0'f32]:
        fresh.root.frame = rect(0, 0, width, 100)
        cached.root.frame = rect(0, 0, width, 100)
        fresh.root.xPersistentLayout = default(PersistentLayoutCache)
        discard fresh.root.layout()
        let profile = cached.root.layout()
        check profile.persistentReuses == 1
        check profile.persistentFallbacks == 0
        check cached.sameFrames(fresh)
        check not cached.root.xLastLayoutSolveDiagnostic.failed

    test "repeated moves and resizes agree with fresh frames":
      let fresh = fixture()
      let cached = fixture()
      discard fresh.root.layout()
      discard cached.root.layout()
      for step in 0 ..< 40:
        let frame = rect(
          float32((step mod 3) * 3),
          float32((step mod 5) * 2),
          float32(180 + (step mod 7) * 13),
          float32(90 + (step mod 4) * 7),
        )
        fresh.root.frame = frame
        cached.root.frame = frame
        fresh.root.xPersistentLayout = default(PersistentLayoutCache)
        discard fresh.root.layout()
        discard cached.root.layout()
        check cached.sameFrames(fresh)
        check not cached.root.xLastLayoutSolveDiagnostic.failed

    test "fitting uses separate variables and leaves the live cache intact":
      let item = fixture()
      let fresh = fixture()
      discard item.root.layout()
      discard fresh.root.layout()
      require item.root.xPersistentLayout.valid
      let variable = item.root.xPersistentLayout.items[0].left
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      let expected = fresh.root.fittingSize()
      resetViewProfile()
      check item.root.fittingSize() == expected
      check currentViewProfile().persistentReuses == 0
      check item.root.xPersistentLayout.items[0].left.sameVariable(variable)
      item.root.frame = rect(0, 0, 230, 100)
      let profile = item.root.layout()
      check profile.persistentReuses == 1

    test "releasing generated inputs also releases the retained solver":
      let item = fixture()
      discard item.root.layout()
      require item.root.xPersistentLayout.valid
      item.root.releaseGeneratedLayoutInputs()
      check not item.root.xPersistentLayout.valid
      item.root.needsLayout = true
      let profile = item.root.layout()
      check profile.persistentBuilds == 1

    test "changed autoresizing inputs update in place and removed children rebuild":
      let fresh = fixture()
      let cached = fixture()
      discard fresh.root.layout()
      discard cached.root.layout()
      fresh.child.autoresizingMask = {}
      cached.child.autoresizingMask = {}
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      # Changed equations keep their positions and are replaced in the solver.
      let changed = cached.root.layout()
      check changed.persistentFallbacks == 0
      check changed.persistentReuses == 1
      check cached.sameFrames(fresh)
      fresh.peer.removeFromSuperview()
      cached.peer.removeFromSuperview()
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      let removed = cached.root.layout()
      check removed.persistentFallbacks == 1
      check removed.persistentBuilds == 1
      check cached.root.frame == fresh.root.frame
      check cached.child.frame == fresh.child.frame

    test "content, appearance and visibility changes match fresh fixed controls":
      proc controls(): tuple[root: View, label: Label] =
        result.root = newView(frame = rect(0, 0, 200, 100))
        result.root{vpPersistentLayout} = true
        result.label = newLabel("Original")
        result.label.frame = rect(10, 5, 80, 25)
        result.label.autoresizingMaskConstraints = true
        result.root.addSubview(result.label)

      let fresh = controls()
      let cached = controls()
      discard fresh.root.layout()
      discard cached.root.layout()
      for label in [fresh.label, cached.label]:
        label.stringValue = "A longer title"
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      discard cached.root.layout()
      check cached.label.frame == fresh.label.frame
      var appearance = initAppearance()
      appearance[srTextField, StyleFontSize] = 24.0
      fresh.root.appearance = appearance
      cached.root.appearance = appearance
      fresh.label.labelStyle = lsHeading
      cached.label.labelStyle = lsHeading
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      discard cached.root.layout()
      check cached.label.frame == fresh.label.frame
      fresh.label.hidden = true
      cached.label.hidden = true
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      discard cached.root.layout()
      check cached.label.frame == fresh.label.frame
      check cached.root.cssLayoutDiagnostics() == fresh.root.cssLayoutDiagnostics()

    test "authored required conflicts and CSS use fresh solvers":
      let fresh = fixture()
      let cached = fixture()
      discard fresh.root.layout()
      discard cached.root.layout()
      for item in [fresh, cached]:
        item.root.addConstraint(item.child[atWidth].equalTo(80))
        item.root.addConstraint(item.child[atWidth].equalTo(90))
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      let conflict = cached.root.layout()
      check conflict.persistentFallbacks == 1
      check conflict.persistentReuses == 0
      check not cached.root.xPersistentLayout.valid
      check cached.sameFrames(fresh)
      check cached.child.frame.size.width == 80
      for item in [fresh, cached]:
        for constraint in item.root.constraints():
          item.root.removeConstraint(constraint)
      discard cached.root.layout()
      require cached.root.xPersistentLayout.valid
      let parsed = parseCssTheme("#child { width: 60px; }", initTheme())
      require parsed.diagnostics.len == 0
      for item in [fresh, cached]:
        item.child.styleId = "child"
        item.root.appearance = initAppearance(parsed.theme)
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      let styled = cached.root.layout()
      check styled.persistentFallbacks == 1
      check styled.persistentReuses == 0
      check not cached.root.xPersistentLayout.valid
      check cached.sameFrames(fresh)
      check cached.root.cssLayoutDiagnostics() == fresh.root.cssLayoutDiagnostics()

    test "a budget failure discards the cache and preserves committed frames":
      let item = fixture()
      discard item.root.layout()
      let before = item.child.frame
      item.root.xLayoutSolveLimits = LayoutSolveLimits(maxViews: 1)
      item.root.frame = rect(0, 0, 240, 100)
      let failed = item.root.layout()
      check failed.persistentFallbacks == 1
      check failed.solverFailures == 1
      check item.root.xLastLayoutSolveDiagnostic.limit == lslViews
      check item.child.frame == before
      check not item.root.xPersistentLayout.valid
      check item.root.solveBlocked(lsmLayout)
      let diagnostic = item.root.xLastLayoutSolveDiagnostic
      discard item.root.layout()
      check item.root.xLastLayoutSolveDiagnostic == diagnostic

    test "constraint, coefficient and memory limits match fresh failure diagnostics":
      for limits in [
        LayoutSolveLimits(maxConstraints: 4),
        LayoutSolveLimits(maxCoefficients: 1),
        LayoutSolveLimits(maxMemoryBytes: 1),
      ]:
        let fresh = fixture()
        let cached = fixture()
        discard fresh.root.layout()
        discard cached.root.layout()
        fresh.root.xLayoutSolveLimits = limits
        cached.root.xLayoutSolveLimits = limits
        fresh.root.frame = rect(0, 0, 240, 100)
        cached.root.frame = rect(0, 0, 240, 100)
        fresh.root.xPersistentLayout = default(PersistentLayoutCache)
        discard fresh.root.layout()
        let profile = cached.root.layout()
        let a = fresh.root.xLastLayoutSolveDiagnostic
        let b = cached.root.xLastLayoutSolveDiagnostic
        check profile.persistentFallbacks == 1
        check a.failed and b.failed
        check b.limit == a.limit
        check b.views == a.views
        check b.constraints == a.constraints
        check b.coefficients == a.coefficients
        check b.estimatedMemoryBytes == a.estimatedMemoryBytes
        check cached.sameFrames(fresh)

    test "a conflicting root resize abandons the mutated solver before fallback":
      let fresh = fixture()
      let cached = fixture()
      discard fresh.root.layout()
      discard cached.root.layout()
      fresh.root.frame = rect(0, 0, 0, 100)
      cached.root.frame = rect(0, 0, 0, 100)
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      let conflicted = cached.root.layout()
      check conflicted.persistentFallbacks == 1
      check conflicted.persistentReuses == 0
      check cached.sameFrames(fresh)
      check cached.root.xLastLayoutSolveDiagnostic.failed ==
        fresh.root.xLastLayoutSolveDiagnostic.failed
      check not cached.root.xPersistentLayout.valid
      fresh.root.frame = rect(0, 0, 250, 100)
      cached.root.frame = rect(0, 0, 250, 100)
      fresh.root.xPersistentLayout = default(PersistentLayoutCache)
      discard fresh.root.layout()
      discard cached.root.layout()
      check cached.sameFrames(fresh)

    test "cached variables and constraints do not retain removed views or roots":
      var rootRef, childRef: BackRef[View]
      block:
        let root = newView(frame = rect(0, 0, 200, 100))
        root{vpPersistentLayout} = true
        rootRef.target = root
        block:
          let child = newView(frame = rect(10, 5, 40, 20))
          childRef.target = child
          root.addSubview(child)
          discard root.layout()
          require root.xPersistentLayout.valid
          child.removeFromSuperview()
        check childRef.isNil
        check not rootRef.isNil
      check rootRef.isNil

    test "intrinsic-sized trees with authored priorities reuse and match fresh solves":
      type IntrinsicTree = object
        root: StackView
        labels: seq[Label]
        fields: seq[TextField]
        widths: seq[LayoutConstraint]
        views: seq[View]

      proc collect(view: View, views: var seq[View]) =
        views.add view
        for child in view.subviews:
          child.collect(views)

      proc build(persistent: bool): IntrinsicTree =
        result.root = newStackView(laVertical)
        result.root.frame = rect(0, 0, 420, 360)
        result.root{vpPersistentLayout} = persistent
        for i in 0 ..< 6:
          let row = newStackView(laHorizontal)
          let label = newLabel("Label " & $i)
          let field = newTextField("value " & $i)
          let button = newButton("Go")
          row.addArrangedSubview(label)
          row.addArrangedSubview(field)
          row.addArrangedSubview(button)
          # Competing non-required widths exercise priority resolution.
          let width =
            field[atWidth].equalTo(120 + float32(i * 10), priority = LayoutPriorityLow)
          activate(width)
          activate(
            field[atWidth].greaterThanOrEqualTo(60, priority = LayoutPriorityHigh)
          )
          result.root.addArrangedSubview(row)
          result.labels.add label
          result.fields.add field
          result.widths.add width
        result.root.collect(result.views)

      proc relayout(tree: IntrinsicTree): ViewProfile =
        layout(View(tree.root))

      var fresh = build(false)
      var cached = build(true)
      discard fresh.relayout()
      discard cached.relayout()
      var reuses = 0
      var state = 0x2545F491'u32
      proc next(state: var uint32, bound: int): int =
        state = state xor (state shl 13)
        state = state xor (state shr 17)
        state = state xor (state shl 5)
        int(state mod uint32(bound))

      for step in 0 ..< 120:
        let index = state.next(6)
        case state.next(5)
        of 0:
          let text = "edited " & $step & " " & "x".repeat(state.next(12))
          fresh.fields[index].stringValue = text
          cached.fields[index].stringValue = text
        of 1:
          let width = 300 + float32(state.next(240))
          let height = 300 + float32(state.next(120))
          fresh.root.frame = rect(0, 0, width, height)
          cached.root.frame = rect(0, 0, width, height)
        of 2:
          let value = 40 + float32(state.next(200))
          fresh.widths[index].constant = value
          cached.widths[index].constant = value
        of 3:
          let priority =
            if state.next(2) == 0:
              LayoutPriorityLow
            else:
              LayoutPriority(500)
          fresh.widths[index].priority = priority
          cached.widths[index].priority = priority
        else:
          let text = "L" & "y".repeat(state.next(16))
          fresh.labels[index].stringValue = text
          cached.labels[index].stringValue = text
        discard fresh.relayout()
        let profile = cached.relayout()
        reuses += profile.persistentReuses
        for i in 0 ..< fresh.views.len:
          if fresh.views[i].frame != cached.views[i].frame:
            checkpoint "step " & $step & " view " & $i
          check fresh.views[i].frame == cached.views[i].frame
      check reuses > 0

when defined(merendaPersistentLayout) and not defined(merendaProfile):
  import std/unittest
  import merenda/nimkit
  import merenda/nimkit/view/viewbase
  from pkg/kiwiberry import sameVariable

  suite "persistent layout without profiling":
    test "a stable resize retains and updates the same solver":
      let root = newView(frame = rect(0, 0, 100, 80))
      let child = newView(frame = rect(0, 0, 20, 20))
      root{vpPersistentLayout} = true
      child.autoresizingMask = {cxWidthSizable}
      root.addSubview(child)
      root.layoutSubtreeIfNeeded()
      require root.xPersistentLayout.valid
      let saved = root.xPersistentLayout.items[0].left
      root.frame = rect(0, 0, 140, 80)
      root.layoutSubtreeIfNeeded()
      check root.xPersistentLayout.items[0].left.sameVariable(saved)
      check child.frame.size.width == 60
      root{vpPersistentLayout} = false
      check not root.xPersistentLayout.valid
