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

Images are represented by linked alt text until an application supplies its own image
loading policy: ![NimKit logo](nimkit.png)
"""

let
  source =
    if paramCount() > 0:
      readFile(paramStr(1))
    else:
      SampleMarkdown
  app = sharedApplication()
  window = newWindow("NimKit Markdown Viewer", frame = rect(120, 80, 820, 700))
  root = newView()
  viewer = newMarkdownView(source)

root.addSubview(viewer)
viewer.pinEdges(toGuide = root.contentLayoutGuide(insets(20.0)))

app.runWindow(window, root, viewer)
