import ObjectiveC
import UIKit

private struct StudifyFakeTrack: Equatable, Hashable {
    let title: String
    let artist: String
}

private let studifySeededGimmeLoveURI = "spotify:track:3CUovld1O1HdAOrkgMlvNx"
private let studifySeededGimmeLoveTrack = StudifyFakeTrack(title: "Gimme Love", artist: "Vista Kicks")

final class StudifyFakePlaybackController: NSObject, UIGestureRecognizerDelegate {
    static let shared = StudifyFakePlaybackController()

    private enum PlaybackIntent: String {
        case toggle
        case next
        case previous
    }

    private struct ViewSnapshot {
        let entries: [(key: String, value: String)]
    }

    private var installed = false
    private var scanTimer: Timer?
    private var progressTimer: Timer?
    private var tapGesture: UITapGestureRecognizer?
    private var lastVisualProbeLogAt = Date(timeIntervalSince1970: 0)
    private var lastMutationProbeAt = Date(timeIntervalSince1970: 0)
    private var lastMiniPlayerSkipLogAt = Date(timeIntervalSince1970: 0)
    private var lastControlIntentAt: [PlaybackIntent: Date] = [:]
    private var lastPassiveRowStartAtByTrack: [StudifyFakeTrack: Date] = [:]
    private var lastPressPathProbeAtByTrack: [StudifyFakeTrack: Date] = [:]
    private var lastGenericTapProbeAt = Date(timeIntervalSince1970: 0)
    private weak var currentVisualRow: UIView?
    private weak var currentMiniPlayerView: UIView?
    private var cachedOfflineModeActive = false
    private var visualGeneration = 0

    private var visibleTracks: [StudifyFakeTrack] = []
    private var currentTrack: StudifyFakeTrack?
    private var isPlaying = false
    private var progress: Float = 0
    private var directMiniPlayerMutationEnabled: Bool {
        UserDefaults.standard.bool(forKey: "StudifyAllowDirectMiniPlayerMutation")
    }

    private override init() {
        super.init()
    }

    func install() {
        DispatchQueue.main.async {
            guard !self.installed else { return }
            self.installed = true
            self.scanTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                self?.refreshVisiblePlaylistState()
            }
            self.progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.advanceProgress()
            }
            if let scanTimer = self.scanTimer {
                RunLoop.main.add(scanTimer, forMode: .common)
            }
            if let progressTimer = self.progressTimer {
                RunLoop.main.add(progressTimer, forMode: .common)
            }
            StudifyLocalAudioPlayer.shared.prepareLibraryFolder()
            self.refreshVisiblePlaylistState()
            studifyOverlayLog("Studify native playback bridge installed")

            // Phase 2: no demo overlay and no autoplay probe. Playback starts from Spotify UI taps.
        }
    }

    func refreshCell(_ cell: UIView) {
        DispatchQueue.main.async {
            guard self.cachedOfflineModeActive || studifyOverlayProbeModeEnabled else { return }
            guard self.looksLikeTrackRow(cell) else { return }
            if studifyOverlayProbeModeEnabled {
                StudifyOfflinePathwayProbe.shared.logObjectContext(cell, reason: "refreshCell")
                StudifyProbeStreamClient.shared.emit(
                    hook: "playlist-cell",
                    phase: "layout",
                    message: self.usefulTextValues(in: cell, maxDepth: 4).prefix(3).joined(separator: " | "),
                    className: NSStringFromClass(type(of: cell)),
                    selector: "layoutSubviews",
                    throttleKey: "playlist-cell-\(NSStringFromClass(type(of: cell)))",
                    minInterval: 2
                )
            }
            let mutations = self.enableNativeInteraction(in: cell)
            if studifyOverlayProbeModeEnabled, mutations > 0 {
                StudifyProbeStreamClient.shared.emit(
                    hook: "offline-ui-mutator",
                    phase: "cell-mutated",
                    message: self.usefulTextValues(in: cell, maxDepth: 4).prefix(3).joined(separator: " | "),
                    className: NSStringFromClass(type(of: cell)),
                    selector: "layoutSubviews",
                    data: ["mutations": mutations],
                    throttleKey: "offline-ui-mutator-cell-\(NSStringFromClass(type(of: cell)))",
                    minInterval: 2,
                    requireActive: false
                )
            }

            if studifyOverlayProbeModeEnabled {
                let now = Date()
                if now.timeIntervalSince(self.lastVisualProbeLogAt) > 5 {
                    self.lastVisualProbeLogAt = now
                    let className = NSStringFromClass(type(of: cell))
                    let text = self.usefulTextValues(in: cell, maxDepth: 4)
                        .prefix(4)
                        .joined(separator: " | ")
                    studifyOverlayLog("Studify cell visual probe class=\(className) text=\(text)")
                }
            }
        }
    }

    func observePlaybackControl(_ control: UIControl, actionName: String) {
        guard cachedOfflineModeActive else { return }

        let intent = playbackIntent(from: control, actionName: actionName)
        guard let intent else { return }
        guard currentTrack != nil || !visibleTracks.isEmpty else { return }

        let now = Date()
        if let last = lastControlIntentAt[intent], now.timeIntervalSince(last) < 0.35 {
            studifyOverlayLog("Passive playback control probe ignored duplicate intent=\(intent.rawValue) action=\(actionName)")
            return
        }
        lastControlIntentAt[intent] = now

        switch intent {
        case .next:
            nextTrack(source: "passive spotify control")
        case .previous:
            previousTrack(source: "passive spotify control")
        case .toggle:
            togglePlayback(source: "passive spotify control")
        }

        studifyOverlayLog("Passive playback control probe intent=\(intent.rawValue) action=\(actionName)")
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "passive-control",
            message: intent.rawValue,
            className: NSStringFromClass(type(of: control)),
            selector: actionName,
            throttleKey: "native-playback-passive-\(intent.rawValue)",
            minInterval: 0.5,
            requireActive: false
        )
    }

    private func refreshVisiblePlaylistState() {
        guard let window = activeWindow() else { return }
        let offlineModeActive = isSpotifyOfflineModeActive(in: window)
        if cachedOfflineModeActive != offlineModeActive {
            studifyOverlayLog("Studify offline simulation mode active=\(offlineModeActive)")
        }
        cachedOfflineModeActive = offlineModeActive

        guard offlineModeActive else {
            if studifyOverlayProbeModeEnabled {
                installTapRecognizerIfNeeded(on: window)
            } else {
                removeTapRecognizerIfNeeded()
            }
            StudifySpotifyStateBridge.shared.clearFakeTrack(reason: "offline-mode-inactive")
            if let currentVisualRow {
                clearSpotifyPlayingVisual(from: currentVisualRow)
            }
            currentVisualRow = nil
            currentMiniPlayerView = nil
            visualGeneration += 1
            return
        }

        installTapRecognizerIfNeeded(on: window)

        var rows: [UIView] = []
        collectTrackRows(in: window, into: &rows, depth: 0)

        var tracks: [StudifyFakeTrack] = []
        var interactiveRows = 0
        var totalMutations = 0
        var didResolveCurrentVisualRow = false
        for row in rows {
            if offlineModeActive {
                totalMutations += enableNativeInteraction(in: row)
            }
            guard let rawTrack = track(from: row) else {
                continue
            }
            let track = canonicalTrack(rawTrack)
            if !tracks.contains(track) {
                interactiveRows += 1
                tracks.append(track)
            }
            let isExactCurrentRow = currentVisualRow.map { $0 === row } ?? false
            let shouldAdoptCurrentRow = currentVisualRow == nil
                && !didResolveCurrentVisualRow
                && track == currentTrack

            if offlineModeActive, isExactCurrentRow || shouldAdoptCurrentRow {
                currentVisualRow = row
                didResolveCurrentVisualRow = true
                applySpotifyPlayingVisual(to: row, animated: false)
            } else if offlineModeActive {
                clearSpotifyPlayingVisual(from: row)
            }
            if studifyOverlayProbeModeEnabled {
                logNativePlaybackStateProbe(row: row, track: track, reason: "window-scan")
            }
        }

        if !tracks.isEmpty {
            visibleTracks = tracks
        }
        if let currentTrack {
            applyNativeMiniPlayerVisual(track: currentTrack)
        }

        let now = Date()
        if studifyOverlayProbeModeEnabled, now.timeIntervalSince(lastVisualProbeLogAt) > 5 {
            lastVisualProbeLogAt = now
            studifyOverlayLog("Studify visual probe rows=\(rows.count) interactive=\(interactiveRows) tracks=\(tracks.count) mutations=\(totalMutations)")
        }

        if studifyOverlayProbeModeEnabled, now.timeIntervalSince(lastMutationProbeAt) > 3 {
            lastMutationProbeAt = now
            StudifyProbeStreamClient.shared.emit(
                hook: "offline-ui-mutator",
                phase: "window-scan",
                message: "rows=\(rows.count) tracks=\(tracks.count) mutations=\(totalMutations)",
                data: [
                    "rows": rows.count,
                    "tracks": tracks.count,
                    "interactiveRows": interactiveRows,
                    "mutations": totalMutations
                ],
                throttleKey: "offline-ui-mutator-window-scan",
                minInterval: 3,
                requireActive: false
            )
        }
    }

    private func installTapRecognizerIfNeeded(on window: UIWindow) {
        if tapGesture?.view === window {
            return
        }

        if let existing = tapGesture {
            existing.view?.removeGestureRecognizer(existing)
        }

        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleWindowTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        tapGesture = recognizer
    }

    private func removeTapRecognizerIfNeeded() {
        guard let recognizer = tapGesture else { return }
        recognizer.view?.removeGestureRecognizer(recognizer)
        tapGesture = nil
    }

    @objc private func handleWindowTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let window = recognizer.view as? UIWindow else { return }
        guard cachedOfflineModeActive || studifyOverlayProbeModeEnabled else { return }
        let point = recognizer.location(in: window)
        guard let hitView = window.hitTest(point, with: nil) else { return }

        guard let row = trackRow(startingAt: hitView) else {
            if studifyOverlayProbeModeEnabled {
                logGenericTapProbe(
                    hitView: hitView,
                    window: window,
                    point: point,
                    reason: cachedOfflineModeActive ? "no-row-candidate" : "online-no-row-candidate"
                )
            }
            return
        }

        if studifyOverlayProbeModeEnabled {
            StudifyProbeStreamClient.shared.start(reason: cachedOfflineModeActive ? "row tap" : "online row tap")
            if let track = track(from: row) {
                logPressPathProbe(
                    hitView: hitView,
                    row: row,
                    track: track,
                    reason: cachedOfflineModeActive ? "window tap ended" : "online window tap ended"
                )
            } else {
                logRowTapWithoutTrackProbe(
                    hitView: hitView,
                    row: row,
                    window: window,
                    point: point,
                    reason: cachedOfflineModeActive ? "row-without-track" : "online-row-without-track"
                )
            }
            return
        }

        guard let track = track(from: row) else {
            return
        }

        start(track: track, row: row, source: "passive row tap")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === tapGesture,
              let view = gestureRecognizer.view
        else {
            return true
        }

        let point = touch.location(in: view)
        guard cachedOfflineModeActive || studifyOverlayProbeModeEnabled else { return false }
        guard let hitView = view.hitTest(point, with: nil) else {
            return false
        }

        if studifyOverlayProbeModeEnabled {
            return true
        }

        return trackRow(startingAt: hitView).flatMap { track(from: $0) } != nil
    }

    private func start(track rawTrack: StudifyFakeTrack, row: UIView? = nil, source: String) {
        if !cachedOfflineModeActive {
            studifyOverlayLog("Native playback bridge skipped outside Spotify offline mode")
            return
        }

        let track = simulatedTrack(for: rawTrack, source: source)
        let now = Date()
        if let lastStart = lastPassiveRowStartAtByTrack[track], now.timeIntervalSince(lastStart) < 0.55 {
            studifyOverlayLog("Passive row tap probe ignored duplicate title=\(track.title) source=\(source)")
            return
        }
        lastPassiveRowStartAtByTrack[track] = now

        currentTrack = track
        publishFakeSpotifyTrack(track, reason: source)
        if !visibleTracks.contains(track) {
            visibleTracks.insert(track, at: 0)
        }
        if track != rawTrack {
            studifyOverlayLog("Native playback bridge using seeded track for offline row press sourceTitle=\(rawTrack.title) sourceArtist=\(rawTrack.artist) seededTitle=\(track.title) seededArtist=\(track.artist) uri=\(spotifyURI(for: track))")
        }
        progress = 0
        isPlaying = startLocalAudioOrSeededSilence(for: track)
        if let row {
            setCurrentSpotifyVisualRow(row)
        }
        StudifySpotifyStateBridge.shared.recordFakeSelection(title: track.title, artist: track.artist, reason: source)
        applyNativeMiniPlayerVisual(track: track)
        if studifyOverlayProbeModeEnabled, let row {
            logNativePlaybackStateProbe(row: row, track: track, reason: "passive-row-tap")
            let beforeRowSnapshot = snapshotTree(from: row, rootName: "row")
            let beforeBottomSnapshot = activeWindow().map {
                snapshotBottomArea(in: $0, rootName: "bottom-before")
            }
            logSnapshot(beforeRowSnapshot, reason: "row-before-native", track: track, maxLines: 44)
            if let beforeBottomSnapshot {
                logSnapshot(beforeBottomSnapshot, reason: "bottom-before-native", track: track, maxLines: 32)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.logNativePlaybackStateProbe(row: row, track: track, reason: "post-native-row-tap")
                let afterRowSnapshot = self.snapshotTree(from: row, rootName: "row")
                self.logSnapshot(afterRowSnapshot, reason: "row-after-native", track: track, maxLines: 44)
                self.logSnapshotDiff(before: beforeRowSnapshot, after: afterRowSnapshot, reason: "row-native-diff", track: track)

                if let window = self.activeWindow() {
                    let afterBottomSnapshot = self.snapshotBottomArea(in: window, rootName: "bottom-after")
                    self.logSnapshot(afterBottomSnapshot, reason: "bottom-after-native", track: track, maxLines: 32)
                    if let beforeBottomSnapshot {
                        self.logSnapshotDiff(before: beforeBottomSnapshot, after: afterBottomSnapshot, reason: "bottom-native-diff", track: track)
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let lateRowSnapshot = self.snapshotTree(from: row, rootName: "row")
                self.logSnapshot(lateRowSnapshot, reason: "row-late-native", track: track, maxLines: 32)
                self.logSnapshotDiff(before: beforeRowSnapshot, after: lateRowSnapshot, reason: "row-late-diff", track: track)
            }
        }
        studifyOverlayLog("Native playback bridge started title=\(track.title) artist=\(track.artist) source=\(source) isPlaying=\(isPlaying)")
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "start",
            message: source,
            data: [
                "title": track.title,
                "artist": track.artist,
                "sourceTitle": rawTrack.title,
                "sourceArtist": rawTrack.artist,
                "uri": spotifyURI(for: track),
                "isPlaying": isPlaying
            ],
            throttleKey: "native-playback-start-\(track.title)",
            minInterval: 0.75
        )
    }

    private func publishFakeSpotifyTrack(_ track: StudifyFakeTrack, reason: String) {
        let uri = spotifyURI(for: track)
        StudifySpotifyStateBridge.shared.setFakeTrack(
            title: track.title,
            artist: track.artist,
            uri: uri,
            reason: reason
        )
        studifyOverlayLog("Native playback bridge published fake Spotify state title=\(track.title) artist=\(track.artist) uri=\(uri) reason=\(reason)")
    }

    private func simulatedTrack(for rawTrack: StudifyFakeTrack, source: String) -> StudifyFakeTrack {
        if source == "passive row tap" {
            return studifySeededGimmeLoveTrack
        }
        return canonicalTrack(rawTrack)
    }

    private func canonicalTrack(_ track: StudifyFakeTrack) -> StudifyFakeTrack {
        seededSpotifyURI(for: track) == nil ? track : studifySeededGimmeLoveTrack
    }

    private func spotifyURI(for track: StudifyFakeTrack) -> String {
        seededSpotifyURI(for: track) ?? localSpotifyURI(for: track)
    }

    private func seededSpotifyURI(for track: StudifyFakeTrack) -> String? {
        let haystack = normalizedSearchText("\(track.title) \(track.artist)")
        if haystack.contains("gimme love"), haystack.contains("vista kicks") {
            return studifySeededGimmeLoveURI
        }
        return nil
    }

    private func localSpotifyURI(for track: StudifyFakeTrack) -> String {
        let raw = "\(track.artist)-\(track.title)".lowercased()
        let allowed = CharacterSet.alphanumerics
        let identifier = raw.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        return "studify:local:\(identifier.isEmpty ? "test-mp3" : identifier)"
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func startLocalAudioOrSeededSilence(for track: StudifyFakeTrack) -> Bool {
        if StudifyLocalAudioPlayer.shared.hasLocalAudio {
            return StudifyLocalAudioPlayer.shared.playTestMP3(restart: true)
        }

        if seededSpotifyURI(for: track) != nil {
            studifyOverlayLog("Native playback bridge simulating seeded offline playback without local audio title=\(track.title) uri=\(spotifyURI(for: track))")
            return true
        }

        return StudifyLocalAudioPlayer.shared.playTestMP3(restart: true)
    }

    private func resumeLocalAudioOrSeededSilence(for track: StudifyFakeTrack) -> Bool {
        if StudifyLocalAudioPlayer.shared.hasLocalAudio {
            return StudifyLocalAudioPlayer.shared.resumeOrRestart()
        }

        if seededSpotifyURI(for: track) != nil {
            studifyOverlayLog("Native playback bridge resuming seeded offline simulation without local audio title=\(track.title) uri=\(spotifyURI(for: track))")
            return true
        }

        return StudifyLocalAudioPlayer.shared.resumeOrRestart()
    }

    private func setCurrentSpotifyVisualRow(_ row: UIView) {
        guard cachedOfflineModeActive else { return }

        visualGeneration += 1
        let generation = visualGeneration

        if let previousRow = currentVisualRow, previousRow !== row {
            clearSpotifyPlayingVisual(from: previousRow)
        }

        currentVisualRow = row
        clearOtherSpotifyPlayingVisuals(keeping: row)
        applySpotifyPlayingVisual(to: row, animated: true)
        studifyOverlayLog("Fast Spotify row visual applied offline-only")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak row] in
            guard let self, let row, row.window != nil else { return }
            guard self.cachedOfflineModeActive else { return }
            guard self.visualGeneration == generation, self.currentVisualRow === row else { return }
            self.clearOtherSpotifyPlayingVisuals(keeping: row)
            self.applySpotifyPlayingVisual(to: row, animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak row] in
            guard let self, let row, row.window != nil else { return }
            guard self.cachedOfflineModeActive else { return }
            guard self.visualGeneration == generation, self.currentVisualRow === row else { return }
            self.clearOtherSpotifyPlayingVisuals(keeping: row)
            self.applySpotifyPlayingVisual(to: row, animated: false)
        }
    }

    private func clearOtherSpotifyPlayingVisuals(keeping currentRow: UIView?) {
        guard let window = activeWindow() else { return }
        var rows: [UIView] = []
        collectTrackRows(in: window, into: &rows, depth: 0)

        for row in rows where currentRow.map({ $0 !== row }) ?? true {
            clearSpotifyPlayingVisual(from: row)
        }
    }

    private func applySpotifyPlayingVisual(to row: UIView, animated: Bool) {
        let mutation = {
            self.setPlayIndicatorWidth(in: row, width: 16, visible: true)
            self.setTitleOffset(in: row, offset: 16)
            self.setTitleColor(in: row, color: self.spotifyGreen)
        }

        if animated {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                mutation()
                row.layoutIfNeeded()
            }
        } else {
            mutation()
        }

        row.isUserInteractionEnabled = true
        row.alpha = 1
    }

    private func clearSpotifyPlayingVisual(from row: UIView) {
        setPlayIndicatorWidth(in: row, width: 0, visible: false)
        setTitleOffset(in: row, offset: 0)
        setTitleColor(in: row, color: .white)
    }

    private var spotifyGreen: UIColor {
        UIColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1)
    }

    private func setPlayIndicatorWidth(in row: UIView, width: CGFloat, visible: Bool) {
        for view in views(in: row) where view.accessibilityIdentifier == "Components.UI.PlayIndicator" {
            view.isHidden = false
            view.alpha = visible ? 1 : 0
            updateWidthConstraints(on: view, width: width)
            setFrameWidth(view, width: width)
            for subview in views(in: view).dropFirst() {
                if !isStudifyFastPlayIndicatorBar(subview) {
                    subview.isHidden = false
                    subview.alpha = visible ? 1 : subview.alpha
                }
            }
            if visible {
                ensureFastPlayIndicatorBars(in: view)
            } else {
                removeFastPlayIndicatorBars(from: view)
            }

            if let container = view.superview {
                updateWidthConstraints(on: container, width: width)
                setFrameWidth(container, width: width)
                container.isHidden = false
                container.alpha = 1
            }
        }
    }

    private func setTitleOffset(in row: UIView, offset: CGFloat) {
        for view in views(in: row) where view.accessibilityIdentifier == "Track.Row.Content.Title" {
            shiftFrame(view, x: offset)
        }

        for label in labels(in: row) where label.accessibilityIdentifier == "Track.Row.Content.Title-internal" {
            shiftFrame(label, x: offset)
        }
    }

    private func setTitleColor(in row: UIView, color: UIColor) {
        for label in labels(in: row) where label.accessibilityIdentifier == "Track.Row.Content.Title-internal" {
            label.textColor = color
            if let attributedText = label.attributedText, attributedText.length > 0 {
                let mutable = NSMutableAttributedString(attributedString: attributedText)
                mutable.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: mutable.length))
                label.attributedText = mutable
            }
        }
    }

    private func shiftFrame(_ view: UIView, x: CGFloat) {
        var frame = view.frame
        let delta = x - frame.minX
        guard abs(delta) > 0.5 else { return }
        frame.origin.x = x
        frame.size.width = max(0, frame.size.width - delta)
        view.frame = frame
    }

    private func setFrameWidth(_ view: UIView, width: CGFloat) {
        var frame = view.frame
        frame.size.width = width
        view.frame = frame
    }

    private func updateWidthConstraints(on view: UIView, width: CGFloat) {
        for constraint in view.constraints where constraint.firstAttribute == .width {
            constraint.constant = width
        }
    }

    private func ensureFastPlayIndicatorBars(in indicator: UIView) {
        let existingBars = indicator.subviews.filter(isStudifyFastPlayIndicatorBar)
        guard existingBars.count < 3 else {
            for bar in existingBars {
                bar.isHidden = false
                bar.alpha = 1
                if bar.layer.animationKeys()?.isEmpty ?? true {
                    animateFastPlayIndicatorBar(bar)
                }
            }
            return
        }

        removeFastPlayIndicatorBars(from: indicator)

        let barWidth: CGFloat = 2
        let barColor = spotifyGreen
        for index in 0..<3 {
            let x = CGFloat(index) * 4 + 2
            let bar = UIView(frame: CGRect(x: x, y: 2, width: barWidth, height: 8))
            bar.accessibilityIdentifier = "Studify.FastPlayIndicatorBar"
            bar.backgroundColor = barColor
            bar.layer.cornerRadius = 1
            bar.isUserInteractionEnabled = false
            indicator.addSubview(bar)
            animateFastPlayIndicatorBar(bar, delay: Double(index) * 0.09)
        }
    }

    private func animateFastPlayIndicatorBar(_ bar: UIView, delay: TimeInterval = 0) {
        bar.layer.removeAllAnimations()
        let originalFrame = bar.frame
        let tallFrame = CGRect(x: originalFrame.minX, y: 1, width: originalFrame.width, height: 10)
        let shortFrame = CGRect(x: originalFrame.minX, y: 5, width: originalFrame.width, height: 5)
        bar.frame = shortFrame
        UIView.animate(
            withDuration: 0.34,
            delay: delay,
            options: [.autoreverse, .repeat, .allowUserInteraction, .beginFromCurrentState],
            animations: {
                bar.frame = tallFrame
            }
        )
    }

    private func removeFastPlayIndicatorBars(from indicator: UIView) {
        for bar in indicator.subviews where isStudifyFastPlayIndicatorBar(bar) {
            bar.layer.removeAllAnimations()
            bar.removeFromSuperview()
        }
    }

    private func isStudifyFastPlayIndicatorBar(_ view: UIView) -> Bool {
        view.accessibilityIdentifier == "Studify.FastPlayIndicatorBar"
    }

    private func applyNativeMiniPlayerVisual(track: StudifyFakeTrack) {
        guard directMiniPlayerMutationEnabled else {
            let now = Date()
            if now.timeIntervalSince(lastMiniPlayerSkipLogAt) > 3 {
                lastMiniPlayerSkipLogAt = now
                studifyOverlayLog("State-first mode skipped direct mini-player UI mutation")
            }
            StudifySpotifyStateBridge.shared.logCurrentSpotifyState(reason: "mini-player-update-skipped")
            return
        }

        guard cachedOfflineModeActive, let window = activeWindow() else { return }
        let cachedMiniPlayer = currentMiniPlayerView.flatMap { view in
            isNativeMiniPlayerCandidate(view, in: window) ? view : nil
        }
        guard let miniPlayer = cachedMiniPlayer ?? findNativeMiniPlayer(in: window) else {
            let now = Date()
            if now.timeIntervalSince(lastMiniPlayerSkipLogAt) > 3 {
                lastMiniPlayerSkipLogAt = now
                studifyOverlayLog("Native mini player visual skipped no candidate")
            }
            return
        }
        currentMiniPlayerView = miniPlayer

        let labels = miniPlayerLabels(in: miniPlayer, window: window)

        if let titleLabel = labels.first {
            updateMiniPlayerLabel(titleLabel, text: track.title, color: .white)
        }
        if labels.count > 1 {
            updateMiniPlayerLabel(labels[1], text: track.artist, color: spotifyGreen)
        }

        for progressView in views(in: miniPlayer).compactMap({ $0 as? UIProgressView }) {
            progressView.progressTintColor = spotifyGreen
            progressView.trackTintColor = UIColor(white: 1, alpha: 0.22)
            progressView.progress = progress
        }

        for view in views(in: miniPlayer) where view.accessibilityIdentifier?.contains("PlayIndicator") == true {
            ensureFastPlayIndicatorBars(in: view)
        }

        miniPlayer.alpha = 1
        miniPlayer.isHidden = false
        studifyOverlayLog("Native mini player visual applied offline-only")
    }

    private func findNativeMiniPlayer(in window: UIWindow) -> UIView? {
        let candidates = views(in: window, maxDepth: 14).compactMap { view -> (view: UIView, score: Int, rect: CGRect)? in
            guard isNativeMiniPlayerCandidate(view, in: window) else { return nil }

            let rect = view.convert(view.bounds, to: window)
            let className = NSStringFromClass(type(of: view)).lowercased()
            var score = 0

            if className.contains("nowplaying") { score += 50 }
            if className.contains("player") { score += 30 }
            if className.contains("bar") { score += 20 }
            if className.contains("mini") { score += 12 }
            if views(in: view, maxDepth: 4).contains(where: { $0 is UIProgressView }) { score += 18 }
            if views(in: view, maxDepth: 4).contains(where: { $0.accessibilityIdentifier?.contains("PlayIndicator") == true }) { score += 10 }
            if rect.minY >= window.bounds.height - max(window.safeAreaInsets.bottom, 0) - 145 { score += 10 }
            if rect.height >= 48 && rect.height <= 88 { score += 8 }

            return (view, score, rect)
        }

        let chosen = candidates
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if abs(lhs.rect.minY - rhs.rect.minY) > 2 {
                    return lhs.rect.minY > rhs.rect.minY
                }
                return lhs.rect.height < rhs.rect.height
            }
            .first

        if let chosen {
            studifyOverlayLog("Native mini player candidate class=\(NSStringFromClass(type(of: chosen.view))) score=\(chosen.score) frame=\(format(rect: chosen.rect))")
        }

        return chosen?.view
    }

    private func isNativeMiniPlayerCandidate(_ view: UIView, in window: UIWindow) -> Bool {
        guard !view.isHidden, view.alpha > 0.01 else { return false }

        let rect = view.convert(view.bounds, to: window)
        let bottomInset = max(window.safeAreaInsets.bottom, 0)
        let bottomThreshold = window.bounds.height - bottomInset - 210

        guard rect.minY >= bottomThreshold,
              rect.maxY <= window.bounds.height + 4,
              rect.width >= window.bounds.width * 0.68,
              rect.height >= 36,
              rect.height <= 120
        else {
            return false
        }

        let labels = miniPlayerLabels(in: view, window: window)
        guard labels.count >= 2 else { return false }

        let visibleText = labels
            .compactMap { $0.text ?? $0.accessibilityLabel }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let tabHits = Set(["home", "search", "your library", "create"]).intersection(visibleText)

        return tabHits.count < 2
    }

    private func miniPlayerLabels(in miniPlayer: UIView, window: UIWindow) -> [UILabel] {
        labels(in: miniPlayer)
            .filter { label in
                guard !label.isHidden, label.alpha > 0.01 else { return false }
                let rect = label.convert(label.bounds, to: window)
                guard rect.width > 4, rect.height > 4 else { return false }
                let text = (label.text ?? label.accessibilityLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !text.isEmpty && !isMiniPlayerIgnoredText(text)
            }
            .sorted { lhs, rhs in
                let left = lhs.convert(lhs.bounds, to: window)
                let right = rhs.convert(rhs.bounds, to: window)
                if abs(left.minY - right.minY) > 2 {
                    return left.minY < right.minY
                }
                return left.minX < right.minX
            }
    }

    private func updateMiniPlayerLabel(_ label: UILabel, text: String, color: UIColor) {
        label.text = text
        label.textColor = color
        label.alpha = 1
        label.isEnabled = true

        if let attributedText = label.attributedText, attributedText.length > 0 {
            let mutable = NSMutableAttributedString(string: text)
            mutable.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: mutable.length))
            mutable.addAttribute(.font, value: label.font as Any, range: NSRange(location: 0, length: mutable.length))
            label.attributedText = mutable
        }
    }

    private func togglePlayback(source: String) {
        guard currentTrack != nil || !visibleTracks.isEmpty else { return }
        if currentTrack == nil, let first = visibleTracks.first {
            currentTrack = first
        }

        if isPlaying {
            StudifyLocalAudioPlayer.shared.pause()
            isPlaying = false
        } else if let currentTrack {
            isPlaying = resumeLocalAudioOrSeededSilence(for: currentTrack)
        } else {
            isPlaying = StudifyLocalAudioPlayer.shared.resumeOrRestart()
        }

        studifyOverlayLog("Native playback bridge toggled isPlaying=\(isPlaying) source=\(source)")
        if let currentTrack {
            publishFakeSpotifyTrack(currentTrack, reason: source)
            StudifySpotifyStateBridge.shared.recordFakeSelection(title: currentTrack.title, artist: currentTrack.artist, reason: source)
            applyNativeMiniPlayerVisual(track: currentTrack)
        }
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "toggle",
            message: source,
            data: [
                "title": currentTrack?.title ?? "",
                "artist": currentTrack?.artist ?? "",
                "uri": currentTrack.map { spotifyURI(for: $0) } ?? "",
                "isPlaying": isPlaying
            ],
            throttleKey: "native-playback-toggle",
            minInterval: 0.5
        )
    }

    private func nextTrack(source: String) {
        guard !visibleTracks.isEmpty else { return }
        let nextIndex: Int
        if let currentTrack, let currentIndex = visibleTracks.firstIndex(of: currentTrack) {
            nextIndex = (currentIndex + 1) % visibleTracks.count
        } else {
            nextIndex = 0
        }
        currentTrack = visibleTracks[nextIndex]
        progress = 0
        isPlaying = currentTrack.map { startLocalAudioOrSeededSilence(for: $0) } ?? false
        if let currentTrack {
            publishFakeSpotifyTrack(currentTrack, reason: source)
            if let row = visibleRow(for: currentTrack) {
                setCurrentSpotifyVisualRow(row)
            } else {
                currentVisualRow = nil
                clearOtherSpotifyPlayingVisuals(keeping: nil)
            }
            StudifySpotifyStateBridge.shared.recordFakeSelection(title: currentTrack.title, artist: currentTrack.artist, reason: source)
            applyNativeMiniPlayerVisual(track: currentTrack)
        }
        studifyOverlayLog("Native playback bridge next source=\(source)")
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "next",
            message: source,
            data: [
                "title": currentTrack?.title ?? "",
                "artist": currentTrack?.artist ?? "",
                "uri": currentTrack.map { spotifyURI(for: $0) } ?? ""
            ],
            throttleKey: "native-playback-next",
            minInterval: 0.5
        )
    }

    private func previousTrack(source: String) {
        guard !visibleTracks.isEmpty else { return }
        let previousIndex: Int
        if let currentTrack, let currentIndex = visibleTracks.firstIndex(of: currentTrack) {
            previousIndex = (currentIndex - 1 + visibleTracks.count) % visibleTracks.count
        } else {
            previousIndex = 0
        }
        currentTrack = visibleTracks[previousIndex]
        progress = 0
        isPlaying = currentTrack.map { startLocalAudioOrSeededSilence(for: $0) } ?? false
        if let currentTrack {
            publishFakeSpotifyTrack(currentTrack, reason: source)
            if let row = visibleRow(for: currentTrack) {
                setCurrentSpotifyVisualRow(row)
            } else {
                currentVisualRow = nil
                clearOtherSpotifyPlayingVisuals(keeping: nil)
            }
            StudifySpotifyStateBridge.shared.recordFakeSelection(title: currentTrack.title, artist: currentTrack.artist, reason: source)
            applyNativeMiniPlayerVisual(track: currentTrack)
        }
        studifyOverlayLog("Native playback bridge previous source=\(source)")
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "previous",
            message: source,
            data: [
                "title": currentTrack?.title ?? "",
                "artist": currentTrack?.artist ?? "",
                "uri": currentTrack.map { spotifyURI(for: $0) } ?? ""
            ],
            throttleKey: "native-playback-previous",
            minInterval: 0.5
        )
    }

    private func advanceProgress() {
        guard isPlaying else { return }
        let audioProgress = StudifyLocalAudioPlayer.shared.progress
        progress = audioProgress > 0 ? audioProgress : progress + 0.008
        if let currentTrack {
            applyNativeMiniPlayerVisual(track: currentTrack)
        }
        if progress >= 1 {
            nextTrack(source: "auto continue")
            return
        }
    }

    private func collectTrackRows(in view: UIView, into rows: inout [UIView], depth: Int) {
        guard depth <= 12, !view.isHidden else { return }

        if looksLikeTrackRow(view) {
            rows.append(view)
            return
        }

        for subview in view.subviews {
            collectTrackRows(in: subview, into: &rows, depth: depth + 1)
        }
    }

    private func visibleRow(for track: StudifyFakeTrack) -> UIView? {
        guard let window = activeWindow() else { return nil }
        var rows: [UIView] = []
        collectTrackRows(in: window, into: &rows, depth: 0)
        return rows.first { row in
            self.track(from: row).map(self.canonicalTrack) == track
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
        guard let window = view.window ?? activeWindow() else { return false }
        let rect = view.convert(view.bounds, to: window)
        guard rect.width >= 180, rect.height >= 28, rect.height <= 132 else { return false }
        guard rect.minY > window.safeAreaInsets.top + 70 else { return false }
        guard rect.maxY < window.bounds.height - max(window.safeAreaInsets.bottom, 0) - 92 else { return false }

        let className = NSStringFromClass(type(of: view)).lowercased()
        let classLooksRowLike = className.contains("cell")
            || className.contains("row")
            || className.contains("track")
            || className.contains("collection")
            || className.contains("table")

        if classLooksRowLike {
            return true
        }

        let values = usefulTextValues(in: view, maxDepth: 6)
        guard !values.isEmpty else { return false }
        guard values.contains(where: { $0.count >= 5 }) else { return false }

        return values.count <= 10
    }

    private func track(from row: UIView) -> StudifyFakeTrack? {
        let values = usefulTextValues(in: row, maxDepth: 4)
        guard values.count >= 2 else { return nil }

        let joined = values.joined(separator: " ").lowercased()
        guard !joined.contains("playlist"),
              !joined.contains("recommended songs"),
              !joined.contains("go online") else {
            return nil
        }

        let title = values[0]
        let artist = values.dropFirst().first(where: { $0 != title }) ?? "Studify local"
        return StudifyFakeTrack(title: title, artist: artist)
    }

    private func logNativePlaybackStateProbe(row: UIView, track: StudifyFakeTrack, reason: String) {
        let labels = usefulTextValues(in: row, maxDepth: 5).prefix(6).joined(separator: " | ")
        let selected = (row as? UITableViewCell)?.isSelected ?? false
        let highlighted = (row as? UITableViewCell)?.isHighlighted ?? false
        let className = NSStringFromClass(type(of: row))
        let accessibility = [
            row.accessibilityLabel,
            row.accessibilityValue,
            row.accessibilityIdentifier
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        studifyOverlayLog(
            "Passive Spotify playback state probe reason=\(reason) class=\(className) selected=\(selected) highlighted=\(highlighted) title=\(track.title) artist=\(track.artist) labels=\(labels) ax=\(accessibility)"
        )
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "passive-state-probe",
            message: reason,
            className: className,
            data: [
                "selected": selected,
                "highlighted": highlighted,
                "title": track.title,
                "artist": track.artist,
                "labels": labels,
                "accessibility": accessibility
            ],
            throttleKey: "native-playback-state-\(className)-\(reason)",
            minInterval: 0.5,
            requireActive: false
        )
    }

    private func logPressPathProbe(hitView: UIView, row: UIView, track: StudifyFakeTrack, reason: String) {
        let now = Date()
        if let last = lastPressPathProbeAtByTrack[track], now.timeIntervalSince(last) < 0.75 {
            return
        }
        lastPressPathProbeAtByTrack[track] = now

        let hitClass = NSStringFromClass(type(of: hitView))
        let rowClass = NSStringFromClass(type(of: row))
        let nearestControl = nearestControlAncestor(startingAt: hitView)
        let labels = usefulTextValues(in: row, maxDepth: 5)
            .prefix(8)
            .joined(separator: " | ")
        let viewChain = viewAncestorChain(from: hitView, limit: 14).joined(separator: " > ")
        let hitResponderChain = responderChain(from: hitView, limit: 14).joined(separator: " > ")
        let rowResponderChain = responderChain(from: row, limit: 14).joined(separator: " > ")
        let gestureSummary = gestureRecognizerSummary(startingAt: hitView, limit: 8)
        let selectorSummary = selectorResponseSummary(startingAt: row, limit: 8)
        let slotSummary = objectSlotValueSummary(startingAt: row, limit: 8)
        let uriCandidates = uriCandidateSummary(from: slotSummary + selectorSummary)
        let controlSummary = nearestControl.map { control in
            "\(NSStringFromClass(type(of: control))) enabled=\(control.isEnabled) selected=\(control.isSelected) highlighted=\(control.isHighlighted) actions=\(controlActionSummary(control))"
        } ?? "none"

        studifyOverlayLog(
            "Passive press path probe reason=\(reason) title=\(track.title) artist=\(track.artist) hit=\(hitClass) row=\(rowClass) labels=\(labels) nearestControl=\(controlSummary) uriCandidates=\(uriCandidates.joined(separator: " || ")) viewChain=\(viewChain) responderChain=\(hitResponderChain) rowResponderChain=\(rowResponderChain) gestures=\(gestureSummary.joined(separator: " || ")) selectors=\(selectorSummary.joined(separator: " || ")) slots=\(slotSummary.joined(separator: " || "))"
        )
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "press-path",
            message: reason,
            className: rowClass,
            data: [
                "title": track.title,
                "artist": track.artist,
                "hitClass": hitClass,
                "rowClass": rowClass,
                "labels": labels,
                "nearestControl": controlSummary,
                "viewChain": viewChain,
                "responderChain": hitResponderChain,
                "rowResponderChain": rowResponderChain,
                "gestures": gestureSummary,
                "selectors": selectorSummary,
                "slots": slotSummary,
                "uriCandidates": uriCandidates
            ],
            throttleKey: "press-path-\(track.title)",
            minInterval: 0.75,
            requireActive: false
        )
    }

    private func logRowTapWithoutTrackProbe(hitView: UIView, row: UIView, window: UIWindow, point: CGPoint, reason: String) {
        let hitClass = NSStringFromClass(type(of: hitView))
        let rowClass = NSStringFromClass(type(of: row))
        let labels = usefulTextValues(in: row, maxDepth: 6)
            .prefix(10)
            .joined(separator: " | ")
        let slotSummary = objectSlotValueSummary(startingAt: row, limit: 10)
        let selectorSummary = selectorResponseSummary(startingAt: row, limit: 10)
        let uriCandidates = uriCandidateSummary(from: slotSummary + selectorSummary)
        let viewChain = viewAncestorChain(from: hitView, limit: 16).joined(separator: " > ")
        let responder = responderChain(from: hitView, limit: 16).joined(separator: " > ")

        studifyOverlayLog(
            "Probe row tap without track reason=\(reason) hit=\(hitClass) row=\(rowClass) point=\(format(Float(point.x))),\(format(Float(point.y))) labels=\(labels) uriCandidates=\(uriCandidates.joined(separator: " || ")) viewChain=\(viewChain) responderChain=\(responder) selectors=\(selectorSummary.joined(separator: " || ")) slots=\(slotSummary.joined(separator: " || "))"
        )
        StudifyProbeStreamClient.shared.emit(
            hook: "row-tap",
            phase: "without-track",
            message: reason,
            className: rowClass,
            data: [
                "hitClass": hitClass,
                "rowClass": rowClass,
                "point": ["x": point.x, "y": point.y],
                "labels": labels,
                "uriCandidates": uriCandidates,
                "viewChain": viewChain,
                "responderChain": responder,
                "selectors": selectorSummary,
                "slots": slotSummary
            ],
            throttleKey: "row-tap-without-track-\(rowClass)-\(labels)",
            minInterval: 0.25,
            requireActive: false
        )
    }

    private func logGenericTapProbe(hitView: UIView, window: UIWindow, point: CGPoint, reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastGenericTapProbeAt) > 0.2 else { return }
        lastGenericTapProbeAt = now

        let hitClass = NSStringFromClass(type(of: hitView))
        let text = usefulTextValues(in: hitView, maxDepth: 4)
            .prefix(8)
            .joined(separator: " | ")
        let viewChain = viewAncestorChain(from: hitView, limit: 16).joined(separator: " > ")
        let responder = responderChain(from: hitView, limit: 16).joined(separator: " > ")
        let nearestRow = nearestRowCandidate(startingAt: hitView, in: window)
        let nearestRowSummary = nearestRow.map { row -> [String: Any] in
            [
                "className": NSStringFromClass(type(of: row)),
                "text": usefulTextValues(in: row, maxDepth: 5).prefix(10).joined(separator: " | "),
                "selectors": selectorResponseSummary(startingAt: row, limit: 8),
                "slots": objectSlotValueSummary(startingAt: row, limit: 8)
            ]
        } ?? [:]

        studifyOverlayLog(
            "Probe generic tap reason=\(reason) hit=\(hitClass) point=\(format(Float(point.x))),\(format(Float(point.y))) text=\(text) nearestRow=\(nearestRowSummary) viewChain=\(viewChain) responderChain=\(responder)"
        )
        StudifyProbeStreamClient.shared.start(reason: "generic tap")
        StudifyProbeStreamClient.shared.emit(
            hook: "tap",
            phase: reason,
            message: hitClass,
            className: hitClass,
            data: [
                "point": ["x": point.x, "y": point.y],
                "text": text,
                "viewChain": viewChain,
                "responderChain": responder,
                "nearestRow": nearestRowSummary
            ],
            throttleKey: "generic-tap-\(hitClass)-\(text)",
            minInterval: 0.2,
            requireActive: false
        )
    }

    private func nearestRowCandidate(startingAt view: UIView, in window: UIWindow) -> UIView? {
        var current: UIView? = view
        var depth = 0

        while let candidate = current, depth < 16 {
            let rect = candidate.convert(candidate.bounds, to: window)
            let className = NSStringFromClass(type(of: candidate)).lowercased()
            let text = usefulTextValues(in: candidate, maxDepth: 5)
            let rowish = className.contains("cell")
                || className.contains("row")
                || className.contains("track")
                || className.contains("element")

            if rowish,
               rect.width >= 160,
               rect.height >= 24,
               rect.height <= 180,
               !text.isEmpty {
                return candidate
            }

            current = candidate.superview
            depth += 1
        }

        return nil
    }

    private func nearestControlAncestor(startingAt view: UIView) -> UIControl? {
        var current: UIView? = view
        var depth = 0
        while let candidate = current, depth < 12 {
            if let control = candidate as? UIControl {
                return control
            }
            current = candidate.superview
            depth += 1
        }
        return nil
    }

    private func viewAncestorChain(from view: UIView, limit: Int) -> [String] {
        var values: [String] = []
        var current: UIView? = view
        var depth = 0

        while let candidate = current, depth < limit {
            values.append(NSStringFromClass(type(of: candidate)))
            current = candidate.superview
            depth += 1
        }

        return values
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

    private func gestureRecognizerSummary(startingAt view: UIView, limit: Int) -> [String] {
        var summaries: [String] = []
        var current: UIView? = view
        var depth = 0

        while let candidate = current, depth < limit {
            let gestures = candidate.gestureRecognizers ?? []
            if !gestures.isEmpty {
                let gestureText = gestures.map { recognizer -> String in
                    let delegateName = recognizer.delegate.map { String(describing: type(of: $0)) } ?? "nil"
                    return "\(NSStringFromClass(type(of: recognizer))) state=\(recognizer.state.rawValue) enabled=\(recognizer.isEnabled) cancels=\(recognizer.cancelsTouchesInView) delaysBegan=\(recognizer.delaysTouchesBegan) delaysEnded=\(recognizer.delaysTouchesEnded) delegate=\(delegateName)"
                }.joined(separator: ", ")
                summaries.append("\(depth):\(NSStringFromClass(type(of: candidate))) gestures=[\(gestureText)]")
            }
            current = candidate.superview
            depth += 1
        }

        if summaries.isEmpty {
            return ["none"]
        }
        return summaries
    }

    private func selectorResponseSummary(startingAt view: UIView, limit: Int) -> [String] {
        let selectorNames = [
            "model",
            "viewModel",
            "item",
            "itemIdentifier",
            "identifier",
            "uri",
            "URI",
            "trackUri",
            "trackURI",
            "playState",
            "playbackState",
            "isPlaying",
            "isPlayable",
            "isDownloaded",
            "contentIsDownloaded",
            "isSelected",
            "isHighlighted",
            "accessibilityIdentifier",
            "accessibilityLabel",
            "trackRowEventHandler",
            "playRestrictionResolver",
            "listPlayer",
            "player",
            "delegate",
            "target",
            "action"
        ]

        var summaries: [String] = []
        var current: UIView? = view
        var depth = 0

        while let candidate = current, depth < limit {
            let object = candidate as NSObject
            let matches = selectorNames.filter { object.responds(to: Selector(($0))) }
            if !matches.isEmpty {
                summaries.append("\(depth):\(NSStringFromClass(type(of: candidate))) responds=[\(matches.joined(separator: ","))]")
            }
            current = candidate.superview
            depth += 1
        }

        if summaries.isEmpty {
            return ["none"]
        }
        return summaries
    }

    private func objectSlotValueSummary(startingAt view: UIView, limit: Int) -> [String] {
        let selectorNames = [
            "model",
            "viewModel",
            "item",
            "itemIdentifier",
            "identifier",
            "uri",
            "URI",
            "trackUri",
            "trackURI",
            "viewURI",
            "pageURI",
            "track",
            "currentTrack",
            "playState",
            "playbackState",
            "restriction",
            "playabilityRestriction",
            "playRestrictionResolver",
            "trackRowEventHandler",
            "listPlayer",
            "player",
            "delegate",
            "target"
        ]

        var summaries: [String] = []
        var current: UIView? = view
        var depth = 0

        while let candidate = current, depth < limit {
            let object = candidate as NSObject
            var values: [String] = []

            for selectorName in selectorNames {
                guard let value = performObjectSelector(selectorName, on: object) else {
                    continue
                }

                let described = describeSlotValue(value)
                guard !described.isEmpty else {
                    continue
                }

                values.append("\(selectorName)=\(described)")
            }

            if !values.isEmpty {
                summaries.append("\(depth):\(NSStringFromClass(type(of: candidate))){\(values.prefix(8).joined(separator: ","))}")
            }

            current = candidate.superview
            depth += 1
        }

        if summaries.isEmpty {
            return ["none"]
        }
        return summaries
    }

    private func uriCandidateSummary(from values: [String]) -> [String] {
        let joined = values.joined(separator: " ")
        let patterns = [
            #"spotify:track:[A-Za-z0-9]+"#,
            #"spotify:episode:[A-Za-z0-9]+"#,
            #"spotify:local:[^,\s\}\|]+"#,
            #"spotify:[A-Za-z]+:[^,\s\}\|]+"#
        ]

        var found: [String] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
            for match in expression.matches(in: joined, range: range) {
                guard let swiftRange = Range(match.range, in: joined) else {
                    continue
                }
                let value = String(joined[swiftRange])
                if !found.contains(value) {
                    found.append(value)
                }
            }
        }

        if found.isEmpty {
            return ["none"]
        }
        return Array(found.prefix(12))
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

    private func describeSlotValue(_ value: AnyObject) -> String {
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
            var pairs: [String] = []
            for (key, value) in dictionary {
                let keyString = cleanInline("\(key)")
                let valueString = cleanInline("\(value)")
                guard !keyString.isEmpty, !valueString.isEmpty else { continue }
                pairs.append("\(keyString):\(valueString)")
            }
            return "dict{\(pairs.prefix(6).joined(separator: "|"))}"
        }

        if let object = value as? NSObject {
            let className = NSStringFromClass(type(of: object))
            let trackSummary = trackLikeSummary(for: object)
            if !trackSummary.isEmpty {
                return "\(className){\(trackSummary)}"
            }
            return className
        }

        return cleanInline("\(value)")
    }

    private func trackLikeSummary(for object: NSObject) -> String {
        let title = firstReadableString(from: object, selectorNames: ["trackTitle", "title", "name"])
        let artist = firstReadableString(from: object, selectorNames: ["artistTitle", "artistName", "artist", "artistDisplayName"])
        let uri = firstReadableString(from: object, selectorNames: ["URI", "uri", "trackURI", "trackUri"])

        return [
            title.isEmpty ? nil : "title=\(title)",
            artist.isEmpty ? nil : "artist=\(artist)",
            uri.isEmpty ? nil : "uri=\(uri)"
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    private func firstReadableString(from object: NSObject, selectorNames: [String]) -> String {
        for selectorName in selectorNames {
            guard let value = performObjectSelector(selectorName, on: object) else {
                continue
            }

            let string = describeSlotValue(value)
            if !string.isEmpty {
                return string
            }
        }

        return ""
    }

    private func cleanInline(_ value: String) -> String {
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

    private func controlActionSummary(_ control: UIControl) -> String {
        var values: [String] = []
        let events: [(UIControl.Event, String)] = [
            (.touchDown, "touchDown"),
            (.touchUpInside, "touchUpInside"),
            (.touchUpOutside, "touchUpOutside"),
            (.touchCancel, "touchCancel"),
            (.primaryActionTriggered, "primaryActionTriggered"),
            (.valueChanged, "valueChanged")
        ]

        for targetObject in control.allTargets {
            let targetName = String(describing: type(of: targetObject))
            for (event, eventName) in events {
                guard let actions = control.actions(forTarget: targetObject, forControlEvent: event),
                      !actions.isEmpty
                else {
                    continue
                }
                values.append("\(eventName):\(targetName).\(actions.joined(separator: ","))")
            }
        }

        if values.isEmpty {
            return "none"
        }
        return values.prefix(8).joined(separator: " | ")
    }

    private func snapshotTree(from root: UIView, rootName: String) -> ViewSnapshot {
        var entries: [(key: String, value: String)] = []
        collectSnapshotEntries(
            from: root,
            root: root,
            path: rootName,
            depth: 0,
            maxDepth: 8,
            maxNodes: 90,
            entries: &entries
        )
        return ViewSnapshot(entries: entries)
    }

    private func snapshotBottomArea(in window: UIWindow, rootName: String) -> ViewSnapshot {
        let bottomInset = max(window.safeAreaInsets.bottom, 0)
        let minY = window.bounds.height - bottomInset - 220
        var entries: [(key: String, value: String)] = []
        collectSnapshotEntries(
            from: window,
            root: window,
            path: rootName,
            depth: 0,
            maxDepth: 7,
            maxNodes: 120,
            entries: &entries,
            include: { view in
                let rect = view.convert(view.bounds, to: window)
                return rect.maxY >= minY && rect.minY <= window.bounds.height
            }
        )
        return ViewSnapshot(entries: entries)
    }

    private func collectSnapshotEntries(
        from view: UIView,
        root: UIView,
        path: String,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        entries: inout [(key: String, value: String)],
        include: ((UIView) -> Bool)? = nil
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

        entries.append((key: path, value: describeSnapshot(view: view, root: root, depth: depth)))

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

    private func describeSnapshot(view: UIView, root: UIView, depth: Int) -> String {
        let className = NSStringFromClass(type(of: view))
        let frame = view.convert(view.bounds, to: root)
        var parts: [String] = [
            "d=\(depth)",
            "class=\(className)",
            "frame=\(format(rect: frame))",
            "hidden=\(view.isHidden)",
            "alpha=\(format(view.alpha))",
            "user=\(view.isUserInteractionEnabled)"
        ]

        if let label = view as? UILabel {
            parts.append("text=\(cleanSnapshot(label.text))")
            parts.append("textColor=\(describe(color: label.textColor))")
            parts.append("font=\(format(label.font.pointSize))")
            parts.append("enabled=\(label.isEnabled)")
        }

        if let button = view as? UIButton {
            parts.append("buttonTitle=\(cleanSnapshot(button.currentTitle))")
            parts.append("buttonSelected=\(button.isSelected)")
            parts.append("buttonHighlighted=\(button.isHighlighted)")
            parts.append("buttonEnabled=\(button.isEnabled)")
        }

        if let control = view as? UIControl {
            parts.append("controlEnabled=\(control.isEnabled)")
            parts.append("controlSelected=\(control.isSelected)")
            parts.append("controlHighlighted=\(control.isHighlighted)")
        }

        if let cell = view as? UITableViewCell {
            parts.append("cellSelected=\(cell.isSelected)")
            parts.append("cellHighlighted=\(cell.isHighlighted)")
        }

        if let imageView = view as? UIImageView {
            parts.append("image=\(imageView.image == nil ? "nil" : "set")")
            parts.append("highlightedImage=\(imageView.highlightedImage == nil ? "nil" : "set")")
            parts.append("imageHighlighted=\(imageView.isHighlighted)")
        }

        if let progressView = view as? UIProgressView {
            parts.append("progress=\(format(progressView.progress))")
        }

        parts.append("tint=\(describe(color: view.tintColor))")
        if let backgroundColor = view.backgroundColor {
            parts.append("bg=\(describe(color: backgroundColor))")
        }
        if view.layer.borderWidth > 0 {
            parts.append("borderWidth=\(format(Float(view.layer.borderWidth)))")
        }

        let accessibility = [
            view.accessibilityLabel.map { "axLabel=\(cleanSnapshot($0))" },
            view.accessibilityValue.map { "axValue=\(cleanSnapshot($0))" },
            view.accessibilityIdentifier.map { "axId=\(cleanSnapshot($0))" }
        ].compactMap { $0 }
        parts.append(contentsOf: accessibility)
        if view.accessibilityTraits.rawValue != 0 {
            parts.append("axTraits=\(view.accessibilityTraits.rawValue)")
        }

        return parts.joined(separator: " ")
    }

    private func logSnapshot(_ snapshot: ViewSnapshot, reason: String, track: StudifyFakeTrack, maxLines: Int) {
        let visibleLines = snapshot.entries.prefix(maxLines).map { "\($0.key) \($0.value)" }
        studifyOverlayLog(
            "Deep Spotify row probe reason=\(reason) title=\(track.title) lines=\(snapshot.entries.count)\n\(visibleLines.joined(separator: "\n"))"
        )
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "deep-snapshot",
            message: reason,
            data: [
                "title": track.title,
                "artist": track.artist,
                "lineCount": snapshot.entries.count,
                "lines": Array(visibleLines)
            ],
            throttleKey: "deep-snapshot-\(reason)-\(track.title)",
            minInterval: 0.5,
            requireActive: false
        )
    }

    private func logSnapshotDiff(before: ViewSnapshot, after: ViewSnapshot, reason: String, track: StudifyFakeTrack) {
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

            if changes.count >= 30 {
                break
            }
        }

        let summary = changes.isEmpty ? "no-view-property-changes" : changes.joined(separator: "\n")
        studifyOverlayLog("Deep Spotify row diff reason=\(reason) title=\(track.title) changes=\(changes.count)\n\(summary)")
        StudifyProbeStreamClient.shared.emit(
            hook: "native-playback",
            phase: "deep-diff",
            message: reason,
            data: [
                "title": track.title,
                "artist": track.artist,
                "changeCount": changes.count,
                "changes": changes
            ],
            throttleKey: "deep-diff-\(reason)-\(track.title)",
            minInterval: 0.5,
            requireActive: false
        )
    }

    private func cleanSnapshot(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > 90 {
            return "\(cleaned.prefix(90))..."
        }
        return cleaned
    }

    private func format(rect: CGRect) -> String {
        "[\(format(Float(rect.minX))),\(format(Float(rect.minY))),\(format(Float(rect.width))),\(format(Float(rect.height)))]"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
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

    @discardableResult
    private func enableNativeInteraction(in root: UIView) -> Int {
        var mutations = 0
        root.isUserInteractionEnabled = true
        if root.alpha < 1 {
            root.alpha = 1
            mutations += 1
        }

        if let control = root as? UIControl {
            if !control.isEnabled {
                control.isEnabled = true
                mutations += 1
            }
        }

        if let label = root as? UILabel {
            if normalizeOfflineLabel(label) {
                mutations += 1
            }
        } else if normalizeSpotifyTextLikeView(root) {
            mutations += 1
        }

        if let imageView = root as? UIImageView {
            if imageView.alpha < 1 {
                imageView.alpha = 1
                mutations += 1
            }
            let tint = imageView.tintColor ?? .white
            if tint.cgColor.alpha < 1 {
                imageView.tintColor = tint.withAlphaComponent(1)
                mutations += 1
            }
        }

        for subview in root.subviews {
            mutations += enableNativeInteraction(in: subview)
        }

        return mutations
    }

    @discardableResult
    private func normalizeOfflineLabel(_ label: UILabel) -> Bool {
        var didMutate = false

        if !label.isEnabled {
            didMutate = true
        }
        label.isEnabled = true

        if label.alpha < 1 {
            didMutate = true
        }
        label.alpha = 1

        guard let text = label.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              !isIgnoredText(text) else {
            return didMutate
        }

        let currentColor = label.textColor ?? .white
        guard currentColor.cgColor.alpha < 0.85 || isVisiblyDimmed(currentColor) else {
            return didMutate
        }

        let fontSize = label.font.pointSize
        let replacementColor: UIColor = fontSize >= 15 ? .white : UIColor(white: 0.72, alpha: 1)
        label.textColor = replacementColor
        didMutate = true

        if let attributedText = label.attributedText, attributedText.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: attributedText)
            mutable.addAttribute(.foregroundColor, value: replacementColor, range: NSRange(location: 0, length: mutable.length))
            label.attributedText = mutable
        }

        return didMutate
    }

    @discardableResult
    private func normalizeSpotifyTextLikeView(_ view: UIView) -> Bool {
        let className = NSStringFromClass(type(of: view)).lowercased()
        guard className.contains("label")
            || className.contains("text")
            || className.contains("encore")
        else {
            return false
        }

        var didMutate = false

        if view.alpha < 1 {
            view.alpha = 1
            didMutate = true
        }

        let replacementColor = UIColor.white
        let colorSelectors = [
            "setTextColor:",
            "setForegroundColor:",
            "setTitleColor:",
            "setTintColor:"
        ]

        for selectorName in colorSelectors {
            let selector = Selector((selectorName))
            if view.responds(to: selector) {
                view.perform(selector, with: replacementColor)
                didMutate = true
            }
        }

        if view.tintColor.cgColor.alpha < 1 || isVisiblyDimmed(view.tintColor) {
            view.tintColor = replacementColor
            didMutate = true
        }

        if let firstLabel = view.subviews.first(where: { $0 is UILabel }) as? UILabel,
           normalizeOfflineLabel(firstLabel) {
            didMutate = true
        }

        return didMutate
    }

    private func isVisiblyDimmed(_ color: UIColor) -> Bool {
        var white: CGFloat = 0
        var alpha: CGFloat = 1
        if color.getWhite(&white, alpha: &alpha) {
            return alpha < 0.85 || white < 0.55
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            return alpha < 0.85 || luminance < 0.45
        }

        return alpha < 0.85
    }

    private func usefulTextValues(in view: UIView, maxDepth: Int) -> [String] {
        var seen = Set<String>()
        return textValues(in: view, maxDepth: maxDepth).compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !isIgnoredText(value), !seen.contains(value) else {
                return nil
            }
            seen.insert(value)
            return value
        }
    }

    private func textValues(in view: UIView, maxDepth: Int, depth: Int = 0) -> [String] {
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

        for subview in view.subviews {
            values.append(contentsOf: textValues(in: subview, maxDepth: maxDepth, depth: depth + 1))
        }

        return values
    }

    private func collectLabels(in view: UIView, into labels: inout [UILabel], maxDepth: Int, depth: Int = 0) {
        guard depth <= maxDepth else { return }
        if let label = view as? UILabel {
            labels.append(label)
        }
        for subview in view.subviews {
            collectLabels(in: subview, into: &labels, maxDepth: maxDepth, depth: depth + 1)
        }
    }

    private func views(in root: UIView, maxDepth: Int = 8, depth: Int = 0) -> [UIView] {
        guard depth <= maxDepth else { return [] }
        return [root] + root.subviews.flatMap { views(in: $0, maxDepth: maxDepth, depth: depth + 1) }
    }

    private func labels(in root: UIView) -> [UILabel] {
        var labels: [UILabel] = []
        collectLabels(in: root, into: &labels, maxDepth: 8)
        return labels
    }

    private func isSpotifyOfflineModeActive(in root: UIView) -> Bool {
        let joined = offlineSignalText(in: root, maxDepth: 12)
            .joined(separator: " ")
            .lowercased()

        let strongSignals = [
            "go online",
            "you're offline",
            "you’re offline",
            "no internet connection",
            "no connection",
            "offline mode",
            "spotify is offline"
        ]

        return strongSignals.contains { joined.contains($0) }
    }

    private func offlineSignalText(in view: UIView, maxDepth: Int, depth: Int = 0) -> [String] {
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
            values.append(contentsOf: offlineSignalText(in: subview, maxDepth: maxDepth, depth: depth + 1))
        }
        return values
    }

    private func playbackIntent(from control: UIControl, actionName: String) -> PlaybackIntent? {
        let values = controlContextValues(from: control)
        let joined = ([actionName] + values).joined(separator: " ").lowercased()
        let exactValues = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        if exactValues.contains(where: { ["next", "skip", "skip forward", "skip to next"].contains($0) })
            || joined.contains("skip to next")
            || joined.contains("skip forward")
            || containsWord(joined, "next") {
            return .next
        }

        if exactValues.contains(where: { ["previous", "prev", "skip back", "skip backward"].contains($0) })
            || joined.contains("skip back")
            || joined.contains("skip backward")
            || containsWord(joined, "previous")
            || containsWord(joined, "prev") {
            return .previous
        }

        if exactValues.contains(where: { ["play", "pause", "play/pause"].contains($0) })
            || joined.contains("playpause")
            || joined.contains("play/pause")
            || containsWord(joined, "pause")
            || containsWord(joined, "play") {
            return .toggle
        }

        return nil
    }

    private func controlContextValues(from control: UIControl) -> [String] {
        var values = textValues(in: control, maxDepth: 3)
        var superview = control.superview
        var depth = 0

        while let view = superview, depth < 3 {
            values.append(contentsOf: textValues(in: view, maxDepth: 2))
            superview = view.superview
            depth += 1
        }

        return Array(Set(values))
    }

    private func containsWord(_ text: String, _ word: String) -> Bool {
        text.range(
            of: "(^|[^a-z])\(NSRegularExpression.escapedPattern(for: word))([^a-z]|$)",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func isMiniPlayerIgnoredText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let ignored: Set<String> = [
            "home",
            "search",
            "your library",
            "create",
            "playlists",
            "play",
            "pause",
            "next",
            "prev",
            "previous"
        ]

        return ignored.contains(lower)
            || lower.contains("studify")
            || lower.contains("open the context menu")
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

        if exactIgnored.contains(lower) {
            return true
        }

        if lower.hasSuffix("min") && lower.allSatisfy({ $0.isNumber || $0 == "m" || $0 == "i" || $0 == "n" }) {
            return true
        }

        return lower.contains("studify overlay")
            || lower.contains("studify fake")
            || lower.contains("ui simulation")
            || lower.contains("download")
            || lower.contains("offline")
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
}
