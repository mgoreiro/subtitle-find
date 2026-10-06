import Foundation
import Observation

@MainActor
@Observable
final class Library {
    var items: [VideoItem] = []
    var isRunning = false
    var notice: String?
    private var task: Task<Void, Never>?
    /// Proveedores sin cuota de descargas en esta tanda → mensaje del servidor.
    private var exhausted: [String: String] = [:]

    var doneCount: Int { items.filter(\.isFinished).count }

    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url))
        let new = VideoScanner.collect(urls).filter { !known.contains($0) }
        if new.isEmpty {
            if items.isEmpty || urls.contains(where: { !known.contains($0) }) {
                notice = L("notice.novideos")
            }
            return
        }
        items += new.map(VideoItem.init)
        start()
    }

    func clear() {
        cancel()
        items.removeAll()
    }

    func retryFailed() {
        for item in items {
            for kind in SubKind.allCases {
                switch item[kind] {
                case .notFound, .failed, .quota: item[kind] = .pending
                default: break
                }
            }
        }
        start()
    }

    func cancel() { task?.cancel() }

    func start() {
        guard !isRunning else { return }
        let providers = Self.makeProviders()
        guard !providers.isEmpty else {
            notice = L("notice.nokeys")
            return
        }
        isRunning = true
        exhausted = [:]
        task = Task {
            while !Task.isCancelled, let item = items.first(where: \.hasPending) {
                await process(item, providers)
                if providers.allSatisfy({ exhausted[$0.name] != nil }) {
                    // Sin cuota en ningún proveedor: no tiene sentido seguir pidiendo.
                    let msg = exhausted.values.first ?? ""
                    for it in items { for k in SubKind.allCases where it[k] == .pending { it[k] = .quota(msg) } }
                    let detail = msg.components(separatedBy: " ts=").first ?? msg
                    notice = LF("notice.quota", detail)
                    break
                }
            }
            isRunning = false
        }
    }

    private static func makeProviders() -> [SubtitleProvider] {
        let d = UserDefaults.standard
        func s(_ k: String) -> String { (d.string(forKey: k) ?? "").trimmingCharacters(in: .whitespaces) }
        var p: [SubtitleProvider] = []
        if !s("osApiKey").isEmpty {
            p.append(OpenSubtitlesProvider(apiKey: s("osApiKey"), username: s("osUser"), password: s("osPass")))
        }
        if !s("subdlKey").isEmpty { p.append(SubDLProvider(apiKey: s("subdlKey"))) }
        return p
    }

    private func process(_ item: VideoItem, _ providers: [SubtitleProvider]) async {
        let overwrite = UserDefaults.standard.bool(forKey: "overwrite")
        let url = item.url
        var info = NameParser.parse(url)
        let fileName = url.deletingPathExtension().lastPathComponent

        var hash: String?
        var needHash = false
        for kind in SubKind.allCases where item[kind] == .pending {
            if overwrite || !FileManager.default.fileExists(atPath: kind.outputURL(for: url).path) { needHash = true }
        }
        if needHash {
            for kind in SubKind.allCases where item[kind] == .pending { item[kind] = .working(L("state.hash")) }
            hash = await Task.detached { MovieHash.compute(url) }.value
            for kind in SubKind.allCases where item[kind] == .working(L("state.hash")) { item[kind] = .working(L("state.imdb")) }
            await resolveIMDB(&info, item: item)
        }

        for kind in SubKind.allCases where item[kind] == .pending || { if case .working = item[kind] { return true }; return false }() {
            if Task.isCancelled { item[kind] = .pending; continue }
            let target = kind.outputURL(for: url)
            if !overwrite, FileManager.default.fileExists(atPath: target.path) {
                item[kind] = .skipped(L("state.exists"))
                continue
            }
            item[kind] = .working(L("state.searching"))
            item[kind] = await fetch(kind, item: item, target: target, info: info, fileName: fileName,
                                     hash: hash, providers: providers)
        }
    }

    /// Orden: id fijado a mano → id explícito (carpeta/.nfo) → resolución por título en IMDB.
    private func resolveIMDB(_ info: inout MediaInfo, item: VideoItem) async {
        if let id = item.imdbOverride {
            info.imdbID = id
            item.imdbLabel = "\(IMDB.format(id)) \(L("imdb.manual"))"
        } else if let id = IMDB.explicitID(for: item.url, isEpisode: info.isEpisode) {
            info.imdbID = id
            item.imdbLabel = "\(IMDB.format(id)) \(L("imdb.explicit"))"
        } else if let m = await IMDBResolver.shared.resolve(info) {
            info.imdbID = m.id
            item.imdbLabel = "\(m.title) · \(IMDB.format(m.id))"
        } else {
            item.imdbLabel = nil
        }
    }

    /// Fija a mano el id de IMDB (el de la serie en episodios) y repite la búsqueda.
    func setIMDB(_ item: VideoItem, text: String) {
        guard let id = IMDB.parseID(text) else {
            notice = L("notice.badimdb")
            return
        }
        item.imdbOverride = id
        for kind in SubKind.allCases where !{ if case .saved = item[kind] { return true }; return false }() {
            item[kind] = .pending
        }
        start()
    }

    private func fetch(_ kind: SubKind, item: VideoItem, target: URL, info: MediaInfo, fileName: String,
                       hash: String?, providers: [SubtitleProvider]) async -> SubState {
        var errors: [String] = []
        for p in providers where exhausted[p.name] == nil {
            if Task.isCancelled { return .pending }
            item[kind] = .working(LF("state.searching.in", p.name))
            do {
                var cands = try await p.search(info: info, fileName: fileName, hash: hash, kind: kind)
                for i in cands.indices { cands[i].score = Scoring.score(cands[i], fileName: fileName, kind: kind) }
                cands.sort { $0.score > $1.score }
                for c in cands.prefix(3) {
                    item[kind] = .working(LF("state.downloading", p.name))
                    do {
                        let data = try await p.download(c, info: info, fileName: fileName, kind: kind)
                        guard let text = SubtitleText.decode(data), SubtitleText.looksLikeSRT(text) else { continue }
                        try Data(text.utf8).write(to: target, options: .atomic)
                        return .saved(p.name)
                    } catch is CancellationError {
                        return .pending
                    } catch let e as ProviderError {
                        errors.append("\(p.name): \(e.localizedDescription)")
                        if case .quota(let m) = e { exhausted[p.name] = m; break }
                    } catch {
                        errors.append("\(p.name): \(error.localizedDescription)")
                    }
                }
            } catch is CancellationError {
                return .pending
            } catch {
                errors.append("\(p.name): \(error.localizedDescription)")
            }
        }
        if !providers.isEmpty, providers.allSatisfy({ exhausted[$0.name] != nil }) {
            return .quota(exhausted.values.first ?? "")
        }
        return errors.isEmpty ? .notFound : .failed(errors.joined(separator: " · "))
    }
}
