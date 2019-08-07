import 
    os,
    json,
    theme,
    options

type 
    AppConfig* = object
        executable*: string
        theme*: Option[AppTheme]
        sizeY*: Option[int]
        workingDir*: Option[string]

const 
    fileName = "config.json"
    
let fileNameFull = getAppDir() / fileName

proc tryLoadConfig*(config: var AppConfig): bool = 
    if existsFile(fileNameFull):
        let jsonNode = parseFile(fileNameFull)
        config = to(jsonNode, AppConfig)
        return true
    return false
