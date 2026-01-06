import SwiftUI

@main
struct File_CityEntry {
    static func main() {
        if NSClassFromString("XCTestCase") != nil {
            TestApp.main()
        } else {
            File_CityApp.main()
        }
    }
}

struct TestApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Running Tests")
        }
    }
}
