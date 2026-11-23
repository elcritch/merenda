# Higher-order messaging in NimKit and Kosmo

1. [x] **Command routing.** Share a live `findFirst` search between
   `doCommandBySelector` and `dispatchCommandInChain`. Invoke `tryToPerform` at each
   hop to preserve command overrides and the action-selector fallback.
   [Responders](src/merenda/nimkit/responder/responders.nim) · [Windows](src/merenda/nimkit/app/windows.nim)
2. [x] **Key-view navigation.** Share the forward and backward search for a view that
   answers true to `canBecomeKeyView`. Preserve selector routing, live links, the
   4,096-hop limit, and one chance for the starting view on wraparound.
   [View protocol](src/merenda/nimkit/view/viewprotos.nim)
3. [x] **Text insertion and unmarking.** Search the live responder chain for the first
   local handler of `insertText` or `unmarkText`. Both selectors return an empty tuple,
   so a successful send is the match. [Windows](src/merenda/nimkit/app/windows.nim)
4. [x] **Mouse and key event dispatch.** Share the first-true search that identifies the
   consuming responder. Localize the event separately for each receiver and honor the
   mouse dispatch `stopBefore` boundary. This requires a receiver predicate or a
   selector overload that can compute arguments per receiver.
   [Windows](src/merenda/nimkit/app/windows.nim)
5. [x] **Tooltip owner lookup.** Evaluated `follow` and kept the direct loop, which
   keeps per-view coordinates, the routed `toolTipAtPoint` call, and the early return
   together. [Windows](src/merenda/nimkit/app/windows.nim)
6. [x] **Table state provider lookup.** Search the live responder chain for the first
   responder that handles `defaultsStore` or `defaultsScopeId`. Preserve the probe
   order, short circuit, and acceptance of empty replies.
   [Table state](src/merenda/nimkit/tables/tablestate.nim)
7. [x] **Menu model loading.** Keep the direct loop. It reads the current data
   source at each index and appends only handled replies. `collectEach` would keep
   sending to the starting data source if a callback replaces it, and would
   collect intermediate replies before filtering. [Menus](src/merenda/nimkit/controls/menus.nim)
8. [x] **Document tab and matrix model loading.** Keep the direct loops. Each
   reads the current source at every index, skips unhandled replies, and restores
   selection after collecting models. `collectEach` would keep querying a source
   after a callback replaces it or a matrix switches to static models.
   [Document tabs](src/merenda/nimkit/containers/documenttabs.nim) · [Matrices](src/merenda/nimkit/controls/matrices.nim)
9. [x] **Kosmo hint mode.** Use `findFirstReply` over the live responder chain.
   Accept every local reply, including false, so the first surface owns the request.
   [Hint mode](src/merenda/kosmo/hintsmode.nim)
10. [x] **Undo manager and pasteboard requestor lookup.** Use `findFirstReply` over
    the live responder chain for undo managers. Exercise the requestor selector
    directly in tests. Both searches skip unhandled sends and handled `none` replies.
    [Responders](src/merenda/nimkit/responder/responders.nim)
11. [x] **Popup-list key-view commands.** Reuse `performCommandInChain` for next
    and previous key-view commands. Start at the popup's next responder and
    preserve `tryToPerform` overrides.
    [Popup lists](src/merenda/nimkit/controls/popuplists.nim)
12. [x] **Kosmo content editing.** Share the pane-membership check with focus
    detection, then use a bounded live `findFirst` for native editing commands.
    A local action implementation claims the edit even when `tryToPerform`
    returns false.
    [Editor](src/merenda/kosmo/application_editor.nim)
13. [x] **Kosmo file-filter visibility.** Share the close and expression button
    setters across initialization, show, and dismiss. Keep direct property
    assignments to preserve required dispatch and layout notification order.
    [File tree](src/merenda/kosmo/filetree.nim)
14. [x] **Search-bar controls.** Share the Previous/Next `enabled=` assignments
    across initialization and match updates. Set `hidden` directly on replacement
    controls after transferring focus back to the query field when needed.
    [Search bars](src/merenda/nimkit/controls/searchbars.nim)
15. [x] **Token-field enabled state.** Update the backing cell, then use direct
    setters for the input and live chip list. If a setter rebuilds the list,
    new chips inherit the cell's enabled state and traversal skips removed chips.
    [Token fields](src/merenda/nimkit/controls/tokenfields.nim)
16. [x] **Compact-tab buttons.** Send `hidden=` to the buttons when the bar
    collapses or expands and `needsDisplay=` when focus changes.
    [Compact tabs](src/merenda/nimkit/containers/compacttabviews.nim)
17. [x] **Mouse hit policy.** Keep the direct loop. It localizes the event for
    each receiver, returns the first non-default reply with its responder, and
    reads the next responder after each send.
    [Windows](src/merenda/nimkit/app/windows.nim)
18. [x] **Keyboard scroll routing.** Walk `responderChain()` once and return on
    the first local `scrollKey` reply of true. With `consumeIfOffered`, remember
    a handled false and still give outer responders a chance.
    [Responders](src/merenda/nimkit/responder/responders.nim)
19. [x] **Native IME state.** Find the first responder that supplies both selection
    and text, then query caret and marked-range state on that responder. Preserve
    the order of the initial local probes.
    [Windows](src/merenda/nimkit/app/windows.nim)
20. [x] **Table type-to-select.** Use `findFirst` over lazy wrapped indexes.
    Skip disabled rows and use the row summary only when the source leaves
    `normalizedSearchTextForRow` unhandled.
    [Table selection](src/merenda/nimkit/tables/tableselection.nim)
21. [x] **Toolbar focus.** Use NimKit's `ToolbarFocusProtocol` and
    `findFirstReply` for Kosmo's `focusToolToolbar`. Accept a handled false as
    final and continue past editor panes with hidden controls.
    [Responders](src/merenda/nimkit/responder/responders.nim) · [Dock controller](src/merenda/kosmo/application_dock.nim)
22. [x] **Menu action targets.** Use `findFirst` over the live responder chain
    with the existing `respondsTo` check. Validate and dispatch on the first
    matching target.
    [Menus](src/merenda/nimkit/controls/menus.nim)
23. [x] **Scroll-wheel dispatch.** Use `findFirst` to return the consuming
    responder. Localize coordinates at each hop, honor
    `wantsForwardedScrollEvents`, and accept any handled `scrollWheel` reply.
    [Windows](src/merenda/nimkit/app/windows.nim)
24. [x] **Native marked-text composition.** Use `findFirst` to stop at the
    first local `setMarkedText` handler. Calculate the replacement range from
    each candidate's text when the native event supplies a range.
    [Windows](src/merenda/nimkit/app/windows.nim)
25. [x] **Menu keyboard shortcuts.** Search menu items in depth-first order.
    Skip hidden items and separators with their submenus, and check each
    parent's shortcut before descending.
    [Menus](src/merenda/nimkit/controls/menus.nim)
26. [x] **View lookup by tag or identifier.** Share the recursive searches
    through the tree overload of `findFirst`. Preserve root-first order and
    the existing field comparisons.
    [Views](src/merenda/nimkit/view/views.nim)
27. [ ] **Responder membership.** Share a live identity search across
    transient-window dismissal, Kosmo sidebar focus, and focus transfer when
    editor content changes.
    [Windows](src/merenda/nimkit/app/windows.nim) · [Kosmo editor](src/merenda/kosmo/application_editor.nim)
28. [ ] **Kosmo dock drop targets.** Use `findFirstReply` to return the first
    eligible host and its valid drop target. Resolve coordinates per host and
    apply the tab-strip center override to the winning target.
    [Dock controller](src/merenda/kosmo/application_dock.nim)
29. [ ] **Table and collection identifier lookup.** Keep the direct data-source
    lookup first, then use a lazy `findFirst` scan on an absent or out-of-bounds
    reply. Preserve table aliases and the collection's index-string fallback.
    [Table rows](src/merenda/nimkit/tables/tablecore.nim) · [Collection items](src/merenda/nimkit/containers/collectionviews.nim)
30. [ ] **Color-picker palette redraw.** Use `sendEachTo` for `needsDisplay=`
    across the palette buttons, then synchronize the wheel and value controls
    in the existing order.
    [Color picker](src/merenda/nimkit/controls/colorpicker.nim)
