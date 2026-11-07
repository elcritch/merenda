import std/[os, strutils]
when defined(syneditProfileBaseline):
  import merenda/nimkit/text/syneditviews_profile_baseline
else:
  import merenda/nimkit/text/syneditviews

let source = repeat(" ", 8 * 1024 * 1024)
let tokens = synEditTokenSpans(source, langNim)
echo "source bytes=", source.len, " spans=", tokens.len
stdout.flushFile()
if paramCount() > 0:
  discard readLine(stdin)
  echo "source still live=", source.len
