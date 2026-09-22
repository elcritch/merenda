## VS Code TextMate grammar discovery metadata and safe local installation.
import std/[json, os, tables, tempfiles, unittest]

import merenda/kosmo/vscodegrammars

const
  FixtureCommit = "0123456789abcdef0123456789abcdef01234567"
  FixtureGrammarPath = "syntaxes/toy.tmLanguage.json"
  FixtureGrammar = """{"scopeName":"source.toy","patterns":[]}"""

proc fixtureTree(): VscodeGrammarTree =
  let content =
    %*{
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
  let manifest =
    %*{
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
    let unsafeManifest =
      %*{
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
