import std/[os, strutils, tables, tempfiles, unittest]

import crunchy/[common, sha256]
import merenda/nimkit
import zippy/ziparchives

suite "nimkit embedded asset cache":
  test "local and embedded ZIPs share a content-addressed cache file":
    let root = createTempDir("merenda-local-zip-", "")
    defer:
      removeDir(root)
    let contents = "shared asset contents"
    var entries = {"fixture.txt": contents}.toTable()
    let archive = createZipArchive(entries)
    let archivePath = root / "fixture.txt.zip"
    writeFile(archivePath, archive)
    let local = installZipAssetFile(archivePath, "nimkit-tests", root / "cache")
    require local.succeeded()
    let embedded = installEmbeddedZipAsset(
      initEmbeddedZipAsset("fixture.txt", archive, sha256(contents).toHex()),
      "nimkit-tests",
      root / "cache",
    )
    check embedded.succeeded()
    check embedded.cacheHit
    check embedded.path == local.path
    check readFile(local.path) == contents
    writeFile(archivePath, "corrupt ZIP")
    check not installZipAssetFile(archivePath, "nimkit-tests", root / "cache").succeeded()

  test "installs and reuses a verified ZIP member":
    let
      root = createTempDir("merenda-embedded-assets-", "")
      contents = "embedded asset contents"
      digest = sha256(contents).toHex()
    defer:
      removeDir(root)
    var entries = {"fixture.txt": contents}.toTable()
    let asset = initEmbeddedZipAsset("fixture.txt", createZipArchive(entries), digest)

    let installed = installEmbeddedZipAsset(asset, "nimkit-tests", root)
    check installed.succeeded()
    check not installed.cacheHit
    check installed.byteLength == contents.len.int64
    check readFile(installed.path) == contents

    writeFile(installed.path, "corrupt")
    let repaired = installEmbeddedZipAsset(asset, "nimkit-tests", root)
    check repaired.succeeded()
    check not repaired.cacheHit
    check readFile(repaired.path) == contents

    let cached = installEmbeddedZipAsset(asset, "nimkit-tests", root)
    check cached.succeeded()
    check cached.cacheHit
    check cached.path == installed.path

  test "rejects corrupt archive contents without leaving an asset":
    let
      root = createTempDir("merenda-corrupt-assets-", "")
      asset = initEmbeddedZipAsset(
        "fixture.txt", "not a ZIP archive", sha256("expected").toHex()
      )
    defer:
      removeDir(root)

    let installed = installEmbeddedZipAsset(asset, "nimkit-tests", root)
    check not installed.succeeded()
    check installed.path.len == 0
    check installed.errorMessage.len > 0
    var cachedFiles = 0
    for kind, path in walkDir(root):
      discard path
      if kind == pcFile:
        inc cachedFiles
    check cachedFiles == 0

  test "rejects members larger than the configured trusted-resource limit":
    let
      root = createTempDir("merenda-oversized-assets-", "")
      contents = "too large"
    defer:
      removeDir(root)
    var entries = {"fixture.txt": contents}.toTable()
    let asset = initEmbeddedZipAsset(
      "fixture.txt",
      createZipArchive(entries),
      sha256(contents).toHex(),
      maximumContentBytes = 3,
    )

    let installed = installEmbeddedZipAsset(asset, "nimkit-tests", root)
    check not installed.succeeded()
    check installed.errorMessage.contains("size limit")

  test "revalidates public asset descriptors before installing":
    let
      root = createTempDir("merenda-invalid-assets-", "")
      contents = "embedded asset contents"
    defer:
      removeDir(root)
    var entries = {"fixture.txt": contents}.toTable()
    var asset = initEmbeddedZipAsset(
      "fixture.txt", createZipArchive(entries), sha256(contents).toHex()
    )
    asset.maximumContentBytes = 0

    let installed = installEmbeddedZipAsset(asset, "nimkit-tests", root)
    check not installed.succeeded()
    check installed.errorMessage.contains("positive")
