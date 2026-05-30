import AVFoundation
import UIKit

final class StudifyLocalAudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = StudifyLocalAudioPlayer()

    private let relativeAudioPath = "StudifyLibrary/audio/test.mp3"
    private let fallbackRelativeAudioPath = "test.mp3"
    private let showSuccessBanners = false
    private var player: AVAudioPlayer?
    private var lastLoadedURL: URL?

    private override init() {
        super.init()
    }

    var displayPath: String {
        "Documents/\(relativeAudioPath)"
    }

    var fallbackDisplayPath: String {
        "Documents/\(fallbackRelativeAudioPath)"
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    var progress: Float {
        guard let player, player.duration > 0 else { return 0 }
        return Float(max(0, min(1, player.currentTime / player.duration)))
    }

    func prepareLibraryFolder() {
        studifyOverlayLog("Studify audio home=\(NSHomeDirectory()) documents=\(documentsURL().path)")

        do {
            try FileManager.default.createDirectory(
                at: audioDirectoryURL(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            fail("Could not create StudifyLibrary/audio: \(error.localizedDescription)")
            return
        }

        if resolvedAudioFileURL() != nil {
            studifyOverlayLog("Studify local audio ready at \(resolvedAudioFileURL()?.path ?? displayPath)")
            showSuccessBanner(
                title: "STUDIFY AUDIO READY",
                detail: displayPath,
                color: UIColor(red: 0.10, green: 0.50, blue: 0.24, alpha: 0.96),
                duration: 4
            )
        } else {
            studifyOverlayLog("Studify local audio missing: \(missingDetail())")
            StudifyOverlayBanner.show(
                title: "STUDIFY AUDIO MISSING",
                detail: missingDetail(),
                color: UIColor(red: 0.78, green: 0.12, blue: 0.16, alpha: 0.96),
                duration: 8
            )
        }
    }

    @discardableResult
    func playTestMP3(restart: Bool = true) -> Bool {
        guard let audioURL = resolvedAudioFileURL() else {
            fail("Missing \(displayPath) or \(fallbackDisplayPath)")
            return false
        }

        do {
            try configureAudioSession()

            if player == nil || lastLoadedURL != audioURL {
                let nextPlayer = try AVAudioPlayer(contentsOf: audioURL)
                nextPlayer.delegate = self
                nextPlayer.prepareToPlay()
                player = nextPlayer
                lastLoadedURL = audioURL
            }

            if restart {
                player?.currentTime = 0
            }

            guard player?.play() == true else {
                fail("AVAudioPlayer.play() returned false")
                return false
            }

            studifyOverlayLog("Studify local audio playing \(audioURL.path)")
            showSuccessBanner(
                title: "STUDIFY AUDIO PLAYING",
                detail: audioURL.lastPathComponent,
                color: UIColor(red: 0.10, green: 0.55, blue: 0.25, alpha: 0.96),
                duration: 3
            )
            return true
        } catch {
            fail(error.localizedDescription)
            return false
        }
    }

    func pause() {
        player?.pause()
        studifyOverlayLog("Studify local audio paused")
    }

    @discardableResult
    func resumeOrRestart() -> Bool {
        guard let player else {
            return playTestMP3(restart: false)
        }

        if player.currentTime >= player.duration {
            player.currentTime = 0
        }

        do {
            try configureAudioSession()
        } catch {
            fail(error.localizedDescription)
            return false
        }

        guard player.play() else {
            fail("AVAudioPlayer.play() returned false")
            return false
        }

        studifyOverlayLog("Studify local audio resumed")
        return true
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        studifyOverlayLog("Studify local audio stopped")
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        studifyOverlayLog("Studify local audio finished successfully=\(flag)")
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        fail(error?.localizedDescription ?? "Decode error")
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    private func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func audioDirectoryURL() -> URL {
        documentsURL()
            .appendingPathComponent("StudifyLibrary", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
    }

    private func audioFileURL() -> URL {
        audioDirectoryURL().appendingPathComponent("test.mp3", isDirectory: false)
    }

    private func fallbackAudioFileURL() -> URL {
        documentsURL().appendingPathComponent("test.mp3", isDirectory: false)
    }

    private func resolvedAudioFileURL() -> URL? {
        let preferred = audioFileURL()
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }

        let fallback = fallbackAudioFileURL()
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }

        return nil
    }

    private func missingDetail() -> String {
        let documentsPath = documentsURL().path
        return "Docs: \(documentsPath) | need StudifyLibrary/audio/test.mp3 or test.mp3"
    }

    private func showSuccessBanner(title: String, detail: String, color: UIColor, duration: TimeInterval) {
        guard showSuccessBanners else { return }
        StudifyOverlayBanner.show(title: title, detail: detail, color: color, duration: duration)
    }

    private func fail(_ message: String) {
        studifyOverlayLog("Studify local audio failed: \(message)")
        StudifyOverlayBanner.show(
            title: message.contains("Missing") ? "STUDIFY AUDIO MISSING" : "STUDIFY AUDIO FAILED",
            detail: message.contains("Missing") ? missingDetail() : "\(message) | Docs: \(documentsURL().path)",
            color: UIColor(red: 0.78, green: 0.12, blue: 0.16, alpha: 0.96),
            duration: 7
        )
    }
}
