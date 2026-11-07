## Compare three rendered Kosmo Markdown previews with and without cache eviction.
## Build the baseline without -d:previewBudget, and the changed tree with it.
## Pass "pause" to hold the active frontend at the flushed checkpoint for profiling.
import std/[json, monotimes, os, strutils, tables, tempfiles, times]
import merenda/nimkit
import merenda/nimkit/app/diagnostics
import merenda/kosmo/kosmo
import merenda/kosmo/vscodegrammars

when defined(macosx):
  {.
    emit: """
#include <malloc/malloc.h>
#include <mach/mach.h>
static size_t markdown_key_heap_bytes(void) {
  vm_address_t *zones = NULL;
  unsigned count = 0;
  if (malloc_get_all_zones(mach_task_self(), NULL, &zones, &count) != KERN_SUCCESS)
    return 0;
  size_t total = 0;
  for (unsigned i = 0; i < count; ++i) {
    malloc_statistics_t stats;
    malloc_zone_statistics((malloc_zone_t *)zones[i], &stats);
    total += stats.size_in_use;
  }
  return total;
}
"""
  .}
  proc heapBytes(): int {.importc: "markdown_key_heap_bytes", nodecl.}
else:
  proc heapBytes(): int =
    getOccupiedMem()

proc installProfileGrammar() =
  let
    path = "syntaxes/profile.tmLanguage.json"
    grammar =
      """{"scopeName":"source.profile-sql","patterns":[{"name":"keyword.control.sql","match":"SELECT"}]}"""
    candidate = VscodeGrammarCandidate(
      id: "profile.sql",
      name: "Profile SQL",
      extensionFolder: "profile-sql",
      languageId: "sql",
      scopeName: "source.profile-sql",
      rootPath: path,
      sourceCommit: "0123456789abcdef0123456789abcdef01234567",
      extensions: @[".sql"],
      grammarFiles: @[
        VscodeGrammarFile(
          path: path, scopeName: "source.profile-sql", languageId: "sql"
        )
      ],
    )
  discard installVscodeGrammar(
    candidate, {path: grammar}.toTable, defaultKosmoVscodeGrammarDirectory()
  )

proc tableDocument(index: int): string =
  result =
    "# Document " & $index & "\n\n| Name | Description | Value |\n| --- | --- | --- |\n"
  for row in 0 ..< 500:
    result.add "| row " & $row & " | A representative table entry | " & $index & " |\n"
  result.add "\n```sql\nSELECT value FROM records;\n```\n"

proc main() =
  let
    root = createTempDir("kosmo-preview-profile-", "")
    oldConfig = getEnv("XDG_CONFIG_HOME")
    hadConfig = existsEnv("XDG_CONFIG_HOME")
  putEnv("XDG_CONFIG_HOME", root)
  installProfileGrammar()
  let frontend = newKosmoApplication(
    newApplication("Markdown preview profile"), monitorsGitStatus = false
  )
  defer:
    frontend.close()
    for index in 0 ..< 3:
      removeFile(root / ("document-" & $index & ".md"))
    if hadConfig:
      putEnv("XDG_CONFIG_HOME", oldConfig)
    else:
      delEnv("XDG_CONFIG_HOME")
    removeDir(root)
  doAssert frontend.editorView.editor.viewerGrammarSources().len > 0
  frontend.window.setContentView(frontend.contentView)
  frontend.contentView.frame = rect(0, 0, 1000, 700)
  frontend.contentView.layoutSubtreeIfNeeded()
  var
    sourceBytes = 0
    originalViews: array[3, uint]
  for index in 0 ..< 3:
    let
      path = root / ("document-" & $index & ".md")
      source = tableDocument(index)
    sourceBytes += source.len
    writeFile(path, source)
    doAssert frontend.openPath(path)
    let view = frontend.editorPane.markdownView
    originalViews[index] = cast[uint](view)
    doAssert view.waitForMarkdownParsing(60_000)
    doAssert view.waitForMarkdownLayout(60_000)
  # Verify the baseline retained all three views without keeping references to them.
  for index in 0 ..< 3:
    doAssert frontend.documentTabs.selectDocumentTabAtIndex(index)
    let view = frontend.editorPane.markdownView
    doAssert cast[uint](view) == originalViews[index]
    doAssert view.waitForMarkdownParsing(60_000)
    doAssert view.waitForMarkdownLayout(60_000)
  let active = frontend.editorPane.markdownView
  when defined(previewBudget):
    frontend.markdownPreviewByteBudget = 0
    let deadline = getMonoTime() + initDuration(seconds = 60)
    while frontend.isMarkdownPreviewWorkPending() and getMonoTime() < deadline:
      discard active.pollMarkdownParsing()
      active.layoutSubtreeIfNeeded()
      sleep(1)
    doAssert not frontend.isMarkdownPreviewWorkPending(), "preview work did not settle"
    doAssert frontend.editorPane.markdownPreviewCount() == 1,
      "budget did not retain exactly one active preview"
  block:
    let rendered = active.textStorage().stringValue()
    doAssert "Document 2" in rendered
  let usage = processResourceUsage()
  echo $(
    %*{
      "stage": "previewCacheSettled",
      "variant": (when defined(previewBudget): "evicted" else: "baseline"),
      "documents": 3,
      "retainedPreviews": (
        when defined(previewBudget): frontend.editorPane.markdownPreviewCount()
        else: 3
      ),
      "rowsPerDocument": 500,
      "sourceBytes": sourceBytes,
      "activeRunes": active.textStorage().len(),
      "heapBytes": heapBytes(),
      "rssBytes": usage.residentBytes,
      "peakRssBytes": usage.peakResidentBytes,
    }
  )
  stdout.flushFile()
  if paramCount() > 0 and paramStr(1) == "pause":
    discard stdin.readLine()
  doAssert frontend.editorPane.markdownView == active

when isMainModule:
  main()
