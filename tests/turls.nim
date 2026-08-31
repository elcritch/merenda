import std/unittest

import merenda/nimkit/app/documents
import merenda/nimkit/app/panels
import merenda/nimkit/app/pasteboards
import merenda/nimkit/foundation/urls
import merenda/nimkit/text/texttypes
import merenda/nimkit/text/textviews

suite "Foundation URLs":
  test "parses HTTP URLs and infers media types from their paths":
    let url = initUrl("HTTPS://example.com/a%20folder/photo.JPEG?size=2#preview")

    check url.absoluteString() ==
      "HTTPS://example.com/a%20folder/photo.JPEG?size=2#preview"
    check url.scheme() == "https"
    check url.host() == "example.com"
    check url.isHttpUrl()
    check not url.isFileUrl()
    check url.decodedPath() == "/a folder/photo.JPEG"
    check url.lastPathComponent() == "photo.JPEG"
    check url.pathExtension() == "jpeg"
    check url.mediaType() == "image/jpeg"

  test "resolves file URLs and relative paths":
    check initUrl("images/icon%202.png?scale=2").localFilePath("/tmp/assets") ==
      "/tmp/assets/images/icon 2.png"
    check initUrl("file:///tmp/icon%202.png").localFilePath() == "/tmp/icon 2.png"
    check initUrl("https://example.com/icon.png").localFilePath("/tmp") == ""

  test "normalizes media types and recognizes common content":
    check normalizedMediaType(" Image/PNG; charset=binary ") == "image/png"
    check normalizedMediaType("not-a-media-type") == ""
    check mediaTypeForFileExtension(".SVG") == "image/svg+xml"
    check mediaTypeForFileExtension("json") == "application/json"
    check isImageMediaType("IMAGE/WEBP; quality=1")
    check not isImageMediaType("application/octet-stream")

  test "bridges parsed URLs through Cocoa-style pasteboard handlers":
    let
      pasteboard = newPasteboard("urls-test")
      url = initUrl("https://example.com/image.png")

    check pasteboard.setUrl(PasteboardTypeUrl, url)
    check pasteboard.urlForType(PasteboardTypeUrl) == url.absoluteString()
    check pasteboard.urlValueForType(PasteboardTypeUrl) == url

  test "bridges document, panel, and attachment URL handlers":
    let
      url = initUrl("file:///tmp/example%20image.PNG")
      document = newDocument(url)
      panel = newOpenPanel()
      attachment = initTextAttachment(fileUrl = url.absoluteString())

    check document.fileUrlValue() == url
    check document.fileName() == "example image.PNG"
    check document.fileType() == "png"
    panel.selectUrl(url)
    check panel.selectedUrlValue() == url
    check attachment.fileUrlValue() == url
    check attachment.isImageAttachment()
