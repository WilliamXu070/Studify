import Foundation
import UIKit

enum StudifySignalResult {
    case success(jobId: String)
    case failure(message: String)
}

final class StudifyDownloadSignalClient {
    static let shared = StudifyDownloadSignalClient()

    private let serverURLDefaultsKey = "StudifySignalServerURL"
    private let defaultServerBaseURLString = "http://172.17.144.67:8787"
    private let clientVersion = "studify-ios-0.1"
    private let serverConfigRelativePaths = [
        "StudifyLibrary/server-url.txt",
        "studify-server-url.txt"
    ]

    private init() { }

    private var serverBaseURLString: String {
        serverURLFromDocuments()
            ?? UserDefaults.container.string(forKey: serverURLDefaultsKey)
            ?? defaultServerBaseURLString
    }

    func startPlaylistJob(
        pageURI: NSURL,
        completion: ((StudifySignalResult) -> Void)? = nil
    ) {
        let playlistURI = pageURI.absoluteString ?? pageURI.description
        startPlaylistJob(playlistURI: playlistURI, completion: completion)
    }

    func startPlaylistJob(
        playlistURI: String,
        completion: ((StudifySignalResult) -> Void)? = nil
    ) {
        guard let baseURL = URL(string: serverBaseURLString) else {
            let message = "Invalid Studify server URL: \(serverBaseURLString)"
            writeDebugLog("[STUDIFY] \(message)")
            complete(.failure(message: message), completion)
            return
        }

        let endpointURL = baseURL.appendingPathComponent("v1/jobs/playlist")
        let payload = makePayload(playlistURI: playlistURI)

        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            let message = "Could not encode Studify playlist payload"
            writeDebugLog("[STUDIFY] \(message)")
            complete(.failure(message: message), completion)
            return
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientVersion, forHTTPHeaderField: "X-Studify-Client")
        request.httpBody = body

        writeDebugLog("[STUDIFY] POST \(endpointURL.absoluteString) playlistURI=\(playlistURI)")
        StudifyDebugVisualAid.posting("\(endpointURL.host ?? "server") \(playlistURI)")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                let message = "Signal request failed: \(error.localizedDescription)"
                writeDebugLog("[STUDIFY] \(message)")
                StudifyDebugVisualAid.failed(error.localizedDescription)
                self.complete(.failure(message: message), completion)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let message = "Signal request returned no HTTP response"
                writeDebugLog("[STUDIFY] \(message)")
                StudifyDebugVisualAid.failed("No HTTP response")
                self.complete(.failure(message: message), completion)
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let message = "Signal server returned \(httpResponse.statusCode): \(responseBody)"
                writeDebugLog("[STUDIFY] \(message)")
                StudifyDebugVisualAid.failed("HTTP \(httpResponse.statusCode)")
                self.complete(.failure(message: message), completion)
                return
            }

            let jobId = self.extractJobId(from: data) ?? "unknown"
            writeDebugLog("[STUDIFY] Signal accepted with jobId=\(jobId)")
            StudifyDebugVisualAid.accepted("jobId \(jobId)")
            self.complete(.success(jobId: jobId), completion)
        }.resume()
    }

    private func makePayload(playlistURI: String) -> [String: Any] {
        var payload: [String: Any] = [
            "playlistUri": playlistURI,
            "playlistUrl": playlistURLString(from: playlistURI),
            "deviceId": deviceId(),
            "deviceName": UIDevice.current.name,
            "clientVersion": clientVersion,
            "spotifyVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "sentAt": ISO8601DateFormatter().string(from: Date()),
        ]

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            payload["bundleIdentifier"] = bundleIdentifier
        }

        return payload
    }

    private func serverURLFromDocuments() -> String? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        for relativePath in serverConfigRelativePaths {
            let url = documentsURL.appendingPathComponent(relativePath, isDirectory: false)
            guard let rawValue = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
                writeDebugLog("[STUDIFY] Ignoring invalid server URL override at \(relativePath): \(trimmed)")
                continue
            }

            return trimmed
        }

        return nil
    }

    private func playlistURLString(from playlistURI: String) -> String {
        if playlistURI.hasPrefix("spotify:playlist:") {
            let playlistId = playlistURI.replacingOccurrences(of: "spotify:playlist:", with: "")
            return "https://open.spotify.com/playlist/\(playlistId)"
        }

        return playlistURI
    }

    private func deviceId() -> String {
        if let identifier = UIDevice.current.identifierForVendor?.uuidString {
            return identifier
        }

        let key = "StudifyDeviceId"
        if let stored = UserDefaults.container.string(forKey: key) {
            return stored
        }

        let generated = UUID().uuidString
        UserDefaults.container.set(generated, forKey: key)
        return generated
    }

    private func extractJobId(from data: Data?) -> String? {
        guard
            let data = data,
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }

        return dictionary["jobId"] as? String
    }

    private func complete(
        _ result: StudifySignalResult,
        _ completion: ((StudifySignalResult) -> Void)?
    ) {
        DispatchQueue.main.async {
            completion?(result)
        }
    }
}
