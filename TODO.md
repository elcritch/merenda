# AppKit NSObject TODO

Generated from `deps/ravynos/Frameworks/AppKit` headers (`@interface NS* : ...`, categories excluded).

Implemented in Nutella today (7): `NSApplication`, `NSButton`, `NSControl`, `NSResponder`, `NSTextField`, `NSView`, `NSWindow`.

Remaining AppKit classes tracked: 222

Sorted by implementation priority (most useful first).

## Runtime Prereqs (Do First)
- [ ] Struct ABI/type encoding correctness - Add robust struct type encodings and remove object fallback for value types.
- [ ] `objcImpl` class methods/metaclass dispatch - Support defining/adding Objective-C class methods (`+`) in `objcImpl`.
- [ ] Optional protocol methods/properties modeling - Represent required vs optional protocol API surface.
- [ ] KVC/boxing type coverage - Expand beyond object/string/integer paths (floats, structs, etc.).
- [ ] Block bridging ergonomics - Add high-level Nim closure to Objective-C block bridge.

## Done: Already Implemented (7)
- [x] NSApplication - Application singleton and event loop coordinator.
- [x] NSButton - Clickable control that triggers actions and toggles state.
- [x] NSControl - Base class for interactive controls.
- [x] NSResponder - Base class for responder chain event handling.
- [x] NSTextField - Single-line text input and display control.
- [x] NSView - Base class for view hierarchy, drawing, and input.
- [x] NSWindow - Top-level window container for views and events.

## P1: Core UI and app-building essentials (68)
- [ ] NSActionCell - Cell subclass that supports target/action behavior.
- [ ] NSAlert - Modal/non-modal alert dialog API.
- [ ] NSBox - Framed container view with title/border styles.
- [ ] NSButtonCell - Cell used by NSButton-style controls.
<!-- - [ ] NSCell - Legacy lightweight drawing/editing object for controls. -->
- [ ] NSClipView - Viewport that clips content inside a scroll view.
- [ ] NSCollectionView - Grid/list collection control with reusable items.
- [ ] NSCollectionViewItem - Controller-like item object for collection entries.
- [ ] NSColor - Color object supporting multiple color spaces.
- [ ] NSColorSpace - Color space definition used by NSColor and rendering.
- [ ] NSColorWell - Interactive control for choosing colors.
- [ ] NSComboBox - Editable combo box with selectable list options.
<!-- - [ ] NSCursor - Mouse cursor image and behavior controller. -->
- [ ] NSDatePicker - Date/time selection control.
- [ ] NSDocument - Document-model object for document-based apps.
- [ ] NSDocumentController - Manager for document lifecycle and windows.
- [ ] NSEvent - Input event object for keyboard, mouse, and system actions.
- [ ] NSFont - Font face and metrics object for text rendering.
- [ ] NSFontDescriptor - Immutable descriptor of font attributes.
- [ ] NSFontManager - Shared manager for font panel and conversions.
- [ ] NSImage - Image asset object for bitmap/vector representations.
- [ ] NSImageRep - Abstract image representation backend.
- [ ] NSImageView - View subclass responsible for drawing and interaction.
- [ ] NSLayoutManager - Glyph layout engine between storage and containers.
- [ ] NSMenu - Menu container for command hierarchies.
- [ ] NSMenuItem - Single command item inside a menu.
- [ ] NSMutableParagraphStyle - Mutable paragraph-level text style settings.
- [ ] NSNib - Compiled Interface Builder nib loader and instantiator.
- [ ] NSOpenPanel - Open-file dialog panel.
- [ ] NSOutlineView - Hierarchical table/tree control.
- [ ] NSPanel - Utility-style window subclass.
- [ ] NSParagraphStyle - Immutable paragraph-level text style settings.
- [ ] NSPasteboard - System pasteboard/clipboard read-write API.
- [ ] NSPathCell - Cell used by path controls and panels.
- [ ] NSPathComponentCell - Cell representing one component in a path.
- [ ] NSPathControl - Breadcrumb/path navigation control.
- [ ] NSPopUpButton - Pop-up button that selects from a menu.
- [ ] NSProgressIndicator - Progress spinner/bar control.
- [ ] NSSavePanel - Save-file dialog panel.
<!-- - [ ] NSScreen - Display device and geometry information. -->
- [ ] NSScrollView - Scrollable container with clip and scrollers.
- [ ] NSSearchField - Text field specialized for search input.
- [ ] NSSecureTextField - Text field that masks entered characters.
- [ ] NSSegmentedControl - Segmented multi-action button control.
- [ ] NSSlider - Continuous or discrete slider control.
- [ ] NSSplitView - Resizable multi-pane container view.
- [ ] NSStatusBar - System status bar that hosts status items.
- [ ] NSStatusItem - Single item in the status bar.
- [ ] NSStepper - Increment/decrement stepper control.
- [ ] NSTabView - Tabbed view container.
- [ ] NSTabViewItem - Single tab item and its associated content.
- [ ] NSTableColumn - Column metadata and cell configuration for tables.
- [ ] NSTableHeaderCell - Cell used to draw table header titles.
- [ ] NSTableHeaderView - Header view that displays table column headers.
- [ ] NSTableView - Column/row table control for structured data.
<!-- - [ ] NSText - Legacy text editing view superclass. -->
- [ ] NSTextContainer - Text layout region used by NSLayoutManager.
- [ ] NSTextFieldCell - Cell used by text field controls.
- [ ] NSTextStorage - Mutable attributed string backing text systems.
- [ ] NSTextView - Multiline rich text editing and layout view.
- [ ] NSToolbar - Window toolbar container.
- [ ] NSToolbarItem - Single command item in a toolbar.
- [ ] NSToolbarItemGroup - Grouped toolbar items presented as a unit.
- [ ] NSTrackingArea - Mouse enter/exit/move tracking region.
- [ ] NSViewController - Controller that owns and manages a view.
- [ ] NSWindowController - Controller that owns and manages a window.
- [ ] NSWorkspace - System workspace and app/file integration API.

## P2: Common controls, data/controller layer, and rendering (66)
- [ ] NSAnimation - Time-based animation object.
- [ ] NSAnimationContext - Transaction context for implicit view animations.
- [ ] NSArrayController - Controller for array-backed model collections.
- [ ] NSBezierPath - Vector path object for 2D drawing.
- [ ] NSColorPanel - Shared panel for choosing colors.
- [ ] NSComboBoxCell - Cell used by combo box controls.
- [ ] NSController - Abstract base class for controller objects.
- [ ] NSDictionaryController - Controller for dictionary-backed models.
- [ ] NSDockTile - Dock tile badge/content representation.
<!-- - [ ] NSDrawer - Legacy slide-out drawer panel attached to a window. -->
- [ ] NSDrawerWindow - Internal window used to host an NSDrawer.
- [ ] NSFontFamily - Model object representing a font family.
- [ ] NSFontPanel - Shared panel for choosing fonts.
- [ ] NSFontPanelCell - Cell used by font panel controls.
<!-- - [ ] NSForm - Legacy form control containing labeled fields. -->
- [ ] NSFormCell - Cell used by NSForm rows.
- [ ] NSGradient - Gradient fill object for drawing operations.
- [ ] NSGraphicsContext - Drawing context wrapper for AppKit rendering.
- [ ] NSHelpManager - Manager object coordinating related subsystem behavior.
- [ ] NSLevelIndicator - Control that displays level/progress ratings.
- [ ] NSLevelIndicatorCell - Cell used by level indicator controls.
<!-- - [ ] NSMatrix - Legacy matrix/grid control of cells. -->
- [ ] NSObjectController - Controller for a single model object.
- [ ] NSOpenGLContext - OpenGL rendering context wrapper.
- [ ] NSOpenGLPixelBuffer - Offscreen OpenGL pixel buffer object.
- [ ] NSOpenGLPixelFormat - Pixel format descriptor for OpenGL surfaces.
- [ ] NSOpenGLView - View that presents OpenGL-rendered content.
- [ ] NSPageLayout - Panel that edits page format and layout options.
- [ ] NSPopUpButtonCell - Cell used by pop-up button controls.
- [ ] NSPredicateEditor - UI for composing NSPredicate expressions.
- [ ] NSPredicateEditorRowTemplate - Template describing a predicate editor row.
- [ ] NSPrintInfo - Print settings and pagination options.
- [ ] NSPrintOperation - Encapsulated print job execution.
- [ ] NSPrintPanel - Panel that presents print options.
- [ ] NSPrinter - Printer device description and capabilities.
- [ ] NSRuleEditor - UI for building rule-based logical expressions.
- [ ] NSRuleEditorButtonCell - Button cell used by rule editor rows.
- [ ] NSRuleEditorViewSliceRow - Internal row view used by NSRuleEditor.
- [ ] NSRulerMarker - Marker item displayed within an NSRulerView.
- [ ] NSRulerView - Ruler UI for text/layout editing views.
<!-- - [ ] NSScroller - Legacy scrollbar control object. -->
- [ ] NSSearchFieldCell - Cell used by search field controls.
- [ ] NSSegmentItem - Model item representing one segment.
- [ ] NSSegmentedCell - Cell used by segmented controls.
- [ ] NSShadow - Drop shadow style object for drawing.
- [ ] NSSliderCell - Cell used by slider controls.
- [ ] NSSound - Simple sound playback object.
- [ ] NSStepperCell - Cell used by stepper controls.
- [ ] NSTextAttachment - Attachment object embedded in attributed text.
- [ ] NSTextAttachmentCell - Cell that draws/edits text attachments.
- [ ] NSTextBlock - Block-level text layout style information.
- [ ] NSTextList - List style metadata for text system.
- [ ] NSTextStorage_concrete - Concrete internal NSTextStorage implementation.
- [ ] NSTextTab - Tab stop descriptor for paragraph layout.
- [ ] NSTextTable - Table layout container for rich text.
- [ ] NSTextTableBlock - Cell block within an NSTextTable layout.
- [ ] NSTokenAttachmentCell - Attachment cell used to render token chips.
- [ ] NSTokenField - Text field that edits tokenized values.
- [ ] NSTokenFieldCell - Cell used by token field controls.
- [ ] NSTreeController - Controller for tree-structured models.
- [ ] NSTypesetter - Low-level text line-breaking and glyph positioning engine.
- [ ] NSTypesetter_concrete - Concrete implementation of NSTypesetter internals.
- [ ] NSUserDefaultsController - Bindings bridge to user defaults values.
- [ ] NSUserDefaultsControllerProxy - Proxy helper for defaults bindings access.
<!-- - [ ] NSViewAnimation - Legacy keyframe animation for view/window changes. -->
- [ ] NSViewBackingLayer - CALayer subclass used as view backing storage.

## P3: Specialized, legacy, and ravynos-internal helpers (88)
<!-- - [ ] NSAlertPanel - Legacy alert panel window variant. -->
- [ ] NSBitmapImageRep - Bitmap-backed image representation class.
<!-- - [ ] NSBrowser - Legacy column-based browser control. -->
- [ ] NSBrowserCell - Cell used by NSBrowser columns.
- [ ] NSBrowserCellColorList - Internal color-list browser cell subclass.
- [ ] NSButtonImageSource - Internal provider for button imagery assets.
- [ ] NSCachedImageRep - Cached/offscreen image representation class.
- [ ] NSCellUndoManager - Manager object coordinating related subsystem behavior.
- [ ] NSClassSwapper - Nib-time helper that swaps archived class names.
- [ ] NSColorList - Named palette of reusable colors.
- [ ] NSColorPicker - Base class for color picker plug-ins.
- [ ] NSColorPickerColorList - Color picker that chooses from color lists.
- [ ] NSColorPickerSliders - Color picker that edits channel sliders.
- [ ] NSColorPickerWheel - Color picker that uses a wheel UI.
- [ ] NSColorPickerWheelView - View for rendering the color wheel picker.
- [ ] NSColor_CGColor - Bridge helper between NSColor and CoreGraphics colors.
- [ ] NSColor_catalog - Internal color catalog-backed NSColor subclass.
- [ ] NSComboBoxView - Internal popup/list view used by NSComboBox.
- [ ] NSComboBoxWindow - Internal window used by NSComboBox dropdown.
- [ ] NSControllerSelectionProxy - Proxy object exposing controller selection state.
- [ ] NSCursorRect - Rectangular region associated with a cursor update.
- [ ] NSCustomImageRep - Client-provided custom image representation.
- [ ] NSCustomObject - Nib placeholder object for custom classes.
- [ ] NSCustomResource - Nib placeholder for custom resources.
- [ ] NSCustomView - Nib placeholder/proxy for custom views.
- [ ] NSDatePickerCell - Cell used by date picker controls.
- [ ] NSDisplay - Display subsystem helper/internal abstraction.
- [ ] NSDraggingManager - Internal manager for drag-and-drop sessions.
- [ ] NSEPSImageRep - Encapsulated PostScript image representation.
- [ ] NSEvent_CoreGraphics - Internal NSEvent subclass/adapter for CoreGraphics events.
- [ ] NSEvent_keyboard - Internal NSEvent specialization for keyboard events.
- [ ] NSEvent_mouse - Internal NSEvent specialization for mouse events.
- [ ] NSEvent_other - Internal NSEvent specialization for other event types.
- [ ] NSEvent_periodic - Internal NSEvent specialization for periodic events.
- [ ] NSFileWrapper - Filesystem wrapper object for file packages and attachments.
- [ ] NSFontMetric - Font metric helper values for layout calculations.
- [ ] NSFontTypeface - Model object for a specific typeface face/style.
- [ ] NSGlyphGenerator - Generates glyphs from character runs.
- [ ] NSGlyphInfo - Metadata describing a specific glyph.
- [ ] NSGraphicsStyle - Internal style bundle for themed drawing primitives.
- [ ] NSIBObjectData - Archived nib object graph metadata container.
- [ ] NSImageCell - Cell used to display/edit images in controls.
- [ ] NSInterfacePart - Internal themed interface part description.
- [ ] NSInterfacePartAttributedString - Internal attributed string for interface parts.
- [ ] NSInterfacePartDisabledAttributedString - Internal disabled-state interface part text.
- [ ] NSKeyboardBinding - Keyboard shortcut binding description.
- [ ] NSKeyboardBindingManager - Manager for keyboard binding lookup and dispatch.
- [ ] NSMeasurementUnit - Measurement unit descriptor used by drawing/layout APIs.
- [ ] NSModalSessionX - Internal modal-session state object.
- [ ] NSNibAXRelationshipConnector - Nib connector for accessibility relationships.
- [ ] NSNibBindingConnector - Nib connector for Cocoa bindings wiring.
- [ ] NSNibConnector - Base connector object in nib unarchiving.
- [ ] NSNibControlConnector - Nib connector for control-action wiring.
- [ ] NSNibFontNameTranslator - Nib helper for translating archived font names.
- [ ] NSNibHelpConnector - Nib connector for help anchor wiring.
- [ ] NSNibOutletConnector - Nib connector for outlet wiring.
- [ ] NSOpenGLDrawable - Drawable surface abstraction for OpenGL.
- [ ] NSPDFImageRep - PDF-backed image representation class.
- [ ] NSPersistentDocument - Document subclass integrated with Core Data persistence.
<!-- - [ ] NSPoofAnimation - Legacy visual poof/disappear animation effect. -->
- [ ] NSPopUpView - Internal view used by pop-up button menus.
- [ ] NSPopUpWindow - Internal window used by pop-up controls.
- [ ] NSPrintProgressPanelController - Controller for print-progress panel UI.
- [ ] NSRangeArray - Internal range collection helper for text/layout.
- [ ] NSRichTextReader - Reader/parser for RTF rich text input.
- [ ] NSRichTextWriter - Writer/serializer for RTF rich text output.
- [ ] NSSecureLayoutManager - Layout manager variant for secure text rendering.
- [ ] NSSecureTextFieldCell - Cell used by secure text fields.
- [ ] NSSecureTextView - Text view specialized for secure entry behavior.
- [ ] NSSheetContext - Internal context for attached sheet state.
- [ ] NSSpellChecker - Spell checking and correction service API.
- [ ] NSSpellCheckerTagData - Internal spell-check session tag storage.
- [ ] NSSpellingViewController - Controller for spelling UI interactions.
<!-- - [ ] NSStringDrawer - Legacy helper for NSString text drawing APIs. -->
<!-- - [ ] NSSystemInfoPanel - Legacy panel that displays system information. -->
- [ ] NSTableCornerView - Corner view between table headers and content.
- [ ] NSTextViewSharedData - Shared internal storage for NSTextView instances.
- [ ] NSThemeFrame - Internal themed frame view for window chrome.
- [ ] NSToolTipWindow - Window used internally to display tooltips.
- [ ] NSToolbarCustomizationPalette - UI palette for customizing toolbar items.
- [ ] NSToolbarCustomizationView - View that hosts toolbar customization UI.
- [ ] NSToolbarItemView - Internal view wrapper for toolbar item rendering.
- [ ] NSToolbarView - Container view that lays out toolbar items.
- [ ] NSUndoReplaceCharacters - Undo command for text character replacement.
- [ ] NSUndoSetAttributes - Undo command for attributed text attribute changes.
- [ ] NSUndoTextOperation - Base undo operation for text edits.
- [ ] NSUndoTyping - Undo operation grouping typing sequences.
- [ ] NSWindowAnimationContext - Context object for window animation transitions.
- [ ] NSWindowTemplate - Archived template used to instantiate windows from nibs.
