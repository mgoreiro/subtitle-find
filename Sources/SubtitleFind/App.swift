import SwiftUI

@main
struct SubtitleFindApp: App {
    @State private var library = Library()

    var body: some Scene {
        Window("Subtitle Find", id: "main") {
            ContentView()
                .environment(library)
                .onOpenURL { library.add([$0]) }
                .frame(minWidth: 580, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("about.menu")) { Author.showAbout() }
            }
        }
        Settings { SettingsView() }
    }
}
