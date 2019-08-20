import os
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

const
    deployPath = "d:\\projects"
    outputDebugExe = "slnSelectorDebug.exe"
    outputReleaseExe = "slnSelector.exe"

task buildDebug, "build":
    exec "nimble build --app:console -d:debug --debuginfo --lineDir:on --debugger:native"

task debug, "build&run":
    buildDebugTask()
    exec "./main.exe"

task buildRelease, "build release":
    exec "nimble build --app:gui -d:release --opt:speed -y"

task deployDebug, "deployDebug":
    buildDebugTask()
    cpFile "./main.exe", "d:\\projects" / outputDebugExe

task deployRelease, "deployRelease":
    buildReleaseTask()
    cpFile "./main.exe", "d:\\projects" / outputReleaseExe