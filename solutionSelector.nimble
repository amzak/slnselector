import os
# Package

version       = "0.1.0"
author        = "amzak"
description   = "tiny tool for opening Visual Studio solution with search-as-you-type"
license       = "MIT"
srcDir        = "src"
bin           = @["main"]

# Dependencies
requires "nim >= 1.0.0",
    "bearlibterminal"

const
    deployPath = "d:\\projects"
    outputDebugExe = "slnselectordebug.exe"
    outputReleaseExe = "slnselector.exe"

task buildDebug, "build":
    exec "nimble build --app:console -d:debug --debuginfo --lineDir:on --debugger:native --hint:source:on"
    cpFile "./main.exe", outputDebugExe

task debug, "build&run":
    buildDebugTask()
    exec outputDebugExe

task buildRelease, "build release":
    exec "nimble build -y --app:gui -d:release --opt:speed"
    cpFile "./main.exe", outputReleaseExe

task deployDebug, "deployDebug":
    buildDebugTask()
    cpFile outputDebugExe, deployPath / outputDebugExe

task deployRelease, "deployRelease":
    buildReleaseTask()
    cpFile outputReleaseExe, deployPath / outputReleaseExe