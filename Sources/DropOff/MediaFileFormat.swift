import Foundation

enum MediaFileFormat {
    static func detectedPathExtension(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536), !data.isEmpty else {
            return nil
        }
        return detectedPathExtension(in: data)
    }

    static func detectedPathExtension(in data: Data) -> String? {
        let bytes = [UInt8](data.prefix(65_536))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "png"
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if bytes.starts(with: Array("GIF87a".utf8))
            || bytes.starts(with: Array("GIF89a".utf8)) {
            return "gif"
        }
        if bytes.count >= 12,
           String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF",
           String(decoding: bytes[8..<12], as: UTF8.self) == "WEBP" {
            return "webp"
        }

        if bytes.count >= 12,
           String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp" {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            if ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand) {
                return "heic"
            }
            if ["avif", "avis"].contains(brand) {
                return "avif"
            }
            return brand == "qt  " ? "mov" : "mp4"
        }

        if let prefix = String(data: data.prefix(16_384), encoding: .utf8) {
            let trimmed = prefix
                .replacingOccurrences(of: "\u{feff}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<svg")
                || (trimmed.hasPrefix("<?xml") && trimmed.range(of: "<svg") != nil) {
                return "svg"
            }
        }
        return nil
    }
}
