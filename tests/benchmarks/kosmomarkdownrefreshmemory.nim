## Capture repeated unchanged preview refreshes using capture_allocations.py's
## stdin checkpoint protocol. Build the same source in both checkouts.
import std/[os, strutils, tempfiles]
import merenda/nimkit
import merenda/kosmo/kosmo

let root = createTempDir("merenda-preview-profile-", "")
let path = root / "large.md"
# A large whitespace-only tail keeps layout small while the source buffer remains
# large enough to expose whole-document extraction on every refresh.
let source = "# Preview\n\nA short rendered paragraph.\n\n" & " ".repeat(225_000)
writeFile(path, source)
let frontend =
  newKosmoApplication(newApplication("Preview profile"), monitorsGitStatus = false)
frontend.window.setContentView(frontend.contentView)
frontend.contentView.frame = rect(0, 0, 800, 600)
frontend.contentView.layoutSubtreeIfNeeded()
doAssert frontend.openPath(path)
let preview = frontend.editorPane.markdownView
doAssert preview.waitForMarkdownParsing(60_000)
let refreshes =
  if paramCount() > 0:
    parseInt(paramStr(1))
  else:
    20
for i in 0 ..< refreshes:
  frontend.editorView.refresh()
  doAssert not preview.isMarkdownParsing()
echo "preview checkpoint sourceBytes=", source.len, " refreshes=", refreshes
stdout.flushFile()
discard stdin.readLine()
doAssert frontend.editorPane.markdownView == preview and source.len > 0
frontend.close()
removeFile(path)
removeDir(root)
