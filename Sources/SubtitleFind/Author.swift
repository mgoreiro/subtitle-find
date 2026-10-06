import AppKit

/// Datos del autor que se muestran en "Acerca de". Edítalos aquí.
/// Texto localizado según el idioma del sistema (Resources/*.lproj).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

enum Author {
    static let name = "Miguel Gonzalez Oreiro"
    static let email = "mgoreiro@gmail.com"
    static let github = "https://github.com/mgoreiro"
    static let year = "2026"
    static let version = "1.0"

    @MainActor
    static func showAbout() {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.paragraphSpacing = 4
        let font = NSFont.systemFont(ofSize: 11)
        func line(_ s: String, link: URL? = nil, bold: Bool = false) -> NSAttributedString {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? NSFont.boldSystemFont(ofSize: 11) : font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
            if let link { attrs[.link] = link }
            return NSAttributedString(string: s + "\n", attributes: attrs)
        }
        let credits = NSMutableAttributedString()
        credits.append(line(L("about.desc")))
        credits.append(line(L("about.author"), bold: true))
        credits.append(line(name))
        credits.append(line(email, link: URL(string: "mailto:\(email)")))
        credits.append(line("github.com/mgoreiro", link: URL(string: github)))
        credits.append(line(L("about.sources"), bold: true))
        credits.append(line(L("about.sources.list")))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Subtitle Find",
            .applicationVersion: version,
            .version: "",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© \(year) \(name)",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
