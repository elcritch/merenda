# Development control

Build any Merenda application with `-d:merenda.devControl` to include an optional
local automation endpoint. Production builds omit the listener, dispatch adapter
and capture queues. The environment cannot enable an uninstrumented build.

```sh
nim ic -d:merenda.devControl examples/controls_showcase.nim
nim ic -o:deps/merenda-dev tools/merenda_dev.nim
MERENDA_DEV_CONTROL=1 MERENDA_BACKGROUND=1 ./examples/controls_showcase &
app_pid=$!
./deps/merenda-dev --pid "$app_pid" windows
./deps/merenda-dev --pid "$app_pid" screenshot --window w1 --output /tmp/showcase.png
./deps/merenda-dev --pid "$app_pid" pointer --window w1 --action click --x 80 --y 100
./deps/merenda-dev --pid "$app_pid" key --window w1 --action down --key a --modifiers command
./deps/merenda-dev --pid "$app_pid" text --window w1 --text 'Hello from automation'
./deps/merenda-dev --pid "$app_pid" theme-load --file /absolute/path/theme.css
./deps/merenda-dev --pid "$app_pid" theme-reload
kill "$app_pid"
wait "$app_pid"
```

`MERENDA_BACKGROUND=1` shows windows without explicit application activation or
key-window ordering on macOS and uses nonactivating presentation on Windows. It
also applies to later windows and popup hosts. Windows remain eligible for normal
user interaction. This is a visible application, and `&` handles shell detachment.
Linux/BSD window managers retain control of activation; this version does not
promise focus preservation there. The control transport currently supports macOS,
Linux and BSD Unix sockets; Windows transport is deferred.

The server starts when the application event loop is prepared and stops when
`Application.run` exits normally. `runForFrames` also pumps control requests; users
of that API must call `app.stopDevControl()` during teardown. Embedders can import
`merenda/nimkit/app/devcontrol` and call
`app.startDevControl(DevControlOptions(socketPath: path))` explicitly.

## Addresses and transport

The client requires exactly one destination: `--pid PID` or `--socket PATH`.
There is no registry, current-instance selection or broadcast. The default socket
is `/tmp/merenda-dev-<uid>/<pid>.sock`. Set `MERENDA_DEV_SOCKET` to an absolute path
to enable the server at another address, then use `--socket` on the client. Its
parent directory must already exist, belong to the current user, and have no
group/other permissions (normally mode 0700). Paths must fit the native socket-path limit (currently 91 bytes with Nim on
macOS, up to 100 elsewhere); the client reports the applicable limit.

Sockets have mode 0600. An occupied address is an error; the server never removes
an existing address to start. After an abnormal exit, remove a stale socket only
after verifying the process is gone. Normal shutdown removes only the inode the
server created. Local processes running as the same user are trusted.

The server handles at most four connections and four captures at a time. Requests
are limited to 128 KiB, responses to 32 MiB, and images to eight million pixels.
Socket work is nonblocking and bounded per application frame, including partial
writes. Instrumented applications with an enabled endpoint poll at most every
20 ms; an idle production build has no polling cost. Captures have a ten-second
deadline; connections have a fifteen-second deadline, extended by output progress.
The CLI accepts `--timeout MS` (default 15000). **A timeout does not prove a
mutating command was undelivered. Clients must not automatically retry input.**

## Commands and screenshot semantics

`info` reports PID, protocol version, capabilities and background presentation.
`windows` reports opaque IDs, titles, logical content dimensions, content scale,
visibility, native readiness, logical key-window state and modal blocking. Popup
hosts are included. IDs last for one server instance, are never reused, and do not
depend on titles or memory addresses.

`screenshot` requests a fresh rendered frame after the command is accepted. The
response contains base64 PNG bytes, pixel dimensions, scale, and the completed
render ID. `--output` writes
those bytes in the **client process**; the app accepts no output file path. Images
contain the rendered client area at backing-pixel resolution with a top-left
origin. Capture happens on the renderer's owning thread before presentation, for
both main-thread and dedicated rendering. The flag enables Vulkan readback via
this repository's `config.nims`; downstream projects using Vulkan must also set
`-d:figdraw.vulkanReadback=on` in their build configuration.

Captures exclude native titlebars, desktop contents, OS shadows, system menus,
and native backdrop/blur effects. Hidden, minimized, closed or unrealized windows
are unavailable and are never shown implicitly. A fresh frame is a rendering
barrier, not a guarantee that loaders, jobs or animations have become idle.

`pointer` supports `move`, `down`, `up`, `drag`, `click`, and `scroll`. Coordinates
are logical content coordinates; optional buttons are `primary`, `secondary`, or
`other`. Scroll uses `--delta-x` and `--delta-y`. `key` supports `down` and `up` with
case-insensitive NimKit key names without the `key` prefix, such as `a`, `enter`,
`arrowleft`, `backspace`, and `escape`. Modifiers are comma-separated `shift`,
`control`, `option`, and `command`. `text` commits UTF-8 text to the responder; it
does not simulate IME composition. Input follows ordinary NimKit dispatch and
rejects modal-blocked windows. Responses distinguish successful delivery from the
`handled` boolean returned by the responder.

## Live themes

`theme-load --file PATH` reads CSS on the app's host and applies it to the
application appearance, including existing windows that inherit it and later
windows. The CLI resolves relative paths before sending them. `theme-reload`
rereads the last successfully loaded file. Each load compiles against the original
appearance saved on the first load, so removing declarations removes their effects.
Filesystem errors and CSS diagnostics leave the current appearance and reload path
unchanged. These commands require an enabled development endpoint.

Merenda Settings also has a **Refresh theme** button below the font choice on the
Typography tab. It rereads the selected bundled theme's complete CSS inheritance
chain, including `base.css` and parent themes, and keeps the chosen fonts and size.
This button is available in regular builds. It reads the source `stylesheets/`
directory recorded at build time; set `MERENDA_THEME_CSS_DIR` to another directory
containing the bundled CSS files when developing from an installed app. The panel
shows CSS or filesystem errors without replacing the active theme.

## Sigils RPC and future adapters

The private Unix socket implements Sigils' `JsonRpcIoAgent` boundary. Sigils'
`JsonRpcAdapter` and `JsonRpcDispatcher` validate JSON-RPC 2.0 messages and dispatch
the explicitly registered typed selectors on the owning GUI thread. No extra
helper thread or TCP listener is needed. Socket I/O finishes iterating connections
before emitting requests, so nested modal event loops and shutdown callbacks can
safely poll or close the endpoint.

The transport is one compact JSON-RPC request and response per connection,
separated by newlines. `merenda.request` takes the named `DevRequest` parameters:

```json
{"jsonrpc":"2.0","id":"r1","method":"merenda.request","params":{"command":"windows"}}
{"jsonrpc":"2.0","id":"r1","result":{"version":1,"id":"","ok":true,"result":{"windows":[]}}}
```

Application failures use stable string codes inside the result, such as
`window_not_found`, `invalid_css`, or `theme_load_failed`. Invalid JSON-RPC messages,
unknown methods, and invalid selector arguments use Sigils' standard JSON-RPC
errors, including `-32601` and `-32602`.

Screenshots finish asynchronously. The first call returns an application result
containing `{"pending":"r1"}`. Retrieve it with
`merenda.result` and `{"token":"r1"}` on another connection. This returns the same
pending handle while rendering is in progress, then consumes the completed result.
Handles are bounded to four and expire after fifteen seconds. **Poll the result
handle; do not resend the original input command.** `sendDevRequest` and the CLI
perform these steps automatically within one overall timeout.

The public `DevRequest`, `DevResponse`, selector descriptors and JSON hooks live in
`merenda/nimkit/devcontrol/protocol`; `devSocketPath`, `sendDevRpcRequest`, and
`sendDevRequest` live in `merenda/nimkit/devcontrol/transport`. These modules have no
GUI dependencies. A future MCP server can call the registered selectors through
JSON-RPC, or reuse the synchronous client wrapper and return PNG payloads directly.
Discovery, view selectors, accessibility trees, OS-level input, native-menu
automation and an MCP server itself are deferred.
