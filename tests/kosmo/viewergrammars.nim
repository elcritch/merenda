import std/[os, strutils, tables, tempfiles, unicode, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo
import merenda/kosmo/vscodegrammars
import fixtures/ui

const
  SqlGrammarPath = "syntaxes/sql.tmLanguage.json"
  SqlHelperPath = "syntaxes/helper.tmLanguage.json"
  SqlSource = "SELECT 'κόσμος' FROM records;"
  SqlGrammar =
    """
{"scopeName":"source.sql","patterns":[{"include":"source.viewer-sql-helper"}]}
"""
  SqlHelper =
    """
{"scopeName":"source.viewer-sql-helper","patterns":[
  {"name":"keyword.control.sql","match":"\\b(SELECT|FROM)\\b"},
  {"name":"string.quoted.single.sql","begin":"'","end":"'"}
]}
"""

proc installSqlFixture(grammarDirectory: string): string =
  let candidate = VscodeGrammarCandidate(
    id: "vscode.sql",
    name: "SQL",
    extensionFolder: "sql",
    languageId: "sql",
    scopeName: "source.sql",
    rootPath: SqlGrammarPath,
    sourceCommit: "0123456789abcdef0123456789abcdef01234567",
    extensions: @[".sql", ".query.sql"],
    fileNames: @["Queryfile"],
    grammarFiles:
      @[
        VscodeGrammarFile(
          path: SqlGrammarPath, scopeName: "source.sql", languageId: "sql"
        ),
        VscodeGrammarFile(path: SqlHelperPath, scopeName: "source.viewer-sql-helper"),
      ],
  )
  installVscodeGrammar(
    candidate,
    {SqlGrammarPath: SqlGrammar, SqlHelperPath: SqlHelper}.toTable,
    grammarDirectory,
  )

proc attributesFor(storage: TextStorage, needle: string): TextAttributes =
  let source = storage.stringValue()
  let index = source.find(needle)
  doAssert index >= 0, needle & " is missing from " & source
  storage.attributesAt(source[0 ..< index].runeLen)

proc checkSqlColors(view: MarkdownView) =
  require view.waitForMarkdownParsing()
  check view.textStorage().attributesFor("SELECT").foregroundColor ==
    view.markdownStyle().syntaxTokenColors[stcKeyword]
  check view.textStorage().attributesFor("κόσμος").foregroundColor ==
    view.markdownStyle().syntaxTokenColors[stcString]

suite "Kosmo installed viewer grammars":
  test "installed roots and includes reach Markdown GitHub and diff worker caches":
    let root = createTempDir("kosmo-viewer-grammars-", "")
    defer:
      removeDir(root)
    let installedPath = installSqlFixture(root)
    let sources = installedVscodeGrammars(root).viewerGrammarSources()
    require sources.len == 2
    check sources.matterLanguageForFile("folder/QUERY.SQL") == "source.sql"
    check sources.matterLanguageForFile("folder/example.query.sql") == "source.sql"
    check sources.matterLanguageForFile("folder/Queryfile") == "source.sql"
    check sources.matterLanguageForFile("folder/unrelated.txt") == ""

    var cache: MatterGrammarCache
    check cache.matterSyntaxHighlighterBounded(SqlSource, "sql").spans.len == 0
    cache.setGrammarSources(sources)
    check cache.matterSyntaxHighlighterBounded(SqlSource, "sql").spans.syntaxTokenAt(0) ==
      stcKeyword
    check cache
    .matterSyntaxHighlighterBounded(SqlSource, "source.sql").spans
    .syntaxTokenAt(0) == stcKeyword

    let preview = newMarkdownView("```sql\n" & SqlSource & "\n```")
    require preview.waitForMarkdownParsing()
    preview.matterGrammarSources = sources
    preview.checkSqlColors()

    let github = newKosmoGitHubPanel(
      GitHubSnapshot(
        items:
          @[
            GitHubItem(
              kind: ghikIssue,
              number: 1,
              title: "SQL",
              body: preview.markdown(),
              state: "OPEN",
            )
          ]
      )
    )
    defer:
      github.close()
    require github.waitForGitHub()
    github.markdownView.expandMarkdownHeadings()
    github.markdownView.matterGrammarSources = sources
    github.markdownView.checkSqlColors()

    let diff = newKosmoGitDiffPanel(
      parseGitDiff(
        "diff --git a/Queryfile b/Queryfile\n@@ -1 +1 @@\n-" & SqlSource & "\n+" &
          SqlSource & "\n"
      )
    )
    defer:
      diff.close()
    diff.frame = rect(0, 0, 800, 600)
    diff.layoutSubtreeIfNeeded()
    require diff.waitForDiff()
    let text = diff.textViewForFile(0)
    require diff.waitForDiff()
    let previousBuilds = diff.highlightBuildCount()
    diff.matterGrammarSources = sources
    require diff.waitForDiff()
    check diff.highlightBuildCount() > previousBuilds
    for needle in ["-SELECT", "+SELECT"]:
      let rendered = text.stringValue()
      let byteIndex = rendered.find(needle) + 1
      require byteIndex > 0
      check text
      .textStorage()
      .attributesAt(rendered[0 ..< byteIndex].runeLen).foregroundColor ==
        diff.markdownView.markdownStyle().syntaxTokenColors[stcKeyword]

    # Updating sources must invalidate a compiled grammar as well as a cached miss.
    writeFile(
      installedPath / SqlHelperPath,
      SqlHelper.replace("keyword.control.sql", "constant.numeric.sql"),
    )
    let updated = installedVscodeGrammars(root).viewerGrammarSources()
    preview.matterGrammarSources = updated
    require preview.waitForMarkdownParsing()
    check preview.textStorage().attributesFor("SELECT").foregroundColor ==
      preview.markdownStyle().syntaxTokenColors[stcNumber]
    diff.matterGrammarSources = updated
    require diff.waitForDiff()
    check text.textStorage().attributesFor("SELECT").foregroundColor ==
      diff.markdownView.markdownStyle().syntaxTokenColors[stcNumber]
    cache.setGrammarSources(@[])
    check cache.matterSyntaxHighlighterBounded(SqlSource, "sql").spans.len == 0

  test "install and reload updates existing cached Kosmo previews and open documents":
    let
      root = createTempDir("kosmo-grammar-reload-", "")
      previousConfig = getEnv("XDG_CONFIG_HOME")
      hadConfig = existsEnv("XDG_CONFIG_HOME")
    putEnv("XDG_CONFIG_HOME", root)
    defer:
      if hadConfig:
        putEnv("XDG_CONFIG_HOME", previousConfig)
      else:
        delEnv("XDG_CONFIG_HOME")
      removeDir(root)
    let frontend = newKosmoApplication(
      newApplication("Kosmo grammar reload"), monitorsGitStatus = false
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 900, 600)
    var previews: seq[MarkdownView]
    for name in ["first.md", "second.md"]:
      let path = root / name
      writeFile(path, "```sql\n" & SqlSource & "\n```")
      require frontend.openPath(path)
      require frontend.editorPane.markdownView.waitForMarkdownParsing()
      previews.add frontend.editorPane.markdownView
    let cachedPreview = frontend.editorPane.markdownView
    let diff = newKosmoGitDiffPanel(
      parseGitDiff(
        "diff --git a/query.sql b/query.sql\n@@ -0,0 +1 @@\n+" & SqlSource & "\n"
      )
    )
    defer:
      diff.close()
    require frontend.openDocument(
      newKosmoPaneDocument(
        "test.grammars.diff",
        "SQL Diff",
        diff,
        preferredFirstResponder = diff.markdownView.textView(),
      )
    )
    require diff.waitForDiff()
    discard installSqlFixture(defaultKosmoVscodeGrammarDirectory())
    frontend.reloadInstalledVscodeGrammars()
    for preview in previews:
      preview.checkSqlColors()
    require diff.waitForDiff()
    let code = diff.textViewForFile(0)
    require diff.waitForDiff()
    check code.textStorage().attributesFor("SELECT").foregroundColor ==
      diff.markdownView.markdownStyle().syntaxTokenColors[stcKeyword]
    # A new viewer also reads installed grammars without a manual reload.
    let github = newKosmoGitHubPanel(
      GitHubSnapshot(
        items:
          @[
            GitHubItem(
              kind: ghikIssue,
              number: 1,
              title: "SQL",
              body: cachedPreview.markdown(),
              state: "OPEN",
            )
          ]
      )
    )
    defer:
      github.close()
    require github.waitForGitHub()
    github.markdownView.expandMarkdownHeadings()
    github.markdownView.checkSqlColors()
