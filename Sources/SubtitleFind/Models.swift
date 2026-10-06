import Foundation
import Observation

enum SubKind: CaseIterable {
    case normal, forced

    var label: String { self == .normal ? L("kind.normal") : L("kind.forced") }

    /// Forzado: mismo nombre que el vídeo (`Peli.srt`). Normal: `Peli_es.srt`.
    func outputURL(for video: URL) -> URL {
        let base = video.deletingPathExtension()
        switch self {
        case .forced: return base.appendingPathExtension("srt")
        case .normal: return URL(fileURLWithPath: base.path + "_es.srt")
        }
    }
}

enum SubState: Equatable {
    case pending
    case working(String)
    case saved(String)
    case skipped(String)
    case notFound
    case failed(String)
    /// Cuota diaria de descargas agotada en todos los proveedores.
    case quota(String)

    var isFinished: Bool {
        switch self {
        case .pending, .working: return false
        default: return true
        }
    }
}

@Observable
final class VideoItem: Identifiable {
    let id = UUID()
    let url: URL
    var normal: SubState = .pending
    var forced: SubState = .pending
    /// Id de IMDB (sin "tt") fijado a mano; para series, el de la serie.
    var imdbOverride: Int?
    /// Texto de lo que se ha usado para buscar, p. ej. "Foundation · tt0804484".
    var imdbLabel: String?

    init(url: URL) { self.url = url }

    subscript(kind: SubKind) -> SubState {
        get { kind == .normal ? normal : forced }
        set { if kind == .normal { normal = newValue } else { forced = newValue } }
    }

    var hasPending: Bool { normal == .pending || forced == .pending }
    var isFinished: Bool { normal.isFinished && forced.isFinished }
}

struct MediaInfo {
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?
    /// Id numérico de IMDB (tt0804484 → 804484); en episodios, el de la serie.
    var imdbID: Int?
    var isEpisode: Bool { season != nil && episode != nil }
}

struct SubtitleCandidate {
    let provider: String
    let release: String
    let ref: String
    let downloads: Int
    let hashMatch: Bool
    let hearingImpaired: Bool
    let forced: Bool
    let trusted: Bool
    var score: Double = 0
}

protocol SubtitleProvider: AnyObject {
    var name: String { get }
    func search(info: MediaInfo, fileName: String, hash: String?, kind: SubKind) async throws -> [SubtitleCandidate]
    /// Devuelve el contenido .srt en bruto.
    func download(_ c: SubtitleCandidate, info: MediaInfo, fileName: String, kind: SubKind) async throws -> Data
}

enum ProviderError: LocalizedError {
    case http(Int, String)
    case quota(String)
    case bad(String)

    var errorDescription: String? {
        switch self {
        case .http(let c, let m): return LF("err.http", c, m)
        case .quota(let m): return LF("err.quota", m)
        case .bad(let m): return m
        }
    }
}
