template withStopwatch*(label: string, action: untyped) =
    var blockLabel: string = label
    let start = cpuTime()
    echo "STOPWATCH: started" & blockLabel & " on " & $start
    action
    let elapsed = cpuTime() - start
    echo "STOPWATCH: " & blockLabel & " completed in " & $elapsed & "s"