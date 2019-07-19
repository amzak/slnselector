import bearlibterminal,
    os,
    osproc,
    strutils,
    strformat,
    algorithm,
    tables,
    sequtils,
    encodings,
    endians

type
    SolutionItem = tuple
        id: int
        label: string
        fullPath: string
        isVisible: bool
        rank: int

    AppConfig = tuple
        white: BLColor
        black: BLColor
        front: BLColor
        back: BLColor
        executable: string

    AppState = object
        items: seq[SolutionItem]
        orderMap: Table[int, int]
        invOrderMap: Table[int, int]
        selectedIndex: int
        inputChars: seq[int]
        inputString: string
        colors: tuple[
            black: BLColor,
            white: BLColor,
            front: BLColor, 
            back: BLColor
        ]
        isRunning: bool
        executable: string

    CodePage = distinct int32

const
    vsPath = "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Professional\\Common7\\IDE\\devenv.exe"

proc toString(str: seq[char]): string =
    result = newStringOfCap(len(str))
    for ch in str:
        add(result, ch)

proc setVisibility(solutionItem: var SolutionItem, isVisible: bool): void =
    solutionItem.isVisible = isVisible

proc walkDirProc(dir: string, depth: int, skipList: openArray[string]): seq[string] =
    result = @[]
    for kind, path in walkDir(dir):
        case kind:
            of pcDir:
                if depth == 0 or (lastPathPart(path) in skipList):
                    continue
                for item in walkDirProc(path, depth - 1, skipList):
                    result.add(item)
            of pcFile:
                result.add(path)
            else:
                discard

iterator walkDir(dir: string, depth: int, skipList: openArray[string]): string =
    for path in walkDirProc(dir, depth, skipList):
        yield path

proc getSolutionsList(): seq[SolutionItem] =
    result = @[]
    var counter: int = 0

    let skipList = [
        "bin",
        "build",
        "packages",
        "tools"
    ]
    let appDir = getAppDir()
    echo "working in ", appDir
    for file in walkDir(appDir, 2, skipList):
        let (dir, name, ext) = splitFile(file)
        if ext!=".sln":
            continue
        let newItem = (id: counter, label: name.toLower(), fullPath: file, isVisible: true, rank: 0)
        result.add(newItem)
        counter += 1

proc render(state: AppState): void =

    terminalColor(state.colors.white)
    terminalBackgroundColor(state.colors.black)
    terminalClear()

    discard terminalPrint(newBLPoint(1, 1), &"> {state.inputString}")

    for solution in state.items:
        if not solution.isVisible:
            continue;

        if state.selectedIndex == solution.id:
            terminalColor(state.colors.back);
            terminalBackgroundColor(state.colors.front);
        else:
            terminalColor(state.colors.front);
            terminalBackgroundColor(state.colors.back);
        let order = state.invOrderMap[solution.id]
        discard terminalPrint(newBLPoint(1, BLInt(order) + 2), solution.label)
    
    terminalRefresh()

proc computeVisibility(input: string, items: var seq[SolutionItem]): void =
    for item in items.mitems:
        var isVisible = false
        if input.len == 0:
            isVisible = true

        let rank = item.label.find(input)
        isVisible = isVisible or rank >= 0

        item.rank = if rank>=0: rank else: high(int)
        item.setVisibility(isVisible)

proc sortInvOrderMap(state: var AppState): void =
    var counter = 0
    for item in state.items.sortedByIt((it.rank, it.label)):
        state.invOrderMap[item.id] = counter
        state.orderMap[counter] = item.id
        counter += 1

    state.selectedIndex = state.orderMap[0]

proc multiByteToWideChar(
    codePage: CodePage,
    dwFlags: int32,
    lpMultiByteStr: cstring,
    cbMultiByte: cint,
    lpWideCharStr: cstring,
    cchWideChar: cint): cint {.
        stdcall, importc: "MultiByteToWideChar", dynlib: "kernel32".}
          
proc wideCharToMultiByte(
    codePage: CodePage,
    dwFlags: int32,
    lpWideCharStr: cstring,
    cchWideChar: cint,
    lpMultiByteStr: cstring,
    cbMultiByte: cint,
    lpDefaultChar: cstring=nil,
    lpUsedDefaultChar: pointer=nil): cint {.
        stdcall, importc: "WideCharToMultiByte", dynlib: "kernel32".}

proc convertToWideString(codePage: CodePage, s: cstring): string =
    ## converts `s` to `destEncoding` that was given to the converter `c`. It
    ## assumed that `s` is in `srcEncoding`.
    # educated guess of capacity:
    var cap = s.len + s.len shr 2
    result = newString(s.len*2)
    echo "cbMultiByte=",cint(s.len)
    # convert to utf-16 LE
    var m = multiByteToWideChar(codePage,
                                dwFlags = 0'i32,
                                lpMultiByteStr = s,
                                cbMultiByte = cint(s.len),
                                lpWideCharStr = cstring(result),
                                cchWideChar = cint(cap))
    echo "m=", m
    echo "error=", osLastError()
    if m == 0:
        # try again; ask for capacity:
        cap = multiByteToWideChar(codePage,
                                dwFlags = 0'i32,
                                lpMultiByteStr = s,
                                cbMultiByte = cint(s.len),
                                lpWideCharStr = nil,
                                cchWideChar = cint(0))
        echo "cap=", cap
        echo "error=", osLastError()
        # and do the conversion properly:
        result = newString(cap*2)
        m = multiByteToWideChar(codePage,
                                dwFlags = 0'i32,
                                lpMultiByteStr = s,
                                cbMultiByte = cint(s.len),
                                lpWideCharStr = cstring(result),
                                cchWideChar = cint(cap))
        echo "error=", osLastError()
        if m == 0: raiseOSError(osLastError())
        setLen(result, m*2)
    elif m <= cap:
        setLen(result, m*2)
    else:
        assert(false) # cannot happen

proc convertFromWideString(codePage: CodePage, s: cstring): string =
    # if already utf-16 LE, no further need to do something:
    if int(codePage) == 1200: 
        return
    # otherwise the fun starts again:
    let charCount = s.len div 2
    var cap = s.len + s.len shr 2
    result = newString(cap)
    var m = wideCharToMultiByte(
        codePage,
        dwFlags = 0'i32,
        lpWideCharStr = s,
        cchWideChar = cint(charCount),
        lpMultiByteStr = cstring(result),
        cbMultiByte = cap.cint)
    if m == 0:
        # try again; ask for capacity:
        cap = wideCharToMultiByte(
        codePage,
        dwFlags = 0'i32,
        lpWideCharStr = s,
        cchWideChar = cint(charCount),
        lpMultiByteStr = nil,
        cbMultiByte = cint(0))
        # and do the conversion properly:
        result = newString(cap)
        m = wideCharToMultiByte(
        codePage,
        dwFlags = 0'i32,
        lpWideCharStr = s,
        cchWideChar = cint(charCount),
        lpMultiByteStr = cstring(result),
        cbMultiByte = cap.cint)
        if m == 0: raiseOSError(osLastError())
        setLen(result, m)
    elif m <= cap:
        setLen(result, m)
    else:
        assert(false) # cannot happen

proc convert(utf16: string): string =
    ## converts `s` to `destEncoding` that was given to the converter `c`. It
    ## assumed that `s` is in `srcEncoding`.

    # special case: empty string: needed because MultiByteToWideChar
    # return 0 in case of error:
    let s = utf16
    let srcCodePage = CodePage(1200)
    let dstCodePage = CodePage(65001)
    if s.len == 0: return ""
    # educated guess of capacity:
    var cap = s.len + s.len shr 2
    result = newString(s.len*2)
    echo "cbMultiByte=",cint(s.len)
    # convert to utf-16 LE
    var m = multiByteToWideChar(codePage = srcCodePage, dwFlags = 0'i32,
                                lpMultiByteStr = cstring(s),
                                cbMultiByte = cint(s.len),
                                lpWideCharStr = cstring(result),
                                cchWideChar = cint(cap))
    echo "m=", m
    if m == 0:
        # try again; ask for capacity:
        cap = multiByteToWideChar(codePage = srcCodePage, 
                                dwFlags = 0'i32,
                                lpMultiByteStr = cstring(s),
                                cbMultiByte = cint(s.len),
                                lpWideCharStr = nil,
                                cchWideChar = cint(0))
        echo "cap=", cap
        # and do the conversion properly:
        result = newString(cap*2)
        m = multiByteToWideChar(codePage = srcCodePage, dwFlags = 0'i32,
                                lpMultiByteStr = cstring(s),
                                cbMultiByte = cint(s.len),
                                lpWideCharStr = cstring(result),
                                cchWideChar = cint(cap))
        echo "error=", osLastError()
        if m == 0: raiseOSError(osLastError())
        setLen(result, m*2)
    elif m <= cap:
        setLen(result, m*2)
    else:
        assert(false) # cannot happen

    # if already utf-16 LE, no further need to do something:
    if int(dstCodePage) == 1200: return
    # otherwise the fun starts again:
    cap = s.len + s.len shr 2
    var res = newString(cap)
    m = wideCharToMultiByte(
        codePage = dstCodePage,
        dwFlags = 0'i32,
        lpWideCharStr = cstring(result),
        cchWideChar = cint(result.len div 2),
        lpMultiByteStr = cstring(res),
        cbMultiByte = cap.cint)
    if m == 0:
        # try again; ask for capacity:
        cap = wideCharToMultiByte(
        codePage = dstCodePage,
        dwFlags = 0'i32,
        lpWideCharStr = cstring(result),
        cchWideChar = cint(result.len div 2),
        lpMultiByteStr = nil,
        cbMultiByte = cint(0))
        # and do the conversion properly:
        res = newString(cap)
        m = wideCharToMultiByte(
        codePage = dstCodePage,
        dwFlags = 0'i32,
        lpWideCharStr = cstring(result),
        cchWideChar = cint(result.len div 2),
        lpMultiByteStr = cstring(res),
        cbMultiByte = cap.cint)
        if m == 0: raiseOSError(osLastError())
        setLen(res, m)
        result = res
    elif m <= cap:
        setLen(res, m)
        result = res
    else:
        assert(false) # cannot happen

proc convert2(codePageFrom: CodePage, codePageTo: CodePage, s: string): string =
    if s.len == 0: return ""

    let unsupportedCodePages = [
        1201,
        12000,
        12001
    ]

    if int(codePageFrom) in unsupportedCodePages:
        let message = "encoding from " & codePageToName(codePageFrom) & " is not supported"
        raise newException(EncodingError, message)

    let intermidiate = if int(codePageFrom) == 1200: s else: convertToWideString(codePageFrom, s)
    return convertFromWideString(codePageTo, intermidiate)

proc mutateState(state: var AppState): void =
    var buff: seq[char] = @[]

    for inputChar in state.inputChars:
        let littleByte = cast[char](inputChar and 0xff)
        let bigByte = cast[char]((inputChar shr 8) and 0xff)
        buff.add(bigByte)
        buff.add(littleByte)

    let buffStr = toString(buff)
    let newInputString = convert2(CodePage(1201), CodePage(65001), buffStr)

    echo newInputString

    if cmp(newInputString, state.inputString) == 0:
        return

    state.inputString = newInputString
    computeVisibility(state.inputString, state.items)
    sortInvOrderMap(state)

proc moveSelection(state: var AppState, delta: int): void =
    var order = state.invOrderMap[state.selectedIndex]

    order += delta
    let count = len(state.items)
    if order >= count:
        order = count - 1
    if order < 0:
        order = 0
    
    state.selectedIndex = state.orderMap[order]

proc handleUpDown(state: var AppState, input: int32): void = 
    var delta = 0
    case input:
        of TK_UP:
            delta = -1
        of TK_DOWN:
            delta = 1
        else:
            return
    moveSelection(state, delta);

proc handleKeyInput(state: var AppState, input: int32): void = 
    echo "input=",input
    state.inputChars.add(input)

proc handleBackspace(state: var AppState): void =
    let len = state.inputChars.len
    if len > 0:
        state.inputChars.del(len - 1)

proc handleEnter(state: var AppState): void =
    if state.selectedIndex >= 0:
        let selectedItem = state.items[state.selectedIndex]
        echo &"handling selection of {selectedItem.label} {selectedItem.fullPath}"

        let (workingDir, _, _) = splitFile(state.executable)

        discard startProcess(state.executable, 
            workingDir,
            [selectedItem.fullPath])
        echo "done."
        state.isRunning = false

proc initAppState(config: AppConfig): AppState = 
    let solutionsList = getSolutionsList()
    var orderMap = initTable[int, int]()
    var invOrderMap = initTable[int, int]()

    var maxLen = 0;
    for solution in solutionsList:
        orderMap[solution.id] = solution.id
        invOrderMap[solution.id] = solution.id
        let len = terminalMeasure(solution.label).w
        if maxLen < len: maxLen = len

    discard terminalSet(&"window.size={maxLen+5}x40")

    return AppState(
        items: solutionsList,
        colors: (
            black: config.black,
            white: config.white,
            front: config.front, 
            back: config.back
        ),
        orderMap: orderMap,
        invOrderMap: invOrderMap,
        executable: config.executable
    )

let termid = terminalOpen()
discard terminalSet("window.title='choose project'")

let white = colorFromName("white")
let black = colorFromName("black")

terminalColor(white);
terminalBackgroundColor(black);

let frontColor = terminalGetCurrentColor();
let backColor = terminalGetCurrentBackgroundColor()

let config: AppConfig = (
    white, 
    black, 
    frontColor, 
    backColor,
    vsPath)
var state = initAppState(config)
echo &"found {state.items.len} elements"

var lastInput: int32 = 0;

state.isRunning = state.items.len > 0

while state.isRunning:
    mutateState(state)
    render(state)
    lastInput = terminalRead()
    case lastInput:
        of TK_CLOSE, TK_ESCAPE:
            break;
        of TK_UP, TK_DOWN:
            handleUpDown(state, lastInput)
        of TK_BACKSPACE:
            handleBackspace(state)
        of TK_ENTER:
            handleEnter(state)
        else:
            discard

    if(terminalCheck(TK_WCHAR)):
        handleKeyInput(state, terminalState(TK_WCHAR))

terminalClose()