import SwiftUI

@main
struct CadenceApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PromptListView()
            }
        }
    }
}
