import Foundation
import Orion
import UIKit

let studifySpotifyStateBridgeEnabled = true

@objc protocol StudifySpotifyStatefulPlayer: AnyObject {
    func currentTrack() -> AnyObject?
}

struct StudifySpotifyStateBridgeLegacyGroup: HookGroup { }
struct StudifySpotifyStateBridgeFeatureGroup: HookGroup { }
struct StudifySpotifyTrackMetadataOverrideGroup: HookGroup { }

private struct StudifySpotifyFakeTrackState {
    let title: String
    let artist: String
    let uri: String
}

func studifyActivateSpotifyStateBridge() {
    guard studifySpotifyStateBridgeEnabled else {
        studifyOverlayLog("Spotify state bridge skipped; opt-in debug bridge disabled")
        return
    }

    var activated: [String] = []
    var missing: [String] = []

    let className = "NowPlaying_PlatformImpl.NowPlayingPlatformSwiftServiceImplementation"
    if let targetClass = NSClassFromString(className) {
        if targetClass.instancesRespond(to: Selector(("provideStatefulPlayer"))) {
            StudifySpotifyStateBridgeLegacyGroup().activate()
            activated.append("provideStatefulPlayer")
        }

        if targetClass.instancesRespond(to: Selector(("provideStatefulPlayerWithFeatureIdentifier:"))) {
            StudifySpotifyStateBridgeFeatureGroup().activate()
            activated.append("provideStatefulPlayerWithFeatureIdentifier:")
        }
    } else {
        missing.append(className)
    }

    if NSClassFromString("SPTPlayerTrackImplementation") != nil {
        StudifySpotifyTrackMetadataOverrideGroup().activate()
        activated.append("SPTPlayerTrackImplementation metadata")
    } else {
        missing.append("SPTPlayerTrackImplementation")
    }

    studifyOverlayLog("Spotify state bridge activated selectors=\(activated.joined(separator: ",")) missing=\(missing.joined(separator: ","))")
}

final class StudifySpotifyStateBridge {
    static let shared = StudifySpotifyStateBridge()

    private weak var statefulPlayer: StudifySpotifyStatefulPlayer?
    private var statefulPlayersBySource: [String: StudifySpotifyStatefulPlayer] = [:]
    private var lastStateLogAt = Date(timeIntervalSince1970: 0)
    private var lastFakeOverrideLogAt = Date(timeIntervalSince1970: 0)
    private let fakeTrackLock = NSLock()
    private var fakeTrackState: StudifySpotifyFakeTrackState?

    private init() { }

    func capture(_ player: StudifySpotifyStatefulPlayer, source: String) {
        statefulPlayer = player
        statefulPlayersBySource[source] = player
        logCurrentSpotifyState(reason: "capture-\(source)", force: true)
    }

    func recordFakeSelection(title: String, artist: String, reason: String) {
        let real = bestSpotifyStateSummary()
        let all = allSpotifyStateSummaries()
        studifyOverlayLog(
            "Spotify state bridge fakeSelection title=\(title) artist=\(artist) reason=\(reason) realTitle=\(real.title) realArtist=\(real.artist) realURI=\(real.uri) providers=\(all)"
        )
    }

    func setFakeTrack(title: String, artist: String, uri: String, reason: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURI = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let nextState = StudifySpotifyFakeTrackState(
            title: cleanTitle,
            artist: cleanArtist.isEmpty ? "Studify" : cleanArtist,
            uri: cleanURI.isEmpty ? "studify:local:\(stableIdentifier(title: cleanTitle, artist: cleanArtist))" : cleanURI
        )

        fakeTrackLock.lock()
        fakeTrackState = nextState
        fakeTrackLock.unlock()

        studifyOverlayLog("Spotify state bridge fakeTrack set title=\(nextState.title) artist=\(nextState.artist) uri=\(nextState.uri) reason=\(reason)")
        nudgeSpotifyNowPlayingUI(reason: reason)
    }

    func clearFakeTrack(reason: String) {
        fakeTrackLock.lock()
        let hadFakeTrack = fakeTrackState != nil
        fakeTrackState = nil
        fakeTrackLock.unlock()

        if hadFakeTrack {
            studifyOverlayLog("Spotify state bridge fakeTrack cleared reason=\(reason)")
            nudgeSpotifyNowPlayingUI(reason: reason)
        }
    }

    func overrideTrackTitle(_ original: @autoclosure () -> String) -> String {
        guard let fake = currentFakeTrackState() else { return original() }
        logFakeOverrideIfNeeded(selector: "trackTitle", fake: fake)
        return fake.title
    }

    func overrideArtistTitle(_ original: @autoclosure () -> String) -> String {
        guard let fake = currentFakeTrackState() else { return original() }
        logFakeOverrideIfNeeded(selector: "artistTitle", fake: fake)
        return fake.artist
    }

    func overrideArtistName(_ original: @autoclosure () -> String) -> String {
        guard let fake = currentFakeTrackState() else { return original() }
        logFakeOverrideIfNeeded(selector: "artistName", fake: fake)
        return fake.artist
    }

    func overrideTrackURI(_ original: @autoclosure () -> NSURL?) -> NSURL? {
        guard let fake = currentFakeTrackState() else { return original() }
        logFakeOverrideIfNeeded(selector: "URI", fake: fake)
        return NSURL(string: fake.uri) ?? original()
    }

    func overrideMetadata(_ original: @autoclosure () -> [String: String]) -> [String: String] {
        var metadata = original()
        guard let fake = currentFakeTrackState() else { return metadata }
        metadata["title"] = fake.title
        metadata["name"] = fake.title
        metadata["track_title"] = fake.title
        metadata["artist"] = fake.artist
        metadata["artist_name"] = fake.artist
        metadata["artistName"] = fake.artist
        metadata["artistTitle"] = fake.artist
        metadata["uri"] = fake.uri
        metadata["track_uri"] = fake.uri
        metadata["spotify_uri"] = fake.uri
        logFakeOverrideIfNeeded(selector: "metadata", fake: fake)
        return metadata
    }

    func logCurrentSpotifyState(reason: String, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastStateLogAt) > 2 else { return }
        lastStateLogAt = now

        let real = bestSpotifyStateSummary()
        studifyOverlayLog(
            "Spotify state bridge currentTrack reason=\(reason) title=\(real.title) artist=\(real.artist) uri=\(real.uri)"
        )
    }

    private func bestSpotifyStateSummary() -> (title: String, artist: String, uri: String) {
        if let fake = currentFakeTrackState() {
            return (fake.title, fake.artist, fake.uri)
        }

        let preferredSources = statefulPlayersBySource.keys.sorted { lhs, rhs in
            score(source: lhs) > score(source: rhs)
        }

        for source in preferredSources {
            let summary = spotifyStateSummary(source: source, player: statefulPlayersBySource[source])
            if summary.title != "nil", summary.title != "unknown" {
                return (summary.title, summary.artist, summary.uri)
            }
        }

        let fallback = spotifyStateSummary(source: "latest", player: statefulPlayer)
        return (fallback.title, fallback.artist, fallback.uri)
    }

    private func allSpotifyStateSummaries() -> String {
        let interesting = statefulPlayersBySource.keys
            .sorted { score(source: $0) > score(source: $1) }
            .prefix(12)

        var summaries = interesting.map { source in
            let summary = spotifyStateSummary(source: source, player: statefulPlayersBySource[source])
            return "\(source){class=\(summary.playerClass),trackClass=\(summary.trackClass),title=\(summary.title),artist=\(summary.artist),uri=\(summary.uri)}"
        }

        if let fake = currentFakeTrackState() {
            summaries.insert("studify-fake{title=\(fake.title),artist=\(fake.artist),uri=\(fake.uri)}", at: 0)
        }

        return summaries.joined(separator: " || ")
    }

    private func spotifyStateSummary(source: String, player: StudifySpotifyStatefulPlayer?) -> (playerClass: String, trackClass: String, title: String, artist: String, uri: String) {
        guard let player else {
            return ("nil", "nil", "nil", "nil", "nil")
        }

        let playerObject = player as AnyObject
        let playerClass = NSStringFromClass(type(of: playerObject))

        guard let track = player.currentTrack() as? NSObject else {
            return (playerClass, "nil", "nil", "nil", "nil")
        }

        return spotifyTrackSummary(source: source, playerClass: playerClass, track: track)
    }

    private func spotifyTrackSummary(source: String, playerClass: String, track: NSObject) -> (playerClass: String, trackClass: String, title: String, artist: String, uri: String) {
        let trackClass = NSStringFromClass(type(of: track))

        let selectorSummary = [
            "trackTitle",
            "title",
            "name",
            "artistTitle",
            "artistName",
            "artist",
            "URI",
            "uri",
            "trackURI",
            "trackUri",
            "metadata"
        ]
        .filter { track.responds(to: Selector(($0))) }
        .joined(separator: ",")

        if !selectorSummary.isEmpty {
            studifyOverlayLog("Spotify state bridge track selectors source=\(source) playerClass=\(playerClass) trackClass=\(trackClass) selectors=\(selectorSummary)")
        }

        let metadata = metadataValues(from: track)
        let title = firstNonEmpty([
            readString(from: track, selectorNames: ["trackTitle", "title", "name"]),
            metadata["title"],
            metadata["name"],
            metadata["track_title"]
        ])
        let artist = firstNonEmpty([
            readString(from: track, selectorNames: ["artistTitle", "artistName", "artist", "artistDisplayName"]),
            metadata["artist"],
            metadata["artist_name"],
            metadata["artistTitle"],
            metadata["artistName"]
        ])
        let uri = firstNonEmpty([
            readString(from: track, selectorNames: ["URI", "uri", "trackURI", "trackUri"]),
            metadata["uri"],
            metadata["track_uri"],
            metadata["spotify_uri"]
        ])

        return (
            playerClass,
            trackClass,
            title.isEmpty ? "unknown" : title,
            artist.isEmpty ? "unknown" : artist,
            uri.isEmpty ? "unknown" : uri
        )
    }

    private func spotifyStateSummary() -> (title: String, artist: String, uri: String) {
        guard let track = statefulPlayer?.currentTrack() as? NSObject else {
            return ("nil", "nil", "nil")
        }

        let metadata = metadataValues(from: track)
        let title = firstNonEmpty([
            readString(from: track, selectorNames: ["trackTitle", "title", "name"]),
            metadata["title"],
            metadata["name"],
            metadata["track_title"]
        ])
        let artist = firstNonEmpty([
            readString(from: track, selectorNames: ["artistTitle", "artistName", "artist", "artistDisplayName"]),
            metadata["artist"],
            metadata["artist_name"],
            metadata["artistTitle"],
            metadata["artistName"]
        ])
        let uri = firstNonEmpty([
            readString(from: track, selectorNames: ["URI", "uri", "trackURI", "trackUri"]),
            metadata["uri"],
            metadata["track_uri"],
            metadata["spotify_uri"]
        ])

        return (
            title.isEmpty ? "unknown" : title,
            artist.isEmpty ? "unknown" : artist,
            uri.isEmpty ? "unknown" : uri
        )
    }

    private func score(source: String) -> Int {
        let lower = source.lowercased()
        var value = 0
        if lower.contains("nowplayingbar") { value += 120 }
        if lower.contains("lockscreen") { value += 110 }
        if lower.contains("nowplaying") { value += 80 }
        if lower.contains("builtin.nowplaying") { value += 30 }
        if lower.contains("legacy") { value += 10 }
        return value
    }

    private func currentFakeTrackState() -> StudifySpotifyFakeTrackState? {
        fakeTrackLock.lock()
        let state = fakeTrackState
        fakeTrackLock.unlock()
        return state
    }

    private func logFakeOverrideIfNeeded(selector: String, fake: StudifySpotifyFakeTrackState) {
        let now = Date()
        guard now.timeIntervalSince(lastFakeOverrideLogAt) > 1 else { return }
        lastFakeOverrideLogAt = now
        studifyOverlayLog("Spotify state bridge fakeTrack override selector=\(selector) title=\(fake.title) artist=\(fake.artist)")
    }

    private func stableIdentifier(title: String, artist: String) -> String {
        let raw = "\(artist)-\(title)".lowercased()
        let allowed = CharacterSet.alphanumerics
        let components = raw.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let collapsed = components
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "test-mp3" : collapsed
    }

    private func nudgeSpotifyNowPlayingUI(reason: String) {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first(where: { $0.isKeyWindow })
            else {
                return
            }

            window.setNeedsLayout()
            for view in self.views(in: window, maxDepth: 12) {
                let className = NSStringFromClass(type(of: view)).lowercased()
                if className.contains("nowplaying") || className.contains("player") || className.contains("bar") {
                    view.setNeedsLayout()
                    view.setNeedsDisplay()
                }
            }
            studifyOverlayLog("Spotify state bridge nudged now-playing UI reason=\(reason)")
        }
    }

    private func views(in view: UIView, maxDepth: Int, depth: Int = 0) -> [UIView] {
        guard depth <= maxDepth else { return [] }
        var result = [view]
        for subview in view.subviews {
            result.append(contentsOf: views(in: subview, maxDepth: maxDepth, depth: depth + 1))
        }
        return result
    }

    private func readString(from object: NSObject, selectorNames: [String]) -> String {
        for selectorName in selectorNames {
            guard let value = performObjectSelector(selectorName, on: object) else { continue }
            let stringValue = string(from: value)
            if !stringValue.isEmpty {
                return stringValue
            }
        }

        return ""
    }

    private func metadataValues(from object: NSObject) -> [String: String] {
        guard let value = performObjectSelector("metadata", on: object) else { return [:] }

        if let typed = value as? [String: String] {
            return typed
        }

        guard let dictionary = value as? NSDictionary else { return [:] }

        var result: [String: String] = [:]
        for (key, value) in dictionary {
            let keyString = string(from: key as AnyObject)
            let valueString = string(from: value as AnyObject)
            guard !keyString.isEmpty, !valueString.isEmpty else { continue }
            result[keyString] = valueString
        }
        return result
    }

    private func performObjectSelector(_ selectorName: String, on object: NSObject) -> AnyObject? {
        let selector = Selector((selectorName))
        guard object.responds(to: selector),
              methodReturnsObject(selector, on: object)
        else {
            return nil
        }
        return object.perform(selector)?.takeUnretainedValue()
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

    private func firstNonEmpty(_ values: [String?]) -> String {
        for value in values {
            let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                return clean
            }
        }
        return ""
    }

    private func string(from value: AnyObject) -> String {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let string = value as? NSString {
            return (string as String).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let url = value as? URL {
            return url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let url = value as? NSURL {
            return (url.absoluteString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

class StudifySpotifyStateBridgeLegacyHook: ClassHook<NSObject> {
    typealias Group = StudifySpotifyStateBridgeLegacyGroup
    static let targetName = "NowPlaying_PlatformImpl.NowPlayingPlatformSwiftServiceImplementation"

    func provideStatefulPlayer() -> StudifySpotifyStatefulPlayer {
        let player = orig.provideStatefulPlayer()
        StudifySpotifyStateBridge.shared.capture(player, source: "legacy")
        return player
    }
}

class StudifySpotifyStateBridgeFeatureHook: ClassHook<NSObject> {
    typealias Group = StudifySpotifyStateBridgeFeatureGroup
    static let targetName = "NowPlaying_PlatformImpl.NowPlayingPlatformSwiftServiceImplementation"

    func provideStatefulPlayerWithFeatureIdentifier(_ identifier: NSString) -> StudifySpotifyStatefulPlayer {
        let player = orig.provideStatefulPlayerWithFeatureIdentifier(identifier)
        StudifySpotifyStateBridge.shared.capture(player, source: "feature-\(identifier)")
        return player
    }
}

class StudifySPTPlayerTrackImplementationHook: ClassHook<NSObject> {
    typealias Group = StudifySpotifyTrackMetadataOverrideGroup
    static let targetName = "SPTPlayerTrackImplementation"

    func trackTitle() -> String {
        StudifySpotifyStateBridge.shared.overrideTrackTitle(orig.trackTitle())
    }

    func artistTitle() -> String {
        StudifySpotifyStateBridge.shared.overrideArtistTitle(orig.artistTitle())
    }

    func artistName() -> String {
        StudifySpotifyStateBridge.shared.overrideArtistName(orig.artistName())
    }

    func URI() -> NSURL? {
        StudifySpotifyStateBridge.shared.overrideTrackURI(orig.URI())
    }

    func metadata() -> [String: String] {
        StudifySpotifyStateBridge.shared.overrideMetadata(orig.metadata())
    }
}
