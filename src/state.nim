import domain,
    bearlibterminal,
    lists

type
    AppState* = object
        items*: seq[SolutionItem]
        orderedList*: DoublyLinkedList[SolutionItem]
        selectedItem*: DoublyLinkedNode[SolutionItem]
        inputChars*: seq[int]
        inputString*: string
        colors*: tuple[
            front: BLColor, 
            back: BLColor
        ]
        isRunning*: bool
        isDataLoaded*: bool
        maxFileLen*: int
        maxLabelLen*: int
        maxVisibleItems*: int