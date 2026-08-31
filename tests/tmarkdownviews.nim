import std/[monotimes, os, strformat, strutils, times, unicode, unittest]

import figdraw

import merenda/nimkit

const
  RepositoryRoot = currentSourcePath().parentDir.parentDir
  RepositoryReadme = RepositoryRoot / "README.md"
  TestImagePath = RepositoryRoot / "data" / "img1.png"

proc runeIndexOf(text, needle: string): int =
  let
    total = text.runeLen
    length = needle.runeLen
  if length == 0:
    return 0
  if length > total:
    return -1
  for index in 0 .. total - length:
    if text.runeSubStr(index, length) == needle:
      return index
  -1

proc attributesFor(storage: TextStorage, needle: string): TextAttributes =
  let index = storage.stringValue().runeIndexOf(needle)
  doAssert index >= 0, "rendered Markdown should contain: " & needle
  storage.attributesAt(index)

suite "nimkit markdown views":
  test "ATX and setext headings use every configured heading level":
    let
      style = initMarkdownStyle()
      storage = markdownTextStorage(
        """
# ATX one
## ATX two
### ATX three
#### ATX four
##### ATX five
###### ATX six

Setext one
==========

Setext two
----------
"""
      )
      rendered = storage.stringValue()

    for level in 1 .. 6:
      let attributes = storage.attributesFor(
        "ATX " & ["one", "two", "three", "four", "five", "six"][level - 1]
      )
      check attributes.fontSize == style.headingFontSizes[level - 1]
      check attributes.foregroundColor == style.headingColor
    check storage.attributesFor("Setext one").fontSize == style.headingFontSizes[0]
    check storage.attributesFor("Setext two").fontSize == style.headingFontSizes[1]
    check rendered.contains("ATX one\n\nATX two")

  test "paragraphs, soft breaks, hard breaks, escapes, and entities render as text":
    let
      source =
        "first line\nsoft continuation" & "  \n" &
        "hard continuation\\\nbackslash continuation\n\n" &
        "Escaped \\*stars\\* &amp; &copy; &#169;."
      storage = markdownTextStorage(source)
      rendered = storage.stringValue()

    check rendered.contains(
      "first line\nsoft continuation\nhard continuation\nbackslash continuation"
    )
    check rendered.contains("\n\nEscaped *stars* & © ©.")

  test "emphasis, strong text, nested emphasis, code, and strikethrough are attributed":
    let
      style = initMarkdownStyle()
      storage = markdownTextStorage(
        "Plain *emphasis*, **strong**, ***both***, `code`, and ~~removed~~."
      )
      rendered = storage.stringValue()
      emphasis = storage.attributesFor("emphasis")
      strong = storage.attributesFor("strong")
      both = storage.attributesFor("both")

    check rendered == "Plain emphasis, strong, both, code, and removed."
    check emphasis.foregroundColor == style.emphasisColor
    check emphasis.fontName == style.emphasisFontName
    check strong.foregroundColor == style.strongColor
    check strong.fontName == style.emphasisFontName
    check strong.fontSize == style.bodyFontSize
    check both.fontName == style.emphasisFontName
    check both.fontSize == style.bodyFontSize
    check storage.attributesFor("code").fontName == style.codeFontName
    check storage.attributesFor("removed").hasStrikethrough()

  test "inline, reference, URI, and email links retain native link metadata":
    let storage = markdownTextStorage(
      """
[inline](https://example.test/inline "Inline")

<https://example.test/auto> and <reader@example.test>

[reference][guide]

[guide]: https://example.test/reference "Guide"
"""
    )
    let rendered = storage.stringValue()

    check rendered ==
      "inline\n\nhttps://example.test/auto and reader@example.test\n\nreference"
    check storage.attributesFor("inline").link == "https://example.test/inline"
    check storage.attributesFor("inline").underlineStyle == tldsSingle
    check storage.attributesFor("https://example.test/auto").link ==
      "https://example.test/auto"
    check storage.attributesFor("reader@example.test").link ==
      "mailto:reader@example.test"
    check storage.attributesFor("reference").link == "https://example.test/reference"

  test "inline and reference images render linked, styled alt text":
    let
      style = initMarkdownStyle()
      storage = markdownTextStorage(
        """
![Inline *alt*](assets/image.png "Preview")

![Reference image][logo]

[logo]: https://example.test/logo.webp "Logo"
"""
      )
      rendered = storage.stringValue()
      inline = storage.attributesFor("Inline")
      reference = storage.attributesFor("Reference image")

    check rendered == "▧ Inline alt\n\n▧ Reference image"
    check inline.link == "assets/image.png"
    check reference.link == "https://example.test/logo.webp"
    check storage.attributesFor("▧").foregroundColor == style.linkColor
    check reference.foregroundColor == style.linkColor

  test "local Markdown images render as native image attachments":
    var style = initMarkdownStyle()
    style.maximumImageSize = initSize(60.0'f32, 40.0'f32)
    let
      view = newMarkdownView(
        "![Image preview](img1.png \"Preview title\")\n\n> ![Quoted](img1.png)",
        frame = rect(0, 0, 320, 240),
        style = style,
        imageBasePath = TestImagePath.parentDir,
      )
      storage = view.textStorage()
      renders = buildRenders(view)

    var attachments: seq[TextAttachment]
    for run in storage.runs:
      if run.attributes.hasAttachment:
        attachments.add run.attributes.attachment
    require attachments.len == 2
    let attachment = attachments[0]
    check attachment.identifier == "markdown-image:img1.png"
    check attachment.contentType == "image/png"
    check attachment.fileName == "img1.png"
    check attachment.fileUrl == "img1.png"
    check attachment.size == initSize(40.0'f32, 40.0'f32)
    check attachment.metadata ==
      @[
        TextMetadataItem(key: "alt", value: "Image preview"),
        TextMetadataItem(key: "title", value: "Preview title"),
      ]
    require DefaultDrawLevel in renders

    var imageCount = 0
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkImage:
        inc imageCount
        check node.screenBox.w == 40.0'f32
        check node.screenBox.h == 40.0'f32
    check imageCount == 2

  test "custom image loaders are cached across Markdown style changes":
    let image = newImageResourceFromFile(TestImagePath)
    var requestedUrls: seq[string]
    let loader: MarkdownImageLoader = proc(url: string): ImageResource =
      requestedUrls.add url
      if url == "asset:logo": image else: nil
    let view = newMarkdownView(
      "![Generated logo](asset:logo)",
      frame = rect(0, 0, 320, 180),
      imageLoader = loader,
    )

    discard buildRenders(view)
    var style = view.markdownStyle
    style.bodyFontSize += 1.0'f32
    view.markdownStyle = style
    discard buildRenders(view)

    check requestedUrls == @["asset:logo"]
    check view.textView().attachmentPresentations().len == 1

  test "unordered, ordered, nested, and multi-block lists retain their structure":
    let storage = markdownTextStorage(
      """
- first
  - nested one
  - nested two
- last

3. third
4. fourth

- paragraph one

  paragraph two
"""
    )
    let rendered = storage.stringValue()

    check rendered.contains("• first\n  • nested one\n  • nested two\n• last")
    check rendered.contains("3. third\n4. fourth")
    check rendered.contains("• paragraph one\n  paragraph two")

  test "block quotes prefix every line and thematic breaks use the configured rule":
    let
      style = initMarkdownStyle()
      storage = markdownTextStorage(
        """
> first line
> second line
>
> second paragraph

---
"""
      )
      rendered = storage.stringValue()

    check rendered.startsWith(
      "│ first line\n│ second line\n│ \n│ second paragraph"
    )
    check rendered.endsWith(style.thematicBreak)
    check storage.attributesFor("first line").foregroundColor == style.quoteColor
    check storage.attributesFor("│").foregroundColor == style.ruleColor

  test "inline, fenced, and indented code use the monospace presentation":
    let
      style = initMarkdownStyle()
      storage = markdownTextStorage(
        """
Use `inline()` here.

```nim
echo "fenced"
```

    echo "indented"
"""
      )
      rendered = storage.stringValue()

    check rendered.contains("Use inline() here.")
    check rendered.contains("[nim]\necho \"fenced\"")
    check rendered.contains("echo \"indented\"")
    check storage.attributesFor("inline()").fontName == style.codeFontName
    check storage.attributesFor("echo \"fenced\"").fontName == style.codeFontName
    check storage.attributesFor("echo \"indented\"").fontName == style.codeFontName
    check storage.attributesFor("[nim]").foregroundColor == style.mutedColor

  test "fenced and indented code blocks render outlined background panels":
    var style = initMarkdownStyle()
    style.codeBlockStyle = MarkdownBlockStyle(
      backgroundColor: color(0.14, 0.22, 0.32, 0.94),
      outlineColor: color(0.52, 0.66, 0.82, 1.0),
      outlineWidth: 2.0'f32,
      cornerRadius: 9.0'f32,
      padding: insets(7.0'f32, 10.0'f32),
    )
    let
      source =
        """
Before `inline`.

```nim
echo "fenced"
```

    echo "indented"
"""
      view = newMarkdownView(source, frame = rect(0, 0, 520, 320), style = style)
      storage = view.textStorage()
      renders = buildRenders(view)

    check storage.attributesFor("inline").backgroundColor.a == 0.0'f32
    check storage.attributesFor("echo \"fenced\"").backgroundColor ==
      style.codeBlockStyle.backgroundColor
    check storage.attributesFor("echo \"indented\"").backgroundColor ==
      style.codeBlockStyle.backgroundColor
    require DefaultDrawLevel in renders

    var panelCount = 0
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == style.codeBlockStyle.backgroundColor.rgba:
        inc panelCount
        check node.stroke.weight == style.codeBlockStyle.outlineWidth
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == style.codeBlockStyle.outlineColor.rgba
        check node.corners[dcTopLeft] == 9'u16
        check node.screenBox.w > 20.0'f32
        check node.screenBox.h > 20.0'f32
    check panelCount == 2

  test "raw inline and block HTML remain inert and visibly muted":
    let
      style = initMarkdownStyle()
      storage = markdownTextStorage(
        """
Press <kbd>Enter</kbd>.

<section>literal block</section>
"""
      )
      rendered = storage.stringValue()

    check rendered == "Press <kbd>Enter</kbd>.\n\n<section>literal block</section>"
    check storage.attributesFor("<kbd>").foregroundColor == style.mutedColor
    check storage.attributesFor("<kbd>").fontName == style.codeFontName
    check storage.attributesFor("<section>").foregroundColor == style.mutedColor

  test "GFM tables render headers, body cells, escaped pipes, and inline styles":
    let
      style = initMarkdownStyle()
      storage = markdownTextStorage(
        """
| Left | Center | Right |
| :--- | :----: | ----: |
| **bold** | `code` | [link](https://example.test) |
| a \| pipe | middle | tail |
"""
      )
      rendered = storage.stringValue()
      header = storage.attributesFor("Left")
      bold = storage.attributesFor("bold")

    check rendered.contains("Left  │  Center  │  Right")
    check rendered.contains("bold  │  code  │  link")
    check rendered.contains("a | pipe  │  middle  │  tail")
    check header.fontName == style.codeFontName
    check header.foregroundColor == style.headingColor
    check header.underlineStyle == tldsSingle
    check bold.fontName == style.emphasisCodeFontName
    check bold.foregroundColor == style.strongColor
    check storage.attributesFor("code").fontName == style.codeFontName
    check storage.attributesFor("link").link == "https://example.test"
    check storage.attributesFor("│").foregroundColor == style.ruleColor

  test "CommonMark and GFM configurations select their extension syntax":
    let
      commonMark = initMarkdownParserConfig(mddCommonMark)
      gfm = initMarkdownParserConfig(mddGitHub)
      source = "~~removed~~\n\n| A | B |\n| - | - |\n| 1 | 2 |"
      commonStorage = markdownTextStorage(source, config = commonMark)
      gfmStorage = markdownTextStorage(source, config = gfm)

    check commonStorage.stringValue().contains("~~removed~~")
    check commonStorage.stringValue().contains("| A | B |")
    check not gfmStorage.stringValue().contains("~~removed~~")
    check gfmStorage.stringValue().contains("A  │  B")

  test "empty and Unicode documents produce valid native text storage":
    let
      style = initMarkdownStyle()
      empty = markdownTextStorage("")
      unicode =
        markdownTextStorage("# Καλημέρα 🌍\n\nПривет **мир**")

    check empty.stringValue() == ""
    check empty.len == 0
    check unicode.stringValue() == "Καλημέρα 🌍\n\nПривет мир"
    check unicode.attributesFor("мир").fontName == style.emphasisFontName

  test "markdown view is reusable, read-only, selectable, and styleable":
    let view = newMarkdownView("# First", frame = rect(0, 0, 480, 320))

    check view.markdown == "# First"
    check not view.editable
    check view.selectable
    check view.richText
    check not view.allowsUndo
    check view.textStorage().stringValue() == "First"
    check view.scrollView().borderType == svbNoBorder

    view.markdown = "## Second"
    check view.markdown == "## Second"
    check view.textStorage().stringValue() == "Second"

    var style = view.markdownStyle
    style.documentInsets = insets(12.0)
    style.headingColor = color(0.8, 0.2, 0.3, 1.0)
    view.markdownStyle = style

    check view.textInsets == insets(12.0)
    check view.textStorage().attributesAt(0).foregroundColor == style.headingColor

    view.markdownConfig = initMarkdownParserConfig(mddCommonMark)
    view.markdown = "~~literal~~"
    check view.textStorage().stringValue() == "~~literal~~"

  test "repository README renders and responds to clicks within an interactive budget":
    let
      source = readFile(RepositoryReadme)
      constructionStarted = getMonoTime()
      view = newMarkdownView(source, frame = rect(0, 0, 760, 540))
      constructionElapsed = getMonoTime() - constructionStarted
      renderingStarted = getMonoTime()
    discard buildRenders(view)
    let
      renderingElapsed = getMonoTime() - renderingStarted
      textView = view.textView()
      snapshot = textView.layoutManager().layoutSnapshot()
      firstLine = snapshot.lineFragments[0].fragmentRect
      clickPoint = initPoint(
        firstLine.origin.x + 8.0'f32,
        firstLine.origin.y + firstLine.size.height * 0.5'f32,
      )
      clickStarted = getMonoTime()
    check textView.mouseDown(MouseEvent(location: clickPoint, button: mbPrimary))
    check textView.mouseUp(MouseEvent(location: clickPoint, button: mbPrimary))
    let
      clickElapsed = getMonoTime() - clickStarted
      styleStarted = getMonoTime()
    var darkStyle = view.markdownStyle
    darkStyle.backgroundColor = color(0.055, 0.065, 0.085, 1.0)
    darkStyle.textColor = color(0.84, 0.86, 0.90, 1.0)
    darkStyle.headingColor = color(0.96, 0.97, 0.99, 1.0)
    darkStyle.codeBlockStyle.backgroundColor = color(0.08, 0.10, 0.14, 1.0)
    view.markdownStyle = darkStyle
    discard buildRenders(view)
    let styleElapsed = getMonoTime() - styleStarted

    echo &"README MarkdownView timing: construct " &
      &"{constructionElapsed.inMilliseconds} ms, render " &
      &"{renderingElapsed.inMilliseconds} ms, click " &
      &"{clickElapsed.inMilliseconds} ms, restyle and render " &
      &"{styleElapsed.inMilliseconds} ms"
    check source.len > 20_000
    check snapshot.lineFragments.len > 100
    check constructionElapsed < initDuration(seconds = 5)
    check renderingElapsed < initDuration(seconds = 5)
    check clickElapsed < initDuration(seconds = 1)
    check styleElapsed < initDuration(seconds = 1)
