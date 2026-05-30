import Foundation
import UIKit

final class StudifyOverlaySignalClient {
    static let shared = StudifyOverlaySignalClient()

    private init() { }

    func startPlaylistJob(playlistURI: String) {
        let serverURLString = studifyOverlayResolvedServerURLString()
        guard let baseURL = URL(string: serverURLString) else {
            fail("Invalid server URL: \(serverURLString)")
            return
        }

        let endpoint = baseURL.appendingPathComponent("v1/jobs/playlist")
        let payload = makePayload(playlistURI: playlistURI)

        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            fail("Could not encode playlist payload")
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("studify-overlay-ios-0.1", forHTTPHeaderField: "X-Studify-Client")
        request.httpBody = body

        studifyOverlayLog("POST \(endpoint.absoluteString) playlistURI=\(playlistURI)")
        StudifyOverlayBanner.show(
            title: "STUDIFY OVERLAY POST STARTED",
            detail: endpoint.host ?? "server",
            color: UIColor(red: 0.09, green: 0.40, blue: 0.95, alpha: 0.96),
            duration: 5
        )

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.fail("Request failed: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.fail("No HTTP response")
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                self.fail("HTTP \(httpResponse.statusCode): \(bodyText)")
                return
            }

            let jobId = self.extractJobId(from: data) ?? "unknown"
            studifyOverlayLog("Signal accepted jobId=\(jobId)")
            StudifyOverlayBanner.show(
                title: "STUDIFY OVERLAY SERVER ACCEPTED",
                detail: jobId,
                color: UIColor(red: 0.12, green: 0.58, blue: 0.28, alpha: 0.96),
                duration: 5
            )
        }.resume()
    }

    private func makePayload(playlistURI: String) -> [String: Any] {
        var payload: [String: Any] = [
            "playlistUri": playlistURI,
            "playlistUrl": playlistURLString(from: playlistURI),
            "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "deviceName": UIDevice.current.name,
            "clientVersion": "studify-overlay-ios-0.1",
            "spotifyVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "sentAt": ISO8601DateFormatter().string(from: Date()),
        ]

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            payload["bundleIdentifier"] = bundleIdentifier
        }

        return payload
    }

    private func playlistURLString(from playlistURI: String) -> String {
        if playlistURI.hasPrefix("spotify:playlist:") {
            let playlistId = playlistURI.replacingOccurrences(of: "spotify:playlist:", with: "")
            return "https://open.spotify.com/playlist/\(playlistId)"
        }

        return playlistURI
    }

    private func extractJobId(from data: Data?) -> String? {
        guard
            let data,
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let dictionary = object as? [String: Any]
        else {
            return nil
        }

        return dictionary["jobId"] as? String
    }

    private func fail(_ message: String) {
        studifyOverlayLog(message)
        StudifyOverlayBanner.show(
            title: "STUDIFY OVERLAY REQUEST FAILED",
            detail: message,
            color: UIColor(red: 0.78, green: 0.12, blue: 0.16, alpha: 0.96),
            duration: 7
        )
    }
}
