import bearlibterminal,
    os,
    osproc,
    strutils,
    strformat,
    algorithm,
    tables,
    encodings,
    unicode,
    appConfig,
    domain,
    state,
    theme,
    options

var
    encodingConverter = open("utf-8", "utf-16")

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

proc getSolutionsList(): auto =
    var items: seq[SolutionItem] = @[]
    var counter: int = 0

    let skipList = [
        "bin",
        "build",
        "packages",
        "tools"
    ]
    let appDir = getAppDir()
    echo "working in ", appDir

    var maxFileLen = 0;
    var maxLabelLen = 0;

    for file in walkDir(appDir, 2, skipList):
        let (_, name, ext) = splitFile(file)
        if ext!=".sln":
            continue
        let label = name.toLower()

        let fileLen = runeLen(file);
        let labelLen = runeLen(label);

        if fileLen > maxFileLen: maxFileLen = fileLen
        if labelLen > maxLabelLen: maxLabelLen = labelLen

        let newItem = SolutionItem(
            id: counter, 
            label: label,
            fullPath: file.replace(appDir, "."), 
            isVisible: true)

        echo label, " ", labelLen
        echo file, " ", fileLen

        items.add(newItem)
        counter += 1

    return (items, maxLabelLen, maxFileLen)

proc render(config: AppConfig, state: AppState): void =

    terminalColor(state.colors.front)
    terminalBackgroundColor(state.colors.back)
    terminalClear()

    discard terminalPrint(newBLPoint(1, 1), &"> {state.inputString}")

    var prevLabel: string
    var renderedItemsCounter = 0

    for solution in state.items:
        if not solution.isVisible:
            continue;

        let frontColor = state.colors.front
        let backColor = state.colors.back

        if state.selectedIndex == solution.id:
            terminalColor(backColor);
            terminalBackgroundColor(frontColor);
        else:
            terminalColor(frontColor);
            terminalBackgroundColor(backColor);

        prevLabel = solution.label
        let order = state.invOrderMap[solution.id]
        let y = order + 2
        discard terminalPrint(newBLPoint(1, BLInt(y)), solution.label)
        renderedItemsCounter += 1
        if y >= config.sizeY.get() - 2:
            break;

    if state.items.len > renderedItemsCounter:
        discard terminalPrint(newBLPoint(1, BLInt(config.sizeY.get() - 1)), &"... and {state.items.len - renderedItemsCounter} more")

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

proc mutateState(state: var AppState): void =
    var buff: seq[char] = @[]

    for inputChar in state.inputChars:
        let littleByte = cast[char](inputChar and 0xff)
        let bigByte = cast[char]((inputChar shr 8) and 0xff)
        buff.add(littleByte)
        buff.add(bigByte)

    let buffStr = toString(buff)
    let newInputString = convert(encodingConverter, buffStr)

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
        let appDir = getAppDir()

        discard startProcess(
            state.executable, 
            workingDir,
            [appDir / selectedItem.fullPath])
        echo "done."
        state.isRunning = false

proc initAppState(config: AppConfig): AppState = 
    var (solutionsList, maxLabelLen, maxFileLen) = getSolutionsList()
    var orderMap = initTable[int, int]()
    var invOrderMap = initTable[int, int]()

    echo maxLabelLen
    echo maxFileLen
    for solution in solutionsList.mitems:
        orderMap[solution.id] = solution.id
        invOrderMap[solution.id] = solution.id
        solution.label = &"{unicode.alignLeft(solution.label, maxLabelLen)} [color=gray]\u2502 {unicode.align(solution.fullPath, maxFileLen)}[/color]"
        echo solution.label

    let max = maxLabelLen + maxFileLen + 5
    discard terminalSet(&"window.size={max}x{config.sizeY.get()}")

    return AppState(
        items: solutionsList,
        colors: (
            front: colorFromName(config.theme.get().front),
            back: colorFromName(config.theme.get().back)
        ),
        orderMap: orderMap,
        invOrderMap: invOrderMap,
        executable: config.executable
    )

discard terminalOpen()
discard terminalSet("window.title='choose project'")

let defaultTheme = AppTheme(
    front: "white",
    back: "black"
)

let defaultYSize = 40

var config: AppConfig
if not tryLoadConfig(config):
    let vsHome = getEnv("VSHOME")
    echo "VSHOME=", vsHome
    config = AppConfig(
        executable: vsHome,
        theme: some(defaultTheme),
        sizeY: some(defaultYSize)
    )

if config.theme.isNone():
    config.theme = some(defaultTheme)

if config.sizeY.isNone():
    config.sizeY = some(defaultYSize)

var appState = initAppState(config)

terminalColor(appState.colors.front);
terminalBackgroundColor(appState.colors.back);

echo &"found {appState.items.len} elements"

var lastInput: int32 = 0;

appState.isRunning = appState.items.len > 0

while appState.isRunning:
    mutateState(appState)
    render(config, appState)
    lastInput = terminalRead()
    case lastInput:
        of TK_CLOSE, TK_ESCAPE:
            break;
        of TK_UP, TK_DOWN:
            handleUpDown(appState, lastInput)
        of TK_BACKSPACE:
            handleBackspace(appState)
        of TK_ENTER:
            handleEnter(appState)
        else:
            discard

    if(terminalCheck(TK_WCHAR)):
        handleKeyInput(appState, terminalState(TK_WCHAR))

encodingConverter.close()
terminalClose()