import tables,
    domain,
    bearlibterminal

type
    AppState* = object
        items*: seq[SolutionItem]
        orderMap*: Table[int, int]
        invOrderMap*: Table[int, int]
        selectedIndex*: int
        inputChars*: seq[int]
        inputString*: string
        colors*: tuple[
            front: BLColor, 
            back: BLColor
        ]
        isRunning*: bool
        isDataLoaded*: bool