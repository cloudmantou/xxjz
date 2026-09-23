import UIKit
import UniformTypeIdentifiers
import Social

class ShareViewController: UIViewController {

    private let suiteName = "group.com.assetlife.shortcuts"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        extractAndProcessImage()
    }

    private func extractAndProcessImage() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            closeWithError()
            return
        }

        let imageType = UTType.image.identifier
        guard itemProvider.hasItemConformingToTypeIdentifier(imageType) else {
            closeWithError()
            return
        }

        itemProvider.loadItem(forTypeIdentifier: imageType, options: nil) { [weak self] item, error in
            guard let self, error == nil else {
                self?.closeWithError()
                return
            }

            var imageData: Data?

            if let url = item as? URL {
                imageData = try? Data(contentsOf: url)
            } else if let data = item as? Data {
                imageData = data
            } else if let image = item as? UIImage {
                imageData = image.pngData()
            }

            guard let data = imageData, !data.isEmpty else {
                self.closeWithError()
                return
            }

            self.persistAndOpenMainApp(imageData: data)
        }
    }

    private func persistAndOpenMainApp(imageData: Data) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suiteName
        ) else {
            closeWithError()
            return
        }

        let fileName = "share-capture-\(UUID().uuidString).png"
        let fileURL = containerURL.appendingPathComponent(fileName)

        do {
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            closeWithError()
            return
        }

        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(fileURL.path, forKey: "pendingRecordImagePath")
        defaults?.set("addRecord", forKey: "pendingShortcutAction")
        defaults?.synchronize()

        let scheme = URL(string: "assetlife://record")!
        openURL(scheme) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: [])
        }
    }

    private func openURL(_ url: URL, completionHandler: @escaping (Bool) -> Void) {
        var responder: UIResponder? = self as UIResponder
        let selector = NSSelectorFromString("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                completionHandler(true)
                return
            }
            responder = r.next
        }
        completionHandler(false)
    }

    private func closeWithError() {
        extensionContext?.completeRequest(returningItems: [])
    }
}
