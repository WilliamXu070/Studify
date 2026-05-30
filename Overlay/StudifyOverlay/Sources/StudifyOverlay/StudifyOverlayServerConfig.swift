import Foundation

private let studifyServerConfigPaths = [
    "StudifyLibrary/server-url.txt",
    "studify-server-url.txt"
]

private let studifyProbeModeConfigPaths = [
    "StudifyLibrary/probe-mode.txt",
    "studify-probe-mode.txt"
]

private let studifyProbeUploadConfigPaths = [
    "StudifyLibrary/probe-upload.txt",
    "studify-probe-upload.txt"
]

func studifyOverlayResolvedServerURLString() -> String {
    if let override = studifyOverlayServerURLOverride() {
        return override
    }

    return studifyOverlayDefaultServerURL
}

func studifyOverlayProbeModeIsEnabled() -> Bool {
    if UserDefaults.standard.bool(forKey: "StudifyOverlayProbeMode") {
        return true
    }

    guard let rawValue = studifyOverlayProbeModeOverride() else {
        return false
    }

    let normalized = rawValue.lowercased()
    return [
        "1",
        "true",
        "yes",
        "on",
        "enabled",
        "probe",
        "probe-mode"
    ].contains(normalized)
}

func studifyOverlayProbeUploadIsEnabled() -> Bool {
    if UserDefaults.standard.bool(forKey: "StudifyOverlayProbeUpload") {
        return true
    }

    guard let rawValue = studifyOverlayProbeUploadOverride() else {
        return false
    }

    let normalized = rawValue.lowercased()
    return [
        "1",
        "true",
        "yes",
        "on",
        "enabled",
        "upload",
        "server"
    ].contains(normalized)
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

private func studifyOverlayProbeUploadOverride() -> String? {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    for relativePath in studifyProbeUploadConfigPaths {
        let url = documentsURL.appendingPathComponent(relativePath, isDirectory: false)
        guard let rawValue = try? String(contentsOf: url, encoding: .utf8) else {
            continue
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }

        return trimmed
    }

    return nil
}

private func studifyOverlayProbeModeOverride() -> String? {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    for relativePath in studifyProbeModeConfigPaths {
        let url = documentsURL.appendingPathComponent(relativePath, isDirectory: false)
        guard let rawValue = try? String(contentsOf: url, encoding: .utf8) else {
            continue
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }

        return trimmed
    }

    return nil
}
