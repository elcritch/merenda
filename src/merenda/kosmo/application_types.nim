# Kosmo's shared application and workspace types.

type
  KosmoMarkdownMode* = enum
    kmmPreview
    kmmSyntax

  KosmoMarkdownColorMode* = enum
    kmcmLight
    kmcmDark

  KosmoEditorContentKind = enum
    keckOther
    keckSyntax
    keckMarkdownPreview

  KosmoPaneCommand = enum
    kpcNone
    kpcSplitBelow
    kpcSplitRight
    kpcNewBelow
    kpcFocusNext
    kpcFocusLeft
    kpcFocusBelow
    kpcFocusAbove
    kpcFocusRight
    kpcClose
    kpcGrowHeight
    kpcShrinkHeight
    kpcShrinkWidth
    kpcGrowWidth
    kpcEqualize

  KosmoCommandBar* = ref object of nimkit.MonoTextView

  KosmoPaneIndicator = ref object of nimkit.View

  KosmoMarkdownView = ref object of nimkit.MarkdownView
    editorView: WeakRef[KosmoEditorView]

  KosmoMarkdownPreview = object
    bufferId: KosmoBufferId
    view: KosmoMarkdownView

  KosmoMarkdownControls* = ref object of nimkit.Box
    modeButton*: nimkit.Button
    colorModeButton*: nimkit.Button
    decreaseFontButton*: nimkit.Button
    increaseFontButton*: nimkit.Button
    editorView: WeakRef[KosmoEditorView]
    xColorMode: KosmoMarkdownColorMode
    xThemeColorMode: KosmoMarkdownColorMode
    xFontSize: float32

  KosmoEditorView* = ref object of nimkit.MonoTextView
    editor*: KosmoEditor
    documentTabs*: nimkit.DocumentTabs
    searchBar: KosmoSearchBar
    searchOrigin: KosmoBufferCursor
    renderBuffer: RenderBuffer
    statusLabel: nimkit.Label
    commandBar: KosmoCommandBar
    scrollOffsetRows: float32
    lastTabs: seq[KosmoTab]
    syncingTabs: bool
    tabsDelegate: KosmoEditorTabsHandler
    usesBufferSubset: bool
    bufferIds: seq[KosmoBufferId]
    selectedBufferId: Option[KosmoBufferId]
    markdownSyntaxBufferIds: seq[KosmoBufferId]
    viewStates: seq[KosmoEditorViewState]
    dockGroup: WeakRef[KosmoEditorGroup]
    pendingPanePrefix: bool

  KosmoEditorTabsHandler = ref object of nimkit.Responder
    editorView: WeakRef[KosmoEditorView]
    dockController: WeakRef[KosmoDockController]
    appearanceWindow: WeakRef[nimkit.Window]

  KosmoEditorPane* = ref object of nimkit.View
    documentTabs*: nimkit.DocumentTabs
    editorView*: KosmoEditorView
    commandBar*: KosmoCommandBar
    markdownView*: KosmoMarkdownView
    markdownPreviews: seq[KosmoMarkdownPreview]
    markdownControls*: KosmoMarkdownControls
    contentView*: nimkit.View
    activeIndicator: KosmoPaneIndicator
    dockGroup: WeakRef[KosmoEditorGroup]

  KosmoSidebarBrowserArea = ref object of nimkit.View
    tabs: nimkit.CompactTabView
    activeIndicator: KosmoPaneIndicator

  KosmoSidebarPane* = ref object of nimkit.View
    contextPanel*: KosmoContextPanel
    splitView*: nimkit.SplitView
    setInitialDivider: bool
    tabs*: nimkit.CompactTabView
    fileTree: KosmoFileTree
    searchPanel: KosmoFileSearchPanel
    activeIndicator: KosmoPaneIndicator
    dockController: WeakRef[KosmoDockController]
    observedWindow: WeakRef[nimkit.Window]

  KosmoEditorGroup* = ref object
    identifier*: string
    panel*: nimkit.DockPanel
    pane*: KosmoEditorPane
    editorView*: KosmoEditorView
    workspace*: nimkit.DockView
    window*: nimkit.Window
    documents: seq[KosmoPaneDocument]
    tabOrder: seq[string]
    selectedTabIdentifier: string

  KosmoDockHost = ref object
    workspace: nimkit.DockView
    window: nimkit.Window
    contentView: nimkit.View
    statusLabel: nimkit.Label
    primary: bool
    activeGroup: KosmoEditorGroup

  KosmoDockController = ref object
    frontend: WeakRef[KosmoApplication]
    editor: KosmoEditor
    groups: seq[KosmoEditorGroup]
    hosts: seq[KosmoDockHost]
    xActiveGroup: KosmoEditorGroup
    nextGroupIdentifier: int
    nextDocumentIdentifier: int
    shortcutBindings: nimkit.KeyBindingTable
    shortcutProfile: KosmoShortcutProfile
    editorInputPolicy: KosmoEditorInputPolicy
    xSidebarFocused: bool

  KosmoContentView = ref object of nimkit.View
    splitView: nimkit.SplitView
    statusLabel: nimkit.Label
    setInitialDivider: bool
    lastSplitWidth: float32
    fileTreeWidth: float32
    onShowFileExplorer: proc() {.closure.}
    onRevealActiveFile: proc() {.closure.}
    onFindInFiles: proc() {.closure.}
    onQuickOpen: proc() {.closure.}
    onNewTerminal: proc() {.closure.}
    onFocusPanel: proc(panelNumber: int) {.closure.}
    quickOpenPanel: KosmoQuickOpenPanel

  KosmoDetachedContentView = ref object of nimkit.View
    workspace: nimkit.DockView
    statusLabel: nimkit.Label

  KosmoWindowManager* = ref object
    application*: nimkit.Application
    keyBindingsPath: string
    configPath: string
    config: KosmoConfig
    frontends: seq[KosmoApplication]
    cliServer: KosmoCliOpenServer

  KosmoWindowLifecycle = ref object of nimkit.Responder
    frontend: WeakRef[KosmoApplication]

  KosmoDetachedWindowLifecycle = ref object of nimkit.Responder
    controller: WeakRef[KosmoDockController]

  KosmoApplication* = ref object
    application*: nimkit.Application
    window*: nimkit.Window
    editorView*: KosmoEditorView
    editorPane*: KosmoEditorPane
    documentTabs*: nimkit.DocumentTabs
    statusLabel*: nimkit.Label
    fileTree*: KosmoFileTree
    fileBrowserPanel*: KosmoFileBrowserPanel
    gitDiffPanel*: KosmoGitDiffPanel
    sidebarPane*: KosmoSidebarPane
    sidebarTabs*: nimkit.CompactTabView
    searchPanel*: KosmoFileSearchPanel
    quickOpenPanel*: KosmoQuickOpenPanel
    splitView*: nimkit.SplitView
    dockView*: nimkit.DockView
    contentView*: nimkit.MenuRootView
    documentView: KosmoContentView
    dockController: KosmoDockController
    xSettingsWindow: KosmoSettingsWindow
    xTerminalOptionAsMeta: bool
    xTerminalLinksEnabled: bool
    xWindowManager: WeakRef[KosmoWindowManager]
    xWindowLifecycle: KosmoWindowLifecycle
    xCliWindowId: string
    xHasFileBrowser: bool
    xClosed: bool
