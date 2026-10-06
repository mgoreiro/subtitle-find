import Foundation

/// Texto localizado según el idioma del sistema (Resources/*.lproj/Localizable.strings).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Igual que `L`, pero la cadena localizada es un formato (`%@`, `%d`).
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
