import Foundation
import UIKit
import Vision

struct OCRTextObservation {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

struct OCRTextLine {
    let text: String
    let observations: [OCRTextObservation]
    let yMidpoint: CGFloat
}

struct OCRResult {
    let fullText: String
    let observations: [OCRTextObservation]
    let lines: [OCRTextLine]
}

protocol OCRServiceProtocol: AnyObject {
    func recognizeText(from image: UIImage) async throws -> String
    func recognizeTextWithDetails(from image: UIImage) async throws -> OCRResult
}

// MARK: - Mock OCR Service

final class MockOCRService: OCRServiceProtocol {

    static let shared = MockOCRService()

    private init() {}

    func recognizeText(from image: UIImage) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Return mock recognized text
        return """
        商品名称: iPhone 15 Pro Max
        交易金额: ¥9999.00
        交易日期: 2024-01-15
        交易平台: 京东商城
        """
    }

    func recognizeTextWithDetails(from image: UIImage) async throws -> OCRResult {
        let text = try await recognizeText(from: image)
        let lines = text.components(separatedBy: "\n").enumerated().map { index, line in
            let obs = OCRTextObservation(text: line, confidence: 0.95, boundingBox: .zero)
            return OCRTextLine(text: line, observations: [obs], yMidpoint: CGFloat(index) * 30)
        }
        let observations = lines.flatMap { $0.observations }
        return OCRResult(fullText: text, observations: observations, lines: lines)
    }
}

// MARK: - Production OCR Service (Placeholder)

final class ProductionOCRService: OCRServiceProtocol {

    static let shared = ProductionOCRService()

    private init() {}

    func recognizeText(from image: UIImage) async throws -> String {
        let result = try await recognizeTextWithDetails(from: image)
        return result.fullText
    }

    func recognizeTextWithDetails(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if error != nil {
                    continuation.resume(throwing: OCRError.recognitionFailed)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRError.recognitionFailed)
                    return
                }

                let ocrObservations: [OCRTextObservation] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    return OCRTextObservation(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: obs.boundingBox
                    )
                }

                if ocrObservations.isEmpty {
                    continuation.resume(throwing: OCRError.recognitionFailed)
                    return
                }

                // Cluster observations into lines by Y coordinate
                let sorted = ocrObservations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                var lines: [OCRTextLine] = []
                var currentLine: [OCRTextObservation] = [sorted[0]]

                for obs in sorted.dropFirst() {
                    let lastMidY = currentLine.last!.boundingBox.midY
                    let avgHeight = (currentLine.reduce(0.0) { $0 + $1.boundingBox.height } / CGFloat(currentLine.count))
                    let lineThreshold = max(0.012, min(0.03, avgHeight * 0.8))
                    // Dynamic Y threshold similar to AChai's line setup; more robust for long screenshots.
                    if abs(obs.boundingBox.midY - lastMidY) < lineThreshold {
                        currentLine.append(obs)
                    } else {
                        // Sort current line by X (left to right) and commit
                        let sortedLine = currentLine.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
                        let lineText = mergeLineText(from: sortedLine)
                        let avgY = sortedLine.reduce(0.0) { $0 + $1.boundingBox.midY } / CGFloat(sortedLine.count)
                        lines.append(OCRTextLine(text: lineText, observations: sortedLine, yMidpoint: avgY))
                        currentLine = [obs]
                    }
                }
                // Commit last line
                let sortedLine = currentLine.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
                let lineText = mergeLineText(from: sortedLine)
                let avgY = sortedLine.reduce(0.0) { $0 + $1.boundingBox.midY } / CGFloat(sortedLine.count)
                lines.append(OCRTextLine(text: lineText, observations: sortedLine, yMidpoint: avgY))

                let fullText = lines.map { $0.text }.joined(separator: "\n")
                continuation.resume(returning: OCRResult(fullText: fullText, observations: ocrObservations, lines: lines))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.recognitionFailed)
                }
            }
        }
    }
}

private func mergeLineText(from observations: [OCRTextObservation]) -> String {
    guard !observations.isEmpty else { return "" }

    var merged = observations[0].text.trimmingCharacters(in: .whitespacesAndNewlines)
    for obs in observations.dropFirst() {
        let current = obs.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty { continue }
        let shouldInsertSpace = shouldInsertLineSpace(previous: merged, next: current)
        merged += shouldInsertSpace ? " \(current)" : current
    }
    return merged
}

private func shouldInsertLineSpace(previous: String, next: String) -> Bool {
    guard let prevScalar = previous.unicodeScalars.last,
          let nextScalar = next.unicodeScalars.first else {
        return true
    }

    let alphaNum = CharacterSet.alphanumerics
    if alphaNum.contains(prevScalar) && alphaNum.contains(nextScalar) {
        return true
    }
    return false
}

enum OCRError: LocalizedError {
    case serviceUnavailable
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "OCR服务暂时不可用"
        case .invalidImage:
            return "无法识别该图片"
        case .recognitionFailed:
            return "文字识别失败"
        }
    }
}
