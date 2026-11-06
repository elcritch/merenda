## VS Code TextMate grammar discovery metadata and safe local installation.
import std/[json, os, strutils, tables, tempfiles, unittest]

import zippy/ziparchives
import merenda/kosmo/vscodegrammars
import merenda/nimkit/foundation/textsearch

const
  FixtureCommit = "0123456789abcdef0123456789abcdef01234567"
  FixtureGrammarPath = "syntaxes/toy.tmLanguage.json"
  FixtureGrammar = """{"scopeName":"source.toy","patterns":[]}"""

proc fixtureTree(): VscodeGrammarTree =
  let content = %*{
    "sha": FixtureCommit,
    "truncated": false,
    "tree": [
      {"path": "extensions/toy/package.json", "type": "blob"},
      {"path": "extensions/toy/" & FixtureGrammarPath, "type": "blob"},
      {"path": "extensions/no-grammar/package.json", "type": "blob"},
    ],
  }
  parseVscodeGrammarTree(content.pretty())

proc fixtureCandidate(): VscodeGrammarCandidate =
  let manifest = %*{
    "contributes": {
      "languages": [
        {
          "id": "toy",
          "aliases": ["Toy Language"],
          "extensions": [".toy", ".toy.src"],
          "filenames": ["Toyfile"],
        }
      ],
      "grammars": [
        {
          "language": "toy",
          "scopeName": "source.toy",
          "path": "./" & FixtureGrammarPath,
        }
      ],
    }
  }
  let candidates =
    parseVscodeGrammarManifest("toy", FixtureCommit, manifest.pretty(), fixtureTree())
  doAssert candidates.len == 1
  candidates[0]

suite "Kosmo VS Code TextMate grammars":
  test "Reni searches grammar metadata and empty registry queries do not fetch":
    let candidate = fixtureCandidate()
    check candidate.matchesVscodeGrammarQuery(
      r"(?<=source\.)toy$", regularExpression = true
    )
    check candidate.matchesVscodeGrammarQuery(
      r"^\.toy(\.src)?$", regularExpression = true
    )
    check candidate.matchesVscodeGrammarQuery(r"^TOYFILE$", regularExpression = true)
    check not candidate.matchesVscodeGrammarQuery(r"^rust$", regularExpression = true)
    check not candidate.matchesVscodeGrammarQuery("", regularExpression = true)
    expect TextSearchError:
      discard candidate.matchesVscodeGrammarQuery("[", regularExpression = true)
    let catalog = newKosmoVscodeGrammarCatalog()
    defer:
      catalog.close()
    catalog.search(" ")
    check catalog.status().startsWith("Enter at least two characters")
    check not catalog.isBusy()
    check catalog.candidates().len == 0

  test "indexes only grammar extensions and searches names, IDs, scopes, and suffixes":
    let tree = fixtureTree()
    check tree.sha == FixtureCommit
    check tree.extensionFolders == @["toy"]

    let candidate = fixtureCandidate()
    check candidate.name == "Toy Language"
    check candidate.scopeName == "source.toy"
    check candidate.rootPath == FixtureGrammarPath
    check candidate.extensions == @[".toy", ".toy.src"]
    check candidate.fileNames == @["Toyfile"]
    check candidate.matchesVscodeGrammarQuery("toy language")
    check candidate.matchesVscodeGrammarQuery(".toy")
    check candidate.matchesVscodeGrammarQuery("source.toy")
    check not candidate.matchesVscodeGrammarQuery("rust")

  test "validates, atomically installs, and reloads parsed grammar files":
    let
      candidate = fixtureCandidate()
      root = createTempDir("kosmo-vscode-grammars-", "")
      grammarDirectory = root / "config" / "grammars"
    defer:
      removeDir(root)

    var contents = initTable[string, string]()
    contents[FixtureGrammarPath] = FixtureGrammar
    candidate.validateVscodeGrammarFiles(contents)
    let installedPath = installVscodeGrammar(candidate, contents, grammarDirectory)
    check dirExists(installedPath)
    check fileExists(installedPath / FixtureGrammarPath)
    check isVscodeGrammarInstalled(candidate.id, grammarDirectory)

    let installed = installedVscodeGrammars(grammarDirectory)
    require installed.len == 1
    check installed[0].candidate.id == candidate.id
    check installed[0].sources.len == 1
    check installed[0].sources[0].content == FixtureGrammar

    expect ValueError:
      discard installVscodeGrammar(candidate, contents, grammarDirectory)

  test "rejects unsafe manifest paths and mismatched grammar scopes":
    let tree = fixtureTree()
    let unsafeManifest = %*{
      "contributes": {
        "grammars": [
          {
            "language": "toy",
            "scopeName": "source.toy",
            "path": "../outside.tmLanguage.json",
          }
        ]
      }
    }
    expect ValueError:
      discard
        parseVscodeGrammarManifest("toy", FixtureCommit, unsafeManifest.pretty(), tree)

    var contents = initTable[string, string]()
    contents[FixtureGrammarPath] = """{"scopeName":"source.impostor","patterns":[]}"""
    expect ValueError:
      fixtureCandidate().validateVscodeGrammarFiles(contents)

    var driveCandidate = fixtureCandidate()
    driveCandidate.rootPath = "C:/outside.tmLanguage.json"
    driveCandidate.grammarFiles[0].path = driveCandidate.rootPath
    contents[driveCandidate.rootPath] = FixtureGrammar
    expect ValueError:
      driveCandidate.validateVscodeGrammarFiles(contents)

suite "Open VSX grammar packages":
  test "search results pin package versions and reject foreign download hosts":
    let response = %*{
      "extensions": [
        {
          "namespace": "publisher",
          "name": "toy",
          "version": "1.2.3",
          "files": {
            "download":
              "https://open-vsx.org/api/publisher/toy/1.2.3/file/publisher.toy-1.2.3.vsix"
          },
        },
        {
          "namespace": "publisher",
          "name": "unsafe",
          "version": "1.2.3",
          "files": {
            "download":
              "https://example.com/api/publisher/unsafe/1.2.3/file/unsafe.vsix"
          },
        },
      ]
    }
    let extensions = parseOpenVsxGrammarSearch($response)
    require extensions.len == 1
    check extensions[0].publisher == "publisher"
    check extensions[0].version == "1.2.3"
    check extensions[0].manifestUrl ==
      "https://open-vsx.org/api/publisher/toy/1.2.3/file/package.json"

  test "installs only contributed grammar data and preserves registry provenance":
    let extension = OpenVsxGrammarExtension(
      publisher: "publisher",
      name: "toy",
      version: "1.2.3",
      archiveUrl:
        "https://open-vsx.org/api/publisher/toy/1.2.3/file/publisher.toy-1.2.3.vsix",
    )
    let manifest = %*{
      "publisher": "publisher",
      "name": "toy",
      "version": "1.2.3",
      "main": "./extension.js",
      "contributes": {
        "languages": [{"id": "toy", "aliases": ["Toy"], "extensions": [".toy"]}],
        "grammars": [
          {
            "language": "toy",
            "scopeName": "source.toy",
            "path": "./syntaxes/toy.tmLanguage.json",
          }
        ],
      },
    }
    let candidates = parseOpenVsxGrammarManifest(extension, $manifest)
    require candidates.len == 1
    let candidate = candidates[0]
    check candidate.id == "openvsx:publisher.toy:toy"
    check candidate.sourceCommit == ""
    check candidate.sourceVersion == "1.2.3"
    let root = createTempDir("kosmo-openvsx-", "")
    defer:
      removeDir(root)
    let archivePath = root / "extension.vsix"
    var entries = initTable[string, string]()
    entries["extension/package.json"] = $manifest
    entries["extension/syntaxes/toy.tmLanguage.json"] = FixtureGrammar
    entries["extension/extension.js"] = "throw new Error('must not execute');"
    entries["extension/README.md"] = "Not grammar data"
    writeFile(archivePath, createZipArchive(entries))
    let contents = candidate.readOpenVsxGrammarArchive(archivePath)
    check contents.len == 1
    let installed = candidate.installVscodeGrammar(contents, root / "installed")
    check not fileExists(installed / "extension.js")
    check not fileExists(installed / "README.md")
    let reloaded = installedVscodeGrammars(root / "installed")
    require reloaded.len == 1
    check reloaded[0].candidate.archiveUrl == extension.archiveUrl
    check reloaded[0].candidate.sourceVersion == extension.version
    check reloaded[0].sources.len == 1
    manifest["version"] = %"9.9.9"
    expect ValueError:
      discard parseOpenVsxGrammarManifest(extension, $manifest)
    manifest["version"] = %extension.version
    manifest["contributes"]["grammars"][0]["path"] = %"../escape.json"
    expect ValueError:
      discard parseOpenVsxGrammarManifest(extension, $manifest)
