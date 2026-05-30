import Foundation
import Orion

struct StudifyPlaybackAvailabilitySpoofGroup: HookGroup { }
struct StudifyPlaybackAvailabilityDataSourceSpoofGroup: HookGroup { }
struct StudifyPlayableCacheAvailabilitySpoofGroup: HookGroup { }
struct StudifyDownloadedContentSpoofGroup: HookGroup { }
struct StudifyPLTrackViewModelSpoofGroup: HookGroup { }
struct StudifyFTPRestrictionSpoofGroup: HookGroup { }

private let studifyPlaybackAvailabilityServiceClass = "CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityServiceImpl"
private let studifyPlaybackAvailabilityDataSourceClass = "CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityDataSourceImpl"
private let studifyPlayableCacheAvailabilityClass = "Offline_PlayableCacheImpl.PlayableCacheAvailabilityProviderImplementation"
private let studifyDownloadedContentCheckerClass = "Offline_UnavailableContentImpl.DownloadedContentCheckerImplementation"
private let studifyPLTrackViewModelClass = "ListUXPlatform_FreeTierPlaylistImpl.PLTrackViewModelImplementation"
private let studifyFTPRestrictionResolverClass = "ListUXPlatform_FreeTierPlaylistImpl.FTPPlayRestrictionResolver"

func studifyActivateOfflinePlayableSpoofGroups() {
    guard UserDefaults.standard.bool(forKey: "StudifyEnableUnsafeOfflineSpoofs") else {
        studifyOverlayLog("Offline playable spoof groups skipped; runtime probe must confirm exact selectors before activation")
        StudifyProbeStreamClient.shared.emit(
            hook: "offline-playable-spoof",
            phase: "skipped",
            message: "exact selectors not confirmed",
            requireActive: false
        )
        return
    }

    var activated: [String] = []
    var missing: [String] = []

    if studifyClassExists(studifyPlaybackAvailabilityServiceClass) {
        if !StudifyPlaybackAvailabilitySpoofGroup.isActive {
            StudifyPlaybackAvailabilitySpoofGroup().activate()
            activated.append("playback-availability-service")
        }
    } else {
        missing.append("playback-availability-service")
    }

    if studifyClassExists(studifyPlaybackAvailabilityDataSourceClass) {
        if !StudifyPlaybackAvailabilityDataSourceSpoofGroup.isActive {
            StudifyPlaybackAvailabilityDataSourceSpoofGroup().activate()
            activated.append("playback-availability-data-source")
        }
    } else {
        missing.append("playback-availability-data-source")
    }

    if studifyClassExists(studifyPlayableCacheAvailabilityClass) {
        if !StudifyPlayableCacheAvailabilitySpoofGroup.isActive {
            StudifyPlayableCacheAvailabilitySpoofGroup().activate()
            activated.append("playable-cache-availability")
        }
    } else {
        missing.append("playable-cache-availability")
    }

    if studifyClassExists(studifyDownloadedContentCheckerClass) {
        if !StudifyDownloadedContentSpoofGroup.isActive {
            StudifyDownloadedContentSpoofGroup().activate()
            activated.append("downloaded-content-checker")
        }
    } else {
        missing.append("downloaded-content-checker")
    }

    if studifyClassExists(studifyPLTrackViewModelClass) {
        if !StudifyPLTrackViewModelSpoofGroup.isActive {
            StudifyPLTrackViewModelSpoofGroup().activate()
            activated.append("playlist-track-view-model")
        }
    } else {
        missing.append("playlist-track-view-model")
    }

    if studifyClassExists(studifyFTPRestrictionResolverClass) {
        if !StudifyFTPRestrictionSpoofGroup.isActive {
            StudifyFTPRestrictionSpoofGroup().activate()
            activated.append("ftp-restriction-resolver")
        }
    } else {
        missing.append("ftp-restriction-resolver")
    }

    studifyOverlayLog("Offline playable spoof groups activated=\(activated.joined(separator: ",")) missing=\(missing.joined(separator: ","))")
    StudifyProbeStreamClient.shared.emit(
        hook: "offline-playable-spoof",
        phase: "activated",
        message: activated.joined(separator: ","),
        data: [
            "activated": activated,
            "missing": missing
        ],
        requireActive: false
    )
}

private func studifyClassExists(_ className: String) -> Bool {
    NSClassFromString(className) != nil
}

private final class StudifyOfflinePlayableSpoofRecorder {
    static let shared = StudifyOfflinePlayableSpoofRecorder()

    private let queue = DispatchQueue(label: "studify.offline.playable.spoof")
    private var lastLogByKey: [String: Date] = [:]

    private init() { }

    func record(className: String, selector: String, message: String) {
        let key = "\(className)-\(selector)"
        queue.async {
            let now = Date()
            if let lastLog = self.lastLogByKey[key], now.timeIntervalSince(lastLog) < 1.5 {
                return
            }
            self.lastLogByKey[key] = now

            studifyOverlayLog("Offline playable spoof hit class=\(className) selector=\(selector) message=\(message)")
            StudifyProbeStreamClient.shared.emit(
                hook: "offline-playable-spoof",
                phase: "hit",
                message: message,
                className: className,
                selector: selector,
                throttleKey: key,
                minInterval: 1.5,
                requireActive: false
            )
        }
    }
}

class StudifyPlaybackAvailabilityServiceHook: ClassHook<NSObject> {
    typealias Group = StudifyPlaybackAvailabilitySpoofGroup
    static let targetName = studifyPlaybackAvailabilityServiceClass

    func canPlayContent(_ content: AnyObject) -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContent:",
            message: "forcing playable"
        )
        return true
    }

    func canPlayContentWithURI(_ uri: AnyObject) -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContentWithURI:",
            message: "\(uri)"
        )
        return true
    }

    func screen(_ screen: AnyObject, canPlayContent content: AnyObject) -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "screen:canPlayContent:",
            message: "forcing screen playable"
        )
        return true
    }
}

class StudifyPlaybackAvailabilityDataSourceHook: ClassHook<NSObject> {
    typealias Group = StudifyPlaybackAvailabilityDataSourceSpoofGroup
    static let targetName = studifyPlaybackAvailabilityDataSourceClass

    func canPlayContent(_ content: AnyObject) -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContent:",
            message: "forcing data source playable"
        )
        return true
    }

    func canPlayContentWithURI(_ uri: AnyObject) -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContentWithURI:",
            message: "\(uri)"
        )
        return true
    }

    func isPlayable() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "isPlayable",
            message: "forcing data source isPlayable"
        )
        return true
    }
}

class StudifyPlayableCacheAvailabilityProviderHook: ClassHook<NSObject> {
    typealias Group = StudifyPlayableCacheAvailabilitySpoofGroup
    static let targetName = studifyPlayableCacheAvailabilityClass

    func isDownloaded() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "isDownloaded",
            message: "forcing cache downloaded"
        )
        return true
    }

    func contentIsDownloaded() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "contentIsDownloaded",
            message: "forcing cache content downloaded"
        )
        return true
    }

    func isPlayable() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "isPlayable",
            message: "forcing cache playable"
        )
        return true
    }
}

class StudifyDownloadedContentCheckerHook: ClassHook<NSObject> {
    typealias Group = StudifyDownloadedContentSpoofGroup
    static let targetName = studifyDownloadedContentCheckerClass

    func isDownloaded() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "isDownloaded",
            message: "forcing downloaded checker"
        )
        return true
    }

    func contentIsDownloaded() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "contentIsDownloaded",
            message: "forcing content downloaded checker"
        )
        return true
    }
}

class StudifyPLTrackViewModelHook: ClassHook<NSObject> {
    typealias Group = StudifyPLTrackViewModelSpoofGroup
    static let targetName = studifyPLTrackViewModelClass

    func isPlayable() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "isPlayable",
            message: "forcing track view model playable"
        )
        return true
    }

    func isDownloaded() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "isDownloaded",
            message: "forcing track view model downloaded"
        )
        return true
    }

    func contentIsDownloaded() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "contentIsDownloaded",
            message: "forcing track view model content downloaded"
        )
        return true
    }
}

class StudifyFTPPlayRestrictionResolverHook: ClassHook<NSObject> {
    typealias Group = StudifyFTPRestrictionSpoofGroup
    static let targetName = studifyFTPRestrictionResolverClass

    func isPlayable() -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "isPlayable",
            message: "forcing restriction resolver playable"
        )
        return true
    }

    func canPlayContent(_ content: AnyObject) -> Bool {
        StudifyOfflinePlayableSpoofRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContent:",
            message: "forcing restriction resolver canPlayContent"
        )
        return true
    }
}
