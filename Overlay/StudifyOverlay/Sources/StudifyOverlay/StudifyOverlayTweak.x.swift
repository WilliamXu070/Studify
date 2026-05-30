import Foundation
import Orion
import UIKit

let studifyOverlayDefaultServerURL = "http://172.17.144.67:8787"
var studifyOverlayProbeModeEnabled: Bool {
    studifyOverlayProbeModeIsEnabled()
}
private var didShowStudifyOverlayProbe = false
private var lastStudifyOverlaySignalAt = Date(timeIntervalSince1970: 0)

struct StudifyOverlayDownloadHookGroup: HookGroup { }
struct StudifyOverlayProbeHookGroup: HookGroup { }

private func studifyOverlayClassName(_ object: AnyObject?) -> String {
    guard let object else { return "nil" }
    return NSStringFromClass(type(of: object))
}

private func studifyOverlayResponderChain(from responder: UIResponder?, limit: Int = 12) -> [String] {
    var values: [String] = []
    var current = responder
    var depth = 0

    while let object = current, depth < limit {
        values.append(NSStringFromClass(type(of: object)))
        current = object.next
        depth += 1
    }

    return values
}

private func studifyOverlayControlRouteSummary(control: UIControl, actionName: String, receiver: AnyObject?, event: UIEvent?) -> [String: Any] {
    let labels = studifyOverlayControlContext(from: control)
        .prefix(8)
        .joined(separator: " | ")

    return [
        "action": actionName,
        "controlClass": NSStringFromClass(type(of: control)),
        "receiverClass": studifyOverlayClassName(receiver),
        "receiverResponds": (receiver as? NSObject)?.responds(to: Selector((actionName))) ?? false,
        "enabled": control.isEnabled,
        "selected": control.isSelected,
        "highlighted": control.isHighlighted,
        "eventType": event?.type.rawValue ?? -1,
        "eventSubtype": event?.subtype.rawValue ?? -1,
        "labels": labels,
        "responderChain": studifyOverlayResponderChain(from: control).joined(separator: " > ")
    ]
}

func studifyOverlayLog(_ message: String) {
    NSLog("[StudifyOverlay] %@", message)

    let path = NSTemporaryDirectory() + "studify_overlay_debug.log"
    let line = "[\(Date())] \(message)\n"

    if FileManager.default.fileExists(atPath: path),
       let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

struct StudifyOverlay: Tweak {
    init() {
        studifyOverlayLog("Studify overlay starting")
        studifyOverlayLog("Studify probe upload enabled=\(studifyOverlayProbeUploadIsEnabled())")

        if !StudifyOverlayDownloadHookGroup.isActive {
            StudifyOverlayDownloadHookGroup().activate()
            studifyOverlayLog("Activated UIControl download hook group")
        }

        studifyActivateSpotifyStateBridge()
        studifyActivateBannerStateProbe()
        studifyActivateOfflinePlayableSpoofGroups()
        StudifyFakePlaybackController.shared.install()
        StudifyOnlinePlaybackProbe.shared.install()

        if studifyOverlayProbeModeEnabled {
            studifyActivateOfflinePathwayMethodProbeGroups()

            if !StudifyOverlayProbeHookGroup.isActive {
                StudifyOverlayProbeHookGroup().activate()
                studifyOverlayLog("Activated Studify probe hook group")
            }
            StudifyOfflinePathwayProbe.shared.runClassProbeOnce()
            StudifyProbeStreamClient.shared.emit(
                hook: "overlay",
                phase: "started",
                message: "Studify overlay started",
                requireActive: false
            )
        } else {
            studifyOverlayLog("Studify probe mode disabled")
        }
    }
}

private func studifyOverlayCollectText(from view: UIView, depth: Int = 0) -> [String] {
    guard depth <= 4 else { return [] }

    var values: [String] = []

    if let label = view.accessibilityLabel, !label.isEmpty {
        values.append(label)
    }

    if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
        values.append(identifier)
    }

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

    for subview in view.subviews {
        values.append(contentsOf: studifyOverlayCollectText(from: subview, depth: depth + 1))
    }

    return values
}

private func studifyOverlayControlContext(from control: UIControl) -> [String] {
    var values = studifyOverlayCollectText(from: control)
    var superview = control.superview
    var depth = 0

    while let view = superview, depth < 5 {
        values.append(contentsOf: studifyOverlayCollectText(from: view, depth: 3))
        superview = view.superview
        depth += 1
    }

    return Array(Set(values))
}

private func studifyOverlayLooksLikeDownloadControl(_ control: UIControl, actionName: String) -> Bool {
    let values = studifyOverlayControlContext(from: control)
    let joined = (values + [actionName]).joined(separator: " ").lowercased()

    let mentionsDownloadIntent = joined.contains("download")
        || joined.contains("offline")
        || joined.contains("offlining")

    guard mentionsDownloadIntent else {
        return false
    }

    return joined.contains("playlist")
        || joined.contains("album")
        || joined.contains("episode")
        || joined.contains("offline")
        || values.count <= 6
}

private func studifyOverlayPlaylistURI(startingAt responder: UIResponder?) -> String {
    let selectors = [
        Selector(("pageURI")),
        Selector(("spt_pageURI")),
        Selector(("viewURI")),
        Selector(("uri"))
    ]

    var current = responder
    var depth = 0

    while let object = current as? NSObject, depth < 12 {
        for selector in selectors where object.responds(to: selector) {
            if let value = object.perform(selector)?.takeUnretainedValue() {
                if let url = value as? NSURL,
                   let uri = url.absoluteString,
                   uri.contains("spotify:playlist:") {
                    return uri
                }

                if let string = value as? NSString,
                   string.contains("spotify:playlist:") {
                    return string as String
                }
            }
        }

        current = current?.next
        depth += 1
    }

    return "spotify:playlist:studify-overlay-fallback"
}

private func studifyOverlaySendSignal(from control: UIControl) {
    let now = Date()
    guard now.timeIntervalSince(lastStudifyOverlaySignalAt) > 2 else {
        studifyOverlayLog("Ignoring duplicate download signal")
        StudifyProbeStreamClient.shared.extend(reason: "duplicate download/offline control")
        return
    }

    lastStudifyOverlaySignalAt = now

    let playlistURI = studifyOverlayPlaylistURI(startingAt: control)
    let labels = studifyOverlayControlContext(from: control).joined(separator: " | ")

    studifyOverlayLog("Download control matched playlistURI=\(playlistURI) labels=\(labels)")
    StudifyProbeStreamClient.shared.start(reason: "download/offline button")
    StudifyProbeStreamClient.shared.emit(
        hook: "download-control",
        phase: "matched",
        message: playlistURI,
        className: NSStringFromClass(type(of: control)),
        selector: "sendAction:to:forEvent:",
        data: ["labels": labels],
        requireActive: false
    )
    StudifyOverlayBanner.show(
        title: "STUDIFY OVERLAY HOOK FIRED",
        detail: playlistURI,
        color: UIColor(red: 0.95, green: 0.62, blue: 0.08, alpha: 0.96),
        duration: 5
    )

    guard !studifyOverlayProbeModeEnabled else {
        studifyOverlayLog("Download signal skipped while probe mode is local-only")
        return
    }

    StudifyOverlaySignalClient.shared.startPlaylistJob(playlistURI: playlistURI)
}

class StudifyOverlayUIControlHook: ClassHook<UIControl> {
    typealias Group = StudifyOverlayDownloadHookGroup
    static let targetName = "UIControl"

    @objc(sendAction:to:forEvent:)
    func sendAction(_ action: Selector, to receiver: AnyObject?, for event: UIEvent?) {
        let actionName = NSStringFromSelector(action)

        if studifyOverlayProbeModeEnabled {
            let routeSummary = studifyOverlayControlRouteSummary(
                control: target,
                actionName: actionName,
                receiver: receiver,
                event: event
            )
            studifyOverlayLog(
                "Passive UIControl action route probe action=\(actionName) control=\(routeSummary["controlClass"] ?? "") receiver=\(routeSummary["receiverClass"] ?? "") receiverResponds=\(routeSummary["receiverResponds"] ?? false) enabled=\(target.isEnabled) selected=\(target.isSelected) highlighted=\(target.isHighlighted) labels=\(routeSummary["labels"] ?? "") chain=\(routeSummary["responderChain"] ?? "")"
            )
            StudifyProbeStreamClient.shared.emit(
                hook: "uicontrol",
                phase: "sendAction",
                message: actionName,
                className: NSStringFromClass(type(of: target)),
                selector: actionName,
                data: routeSummary,
                throttleKey: "uicontrol-\(actionName)-\(NSStringFromClass(type(of: target)))",
                minInterval: 0.75
            )

            if !didShowStudifyOverlayProbe {
                didShowStudifyOverlayProbe = true
                studifyOverlayLog("UIControl hook active; first action=\(actionName)")
                StudifyProbeStreamClient.shared.emit(
                    hook: "uicontrol",
                    phase: "active",
                    message: actionName,
                    className: NSStringFromClass(type(of: target)),
                    selector: actionName,
                    requireActive: false
                )
            }
        }

        if studifyOverlayLooksLikeDownloadControl(target, actionName: actionName) {
            studifyOverlaySendSignal(from: target)
            orig.sendAction(action, to: receiver, for: event)
            return
        }

        StudifyFakePlaybackController.shared.observeOfflineRowControlAction(target, actionName: actionName)
        StudifyFakePlaybackController.shared.observePlaybackControl(target, actionName: actionName)
        StudifyOnlinePlaybackProbe.shared.observeControl(target, actionName: actionName, receiver: receiver, event: event)
        orig.sendAction(action, to: receiver, for: event)
    }
}

class StudifyOverlayUIApplicationHook: ClassHook<UIApplication> {
    typealias Group = StudifyOverlayDownloadHookGroup
    static let targetName = "UIApplication"

    @objc(sendAction:to:from:forEvent:)
    func sendAction(_ action: Selector, to targetObject: AnyObject?, from sender: AnyObject?, for event: UIEvent?) -> Bool {
        let actionName = NSStringFromSelector(action)
        let senderResponder = sender as? UIResponder
        let targetClass = studifyOverlayClassName(targetObject)
        let senderClass = studifyOverlayClassName(sender)
        let senderChain = studifyOverlayResponderChain(from: senderResponder).joined(separator: " > ")

        if studifyOverlayProbeModeEnabled {
            studifyOverlayLog(
                "Passive UIApplication action route probe action=\(actionName) target=\(targetClass) sender=\(senderClass) senderChain=\(senderChain)"
            )
            StudifyProbeStreamClient.shared.emit(
                hook: "uiapplication",
                phase: "sendAction",
                message: actionName,
                className: senderClass,
                selector: actionName,
                data: [
                    "targetClass": targetClass,
                    "senderClass": senderClass,
                    "senderChain": senderChain,
                    "eventType": event?.type.rawValue ?? -1,
                    "eventSubtype": event?.subtype.rawValue ?? -1
                ],
                throttleKey: "uiapplication-\(actionName)-\(senderClass)-\(targetClass)",
                minInterval: 0.5,
                requireActive: false
            )
        }

        StudifyFakePlaybackController.shared.observeOfflineActionSender(sender, actionName: actionName)
        return orig.sendAction(action, to: targetObject, from: sender, for: event)
    }
}

class StudifyOverlayCollectionViewCellHook: ClassHook<UICollectionViewCell> {
    typealias Group = StudifyOverlayDownloadHookGroup
    static let targetName = "UICollectionViewCell"

    func layoutSubviews() {
        orig.layoutSubviews()
        StudifyFakePlaybackController.shared.refreshCell(target)
    }
}

class StudifyOverlayTableViewCellHook: ClassHook<UITableViewCell> {
    typealias Group = StudifyOverlayDownloadHookGroup
    static let targetName = "UITableViewCell"

    func layoutSubviews() {
        orig.layoutSubviews()
        StudifyFakePlaybackController.shared.refreshCell(target)
    }
}
