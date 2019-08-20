type
    SolutionItem* = object
        id*: int
        label*: string
        fullPath*: string
        isVisible*: bool
        rank*: int

proc `<`* (self: SolutionItem, other: SolutionItem): bool =
    return system.cmp((self.rank, self.label), (other.rank, other.label)) < 0

proc `<=`* (self: SolutionItem, other: SolutionItem): bool =
    return system.cmp((self.rank, self.label), (other.rank, other.label)) <= 0