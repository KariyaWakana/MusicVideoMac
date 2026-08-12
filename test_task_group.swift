import Foundation

func test() async {
    print("Starting")
    let result = await withTaskGroup(of: String?.self) { group in
        group.addTask {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return "Task 1"
        }
        
        group.addTask {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            return "Timeout"
        }
        
        let first = await group.next()!
        print("Got first: \(first ?? "nil")")
        return first
    }
    print("Finished with result: \(result ?? "nil")")
}

Task {
    await test()
    exit(0)
}
RunLoop.main.run()
