import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            SidebarView()
            MetalCityView()
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }
}
