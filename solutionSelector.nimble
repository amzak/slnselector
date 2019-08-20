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
    outputDebugExe = "slnselectordebug.exe"
    outputReleaseExe = "slnselector.exe"

task buildDebug, "build":
    exec "nimble build --app:console -d:debug --debuginfo --lineDir:on --debugger:native"
    cpFile "./main.exe", outputDebugExe

task debug, "build&run":
    buildDebugTask()
    exec "./main.exe"

task buildRelease, "build release":
    exec "nimble build -y --app:gui -d:release --opt:speed"
    cpFile "./main.exe", outputReleaseExe

task deployDebug, "deployDebug":
    buildDebugTask()
    cpFile outputDebugExe, "d:\\projects" / outputDebugExe

task deployRelease, "deployRelease":
    buildReleaseTask()
    cpFile outputReleaseExe, "d:\\projects" / outputReleaseExe