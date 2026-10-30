## Shared runner for tests requiring cross-component or process-level integration.
import std/exitprocs
import integrations/fixtures/devcontrol
import integrations/fixtures/atomicsavefailure
import integrations/fixtures/githubcli
import integrations/fixtures/kosmolspexec
import integrations/fixtures/moefrontendexec
import integrations/processdescriptors
import integrations/atomicsaves
import integrations/application_sigils
import integrations/kosmolsp
import integrations/figdraw_text_offsets
import integrations/gitprocesslifecycle
import integrations/githubviewer
import integrations/kosmoprocesses
import integrations/moefrontendwork
import integrations/kosmocliopen
import integrations/kosmoterminalenvironment
import integrations/kosmoterminalinput
import integrations/nativewindowactivation
import integrations/nativeeventloop
import integrations/nativewindowlifecycle
import integrations/nativewindowrepaint
import integrations/nativewindowscale
import integrations/urlassets
import integrations/terminalwatch
import integrations/terminals
import integrations/resourcelifetimes
import integrations/devcontrol
import integrations/backgroundworkershutdown

when isMainModule:
  # Nim ic can otherwise exit successfully after unittest records a failure.
  if getProgramResult() != 0:
    quit(getProgramResult())
