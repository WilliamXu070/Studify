import Foundation
import Orion
import UIKit

var studifyOnlinePlaybackProbeEnabled: Bool {
    UserDefaults.standard.bool(forKey: "StudifyEnableOnlinePlaybackProbe")
}

private struct StudifyOnlineProbeTrack: Equatable {
    let title: String
    let artist: String
}

final class StudifyOnlinePlaybackProbe: NSObject, UIGestureRecognizerDelegate {
    static let shared = StudifyOnlinePlaybackProbe()

    private var installed = false
    private weak var installedWindow: UIWindow?
    private var tapGesture: UITapGestureRecognizer?
    private var sampleTimer: Timer?
    private var lastSignature = ""
    private var lastControlLogAtByKey: [String: Date] = [:]

    private override init() {
        super.init()
    }

    func install() {
        guard studifyOnlinePlaybackProbeEnabled else { return }

        DispatchQueue.main.async {
            guard !self.installed else { return }
            self.installed = true

            self.sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.refresh(reason: "timer")
            }
            if let sampleTimer = self.sampleTimer {
                RunLoop.main.add(sampleTimer, forMode: .common)
            }

            self.refresh(reason: "install")
            studifyOverlayLog("Online playback probe installed")
        }
    }

    func observeControl(_ control: UIControl, actionName: String, receiver: AnyObject?, event: UIEvent?) {
        guard studifyOnlinePlaybackProbeEnabled else { return }

        let context = usefulText(in: control, maxDepth: 3).prefix(8).joined(separator: " | ")
        let receiverClass = receiver.map { NSStringFromClass(type(of: $0)) } ?? "nil"
        let key = "\(actionName)-\(NSStringFromClass(type(of: control)))-\(receiverClass)-\(context)"
        let now = Date()
        if let last = lastControlLogAtByKey[key], now.timeIntervalSince(last) < 0.75 {
            return
        }
        lastControlLogAtByKey[key] = now

        studifyOverlayLog(
            "Online playback probe control action=\(actionName) control=\(NSStringFromClass(type(of: control))) receiver=\(receiverClass) enabled=\(control.isEnabled) selected=\(control.isSelected) highlighted=\(control.isHighlighted) eventType=\(event?.type.rawValue ?? -1) text=\(context)"
        )
        StudifySpotifyStateBridge.shared.logCurrentSpotifyState(reason: "online-control-\(actionName)", force: true)
    }

    private func refresh(reason: String) {
        guard let window = activeWindow() else { return }
        installTapRecognizerIfNeeded(on: window)

        let rows = visibleTrackRows(in: window)
        let rowText = rows.prefix(6).map { row in
            track(from: row).map { "\($0.title) - \($0.artist)" } ?? usefulText(in: row, maxDepth: 4).prefix(4).joined(separator: " / ")
        }
        let bottom = bottomSnapshot(in: window, rootName: "bottom")
        let bottomText = bottom.entries.prefix(12).map(\.value).joined(separator: " || ")
        let signature = "rows=\(rowText.joined(separator: " || ")) bottom=\(bottomText)"

        guard signature != lastSignature else { return }
        lastSignature = signature

        studifyOverlayLog(
            "Online playback probe sample reason=\(reason) rows=\(rows.count) rowText=\(rowText.joined(separator: " || "))\n\(format(snapshot: bottom, maxLines: 24))"
        )
        StudifySpotifyStateBridge.shared.logCurrentSpotifyState(reason: "online-sample-\(reason)", force: true)
    }

    private func installTapRecognizerIfNeeded(on window: UIWindow) {
        guard installedWindow !== window else { return }

        if let tapGesture {
            tapGesture.view?.removeGestureRecognizer(tapGesture)
        }

        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)

        tapGesture = recognizer
        installedWindow = window
        studifyOverlayLog("Online playback probe attached window=\(NSStringFromClass(type(of: window)))")
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let window = recognizer.view as? UIWindow
        else {
            return
        }

        let point = recognizer.location(in: window)
        guard let hitView = window.hitTest(point, with: nil) else { return }

        let row = trackRow(startingAt: hitView)
        let rowTrack = row.flatMap { track(from: $0) }
        let hitText = usefulText(in: hitView, maxDepth: 2).prefix(6).joined(separator: " | ")
        let rowText = row.map { usefulText(in: $0, maxDepth: 4).prefix(8).joined(separator: " | ") } ?? "nil"
        let bottomBefore = bottomSnapshot(in: window, rootName: "bottom-before")
        let rowBefore = row.map { snapshot(from: $0, rootName: "row-before", maxDepth: 5, maxNodes: 80) }

        studifyOverlayLog(
            "Online playback probe tap hit=\(NSStringFromClass(type(of: hitView))) hitText=\(hitText) rowTrack=\(rowTrack.map { "\($0.title) - \($0.artist)" } ?? "nil") rowText=\(rowText)\n\(format(snapshot: bottomBefore, maxLines: 28))"
        )
        StudifySpotifyStateBridge.shared.logCurrentSpotifyState(reason: "online-tap-before", force: true)
        if let rowBefore, let rowTrack {
            log(snapshot: rowBefore, reason: "online-row-before", track: rowTrack, maxLines: 28)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.logAfterTap(window: window, row: row, rowTrack: rowTrack, bottomBefore: bottomBefore, rowBefore: rowBefore, delayLabel: "350ms")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.logAfterTap(window: window, row: row, rowTrack: rowTrack, bottomBefore: bottomBefore, rowBefore: rowBefore, delayLabel: "1200ms")
        }
    }

    private func logAfterTap(
        window: UIWindow,
        row: UIView?,
        rowTrack: StudifyOnlineProbeTrack?,
        bottomBefore: StudifyOnlineProbeSnapshot,
        rowBefore: StudifyOnlineProbeSnapshot?,
        delayLabel: String
    ) {
        guard window.windowScene != nil || window.superview != nil else { return }

        let bottomAfter = bottomSnapshot(in: window, rootName: "bottom-after-\(delayLabel)")
        studifyOverlayLog(
            "Online playback probe bottom-after delay=\(delayLabel)\n\(format(snapshot: bottomAfter, maxLines: 28))"
        )
        logDiff(before: bottomBefore, after: bottomAfter, reason: "online-bottom-diff-\(delayLabel)")
        StudifySpotifyStateBridge.shared.logCurrentSpotifyState(reason: "online-tap-after-\(delayLabel)", force: true)

        guard let row, let rowBefore, let rowTrack else { return }
        let rowAfter = snapshot(from: row, rootName: "row-after-\(delayLabel)", maxDepth: 5, maxNodes: 80)
        log(snapshot: rowAfter, reason: "online-row-after-\(delayLabel)", track: rowTrack, maxLines: 28)
        logDiff(before: rowBefore, after: rowAfter, reason: "online-row-diff-\(delayLabel)")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === tapGesture,
              let window = gestureRecognizer.view as? UIWindow
        else {
            return false
        }

        let point = touch.location(in: window)
        guard let hitView = window.hitTest(point, with: nil) else { return false }
        if trackRow(startingAt: hitView) != nil { return true }
        if bottomPlayerCandidate(startingAt: hitView, in: window) != nil { return true }
        if hitView is UIControl { return true }
        return false
    }

    private func visibleTrackRows(in window: UIWindow) -> [UIView] {
        views(in: window, maxDepth: 13).filter { view in
            !view.isHidden && view.alpha > 0.01 && looksLikeTrackRow(view)
        }
    }

    private func trackRow(startingAt view: UIView) -> UIView? {
        var current: UIView? = view
        var depth = 0
        while let candidate = current, depth < 10 {
            if looksLikeTrackRow(candidate) {
                return candidate
            }
            current = candidate.superview
            depth += 1
        }
        return nil
    }

    private func looksLikeTrackRow(_ view: UIView) -> Bool {
        let text = usefulText(in: view, maxDepth: 4)
        guard text.count >= 2, track(fromText: text) != nil else { return false }

        let rect = view.window.map { view.convert(view.bounds, to: $0) } ?? view.bounds
        guard rect.width > 180, rect.height >= 36, rect.height <= 130 else { return false }

        let joined = text.joined(separator: " ").lowercased()
        if joined.contains("recommended songs") || joined.contains("go online") || joined.contains("your library") {
            return false
        }
        return true
    }

    private func track(from row: UIView) -> StudifyOnlineProbeTrack? {
        track(fromText: usefulText(in: row, maxDepth: 4))
    }

    private func track(fromText text: [String]) -> StudifyOnlineProbeTrack? {
        var values: [String] = []
        var seen = Set<String>()
        for value in text {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty,
                  !seen.contains(clean),
                  !isIgnoredText(clean)
            else {
                continue
            }
            seen.insert(clean)
            values.append(clean)
        }

        guard values.count >= 2 else { return nil }
        return StudifyOnlineProbeTrack(title: values[0], artist: values[1])
    }

    private func bottomSnapshot(in window: UIWindow, rootName: String) -> StudifyOnlineProbeSnapshot {
        let minY = window.bounds.height - max(window.safeAreaInsets.bottom, 0) - 230
        return snapshot(
            from: window,
            rootName: rootName,
            maxDepth: 9,
            maxNodes: 90
        ) { view in
            guard !view.isHidden, view.alpha > 0.01 else { return false }
            let rect = view.convert(view.bounds, to: window)
            return rect.maxY >= minY
                && rect.minY <= window.bounds.height
                && rect.width >= 24
                && rect.height >= 10
        }
    }

    private func bottomPlayerCandidate(startingAt view: UIView, in window: UIWindow) -> UIView? {
        var current: UIView? = view
        var depth = 0
        let minY = window.bounds.height - max(window.safeAreaInsets.bottom, 0) - 210
        while let candidate = current, depth < 8 {
            let rect = candidate.convert(candidate.bounds, to: window)
            let text = usefulText(in: candidate, maxDepth: 4).joined(separator: " ").lowercased()
            let className = NSStringFromClass(type(of: candidate)).lowercased()
            if rect.maxY >= minY,
               rect.height >= 36,
               rect.width >= window.bounds.width * 0.45,
               (className.contains("nowplaying") || className.contains("bar") || text.contains("pause") || text.contains("play")) {
                return candidate
            }
            current = candidate.superview
            depth += 1
        }
        return nil
    }

    private func snapshot(
        from root: UIView,
        rootName: String,
        maxDepth: Int,
        maxNodes: Int,
        include: ((UIView) -> Bool)? = nil
    ) -> StudifyOnlineProbeSnapshot {
        var entries: [(key: String, value: String)] = []
        collectSnapshotEntries(
            from: root,
            root: root,
            path: rootName,
            depth: 0,
            maxDepth: maxDepth,
            maxNodes: maxNodes,
            entries: &entries,
            include: include
        )
        return StudifyOnlineProbeSnapshot(entries: entries)
    }

    private func collectSnapshotEntries(
        from view: UIView,
        root: UIView,
        path: String,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        entries: inout [(key: String, value: String)],
        include: ((UIView) -> Bool)?
    ) {
        guard depth <= maxDepth, entries.count < maxNodes else { return }

        if let include, !include(view) {
            for (index, subview) in view.subviews.enumerated() where entries.count < maxNodes {
                collectSnapshotEntries(
                    from: subview,
                    root: root,
                    path: "\(path).\(index)",
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    maxNodes: maxNodes,
                    entries: &entries,
                    include: include
                )
            }
            return
        }

        entries.append((path, describe(view: view, root: root, depth: depth)))

        for (index, subview) in view.subviews.enumerated() where entries.count < maxNodes {
            collectSnapshotEntries(
                from: subview,
                root: root,
                path: "\(path).\(index)",
                depth: depth + 1,
                maxDepth: maxDepth,
                maxNodes: maxNodes,
                entries: &entries,
                include: include
            )
        }
    }

    private func describe(view: UIView, root: UIView, depth: Int) -> String {
        let rect = view.convert(view.bounds, to: root)
        var parts = [
            "d=\(depth)",
            "class=\(NSStringFromClass(type(of: view)))",
            "frame=\(format(rect: rect))",
            "hidden=\(view.isHidden)",
            "alpha=\(format(view.alpha))",
            "user=\(view.isUserInteractionEnabled)"
        ]

        if let label = view as? UILabel {
            parts.append("text=\(clean(label.text))")
            parts.append("textColor=\(describe(color: label.textColor))")
            parts.append("enabled=\(label.isEnabled)")
        }
        if let button = view as? UIButton {
            parts.append("buttonTitle=\(clean(button.currentTitle))")
            parts.append("buttonEnabled=\(button.isEnabled)")
            parts.append("buttonSelected=\(button.isSelected)")
        }
        if let control = view as? UIControl {
            parts.append("controlEnabled=\(control.isEnabled)")
            parts.append("controlSelected=\(control.isSelected)")
            parts.append("controlHighlighted=\(control.isHighlighted)")
        }
        if let imageView = view as? UIImageView {
            parts.append("image=\(imageView.image == nil ? "nil" : "set")")
            parts.append("highlighted=\(imageView.isHighlighted)")
        }
        if let progressView = view as? UIProgressView {
            parts.append("progress=\(format(progressView.progress))")
        }

        parts.append("tint=\(describe(color: view.tintColor))")
        if let backgroundColor = view.backgroundColor {
            parts.append("bg=\(describe(color: backgroundColor))")
        }
        if let accessibilityLabel = view.accessibilityLabel, !accessibilityLabel.isEmpty {
            parts.append("axLabel=\(clean(accessibilityLabel))")
        }
        if let accessibilityValue = view.accessibilityValue, !accessibilityValue.isEmpty {
            parts.append("axValue=\(clean(accessibilityValue))")
        }
        if let accessibilityIdentifier = view.accessibilityIdentifier, !accessibilityIdentifier.isEmpty {
            parts.append("axId=\(clean(accessibilityIdentifier))")
        }

        return parts.joined(separator: " ")
    }

    private func log(snapshot: StudifyOnlineProbeSnapshot, reason: String, track: StudifyOnlineProbeTrack, maxLines: Int) {
        studifyOverlayLog(
            "Online playback probe snapshot reason=\(reason) title=\(track.title) artist=\(track.artist) lines=\(snapshot.entries.count)\n\(format(snapshot: snapshot, maxLines: maxLines))"
        )
    }

    private func logDiff(before: StudifyOnlineProbeSnapshot, after: StudifyOnlineProbeSnapshot, reason: String) {
        let beforeMap = Dictionary(uniqueKeysWithValues: before.entries.map { ($0.key, $0.value) })
        let afterMap = Dictionary(uniqueKeysWithValues: after.entries.map { ($0.key, $0.value) })
        let keys = Array(Set(beforeMap.keys).union(afterMap.keys)).sorted()

        var changes: [String] = []
        for key in keys {
            let beforeValue = beforeMap[key]
            let afterValue = afterMap[key]
            guard beforeValue != afterValue else { continue }
            if let beforeValue, let afterValue {
                changes.append("\(key) BEFORE \(beforeValue)")
                changes.append("\(key) AFTER  \(afterValue)")
            } else if let beforeValue {
                changes.append("\(key) REMOVED \(beforeValue)")
            } else if let afterValue {
                changes.append("\(key) ADDED \(afterValue)")
            }
            if changes.count >= 34 { break }
        }

        studifyOverlayLog("Online playback probe diff reason=\(reason) changes=\(changes.count)\n\(changes.joined(separator: "\n"))")
    }

    private func format(snapshot: StudifyOnlineProbeSnapshot, maxLines: Int) -> String {
        snapshot.entries
            .prefix(maxLines)
            .map { "\($0.key) \($0.value)" }
            .joined(separator: "\n")
    }

    private func usefulText(in view: UIView, maxDepth: Int, depth: Int = 0) -> [String] {
        guard depth <= maxDepth, !view.isHidden, view.alpha > 0.01 else { return [] }
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
        if let accessibilityValue = view.accessibilityValue, !accessibilityValue.isEmpty {
            values.append(accessibilityValue)
        }
        if let accessibilityIdentifier = view.accessibilityIdentifier, !accessibilityIdentifier.isEmpty {
            values.append(accessibilityIdentifier)
        }

        for subview in view.subviews {
            values.append(contentsOf: usefulText(in: subview, maxDepth: maxDepth, depth: depth + 1))
        }

        var seen = Set<String>()
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

    private func isIgnoredText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let exactIgnored: Set<String> = [
            "home",
            "search",
            "your library",
            "create",
            "add",
            "edit",
            "sort",
            "name & details",
            "recommended songs",
            "based on the songs of this playlist",
            "play",
            "pause",
            "next",
            "prev",
            "previous",
            "shuffle",
            "repeat",
            "william",
            "test"
        ]

        if exactIgnored.contains(lower) { return true }
        if lower.hasSuffix("min") && lower.allSatisfy({ $0.isNumber || $0 == "m" || $0 == "i" || $0 == "n" }) {
            return true
        }
        return lower.contains("download") || lower.contains("offline")
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

    private func clean(_ value: String?) -> String {
        let cleanValue = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        if cleanValue.count > 100 {
            return "\(cleanValue.prefix(100))..."
        }
        return cleanValue
    }

    private func format(rect: CGRect) -> String {
        "[\(format(rect.minX)),\(format(rect.minY)),\(format(rect.width)),\(format(rect.height))]"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    private func format(_ value: Float) -> String {
        String(format: "%.2f", Double(value))
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

private struct StudifyOnlineProbeSnapshot {
    let entries: [(key: String, value: String)]
}
