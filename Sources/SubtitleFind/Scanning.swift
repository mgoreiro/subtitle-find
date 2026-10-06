import Foundation

enum VideoScanner {
    static let exts: Set<String> = ["mkv", "mp4", "m4v", "avi", "mov", "wmv", "mpg", "mpeg", "ts", "m2ts", "webm", "flv", "divx"]

    /// Expande ficheros y carpetas (recursivo) a una lista ordenada de vídeos.
    static func collect(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let en = fm.enumerator(at: u, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let f as URL in en where exts.contains(f.pathExtension.lowercased()) {
                    out.append(f)
                }
            } else if exts.contains(u.pathExtension.lowercased()) {
                out.append(u)
            }
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

/// Hash de OpenSubtitles: tamaño + suma de palabras de 64 bits de los primeros y últimos 64 KB.
enum MovieHash {
    static func compute(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let chunk = 65536
        guard let size = try? h.seekToEnd(), size >= UInt64(chunk) else { return nil }
        var hash = size
        func add(_ d: Data) {
            d.withUnsafeBytes { raw in
                for i in 0..<(raw.count / 8) {
                    hash = hash &+ raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self)
                }
            }
        }
        do {
            try h.seek(toOffset: 0)
            guard let a = try h.read(upToCount: chunk), a.count == chunk else { return nil }
            try h.seek(toOffset: size - UInt64(chunk))
            guard let b = try h.read(upToCount: chunk), b.count == chunk else { return nil }
            add(a); add(b)
        } catch { return nil }
        return String(format: "%016llx", hash)
    }
}

enum NameParser {
    private static let tags = #"\b(480p|576p|720p|1080p|2160p|4k|uhd|bluray|blu-ray|brrip|bdrip|web-?dl|webrip|hdtv|dvdrip|hdrip|x264|x265|h264|h265|hevc|remux|proper|repack|extended|unrated|directors?\.?cut|multi|castellano|spanish)\b"#

    static func parse(_ url: URL) -> MediaInfo {
        var s = url.deletingPathExtension().lastPathComponent
        s = s.replacingOccurrences(of: #"^\[[^\]]*\]\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[._]"#, with: " ", options: .regularExpression)

        var cut = s.endIndex
        var season: Int?, episode: Int?, year: Int?

        if let (r, g) = match(#"\bS(\d{1,2})[ .-]?E(\d{1,3})\b"#, in: s) {
            season = Int(g[0]); episode = Int(g[1]); cut = min(cut, r.lowerBound)
        } else if let (r, g) = match(#"\b(\d{1,2})x(\d{2,3})\b"#, in: s) {
            season = Int(g[0]); episode = Int(g[1]); cut = min(cut, r.lowerBound)
        }
        // Año entre paréntesis; si no, el último número de 4 cifras plausible ("Blade Runner 2049 2017" → 2017).
        let maxYear = Calendar.current.component(.year, from: Date()) + 1
        let bare = allMatches(#"\b((?:19|20)\d{2})\b"#, in: s).filter { $0.0.lowerBound != s.startIndex && (Int($0.1[0]) ?? 0) <= maxYear }
        if let (r, g) = match(#"[\(\[]((?:19|20)\d{2})[\)\]]"#, in: s) ?? bare.last {
            year = Int(g[0]); cut = min(cut, r.lowerBound)
        }
        if let (r, _) = match(tags, in: s, skipAtStart: true) { cut = min(cut, r.lowerBound) }

        var title = String(s[..<cut]).trimmingCharacters(in: CharacterSet(charactersIn: " -([")) 
        if title.isEmpty { title = s }
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return MediaInfo(title: title, year: season == nil ? year : nil, season: season, episode: episode)
    }

    private static func match(_ pattern: String, in s: String, skipAtStart: Bool = false) -> (Range<String.Index>, [String])? {
        allMatches(pattern, in: s).first { !(skipAtStart && $0.0.lowerBound == s.startIndex) }
    }

    private static func allMatches(_ pattern: String, in s: String) -> [(Range<String.Index>, [String])] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let r = Range(m.range, in: s) else { return nil }
            let groups = (1..<m.numberOfRanges).map {
                m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0))
            }
            return (r, groups)
        }
    }
}

enum Scoring {
    static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let x = tokens(a), y = tokens(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }

    static func score(_ c: SubtitleCandidate, fileName: String, kind: SubKind) -> Double {
        var s = similarity(c.release, fileName) * 40
        if c.hashMatch { s += 100 }
        s += log10(Double(c.downloads) + 1) * 5
        if c.trusted { s += 3 }
        if kind == .normal && c.hearingImpaired { s -= 5 }
        return s
    }
}

enum SubtitleText {
    /// Decodifica a UTF-8 desde UTF-8/UTF-16/Windows-1252/Latin-1.
    static func decode(_ d: Data) -> String? {
        var data = d
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
    }

    static func looksLikeSRT(_ s: String) -> Bool {
        s.range(of: #"\d{1,2}:\d{2}:\d{2}[,.]\d{3}\s*-->"#, options: .regularExpression) != nil
    }
}
