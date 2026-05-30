import Foundation
import ObjectiveC
import Orion

struct StudifyProbePlaybackAvailabilityServiceCanPlayGroup: HookGroup { }
struct StudifyProbePlaybackAvailabilityServiceCanPlayURIGroup: HookGroup { }
struct StudifyProbePlaybackAvailabilityServiceScreenCanPlayGroup: HookGroup { }
struct StudifyProbePlaybackAvailabilityDataSourceCanPlayGroup: HookGroup { }
struct StudifyProbePlaybackAvailabilityDataSourceCanPlayURIGroup: HookGroup { }
struct StudifyProbePlaybackAvailabilityDataSourceIsPlayableGroup: HookGroup { }
struct StudifyProbePlayableCacheIsDownloadedGroup: HookGroup { }
struct StudifyProbePlayableCacheContentIsDownloadedGroup: HookGroup { }
struct StudifyProbePlayableCacheIsPlayableGroup: HookGroup { }
struct StudifyProbeDownloadedContentIsDownloadedGroup: HookGroup { }
struct StudifyProbeDownloadedContentContentIsDownloadedGroup: HookGroup { }
struct StudifyProbePLTrackViewModelIsPlayableGroup: HookGroup { }
struct StudifyProbePLTrackViewModelIsDownloadedGroup: HookGroup { }
struct StudifyProbePLTrackViewModelContentIsDownloadedGroup: HookGroup { }
struct StudifyProbeFTPRestrictionResolverIsPlayableGroup: HookGroup { }
struct StudifyProbeFTPRestrictionResolverCanPlayGroup: HookGroup { }

private let studifyProbePlaybackAvailabilityServiceClass = "CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityServiceImpl"
private let studifyProbePlaybackAvailabilityDataSourceClass = "CreativeWorkCommons_PlaybackAvailabilityImpl.PlaybackAvailabilityDataSourceImpl"
private let studifyProbePlayableCacheAvailabilityClass = "Offline_PlayableCacheImpl.PlayableCacheAvailabilityProviderImplementation"
private let studifyProbeDownloadedContentCheckerClass = "Offline_UnavailableContentImpl.DownloadedContentCheckerImplementation"
private let studifyProbePLTrackViewModelClass = "ListUXPlatform_FreeTierPlaylistImpl.PLTrackViewModelImplementation"
private let studifyProbeFTPRestrictionResolverClass = "ListUXPlatform_FreeTierPlaylistImpl.FTPPlayRestrictionResolver"

func studifyActivateOfflinePathwayMethodProbeGroups() {
    guard studifyOverlayProbeModeEnabled else { return }

    var activated: [String] = []
    var skipped: [String] = []

    studifyActivateBoolProbe(
        className: studifyProbePlaybackAvailabilityServiceClass,
        selectorName: "canPlayContent:",
        label: "playback-service.canPlayContent",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlaybackAvailabilityServiceCanPlayGroup.isActive {
            StudifyProbePlaybackAvailabilityServiceCanPlayGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePlaybackAvailabilityServiceClass,
        selectorName: "canPlayContentWithURI:",
        label: "playback-service.canPlayContentWithURI",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlaybackAvailabilityServiceCanPlayURIGroup.isActive {
            StudifyProbePlaybackAvailabilityServiceCanPlayURIGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePlaybackAvailabilityServiceClass,
        selectorName: "screen:canPlayContent:",
        label: "playback-service.screenCanPlayContent",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlaybackAvailabilityServiceScreenCanPlayGroup.isActive {
            StudifyProbePlaybackAvailabilityServiceScreenCanPlayGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePlaybackAvailabilityDataSourceClass,
        selectorName: "canPlayContent:",
        label: "playback-data-source.canPlayContent",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlaybackAvailabilityDataSourceCanPlayGroup.isActive {
            StudifyProbePlaybackAvailabilityDataSourceCanPlayGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePlaybackAvailabilityDataSourceClass,
        selectorName: "canPlayContentWithURI:",
        label: "playback-data-source.canPlayContentWithURI",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlaybackAvailabilityDataSourceCanPlayURIGroup.isActive {
            StudifyProbePlaybackAvailabilityDataSourceCanPlayURIGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePlaybackAvailabilityDataSourceClass,
        selectorName: "isPlayable",
        label: "playback-data-source.isPlayable",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlaybackAvailabilityDataSourceIsPlayableGroup.isActive {
            StudifyProbePlaybackAvailabilityDataSourceIsPlayableGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePlayableCacheAvailabilityClass,
        selectorName: "isDownloaded",
        label: "playable-cache.isDownloaded",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlayableCacheIsDownloadedGroup.isActive {
            StudifyProbePlayableCacheIsDownloadedGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePlayableCacheAvailabilityClass,
        selectorName: "contentIsDownloaded",
        label: "playable-cache.contentIsDownloaded",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlayableCacheContentIsDownloadedGroup.isActive {
            StudifyProbePlayableCacheContentIsDownloadedGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePlayableCacheAvailabilityClass,
        selectorName: "isPlayable",
        label: "playable-cache.isPlayable",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePlayableCacheIsPlayableGroup.isActive {
            StudifyProbePlayableCacheIsPlayableGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbeDownloadedContentCheckerClass,
        selectorName: "isDownloaded",
        label: "downloaded-checker.isDownloaded",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbeDownloadedContentIsDownloadedGroup.isActive {
            StudifyProbeDownloadedContentIsDownloadedGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbeDownloadedContentCheckerClass,
        selectorName: "contentIsDownloaded",
        label: "downloaded-checker.contentIsDownloaded",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbeDownloadedContentContentIsDownloadedGroup.isActive {
            StudifyProbeDownloadedContentContentIsDownloadedGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePLTrackViewModelClass,
        selectorName: "isPlayable",
        label: "pl-track-view-model.isPlayable",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePLTrackViewModelIsPlayableGroup.isActive {
            StudifyProbePLTrackViewModelIsPlayableGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePLTrackViewModelClass,
        selectorName: "isDownloaded",
        label: "pl-track-view-model.isDownloaded",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePLTrackViewModelIsDownloadedGroup.isActive {
            StudifyProbePLTrackViewModelIsDownloadedGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbePLTrackViewModelClass,
        selectorName: "contentIsDownloaded",
        label: "pl-track-view-model.contentIsDownloaded",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbePLTrackViewModelContentIsDownloadedGroup.isActive {
            StudifyProbePLTrackViewModelContentIsDownloadedGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbeFTPRestrictionResolverClass,
        selectorName: "isPlayable",
        label: "ftp-restriction.isPlayable",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbeFTPRestrictionResolverIsPlayableGroup.isActive {
            StudifyProbeFTPRestrictionResolverIsPlayableGroup().activate()
        }
    }

    studifyActivateBoolProbe(
        className: studifyProbeFTPRestrictionResolverClass,
        selectorName: "canPlayContent:",
        label: "ftp-restriction.canPlayContent",
        activated: &activated,
        skipped: &skipped
    ) {
        if !StudifyProbeFTPRestrictionResolverCanPlayGroup.isActive {
            StudifyProbeFTPRestrictionResolverCanPlayGroup().activate()
        }
    }

    studifyOverlayLog("Observe-only native method probe activated=\(activated.joined(separator: ",")) skipped=\(skipped.joined(separator: ","))")
    StudifyProbeStreamClient.shared.emit(
        hook: "native-method-probe",
        phase: "activated",
        message: "observe-only",
        data: [
            "activated": activated,
            "skipped": skipped
        ],
        requireActive: false
    )
}

private func studifyActivateBoolProbe(
    className: String,
    selectorName: String,
    label: String,
    activated: inout [String],
    skipped: inout [String],
    activate: () -> Void
) {
    guard let cls = NSClassFromString(className) as? NSObject.Type else {
        skipped.append("\(label):class-missing")
        return
    }

    let selector = Selector((selectorName))
    guard cls.instancesRespond(to: selector) else {
        skipped.append("\(label):selector-missing")
        return
    }

    guard studifyProbeMethodReturnsBool(cls, selector: selector) else {
        skipped.append("\(label):non-bool-return")
        return
    }

    activate()
    activated.append(label)
}

private func studifyProbeMethodReturnsBool(_ cls: NSObject.Type, selector: Selector) -> Bool {
    guard let method = class_getInstanceMethod(cls, selector),
          let encodingPointer = method_getTypeEncoding(method)
    else {
        return false
    }

    let encoding = String(cString: encodingPointer)
    return encoding.hasPrefix("B") || encoding.hasPrefix("c")
}

private final class StudifyNativeMethodProbeRecorder {
    static let shared = StudifyNativeMethodProbeRecorder()

    private let queue = DispatchQueue(label: "studify.native.method.probe")
    private var lastLogByKey: [String: Date] = [:]

    private init() { }

    func record(className: String, selector: String, args: [String: String] = [:], result: Bool) {
        let key = "\(className)-\(selector)-\(args.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))-\(result)"

        queue.async {
            let now = Date()
            if let lastLog = self.lastLogByKey[key], now.timeIntervalSince(lastLog) < 0.35 {
                return
            }
            self.lastLogByKey[key] = now

            studifyOverlayLog("Observe-only native method probe class=\(className) selector=\(selector) result=\(result) args=\(args)")
            StudifyProbeStreamClient.shared.emit(
                hook: "native-method",
                phase: "return",
                message: "\(selector) -> \(result)",
                className: className,
                selector: selector,
                data: [
                    "result": result,
                    "args": args
                ],
                throttleKey: key,
                minInterval: 0.35
            )
        }
    }
}

private func studifyProbeDescribe(_ value: AnyObject?) -> String {
    guard let value else { return "nil" }

    if let string = value as? String {
        return studifyProbeClean(string)
    }

    if let string = value as? NSString {
        return studifyProbeClean(string as String)
    }

    if let url = value as? URL {
        return studifyProbeClean(url.absoluteString)
    }

    if let url = value as? NSURL {
        return studifyProbeClean(url.absoluteString ?? "")
    }

    if let dictionary = value as? NSDictionary {
        var pairs: [String] = []
        for (key, value) in dictionary {
            pairs.append("\(studifyProbeClean("\(key)")):\(studifyProbeClean("\(value)"))")
        }
        return "dict{\(pairs.prefix(6).joined(separator: "|"))}"
    }

    guard let object = value as? NSObject else {
        return studifyProbeClean("\(value)")
    }

    let className = NSStringFromClass(type(of: object))
    let selectors = ["URI", "uri", "trackURI", "trackUri", "trackTitle", "title", "name"]
    var parts: [String] = []
    for selectorName in selectors {
        let selector = Selector((selectorName))
        guard object.responds(to: selector),
              studifyProbeMethodReturnsObject(object, selector: selector),
              let result = object.perform(selector)?.takeUnretainedValue()
        else {
            continue
        }
        parts.append("\(selectorName)=\(studifyProbeDescribe(result))")
    }

    if parts.isEmpty {
        return className
    }
    return "\(className){\(parts.prefix(5).joined(separator: ","))}"
}

private func studifyProbeMethodReturnsObject(_ object: NSObject, selector: Selector) -> Bool {
    guard let method = class_getInstanceMethod(type(of: object), selector),
          let encodingPointer = method_getTypeEncoding(method)
    else {
        return false
    }

    let encoding = String(cString: encodingPointer)
    return encoding.hasPrefix("@")
}

private func studifyProbeClean(_ value: String) -> String {
    let cleaned = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\t", with: " ")

    if cleaned.count > 180 {
        return "\(cleaned.prefix(180))..."
    }
    return cleaned
}

class StudifyProbePlaybackAvailabilityServiceCanPlayHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlaybackAvailabilityServiceCanPlayGroup
    static let targetName = studifyProbePlaybackAvailabilityServiceClass

    func canPlayContent(_ content: AnyObject) -> Bool {
        let result = orig.canPlayContent(content)
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContent:",
            args: ["content": studifyProbeDescribe(content)],
            result: result
        )
        return result
    }
}

class StudifyProbePlaybackAvailabilityServiceCanPlayURIHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlaybackAvailabilityServiceCanPlayURIGroup
    static let targetName = studifyProbePlaybackAvailabilityServiceClass

    func canPlayContentWithURI(_ uri: AnyObject) -> Bool {
        let result = orig.canPlayContentWithURI(uri)
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContentWithURI:",
            args: ["uri": studifyProbeDescribe(uri)],
            result: result
        )
        return result
    }
}

class StudifyProbePlaybackAvailabilityServiceScreenCanPlayHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlaybackAvailabilityServiceScreenCanPlayGroup
    static let targetName = studifyProbePlaybackAvailabilityServiceClass

    func screen(_ screen: AnyObject, canPlayContent content: AnyObject) -> Bool {
        let result = orig.screen(screen, canPlayContent: content)
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "screen:canPlayContent:",
            args: [
                "screen": studifyProbeDescribe(screen),
                "content": studifyProbeDescribe(content)
            ],
            result: result
        )
        return result
    }
}

class StudifyProbePlaybackAvailabilityDataSourceCanPlayHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlaybackAvailabilityDataSourceCanPlayGroup
    static let targetName = studifyProbePlaybackAvailabilityDataSourceClass

    func canPlayContent(_ content: AnyObject) -> Bool {
        let result = orig.canPlayContent(content)
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContent:",
            args: ["content": studifyProbeDescribe(content)],
            result: result
        )
        return result
    }
}

class StudifyProbePlaybackAvailabilityDataSourceCanPlayURIHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlaybackAvailabilityDataSourceCanPlayURIGroup
    static let targetName = studifyProbePlaybackAvailabilityDataSourceClass

    func canPlayContentWithURI(_ uri: AnyObject) -> Bool {
        let result = orig.canPlayContentWithURI(uri)
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContentWithURI:",
            args: ["uri": studifyProbeDescribe(uri)],
            result: result
        )
        return result
    }
}

class StudifyProbePlaybackAvailabilityDataSourceIsPlayableHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlaybackAvailabilityDataSourceIsPlayableGroup
    static let targetName = studifyProbePlaybackAvailabilityDataSourceClass

    func isPlayable() -> Bool {
        let result = orig.isPlayable()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "isPlayable",
            result: result
        )
        return result
    }
}

class StudifyProbePlayableCacheIsDownloadedHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlayableCacheIsDownloadedGroup
    static let targetName = studifyProbePlayableCacheAvailabilityClass

    func isDownloaded() -> Bool {
        let result = orig.isDownloaded()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "isDownloaded",
            result: result
        )
        return result
    }
}

class StudifyProbePlayableCacheContentIsDownloadedHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlayableCacheContentIsDownloadedGroup
    static let targetName = studifyProbePlayableCacheAvailabilityClass

    func contentIsDownloaded() -> Bool {
        let result = orig.contentIsDownloaded()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "contentIsDownloaded",
            result: result
        )
        return result
    }
}

class StudifyProbePlayableCacheIsPlayableHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePlayableCacheIsPlayableGroup
    static let targetName = studifyProbePlayableCacheAvailabilityClass

    func isPlayable() -> Bool {
        let result = orig.isPlayable()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "isPlayable",
            result: result
        )
        return result
    }
}

class StudifyProbeDownloadedContentIsDownloadedHook: ClassHook<NSObject> {
    typealias Group = StudifyProbeDownloadedContentIsDownloadedGroup
    static let targetName = studifyProbeDownloadedContentCheckerClass

    func isDownloaded() -> Bool {
        let result = orig.isDownloaded()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "isDownloaded",
            result: result
        )
        return result
    }
}

class StudifyProbeDownloadedContentContentIsDownloadedHook: ClassHook<NSObject> {
    typealias Group = StudifyProbeDownloadedContentContentIsDownloadedGroup
    static let targetName = studifyProbeDownloadedContentCheckerClass

    func contentIsDownloaded() -> Bool {
        let result = orig.contentIsDownloaded()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "contentIsDownloaded",
            result: result
        )
        return result
    }
}

class StudifyProbePLTrackViewModelIsPlayableHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePLTrackViewModelIsPlayableGroup
    static let targetName = studifyProbePLTrackViewModelClass

    func isPlayable() -> Bool {
        let result = orig.isPlayable()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "isPlayable",
            result: result
        )
        return result
    }
}

class StudifyProbePLTrackViewModelIsDownloadedHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePLTrackViewModelIsDownloadedGroup
    static let targetName = studifyProbePLTrackViewModelClass

    func isDownloaded() -> Bool {
        let result = orig.isDownloaded()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "isDownloaded",
            result: result
        )
        return result
    }
}

class StudifyProbePLTrackViewModelContentIsDownloadedHook: ClassHook<NSObject> {
    typealias Group = StudifyProbePLTrackViewModelContentIsDownloadedGroup
    static let targetName = studifyProbePLTrackViewModelClass

    func contentIsDownloaded() -> Bool {
        let result = orig.contentIsDownloaded()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "contentIsDownloaded",
            result: result
        )
        return result
    }
}

class StudifyProbeFTPRestrictionResolverIsPlayableHook: ClassHook<NSObject> {
    typealias Group = StudifyProbeFTPRestrictionResolverIsPlayableGroup
    static let targetName = studifyProbeFTPRestrictionResolverClass

    func isPlayable() -> Bool {
        let result = orig.isPlayable()
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "isPlayable",
            result: result
        )
        return result
    }
}

class StudifyProbeFTPRestrictionResolverCanPlayHook: ClassHook<NSObject> {
    typealias Group = StudifyProbeFTPRestrictionResolverCanPlayGroup
    static let targetName = studifyProbeFTPRestrictionResolverClass

    func canPlayContent(_ content: AnyObject) -> Bool {
        let result = orig.canPlayContent(content)
        StudifyNativeMethodProbeRecorder.shared.record(
            className: Self.targetName,
            selector: "canPlayContent:",
            args: ["content": studifyProbeDescribe(content)],
            result: result
        )
        return result
    }
}
