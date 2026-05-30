import Foundation

private let studifyServerConfigPaths = [
    "StudifyLibrary/server-url.txt",
    "studify-server-url.txt"
]

func studifyOverlayResolvedServerURLString() -> String {
    if let override = studifyOverlayServerURLOverride() {
        return override
    }

    return studifyOverlayDefaultServerURL
}

private func studifyOverlayServerURLOverride() -> String? {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    for relativePath in studifyServerConfigPaths {
        let url = documentsURL.appendingPathComponent(relativePath, isDirectory: false)
        guard let rawValue = try? String(contentsOf: url, encoding: .utf8) else {
            continue
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            studifyOverlayLog("Ignoring invalid Studify server URL override at \(relativePath): \(trimmed)")
            continue
        }

        return trimmed
    }

    return nil
}
