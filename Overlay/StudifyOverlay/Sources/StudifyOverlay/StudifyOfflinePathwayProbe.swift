import Foundation
import UIKit

final class StudifyOfflinePathwayProbe {
    static let shared = StudifyOfflinePathwayProbe()

    private var didRunClassProbe = false
    private var loggedObjectClasses = Set<String>()
    private var didShowRowHookBanner = false

    private let candidateClasses: [(label: String, name: String)] = [
        ("forced offline manager", "Connectivity_ReachabilityImpl.ForcedOfflineModeManagerImpl"),
        ("download button helper", "Offline_ContentOffliningUIImpl.ContentOffliningUIHelperImplementation"),
        ("offline content state factory", "Offline_DeadEndsUIImpl.OfflineContentStateFactoryImpl"),
        ("downloaded content checker", "Offline_UnavailableContentImpl.DownloadedContentCheckerImplementation"),
        ("playback availability service", "CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityServiceImpl"),
        ("playback availability data source", "CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityDataSourceImpl"),
        ("playback availability data source provider", "CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityDataSourceProviderImpl"),
        ("free tier playlist play restriction", "ListUXPlatform_FreeTierPlaylistImpl.FTPPlayRestrictionResolver"),
        ("free tier playlist track event handler", "ListUXPlatform_FreeTierPlaylistImpl.FTPTrackRowEventHandler"),
        ("free tier playlist list player", "ListUXPlatform_FreeTierPlaylistImpl.ListPlayerImpl"),
        ("free tier playlist track model factory", "ListUXPlatform_FreeTierPlaylistImpl.PLTrackViewModelFactory"),
        ("free tier playlist track model", "ListUXPlatform_FreeTierPlaylistImpl.PLTrackViewModelImplementation"),
        ("free tier playlist swipable cell", "ListUXPlatform_FreeTierPlaylistImpl.LegacySwipableElementTableViewCell"),
        ("playable cache availability provider", "Offline_PlayableCacheImpl.PlayableCacheAvailabilityProviderImplementation"),
        ("playable cache player", "Offline_PlayableCacheImpl.PlayableCachePlayerImplementation"),
        ("playable cache list player", "Offline_PlayableCacheImpl.PlayableCacheListPlayerImplementation")
    ]

    private let selectorsToProbe: [String] = [
        "isForcedOfflineModeOn",
        "isCurrentForcedOfflineModeOn",
        "addObserver:",
        "removeObserver:",
        "downloadToggledWithCurrentAvailability:addAction:removeAction:pageIdentifier:pageURI:",
        "downloadToggledWithCurrentAvailability:addAction:removeAction:pageIdentifier:pageURI:interactionID:",
        "provideDownloadedContentChecker",
        "providePlayableCacheAvailabilityProvider",
        "canPlayContent:",
        "canPlayContentWithURI:",
        "screen:canPlayContent:",
        "playableCacheAvailabilityDidChange:",
        "playableCacheAvailabilityAndEnoughContentDidChange:",
        "offlineContentState",
        "offlineContentStateFactory",
        "offlineContentStateProvider",
        "downloadedContentChecker",
        "playbackAvailabilityService",
        "playbackAvailabilityDataSource",
        "playbackAvailabilityDataSourceProvider",
        "playbackAvailabilityDataSourceProviderCache",
        "playableCacheAvailabilityProvider",
        "playRestrictionResolver",
        "trackRowEventHandler",
        "trackUri",
        "trackURI",
        "uri",
        "URI",
        "viewURI",
        "pageURI",
        "model",
        "viewModel",
        "isDownloaded",
        "contentIsDownloaded",
        "isPlayable",
        "restriction",
        "playabilityRestriction"
    ]

    private init() { }

    func runClassProbeOnce() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard !self.didRunClassProbe else { return }
            self.didRunClassProbe = true

            studifyOverlayLog("Studify offline pathway probe started")
            StudifyProbeStreamClient.shared.emit(
                hook: "offline-pathway",
                phase: "probe-started",
                message: "class probe started",
                requireActive: false
            )

            var foundClasses: [String] = []
            var selectorSummaries: [String] = []

            for candidate in self.candidateClasses {
                guard let cls = NSClassFromString(candidate.name) as? NSObject.Type else {
                    studifyOverlayLog("Offline pathway class missing label=\(candidate.label) name=\(candidate.name)")
                    StudifyProbeStreamClient.shared.emit(
                        hook: "offline-pathway",
                        phase: "class-missing",
                        message: candidate.label,
                        className: candidate.name,
                        throttleKey: "offline-missing-\(candidate.name)",
                        minInterval: 30,
                        requireActive: false
                    )
                    continue
                }

                let matches = self.selectorsToProbe.filter {
                    cls.instancesRespond(to: Selector(($0))) || cls.responds(to: Selector(($0)))
                }

                studifyOverlayLog(
                    "Offline pathway class found label=\(candidate.label) name=\(candidate.name) selectors=\(matches.joined(separator: ", "))"
                )
                StudifyProbeStreamClient.shared.emit(
                    hook: "offline-pathway",
                    phase: "class-found",
                    message: candidate.label,
                    className: candidate.name,
                    data: ["selectors": matches],
                    throttleKey: "offline-found-\(candidate.name)",
                    minInterval: 30,
                    requireActive: false
                )

                foundClasses.append(candidate.label)
                if !matches.isEmpty {
                    selectorSummaries.append("\(candidate.label): \(matches.prefix(3).joined(separator: "/"))")
                }
            }

            let detail: String
            if selectorSummaries.isEmpty {
                detail = "found \(foundClasses.count)/\(self.candidateClasses.count) classes"
            } else {
                detail = selectorSummaries.prefix(2).joined(separator: " | ")
            }

            StudifyOverlayBanner.show(
                title: "STUDIFY OFFLINE PROBE",
                detail: detail,
                color: UIColor(red: 0.10, green: 0.42, blue: 0.86, alpha: 0.96),
                duration: 6
            )
        }
    }

    func logObjectContext(_ object: NSObject, reason: String) {
        let className = NSStringFromClass(type(of: object))
        guard !loggedObjectClasses.contains(className) else { return }

        let lower = className.lowercased()
        guard lower.contains("playlist")
            || lower.contains("track")
            || lower.contains("offline")
            || lower.contains("playable")
            || lower.contains("availability")
            || lower.contains("restriction")
            || lower.contains("swipable")
        else {
            return
        }

        loggedObjectClasses.insert(className)

        var matches: [String] = []
        for selectorName in selectorsToProbe {
            let selector = Selector((selectorName))
            if object.responds(to: selector) {
                matches.append(selectorName)
            }
        }

        studifyOverlayLog("Offline pathway object reason=\(reason) class=\(className) selectors=\(matches.joined(separator: ", "))")
        StudifyProbeStreamClient.shared.emit(
            hook: "offline-pathway",
            phase: "object",
            message: reason,
            className: className,
            data: ["selectors": matches],
            throttleKey: "offline-object-\(className)",
            minInterval: 5
        )

        if !didShowRowHookBanner {
            didShowRowHookBanner = true
            StudifyOverlayBanner.show(
                title: "STUDIFY ROW HOOK HIT",
                detail: className.components(separatedBy: ".").suffix(2).joined(separator: "."),
                color: UIColor(red: 0.20, green: 0.70, blue: 0.28, alpha: 0.96),
                duration: 5
            )
        }
    }
}
