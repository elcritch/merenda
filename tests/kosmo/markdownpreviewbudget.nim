## The policy decides evictions without retaining preview or document owners.

import std/unittest
import merenda/kosmo/markdownpreviewbudget

suite "Kosmo Markdown preview budget":
  test "shared owner is counted once until its last consumer is evicted":
    let entries = [
      MarkdownPreviewBudgetEntry(
        paneId: 1, lastUsed: 1, viewBytes: 10, ownerId: 42, ownerBytes: 100
      ),
      MarkdownPreviewBudgetEntry(
        paneId: 2, lastUsed: 2, viewBytes: 10, ownerId: 42, ownerBytes: 100
      ),
      MarkdownPreviewBudgetEntry(
        paneId: 3, lastUsed: 3, viewBytes: 20, ownerId: 43, ownerBytes: 30
      ),
    ]
    let one = markdownPreviewEvictions(entries, 160, 3)
    check one.victims == @[0]
    check one.retainedBytes == 160
    check not one.overByteBudget
    let both = markdownPreviewEvictions(entries, 50, 3)
    check both.victims == @[0, 1]
    check both.retainedBytes == 50
    check not both.overByteBudget

  test "stale owner estimates use the largest retained value":
    let entries = [
      MarkdownPreviewBudgetEntry(
        paneId: 1, lastUsed: 1, viewBytes: 10, ownerId: 4, ownerBytes: 100
      ),
      MarkdownPreviewBudgetEntry(
        paneId: 2, lastUsed: 2, viewBytes: 10, ownerId: 4, ownerBytes: 60
      ),
    ]
    let full = markdownPreviewEvictions(entries, 120, 3)
    check full.victims.len == 0
    check full.retainedBytes == 120
    let evicted = markdownPreviewEvictions(entries, 80, 3)
    check evicted.victims == @[0, 1]
    check evicted.retainedBytes == 0
    var pinned = entries
    pinned[1].pinned = true
    let oversize = markdownPreviewEvictions(pinned, 80, 3)
    check oversize.victims == @[0]
    check oversize.retainedBytes == 110
    check oversize.overByteBudget

  test "pane limits evict only excess panes, independently of byte pressure":
    let entries = [
      MarkdownPreviewBudgetEntry(paneId: 1, lastUsed: 3),
      MarkdownPreviewBudgetEntry(paneId: 1, lastUsed: 2),
      MarkdownPreviewBudgetEntry(paneId: 1, lastUsed: 1),
      MarkdownPreviewBudgetEntry(paneId: 2, lastUsed: 0),
    ]
    let decision = markdownPreviewEvictions(entries, 1_000, 2)
    check decision.victims == @[2]
    check not decision.overPaneLimit

  test "mounted previews stay pinned even if they exceed both limits":
    let entries = [
      MarkdownPreviewBudgetEntry(paneId: 1, lastUsed: 0, pinned: true, ownerBytes: 150),
      MarkdownPreviewBudgetEntry(paneId: 1, lastUsed: 1, pinned: true, viewBytes: 5),
      MarkdownPreviewBudgetEntry(paneId: 2, lastUsed: 2, viewBytes: 10),
    ]
    let decision = markdownPreviewEvictions(entries, 100, 1)
    check decision.victims == @[2]
    check decision.retainedBytes == 155
    check decision.overByteBudget
    check decision.overPaneLimit

  test "equal recency is resolved by input order":
    let entries = [
      MarkdownPreviewBudgetEntry(paneId: 1, lastUsed: 7, viewBytes: 10),
      MarkdownPreviewBudgetEntry(paneId: 2, lastUsed: 7, viewBytes: 10),
      MarkdownPreviewBudgetEntry(paneId: 3, lastUsed: 7, viewBytes: 10),
    ]
    let decision = markdownPreviewEvictions(entries, 10, 3)
    check decision.victims == @[0, 1]
    check decision.retainedBytes == 10

  test "incomplete estimates are reported only for retained entries":
    let entries = [
      MarkdownPreviewBudgetEntry(
        paneId: 1, lastUsed: 1, viewBytes: 10, viewIncomplete: true
      ),
      MarkdownPreviewBudgetEntry(paneId: 1, lastUsed: 2, pinned: true, viewBytes: 10),
    ]
    check markdownPreviewEvictions(entries, 20, 3).incomplete
    let decision = markdownPreviewEvictions(entries, 10, 3)
    check decision.victims == @[0]
    check not decision.incomplete

  test "shared owner incompleteness remains until its last consumer leaves":
    let entries = [
      MarkdownPreviewBudgetEntry(
        paneId: 1,
        lastUsed: 1,
        viewBytes: 10,
        ownerId: 5,
        ownerBytes: 100,
        ownerIncomplete: true,
      ),
      MarkdownPreviewBudgetEntry(
        paneId: 2, lastUsed: 2, pinned: true, viewBytes: 10, ownerId: 5, ownerBytes: 100
      ),
    ]
    let decision = markdownPreviewEvictions(entries, 110, 3)
    check decision.victims == @[0]
    check decision.retainedBytes == 110
    check decision.incomplete
    let exclusive = [
      MarkdownPreviewBudgetEntry(
        paneId: 1, lastUsed: 1, viewBytes: 10, ownerBytes: 100, ownerIncomplete: true
      ),
      MarkdownPreviewBudgetEntry(paneId: 2, lastUsed: 2, pinned: true, viewBytes: 10),
    ]
    let evicted = markdownPreviewEvictions(exclusive, 10, 3)
    check evicted.victims == @[0]
    check not evicted.incomplete

  test "in-flight owners are pinned without consuming a pane slot":
    let pending = [
      MarkdownPreviewBudgetEntry(
        kind: mpbkPendingOwner, ownerId: 4, ownerBytes: 100, ownerIncomplete: true
      )
    ]
    let decision = markdownPreviewEvictions(pending, 50, 0)
    check decision.victims.len == 0
    check decision.retainedBytes == 100
    check decision.overByteBudget
    check not decision.overPaneLimit
    check decision.incomplete

  test "in-flight owner and visible consumer are charged only once":
    let entries = [
      MarkdownPreviewBudgetEntry(kind: mpbkPendingOwner, ownerId: 4, ownerBytes: 120),
      MarkdownPreviewBudgetEntry(
        paneId: 1, pinned: true, viewBytes: 10, ownerId: 4, ownerBytes: 100
      ),
      MarkdownPreviewBudgetEntry(paneId: 2, lastUsed: 1, viewBytes: 20),
    ]
    let decision = markdownPreviewEvictions(entries, 130, 1)
    check decision.victims == @[2]
    check decision.retainedBytes == 130
    check not decision.overPaneLimit
    check not decision.overByteBudget

  test "saved view state contributes bytes but is never a pane preview":
    let entries = [
      MarkdownPreviewBudgetEntry(
        kind: mpbkSavedState, paneId: 1, viewBytes: 60, viewIncomplete: true
      ),
      MarkdownPreviewBudgetEntry(paneId: 1, lastUsed: 1, viewBytes: 20),
    ]
    let decision = markdownPreviewEvictions(entries, 50, 0)
    check decision.victims == @[1]
    check decision.retainedBytes == 60
    check decision.overByteBudget
    check not decision.overPaneLimit
    check decision.incomplete

  test "retired layout payload stays pinned without consuming a preview slot":
    let entries = [
      MarkdownPreviewBudgetEntry(
        kind: mpbkRetiredView, viewBytes: 80, viewIncomplete: true
      ),
      MarkdownPreviewBudgetEntry(paneId: 1, viewBytes: 5),
    ]
    let decision = markdownPreviewEvictions(entries, 50, 0)
    check decision.victims == @[1]
    check decision.retainedBytes == 80
    check decision.overByteBudget
    check not decision.overPaneLimit
    check decision.incomplete

  test "zero limits and saturated costs remain finite and visible":
    let entries = [
      MarkdownPreviewBudgetEntry(paneId: 1, pinned: true, viewBytes: high(uint64)),
      MarkdownPreviewBudgetEntry(paneId: 2, pinned: true, ownerBytes: 1),
      MarkdownPreviewBudgetEntry(paneId: 3, viewBytes: 0),
    ]
    let decision = markdownPreviewEvictions(entries, high(uint64), 0)
    check decision.victims == @[2]
    check decision.retainedBytes == high(uint64)
    check decision.overByteBudget
    check decision.overPaneLimit
    let empty = markdownPreviewEvictions([], 0, 0)
    check empty.victims.len == 0
    check empty.retainedBytes == 0
    check not empty.overByteBudget
    check not empty.overPaneLimit
