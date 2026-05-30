import Foundation
import UIKit

final class StudifyProbeStreamClient {
    static let shared = StudifyProbeStreamClient()

    private let queue = DispatchQueue(label: "studify.probe.stream")
    private let sessionDuration: TimeInterval = 90
    private var activeUntil = Date(timeIntervalSince1970: 0)
    private var sessionId = UUID().uuidString
    private var lastSentByKey: [String: Date] = [:]

    private init() { }

    var isActive: Bool {
        guard studifyOverlayProbeModeEnabled else { return false }
        return queue.sync { Date() < activeUntil }
    }

    func start(reason: String) {
        guard studifyOverlayProbeModeEnabled else { return }
        queue.async {
            self.sessionId = UUID().uuidString
            self.activeUntil = Date().addingTimeInterval(self.sessionDuration)
            self.lastSentByKey.removeAll()

            DispatchQueue.main.async {
                StudifyOverlayBanner.show(
                    title: "STUDIFY PROBE STREAM ON",
                    detail: "\(reason) | \(Int(self.sessionDuration))s",
                    color: UIColor(red: 0.08, green: 0.45, blue: 0.95, alpha: 0.96),
                    duration: 5
                )
            }

            self.emitLocked(
                hook: "probe-session",
                phase: "started",
                message: reason,
                className: "",
                selector: "",
                data: ["durationSeconds": Int(self.sessionDuration)],
                throttleKey: nil,
                minInterval: 0
            )
        }
    }

    func extend(reason: String) {
        guard studifyOverlayProbeModeEnabled else { return }
        queue.async {
            self.activeUntil = Date().addingTimeInterval(self.sessionDuration)
            self.emitLocked(
                hook: "probe-session",
                phase: "extended",
                message: reason,
                className: "",
                selector: "",
                data: ["durationSeconds": Int(self.sessionDuration)],
                throttleKey: "probe-session-extended",
                minInterval: 2
            )
        }
    }

    func emit(
        hook: String,
        phase: String,
        message: String = "",
        className: String = "",
        selector: String = "",
        data: [String: Any] = [:],
        throttleKey: String? = nil,
        minInterval: TimeInterval = 0.5,
        requireActive: Bool = true
    ) {
        guard studifyOverlayProbeModeEnabled else { return }
        queue.async {
            guard !requireActive || Date() < self.activeUntil else { return }
            self.emitLocked(
                hook: hook,
                phase: phase,
                message: message,
                className: className,
                selector: selector,
                data: data,
                throttleKey: throttleKey,
                minInterval: minInterval
            )
        }
    }

    private func emitLocked(
        hook: String,
        phase: String,
        message: String,
        className: String,
        selector: String,
        data: [String: Any],
        throttleKey: String?,
        minInterval: TimeInterval
    ) {
        if let throttleKey {
            let now = Date()
            if let lastSent = lastSentByKey[throttleKey], now.timeIntervalSince(lastSent) < minInterval {
                return
            }
            lastSentByKey[throttleKey] = now
        }

        let serverURLString = studifyOverlayResolvedServerURLString()
        guard let baseURL = URL(string: serverURLString) else {
            studifyOverlayLog("Probe stream invalid server URL: \(serverURLString)")
            return
        }

        let endpoint = baseURL.appendingPathComponent("v1/probe/events")
        var payload = data
        payload["deviceId"] = UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
        payload["deviceName"] = UIDevice.current.name
        payload["sessionId"] = sessionId
        payload["hook"] = hook
        payload["phase"] = phase
        payload["message"] = message
        payload["className"] = className
        payload["selector"] = selector
        payload["spotifyVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        payload["sentAt"] = ISO8601DateFormatter().string(from: Date())

        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            studifyOverlayLog("Probe stream could not encode event hook=\(hook) phase=\(phase)")
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("studify-probe-ios-0.1", forHTTPHeaderField: "X-Studify-Client")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                studifyOverlayLog("Probe stream failed hook=\(hook) error=\(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                studifyOverlayLog("Probe stream HTTP \(httpResponse.statusCode) hook=\(hook)")
            }
        }.resume()
    }
}
