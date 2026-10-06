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
        .alert("Subtitle Find", isPresented: Binding(get: { lib.notice != nil }, set: { if !$0 { lib.notice = nil } })) {
            Button("OK") {}
        } message: { Text(lib.notice ?? "") }
    }

    private var keyBanner: some View {
        HStack {
            Image(systemName: "key.fill")
            Text("Configura una API key de OpenSubtitles o SubDL en Ajustes (⌘,) para poder buscar.")
            Spacer()
            SettingsLink { Text("Abrir ajustes") }
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
            Text("Arrastra aquí vídeos o carpetas").font(.title2)
            Text("Buscaré subtítulos en castellano (normales y forzados) y los guardaré junto a cada vídeo.")
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
            Text("\(lib.doneCount) de \(lib.items.count) vídeos")
                .foregroundStyle(.secondary)
            Spacer()
            if lib.isRunning {
                Button("Cancelar") { lib.cancel() }
            } else {
                Button("Reintentar fallidos") { lib.retryFailed() }
            }
            Button("Vaciar lista") { lib.clear() }
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
                Text("IMDB: \(l)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 16) {
                StateBadge(kind: .normal, state: item.normal)
                StateBadge(kind: .forced, state: item.forced)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Fijar id de IMDB…") { idText = item.imdbOverride.map(IMDB.format) ?? ""; askID = true }
            Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
        .alert("Id de IMDB", isPresented: $askID) {
            TextField("tt0804484", text: $idText)
            Button("Buscar") { lib.setIMDB(item, text: idText) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Para series, el id de la serie (no el del episodio). También vale la URL de IMDB.")
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
        case .pending: return "en cola"
        case .working(let s): return s
        case .saved(let p): return "guardado (\(p))"
        case .skipped(let s): return s
        case .notFound: return "no encontrado"
        case .failed: return "error"
        case .quota: return "cuota agotada"
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
            Section("OpenSubtitles.com (recomendado: marca los forzados y busca por hash)") {
                TextField("API key", text: $osKey)
                TextField("Usuario (opcional)", text: $osUser)
                SecureField("Contraseña (opcional)", text: $osPass)
                Link("Crear API key", destination: URL(string: "https://www.opensubtitles.com/consumers")!)
                Text("Sin usuario y contraseña, OpenSubtitles solo permite 5 descargas cada 24 h. Con tu cuenta la cuota es mayor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("SubDL (alternativa)") {
                TextField("API key", text: $subdlKey)
                Link("Crear API key", destination: URL(string: "https://subdl.com/panel/api")!)
            }
            Section {
                Toggle("Sobrescribir subtítulos existentes", isOn: $overwrite)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 470)
    }
}
