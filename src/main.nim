import bearlibterminal,
    os,
    osproc,
    strutils,
    strformat,
    algorithm,
    tables,
    encodings,
    unicode

type
    SolutionItem = object
        id: int
        label: string
        fullPath: string
        isVisible: bool
        rank: int

    AppConfig = object
        white: BLColor
        black: BLColor
        front: BLColor
        back: BLColor
        executable: string
        size: tuple[width: int, height: int]

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

        if filelen > maxFileLen: maxFileLen = filelen
        if labellen > maxLabelLen: maxLabelLen = labellen

        let newItem = SolutionItem(
            id: counter, 
            label: label,
            fullPath: file.replace(appDir, "."), 
            isVisible: true)

        echo label, " ", labellen
        echo file, " ", filelen

        items.add(newItem)
        counter += 1

    return (items, maxLabelLen, maxFileLen)

proc render(config: AppConfig, state: AppState): void =

    terminalColor(state.colors.white)
    terminalBackgroundColor(state.colors.black)
    terminalClear()

    discard terminalPrint(newBLPoint(1, 1), &"> {state.inputString}")

    var prevLabel: string
    var renderedItemsCounter = 0

    for solution in state.items:
        if not solution.isVisible:
            continue;

        if state.selectedIndex == solution.id:
            terminalColor(state.colors.back);
            terminalBackgroundColor(state.colors.front);
        else:
            terminalColor(state.colors.front);
            terminalBackgroundColor(state.colors.back);

        prevLabel = solution.label
        let order = state.invOrderMap[solution.id]
        let y = order + 2
        discard terminalPrint(newBLPoint(1, BLInt(y)), solution.label)
        renderedItemsCounter += 1
        if y >= config.size.height - 2:
            break;

    if state.items.len > renderedItemsCounter:
        discard terminalPrint(newBLPoint(1, BLInt(config.size.height - 1)), &"... and {state.items.len - renderedItemsCounter} more")

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
    var max = 0;
    for solution in solutionsList.mitems:
        orderMap[solution.id] = solution.id
        invOrderMap[solution.id] = solution.id
        solution.label = &"{strutils.alignLeft(solution.label, maxLabelLen)} [color=gray]\u2502 {strutils.align(solution.fullPath, maxFileLen)}[/color]"
        echo solution.label

        if max < solution.label.len: max = solution.label.len

    discard terminalSet(&"window.size={max+1}x{config.size.height}")

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

discard terminalOpen()
discard terminalSet("window.title='choose project'")

let white = colorFromName("white")
let black = colorFromName("black")

terminalColor(white);
terminalBackgroundColor(black);

let frontColor = terminalGetCurrentColor();
let backColor = terminalGetCurrentBackgroundColor()

let vsHome = getEnv("VSHOME")
echo "VSHOME=", vsHome
let config:AppConfig = AppConfig(
    white: white, 
    black: black, 
    front: frontColor, 
    back: backColor, 
    executable: vsHome,
    size: (0, 40))

var state = initAppState(config)
echo &"found {state.items.len} elements"

var lastInput: int32 = 0;

state.isRunning = state.items.len > 0

while state.isRunning:
    mutateState(state)
    render(config, state)
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

encodingConverter.close()
terminalClose()