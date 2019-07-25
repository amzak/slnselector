# Package

version       = "0.1.0"
author        = "Anonymous"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "src"
bin           = @["main"]

# Dependencies
requires "nim >= 0.20.0",
    "bearlibterminal"

task debug, "build&run":
    exec "nimble build"
    exec "./main.exe"

task release, "build release":
    exec "nimble build --app:gui -d:release --opt:speed"

task deploy, "build&deploy":
    exec "nimble build --app:gui -d:release --opt:speed"
    cpFile "./main.exe","d:\\projects\\slnSelector.exe"