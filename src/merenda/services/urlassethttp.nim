## Synchronous stdlib transport for the URL asset worker.

# HttpClient.get buffers the whole body and downloadFile uses an unbounded
# FileStream. Reuse the stdlib response parser with a size-limited stream.
include std/httpclient

import std/atomics
when defined(posix):
  import std/posix
import threading/smartptrs

const UrlAssetReadTimeoutMs = 3_000

type
  UrlAssetCancellation* = SharedPtr[Atomic[bool]]
  UrlAssetDownloadCancelled = object of IOError
  UrlAssetLimitExceeded = object of IOError

  UrlAssetHttpResponse* = object
    status*: int
    byteLength*: int64
    limitExceeded*: bool
    mediaType*: string

  BoundedAssetStream = ref object of StreamObj
    file: File
    length, maximumBytes: int
    cancellation: UrlAssetCancellation

proc checkCancelled*(cancellation: UrlAssetCancellation) =
  if cancellation[].load(moAcquire):
    raise newException(UrlAssetDownloadCancelled, "URL asset load was cancelled")

proc writeAssetData(stream: Stream, buffer: pointer, length: int) =
  let asset = BoundedAssetStream(stream)
  asset.cancellation.checkCancelled()
  if length > asset.maximumBytes - asset.length:
    raise newException(UrlAssetLimitExceeded, "URL asset exceeds its byte limit")
  if asset.file.writeBuffer(buffer, length) != length:
    raise newException(IOError, "Unable to write URL asset")
  asset.length += length

proc rewindAssetStream(stream: Stream, position: int) =
  # parseBody rewinds the stream after the write. The caller only needs its size.
  discard

proc setAssetReadTimeout(socket: Socket) =
  # recvFull and response headers use HttpClient.timeout. The stdlib chunk
  # parser reads chunk headers directly, so its socket needs a timeout too.
  when defined(windows):
    const WinsockReceiveTimeout = 0x1006 # SO_RCVTIMEO
    setSockOptInt(
      socket.getFd(), SOL_SOCKET, WinsockReceiveTimeout, UrlAssetReadTimeoutMs
    )
  elif defined(posix):
    var timeout = Timeval(tv_sec: posix.Time(UrlAssetReadTimeoutMs div 1000))
    if posix.setsockopt(
      socket.getFd(),
      posix.SOL_SOCKET,
      SO_RCVTIMEO,
      addr timeout,
      SockLen(sizeof(timeout)),
    ) != 0:
      raiseOSError(osLastError())

proc fetchUrlAsset*(
    url: Uri, path: string, maximumAssetBytes: int, cancellation: UrlAssetCancellation
): UrlAssetHttpResponse =
  when defined(ssl):
    if defaultSslContext.isNil:
      defaultSslContext = newContext(verifyMode = CVerifyPeerUseEnvVars)
  let client = newHttpClient(
    timeout = UrlAssetReadTimeoutMs, headers = newHttpHeaders({"Connection": "close"})
  )
  defer:
    client.close()
  # Only read the final response body. Redirects are handled by HttpClient.
  client.getBody = false
  let response = client.get(url)
  result.status = response.code.int
  result.mediaType = response.headers.getOrDefault("Content-Type")
  cancellation.checkCancelled()
  if result.status notin 200 .. 299:
    return

  let asset = BoundedAssetStream(
    file: open(path, fmWrite),
    maximumBytes: maximumAssetBytes,
    cancellation: cancellation,
    writeDataImpl: writeAssetData,
    setPositionImpl: rewindAssetStream,
  )
  defer:
    asset.file.close()
  if response.code != Http204:
    client.socket.setAssetReadTimeout()
    client.bodyStream = asset
    try:
      parseBody(client, response.headers, response.version)
    except UrlAssetLimitExceeded:
      result.limitExceeded = true
  result.byteLength = asset.length
