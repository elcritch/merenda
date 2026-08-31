import std/os

import merenda/nimkit

const SampleMarkdown =
  """
# NimKit Markdown

A lightweight Markdown viewer rendered with **native NimKit text**, without an HTML
engine or browser widget.

## What it handles

- Headings and paragraphs
- *Emphasis*, **strong text**, ~~strikethrough~~, and `inline code`
- [Clickable links](https://github.com/elcritch/merenda)
- Ordered and unordered lists
- Block quotes, fenced code, thematic breaks, images, and GFM tables

> Markdown is parsed into an AST and converted directly into NimKit attributed text.

```nim
let viewer = newMarkdownView("# Hello from Nim")
viewer.markdown = "## Updated document"
```

| Layer | Responsibility |
| --- | --- |
| markdown | Parse CommonMark or GFM |
| NimKit | Layout, selection, links, scrolling, and drawing |

---

Local images render natively when the viewer has a base path:

![NimKit sample](img1.png)
"""

let
  documentPath =
    if paramCount() > 0:
      absolutePath(paramStr(1))
    else:
      ""
  source =
    if documentPath.len > 0:
      readFile(documentPath)
    else:
      SampleMarkdown
  imageBasePath =
    if documentPath.len > 0:
      documentPath.parentDir
    else:
      currentSourcePath().parentDir.parentDir / "data"
  app = sharedApplication()
  window = newWindow("NimKit Markdown Viewer", frame = rect(120, 80, 820, 700))
  root = newView()
  viewer = newMarkdownView(source, imageBasePath = imageBasePath)

root.addSubview(viewer)
viewer.pinEdges(toGuide = root.contentLayoutGuide(insets(20.0)))

app.runWindow(window, root, viewer)
