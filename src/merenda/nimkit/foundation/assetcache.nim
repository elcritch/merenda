## Installation of statically embedded ZIP resources into an application cache.

import std/[appdirs, os, paths, strutils, tempfiles]

import crunchy/[common, sha256]
import zippy/ziparchives

const NimKitAssetCacheDirectoryName* = "assets"

type
  EmbeddedZipAsset* = object ## One file stored in an embedded ZIP archive.
    fileName*: string
    archiveMember*: string
    archiveContents*: string
    contentSha256*: string

  EmbeddedAssetInstallState* = enum
    eaisFailed
    eaisReady

  EmbeddedAssetInstallResult* = object
    ## Result of installing one embedded asset into the cache.
    state*: EmbeddedAssetInstallState
    path*: string
    byteLength*: int64
    cacheHit*: bool
    errorMessage*: string

func validateFileName(fileName: string) =
  if fileName.len == 0:
    raise newException(ValueError, "embedded asset file name cannot be empty")
  if fileName in [".", ".."] or '/' in fileName or '\\' in fileName or '\0' in fileName:
    raise newException(ValueError, "embedded asset file name must be a base name")

func validateSha256(value: string) =
  if value.len != 64:
    raise newException(ValueError, "embedded asset SHA-256 must have 64 digits")
  for character in value:
    if character notin {'0' .. '9', 'a' .. 'f', 'A' .. 'F'}:
      raise newException(ValueError, "embedded asset SHA-256 must be hexadecimal")

func initEmbeddedZipAsset*(
    fileName, archiveContents, contentSha256: string, archiveMember = ""
): EmbeddedZipAsset =
  ## Describe one statically embedded ZIP member and its expected contents.
  fileName.validateFileName()
  contentSha256.validateSha256()
  if archiveContents.len == 0:
    raise newException(ValueError, "embedded ZIP archive cannot be empty")
  result = EmbeddedZipAsset(
    fileName: fileName,
    archiveMember: if archiveMember.len > 0: archiveMember else: fileName,
    archiveContents: archiveContents,
    contentSha256: contentSha256.toLowerAscii(),
  )

func succeeded*(installResult: EmbeddedAssetInstallResult): bool =
  ## Return whether the asset is ready for use at `installResult.path`.
  installResult.state == eaisReady

proc nimkitAssetCacheDirectory*(applicationIdentifier: string): string =
  ## Return the platform cache directory for one application's installed assets.
  if applicationIdentifier.strip().len == 0:
    raise newException(ValueError, "application identifier cannot be empty")
  $(
    appdirs.getCacheDir(Path(applicationIdentifier)) /
    Path(NimKitAssetCacheDirectoryName)
  )

func embeddedAssetCachePath(asset: EmbeddedZipAsset, cacheDirectory: string): string =
  cacheDirectory / (asset.contentSha256.toLowerAscii() & "-" & asset.fileName)

proc cachedAssetIsValid(path, expectedSha256: string): bool =
  if not fileExists(path):
    return
  try:
    result = sha256(readFile(path)).toHex().toLowerAscii() == expectedSha256
  except OSError:
    discard

proc removeFileIfPresent(path: string) =
  if path.len > 0 and fileExists(path):
    try:
      removeFile(path)
    except OSError:
      discard

proc installEmbeddedZipAsset*(
    asset: EmbeddedZipAsset, applicationIdentifier: string, cacheDirectory = ""
): EmbeddedAssetInstallResult =
  ## Extract and verify an embedded ZIP member in the application asset cache.
  ##
  ## The returned path is content-addressed by the expected SHA-256. Installation
  ## failures are reported in the result so applications can choose a fallback.
  var
    archivePath: string
    outputPath: string
    reader: ZipArchiveReader
  try:
    asset.fileName.validateFileName()
    asset.contentSha256.validateSha256()
    if asset.archiveContents.len == 0:
      raise newException(ValueError, "embedded ZIP archive cannot be empty")
    if asset.archiveMember.len == 0:
      raise newException(ValueError, "embedded ZIP member cannot be empty")

    let
      expectedSha256 = asset.contentSha256.toLowerAscii()
      resolvedCacheDirectory =
        if cacheDirectory.len > 0:
          cacheDirectory
        else:
          nimkitAssetCacheDirectory(applicationIdentifier)
      targetPath = asset.embeddedAssetCachePath(resolvedCacheDirectory)
    createDir(resolvedCacheDirectory)

    if targetPath.cachedAssetIsValid(expectedSha256):
      return EmbeddedAssetInstallResult(
        state: eaisReady,
        path: targetPath,
        byteLength: getFileSize(targetPath),
        cacheHit: true,
      )

    let archiveFile =
      createTempFile(".nimkit-embedded-", ".zip", resolvedCacheDirectory)
    archivePath = archiveFile.path
    archiveFile.cfile.close()
    writeFile(archivePath, asset.archiveContents)

    reader = openZipArchive(archivePath)
    let contents = reader.extractFile(asset.archiveMember)
    reader.close()
    reader = nil
    if sha256(contents).toHex().toLowerAscii() != expectedSha256:
      raise newException(ValueError, "embedded asset SHA-256 does not match")

    let outputFile =
      createTempFile(".nimkit-embedded-", ".part", resolvedCacheDirectory)
    outputPath = outputFile.path
    outputFile.cfile.close()
    writeFile(outputPath, contents)
    if fileExists(targetPath):
      removeFile(targetPath)
    moveFile(outputPath, targetPath)
    outputPath.setLen(0)

    result = EmbeddedAssetInstallResult(
      state: eaisReady, path: targetPath, byteLength: contents.len.int64
    )
  except CatchableError as error:
    result.errorMessage = error.msg
  finally:
    if not reader.isNil:
      try:
        reader.close()
      except OSError:
        discard
    archivePath.removeFileIfPresent()
    outputPath.removeFileIfPresent()
