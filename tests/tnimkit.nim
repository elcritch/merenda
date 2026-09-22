## NimKit's shared test runner and complete public API smoke test.
import merenda/nimkit

import nimkit/application_icon
import nimkit/assetcache
import nimkit/backrefs_arc
import nimkit/comboboxes
import nimkit/controls
import nimkit/datepickers
import nimkit/daterangepickers
import nimkit/tokenfields
import nimkit/popuphosts
import nimkit/constraints
import nimkit/controlfontfaces
import nimkit/diagnostics
import nimkit/documenttabs
import nimkit/filesearch
import nimkit/filebrowsers
import nimkit/gitstatus
import nimkit/font_layout
import nimkit/fontpickers
import nimkit/gaptextbuffers
import nimkit/images
import nimkit/markdownviews
import nimkit/menus
import nimkit/segmentedcontrols
import nimkit/resources
import nimkit/settings
import nimkit/svgimages
import nimkit/svgpathloader
import nimkit/styledruns
import nimkit/table_column_resizing
import nimkit/textlayout
import nimkit/terminalgeometry
import nimkit/urls

when not defined(useNativeDynlib):
  # Retained render fragments are a client-side Figdraw implementation detail
  # and are intentionally outside the native ABI.
  import nimkit/renderfragments
  import nimkit/threading
