import Foundation
import Orion
import UIKit

final class StudifyPromptPresentationProbe {
    static let shared = StudifyPromptPresentationProbe()

    private var timer: Timer?
    private var lastSignature = ""
    private var lastLogAt = Date(timeIntervalSince1970: 0)

    private init() { }

    func install() {
        guard studifyOverlayProbeModeEnabled else { return }

        DispatchQueue.main.async {
            guard self.timer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                self?.scan(reason: "timer")
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            self.scan(reason: "install")
            studifyOverlayLog("Prompt/premium presentation probe installed")
        }
    }

    func noteController(_ controller: UIViewController, reason: String) {
        guard studifyOverlayProbeModeEnabled else { return }
        let className = NSStringFromClass(type(of: controller))
        let text = studifyPromptProbeText(in: controller.view, maxDepth: 8, limit: 80)
        recordIfInteresting(
            reason: reason,
            className: className,
            text: text,
            data: [
                "presentingClass": controller.presentingViewController.map { NSStringFromClass(type(of: $0)) } ?? "",
                "presentedClass": controller.presentedViewController.map { NSStringFromClass(type(of: $0)) } ?? "",
                "modalPresentationStyle": controller.modalPresentationStyle.rawValue
            ]
        )
    }

    private func scan(reason: String) {
        guard studifyOverlayProbeModeEnabled,
              let window = activeWindow()
        else {
            return
        }

        let text = studifyPromptProbeText(in: window, maxDepth: 12, limit: 120)
        let topController = topViewController(from: window.rootViewController)
        let className = topController.map { NSStringFromClass(type(of: $0)) } ?? NSStringFromClass(type(of: window))

        recordIfInteresting(
            reason: reason,
            className: className,
            text: text,
            data: [
                "windowClass": NSStringFromClass(type(of: window)),
                "rootClass": window.rootViewController.map { NSStringFromClass(type(of: $0)) } ?? "",
                "topControllerClass": className
            ]
        )
    }

    private func recordIfInteresting(reason: String, className: String, text: String, data: [String: Any]) {
        let joined = "\(className) \(text)"
        let lower = joined.lowercased()
        let isGate = studifyPromptProbeLooksLikePremiumGate(lower)
        let isPrompt = studifyPromptProbeLooksLikePrompt(lower)

        guard isGate || isPrompt else { return }

        let signature = "\(isGate)-\(className)-\(text.prefix(280))"
        let now = Date()
        guard signature != lastSignature || now.timeIntervalSince(lastLogAt) > 2.5 else {
            return
        }
        lastSignature = signature
        lastLogAt = now

        if isGate {
            StudifyProbeStreamClient.shared.extend(reason: "premium/song-selection prompt")
        }

        studifyOverlayLog("Prompt/premium probe reason=\(reason) gate=\(isGate) class=\(className) text=\(text)")
        StudifyProbeStreamClient.shared.emit(
            hook: isGate ? "premium-gate" : "prompt",
            phase: reason,
            message: text,
            className: className,
            data: data.merging([
                "isGate": isGate,
                "visibleText": text
            ]) { _, new in new },
            throttleKey: "prompt-\(signature)",
            minInterval: 2.5,
            requireActive: false
        )
    }

    private func activeWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })
                ?? UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first
                ?? UIApplication.shared.windows.first
        }

        return UIApplication.shared.keyWindow ?? UIApplication.shared.windows.first
    }

    private func topViewController(from root: UIViewController?) -> UIViewController? {
        var current = root
        var depth = 0

        while depth < 12 {
            if let presented = current?.presentedViewController {
                current = presented
            } else if let navigation = current as? UINavigationController {
                current = navigation.visibleViewController ?? navigation.topViewController
            } else if let tab = current as? UITabBarController {
                current = tab.selectedViewController
            } else {
                break
            }
            depth += 1
        }

        return current
    }
}

class StudifyPromptUIViewControllerProbeHook: ClassHook<UIViewController> {
    typealias Group = StudifyOverlayProbeHookGroup
    static let targetName = "UIViewController"

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        StudifyPromptPresentationProbe.shared.noteController(target, reason: "viewDidAppear")
    }
}

private func studifyPromptProbeLooksLikePrompt(_ lower: String) -> Bool {
    [
        "popup",
        "pop up",
        "dialog",
        "alert",
        "sheet",
        "upsell",
        "timecap"
    ].contains { lower.contains($0) }
}

private func studifyPromptProbeLooksLikePremiumGate(_ lower: String) -> Bool {
    if lower.contains("timecap") || lower.contains("upsell") || lower.contains("free tier") || lower.contains("freetier") {
        return true
    }

    if lower.contains("song selection") || lower.contains("random order") || lower.contains("play any song") {
        return true
    }

    return lower.contains("premium")
        && (lower.contains("song") || lower.contains("random") || lower.contains("play") || lower.contains("get"))
}

private func studifyPromptProbeText(in view: UIView?, maxDepth: Int, limit: Int) -> String {
    guard let view else { return "" }
    var values: [String] = []
    studifyPromptProbeCollectText(in: view, depth: 0, maxDepth: maxDepth, limit: limit, values: &values)

    var seen = Set<String>()
    return values
        .map(studifyPromptProbeClean)
        .filter { !$0.isEmpty }
        .filter { value in
            if seen.contains(value) { return false }
            seen.insert(value)
            return true
        }
        .prefix(limit)
        .joined(separator: " | ")
}

private func studifyPromptProbeCollectText(in view: UIView, depth: Int, maxDepth: Int, limit: Int, values: inout [String]) {
    guard depth <= maxDepth, values.count < limit else { return }

    if let label = view.accessibilityLabel {
        values.append(label)
    }
    if let identifier = view.accessibilityIdentifier {
        values.append(identifier)
    }
    if let label = view as? UILabel {
        values.append(label.text ?? "")
    }
    if let textView = view as? UITextView {
        values.append(textView.text ?? "")
    }
    if let textField = view as? UITextField {
        values.append(textField.text ?? "")
        values.append(textField.placeholder ?? "")
    }
    if let button = view as? UIButton {
        values.append(button.currentTitle ?? "")
        values.append(button.title(for: .normal) ?? "")
    }

    for subview in view.subviews where values.count < limit {
        studifyPromptProbeCollectText(in: subview, depth: depth + 1, maxDepth: maxDepth, limit: limit, values: &values)
    }
}

private func studifyPromptProbeClean(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .split(separator: " ")
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
