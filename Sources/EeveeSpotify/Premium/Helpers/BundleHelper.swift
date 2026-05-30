import Foundation
import MachO
import SwiftUI
import libroot

class BundleHelper {
    private let bundleName = "EeveeSpotify"
    
    // Make properties optional to prevent init crash
    private var bundle: Bundle?
    private var enBundle: Bundle?
    
    static let shared = BundleHelper()
    
    private init() {
        // Try locating in main bundle first
        if let path = Bundle.main.path(forResource: bundleName, ofType: "bundle"),
           let b = Bundle(path: path) {
            self.bundle = b
            NSLog("[EeveeSpotify] Loaded bundle from main bundle: \(path)")
        } 
        // If not found, try locating in file system (jailbreak path)
        else {
            let jbPath = jbRootPath("/Library/Application Support/\(bundleName).bundle")
            if let b = Bundle(path: jbPath) {
                self.bundle = b
                NSLog("[EeveeSpotify] Loaded bundle from filesystem: \(jbPath)")
            } else if let liveContainerPath = Self.liveContainerBundlePath(bundleName: bundleName),
                      let b = Bundle(path: liveContainerPath) {
                self.bundle = b
                NSLog("[EeveeSpotify] Loaded bundle from LiveContainer tweak folder: \(liveContainerPath)")
            } else {
                NSLog("[EeveeSpotify] ERROR: Could not find EeveeSpotify.bundle!")
                self.bundle = nil
            }
        }
        
        // Load English localization if available
        if let b = self.bundle, let enPath = b.path(forResource: "en", ofType: "lproj"),
           let enB = Bundle(path: enPath) {
            self.enBundle = enB
        } else {
            NSLog("[EeveeSpotify] WARNING: Could not load en.lproj from bundle")
            self.enBundle = nil
        }
    }
    
    func uiImage(_ name: String) -> UIImage? {
        guard let bundle = self.bundle else { return nil }
        
        if let path = bundle.path(forResource: name, ofType: "png") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }
    
    func localizedString(_ key: String) -> String {
        guard let bundle = self.bundle else { return key }

        let value = bundle.localizedString(forKey: key, value: "No translation", table: nil)
        
        if value != "No translation" {
            return value
        }
        
        return enBundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
    }
    
    func resolveConfiguration() throws -> ResolveConfiguration {
        guard let bundle = self.bundle,
              let url = bundle.url(forResource: "resolveconfiguration", withExtension: "bnk") else {
            throw NSError(domain: "EeveeSpotify", code: 404, userInfo: [NSLocalizedDescriptionKey: "Configuration not found"])
        }
        
        return try ResolveConfiguration(
            serializedBytes: try Data(contentsOf: url)
        )
    }

    private static func liveContainerBundlePath(bundleName: String) -> String? {
        for imageIndex in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(imageIndex) else {
                continue
            }

            let imagePath = String(cString: imageName)
            guard imagePath.hasSuffix("/EeveeSpotify.dylib")
                || imagePath.contains("/EeveeSpotify.framework/")
            else {
                continue
            }

            let imageDirectory = URL(fileURLWithPath: imagePath).deletingLastPathComponent()
            let candidates = [
                imageDirectory.appendingPathComponent("\(bundleName).bundle").path,
                imageDirectory.deletingLastPathComponent().appendingPathComponent("\(bundleName).bundle").path
            ]

            if let path = candidates.first(where: FileManager.default.fileExists(atPath:)) {
                return path
            }
        }

        return nil
    }
}
