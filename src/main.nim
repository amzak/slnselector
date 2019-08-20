import bearlibterminal,
    os,
    osproc,
    strutils,
    strformat,
    algorithm,
    encodings,
    unicode,
    appConfig,
    domain,
    state,
    theme,
    options,
    lists

var
    encodingConverter = open("utf-8", "utf-16")
    channel = Channel[SolutionItem]()
    loadingThread: Thread[tuple[dir: string, depth: int]]

proc toString(str: seq[char]): string =
    result = newStringOfCap(len(str))
    for ch in str:
        add(result, ch)

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

proc getSolutionsList(params: tuple[dir: string, depth: int]) {.thread.} =
    var counter: int = 0

    let skipList = [
        "bin",
        "build",
        "packages",
        "tools"
    ]

    let (workingDir, depth) = params

    echo &"working in {workingDir} with depth {depth}"

    for file in walkDir(workingDir, depth, skipList):
        let (_, name, ext) = splitFile(file)
        if ext!=".sln":
            continue
        let label = name.toLower()

        let newItem = SolutionItem(
            id: counter, 
            label: label,
            fullPath: file.replace(workingDir, "."), 
            isVisible: true)

        counter += 1
        channel.send(newItem)
        echo "sent ", newItem.label

proc loadSolutions(thread: var Thread, config: AppConfig) =
    let params: tuple[dir: string, depth: int] = (dir: config.workingDir.get(), depth: config.depth.get())
    thread.createThread(getSolutionsList, params)

proc render(config: AppConfig, state: AppState): void =
    terminalColor(state.colors.front)
    terminalBackgroundColor(state.colors.back)
    terminalClear()

    discard terminalPrint(newBLPoint(1, 1), &"> {state.inputString}")

    if not state.isDataLoaded:
        discard terminalPrint(newBLPoint(1, 2), "loading...")

    var order = 0

    for solutionNode in nodes(state.orderedList):
        let solution = solutionNode.value

        if not solution.isVisible:
            continue;

        let isSelected = solutionNode == state.selectedItem

        let frontColor = state.colors.front
        let backColor = state.colors.back

        if isSelected:
            terminalColor(backColor);
            terminalBackgroundColor(frontColor);
        else:
            terminalColor(frontColor);
            terminalBackgroundColor(backColor);

        let labelRect = newBLRect(1, BLInt(order + 2), BLInt(state.maxLabelLen), 1)
        var size = terminalPrint(labelRect, TK_ALIGN_LEFT, unicode.alignLeft(solution.label, state.maxLabelLen))
        let labelSize = cast[int](size.w)

        let pathRect = newBLRect(BLInt(state.maxLabelLen + 4), BLInt(order + 2), BLInt(state.maxFileLen), 1)
        size = terminalPrint(pathRect, TK_ALIGN_RIGHT, solution.fullPath)
        let pathSize = cast[int](size.w)

        let separatorWidth = state.maxLabelLen + state.maxFileLen + 3 - labelSize - pathSize
        let separatorRect = newBLRect(BLInt(state.maxLabelLen + 1), BLInt(order + 2), BLInt(separatorWidth), 1)
        discard terminalPrint(separatorRect, TK_ALIGN_CENTER , unicode.alignLeft("\u2502", separatorWidth))

        order += 1

    terminalRefresh()

proc computeVisibility(input: string, item: var SolutionItem) =
    var isVisible = false
    if input.len == 0:
        item.isVisible = true
        item.rank = high(int)
        return

    let rank = item.label.find(input)
    isVisible = isVisible or rank >= 0
    item.rank = if rank>=0: rank else: high(int)
    item.isVisible = isVisible

proc computeVisibility(input: string, items: var seq[SolutionItem]): void =
    for item in items.mitems:
        computeVisibility(input, item)

proc sortOrderedList(state: var AppState): void =
    state.orderedList = initDoublyLinkedList[SolutionItem]()

    var counter = 0
    for item in state.items.sortedByIt((it.rank, it.label)):
        if counter > state.maxVisibleItems:
            break
        state.orderedList.append(item)
        counter += 1

    state.selectedItem = state.orderedList.head

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
    sortOrderedList(state)

proc moveSelection(state: var AppState, delta: int): void =
    let direction = delta >= 0
    for i in 1..abs(delta):
        if direction:
            if state.selectedItem.next == nil:
                return
            state.selectedItem = state.selectedItem.next
        else:
            if state.selectedItem.prev == nil:
                return
            state.selectedItem = state.selectedItem.prev
    echo state.selectedItem.value

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

proc handleEnter(config: AppConfig, state: var AppState): void =
    if state.selectedItem != nil:
        let selectedItem = state.selectedItem.value
        echo &"handling selection of {selectedItem.label} {selectedItem.fullPath}"

        let (workingDir, _, _) = splitFile(config.executable)
        let appDir = config.workingDir.get()

        discard startProcess(
            config.executable, 
            workingDir,
            [appDir / selectedItem.fullPath])
        echo "done."
        state.isRunning = false

proc initAppState(config: AppConfig): AppState = 
    let max = 50
    discard terminalSet(&"window.size={max}x{config.sizeY.get()}")

    return AppState(
        items: @[],
        colors: (
            front: colorFromName(config.theme.get().front),
            back: colorFromName(config.theme.get().back)
        ),
        orderedList: initDoublyLinkedList[SolutionItem](),
        maxVisibleItems: config.sizeY.get() - 4
    )

proc addSolution(state: var AppState, solution: var SolutionItem) =
    let fileLen = runeLen(solution.fullPath);
    let labelLen = runeLen(solution.label);

    if fileLen > state.maxFileLen: state.maxFileLen = fileLen
    if labelLen > state.maxLabelLen: state.maxLabelLen = labelLen

    computeVisibility(state.inputString, solution)

    state.items.add(solution)

proc appendOrdered(state: var AppState, solution: var SolutionItem) =
    if state.orderedList.head == nil:
        state.orderedList.append(solution)
        state.selectedItem = state.orderedList.head
        echo "added first"
    else:
        for item in state.orderedList.nodes():
            if item.next == nil:
                state.orderedList.append(solution)
                echo "added last"
                return

            if solution > item.value and solution <= item.next.value:
                let newNext = newDoublyLinkedNode(solution)
                newNext.next = item.next
                newNext.prev = item
                item.next.prev = newNext
                item.next = newNext
                echo &"added {newNext.value.label} after {item.value.label}"
                return

proc recvData(config: AppConfig, state: var AppState) =
    state.isDataLoaded = not loadingThread.running()

    var maxOrdered = state.maxVisibleItems
    var counter: int = 0
    while true:
        var (hasData, solution) = channel.tryRecv()
        if not hasData:
            break
        state.addSolution(solution)
        state.appendOrdered(solution)
        counter += 1

    if state.isDataLoaded:
        var orderedCounter = 0
        for item in nodes(state.orderedList):
            if orderedCounter >= maxOrdered:
                item.next = nil
            orderedCounter += 1

        echo "loading completed"

    if counter == 0:
        return

    let max = state.maxLabelLen + state.maxFileLen + 5
    discard terminalSet(&"window.size={max}x{state.maxVisibleItems + 3}")

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

if config.workingDir.isNone():
    config.workingDir = some(getAppDir())

if config.depth.isNone():
    config.depth = some(2)

open(channel)

loadSolutions(loadingThread, config)

var appState = initAppState(config)

terminalColor(appState.colors.front);
terminalBackgroundColor(appState.colors.back);

var lastInput: int32 = 0;

appState.isRunning = true

while appState.isRunning:
    recvData(config, appState);
    mutateState(appState)
    render(config, appState)

    if appState.isDataLoaded:
        lastInput = terminalRead()
    else:
        if terminalHasInput():
            lastInput = terminalRead()
        else:
            terminalDelay(1);
            continue

    case lastInput:
        of TK_CLOSE, TK_ESCAPE:
            break;
        of TK_UP, TK_DOWN:
            handleUpDown(appState, lastInput)
        of TK_BACKSPACE:
            handleBackspace(appState)
        of TK_ENTER:
            handleEnter(config, appState)
        else:
            discard

    if(terminalCheck(TK_WCHAR)):
        handleKeyInput(appState, terminalState(TK_WCHAR))

encodingConverter.close()
terminalClose()
channel.close()