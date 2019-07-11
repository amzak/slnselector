import bearlibterminal,
    os,
    osproc,
    strutils,
    strformat,
    algorithm,
    tables

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
        inputChars: seq[char]
        inputString: string
        colors: tuple[
            black: BLColor,
            white: BLColor,
            front: BLColor, 
            back: BLColor
        ]
        isRunning: bool
        executable: string

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

proc mutateState(state: var AppState): void =
    let newInputString = toString(state.inputChars)

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
    let incomingChar = cast[char](input);
    if(isAlphaNumeric(incomingChar)):
        state.inputChars.add(incomingChar);

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