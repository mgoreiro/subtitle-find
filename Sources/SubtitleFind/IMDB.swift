import Foundation

enum IMDB {
    static func format(_ id: Int) -> String { String(format: "tt%07d", id) }

    /// Acepta "tt0804484", "804484" o una URL de imdb.com.
    static func parseID(_ text: String) -> Int? {
        if let m = text.range(of: #"tt(\d{6,9})"#, options: .regularExpression) {
            return Int(text[m].dropFirst(2))
        }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= 5 && t.allSatisfy(\.isNumber) ? Int(t) : nil
    }

    /// Busca un id explícito: en carpetas (`{imdb-tt…}`) o en un .nfo junto al vídeo.
    /// En episodios solo se usan carpetas y `tvshow.nfo`, porque el .nfo del episodio lleva el id del episodio.
    static func explicitID(for video: URL, isEpisode: Bool) -> Int? {
        let fm = FileManager.default
        var dirs: [URL] = []
        var d = video.deletingLastPathComponent()
        for _ in 0..<3 { dirs.append(d); d = d.deletingLastPathComponent() }

        var names = dirs.prefix(2).map(\.lastPathComponent)
        if !isEpisode { names.insert(video.deletingPathExtension().lastPathComponent, at: 0) }
        for n in names { if let id = parseID(n), n.contains("tt") { return id } }

        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension.lowercased() == "nfo" {
                let base = f.deletingPathExtension().lastPathComponent.lowercased()
                let ok = isEpisode ? base == "tvshow"
                                   : (dir == dirs[0] && (base == "movie" || base == video.deletingPathExtension().lastPathComponent.lowercased()))
                guard ok, let h = try? FileHandle(forReadingFrom: f),
                      let data = try? h.read(upToCount: 65536), let text = String(data: data, encoding: .utf8),
                      let m = text.range(of: #"tt\d{6,9}"#, options: .regularExpression) else { continue }
                return parseID(String(text[m]))
            }
        }
        return nil
    }
}

/// Traduce título → id de IMDB con el endpoint de sugerencias de IMDB (no oficial, sin clave).
actor IMDBResolver {
    static let shared = IMDBResolver()

    struct Match { let id: Int; let title: String }
    private var cache: [String: Match] = [:]
    private var misses = Set<String>()

    func resolve(_ info: MediaInfo) async -> Match? {
        let key = "\(info.title.lowercased())|\(info.year ?? 0)|\(info.isEpisode)"
        if let c = cache[key] { return c }
        if misses.contains(key) { return nil }

        let q = info.title.lowercased()
        guard let first = q.first(where: { $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let enc = q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://v3.sg.media-imdb.com/suggestion/\(first)/\(enc).json") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, http) = try? await HTTP.send(req), http.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = obj["d"] as? [[String: Any]] else { return nil } // fallo de red: no se cachea

        let types: Set<String> = info.isEpisode ? ["tvSeries", "tvMiniSeries"] : ["movie", "tvMovie"]
        let candidates = results.filter { types.contains(($0["qid"] as? String) ?? "") && $0["id"] is String }
        func match(_ r: [String: Any]) -> Match? {
            guard let id = parseID(r["id"] as? String ?? "") else { return nil }
            return Match(id: id, title: (r["l"] as? String) ?? info.title)
        }
        // IMDB ordena por relevancia/popularidad; si conocemos el año, preferimos el que coincida (±1).
        let byYear = info.year.flatMap { y in
            candidates.first { r in (r["y"] as? Int).map { abs($0 - y) <= 1 } ?? false }
        }
        if let r = byYear ?? candidates.first, let m = match(r) {
            cache[key] = m
            return m
        }
        misses.insert(key)
        return nil
    }

    private func parseID(_ s: String) -> Int? { IMDB.parseID(s) }
}
