from sigils/protocol import nil

when declared(protocol.sig):
  from sigils/protocol import sig
  export sig
else:
  template sig*(name: static string): protocol.SigilName =
    protocol.sigName(name)

template sigils*(
    name: static string
): protocol.SigilName {.deprecated: "use sig\"name\"".} =
  sig(name)
