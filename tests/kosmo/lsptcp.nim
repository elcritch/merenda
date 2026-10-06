import std/[nativesockets, unittest]

import merenda/kosmo/[cli, lsptcp]

suite "Kosmo TCP LSP endpoints":
  test "accepts hostnames and IPv4 and bracketed IPv6 addresses":
    check parseLspTcpEndpoint("tcp://localhost:49153") ==
      LspTcpEndpoint(host: "localhost", port: Port(49153))
    check parseLspTcpEndpoint("tcp://127.0.0.1:1") ==
      LspTcpEndpoint(host: "127.0.0.1", port: Port(1))
    check parseLspTcpEndpoint("tcp://[::1]:65535") ==
      LspTcpEndpoint(host: "::1", port: Port(65535))
    check kosmoLspChildArguments("tcp://127.0.0.1:49153") ==
      @[KosmoLspExecFlag, "tcp://127.0.0.1:49153"]

  test "rejects incomplete endpoints and URI components outside host and port":
    for address in [
      "http://127.0.0.1:49153", "tcp://:49153", "tcp://localhost", "tcp://localhost:0",
      "tcp://localhost:65536", "tcp://localhost:-1", "tcp://localhost:port",
      "tcp://localhost:999999999999999999999999", "tcp://user@localhost:49153",
      "tcp://localhost:49153/path", "tcp://localhost:49153?query",
      "tcp://localhost:49153#fragment", "tcp://local host:49153",
    ]:
      expect ValueError:
        discard parseLspTcpEndpoint(address)
