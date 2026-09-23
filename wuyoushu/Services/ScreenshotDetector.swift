import Foundation
import Photos
import UIKit

final class ScreenshotDetector {
    static let shared = ScreenshotDetector()

    private let lastBackgroundKey = "lastBackgroundTimestamp"
    private let enabledKey = "screenshotDetectionEnabled"

    private init() {}

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Call when app enters background
    func recordBackgroundTime() {
        UserDefaults.standard.set(Date(), forKey: lastBackgroundKey)
    }

    /// Check for new screenshots taken while app was in background.
    /// Returns the latest screenshot image if found, nil otherwise.
    func checkForNewScreenshot() async -> UIImage? {
        guard isEnabled else { return nil }

        let status = PHPhotoLibrary.authorizationStatus()
        guard status == .authorized || status == .limited else { return nil }

        guard let lastTime = UserDefaults.standard.object(forKey: lastBackgroundKey) as? Date else {
            return nil
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate > %@ AND mediaSubtype & %d != 0",
            lastTime as NSDate,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = assets.firstObject else { return nil }

        return await loadImage(from: asset)
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    private func loadImage(from asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            let targetSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .default,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
