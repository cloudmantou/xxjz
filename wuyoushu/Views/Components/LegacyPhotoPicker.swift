import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LegacyPhotoPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onImageData: (Data?) -> Void

    init(selectionLimit: Int = 1, onImageData: @escaping (Data?) -> Void) {
        self.selectionLimit = selectionLimit
        self.onImageData = onImageData
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageData: onImageData)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImageData: (Data?) -> Void

        init(onImageData: @escaping (Data?) -> Void) {
            self.onImageData = onImageData
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                DispatchQueue.main.async {
                    self.onImageData(nil)
                }
                return
            }

            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                DispatchQueue.main.async {
                    self.onImageData(nil)
                }
                return
            }

            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                DispatchQueue.main.async {
                    self.onImageData(data)
                }
            }
        }
    }
}
