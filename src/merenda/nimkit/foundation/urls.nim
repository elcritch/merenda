## URL values and media-type inference shared by NimKit platform services.
##
## `Url` is a small Foundation-style value type. Existing APIs may continue to
## accept strings, while URL-aware code can use one parser and one set of path,
## scheme, and content-type rules.

import std/[os, strutils, uri]

type Url* = object ## Parsed URL value that preserves its original spelling.
  xAbsoluteString: string
  xUri: Uri

proc initUrl*(value: string): Url =
  ## Parse `value` without requiring it to be absolute.
  ##
  ## Relative paths are valid URLs and can later be resolved with
  ## `localFilePath`.
  Url(xAbsoluteString: value, xUri: parseUri(value))

func absoluteString*(url: Url): string =
  ## Return the original URL string.
  url.xAbsoluteString

func `$`*(url: Url): string =
  ## Return the original URL string.
  url.xAbsoluteString

func isEmpty*(url: Url): bool =
  ## Return whether the URL has no source string.
  url.xAbsoluteString.len == 0

func scheme*(url: Url): string =
  ## Return the normalized URL scheme without a trailing colon.
  url.xUri.scheme.toLowerAscii()

func host*(url: Url): string =
  ## Return the URL hostname.
  url.xUri.hostname

func hasScheme*(url: Url): bool =
  ## Return whether the URL contains a scheme.
  url.xUri.scheme.len > 0

func isHttpUrl*(url: Url): bool =
  ## Return whether the URL uses HTTP or HTTPS and has a hostname.
  url.scheme() in ["http", "https"] and url.host().len > 0

func isFileUrl*(url: Url): bool =
  ## Return whether the URL is a file URL or a scheme-less local path.
  not url.hasScheme() or url.scheme() == "file"

proc decodedPath*(url: Url): string =
  ## Return the percent-decoded URL path without its query or fragment.
  decodeUrl(url.xUri.path, decodePlus = false)

proc localFilePath*(url: Url, basePath = ""): string =
  ## Resolve a file URL or scheme-less path to a local filesystem path.
  ##
  ## Relative paths require `basePath`. Non-file URL schemes return an empty
  ## string. A non-local file URL host is preserved as a UNC-style prefix.
  if not url.isFileUrl():
    return
  var path = url.decodedPath()
  if url.scheme() == "file" and url.host().len > 0 and
      url.host().toLowerAscii() != "localhost":
    path = "//" & url.host() & "/" & path.strip(chars = {'/'}, leading = true)
  when defined(windows):
    if path.len >= 3 and path[0] == '/' and path[1].isAlphaAscii and path[2] == ':':
      path = path[1 .. ^1]
  if path.len == 0 or path.isAbsolute:
    return path
  if basePath.len > 0:
    return basePath / path

func normalizedFileType*(fileType: string): string =
  ## Normalize a path extension or file type to lowercase without leading dots.
  result = fileType.strip().toLowerAscii()
  while result.len > 0 and result[0] == '.':
    result = result[1 .. ^1]

func pathExtension*(url: Url): string =
  ## Return the normalized extension of the URL path without a leading dot.
  splitFile(url.xUri.path).ext.normalizedFileType()

proc lastPathComponent*(url: Url): string =
  ## Return the decoded final component of the URL path.
  url.decodedPath().extractFilename()

func normalizedMediaType*(value: string): string =
  ## Normalize an HTTP media type and discard parameters such as `charset`.
  let parameterStart = value.find(';')
  result =
    if parameterStart < 0:
      value.strip().toLowerAscii()
    else:
      value[0 ..< parameterStart].strip().toLowerAscii()
  if result.count('/') != 1 or result.startsWith('/') or result.endsWith('/'):
    result.setLen(0)

func mediaTypeForFileExtension*(fileExtension: string): string =
  ## Return the standard media type for a common filename extension.
  case fileExtension.normalizedFileType()
  of "avif": "image/avif"
  of "bmp": "image/bmp"
  of "gif": "image/gif"
  of "ico": "image/x-icon"
  of "jpeg", "jpg": "image/jpeg"
  of "png": "image/png"
  of "svg": "image/svg+xml"
  of "tif", "tiff": "image/tiff"
  of "webp": "image/webp"
  of "aac": "audio/aac"
  of "flac": "audio/flac"
  of "m4a": "audio/mp4"
  of "mp3": "audio/mpeg"
  of "oga", "ogg": "audio/ogg"
  of "wav": "audio/wav"
  of "avi": "video/x-msvideo"
  of "m4v", "mp4": "video/mp4"
  of "mov": "video/quicktime"
  of "ogv": "video/ogg"
  of "webm": "video/webm"
  of "css": "text/css"
  of "csv": "text/csv"
  of "htm", "html": "text/html"
  of "md", "markdown": "text/markdown"
  of "txt": "text/plain"
  of "js", "mjs": "text/javascript"
  of "json": "application/json"
  of "pdf": "application/pdf"
  of "wasm": "application/wasm"
  of "xml": "application/xml"
  of "gz": "application/gzip"
  of "tar": "application/x-tar"
  of "zip": "application/zip"
  else: ""

func mediaType*(url: Url): string =
  ## Infer the URL resource's media type from its path extension.
  url.pathExtension().mediaTypeForFileExtension()

func isImageMediaType*(mediaType: string): bool =
  ## Return whether `mediaType` identifies image content.
  mediaType.normalizedMediaType().startsWith("image/")
