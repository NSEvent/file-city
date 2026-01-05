import SwiftUI

struct SidebarView: View {
    var body: some View {
        List {
            Text("Root")
        }
        .listStyle(SidebarListStyle())
    }
}
