import Foundation

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    /// Reintenta con espera en 429 (rate limit).
    static func send(_ req: URLRequest, retries: Int = 3) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ProviderError.bad("Sin respuesta del servidor") }
            if http.statusCode == 429, attempt < retries {
                let wait = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(2 << attempt)
                try await Task.sleep(for: .seconds(min(wait, 30)))
                attempt += 1
                continue
            }
            return (data, http)
        }
    }
}

// MARK: - OpenSubtitles.com (REST v1)

final class OpenSubtitlesProvider: SubtitleProvider, @unchecked Sendable {
    let name = "OpenSubtitles"
    private static let userAgent = "SubtitleFind v1.0"
    private let apiKey: String
    private let username: String
    private let password: String
    private var token: String?
    private var host = "api.opensubtitles.com"
    private var loginTried = false
    private var loginNote: String?

    init(apiKey: String, username: String, password: String) {
        self.apiKey = apiKey; self.username = username; self.password = password
    }

    private func call(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                      json: [String: Any]? = nil) async throws -> [String: Any] {
        var c = URLComponents()
        c.scheme = "https"; c.host = host; c.path = "/api/v1" + path
        if !query.isEmpty { c.queryItems = query.sorted { $0.name < $1.name } }
        var r = URLRequest(url: c.url!)
        r.httpMethod = method
        r.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            r.httpBody = try JSONSerialization.data(withJSONObject: json)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, http) = try await HTTP.send(r)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let msg = (obj["message"] as? String) ?? "respuesta inesperada"
            if http.statusCode == 406 { throw ProviderError.quota(msg) }
            throw ProviderError.http(http.statusCode, msg)
        }
        return obj
    }

    private func loginIfNeeded() async {
        guard token == nil, !loginTried, !username.isEmpty, !password.isEmpty else { return }
        loginTried = true
        do {
            let obj = try await call("/login", method: "POST", json: ["username": username, "password": password])
            if let t = obj["token"] as? String {
                token = t
                if let b = obj["base_url"] as? String, !b.isEmpty {
                    host = b.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "/", with: "")
                }
            }
        } catch {
            loginNote = "el inicio de sesión con tu usuario falló (\(error.localizedDescription))"
        }
    }

    func search(info: MediaInfo, fileName: String, hash: String?, kind: SubKind) async throws -> [SubtitleCandidate] {
        await loginIfNeeded()
        let base = [
            URLQueryItem(name: "languages", value: "es"),
            URLQueryItem(name: "foreign_parts_only", value: kind == .forced ? "only" : "exclude"),
            URLQueryItem(name: "ai_translated", value: "exclude"),
            URLQueryItem(name: "machine_translated", value: "exclude"),
        ]
        var byHash = base, byText = base
        var out: [SubtitleCandidate] = []
        var seen = Set<String>()

        func parse(_ obj: [String: Any]) {
            for d in obj["data"] as? [[String: Any]] ?? [] {
                guard let a = d["attributes"] as? [String: Any],
                      let files = a["files"] as? [[String: Any]],
                      let fid = files.first?["file_id"] as? Int else { continue }
                let ref = String(fid)
                guard seen.insert(ref).inserted else { continue }
                let isForced = (a["foreign_parts_only"] as? Bool) ?? false
                if (kind == .forced) != isForced { continue }
                out.append(SubtitleCandidate(
                    provider: name,
                    release: (a["release"] as? String) ?? (files.first?["file_name"] as? String) ?? "",
                    ref: ref,
                    downloads: (a["download_count"] as? Int) ?? 0,
                    hashMatch: (a["moviehash_match"] as? Bool) ?? false,
                    hearingImpaired: (a["hearing_impaired"] as? Bool) ?? false,
                    forced: isForced,
                    trusted: (a["from_trusted"] as? Bool) ?? false))
            }
        }

        if let hash {
            byHash.append(URLQueryItem(name: "moviehash", value: hash))
            parse(try await call("/subtitles", query: byHash))
        }
        if let id = info.imdbID {
            var byID = base
            if info.isEpisode, let s = info.season, let e = info.episode {
                byID += [URLQueryItem(name: "parent_imdb_id", value: String(id)),
                         URLQueryItem(name: "season_number", value: String(s)),
                         URLQueryItem(name: "episode_number", value: String(e))]
            } else {
                byID.append(URLQueryItem(name: "imdb_id", value: String(id)))
            }
            parse(try await call("/subtitles", query: byID))
        }
        // Por texto solo si lo anterior no ha dado nada (ahorra cuota de peticiones).
        guard out.isEmpty else { return out }
        byText.append(URLQueryItem(name: "query", value: info.title.lowercased()))
        if info.isEpisode, let s = info.season, let e = info.episode {
            byText.append(URLQueryItem(name: "season_number", value: String(s)))
            byText.append(URLQueryItem(name: "episode_number", value: String(e)))
            byText.append(URLQueryItem(name: "type", value: "episode"))
        } else {
            byText.append(URLQueryItem(name: "type", value: "movie"))
            if let y = info.year { byText.append(URLQueryItem(name: "year", value: String(y))) }
        }
        parse(try await call("/subtitles", query: byText))
        return out
    }

    func download(_ c: SubtitleCandidate, info: MediaInfo, fileName: String, kind: SubKind) async throws -> Data {
        await loginIfNeeded()
        let obj: [String: Any]
        do {
            obj = try await call("/download", method: "POST", json: ["file_id": Int(c.ref) ?? 0, "sub_format": "srt"])
        } catch ProviderError.quota(let m) {
            throw ProviderError.quota(m + (loginNote.map { " · " + $0 } ?? ""))
        }
        guard let link = obj["link"] as? String, let url = URL(string: link) else {
            throw ProviderError.bad("OpenSubtitles no devolvió enlace de descarga")
        }
        let (data, http) = try await HTTP.send(URLRequest(url: url))
        guard http.statusCode == 200 else { throw ProviderError.http(http.statusCode, "descarga fallida") }
        return data
    }
}

// MARK: - SubDL

final class SubDLProvider: SubtitleProvider, @unchecked Sendable {
    let name = "SubDL"
    private let apiKey: String

    init(apiKey: String) { self.apiKey = apiKey }

    func search(info: MediaInfo, fileName: String, hash: String?, kind: SubKind) async throws -> [SubtitleCandidate] {
        func query(_ extra: [URLQueryItem]) async throws -> [String: Any] {
            var c = URLComponents(string: "https://api.subdl.com/api/v1/subtitles")!
            var q = [
                URLQueryItem(name: "api_key", value: apiKey),
                URLQueryItem(name: "languages", value: "ES"),
                URLQueryItem(name: "subs_per_page", value: "30"),
            ] + extra
            if info.isEpisode, let s = info.season, let e = info.episode {
                q += [URLQueryItem(name: "type", value: "tv"),
                      URLQueryItem(name: "season_number", value: String(s)),
                      URLQueryItem(name: "episode_number", value: String(e))]
            } else {
                q.append(URLQueryItem(name: "type", value: "movie"))
                if extra.first?.name == "film_name", let y = info.year { q.append(URLQueryItem(name: "year", value: String(y))) }
            }
            c.queryItems = q
            let (data, http) = try await HTTP.send(URLRequest(url: c.url!))
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard http.statusCode == 200 else {
                throw ProviderError.http(http.statusCode, (obj["error"] as? String) ?? "respuesta inesperada")
            }
            return obj
        }
        var obj: [String: Any] = [:]
        if let id = info.imdbID { obj = try await query([URLQueryItem(name: "imdb_id", value: IMDB.format(id))]) }
        if (obj["subtitles"] as? [[String: Any]] ?? []).isEmpty {
            obj = try await query([URLQueryItem(name: "film_name", value: info.title)])
        }
        var out: [SubtitleCandidate] = []
        for s in obj["subtitles"] as? [[String: Any]] ?? [] {
            guard let url = s["url"] as? String else { continue }
            let release = (s["release_name"] as? String) ?? (s["name"] as? String) ?? ""
            let lower = release.lowercased() + " " + ((s["name"] as? String) ?? "").lowercased()
            // SubDL no marca "forzado": se deduce del nombre.
            let isForced = lower.contains("forced") || lower.contains("forzado")
            if (kind == .forced) != isForced { continue }
            if (s["full_season"] as? Bool) == true, info.isEpisode { /* se resuelve al descomprimir */ }
            out.append(SubtitleCandidate(provider: name, release: release, ref: url, downloads: 0,
                                         hashMatch: false, hearingImpaired: (s["hi"] as? Bool) ?? false,
                                         forced: isForced, trusted: false))
        }
        return out
    }

    func download(_ c: SubtitleCandidate, info: MediaInfo, fileName: String, kind: SubKind) async throws -> Data {
        guard let url = URL(string: "https://dl.subdl.com" + c.ref) else { throw ProviderError.bad("URL de SubDL inválida") }
        let (data, http) = try await HTTP.send(URLRequest(url: url))
        guard http.statusCode == 200 else { throw ProviderError.http(http.statusCode, "descarga fallida") }
        guard data.starts(with: [0x50, 0x4B]) else { return data } // no es zip: ya es el .srt
        let files = try ZipExtractor.srtFiles(in: data)
        var pool = files
        if let s = info.season, let e = info.episode {
            let re = try NSRegularExpression(pattern: String(format: #"s0*%d[ ._-]?e0*%d\b|\b0*%dx0*%d\b"#, s, e, s, e),
                                             options: .caseInsensitive)
            let matching = pool.filter { re.firstMatch(in: $0.name, range: NSRange($0.name.startIndex..., in: $0.name)) != nil }
            if !matching.isEmpty { pool = matching }
        }
        let isForcedName: (String) -> Bool = { $0.lowercased().contains("forced") || $0.lowercased().contains("forzado") }
        let byKind = pool.filter { isForcedName($0.name) == (kind == .forced) }
        if !byKind.isEmpty { pool = byKind }
        guard let best = pool.max(by: { Scoring.similarity($0.name, fileName) < Scoring.similarity($1.name, fileName) }) else {
            throw ProviderError.bad("El zip no contiene .srt")
        }
        return best.data
    }
}

enum ZipExtractor {
    static func srtFiles(in zip: Data) throws -> [(name: String, data: Data)] {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let zipURL = dir.appendingPathComponent("s.zip")
        let out = dir.appendingPathComponent("out")
        try zip.write(to: zipURL)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-qq", "-o", zipURL.path, "-d", out.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        var res: [(String, Data)] = []
        if let en = fm.enumerator(at: out, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.pathExtension.lowercased() == "srt" {
                if let d = try? Data(contentsOf: f) { res.append((f.lastPathComponent, d)) }
            }
        }
        return res
    }
}
