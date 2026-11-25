## The About window shown by Kosmo's application menu.
import std/strutils

from pkg/pixie import resize

import ../nimkit
import ../nimkit/directviews

proc newKosmoAboutWindow*(app: Application): Window =
  let
    info = app.aboutInfo()
    name = app.applicationName()
    icon = app.icon()
    credits = info.credits.splitLines()
    content = newDirectView()
  content.viewBody:
    VStack:
      this.alignment = svaCenter
      this.distribution = svdNatural
      this.edgeInsets = insets(24)
      this.spacing = 10
      if not icon.isNil:
        ImageView(newImageResource(icon.pixels().resize(72, 72))):
          this.accessibilityLabel = name & " icon"
      Label(stringValue = name, labelStyle = lsTitle)
      Label(stringValue = "Version " & info.version)
      Label(stringValue = "Build " & info.buildVersion, labelStyle = lsStatus)
      for index, line in credits:
        if line.len > 0:
          keyed(index):
            var url = ""
            for link in info.creditLinks:
              if link.text == line:
                url = link.url
                break
            if url.len > 0:
              Button(line):
                this.onAction(app, url) do(
                  this: Button, owner: Application, link: string
                ):
                  discard owner.workspace().openUrl(link)
            else:
              Label(stringValue = line)

  result = newPanel("About " & name, rect(180, 160, 540, 290))
  result.automaticallyAdjustsContentMinSize = true
  result.setContentView(content)
