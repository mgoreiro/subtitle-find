import SwiftUI

struct ContentView: View {
    @Environment(Library.self) private var lib
    @AppStorage("osApiKey") private var osKey = ""
    @AppStorage("subdlKey") private var subdlKey = ""
    @State private var targeted = false

    private var hasKeys: Bool { !osKey.isEmpty || !subdlKey.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if !hasKeys { keyBanner }
            if lib.items.isEmpty {
                placeholder
            } else {
                List(lib.items) { RowView(item: $0) }
                    .listStyle(.inset)
                Divider()
                footer
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            lib.add(urls)
            return true
        } isTargeted: { targeted = $0 }
        .overlay {
            if targeted && !lib.items.isEmpty {
                RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 3).padding(4)
            }
        }
        .toolbar {
            ToolbarItem { SettingsLink { Image(systemName: "gearshape") } }
        }
        .alert(L("app.name"), isPresented: Binding(get: { lib.notice != nil }, set: { if !$0 { lib.notice = nil } })) {
            Button(L("ok")) {}
        } message: { Text(lib.notice ?? "") }
    }

    private var keyBanner: some View {
        HStack {
            Image(systemName: "key.fill")
            Text(L("ui.banner"))
            Spacer()
            SettingsLink { Text(L("ui.openSettings")) }
        }
        .font(.callout)
        .padding(10)
        .background(.yellow.opacity(0.2))
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 54))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            Text(L("ui.drop.title")).font(.title2)
            Text(L("ui.drop.desc"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(targeted ? Color.accentColor : .secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(16)
        }
    }

    private var footer: some View {
        HStack {
            if lib.isRunning { ProgressView().controlSize(.small) }
            Text(LF("ui.progress", lib.doneCount, lib.items.count))
                .foregroundStyle(.secondary)
            Spacer()
            if lib.isRunning {
                Button(L("common.cancel")) { lib.cancel() }
            } else {
                Button(L("ui.retry")) { lib.retryFailed() }
            }
            Button(L("ui.clear")) { lib.clear() }
        }
        .padding(10)
    }
}

struct RowView: View {
    @Environment(Library.self) private var lib
    let item: VideoItem
    @State private var askID = false
    @State private var idText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Text(item.url.deletingLastPathComponent().path)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            if let l = item.imdbLabel {
                Text(LF("ui.imdb.line", l)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 16) {
                StateBadge(kind: .normal, state: item.normal)
                StateBadge(kind: .forced, state: item.forced)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(L("ctx.setimdb")) { idText = item.imdbOverride.map(IMDB.format) ?? ""; askID = true }
            Button(L("ctx.reveal")) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
        .alert(L("alert.imdb.title"), isPresented: $askID) {
            TextField("tt0804484", text: $idText)
            Button(L("alert.imdb.search")) { lib.setIMDB(item, text: idText) }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("alert.imdb.msg"))
        }
    }
}

struct StateBadge: View {
    let kind: SubKind
    let state: SubState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(color)
            Text("\(kind.label): \(text)").font(.caption).lineLimit(1)
        }
        .help(help)
    }

    private var text: String {
        switch state {
        case .pending: return L("state.queued")
        case .working(let s): return s
        case .saved(let p): return LF("state.saved", p)
        case .skipped(let s): return s
        case .notFound: return L("state.notfound")
        case .failed: return L("state.error")
        case .quota: return L("state.quota")
        }
    }

    private var help: String {
        switch state {
        case .failed(let m), .quota(let m): return m
        default: return ""
        }
    }

    private var symbol: String {
        switch state {
        case .pending: return "clock"
        case .working: return "arrow.triangle.2.circlepath"
        case .saved: return "checkmark.circle.fill"
        case .skipped: return "arrow.uturn.forward.circle"
        case .notFound: return "questionmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .quota: return "hourglass"
        }
    }

    private var color: Color {
        switch state {
        case .saved: return .green
        case .failed: return .red
        case .notFound, .quota: return .orange
        default: return .secondary
        }
    }
}

struct SettingsView: View {
    @AppStorage("osApiKey") private var osKey = ""
    @AppStorage("osUser") private var osUser = ""
    @AppStorage("osPass") private var osPass = ""
    @AppStorage("subdlKey") private var subdlKey = ""
    @AppStorage("overwrite") private var overwrite = false

    var body: some View {
        Form {
            Section(L("settings.os.title")) {
                TextField(L("settings.apikey"), text: $osKey)
                TextField(L("settings.user"), text: $osUser)
                SecureField(L("settings.pass"), text: $osPass)
                Link(L("settings.createkey"), destination: URL(string: "https://www.opensubtitles.com/consumers")!)
                Text(L("settings.os.note"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("settings.subdl.title")) {
                TextField(L("settings.apikey"), text: $subdlKey)
                Link(L("settings.createkey"), destination: URL(string: "https://subdl.com/panel/api")!)
            }
            Section {
                Toggle(L("settings.overwrite"), isOn: $overwrite)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 470)
    }
}
