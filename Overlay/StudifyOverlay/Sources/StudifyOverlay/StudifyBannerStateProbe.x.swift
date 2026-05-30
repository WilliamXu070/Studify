import Foundation
import ObjectiveC
import Orion
import UIKit

var studifyBannerStateProbeEnabled: Bool {
    studifyOverlayProbeModeEnabled || UserDefaults.standard.bool(forKey: "StudifyEnableBannerStateProbe")
}

struct StudifyBannerStateProbeHookGroup: HookGroup { }

func studifyActivateBannerStateProbe() {
    guard studifyBannerStateProbeEnabled else {
        studifyOverlayLog("Banner/state probe skipped; opt-in debug probe disabled")
        return
    }

    if !StudifyBannerStateProbeHookGroup.isActive {
        StudifyBannerStateProbeHookGroup().activate()
    }

    StudifyBannerStateProbe.shared.install()
    studifyOverlayLog("Banner/state probe activated")
}

final class StudifyBannerStateProbe {
    static let shared = StudifyBannerStateProbe()

    private var timer: Timer?
    private var didRunClassProbe = false
    private var lastBottomSignature = ""
    private var lastBottomLogAt = Date(timeIntervalSince1970: 0)
    private var lastControllerLogByClass: [String: Date] = [:]
    private var lastViewLogByClass: [String: Date] = [:]

    private let candidateClasses = [
        "NowPlaying_BarImpl.NowPlayingBarContainerViewController",
        "NowPlaying_BarImpl.NowPlayingBarViewController",
        "NowPlaying_BarImpl.NowPlayingBarView",
        "NowPlaying_BarImpl.NowPlayingBarViewModelImplementation",
        "NowPlaying_BarImpl.NowPlayingBarModelImplementation",
        "NowPlaying_BarImpl.NowPlayingBarServiceImplementation",
        "NowPlaying_BarPageImpl.NowPlayingBarPage",
        "NowPlaying_PlatformImpl.NowPlayingPlatformSwiftServiceImplementation",
        "NowPlaying_PublishersKitImpl.SPTPlayerStateImplementation",
        "NowPlaying_PublishersKitImpl.SPTMutablePlayerState",
        "NowPlaying_PublishersKitImpl.NowPlayingViewStatePublisher",
        "LockScreen_LockScreenImpl.LockScreenInfoCenterManager",
        "LockScreen_LockScreenImpl.LockScreenDataProviderImplementation",
        "LockScreen_LockScreenImpl.LockScreenUpdaterImplementation",
        "LockScreen_LockScreenImpl.LockScreenResolverImplementation",
        "LockScreen_LockScreenImpl.LockScreenServiceImplementation"
    ]

    private let selectorsToProbe = [
        "viewModel",
        "model",
        "state",
        "playerState",
        "currentState",
        "currentTrack",
        "track",
        "trackTitle",
        "artistName",
        "artistTitle",
        "URI",
        "uri",
        "metadata",
        "isPlaying",
        "isPaused",
        "isActive",
        "playbackState",
        "nowPlayingBarState",
        "nowPlayingBarViewModel",
        "nowPlayingInfo",
        "updateNowPlayingInfo",
        "updateNowPlayingInfo:",
        "publishState:",
        "setState:",
        "setModel:",
        "configureWithModel:",
        "configureWithViewModel:",
        "setViewModel:"
    ]

    private let objectSelectorsToSnapshot = [
        "viewModel",
        "model",
        "state",
        "playerState",
        "currentState",
        "currentTrack",
        "track",
        "nowPlayingBarState",
        "nowPlayingBarViewModel",
        "nowPlayingInfo"
    ]

    private init() { }

    func install() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.scanBottomBanner(reason: "timer")
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.runClassProbeOnce()
            self.scanBottomBanner(reason: "install")
        }
    }

    func noteController(_ controller: UIViewController, reason: String) {
        let className = NSStringFromClass(type(of: controller))
        guard shouldLogClass(className, lastLogByClass: &lastControllerLogByClass, interval: 1.0) else { return }

        let responder = responderChain(from: controller, limit: 10).joined(separator: " > ")
        let viewSummary = controller.isViewLoaded ? describeView(controller.view, root: controller.view, window: controller.view.window) : "view-not-loaded"
        let slots = objectSlotSummary(for: controller)
        studifyOverlayLog("Banner/state controller reason=\(reason) class=\(className) slots=\(slots) responder=\(responder) view=\(viewSummary)")
        scanBottomBanner(reason: "controller-\(shortClass(className))")
    }

    func noteView(_ view: UIView, reason: String) {
        let className = NSStringFromClass(type(of: view))
        guard shouldLogClass(className, lastLogByClass: &lastViewLogByClass, interval: 1.0) else { return }

        let text = usefulTextValues(in: view, maxDepth: 6).prefix(6).joined(separator: " | ")
        let responder = responderChain(from: view, limit: 10).joined(separator: " > ")
        let slots = objectSlotSummary(for: view)
        studifyOverlayLog("Banner/state view reason=\(reason) class=\(className) slots=\(slots) view=\(describeView(view, root: view.window ?? view, window: view.window)) text=\(text) responder=\(responder)")
        scanBottomBanner(reason: "view-\(shortClass(className))")
    }

    func scanBottomBanner(reason: String) {
        guard let window = activeWindow() else { return }

        let candidates = bottomCandidates(in: window)
        let signature = candidates
            .prefix(8)
            .map { "\($0.score):\($0.className):\($0.text)" }
            .joined(separator: " || ")

        let now = Date()
        guard signature != lastBottomSignature || now.timeIntervalSince(lastBottomLogAt) > 3 else { return }
        lastBottomSignature = signature
        lastBottomLogAt = now

        let detail = candidates.prefix(10).map { candidate in
            "score=\(candidate.score) class=\(candidate.className) frame=\(format(rect: candidate.rect)) bg=\(candidate.background) controls=\(candidate.controls) text=\(candidate.text) selectors=\(candidate.selectors) slots=\(candidate.slots)"
        }
        .joined(separator: "\n")

        studifyOverlayLog("Banner/state bottom probe reason=\(reason) candidates=\(candidates.count)\n\(detail)")
    }

    private func runClassProbeOnce() {
        guard !didRunClassProbe else { return }
        didRunClassProbe = true

        let lines = candidateClasses.map { className -> String in
            guard let cls = NSClassFromString(className) as? NSObject.Type else {
                return "missing \(className)"
            }

            let selectors = selectorsToProbe.filter {
                cls.instancesRespond(to: Selector(($0))) || cls.responds(to: Selector(($0)))
            }
            let methods = "method-scan-disabled-in-clean-build"
            return "found \(className) selectors=\(selectors.joined(separator: ",")) methods=\(methods)"
        }

        studifyOverlayLog("Banner/state class probe\n\(lines.joined(separator: "\n"))")
    }

    private func bottomCandidates(in window: UIWindow) -> [(score: Int, className: String, rect: CGRect, text: String, background: String, controls: String, selectors: String, slots: String)] {
        let bottomInset = max(window.safeAreaInsets.bottom, 0)
        let minY = window.bounds.height - bottomInset - 300

        return views(in: window, maxDepth: 14)
            .compactMap { view -> (score: Int, className: String, rect: CGRect, text: String, background: String, controls: String, selectors: String, slots: String)? in
                guard !view.isHidden, view.alpha > 0.01 else { return nil }
                let rect = view.convert(view.bounds, to: window)
                guard rect.maxY >= minY,
                      rect.minY <= window.bounds.height,
                      rect.width >= window.bounds.width * 0.45,
                      rect.height >= 20,
                      rect.height <= 170
                else {
                    return nil
                }

                let className = NSStringFromClass(type(of: view))
                let lowerClass = className.lowercased()
                let text = usefulTextValues(in: view, maxDepth: 5).prefix(8).joined(separator: " | ")
                let lowerText = text.lowercased()
                let controls = controlSummary(in: view)
                let selectors = selectorSummary(for: view)
                let slots = objectSlotSummary(for: view)
                let background = describe(color: view.backgroundColor)

                var score = 0
                if lowerClass.contains("nowplaying") { score += 80 }
                if lowerClass.contains("bar") { score += 45 }
                if lowerClass.contains("player") { score += 35 }
                if lowerClass.contains("mini") { score += 20 }
                if lowerClass.contains("tabbar") { score -= 80 }
                if lowerText.contains("home") { score -= 20 }
                if lowerText.contains("search") { score -= 20 }
                if lowerText.contains("your library") { score -= 20 }
                if lowerText.contains("create") { score -= 20 }
                if text.contains(" | ") { score += 20 }
                if !text.isEmpty { score += 20 }
                if controls.contains("play") || controls.contains("pause") { score += 25 }
                if controls.contains("next") || controls.contains("previous") { score += 10 }
                if isRedSpotifyMiniPlayerColor(view.backgroundColor) { score += 60 }
                if rect.minY > window.bounds.height - bottomInset - 175 { score += 20 }
                if rect.height >= 44 && rect.height <= 95 { score += 20 }

                guard score > 0 else { return nil }
                return (score, className, rect, text, background, controls, selectors, slots)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.rect.minY > $1.rect.minY
            }
    }

    private func isRedSpotifyMiniPlayerColor(_ color: UIColor?) -> Bool {
        guard let color else { return false }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return alpha > 0.25 && red > green * 1.4 && red > blue * 1.2 && red > 0.25
    }

    private func controlSummary(in view: UIView) -> String {
        views(in: view, maxDepth: 4)
            .compactMap { subview -> String? in
                guard let control = subview as? UIControl else { return nil }
                let text = usefulTextValues(in: control, maxDepth: 3).prefix(4).joined(separator: "/")
                return "\(shortClass(NSStringFromClass(type(of: control))))[\(text)]"
            }
            .prefix(8)
            .joined(separator: ",")
    }

    private func selectorSummary(for object: NSObject) -> String {
        selectorsToProbe
            .filter { object.responds(to: Selector(($0))) }
            .prefix(12)
            .joined(separator: ",")
    }

    private func objectSlotSummary(for object: NSObject) -> String {
        objectSelectorsToSnapshot
            .compactMap { selectorName -> String? in
                let selector = Selector((selectorName))
                guard object.responds(to: selector),
                      methodReturnsObject(selector, on: object),
                      let value = object.perform(selector)?.takeUnretainedValue()
                else {
                    return nil
                }

                return "\(selectorName)=\(describe(value: value))"
            }
            .prefix(8)
            .joined(separator: ",")
    }

    private func methodReturnsObject(_ selector: Selector, on object: NSObject) -> Bool {
        guard let method = class_getInstanceMethod(type(of: object), selector),
              let encodingPointer = method_getTypeEncoding(method)
        else {
            return false
        }

        let encoding = String(cString: encodingPointer)
        return encoding.hasPrefix("@")
    }

    private func describe(value: AnyObject) -> String {
        if let string = value as? String {
            return cleanInline(string)
        }

        if let string = value as? NSString {
            return cleanInline(string as String)
        }

        if let url = value as? URL {
            return cleanInline(url.absoluteString)
        }

        if let url = value as? NSURL {
            return cleanInline(url.absoluteString ?? "")
        }

        if let dictionary = value as? NSDictionary {
            return describe(dictionary: dictionary)
        }

        if let view = value as? UIView {
            return "\(shortClass(NSStringFromClass(type(of: view)))){\(usefulTextValues(in: view, maxDepth: 3).prefix(4).joined(separator: "|"))}"
        }

        if let object = value as? NSObject {
            let className = shortClass(NSStringFromClass(type(of: object)))
            let trackText = trackLikeSummary(for: object)
            if !trackText.isEmpty {
                return "\(className){\(trackText)}"
            }
            return className
        }

        return cleanInline("\(value)")
    }

    private func describe(dictionary: NSDictionary) -> String {
        var pairs: [String] = []
        for (key, value) in dictionary {
            let keyString = cleanInline("\(key)")
            let valueString = cleanInline("\(value)")
            guard !keyString.isEmpty, !valueString.isEmpty else { continue }
            pairs.append("\(keyString):\(valueString)")
        }
        return "dict{\(pairs.prefix(6).joined(separator: "|"))}"
    }

    private func trackLikeSummary(for object: NSObject) -> String {
        let title = readObjectString(from: object, selectorNames: ["trackTitle", "title", "name"])
        let artist = readObjectString(from: object, selectorNames: ["artistTitle", "artistName", "artist", "artistDisplayName"])
        let uri = readObjectString(from: object, selectorNames: ["URI", "uri", "trackURI", "trackUri"])

        return [
            title.isEmpty ? nil : "title=\(title)",
            artist.isEmpty ? nil : "artist=\(artist)",
            uri.isEmpty ? nil : "uri=\(uri)"
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    private func readObjectString(from object: NSObject, selectorNames: [String]) -> String {
        for selectorName in selectorNames {
            let selector = Selector((selectorName))
            guard object.responds(to: selector),
                  methodReturnsObject(selector, on: object),
                  let value = object.perform(selector)?.takeUnretainedValue()
            else {
                continue
            }

            let clean = describe(value: value)
            if !clean.isEmpty {
                return clean
            }
        }

        return ""
    }

    private func cleanInline(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func shouldLogClass(_ className: String, lastLogByClass: inout [String: Date], interval: TimeInterval) -> Bool {
        let lower = className.lowercased()
        guard lower.contains("nowplaying")
            || lower.contains("lockscreen")
            || lower.contains("player")
            || lower.contains("bar")
        else {
            return false
        }

        let now = Date()
        if let last = lastLogByClass[className], now.timeIntervalSince(last) < interval {
            return false
        }
        lastLogByClass[className] = now
        return true
    }

    private func usefulTextValues(in view: UIView, maxDepth: Int, depth: Int = 0) -> [String] {
        guard depth <= maxDepth else { return [] }
        var values: [String] = []

        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            values.append(text)
        }
        if let button = view as? UIButton {
            if let title = button.title(for: .normal), !title.isEmpty {
                values.append(title)
            }
            if let currentTitle = button.currentTitle, !currentTitle.isEmpty {
                values.append(currentTitle)
            }
        }
        if let accessibilityLabel = view.accessibilityLabel, !accessibilityLabel.isEmpty {
            values.append(accessibilityLabel)
        }
        if let accessibilityIdentifier = view.accessibilityIdentifier, !accessibilityIdentifier.isEmpty {
            values.append(accessibilityIdentifier)
        }

        var seen = Set<String>()
        for subview in view.subviews {
            values.append(contentsOf: usefulTextValues(in: subview, maxDepth: maxDepth, depth: depth + 1))
        }

        return values.compactMap { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !seen.contains(clean) else { return nil }
            seen.insert(clean)
            return clean
        }
    }

    private func views(in root: UIView, maxDepth: Int, depth: Int = 0) -> [UIView] {
        guard depth <= maxDepth else { return [] }
        return [root] + root.subviews.flatMap { views(in: $0, maxDepth: maxDepth, depth: depth + 1) }
    }

    private func responderChain(from responder: UIResponder?, limit: Int) -> [String] {
        var values: [String] = []
        var current = responder
        var depth = 0
        while let candidate = current, depth < limit {
            values.append(NSStringFromClass(type(of: candidate)))
            current = candidate.next
            depth += 1
        }
        return values
    }

    private func describeView(_ view: UIView?, root: UIView, window: UIWindow?) -> String {
        guard let view else { return "nil" }
        let coordinateRoot = window ?? root
        return "class=\(NSStringFromClass(type(of: view))) frame=\(format(rect: view.convert(view.bounds, to: coordinateRoot))) text=\(usefulTextValues(in: view, maxDepth: 4).prefix(5).joined(separator: " | ")) selectors=\(selectorSummary(for: view)) slots=\(objectSlotSummary(for: view))"
    }

    private func activeWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }

            return windows.first(where: { $0.isKeyWindow })
                ?? windows.first(where: { !$0.isHidden && $0.alpha > 0 })
                ?? UIApplication.shared.windows.first(where: { $0.isKeyWindow })
                ?? UIApplication.shared.windows.first
        }

        return UIApplication.shared.keyWindow ?? UIApplication.shared.windows.first
    }

    private func shortClass(_ className: String) -> String {
        className.components(separatedBy: ".").suffix(2).joined(separator: ".")
    }

    private func format(rect: CGRect) -> String {
        "[\(format(rect.minX)),\(format(rect.minY)),\(format(rect.width)),\(format(rect.height))]"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private func describe(color: UIColor?) -> String {
        guard let color else { return "nil" }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return "rgba(\(format(red)),\(format(green)),\(format(blue)),\(format(alpha)))"
        }
        var white: CGFloat = 0
        if color.getWhite(&white, alpha: &alpha) {
            return "wa(\(format(white)),\(format(alpha)))"
        }
        return "\(color)"
    }
}

class StudifyNowPlayingBarContainerControllerProbeHook: ClassHook<UIViewController> {
    typealias Group = StudifyBannerStateProbeHookGroup
    static let targetName = "NowPlaying_BarImpl.NowPlayingBarContainerViewController"

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        StudifyBannerStateProbe.shared.noteController(target, reason: "container-viewDidLayoutSubviews")
    }

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        StudifyBannerStateProbe.shared.noteController(target, reason: "container-viewDidAppear")
    }
}

class StudifyNowPlayingBarControllerProbeHook: ClassHook<UIViewController> {
    typealias Group = StudifyBannerStateProbeHookGroup
    static let targetName = "NowPlaying_BarImpl.NowPlayingBarViewController"

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        StudifyBannerStateProbe.shared.noteController(target, reason: "bar-viewDidLayoutSubviews")
    }

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        StudifyBannerStateProbe.shared.noteController(target, reason: "bar-viewDidAppear")
    }
}

class StudifyNowPlayingBarViewProbeHook: ClassHook<UIView> {
    typealias Group = StudifyBannerStateProbeHookGroup
    static let targetName = "NowPlaying_BarImpl.NowPlayingBarView"

    func layoutSubviews() {
        orig.layoutSubviews()
        StudifyBannerStateProbe.shared.noteView(target, reason: "bar-layoutSubviews")
    }
}
