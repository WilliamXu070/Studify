import Orion
import UIKit

private func showHighQualityPopUp() {
    PopUpHelper.showPopUp(
        message: "high_audio_quality_popup".localized,
        buttonText: "OK".uiKitLocalized
    )
}

private func showPlaylistDownloadingPopUp(_ isPlaylist: Bool, onSecondaryClick: (() -> Void)?) {
    PopUpHelper.showPopUp(
        message: "playlist_downloading_popup".localized,
        buttonText: "OK".uiKitLocalized,
        secondButtonText: isPlaylist
            ? "download_local_playlist".localized
            : nil,
        onSecondaryClick: onSecondaryClick
    )
}

private func sendStudifyPlaylistDownloadSignal(pageURI: NSURL) {
    StudifyDownloadSignalClient.shared.startPlaylistJob(pageURI: pageURI) { result in
        switch result {
        case .success(let jobId):
            PopUpHelper.showPopUp(
                message: "Studify playlist job created.\n\nJob ID: \(jobId)\n\nOpen the Studify signal server dashboard on your Mac to watch state changes.",
                buttonText: "OK".uiKitLocalized
            )

        case .failure(let message):
            PopUpHelper.showPopUp(
                message: "Studify signal failed.\n\n\(message)",
                buttonText: "OK".uiKitLocalized
            )
        }
    }
}

private func handleStudifyDownloadToggle(pageURI: NSURL) {
    let playlistURI = pageURI.absoluteString ?? pageURI.description
    let isPlaylist = Dynamic.convert(pageURI, to: SPTURL.self)
        .isPlaylistURL()

    writeDebugLog("[STUDIFY] Intercepted offline toggle pageURI=\(playlistURI), isPlaylist=\(isPlaylist)")
    StudifyDebugVisualAid.intercepted("offline helper \(playlistURI)")

    guard isPlaylist else {
        StudifyDebugVisualAid.failed("Not a playlist URI")
        showPlaylistDownloadingPopUp(false, onSecondaryClick: nil)
        return
    }

    sendStudifyPlaylistDownloadSignal(pageURI: pageURI)
}

private var lastStudifyFallbackSignalAt = Date(timeIntervalSince1970: 0)

private func collectStudifyControlText(from view: UIView, depth: Int = 0) -> [String] {
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
        values.append(contentsOf: collectStudifyControlText(from: subview, depth: depth + 1))
    }

    return values
}

private func collectStudifyControlContext(from control: UIControl) -> [String] {
    var values = collectStudifyControlText(from: control)
    var superview = control.superview
    var depth = 0

    while let view = superview, depth < 5 {
        values.append(contentsOf: collectStudifyControlText(from: view, depth: 3))
        superview = view.superview
        depth += 1
    }

    return Array(Set(values))
}

private func studifyLooksLikeDownloadControl(_ control: UIControl, actionName: String) -> Bool {
    let values = collectStudifyControlContext(from: control)
    let joined = (values + [actionName]).joined(separator: " ").lowercased()

    guard joined.contains("download") else {
        return false
    }

    return joined.contains("playlist")
        || joined.contains("album")
        || joined.contains("episode")
        || joined.contains("offline")
        || values.count <= 6
}

private func studifyPlaylistURIFromResponderChain(startingAt responder: UIResponder?) -> String? {
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

    return nil
}

private func sendStudifyFallbackDownloadSignal(from control: UIControl) {
    let now = Date()
    guard now.timeIntervalSince(lastStudifyFallbackSignalAt) > 2 else {
        writeDebugLog("[STUDIFY] Ignoring duplicate UIControl fallback signal")
        return
    }

    lastStudifyFallbackSignalAt = now

    let labels = collectStudifyControlContext(from: control)
    let playlistURI = studifyPlaylistURIFromResponderChain(startingAt: control)
        ?? "spotify:playlist:studify-ui-fallback"

    writeDebugLog("[STUDIFY] UIControl fallback intercepted download labels=\(labels.joined(separator: " | ")) playlistURI=\(playlistURI)")
    StudifyDebugVisualAid.intercepted("UIControl fallback \(playlistURI)")

    StudifyDownloadSignalClient.shared.startPlaylistJob(playlistURI: playlistURI) { result in
        switch result {
        case .success(let jobId):
            PopUpHelper.showPopUp(
                message: "Studify fallback job created.\n\nJob ID: \(jobId)\n\nThe UIControl fallback fired, so the tweak is executing on the button tap.",
                buttonText: "OK".uiKitLocalized
            )

        case .failure(let message):
            PopUpHelper.showPopUp(
                message: "Studify fallback signal failed.\n\n\(message)",
                buttonText: "OK".uiKitLocalized
            )
        }
    }
}

//

class StreamQualitySettingsSectionHook: ClassHook<NSObject> {
    typealias Group = IOS14PremiumPatchingGroup
    static let targetName = "StreamQualitySettingsSection"

    func shouldResetSelection() -> Bool {
        showHighQualityPopUp()
        return true
    }
}

class ListRowInteractionListenerViewHook: ClassHook<UIView> {
    typealias Group = NonIOS14PremiumPatchingGroup
    static let targetName = "_TtC15Settings_ECMKit30ListRowInteractionListenerView"

    func performAction() {
        guard
            let accessibilityLabel = target.subviews.first?.accessibilityLabel,
            accessibilityLabel.hasSuffix("Premium")
        else {
            orig.performAction()
            return
        }
        
        showHighQualityPopUp()
    }
}

//

class ContentOffliningUIHelperImplementationHook: ClassHook<NSObject> {
    typealias Group = IOS14And15PremiumPatchingGroup
    static let targetName = "Offline_ContentOffliningUIImpl.ContentOffliningUIHelperImplementation"
    
    func downloadToggledWithCurrentAvailability(
        _ availability: NSInteger,
        addAction: NSObject,
        removeAction: NSObject,
        pageIdentifier: NSString,
        pageURI: NSURL
    ) {
        handleStudifyDownloadToggle(pageURI: pageURI)
    }
}

class ContentOffliningUIHelperImplementationModernHook: ClassHook<NSObject> {
    typealias Group = LatestPremiumPatchingGroup
    static let targetName = "Offline_ContentOffliningUIImpl.ContentOffliningUIHelperImplementation"
    
    func downloadToggledWithCurrentAvailability(
        _ availability: NSInteger,
        addAction: NSObject,
        removeAction: NSObject,
        pageIdentifier: NSString,
        pageURI: NSURL,
        interactionID: NSString
    ) {
        handleStudifyDownloadToggle(pageURI: pageURI)
    }
}

class V91ContentOffliningUIHelperImplementationModernHook: ClassHook<NSObject> {
    typealias Group = V91StudifyDownloadSignalGroup
    static let targetName = "Offline_ContentOffliningUIImpl.ContentOffliningUIHelperImplementation"

    func downloadToggledWithCurrentAvailability(
        _ availability: NSInteger,
        addAction: NSObject,
        removeAction: NSObject,
        pageIdentifier: NSString,
        pageURI: NSURL,
        interactionID: NSString
    ) {
        handleStudifyDownloadToggle(pageURI: pageURI)
    }
}

class V91ContentOffliningUIHelperImplementationLegacyHook: ClassHook<NSObject> {
    typealias Group = V91StudifyDownloadSignalLegacyGroup
    static let targetName = "Offline_ContentOffliningUIImpl.ContentOffliningUIHelperImplementation"

    func downloadToggledWithCurrentAvailability(
        _ availability: NSInteger,
        addAction: NSObject,
        removeAction: NSObject,
        pageIdentifier: NSString,
        pageURI: NSURL
    ) {
        handleStudifyDownloadToggle(pageURI: pageURI)
    }
}

class V91StudifyDownloadButtonFallbackHook: ClassHook<UIControl> {
    typealias Group = V91StudifyDownloadButtonFallbackGroup
    static let targetName = "UIControl"

    func sendAction(_ action: Selector, to receiver: AnyObject?, for event: UIEvent?) {
        guard studifyLooksLikeDownloadControl(target, actionName: NSStringFromSelector(action)) else {
            orig.sendAction(action, to: receiver, for: event)
            return
        }

        sendStudifyFallbackDownloadSignal(from: target)
    }
}
